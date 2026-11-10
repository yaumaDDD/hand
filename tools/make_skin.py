#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Make the skin of the bare fingers that the fingerless gloves are drawn with.

    python tools/make_skin.py <extracted_root> [--skin hands2.zip] [--hands hands.zip] [--out DIR] [--preview DIR]

The fingers are inside the glove models (see patch_models.py), their skin is not. It is put
together from two archives:

    materials/zcity_csgo_gloves/skin/fingers.vmt
                                     fingers_color.vtf   bare_arm_135 of hands2.zip, as it is
                                     fingers_normal.vtf  v_model_base_arms of hands.zip, shine repaired
                                     fingers_exp.vtf     v_model_base_arms of hands.zip, unchanged

bare_arm_135 is a bare arm of the kind the glove models were made for (they name bare_arm_133,
of the same folder): clean skin all over, in the very texture layout of the fingers. Only its
colour texture is there; the normal and exponent maps its material names are not. Those come
from v_model_base_arms, the arm material of the first CS:GO versions, which has the same layout
and the same hand painted on it.

That older material was painted for one glove only: everything that glove covers - the hand up
to the middle of the fingers - is darkened in its colour texture and has no shine at all (alpha
of its normal map), as if it were in the shadow of the glove. The colour texture is therefore no
longer used (up to 1.2.0 it was, with the darkening taken out of the fingers again); it is only
looked at, because the dark zone shows where the shine is missing. The other fingerless gloves
are shorter there, the hand wraps leave the whole thumb free, and they would show dull fingers
next to shiny ones. So the shine is put back wherever a finger of any glove model uses the
texture. The skin that shows through the cut-out on the back of the "Fingerless" glove keeps
the shine it was painted with.

How: the zone is found as the dark part of the (blurred) old colour texture. For every finger
the profile across the edge of that zone is measured - how much duller, where exactly, how
soft - and the same edge is put on again the other way round. Around the fingers a margin of a
few pixels continues their values, because texture filtering reads there. Nothing else is
touched, and the normal map is not compressed again as a whole: only the 4x4 blocks in which
something changes are replaced, in every mip level, so that the rest keeps the quality it came
with (the tool stops if anything outside the fingers differs afterwards).

<extracted_root> has one sub-folder per source archive (build_addon.py --keep-temp leaves such
a tree in build/_extract). Needs numpy and pillow. The result is committed, so building the
addon does not need this script.
"""
import argparse
import math
import os
import sys
import zipfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_vmts  # noqa: E402
import mdl_lite  # noqa: E402
import patch_models  # noqa: E402
import render_previews as R  # noqa: E402
import vmt  # noqa: E402
import vtflib  # noqa: E402
import zcg_layout as L  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))

SOURCE = 'v_model_base_arms'  # .vmt, _color.vtf, _normal.vtf, _exp.vtf inside hands.zip
COLOR = 'bare_arm_135'        # .vtf inside hands2.zip: the colour texture that is shipped
SKIN_DIR, SKIN_NAME = L.FINGER_MATERIAL.rsplit('/', 1)  # folder below materials/, name of the material
# texture of the source material -> ours
TEXTURES = {SOURCE + '_color': SKIN_NAME + '_color', SOURCE + '_normal': SKIN_NAME + '_normal',
            SOURCE + '_exp': SKIN_NAME + '_exp'}
# reflections need an envmap mask in the alpha channel of the colour texture, which is dropped here
DROP_KEYS = {'$envmap', '$envmaptint', '$basealphaenvmapmask'}

LUMA = np.array([0.299, 0.587, 0.114])
ZONE_BLUR = 5.0     # the shadow is found on a blurred picture: wrinkles and hair must not count
DIST_BLUR = 6.0     # blur used to measure distances from the edge of the zone
FIT_RANGE = 12      # pixels on both sides of that edge that are looked at
MARGIN = 8          # pixels around the fingers that get their values (texture filtering reads there)

_PHI_X = np.linspace(-6.0, 6.0, 2401)
_PHI = np.array([0.5 * (1.0 + math.erf(x / math.sqrt(2.0))) for x in _PHI_X])


def phi(x):
    """normal distribution function: 0 far below zero, 1 far above. A sharp edge blurred with a
    gaussian of size s looks like phi(distance / s)"""
    return np.interp(x, _PHI_X, _PHI)


# ----------------------------------------------------------------------------------------------
# small image helpers (numpy only)
# ----------------------------------------------------------------------------------------------
def gauss(a, sigma):
    """separable gaussian blur with replicated edges; a is (H, W) or (H, W, C)"""
    r = max(1, int(np.ceil(sigma * 3)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = a.astype(np.float64)
    for axis in (0, 1):
        pad = [(0, 0)] * out.ndim
        pad[axis] = (r, r)
        p = np.pad(out, pad, mode='edge')
        acc = np.zeros_like(out)
        n = out.shape[axis]
        for i, w in enumerate(k):
            sl = [slice(None)] * out.ndim
            sl[axis] = slice(i, i + n)
            acc += w * p[tuple(sl)]
        out = acc
    return out


def components(mask, diagonal=False):
    """(label per pixel: 1.. for the connected parts of a bool mask and 0 outside; sizes by label)"""
    h, w = mask.shape
    label = np.zeros((h, w), np.int32)
    sizes = [0]
    steps = [(-1, 0), (1, 0), (0, -1), (0, 1)] + ([(-1, -1), (-1, 1), (1, -1), (1, 1)] if diagonal else [])
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if label[y0, x0]:
            continue
        current = len(sizes)
        label[y0, x0] = current
        stack, size = [(y0, x0)], 0
        while stack:
            y, x = stack.pop()
            size += 1
            for dy, dx in steps:
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not label[yy, xx]:
                    label[yy, xx] = current
                    stack.append((yy, xx))
        sizes.append(size)
    return label, sizes


def spread(img, known, steps):
    """continues the picture from the known pixels into their surroundings, `steps` pixels far.
    returns (picture, mask of what is known now)"""
    out = np.array(img, dtype=np.float64)
    known = known.copy()
    h, w = known.shape
    for _ in range(steps):
        padded = np.pad(out * known[:, :, None], ((1, 1), (1, 1), (0, 0)))
        weight = np.pad(known.astype(np.float64), 1)
        total, count = np.zeros_like(out), np.zeros((h, w))
        for dy in (0, 1, 2):
            for dx in (0, 1, 2):
                total += padded[dy:dy + h, dx:dx + w]
                count += weight[dy:dy + h, dx:dx + w]
        new = ~known & (count > 0)
        out[new] = total[new] / count[new][:, None]
        known |= new
    return out, known


def otsu(values):
    """threshold that splits the values into two groups best"""
    hist, edges = np.histogram(values, bins=256)
    mids = (edges[:-1] + edges[1:]) / 2
    w0 = np.cumsum(hist)
    w1 = w0[-1] - w0
    s0 = np.cumsum(hist * mids)
    m0 = s0 / np.maximum(w0, 1)
    m1 = (s0[-1] - s0) / np.maximum(w1, 1)
    return mids[np.argmax(w0 * w1 * (m0 - m1) ** 2)]


# ----------------------------------------------------------------------------------------------
# which part of the texture do the fingers use?
# ----------------------------------------------------------------------------------------------
def welded_components(pos, tris):
    """component id per vertex; vertices at the same place count as one"""
    _, weld = np.unique(np.round(pos * 1000).astype(np.int64), axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    parent = list(range(int(weld.max()) + 1))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b, c in weld[tris].tolist():
        ra, rb, rc = find(a), find(b), find(c)
        parent[rb] = ra
        parent[find(rc)] = ra
    return np.array([find(a) for a in weld.tolist()])


def kept_triangles(stem):
    """texture coordinates (n, 3, 2) of what patch_models.py leaves of the bare arm, in two groups:
    the fingers (pieces that are not connected to the arm) and the skin that continues under the
    glove and shows through a cut-out"""
    info = mdl_lite.read(stem + '.mdl')
    verts, _tangents = R.read_vvd(stem + '.vvd')
    vtx = R.read_vtx(stem + '.dx90.vtx')
    hand = np.array([patch_models.is_hand_bone(b['name']) for b in info['bones']])
    fingers, under = [], []
    for bi, bodypart in enumerate(info['bodyparts']):
        for mi, model in enumerate(bodypart['models']):
            for ki, mesh in enumerate(model['meshes']):
                if not info['textures'][mesh['material']].lower().startswith(patch_models.BARE_PREFIX):
                    continue
                ids, tris = vtx[bi][mi][ki]
                v = verts[model['vertexindex'] // 48 + mesh['vertoffset'] + ids]
                on_hand = hand[v['b'][np.arange(len(v)), np.argmax(v['w'], axis=1)]]
                comp = welded_components(v['pos'].astype(np.float64), tris)
                with_arm = np.zeros(int(comp.max()) + 1, bool)
                with_arm[comp[~on_hand]] = True
                keep = on_hand[tris].all(axis=1)
                arm_side = with_arm[comp[tris[:, 0]]]
                uv = v['uv'].astype(np.float64)
                fingers.append(uv[tris[keep & ~arm_side]])
                under.append(uv[tris[keep & arm_side]])
    return np.concatenate(fingers), np.concatenate(under)


def footprint(uv_tris, w, h):
    """bool mask of the texture pixels the triangles cover"""
    if len(uv_tris) == 0:
        return np.zeros((h, w), bool)
    p = np.zeros((len(uv_tris) * 3, 3))
    p[:, 0] = uv_tris[:, :, 0].reshape(-1) * w
    p[:, 1] = uv_tris[:, :, 1].reshape(-1) * h
    covered, _bary, _depth = R.rasterize(p, np.arange(len(p)).reshape(-1, 3), w, h)
    return covered >= 0


# ----------------------------------------------------------------------------------------------
# the shadow of the old glove
# ----------------------------------------------------------------------------------------------
def edge_distance(zone):
    """distance of every pixel to the edge of the zone, negative inside (exact at straight edges,
    no more than +-6 * DIST_BLUR)"""
    return np.interp(gauss(zone.astype(np.float64), DIST_BLUR), _PHI, _PHI_X) * -DIST_BLUR


def profile(dist, values):
    """mean of the values (n, channels) by distance from the edge, in steps of a pixel.
    returns (distances, number of pixels at each, means) or None when there is too little skin
    on one of the sides"""
    span = np.arange(-FIT_RANGE, FIT_RANGE + 1)
    near = np.abs(dist) <= FIT_RANGE + 0.49
    step = np.rint(dist[near]).astype(int) + FIT_RANGE
    count = np.bincount(step, minlength=len(span)).astype(np.float64)
    if (count[span <= -5] >= 20).sum() < 4 or (count[span >= 5] >= 20).sum() < 4:
        return None
    means = np.stack([np.bincount(step, weights=values[near][:, c], minlength=len(span))
                      for c in range(values.shape[1])], axis=1) / np.maximum(count, 1)[:, None]
    return span, count, means


def levels(span, count, means, offset, sigma):
    """least squares for  means = light + (dark - light) * phi(-(span - offset) / sigma).
    returns (light, dark, error)"""
    m = phi(-(span - offset) / sigma)
    sw, sm, smm = count.sum(), (count * m).sum(), (count * m * m).sum()
    sp, smp = (count * means).sum(), (count * m * means).sum()
    det = sw * smm - sm * sm
    light = (sp * smm - smp * sm) / det
    step = (sw * smp - sm * sp) / det
    return light, light + step, math.sqrt((count * (light + step * m - means) ** 2).sum() / sw)


def fit_edge(span, count, means):
    """where exactly the painted edge is and how soft: (offset, sigma, light, dark, error)"""
    best = None
    for offset in np.arange(-5.0, 5.01, 0.25):
        for sigma in np.arange(1.0, 7.01, 0.25):
            light, dark, error = levels(span, count, means, offset, sigma)
            if best is None or error < best[4]:
                best = (float(offset), float(sigma), light, dark, error)
    return best


def analyse(color, normal, fingers, under):
    """finds the darkened zone and measures, finger by finger, how much darker and duller it is.
    returns a dict with pictures (H, W): zone (bool), shade (0..1, how much of the darkening a
    pixel of a finger has), factor (H, W, 3: darkened colour / real colour), dull (what the alpha
    of the normal map lacks), dull_shade (like shade, but of the alpha); and islands, the
    numbers of every finger for the log"""
    rgb = color[:, :, :3].astype(np.float64)
    luma = rgb @ LUMA
    alpha = normal[:, :, 3].astype(np.float64)
    h, w = fingers.shape
    smooth = gauss(luma, ZONE_BLUR)
    threshold = otsu(smooth[fingers | under])
    label, sizes = components(smooth < threshold)
    zone = label == int(np.argmax(sizes))
    share = zone[fingers].mean()
    if not 0.05 < share < 0.9:
        raise SystemExit('the darkened zone was not found where the fingers are (it covers %.0f%% of them)' % (share * 100))
    if (gauss(fingers.astype(np.float64), MARGIN) > 0.001)[under].any():
        raise SystemExit('the fingers are too close to the skin under the glove in the texture: '
                         'it would be changed as well')

    # Every finger is a piece of its own in the texture, with its own skin tone, and the zone was
    # painted with a soft brush that is not equally soft everywhere. So each piece is measured
    # separately: the colours along the distance from the edge of the zone are modelled as a
    # blurred step, which gives the place of the edge, its softness and the colour on both sides.
    dist = edge_distance(zone)
    label, sizes = components(fingers, diagonal=True)
    shade, dull_shade, dull = np.zeros((h, w)), np.zeros((h, w)), np.zeros((h, w))
    factor = np.ones((h, w, 3))
    islands, rest = [], np.zeros((h, w), bool)
    for i in range(1, len(sizes)):
        island = label == i
        d = dist[island]
        if d.min() > -1.0:
            continue  # this piece is not in the zone at all
        found = profile(d, np.column_stack([luma[island], rgb[island], alpha[island]]))
        if found is None:
            rest |= island
            continue
        span, count, means = found
        offset, sigma, light, dark, error = fit_edge(span, count, means[:, 0])
        f = np.array([dark_c / light_c for light_c, dark_c, _ in
                      (levels(span, count, means[:, c], offset, sigma) for c in (1, 2, 3))])
        a_offset, a_sigma, a_light, a_dark, _ = fit_edge(span, count, means[:, 4])
        if not (0.3 < f.min() and f.max() < 0.95) or a_light <= a_dark:
            raise SystemExit('implausible darkening: colour factor %s, shine %.1f -> %.1f' % (f, a_light, a_dark))
        shade[island] = phi(-(d - offset) / sigma)
        factor[island] = f
        dull_shade[island] = phi(-(d - a_offset) / a_sigma)
        dull[island] = a_light - a_dark
        ys, xs = np.nonzero(island)
        islands.append(dict(x=int(xs.mean()), y=int(ys.mean()), size=sizes[i], share=float((d < 0).mean()),
                            offset=offset, sigma=sigma, light=light, dark=dark, error=error, factor=f,
                            shine=(a_light, a_dark), shine_edge=(a_offset, a_sigma)))
    if not islands:
        raise SystemExit('too little skin on both sides of the zone edge to measure the darkening')
    if rest.any():  # too small to be measured: like the average finger
        sigma = float(np.mean([i['sigma'] for i in islands]))
        shade[rest] = dull_shade[rest] = phi(-dist[rest] / sigma)
        factor[rest] = np.mean([i['factor'] for i in islands], axis=0)
        dull[rest] = np.mean([i['shine'][0] - i['shine'][1] for i in islands])
    return dict(zone=zone, dist=dist, shade=shade, factor=factor, dull=dull, dull_shade=dull_shade,
                islands=islands, unmeasured=int(rest.sum()), threshold=threshold)


def repaint(image, fixed, fingers, shade):
    """`fixed` on the fingers, their continuation in a margin around them wherever something was
    fixed nearby, the original picture everywhere else. returns (picture, mask of that margin)"""
    out = np.array(image, dtype=np.float64)
    out[fingers] = fixed[fingers]
    around, reach = spread(np.dstack([out, shade]), fingers, MARGIN)
    margin = reach & ~fingers
    t = np.clip(around[margin][:, -1:] * 4.0, 0.0, 1.0)
    out[margin] = out[margin] * (1.0 - t) + around[margin][:, :-1] * t
    return out, margin & (around[:, :, -1] > 0.0025)


def fix_shine(normal, fingers, a):
    """alpha of the normal map = how much the skin shines; it is zero inside the zone.
    returns it as it should be, (H, W) float, and the margin that was repainted"""
    alpha = normal[:, :, 3:4].astype(np.float64)
    fixed = alpha + (a['dull_shade'] * a['dull'])[:, :, None]
    alpha, margin = repaint(alpha, fixed, fingers, a['dull_shade'])
    return alpha[:, :, 0], margin


# ----------------------------------------------------------------------------------------------
# files
# ----------------------------------------------------------------------------------------------
def open_source(path):
    """lower-case base name -> content, for the files of the hands archive (or folder)"""
    files = {}
    if os.path.isdir(path):
        for dp, _dirs, names in os.walk(path):
            for name in names:
                with open(os.path.join(dp, name), 'rb') as f:
                    files[name.lower()] = f.read()
    else:
        with zipfile.ZipFile(path) as z:
            for item in z.infolist():
                if not item.is_dir():
                    files[os.path.basename(item.filename).lower()] = z.read(item)
    return files


def convert_vmt(text):
    _shader, items = vmt.parse(text)
    out, dropped = [], []
    for key, value in items:
        k = key.lower()
        if not isinstance(value, str) or k in DROP_KEYS:
            dropped.append(k)
            continue
        if k in make_vmts.TEXTURE_KEYS:
            ours = TEXTURES.get(make_vmts.texpath(value).rsplit('/', 1)[-1])
            if not ours:
                dropped.append('%s (%s is not in the archive)' % (k, value))
                continue
            value = SKIN_DIR + '/' + ours
        out.append((k, value))
    for wanted in ('$basetexture', '$bumpmap'):
        if not any(k == wanted for k, _ in out):
            raise SystemExit('%s.vmt has no %s' % (SOURCE, wanted))
    return out, dropped


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src_root')
    ap.add_argument('--skin', default=os.path.join(ROOT, 'hands2.zip'), help='archive (or folder) with %s.vtf' % COLOR)
    ap.add_argument('--hands', default=os.path.join(ROOT, 'hands.zip'), help='archive (or folder) with %s.*' % SOURCE)
    ap.add_argument('--out', default=os.path.join(ROOT, L.ADDON_DIRNAME))
    ap.add_argument('--preview', help='folder for pictures of what was done (before / after / masks)')
    args = ap.parse_args()

    src = open_source(args.hands)
    for name in [SOURCE + '.vmt'] + [t + '.vtf' for t in TEXTURES]:
        if name not in src:
            raise SystemExit('%s is not in %s' % (name, args.hands))
    _hdr, color = vtflib.decode_top_mip(src[SOURCE + '_color.vtf'])
    _hdr, normal = vtflib.decode_top_mip(src[SOURCE + '_normal.vtf'])
    vtflib.decode_top_mip(src[SOURCE + '_exp.vtf'])  # just to be sure it is a texture
    h, w = color.shape[:2]
    if normal.shape[:2] != (h, w):
        raise SystemExit('colour texture and normal map differ in size')

    skin_vtf = open_source(args.skin).get(COLOR + '.vtf')
    if skin_vtf is None:
        raise SystemExit('%s.vtf is not in %s' % (COLOR, args.skin))
    skin_hdr, skin_table = vtflib.mip_table(skin_vtf)
    _hdr, skin = vtflib.decode_top_mip(skin_vtf)
    if skin_hdr['format'] != vtflib.FMT_DXT5 or skin.shape[:2] != (h, w):
        raise SystemExit('%s.vtf is expected to be a DXT5 texture of %d x %d' % (COLOR, w, h))

    idx = make_vmts.build_index(args.src_root)
    fingers, under = np.zeros((h, w), bool), np.zeros((h, w), bool)
    models = []
    for fam in L.FAMILIES:
        for model, _body, _label in fam['variants']:
            if fam['fingerless'] and model not in models:
                models.append(model)
    for model in models:
        uv_fingers, uv_under = kept_triangles(idx[L.MODELS_DIR + '/' + model + '.mdl'][:-4])
        if len(uv_fingers) == 0:
            raise SystemExit('%s: no fingers found in the model' % model)
        fingers |= footprint(uv_fingers, w, h)
        under |= footprint(uv_under, w, h)
        print('%-44s %5d finger triangles, %4d of skin under the glove' % (model, len(uv_fingers), len(uv_under)))

    a = analyse(color, normal, fingers, under)
    new_alpha, margin = fix_shine(normal, fingers, a)
    print('the fingers use %.1f%% of the texture, %.0f%% of that is in the darkened zone:'
          % (fingers.mean() * 100, a['zone'][fingers].mean() * 100))
    for i in sorted(a['islands'], key=lambda i: i['x']):
        print('    finger at %4d,%-4d %6d px, %2.0f%% of it at %.2f %.2f %.2f of its colour (edge %+.2f px, soft %.2f, fit +-%.1f); '
              'shine %2.0f -> %2.0f (edge %+.2f px, soft %.2f)'
              % (i['x'], i['y'], i['size'], i['share'] * 100, i['factor'][0], i['factor'][1], i['factor'][2],
                 i['offset'], i['sigma'], i['error'], i['shine'][0], max(i['shine'][1], 0.0), i['shine_edge'][0], i['shine_edge'][1]))
    if a['unmeasured']:
        print('    %d more pixels were too few to be measured and got the average' % a['unmeasured'])
    dark, light = fingers & (a['shade'] > 0.9), fingers & (a['shade'] < 0.1)
    print('fingers, mean colour: %s in %s; %s had %s in its darkened part and %s in the rest' % (
        np.round(skin[:, :, :3][fingers].mean(axis=0)), COLOR, SOURCE,
        np.round(color[:, :, :3][dark].mean(axis=0)), np.round(color[:, :, :3][light].mean(axis=0))))

    # The normal map stays the file it is: only the 4x4 blocks in which something changes are
    # compressed again (in every mip), so nothing else loses quality a second time.
    want_n = normal.astype(np.float64)
    want_n[:, :, 3] = new_alpha
    normal_vtf, blocks_n = vtflib.patch_dxt5(src[SOURCE + '_normal.vtf'], normal, want_n, alpha=True)
    _hdr, shipped_n = vtflib.decode_top_mip(normal_vtf)

    differs = shipped_n[:, :, 3] != normal[:, :, 3]
    _, allowed = spread(np.zeros((h, w, 1)), fingers | margin, 3)  # a block may reach 3 pixels further
    print('shine changed: %d pixels on the fingers, %d around them, %d elsewhere, %d of the skin under the glove'
          % ((differs & fingers).sum(), (differs & allowed & ~fingers).sum(), (differs & ~allowed).sum(), (differs & under).sum()))
    if (differs & (under | ~allowed)).any() or (shipped_n[:, :, :3] != normal[:, :, :3]).any():
        raise SystemExit('the normal map was changed outside the fingers')
    touched = fingers | margin
    print('blocks compressed again per mip: %s' % (blocks_n,))
    print('compression error where it was changed: %.2f (of 255, rms)' % (
        np.sqrt(((shipped_n[:, :, 3][touched] - new_alpha[touched]) ** 2).mean())))

    out_dir = os.path.join(args.out, 'materials', SKIN_DIR.replace('/', os.sep))
    os.makedirs(out_dir, exist_ok=True)
    # The colour texture carries a mask in its alpha (where a tint would go: next to nowhere) that
    # the material does not use: stored as DXT1 it is half the size and shows exactly the same
    # colours, block for block.
    path = os.path.join(out_dir, SKIN_NAME + '_color.vtf')
    thumb = vtflib.thumbnail(skin_vtf)
    if thumb is None:
        raise SystemExit('%s.vtf has no thumbnail' % COLOR)
    vtflib.write_container(path, w, h, vtflib.FMT_DXT1, 0,
                           [vtflib.dxt5_to_dxt1(skin_vtf[off:off + vtflib.mip_bytes(vtflib.FMT_DXT5, mw, mh)])
                            for off, mw, mh in skin_table], thumb, skin_hdr['reflectivity'])
    with open(path, 'rb') as f:
        stored = f.read()
    for (off, mw, mh), (off1, _, _) in zip(skin_table, vtflib.mip_table(stored)[1]):
        if (vtflib.decode_mip(stored, vtflib.FMT_DXT1, off1, mw, mh)[:, :, :3] !=
                vtflib.decode_mip(skin_vtf, vtflib.FMT_DXT5, off, mw, mh)[:, :, :3]).any():
            raise SystemExit('the DXT1 copy of the colour texture differs')
    with open(os.path.join(out_dir, SKIN_NAME + '_normal.vtf'), 'wb') as f:
        f.write(normal_vtf)
    with open(os.path.join(out_dir, SKIN_NAME + '_exp.vtf'), 'wb') as f:
        f.write(src[SOURCE + '_exp.vtf'])

    items, dropped = convert_vmt(src[SOURCE + '.vmt'].decode('latin-1'))
    header = ('Z-City CS:GO gloves - skin of the bare fingers inside the fingerless glove models.\n'
              'Generated by tools/make_skin.py from %s (hands2.zip) and %s (hands.zip), do not edit by hand.'
              % (COLOR, SOURCE))
    with open(os.path.join(out_dir, SKIN_NAME + '.vmt'), 'w', encoding='ascii', newline='\n') as f:
        f.write(vmt.dump('VertexLitGeneric', items, header))
    print('left out of the material: %s' % ', '.join(dropped))
    print('wrote %s' % os.path.normpath(out_dir))
    for name in sorted(os.listdir(out_dir)):
        print('    %-22s %8d bytes' % (name, os.path.getsize(os.path.join(out_dir, name))))

    if args.preview:
        from PIL import Image
        os.makedirs(args.preview, exist_ok=True)
        Image.fromarray(color[:, :, :3]).save(os.path.join(args.preview, 'skin_old.png'))
        Image.fromarray(skin[:, :, :3]).save(os.path.join(args.preview, 'skin.png'))
        Image.fromarray(normal[:, :, 3]).save(os.path.join(args.preview, 'shine_before.png'))
        Image.fromarray(shipped_n[:, :, 3]).save(os.path.join(args.preview, 'shine_after.png'))
        masks = color[:, :, :3].astype(np.float64) * 0.45
        masks[a['zone']] += np.array([0, 40, 110])
        masks[fingers] += np.array([0, 110, 0])
        masks[under] += np.array([120, 0, 0])
        masks[margin] += np.array([110, 110, 0])
        Image.fromarray(np.clip(masks, 0, 255).astype(np.uint8)).save(os.path.join(args.preview, 'skin_masks.png'))
        print('preview: %s' % args.preview)


if __name__ == '__main__':
    main()
