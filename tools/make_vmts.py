#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the cleaned-up glove VMTs shipped in zcity_csgo_gloves/materials.

    python tools/make_vmts.py <extracted_root> [--out DIR] [--envmap] [--keep-black-tint]

<extracted_root> has one sub-folder per source archive (build_addon.py --keep-temp
leaves such a tree in build/_extract).

The VMTs inside the archives come from a "Modern Warfare base" c_hands port and do not
work in plain Garry's Mod:
  * $envmap points to envmaps/specularity_00 and a MwEnvMapTint proxy - neither exists
    without MW Base (=> pink/black reflections and console errors);
  * $fresnelrangestexture points to a warp texture that is not in the archives;
  * the Bloodhound-type gloves tint their metal parts black ("$color2" "[0 0 0]" blended by
    the base texture alpha) and rely on that envmap to give them a colour back - without
    it the studs and emblems are just black, so the black tint is dropped as well;
  * texture paths use mixed case (breaks on Linux servers / clients);
  * a few files are truncated or have stray braces.
Only the materials really used by the shipped models are generated.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mdl_lite  # noqa: E402
import vmt  # noqa: E402
import zcg_layout as L  # noqa: E402

TEXTURE_KEYS = {
    '$basetexture', '$bumpmap', '$normalmap', '$phongexponenttexture', '$envmapmask', '$lightwarptexture',
    '$phongwarptexture', '$detail', '$selfillummask', '$fresnelrangestexture', '$masks1', '$masks2',
}
DROP_KEYS = {'$fresnelrangestexture', 'proxies'}
ENVMAP_KEYS = {'$envmap', '$envmaptint'}
TINT_KEYS = {'$color2', '$blendtintbybasealpha'}


def build_index(src_root):
    """addon-relative lowercase path -> source file"""
    idx = {}
    for arc, maps in L.ARCHIVES.items():
        for inner, dest in maps:
            base = os.path.join(src_root, arc, inner)
            if not os.path.isdir(base):
                raise SystemExit('missing extracted archive folder: %s' % base)
            for dp, _, files in os.walk(base):
                for fn in files:
                    rel = os.path.relpath(os.path.join(dp, fn), base).replace('\\', '/')
                    top = L.MODELS_DIR if dest == '@models' else L.ARMS_MAT_DIR + '/' + dest
                    idx[(top + '/' + rel).lower()] = os.path.join(dp, fn)
    return idx


def used_vmts(idx):
    """addon-relative vmt path -> list of models that use it"""
    used = {}
    for m in L.MODELS:
        info = mdl_lite.read(idx[L.MODELS_DIR + '/' + m + '.mdl'])
        for tex in info['textures']:
            for cd in info['cdtextures']:
                key = 'materials/' + cd + '/' + tex.lower() + '.vmt'
                if key in idx:
                    used.setdefault(key, []).append(m)
                    break
    return used


def texpath(value):
    v = value.replace('\\', '/').strip().strip('/').lower()
    if v.endswith('.vtf'):
        v = v[:-4]
    return v


def is_black(value):
    try:
        nums = [float(x) for x in value.replace('[', ' ').replace(']', ' ').replace('{', ' ').replace('}', ' ').split()]
    except (ValueError, AttributeError):
        return False
    return len(nums) > 0 and all(abs(x) < 1e-6 for x in nums)


def convert(text, idx, keep_envmap, name, keep_black_tint=False):
    shader, items = vmt.parse(text)
    black_tint = any(k.lower() == '$color2' and is_black(v) for k, v in items)
    out = []
    for key, val in items:
        k = key.lower()
        if k in DROP_KEYS:
            continue
        if k in TINT_KEYS and black_tint and not keep_black_tint and not keep_envmap:
            continue
        if k in ENVMAP_KEYS:
            if not keep_envmap:
                continue
            if k == '$envmap':
                val = 'env_cubemap'
        elif not isinstance(val, str):
            raise SystemExit('%s: unexpected block %r' % (name, key))
        elif k in TEXTURE_KEYS:
            val = texpath(val)
            if 'materials/' + val + '.vtf' not in idx:
                raise SystemExit('%s: %s -> %s.vtf is not in the archives' % (name, k, val))
        out.append((k, val))
    if not any(k == '$basetexture' for k, _ in out):
        raise SystemExit('%s: no $basetexture' % name)
    return 'VertexLitGeneric', out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('src_root')
    ap.add_argument('--out', default=os.path.join(here, '..', L.ADDON_DIRNAME))
    ap.add_argument('--envmap', action='store_true',
                    help='keep reflections ($envmap env_cubemap, black metal tint included) instead of dropping them')
    ap.add_argument('--keep-black-tint', action='store_true', help='keep "$color2" "[0 0 0]" even without the envmap')
    args = ap.parse_args()

    idx = build_index(args.src_root)
    used = used_vmts(idx)
    for rel in sorted(used):
        text = open(idx[rel], 'r', encoding='latin-1').read()
        shader, items = convert(text, idx, args.envmap, rel, args.keep_black_tint)
        dst = os.path.join(args.out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        header = 'Z-City CS:GO gloves - generated by tools/make_vmts.py, do not edit by hand'
        with open(dst, 'w', encoding='ascii', newline='\n') as f:
            f.write(vmt.dump(shader, items, header))
    print('wrote %d VMT files to %s' % (len(used), os.path.normpath(os.path.join(args.out, L.ARMS_MAT_DIR))))


if __name__ == '__main__':
    main()
