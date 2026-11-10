#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Re-encode the oversized glove textures (4096x4096 DXT5 / 2048x2048 RGBA8888 without
mipmaps, 16.8 MB each) as 1024x1024 DXT5 with a full mip chain (1.4 MB each).

    python tools/optimize_textures.py <extracted_root> <out_dir>

<extracted_root> has one sub-folder per source archive (as produced by build_addon.py
--keep-temp); <out_dir> receives the files in the final addon layout so they can be packed
into the archives the build reads (OPTIMIZED in build_addon.py: optimized_textures.7z and,
for the gloves added later, optimized_textures2.7z).  Requires: numpy, etcpak.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vtflib  # noqa: E402
import zcg_layout as L  # noqa: E402

TARGET = 1024
MAX_BYTES = 6 * 1024 * 1024  # anything bigger than this is considered oversized


def is_normal_map(name):
    n = name.lower()
    return n.endswith('_n.vtf') or '_normal' in n


def main(src_root, out_root):
    done, saved = 0, 0
    for arc, maps in sorted(L.ARCHIVES.items()):
        for inner, dest in maps:
            if dest == '@models':
                continue
            base = os.path.join(src_root, arc, inner)
            for dp, _, files in os.walk(base):
                for fn in sorted(files):
                    if not fn.lower().endswith('.vtf'):
                        continue
                    src = os.path.join(dp, fn)
                    size = os.path.getsize(src)
                    if size <= MAX_BYTES:
                        continue
                    rel = os.path.relpath(src, base).replace('\\', '/').lower()
                    dst = os.path.join(out_root, L.ARMS_MAT_DIR, dest, rel)
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    hdr, img = vtflib.read_top_mip(src)
                    normal = is_normal_map(fn)
                    mips = vtflib.build_mips(img, TARGET, normal=normal)
                    vtflib.write_vtf(dst, mips, fmt=vtflib.FMT_DXT5, flags=vtflib.FLAG_EIGHTBITALPHA)
                    new = os.path.getsize(dst)
                    done += 1
                    saved += size - new
                    print('%-78s %4dx%-4d %-8s -> %dx%d DXT5 %2d mips%s  %5.2f -> %4.2f MB' % (
                        os.path.join(dest, rel), hdr['width'], hdr['height'], vtflib.FMT_NAMES.get(hdr['format'], '?'),
                        mips[0].shape[1], mips[0].shape[0], len(mips), ' (normal map)' if normal else '',
                        size / 1048576.0, new / 1048576.0))
    print('optimized %d textures, saved %.1f MB' % (done, saved / 1048576.0))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
