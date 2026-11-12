#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the ready-to-install Garry's Mod addon "zcity_csgo_gloves".

    python build_addon.py [--out DIR] [--zip] [--original-textures] [--keep-temp]

The repository keeps the heavy content (models, textures) in the .7z / .zip archives it was delivered
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
and, for the Lua of the clothing packs to be run (tools/lua_names.py: the names it builds while
running are found only that way), the lupa module (python -m pip install lupa).
About 1.5 GB of free disk space is used while building; the result is about 270 MB.
"""
import argparse
import collections
import os
import posixpath
import re
import shutil
import struct
import subprocess
import tempfile
import sys
import hashlib
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, 'tools'))

import make_lua_data  # noqa: E402
import make_vmts  # noqa: E402
import mdl_lite  # noqa: E402
import patch_models  # noqa: E402
import vmt  # noqa: E402
import zcg_layout as L  # noqa: E402
import list_content  # noqa: E402
import lua_names  # noqa: E402
import place_content  # noqa: E402
import content_report  # noqa: E402

# reduced versions of the oversized textures (tools/optimize_textures.py), in the addon layout;
# the second archive came with the Driver and Specialist gloves, the third with Sport
OPTIMIZED = ('optimized_textures.7z', 'optimized_textures2.7z', 'optimized_textures3.7z')
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


def extract_zip(archive, dest):
    """ZipFile.extractall with the file names their authors meant (see zcg_layout.zip_name)"""
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            parts = [p for p in L.zip_name(info).replace('\\', '/').split('/') if p not in ('', '.')]
            if not parts or '..' in parts:
                continue
            target = os.path.join(dest, *parts)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(info) as src, open(target, 'wb') as f:
                shutil.copyfileobj(src, f)


def file_stamp(path):
    info = os.stat(path)
    return '%s:%d:%d' % (os.path.basename(path), info.st_size, info.st_mtime_ns)


def is_extracted(dest, stamp):
    marker = os.path.join(dest, MARKER)
    if os.path.isfile(marker):
        with open(marker, 'r', encoding='utf-8') as f:
            return f.read().strip() == stamp
    return False


def extract(extractor, archive, dest, stamp=None):
    """unpack archive into dest unless that was already done for this very file"""
    stamp = stamp or file_stamp(archive)
    marker = os.path.join(dest, MARKER)
    if is_extracted(dest, stamp):
        return False
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    if archive.lower().endswith('.zip'):
        extract_zip(archive, dest)
    else:
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
        # most archives are .7z, the later uploads .zip
        found = [os.path.join(HERE, name + ext) for ext in ('.7z', '.zip') if os.path.isfile(os.path.join(HERE, name + ext))]
        if not found:
            raise BuildError('archive is missing: %s (.7z or .zip)' % os.path.join(HERE, name))
        archive = found[0]
        print('  [%2d/%d] %s' % (i, len(names), os.path.basename(archive)), end='', flush=True)
        fresh = extract(extractor, archive, os.path.join(temp, name))
        print('' if fresh else '  (already unpacked)')


def check_out(out):
    if os.path.exists(out) and not looks_like_old_build(out):
        raise BuildError('%s exists and is not an earlier build of this addon - '
                         'remove it yourself or choose another --out' % out)


def lower_case_content(out):
    """Materials and models that were dropped into the addon folder keep the case their author
    used; the game on Linux and the Workshop packer only take lower-case paths."""
    renamed = 0
    for root in L.CONTENT_ROOTS:
        base = os.path.join(out, root)
        if root == 'lua' or not os.path.isdir(base):
            continue
        wrong = [rel for rel, _full in walk_files(base) if rel != rel.lower()]
        if not wrong:
            continue
        # through a second folder: a rename that only changes the case is no rename on Windows
        stage = base + '.zcg_case'
        os.rename(base, stage)
        for rel, full in sorted(walk_files(stage)):
            target = os.path.join(base, rel.lower())
            if os.path.exists(target):
                raise BuildError('two files differ only in the case of their names: %s/%s' % (root, rel))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            os.replace(full, target)
        shutil.rmtree(stage)
        renamed += len(wrong)
    return renamed


def step_skeleton(out, by_name=False):
    """The addon as it lies in the repository. With by_name the materials and models somebody put
    into its folders by hand are not copied but returned as [(path in the skeleton, file)]:
    step_dropins places them like the content of an archive."""
    skeleton = os.path.join(HERE, L.ADDON_DIRNAME)
    if not os.path.isfile(os.path.join(skeleton, 'addon.json')):
        raise BuildError('addon skeleton is missing: %s' % skeleton)
    check_out(out)
    if os.path.exists(out):
        shutil.rmtree(out)
    by_hand = []

    def not_copied(folder, names):
        skipped = []
        for name in names:
            full = os.path.join(folder, name)
            rel = os.path.relpath(full, skeleton).replace('\\', '/')
            # (what sort_content.bat leaves behind when it is tried on the skeleton itself)
            if rel in (SORT_TOOL_DIR, '_not_used', '_sorting', 'sort_content_report.txt') or name == '__pycache__':
                skipped.append(name)
                continue
            if by_name and os.path.isfile(full) and rel.lower().startswith(('materials/', 'models/')) \
                    and place_content.kind_of(name) and not L.is_own_content(rel):
                by_hand.append((rel, full))
                skipped.append(name)
        return skipped

    shutil.copytree(skeleton, out, ignore=not_copied)
    # the folders those files were in are of no use empty (and may have upper-case names)
    for rel, _full in by_hand:
        folder = os.path.dirname(os.path.join(out, rel))
        while os.path.dirname(folder) != out and os.path.isdir(folder) and not os.listdir(folder):
            os.rmdir(folder)
            folder = os.path.dirname(folder)
    return lower_case_content(out), sorted(by_hand)


DROPIN_PREFIX = '_dropin_'


def dropin_folder(temp, name):
    """where a drop-in archive is unpacked: by its name, so that another archive never finds the
    files of this one there"""
    return os.path.join(temp, DROPIN_PREFIX + hashlib.sha1(name.encode('utf-8')).hexdigest()[:12])


def join_volumes(name, parts, joined):
    """a split archive (x.7z.001, x.7z.002 ...) back in one piece"""
    numbers = [int(L.VOLUME.match(os.path.basename(part)).group(2)) for part in parts]
    if numbers != list(range(1, len(parts) + 1)):
        raise BuildError('%s: its parts must be .001, .002 ... without a gap, found %s'
                         % (name, ', '.join('.%03d' % n for n in numbers)))
    os.makedirs(os.path.dirname(joined), exist_ok=True)
    with open(joined, 'wb') as whole:
        for part in parts:
            with open(part, 'rb') as f:
                shutil.copyfileobj(f, whole, 1 << 20)


def dropin_files(extractor, temp, name, kind, paths):
    """[(path inside a drop-in source, file on the disk)]; an archive is unpacked for that"""
    if kind == 'folder':
        base = paths[0]
    else:
        base = dropin_folder(temp, name)
        stamp = '|'.join(file_stamp(path) for path in paths)
        if not is_extracted(base, stamp):
            archive, joined = paths[0], None
            if kind == 'volumes':
                archive = joined = base + os.path.splitext(name)[1].lower()
                join_volumes(name, paths, joined)
            try:
                extract(extractor, archive, base, stamp)
            except BuildError:
                raise
            except Exception as err:    # whatever the unpacker says about a broken archive
                raise BuildError('%s cannot be unpacked: %s' % (name, err))
            finally:
                if joined and os.path.isfile(joined):
                    os.remove(joined)
    return [(rel, full) for rel, full in sorted(walk_files(base)) if rel != MARKER]


def forget_old_dropins(temp, sources):
    """unpacked archives that are not in the repository any more"""
    used = set(os.path.basename(dropin_folder(temp, name)) for name, _kind, _paths in sources)
    if not os.path.isdir(temp):
        return
    for entry in os.listdir(temp):
        if entry.startswith('_dropin') and os.path.splitext(entry)[0] not in used:
            full = os.path.join(temp, entry)
            shutil.rmtree(full) if os.path.isdir(full) else os.remove(full)


def step_dropins(extractor, temp, out, by_hand=()):
    """The other archives and folders of the repository root are parts of other addons: Lua that
    adds clothes to the appearance menu, materials, models (see "Drop-in archives" in
    tools/zcg_layout.py).

    Lua and the like go into the build under the path their folders give them. Materials,
    textures and models are not trusted to lie in the right folders: tools/place_content.py puts
    each of them where the Lua, a model or a material that names it looks for it.

    A file of this addon is never replaced; of two different files with one path the one from
    the source that comes later by name is used - but not of two Lua files: which of two versions
    of a script is meant cannot be told here, and dropping one without a word would lose what it
    adds, so the build stops. Unless the two are known to be versions of one addon
    (zcg_layout.PACK_VERSIONS): then one of them is taken whole and the other is left out whole -
    its Lua and everything else but its materials and models, which are sorted by name and come
    first, so that no file of the version that was taken is replaced by one of them. The entry
    of its source says so ('versions'). by_hand - the materials and models that were put into the
    folders of the addon itself (see step_skeleton) - come last.
    Returns (a report for each source, the Report of place_content, the paths the Lua names,
    what running that Lua told - see run_lua)."""
    report, placed, content, lua = [], {}, [], []
    sources = L.dropin_sources(HERE)
    names = [name for name, _kind, _paths in sources]
    twice = sorted(set(name for name in names if names.count(name) > 1))
    if twice:
        raise BuildError('%s: the archive is in the repository both whole and in parts (.001, .002 ...); '
                         'remove one of the two' % ', '.join(twice))
    forget_old_dropins(temp, sources)

    # the pack of every file (the title in the addon.json above it), and which packs are left out
    # because another version of them is taken
    listed, with_lua = [], set()
    for number, (name, kind, paths) in enumerate(sources, 1):
        files = dropin_files(extractor, temp, name, kind, paths)
        on_disk = dict(files)
        lower = L.lower_names(on_disk)
        titles, of_folder = {}, {}
        for inner, _full in files:
            folder = posixpath.dirname(inner.replace('\\', '/'))
            if folder not in of_folder:
                of_folder[folder] = L.pack_title(lower, lambda path: read_bytes(on_disk[path]), inner)
            titles[inner] = of_folder[folder]
            dest = L.dropin_destination(inner)
            if dest and dest.startswith('lua/') and dest.endswith('.lua'):
                with_lua.add(titles[inner])
        listed.append((number, name, kind, paths, files, titles))
    for title in L.CHOSEN_PACKS:
        if title not in L.version_titles():
            raise BuildError('--pack "%s": no such version is known. The packs that have versions (PACK_VERSIONS in '
                             'tools/zcg_layout.py): %s' % (title, ', '.join('"%s"' % known for known in L.version_titles())))
        if title not in with_lua:
            raise BuildError('--pack "%s": no drop-in source brings the Lua of that pack' % title)
    left = L.versions_left_out(with_lua)
    versions, pack_at = collections.OrderedDict(), {}

    for number, name, kind, paths, files, titles in listed:
        counts = collections.Counter()
        left_out, notes, no_place, mine = 0, [], [], []

        def as_seen(inner):
            """(a folder of the repository root may itself be a numbered copy of materials/ or
            models/ - "materials3": its name belongs to the path then)"""
            return name + '/' + inner if kind == 'folder' else inner

        # (the numbered folders that hold a tree: a file right in one of them is a file of its top)
        trees = L.tree_roots(as_seen(inner) for inner, _full in files if place_content.kind_of(inner))
        for inner, full in files:
            title = titles[inner]
            seen = as_seen(inner)
            if place_content.kind_of(inner):
                # (of a version that is left out: before every other source, so that it replaces nothing)
                content.append(place_content.Item(name, inner, full, L.dropin_destination(inner), 0 if title in left else number,
                                                  L.merged_destination(seen, trees=trees),
                                                  L.merged_destination(seen, mirror=True, trees=trees), L.numbered_folder(seen)))
                continue
            dest = L.dropin_destination(inner)
            if dest is None:
                # a picture, a note in a numbered copy of materials/: it goes along with the content there
                merged = L.merged_destination(seen)
                if merged and merged.split('/', 1)[0] in ('materials', 'models'):
                    dest = merged
            if dest is None:
                left_out += 1
                no_place.append(inner)
                continue
            data = read_bytes(full)
            digest = hashlib.sha1(data).digest()
            if title in left:
                version = versions.get((title, name))
                if version is None:
                    version = versions[(title, name)] = dict(title=title, instead=left[title], source=name, lua={}, other=0)
                    mine.append(version)
                if dest.startswith('lua/') and dest.endswith('.lua'):
                    version['lua'][dest] = data
                else:
                    version['other'] += 1
                continue
            target = os.path.join(out, dest)
            if dest in placed:
                if placed[dest][1] == digest:
                    continue
                if dest.endswith('.lua'):
                    raise BuildError('two drop-in sources bring different Lua files for one place, %s: "%s" and "%s". '
                                     'Only one can be in the addon, and what the other adds would be lost: remove or '
                                     'rename one of the two. (Two versions of one addon? Name their titles - %s and %s - '
                                     'in PACK_VERSIONS of tools/zcg_layout.py: one of them is then taken whole.)'
                                     % (dest, placed[dest][0], name,
                                        '"%s"' % pack_at[dest] if pack_at.get(dest) else 'no addon.json there',
                                        '"%s"' % title if title else 'no addon.json there'))
                notes.append('%s: another version is in %s, the one from here is used' % (dest, placed[dest][0]))
            elif os.path.exists(target):
                notes.append('%s: the file of this addon is kept' % dest)
                continue
            else:
                root = dest.split('/', 1)[0]
                counts[root if root in ('lua', 'materials', 'models') else 'other'] += 1
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, 'wb') as f:
                f.write(data)
            placed[dest] = (name, digest)
            pack_at[dest] = title
            if dest.endswith('.lua'):
                lua.append(data)
        report.append(dict(name=name, kind=kind, parts=len(paths), counts=counts, left_out=left_out, notes=notes,
                           no_place=no_place, versions=mine))
    if by_hand:
        name = L.ADDON_DIRNAME
        trees = L.tree_roots(inner for inner, _full in by_hand)
        for inner, full in by_hand:
            content.append(place_content.Item(name, inner, full, L.dropin_destination(inner), len(sources) + 1,
                                              L.merged_destination(inner, trees=trees),
                                              L.merged_destination(inner, mirror=True, trees=trees), L.numbered_folder(inner)))
        report.append(dict(name=name, kind='folder', parts=1, counts=collections.Counter(), left_out=0, notes=[],
                           no_place=[], versions=[]))

    # a version that was left out, measured against the one that was taken
    for version in versions.values():
        theirs = dict((dest, placed[dest]) for dest, title in pack_at.items() if title == version['instead'])
        version['from'] = sorted(set(source for source, _digest in theirs.values()))
        version['instead_lua'] = sorted(dest for dest in theirs if dest.startswith('lua/') and dest.endswith('.lua'))
        version['same'] = sum(1 for dest, data in version['lua'].items()
                              if dest in placed and placed[dest][1] == hashlib.sha1(data).digest())
        version['differ'] = sum(1 for dest in version['lua'] if dest in placed) - version['same']
        # A Lua file only this version has: the folder of the owner may hold it, from an addon
        # that was built with this version - the new addon is copied over the old one, and
        # nothing is deleted then. An empty file takes its place.
        version['stubs'] = []
        for dest in sorted(version['lua']):
            target = os.path.join(out, dest)
            if dest in placed or os.path.exists(target):
                continue
            data = STUB_LUA % (version['title'], version['instead'])
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, 'w', encoding='ascii', newline='\n') as f:
                f.write(data)
            placed[dest] = ('', hashlib.sha1(data.encode('ascii')).digest())
            version['stubs'].append(dest)

    # what that Lua wants to find in the materials and models folders: what its text spells out,
    # and what it puts into the appearance tables when it is run
    named = set()
    for data in lua:
        named |= list_content.names_in(data.decode('utf-8-sig', 'replace'))
    ran = run_lua(out, list(versions.values())) if lua else dict(result=None, files={}, tried=False, left_out=[])
    ran['only'] = set()
    if ran['result'] is not None:
        ran['only'] = set(ran['result'].names) - named - list_content.stock_names()
        named |= set(ran['result'].names)
        named -= ran['result'].stock
    if named:
        named -= list_content.stock_names()
    # the files only a version that was left out names: they have their places too - a file of
    # that version is not taken for a namesake of the version in the addon - and nobody asks for them
    spare = set()
    for entry in ran['left_out']:
        entry['names'] -= named
        entry['own'] &= named
        spare |= entry['names']

    result = place_content.place(content, named, lambda path: os.path.isfile(os.path.join(out, path)), spare)
    by_name = dict((entry['name'], entry) for entry in report)
    for dest, item in result.placed:
        copy(item.path, os.path.join(out, dest))
        by_name[item.source]['counts'][dest.split('/', 1)[0]] += 1
    for item, _why in result.left_out:
        by_name[item.source]['left_out'] += 1
    return report, result, named, ran


def run_lua(out, versions=()):
    """Runs the Lua of the assembled addon the way the game would (tools/lua_names.py) and reads
    the appearance tables. Returns dict(result = a lua_names.Result, or None where Lua cannot be
    run; files = {path below lua/: text} of the Lua that is not the gloves' own; tried = True).
    What the tables hold then is written into the addon (BOUND_LUA): in the game zcg_content
    compares the tables with it. bound = how many entries that list has.
    versions: the packs that were left out because another version of them is in the addon
    (step_dropins). Each is run once in the place of that one, for the names only it names
    (names) and the names the addon as it is names and it does not (own):
    left_out = [dict(title, instead, source, names, own)]."""
    bound = os.path.join(out, 'lua', BOUND_LUA)
    if os.path.isfile(bound):
        os.remove(bound)
    everything = lua_names.folder_files(os.path.join(out, 'lua'))
    files = dict((path, text) for path, text in everything.items() if not lua_names.is_own(path))
    result = lua_names.run_addon(everything)[0] if lua_names.available() else None
    listed = 0
    titles = dict((path, title) for path, title in list_content.pack_titles(HERE).items() if path in files)

    used = set()
    for text in files.values():
        used |= list_content.names_in(text)
    if result is not None:
        used |= set(result.names)
        used -= result.stock
    used -= list_content.stock_names()
    left_out = []
    for version in versions:
        theirs = dict((dest[len('lua/'):], lua_names.lua_text(data)) for dest, data in version['lua'].items())
        instead = set(dest[len('lua/'):] for dest in version['instead_lua'])
        names = list_content.other_version_names(everything, instead, theirs, text_only=result is None)
        names -= list_content.stock_names()
        left_out.append(dict(title=version['title'], instead=version['instead'], source=version['source'],
                             names=names - used, own=used - names))

    if result is not None:
        by_file = bound_entries(result)
        listed = sum(len(entries) for entries in by_file.values())
        if listed:
            write_bound(bound, by_file, titles, left_out)
            check_bound(bound, by_file, everything)
    return dict(result=result, files=files, tried=True, bound=listed, titles=titles, left_out=left_out)


# what stands at the place of a Lua file that only a left-out version of a pack has
STUB_LUA = ('-- Left empty on purpose by build_addon.py.\n'
            '-- "%s" has a Lua file here. This addon was built with "%s" instead - another version of the\n'
            '-- same addon, which has none. The empty file is here to replace that one in a folder that was\n'
            '-- updated by copying the new addon over the old one.\n')


# the entries of the appearance tables that the Lua of the clothing packs makes, for the game
BOUND_LUA = L.ADDON_DIRNAME + '/sh_bound.lua'


def lua_string(text):
    """a Lua string literal for a text of Lua (lua_names.lua_text): the same bytes, written in
    plain ASCII - whatever encoding the name of a piece of clothing has, it arrives as it was"""
    out = []
    for byte in bytearray(lua_names.lua_bytes(text)):
        c = chr(byte)
        if c in '\\"':
            out.append('\\' + c)
        elif 32 <= byte < 127:
            out.append(c)
        else:
            out.append('\\%03d' % byte)
    return '"' + ''.join(out) + '"'


def bound_entries(result):
    """{Lua file: [(entry, value, side)]} - side None: on both sides, 1: on the server only,
    2: on the clients only. Without what is only added when its file is installed."""
    server, client = result.entries.get('server', {}), result.entries.get('client', {})
    by_file = {}
    for entry in sorted(set(server) | set(client)):
        if entry in result.if_installed:
            continue
        if server.get(entry) == client.get(entry):
            value, by = server[entry]
            by_file.setdefault(by, []).append((entry, value, None))
            continue
        for side, table in ((1, server), (2, client)):
            if entry in table:
                value, by = table[entry]
                by_file.setdefault(by, []).append((entry, value, side))
    return by_file


def check_bound(path, by_file, lua_files):
    """The list is for the check of the addon itself (ZCG.BoundMissing in sh_content.lua): run the
    Lua once more, let that check read the file as written and see that it finds every entry -
    a list the game reads differently from the way it was meant would cry wolf on every server."""
    with open(path, 'rb') as f:
        text = lua_names.lua_text(f.read())
    result = lua_names.run_addon(lua_files, bound=text)[0]
    for number, realm in enumerate(lua_names.REALMS, 1):
        want = sum(1 for entries in by_file.values() for _entry, _value, side in entries if side in (None, number))
        count, missing = result.bound.get(realm, (None, []))
        if count != want or missing:
            raise BuildError('%s does not say what it was written to say: read back on the %s, the check of the addon '
                             'looks for %s entries of %d and does not find %d of them%s. This is a fault of '
                             'build_addon.py or tools/lua_names.py, not of the Lua.'
                             % (BOUND_LUA, realm, count, want, len(missing),
                                ', such as %r' % (missing[0][0],) if missing else ''))


def write_bound(path, by_file, titles=None, left_out=()):
    """by_file: bound_entries(); titles: {Lua file: the title of the pack it came with};
    left_out: the versions of packs that are not in the addon, each with the names only it names"""
    lines = [
        '-- Written by build_addon.py; made anew with every build of the addon.',
        '--',
        '-- What the Lua of the clothing packs in this addon puts into the appearance tables of Z-City when a',
        '-- game starts - found by running that Lua while the addon was built (tools/lua_names.py):',
        '--     Lua file = { { where in the tables, the value [, 1 = on the server only, 2 = on clients only] }, ... }',
        '-- The console command zcg_content compares the tables of the running game with this list. An entry',
        '-- that is not there was lost on the way: its Lua file did not load, or something made the table anew.',
        '',
        'ZCGloves.Bound = {',
    ]
    for by in sorted(by_file):
        lines.append('\t[%s] = {' % lua_string(by))
        for entry, value, side in by_file[by]:
            lines.append('\t\t{ %s, %s%s },' % (lua_string(entry), lua_string(value), '' if side is None else ', %d' % side))
        lines.append('\t},')
    lines.append('}')
    def text(value):
        # (a title is text: written as UTF-8, which is what the console of the game shows)
        return lua_string(lua_names.lua_text((u'%s' % value).encode('utf-8')))

    named = sorted(by for by in by_file if (titles or {}).get(by))
    if named:
        lines += ['', '-- the packs these Lua files came with: zcg_content names them next to a missing file', 'ZCGloves.BoundPacks = {']
        for by in named:
            lines.append('\t[%s] = %s,' % (lua_string(by), text(titles[by])))
        lines.append('}')
    if left_out:
        lines += ['',
                  '-- Packs whose Lua is NOT in this addon: each is another version of a pack that is, and the game can',
                  '-- only have one of the two (zcg_layout.PACK_VERSIONS). pack = the pack that is here instead.',
                  'ZCGloves.BoundLeftOut = {']
        for entry in sorted(left_out, key=lambda entry: entry['title']):
            lines.append('\t[%s] = %s,' % (text(entry['title']), text(entry['instead'])))
        lines += ['}',
                  '-- the files only such a pack names: the game does not need them with this addon',
                  'ZCGloves.BoundOther = {']
        for entry in sorted(left_out, key=lambda entry: entry['title']):
            for name in sorted(entry['names']):
                lines.append('\t[%s] = %s,' % (lua_string(name), text(entry['title'])))
        lines += ['}',
                  '-- the files this addon names and such a pack does not: which of the two kinds is installed tells',
                  '-- which version the content on this computer belongs to',
                  'ZCGloves.BoundOnly = {']
        for entry in sorted(left_out, key=lambda entry: entry['title']):
            for name in sorted(entry.get('own', ())):
                lines.append('\t[%s] = %s,' % (lua_string(name), text(entry['title'])))
        lines.append('}')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='ascii', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


# sort_content.bat of the skeleton does on the computer of the addon's owner what step_dropins
# does here: it runs these scripts, which the build puts next to it
SORT_TOOL_DIR = 'sort_content'
SORT_TOOL = ('sort_content.py', 'place_content.py', 'content_report.py', 'list_content.py', 'glua.py',
             'zcg_layout.py', 'vmt.py', 'game_files.py')


def step_sort_tool(out, ran=None):
    """The scripts of sort_content.bat with two lists, because the tool has neither z_city.zip nor
    a Lua to run where it works:
      * the files Z-City names itself - it must not go looking for them among the content;
      * the names the Lua of the addon puts into the appearance tables when it is run (ran: what
        run_lua returned) - the text of the Lua does not show all of them.
    Returns (scripts, names in the first list, names in the second one or None)."""
    dest = os.path.join(out, SORT_TOOL_DIR)
    for name in SORT_TOOL:
        copy(os.path.join(HERE, 'tools', name), os.path.join(dest, name))
    result = ran['result'] if ran else None
    stock = set(list_content.stock_names())
    if result is not None:
        stock |= result.stock
    with open(os.path.join(dest, list_content.STOCK_LIST), 'w', encoding='utf-8', newline='\n') as f:
        f.write('# Materials, models and sounds that the Lua of Z-City names itself (read out of z_city.zip by\n'
                '# build_addon.py). They come with the gamemode: sort_content.py does not ask for them.\n')
        f.write('\n'.join(sorted(stock)) + '\n')
    listed = None
    if ran and ran['tried']:
        names = set(result.names) - stock if result is not None else set()
        by = dict((name, result.names[name]['by']) for name in names)
        list_content.write_run_list(os.path.join(dest, list_content.RUN_LIST), names, ran['files'], ran=result is not None,
                                    failed=lua_failed(ran), by=by, titles=ran.get('titles'),
                                    left_out=[(entry['title'], entry['instead'], entry['names'] - stock,
                                               entry.get('own', set()) - stock)
                                              for entry in ran.get('left_out', ())])
        listed = len(names)
    return len(SORT_TOOL), len(stock), listed


# The Lua of the versions that were left out goes into the addon as well, beside the scripts of
# sort_content.bat: when the content of the owner turns out to be that of such a version, the tool
# puts its Lua in place - nobody has to know which archive of a release to take.
VERSIONS_DIR = 'versions'       # (sort_content.VERSIONS)
VERSIONS_INDEX = 'index.txt'


def version_folder(title):
    return re.sub(r'[^a-z0-9]+', '_', title.lower()).strip('_') or 'version'


def step_versions(out, temp, args, left_out):
    """left_out: the versions that are not in the addon (what run_lua tells: title, instead).
    Builds the addon once more with each of them, into a folder that goes away again, and keeps
    the files that differ - those of that build and those of this one - by their paths in the
    addon below sort_content/versions/<folder of the version>/.
    Returns [(title, folder, files)], the version in the addon first."""
    base = os.path.join(out, SORT_TOOL_DIR, VERSIONS_DIR)
    if os.path.isdir(base):
        shutil.rmtree(base)
    kept = {}       # title -> {path: bytes}
    order = []
    for entry in left_out:
        title, mine = entry['title'], entry['instead']
        group = [g for g in L.PACK_VERSIONS if title in g]
        others = [t for t in L.CHOSEN_PACKS if not group or t not in group[0]]
        scratch = tempfile.mkdtemp(prefix='zcg_version_', dir=os.path.dirname(out))
        try:
            other_out = os.path.join(scratch, os.path.basename(out))
            cmd = [sys.executable, os.path.abspath(__file__), '--out', other_out, '--temp', temp, '--keep-temp',
                   '--no-versions', '--pack', title]
            for t in others:
                cmd += ['--pack', t]
            if args.original_textures:
                cmd.append('--original-textures')
            proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if proc.returncode != 0:
                tail = proc.stdout.decode('utf-8', 'replace').strip().splitlines()[-15:]
                raise BuildError('the build with "%s" (for %s/%s) failed:\n    %s'
                                 % (title, SORT_TOOL_DIR, VERSIONS_DIR, '\n    '.join(tail)))
            here = dict(walk_files(out))
            there = dict(walk_files(other_out))
            uneven = sorted(set(here) ^ set(there))
            if uneven:
                # (a file only one version has would have to be deleted on a switch: the builds put
                # an empty file at such a place instead, see EMPTY_LUA)
                raise BuildError('the builds with "%s" and with "%s" do not have the same files, so one cannot be '
                                 'switched to the other:\n    %s' % (mine, title, '\n    '.join(uneven[:20])))
            for rel in sorted(here):
                a, b = read_bytes(here[rel]), read_bytes(there[rel])
                if a != b:
                    kept.setdefault(mine, {})[rel] = a
                    kept.setdefault(title, {})[rel] = b
            for t in (mine, title):
                if t not in order:
                    order.append(t)
        finally:
            shutil.rmtree(scratch, ignore_errors=True)
    # (a version takes part in every switch with the same files)
    every = sorted(set(rel for files in kept.values() for rel in files))
    done = []
    for title in order:
        folder = version_folder(title)
        if folder in [f for _t, f, _n in done]:
            raise BuildError('two versions would share the folder %s/%s/%s' % (SORT_TOOL_DIR, VERSIONS_DIR, folder))
        for rel in every:
            data = kept[title].get(rel)
            if data is None:
                data = read_bytes(os.path.join(out, rel))    # the same in this build and in that one
            dest = os.path.join(base, folder, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, 'wb') as f:
                f.write(data)
        done.append((title, folder, len(every)))
    if done:
        with open(os.path.join(base, VERSIONS_INDEX), 'w', encoding='utf-8', newline='\n') as f:
            f.write('# The versions this addon can be switched to by sort_content.bat (it does so itself when the\n'
                    '# content is that of another version; by hand: sort_content.bat --use-version <title>).\n'
                    '# Each folder holds, by their paths in the addon, the files that differ between the versions.\n'
                    '# <folder><tab><title>\n')
            for title, folder, _files in done:
                f.write('%s\t%s\n' % (folder, title))
    return done


def version_lines(versions, ran):
    """what the build says about the packs of a source that were left out because another version
    of them is in the addon (step_dropins)"""
    out = []
    names = dict((entry['title'], entry['names']) for entry in ran.get('left_out', ()))
    for version in versions:
        spare = names.get(version['title'], ())
        out.append('      NOT TAKEN: "%s" is another version of "%s" (%s). Both bring the same Lua files'
                   % (version['title'], version['instead'], ', '.join(version['from']) or '?'))
        out.append('          (%d of its %d differ), and the game can only have one of the two. The addon is built with'
                   % (version['differ'], len(version['lua'])))
        out.append('          "%s", whole; the %d Lua files of this one%s are left out, whole.'
                   % (version['instead'], len(version['lua']),
                      ' and %d other files' % version['other'] if version['other'] else ''))
        if spare:
            first = sorted(spare)[0]
            out.append('          %d materials and models are named by this version only, such as %s:' % (len(spare), first))
            out.append('          the game does not need them with this addon. sort_content.bat knows them, so as not to take')
            out.append('          such a file for a namesake that is needed.')
        for dest in version['stubs']:
            out.append('          %s: only this version has that file. An empty one is put there: it replaces the file in a'
                       % dest)
            out.append('          folder that was updated by copying the new addon over the old one.')
        out.append('          To build with this version instead:  build_addon.bat --pack "%s"' % version['title'])
    return out


def lua_failed(ran):
    """{Lua file: the error} - the Lua of the clothing packs that stopped with an error when it was run"""
    failed = {}
    if ran['result'] is not None:
        for _realm, name, message in ran['result'].errors:
            if name in ran['files']:
                failed.setdefault(name, message.split('\n')[0])
    return failed


def lua_run_lines(ran):
    """what running the Lua told, for the screen"""
    if not ran['tried']:
        return []
    result = ran['result']
    if result is None:
        return ['  NOT RUN: the Lua of the clothing packs could not be run here - the lupa module is missing',
                '      (python -m pip install lupa). Names that Lua puts together while running, or writes from',
                '      inside the materials folder, stay unknown to sort_content.bat: it may take such a file for',
                '      a namesake of another pack.']
    out = []
    only = sorted(ran['only'])
    out.append('  that Lua was run (tools/lua_names.py): %d of these names are not to be read in its text%s'
               % (len(only), ', such as %s' % only[0] if only else ''))
    if ran.get('bound'):
        out.append('      the %d clothes, faces, models and accessories it puts into the appearance tables are written into'
                   % ran['bound'])
        out.append('      lua/%s: in the game zcg_content tells which of them are not there' % BOUND_LUA)
    # a name one file of a pack put into the tables and a later file replaced or dropped
    stock = set(lua_names.stock_files())
    lost = [entry for entry in result.lost if entry['by'] not in stock]
    if lost:
        out.append('      note: %d names that one Lua file puts into the appearance tables are replaced or dropped '
                   'by a later one (python tools/lua_names.py):' % len(lost))
        by_pair = collections.OrderedDict()
        for entry in lost:
            by_pair.setdefault((entry['by'], entry['during']), []).append(entry)
        for (by, during), entries in by_pair.items():
            first = entries[0]
            out.append('          %s -> %s: %d, such as %s (%s)%s'
                       % (by, during, len(entries), first['path'], first['who'],
                          ', now %s' % first['now'] if first['now'] else ', dropped'))
    for realm, name, message in result.errors[:10]:
        out.append('  STOPPED WITH AN ERROR: %s, run as the %s: %s' % (name, realm, message.split('\n')[0]))
    if len(result.errors) > 10:
        out.append('      ... and %d more' % (len(result.errors) - 10))
    if result.errors:
        out.append('      What such a file adds after that place is in no list - and not in the game either, if the game')
        out.append('      stops there too (the imitation of the game in tools/lua_names.lua may be what is wrong).')
        out.append('      sort_content.bat tells the owner of the addon about it.')
    return out


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


def step_verify(out, foreign=()):
    """model -> material -> VMT -> texture, the Lua catalogue and the icons.
    foreign: files of other addons (step_dropins) - they are reported there, not judged here"""
    problems = []
    foreign = set(foreign)
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
        rel = os.path.relpath(path, out).replace('\\', '/')
        if rel not in foreign:
            check_vmt(rel)
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


def zip_path(out):
    """where the archive of the addon in out goes: <out>.zip - with the ending of its version
    when the build was told to take one that has an archive of its own in a release
    (L.VERSION_ZIPS: build/zcity_csgo_gloves_legacy.zip), so that it does not replace the other"""
    ending = L.build_zip_name()[len(L.ADDON_DIRNAME):]
    return out + ending


def make_zip(out, path=None):
    """<out>.zip (or path) with the addon folder inside; byte for byte the same for the same content"""
    path = path or out + '.zip'
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
        elif rel.endswith('.lua') and rel.startswith('lua/'):
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
                    help='keep the original 4096 px (and uncompressed 2048 px) textures: about 1020 MB instead of 364 MB')
    ap.add_argument('--gloves-only', action='store_true',
                    help='leave out the drop-in archives (the Lua, materials and models of other addons that lie '
                         'in the repository root): the gloves alone, as up to version 1.3.0')
    ap.add_argument('--pack', action='append', default=[], metavar='TITLE',
                    help='of the drop-in packs that are versions of one addon - they bring the same Lua files, and the '
                         'game can only have one (PACK_VERSIONS in tools/zcg_layout.py) - take this one, by the title in '
                         'its addon.json: --pack "Z-City Appearance Mod LEGACY". By default the first one listed there.')
    ap.add_argument('--no-versions', action='store_true',
                    help='do not put the Lua of the versions that were left out beside sort_content.bat '
                         '(sort_content/versions): the addon then cannot switch to them by itself')
    ap.add_argument('--zip', action='store_true',
                    help='also pack the result into <out>.zip (with --pack "Z-City Appearance Mod LEGACY": <out>_legacy.zip)')
    args = ap.parse_args()
    L.CHOSEN_PACKS[:] = args.pack

    # archive names are not always ASCII; a console that cannot show them must not stop the build
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='replace')

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
    renamed, by_hand = step_skeleton(out, by_name=not args.gloves_only)
    if renamed:
        print('  %d files in the materials / models folders of the addon got lower-case paths' % renamed)
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

    foreign = ()
    left_out = ()
    # (the report of a build that was told to take a version with an archive of its own is named after
    # it, like the archive: content_report_legacy.txt - it does not replace the report of the other build)
    listing = os.path.join(os.path.dirname(out), 'content_report%s.txt' % zip_path('')[:-len('.zip')])
    if os.path.isfile(listing):
        os.remove(listing)      # of an earlier build; written again below when there is content
    for name in L.unread_archives(HERE):
        print('  NOT USED: %s - only .zip and .7z archives are read (whole, or split by 7-Zip into .001 .002 ...)' % name)
    if args.gloves_only:
        print('  drop-in archives left out (--gloves-only)')
        bat = os.path.join(out, 'sort_content.bat')     # nothing to sort without the clothes
        if os.path.isfile(bat):
            os.remove(bat)
    else:
        sources, content, named, ran = step_dropins(extractor, temp, out, by_hand)
        left_out = ran.get('left_out', ()) if ran else ()
        scripts, stock, listed = step_sort_tool(out, ran)
        print('  sort_content.bat: %d scripts, %d names of Z-City itself that it leaves alone%s'
              % (scripts, stock, '' if listed is None else ", %d names the addon's Lua gives when it is run" % listed))
        foreign = [dest for dest, _item in content.placed]
        for entry in sources:
            counts = entry['counts']
            parts = ['%d %s' % (counts[key], label) for key, label in (
                ('lua', 'Lua files'), ('materials', 'material files'), ('models', 'model files'), ('other', 'other files'))
                if counts[key]]
            label = entry['name'] + ('/' if entry['kind'] == 'folder' else '')
            if entry['kind'] == 'volumes':
                label += ' (%d parts)' % entry['parts']
            left = ''
            if entry['left_out']:
                left = ' (%d files without a place in an addon left out' % entry['left_out']
                if entry['no_place']:
                    left += ': ' + ', '.join(entry['no_place'][:3]) + (' ...' if len(entry['no_place']) > 3 else '')
                left += ')'
            nothing = 'NOTHING for the addon - no Lua, no materials, no models'
            if entry['versions'] and not parts:
                nothing = 'NOT TAKEN, see below'
            print('  drop-in %s: %s%s' % (label, ', '.join(parts) or nothing, left))
            for line in version_lines(entry['versions'], ran):
                print(line)
            for note in entry['notes'][:10]:
                print('      note: ' + note)
            if len(entry['notes']) > 10:
                print('      ... and %d more notes' % (len(entry['notes']) - 10))
        if named:
            present = sum(1 for name in named if os.path.isfile(os.path.join(out, name)))
            print('  the drop-in Lua names %d materials and models of its own: %d are in the addon, %d are not '
                  '(python tools/list_content.py)' % (len(named), present, len(named) - present))
        for line in lua_run_lines(ran):
            print(line)
        if content.placed or content.left_out:
            moves = sorted(content.moves.items(), key=lambda kv: (-kv[1], kv[0]))
            if moves:
                print('  %d content files were not where the game looks for them and were put there:'
                      % sum(content.moves.values()))
            for (source, src, dst), count in moves[:12]:
                print('      %s  ->  %s/  (%d files)' % (content_report.moved_from(sources, source, src), dst, count))
            if len(moves) > 12:
                print('      ... and %d more folders' % (len(moves) - 12))
            for note in content.notes[:10]:
                print('      note: ' + note)
            if len(content.notes) > 10:
                print('      ... and %d more notes' % (len(content.notes) - 10))
            materials = sum(1 for dest, _item in content.placed if dest.endswith('.vmt'))
            print('  content: %d models name %d materials, %d of them have no file; '
                  '%d materials name %d textures, %d of them have no file'
                  % (content.models, content.materials_wanted, len(content.missing_materials),
                     materials, content.textures_wanted, len(content.missing_textures)))
            content_report.write(listing, sources, content, named, 'build_addon.py', spare=dict(
                (name, entry['title']) for entry in ran.get('left_out', ()) for name in entry['names']))
            print('      (a name without a file may be a part of the game or of Z-City; the lists are in %s)' % listing)

    print('Checking')
    problems, vmts = step_verify(out, foreign)
    if problems:
        for line in problems[:40]:
            print('  PROBLEM: ' + line)
        if len(problems) > 40:
            print('  ... and %d more' % (len(problems) - 40))
        raise BuildError('the build is not usable, see the problems above')
    print('  %d gloves, %d materials: every model finds its materials and textures' % (len(L.variants()), vmts))

    if left_out and not args.no_versions:
        print('Versions')
        for title, folder, files in step_versions(out, temp, args, left_out):
            print('  %s/%s/%s/: %d files of "%s"%s' % (SORT_TOOL_DIR, VERSIONS_DIR, folder, files, title,
                                                      '' if title in [e['title'] for e in left_out] else '  (the one in place)'))
        print('  sort_content.bat puts the Lua of the version the content belongs to in place by itself')

    if not args.keep_temp:
        shutil.rmtree(temp, ignore_errors=True)

    groups, total_files, total_size = summary(out)
    print('')
    print('Done: %s' % out)
    print('  %d files, %s  (%s)' % (total_files, mb(total_size), ', '.join(
        '%s %d' % (key, groups[key][0]) for key in ('models', 'textures', 'materials', 'icons', 'lua') if groups[key][0])))

    if args.zip:
        archive = make_zip(out, zip_path(out))
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
