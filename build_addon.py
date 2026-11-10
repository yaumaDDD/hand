#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the ready-to-install Garry's Mod addon "zcity_csgo_gloves".

    python build_addon.py [--out DIR] [--zip] [--original-textures] [--keep-temp]

The repository keeps the heavy content (models, textures) in the .7z archives it was delivered
in, plus a small addon skeleton (Lua, materials, icons) in zcity_csgo_gloves/.  This script
unpacks the archives and puts everything where the game expects it:

    build/zcity_csgo_gloves/        <- copy this folder to garrysmod/addons/
        addon.json
        lua/...
        materials/...
        models/zcity_csgo_gloves/...

Needs Python 3.7+ and one of
    * the py7zr module          (python -m pip install py7zr)
    * 7-Zip / p7zip             (7z, 7za, 7zr or 7zz in PATH, or installed in Program Files)
About 1.5 GB of free disk space is used while building; the result is about 270 MB.
"""
import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'tools'))

import make_lua_data  # noqa: E402
import make_vmts  # noqa: E402
import mdl_lite  # noqa: E402
import patch_models  # noqa: E402
import vmt  # noqa: E402
import zcg_layout as L  # noqa: E402

# reduced versions of the oversized textures (tools/optimize_textures.py), in the addon layout;
# the second archive came with the Driver and Specialist gloves
OPTIMIZED = ('optimized_textures.7z', 'optimized_textures2.7z')
OVERSIZED = 6 * 1024 * 1024  # as in tools/optimize_textures.py
MARKER = '.zcg_extracted'
# file date inside the zip: fixed, so that the same sources always give the very same zip
ZIP_TIME = (2026, 11, 10, 12, 0, 0)


class BuildError(Exception):
    exit_code = 1


class NoExtractor(BuildError):
    exit_code = 3  # build_addon.bat reacts to this one by installing py7zr


# ---------------------------------------------------------------------------------------------
# 7z extraction
# ---------------------------------------------------------------------------------------------
def find_7z_binary():
    for name in ('7z', '7za', '7zr', '7zz'):
        exe = shutil.which(name)
        if exe:
            return exe
    for var in ('ProgramFiles', 'ProgramW6432', 'ProgramFiles(x86)'):
        base = os.environ.get(var)
        if base:
            exe = os.path.join(base, '7-Zip', '7z.exe')
            if os.path.isfile(exe):
                return exe
    return None


def pick_extractor():
    """returns (description, function(archive, dest))"""
    try:
        import py7zr
    except ImportError:
        py7zr = None

    if py7zr is not None:
        def with_py7zr(archive, dest):
            with py7zr.SevenZipFile(archive, 'r') as z:
                z.extractall(path=dest)
        return 'py7zr ' + getattr(py7zr, '__version__', ''), with_py7zr

    exe = find_7z_binary()
    if exe:
        def with_binary(archive, dest):
            proc = subprocess.run([exe, 'x', '-y', '-o' + dest, archive],
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if proc.returncode != 0:
                tail = proc.stdout.decode('utf-8', 'replace').strip().splitlines()[-8:]
                raise BuildError('%s failed on %s:\n    %s' % (os.path.basename(exe), archive, '\n    '.join(tail)))
        return exe, with_binary

    raise NoExtractor(
        'no way to unpack .7z archives was found. Do one of:\n'
        '    * run:  %s -m pip install py7zr\n'
        '    * install 7-Zip (https://www.7-zip.org) and run this script again'
        % (os.path.basename(sys.executable) or 'python'))


def extract(extractor, archive, dest):
    """unpack archive into dest unless that was already done for this very file"""
    stamp = '%s:%d' % (os.path.basename(archive), os.path.getsize(archive))
    marker = os.path.join(dest, MARKER)
    if os.path.isfile(marker):
        with open(marker, 'r', encoding='utf-8') as f:
            if f.read().strip() == stamp:
                return False
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    extractor(archive, dest)
    with open(marker, 'w', encoding='utf-8') as f:
        f.write(stamp)
    return True


# ---------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------
def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def read_vmt(path):
    with open(path, 'r', encoding='latin-1') as f:
        return vmt.parse(f.read())


def vmt_textures(path):
    """addon-relative .vtf paths a VMT refers to"""
    _shader, items = read_vmt(path)
    out = []
    for key, val in items:
        if key.lower() in make_vmts.TEXTURE_KEYS and isinstance(val, str):
            out.append('materials/' + make_vmts.texpath(val) + '.vtf')
    return out


def vtf_size(path):
    """(width, height) of a VTF file, raises BuildError if it is not one"""
    with open(path, 'rb') as f:
        head = f.read(20)
    if len(head) < 20 or head[:4] != b'VTF\x00':
        raise BuildError('not a VTF file: %s' % path)
    width, height = struct.unpack_from('<2H', head, 16)
    if not width or not height:
        raise BuildError('broken VTF header: %s' % path)
    return width, height


def walk_files(root):
    for dp, _dirs, files in os.walk(root):
        for fn in files:
            full = os.path.join(dp, fn)
            yield os.path.relpath(full, root).replace('\\', '/'), full


def looks_like_old_build(path):
    """only ever delete a folder this script produced"""
    if not os.path.isdir(path):
        return False
    entries = os.listdir(path)
    if not entries:
        return True
    return os.path.isfile(os.path.join(path, 'addon.json')) and \
        os.path.isfile(os.path.join(path, 'lua', 'autorun', L.ADDON_DIRNAME + '.lua'))


def mb(size):
    return '%.1f MB' % (size / 1048576.0)


# ---------------------------------------------------------------------------------------------
# build steps
# ---------------------------------------------------------------------------------------------
def step_extract(extractor, temp):
    names = sorted(L.ARCHIVES)
    for i, name in enumerate(names, 1):
        archive = os.path.join(HERE, name + '.7z')
        if not os.path.isfile(archive):
            raise BuildError('archive is missing: %s' % archive)
        print('  [%2d/%d] %s.7z' % (i, len(names), name), end='', flush=True)
        fresh = extract(extractor, archive, os.path.join(temp, name))
        print('' if fresh else '  (already unpacked)')


def check_out(out):
    if os.path.exists(out) and not looks_like_old_build(out):
        raise BuildError('%s exists and is not an earlier build of this addon - '
                         'remove it yourself or choose another --out' % out)


def step_skeleton(out):
    skeleton = os.path.join(HERE, L.ADDON_DIRNAME)
    if not os.path.isfile(os.path.join(skeleton, 'addon.json')):
        raise BuildError('addon skeleton is missing: %s' % skeleton)
    check_out(out)
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(skeleton, out)


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def step_models(idx, out):
    """copies the models and takes the bare CS:GO arm out of them, except for the hands and
    fingers of the fingerless gloves (see tools/patch_models.py).
    returns (files, triangles of the arm that stay, triangles removed)"""
    count, kept, removed = 0, 0, 0
    for model in L.MODELS:
        for ext in L.MODEL_EXTS:
            rel = L.MODELS_DIR + '/' + model + ext
            src = idx.get(rel.lower())
            if not src:
                raise BuildError('model file is not in the archives: %s' % rel)
            copy(src, os.path.join(out, rel.lower()))
            count += 1
        stem = os.path.join(out, L.MODELS_DIR, model)
        for ext in L.MODEL_EXTS:
            if not ext.endswith('.vtx'):
                continue
            original = read_bytes(stem + ext)
            try:
                patched, stats = patch_models.fingers_only(stem + '.mdl', read_bytes(stem + '.vvd'), original)
            except (patch_models.PatchError, ValueError, IndexError, KeyError, struct.error) as err:
                raise BuildError('%s%s: cannot remove the bare arm: %s' % (model, ext, err))
            if len(patched) != len(original):
                raise BuildError('%s%s: patching changed the file size' % (model, ext))
            with open(stem + ext, 'wb') as f:
                f.write(patched)
            kept += stats['kept']
            removed += stats['removed']
    return count, kept, removed


def shipped_vmts(out):
    root = os.path.join(out, L.ARMS_MAT_DIR)
    return sorted(full for rel, full in walk_files(root) if rel.endswith('.vmt'))


def step_textures(idx, out):
    wanted = set()
    for path in shipped_vmts(out):
        for tex in vmt_textures(path):
            if tex not in idx:
                raise BuildError('%s refers to %s, which is not in the archives' % (path, tex))
            wanted.add(tex)
    for tex in sorted(wanted):
        copy(idx[tex], os.path.join(out, tex))
    return wanted


def step_optimized(extractor, temp, out, wanted):
    replaced, saved = 0, 0
    for number, name in enumerate(OPTIMIZED, 1):
        archive = os.path.join(HERE, name)
        if not os.path.isfile(archive):
            raise BuildError('%s is missing (use --original-textures to build without it)' % archive)
        dest = os.path.join(temp, '_optimized' + (str(number) if number > 1 else ''))
        extract(extractor, archive, dest)
        for rel, full in walk_files(dest):
            rel = rel.lower()
            if not rel.endswith('.vtf') or rel not in wanted:
                continue
            target = os.path.join(out, rel)
            saved += os.path.getsize(target) - os.path.getsize(full)
            copy(full, target)
            replaced += 1
    # a texture that was forgotten here would quietly add 16 MB to the addon
    left = sorted(rel for rel in wanted if os.path.getsize(os.path.join(out, rel)) > OVERSIZED)
    if left:
        raise BuildError('no reduced version in %s for:\n    %s\n'
                         'run tools/optimize_textures.py and pack its output, or build with --original-textures'
                         % (' / '.join(OPTIMIZED), '\n    '.join(left)))
    return replaced, saved


def step_verify(out):
    """model -> material -> VMT -> texture, the Lua catalogue and the icons"""
    problems = []
    variants = L.variants()

    def exists(rel):
        return os.path.isfile(os.path.join(out, rel))

    checked_vmts = {}

    def check_vmt(rel):
        if rel in checked_vmts:
            return
        checked_vmts[rel] = True
        try:
            textures = vmt_textures(os.path.join(out, rel))
        except Exception as err:  # noqa: BLE001 - any parse problem is a build problem
            problems.append('%s: %s' % (rel, err))
            return
        if not any(t for t in textures):
            problems.append('%s: no textures' % rel)
        for tex in textures:
            if not exists(tex):
                problems.append('%s: texture is missing: %s' % (rel, tex))
                continue
            try:
                vtf_size(os.path.join(out, tex))
            except BuildError as err:
                problems.append(str(err))

    # which models belong to fingerless gloves: those must have fingers, the others must not
    with_fingers = {v['model']: v['family']['fingerless'] for v in variants}
    for fam in L.FAMILIES:
        for model, _body, _label in fam['variants']:
            if with_fingers[model] != fam['fingerless']:
                problems.append('%s: used by fingerless and by full-finger gloves at once' % model)

    models = {}
    for v in variants:
        rel = L.MODELS_DIR + '/' + v['model'] + '.mdl'
        if v['model'] not in models:
            for ext in L.MODEL_EXTS:
                if not exists(L.MODELS_DIR + '/' + v['model'] + ext):
                    problems.append('model file is missing: %s%s' % (v['model'], ext))
            try:
                models[v['model']] = mdl_lite.read(os.path.join(out, rel))
            except Exception as err:  # noqa: BLE001
                problems.append('%s: %s' % (rel, err))
                models[v['model']] = None
            if models[v['model']]:
                stem = os.path.join(out, L.MODELS_DIR, v['model'])
                # The three files of a model may come from different archives; the game refuses
                # a model whose files do not carry the same checksum.
                sums = []
                for ext, offset in (('.mdl', 8), ('.vvd', 8), ('.dx90.vtx', 16)):
                    if os.path.isfile(stem + ext):
                        with open(stem + ext, 'rb') as f:
                            f.seek(offset)
                            sums.append(f.read(4))
                if len(set(sums)) > 1:
                    problems.append('%s: the .mdl, .vvd and .dx90.vtx do not belong together (different checksums)' % v['model'])
                for ext in L.MODEL_EXTS:
                    if not ext.endswith('.vtx') or not os.path.isfile(stem + ext):
                        continue
                    try:
                        drawn, wrong = patch_models.count_bare(stem + '.mdl', read_bytes(stem + '.vvd'), read_bytes(stem + ext))
                    except Exception as err:  # noqa: BLE001
                        problems.append('%s%s: %s' % (v['model'], ext, err))
                        continue
                    if wrong:
                        problems.append('%s%s: %d triangles of the bare CS:GO arm are still in the model' % (v['model'], ext, wrong))
                    if with_fingers[v['model']] and not drawn:
                        problems.append('%s%s: a fingerless glove without fingers' % (v['model'], ext))
                    if not with_fingers[v['model']] and drawn:
                        problems.append('%s%s: %d triangles of bare skin in a full-finger glove' % (v['model'], ext, drawn))
        info = models[v['model']]
        if not info:
            continue

        gloves = [bp for bp in info['bodyparts'] if bp['name'] == 'gloves']
        if not gloves or v['body'] >= len(gloves[0]['models']):
            problems.append('%s: no body group "gloves" value %d' % (rel, v['body']))
            continue
        try:
            materials = L.glove_materials(info, v)
        except ValueError as err:
            problems.append(str(err))
            continue
        found = 0
        for _index, name, drawn in materials:
            if name.startswith(patch_models.BARE_PREFIX):
                continue  # what is left of the arm inside the glove model: Lua sets its material
            hit = None
            for cd in info['cdtextures']:
                cand = 'materials/' + cd + '/' + drawn + '.vmt'
                if exists(cand):
                    hit = cand
                    break
            if not hit:
                problems.append('%s (%s): material is missing: %s' % (v['id'], v['model'], drawn))
                continue
            found += 1
            check_vmt(hit)
        if not found:
            problems.append('%s: the glove has no materials' % v['id'])

        if not exists('materials/%s/icons/%s.png' % (L.ADDON_DIRNAME, v['id'])):
            problems.append('%s: icon is missing' % v['id'])

    # the skin of those fingers, and the Lua side must ask for this very material
    skin = 'materials/' + L.FINGER_MATERIAL + '.vmt'
    if exists(skin):
        check_vmt(skin)
    else:
        problems.append('the skin of the glove fingers is missing: %s - run tools/make_skin.py' % skin)
    config = os.path.join(out, 'lua', L.ADDON_DIRNAME, 'sh_config.lua')
    if not os.path.isfile(config):
        problems.append('lua/%s/sh_config.lua is missing' % L.ADDON_DIRNAME)
    else:
        with open(config, 'r', encoding='utf-8') as f:
            if 'FingerMaterial = "%s"' % L.FINGER_MATERIAL not in f.read():
                problems.append('sh_config.lua: FingerMaterial is expected to be "%s"' % L.FINGER_MATERIAL)

    # everything that is shipped must be usable (no stray upper-case names, no orphans)
    for path in shipped_vmts(out):
        check_vmt(os.path.relpath(path, out).replace('\\', '/'))
    for rel, _full in walk_files(out):
        if rel != rel.lower():
            problems.append('upper-case file name (breaks on Linux): %s' % rel)

    data = os.path.join(out, 'lua', L.ADDON_DIRNAME, 'sh_data.lua')
    if not os.path.isfile(data):
        problems.append('lua/%s/sh_data.lua is missing' % L.ADDON_DIRNAME)
    else:
        with open(data, 'r', encoding='utf-8') as f:
            text = f.read()
        lines = set(line.strip() for line in text.splitlines())
        for v in variants:
            # the very line the generator writes: model, body value and swapped materials included
            try:
                known = models.get(v['model']) and make_lua_data.variant_lua(v, models[v['model']], out) in lines
            except ValueError as err:
                problems.append(str(err))
                continue
            if not known:
                problems.append('sh_data.lua does not know %s (as it is now) - run tools/make_lua_data.py' % v['id'])
        # ... and where it expects the removed arm, there must be a removed triangle
        cuts = dict(re.findall(r'\["([^"]+\.mdl)"\] = \{.*\bbare = \{.*\bcut = (\d+)', text))
        for model in L.MODELS:
            rel = L.MODELS_DIR + '/' + model
            vtx = os.path.join(out, rel + '.dx90.vtx')
            if rel + '.mdl' not in cuts:
                problems.append('sh_data.lua does not know the model %s - run tools/make_lua_data.py' % model)
            elif os.path.isfile(vtx) and not patch_models.is_removed(read_bytes(vtx), int(cuts[rel + '.mdl'])):
                problems.append('sh_data.lua does not fit %s.dx90.vtx - run tools/make_lua_data.py' % model)

    return problems, len(checked_vmts)


def make_zip(out):
    """<out>.zip with the addon folder inside; byte for byte the same for the same content"""
    path = out + '.zip'
    top = os.path.basename(out)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for rel, full in sorted(walk_files(out)):
            info = zipfile.ZipInfo(top + '/' + rel, date_time=ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3  # same header whatever the system the zip is made on
            info.external_attr = 0o644 << 16
            with open(full, 'rb') as f:
                z.writestr(info, f.read())
    return path


def summary(out):
    groups = {'models': [0, 0], 'textures': [0, 0], 'materials': [0, 0], 'icons': [0, 0], 'lua': [0, 0], 'other': [0, 0]}
    for rel, full in walk_files(out):
        if rel.startswith('models/'):
            key = 'models'
        elif rel.endswith('.vtf'):
            key = 'textures'
        elif rel.endswith('.vmt'):
            key = 'materials'
        elif rel.endswith('.png'):
            key = 'icons'
        elif rel.endswith('.lua'):
            key = 'lua'
        else:
            key = 'other'
        groups[key][0] += 1
        groups[key][1] += os.path.getsize(full)
    total_files = sum(g[0] for g in groups.values())
    total_size = sum(g[1] for g in groups.values())
    return groups, total_files, total_size


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=os.path.join(HERE, 'build', L.ADDON_DIRNAME),
                    help='where to put the addon folder (default: build/%s)' % L.ADDON_DIRNAME)
    ap.add_argument('--temp', default=os.path.join(HERE, 'build', '_extract'),
                    help='where to unpack the archives (default: build/_extract)')
    ap.add_argument('--keep-temp', action='store_true',
                    help='keep the unpacked archives (the scripts in tools/ work on that folder, and the next build is faster)')
    ap.add_argument('--original-textures', action='store_true',
                    help='keep the original 4096 px (and uncompressed 2048 px) textures: about 840 MB instead of 270 MB')
    ap.add_argument('--zip', action='store_true', help='also pack the result into <out>.zip')
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    temp = os.path.abspath(args.temp)
    if os.path.basename(out).lower() != os.path.basename(out):
        raise BuildError('the addon folder name must be lower case: %s' % os.path.basename(out))
    if temp == out or temp.startswith(out + os.sep) or out.startswith(temp + os.sep):
        raise BuildError('--out and --temp must be separate folders')
    check_out(out)

    description, extractor = pick_extractor()
    print('Unpacking the archives with %s' % description.strip())
    step_extract(extractor, temp)
    idx = make_vmts.build_index(temp)

    print('Assembling %s' % out)
    step_skeleton(out)
    models, fingers, arm = step_models(idx, out)
    wanted = step_textures(idx, out)
    print('  %d model files, %d textures' % (models, len(wanted)))
    print('  the bare CS:GO arm inside the glove models: %d triangles removed, %d kept '
          '(hands and fingers of the fingerless gloves)' % (arm, fingers))
    if args.original_textures:
        print('  original textures kept (--original-textures)')
    else:
        replaced, saved = step_optimized(extractor, temp, out, wanted)
        print('  %d oversized textures replaced by their 1024 px DXT5 versions (saves %s)' % (replaced, mb(saved)))

    print('Checking')
    problems, vmts = step_verify(out)
    if problems:
        for line in problems[:40]:
            print('  PROBLEM: ' + line)
        if len(problems) > 40:
            print('  ... and %d more' % (len(problems) - 40))
        raise BuildError('the build is not usable, see the problems above')
    print('  %d gloves, %d materials: every model finds its materials and textures' % (len(L.variants()), vmts))

    if not args.keep_temp:
        shutil.rmtree(temp, ignore_errors=True)

    groups, total_files, total_size = summary(out)
    print('')
    print('Done: %s' % out)
    print('  %d files, %s  (%s)' % (total_files, mb(total_size), ', '.join(
        '%s %d' % (key, groups[key][0]) for key in ('models', 'textures', 'materials', 'icons', 'lua') if groups[key][0])))

    if args.zip:
        archive = make_zip(out)
        print('  zip: %s (%s)' % (archive, mb(os.path.getsize(archive))))

    print('')
    print('Install: copy the folder "%s" into  <Steam>/steamapps/common/GarrysMod/garrysmod/addons/' % os.path.basename(out))
    print('on the server AND on every client (or upload it to the Workshop, see README.md).')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except BuildError as err:
        print('')
        print('ERROR: %s' % err)
        sys.exit(err.exit_code)
    except KeyboardInterrupt:
        print('')
        print('interrupted')
        sys.exit(130)
