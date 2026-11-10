#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Render the glove icons used by the in-game picker and the catalogue picture for the README.

    python tools/render_previews.py <extracted_root> [--icons DIR] [--sheet FILE] [--only ID ...]

<extracted_root> has one sub-folder per source archive (build_addon.py --keep-temp leaves such
a tree in build/_extract).  Needs numpy and pillow.

This is a small software rasteriser, not the game: it reads the .mdl/.vvd/.vtx files and the
VTF textures directly, poses nothing (bind pose) and shades with a simple lambert + specular
model.  It is good enough to tell the 44 variants apart, which is all the icons are for.
The pictures are committed, so the tool only has to be re-run when gloves are added or changed.
"""
import argparse
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_vmts  # noqa: E402
import mdl_lite  # noqa: E402
import vmt  # noqa: E402
import vtflib  # noqa: E402
import zcg_layout as L  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.normpath(os.path.join(HERE, '..', L.ADDON_DIRNAME))
SKIN = np.array([0.30, 0.30, 0.32])  # neutral "mannequin" colour for the bare fingers (linear)
EXPOSURE = 1.9

VVD_VERTEX = np.dtype([('w', '<f4', 3), ('b', 'u1', 3), ('nb', 'u1'), ('pos', '<f4', 3), ('nrm', '<f4', 3), ('uv', '<f4', 2)])
VTX_VERTEX = np.dtype([('bw', 'u1', 3), ('nb', 'u1'), ('id', '<u2'), ('bid', 'i1', 3)])


# ----------------------------------------------------------------------------------------------
# file readers
# ----------------------------------------------------------------------------------------------
def read_vvd(path):
    b = open(path, 'rb').read()
    lodverts = struct.unpack_from('<8i', b, 16)
    numfix, fixstart, vstart, tstart = struct.unpack_from('<4i', b, 48)
    total = (tstart - vstart) // 48 if tstart else (len(b) - vstart) // 48
    raw = np.frombuffer(b, dtype=VVD_VERTEX, count=total, offset=vstart)
    tang = np.frombuffer(b, dtype='<f4', count=total * 4, offset=tstart).reshape(-1, 4) if tstart else None
    if numfix:
        parts, tparts = [], []
        for i in range(numfix):
            lod, src, n = struct.unpack_from('<3i', b, fixstart + i * 12)
            if lod >= 0:
                parts.append(raw[src:src + n])
                if tang is not None:
                    tparts.append(tang[src:src + n])
        return np.concatenate(parts), (np.concatenate(tparts) if tang is not None else None)
    return raw[:lodverts[0]], (tang[:lodverts[0]] if tang is not None else None)


def read_vtx(path):
    """list[bodypart] of list[model] of list[mesh] (LOD 0); mesh = (vertex ids, triangles indexing them)"""
    b = open(path, 'rb').read()
    version = struct.unpack_from('<i', b, 0)[0]
    if version != 7:
        raise ValueError('%s: unsupported vtx version %d' % (path, version))
    numbp, bpoff = struct.unpack_from('<2i', b, 28)
    out = []
    for i in range(numbp):
        bo = bpoff + i * 8
        nummodels, modeloff = struct.unpack_from('<2i', b, bo)
        models = []
        for j in range(nummodels):
            mo = bo + modeloff + j * 8
            _nlods, lodoff = struct.unpack_from('<2i', b, mo)
            lo = mo + lodoff
            nummeshes, meshoff = struct.unpack_from('<2i', b, lo)
            meshes = []
            for k in range(nummeshes):
                meo = lo + meshoff + k * 9
                nsg, sgoff = struct.unpack_from('<2i', b, meo)
                vids, tris, base = [], [], 0
                for s in range(nsg):
                    so = meo + sgoff + s * 25
                    nv, vo, ni, io, ns, sto = struct.unpack_from('<6i', b, so)
                    verts = np.frombuffer(b, dtype=VTX_VERTEX, count=nv, offset=so + vo)
                    idx = np.frombuffer(b, dtype='<u2', count=ni, offset=so + io).astype(np.int64)
                    for t in range(ns):
                        sth = so + sto + t * 27
                        sni, sio = struct.unpack_from('<2i', b, sth)
                        flags = b[sth + 18]
                        sub = idx[sio:sio + sni]
                        if flags & 1:  # triangle list
                            tris.append(sub.reshape(-1, 3) + base)
                        elif flags & 2:  # triangle strip
                            tt = [(sub[q], sub[q + 1], sub[q + 2]) if q % 2 == 0 else (sub[q + 1], sub[q], sub[q + 2])
                                  for q in range(len(sub) - 2)]
                            tris.append(np.array(tt, np.int64).reshape(-1, 3) + base)
                    vids.append(verts['id'].astype(np.int64))
                    base += nv
                meshes.append((np.concatenate(vids) if vids else np.zeros(0, np.int64),
                               np.concatenate(tris) if tris else np.zeros((0, 3), np.int64)))
            models.append(meshes)
        out.append(models)
    return out


class Assets:
    def __init__(self, src_root, tex_size=512):
        self.idx = make_vmts.build_index(src_root)
        self.tex_size = tex_size
        self._tex = {}
        self._models = {}

    def texture(self, rel):
        """'models/weapons/...' (no extension) -> float32 RGBA 0..1"""
        if rel not in self._tex:
            _hdr, img = vtflib.read_top_mip(self.idx['materials/' + rel + '.vtf'])
            h, w = img.shape[:2]
            f = img.astype(np.float32) / 255.0
            if w > self.tex_size:
                k = w // self.tex_size
                f = f.reshape(h // k, k, w // k, k, 4).mean(axis=(1, 3))
            self._tex[rel] = f
        return self._tex[rel]

    def material(self, cds, texname):
        for cd in cds:
            p = os.path.join(ADDON, 'materials', cd, texname.lower() + '.vmt')
            if os.path.exists(p):
                _shader, items = vmt.parse(open(p).read())
                return {k: v for k, v in items if isinstance(v, str)}
        return None

    def model(self, name):
        if name not in self._models:
            p = self.idx[L.MODELS_DIR + '/' + name + '.mdl'][:-4]
            verts, tang = read_vvd(p + '.vvd')
            self._models[name] = (mdl_lite.read(p + '.mdl'), verts, tang, read_vtx(p + '.dx90.vtx'))
        return self._models[name]

    def meshes(self, name, body):
        """meshes of body group "gloves" = body (LOD 0)"""
        info, verts, tang, vtx = self.model(name)
        bi = [i for i, bp in enumerate(info['bodyparts']) if bp['name'] == 'gloves'][0]
        m = info['bodyparts'][bi]['models'][body]
        out = []
        for ki, me in enumerate(m['meshes']):
            tex = info['textures'][me['material']]
            vids, tris = vtx[bi][body][ki]
            base = m['vertexindex'] // 48 + me['vertoffset']
            v = verts[base + vids]
            mat = self.material(info['cdtextures'], tex)
            out.append(dict(tex=tex, mat=mat, pos=v['pos'].astype(np.float64), nrm=v['nrm'].astype(np.float64),
                            uv=v['uv'].astype(np.float64), bones=v['b'], w=v['w'], tris=tris,
                            tang=tang[base + vids] if tang is not None else None))
        return info, out


# ----------------------------------------------------------------------------------------------
# camera: look at the back of one hand
# ----------------------------------------------------------------------------------------------
def hand_view(info, side='R'):
    """returns (select(mesh) -> vertex mask, 3x3 view matrix with rows right / down / forward)"""
    names = [bn['name'] for bn in info['bones']]
    m = np.eye(4)
    m[:3, :4] = np.array(info['bones'][names.index('ValveBiped.Bip01_%s_Hand' % side)]['pose_to_bone']).reshape(3, 4)
    m = np.linalg.inv(m)  # bone -> model space in the bind pose
    x, y = m[:3, 0], m[:3, 1]  # x: along the hand towards the fingers
    on_side = np.array([('_%s_' % side) in n for n in names])
    on_hand = np.array([('_%s_Hand' % side) in n or ('_%s_Finger' % side) in n for n in names])

    def select(mesh):
        dom = mesh['bones'][np.arange(len(mesh['bones'])), np.argmax(mesh['w'], axis=1)]
        # of the bare arm keep only the hand itself: the forearm would just shrink the picture
        return (on_hand if mesh['mat'] is None else on_side)[dom]

    fwd = -y if side == 'R' else y  # looking at the back of the hand
    right = np.cross(fwd, x)
    right /= np.linalg.norm(right)
    return select, np.stack([right, -x, fwd])


# ----------------------------------------------------------------------------------------------
# rasteriser
# ----------------------------------------------------------------------------------------------
def rasterize(P, tris, W, H):
    zbuf = np.full((H, W), np.inf)
    tbuf = np.full((H, W), -1, np.int64)
    bary = np.zeros((H, W, 3))
    p0, p1, p2 = P[tris[:, 0]], P[tris[:, 1]], P[tris[:, 2]]
    area = (p1[:, 0] - p0[:, 0]) * (p2[:, 1] - p0[:, 1]) - (p2[:, 0] - p0[:, 0]) * (p1[:, 1] - p0[:, 1])
    mn = np.floor(np.minimum(np.minimum(p0, p1), p2)[:, :2]).astype(int)
    mx = np.ceil(np.maximum(np.maximum(p0, p1), p2)[:, :2]).astype(int)
    for i in range(len(tris)):
        a = area[i]
        if abs(a) < 1e-9:
            continue
        x0, y0 = max(mn[i, 0], 0), max(mn[i, 1], 0)
        x1, y1 = min(mx[i, 0], W - 1), min(mx[i, 1], H - 1)
        if x0 > x1 or y0 > y1:
            continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((p1[i, 0] - X) * (p2[i, 1] - Y) - (p2[i, 0] - X) * (p1[i, 1] - Y)) / a
        w1 = ((p2[i, 0] - X) * (p0[i, 1] - Y) - (p0[i, 0] - X) * (p2[i, 1] - Y)) / a
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        z = w0 * p0[i, 2] + w1 * p1[i, 2] + w2 * p2[i, 2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        upd = inside & (z < sub)
        if not upd.any():
            continue
        sub[upd] = z[upd]
        tbuf[y0:y1 + 1, x0:x1 + 1][upd] = i
        bb = bary[y0:y1 + 1, x0:x1 + 1]
        bb[upd, 0] = w0[upd]
        bb[upd, 1] = w1[upd]
        bb[upd, 2] = w2[upd]
    return tbuf, bary, zbuf


def sample(tex, uv):
    h, w = tex.shape[:2]
    u = (uv[:, 0] % 1.0) * w - 0.5
    v = (uv[:, 1] % 1.0) * h - 0.5
    x0 = np.floor(u).astype(int)
    y0 = np.floor(v).astype(int)
    fx = (u - x0)[:, None]
    fy = (v - y0)[:, None]
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    x0 %= w
    y0 %= h
    return (tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx) * (1 - fy) + (tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx) * fy


def render(assets, meshes, view, select, size=512, margin=1.06, light=(-0.45, -0.55, -0.7)):
    """returns float RGBA (size, size, 4), straight alpha, sRGB"""
    W = H = size
    kept = []
    for m in meshes:
        m['_keep'] = select(m)
        if m['mat'] is not None and m['_keep'].any():
            kept.append(m['pos'][m['_keep']])
    scr = np.concatenate(kept) @ view.T  # framing ignores the bare hand
    lo, hi = scr.min(0), scr.max(0)
    center = (lo + hi) / 2
    scale = W / (max(hi[0] - lo[0], hi[1] - lo[1]) * margin)

    img = np.zeros((H, W, 4))
    zall = np.full((H, W), np.inf)
    to_light = -np.array(light, float)
    to_light /= np.linalg.norm(to_light)
    half = to_light + np.array([0, 0, -1.0])
    half /= np.linalg.norm(half)
    for m in meshes:
        tris = m['tris'][m['_keep'][m['tris']].all(axis=1)]
        if len(tris) == 0:
            continue
        s = m['pos'] @ view.T
        P = np.empty_like(s)
        P[:, 0] = (s[:, 0] - center[0]) * scale + W / 2
        P[:, 1] = (s[:, 1] - center[1]) * scale + H / 2
        P[:, 2] = s[:, 2]
        tbuf, bary, zbuf = rasterize(P, tris, W, H)
        mask = (tbuf >= 0) & (zbuf < zall)
        if not mask.any():
            continue
        bc = bary[mask]
        tv = tris[tbuf[mask]]
        uv = (m['uv'][tv] * bc[:, :, None]).sum(axis=1)
        n = (m['nrm'][tv] * bc[:, :, None]).sum(axis=1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-6)
        mat = m['mat']
        if mat is None:  # bare hand of the fingerless gloves
            alb = np.tile(SKIN, (len(tv), 1))
            spec_mask = np.zeros(len(tv))
        else:
            base = sample(assets.texture(mat['$basetexture']), uv)
            alb = base[:, :3] ** 2.2
            tint = np.array([float(x) for x in mat.get('$color2', '[1 1 1]').strip('[]').split()])
            if mat.get('$blendtintbybasealpha') == '1':
                a = base[:, 3:4]
                alb = alb * (1 - a) + alb * tint * a
            else:
                alb = alb * tint
            spec_mask = np.ones(len(tv))
            if '$bumpmap' in mat and m['tang'] is not None:
                nt = sample(assets.texture(mat['$bumpmap']), uv)
                tn = nt[:, :3] * 2 - 1
                spec_mask = nt[:, 3]
                tg = (m['tang'][tv] * bc[:, :, None]).sum(axis=1)
                t = tg[:, :3] - n * (tg[:, :3] * n).sum(axis=1, keepdims=True)
                t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-6)
                bt = np.cross(n, t) * np.sign(tg[:, 3:4] + 1e-9)
                n = t * tn[:, 0:1] + bt * tn[:, 1:2] + n * tn[:, 2:3]
                n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-6)
        nv = n @ view.T
        ndl = np.clip((nv * to_light).sum(axis=1), 0, 1)
        fill = np.clip((nv * np.array([0.6, 0.2, -0.75])).sum(axis=1), 0, 1)
        spec = np.clip((nv * half).sum(axis=1), 0, 1) ** 24 * 0.35 * spec_mask
        col = alb * (0.34 + 0.95 * ndl[:, None] + 0.25 * fill[:, None])
        col += spec[:, None] * (0.5 + 0.5 * alb / np.maximum(alb.max(axis=1, keepdims=True), 1e-3))
        col = 1.0 - np.exp(-EXPOSURE * col)  # soft clip: the icons sit on a dark panel, dark leather must stay readable
        img[mask, :3] = np.clip(col, 0, 1) ** (1 / 2.2)
        img[mask, 3] = 1.0
        zall[mask] = zbuf[mask]
    return img


def downscale(img, size):
    """box filter on premultiplied alpha, then bleed the colour into transparent pixels"""
    k = img.shape[0] // size
    pm = img[:, :, :3] * img[:, :, 3:4]
    a = img[:, :, 3].reshape(size, k, size, k).mean(axis=(1, 3))
    rgb = pm.reshape(size, k, size, k, 3).mean(axis=(1, 3)) / np.maximum(a[:, :, None], 1e-6)
    known = a > 0
    for _ in range(4):  # avoids dark fringes when the game filters the icon
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                acc += np.roll(np.roll(rgb * known[:, :, None], dy, 0), dx, 1)
                cnt += np.roll(np.roll(known, dy, 0), dx, 1)
        fill = ~known & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        known = known | fill
    out = np.dstack([rgb, a])
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


# ----------------------------------------------------------------------------------------------
# catalogue picture
# ----------------------------------------------------------------------------------------------
def make_sheet(variants, tiles, path, tile=168, cols=8):
    pad, label_h, head_h = 10, 34, 40
    bg, panel, text, dim = (24, 24, 28), (38, 38, 46), (235, 235, 235), (160, 160, 170)
    f_head = ImageFont.load_default(size=22)
    f_lab = ImageFont.load_default(size=13)
    f_small = ImageFont.load_default(size=11)

    families = []
    for v in variants:
        if not families or families[-1][0] is not v['family']:
            families.append((v['family'], []))
        families[-1][1].append(v)

    # single-variant families share one row to save space
    rows = []
    singles = [f for f in families if len(f[1]) < 4]
    for fam, vs in families:
        if len(vs) < 4:
            continue
        rows.append((fam['title'] + ('  (fingerless)' if fam['fingerless'] else ''), vs))
    if singles:
        rows.append(('Other', [v for _f, vs in singles for v in vs]))

    width = pad + cols * (tile + pad)
    height = pad
    for _title, vs in rows:
        height += head_h + ((len(vs) + cols - 1) // cols) * (tile + label_h + pad)
    sheet = Image.new('RGB', (width, height), bg)
    d = ImageDraw.Draw(sheet)
    y = pad
    for title, vs in rows:
        d.text((pad + 2, y + 6), title, font=f_head, fill=text)
        y += head_h
        for i, v in enumerate(vs):
            x = pad + (i % cols) * (tile + pad)
            yy = y + (i // cols) * (tile + label_h + pad)
            d.rounded_rectangle((x, yy, x + tile, yy + tile + label_h), 8, fill=panel)
            im = Image.fromarray(tiles[v['id']], 'RGBA').resize((tile, tile), Image.LANCZOS)
            sheet.paste(im, (x, yy), im)
            d.text((x + 8, yy + tile + 1), v['name'].replace('CS:GO ', ''), font=f_lab, fill=text)
            d.text((x + 8, yy + tile + 17), v['label'], font=f_small, fill=dim)
        y += ((len(vs) + cols - 1) // cols) * (tile + label_h + pad)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path, quality=88, optimize=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src_root')
    ap.add_argument('--icons', default=os.path.join(ADDON, 'materials', 'zcity_csgo_gloves', 'icons'))
    ap.add_argument('--sheet', default=os.path.normpath(os.path.join(HERE, '..', 'docs', 'gloves.jpg')))
    ap.add_argument('--size', type=int, default=128, help='icon size in pixels (power of two)')
    ap.add_argument('--only', nargs='*', help='render only these variant ids (no catalogue)')
    args = ap.parse_args()

    assets = Assets(args.src_root)
    variants = L.variants()
    os.makedirs(args.icons, exist_ok=True)
    tiles = {}
    for v in variants:
        if args.only and v['id'] not in args.only:
            continue
        info, meshes = assets.meshes(v['model'], v['body'])
        select, view = hand_view(info, 'R')
        big = render(assets, meshes, view, select, size=512)
        tiles[v['id']] = downscale(big, 256)
        Image.fromarray(downscale(big, args.size), 'RGBA').save(os.path.join(args.icons, v['id'] + '.png'), optimize=True)
        print('%-16s %s' % (v['id'], v['name']), flush=True)
    if not args.only:
        make_sheet(variants, tiles, args.sheet)
        print('catalogue: %s' % args.sheet)


if __name__ == '__main__':
    main()
