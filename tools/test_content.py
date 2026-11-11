#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests of tools/place_content.py and of the way build_addon.py reads drop-in content.

    python tools/test_content.py

Made-up files in a temporary folder: materials that name textures, models that name materials,
packed the wrong way round in the ways that were met in practice. The names the tests look for
are the real ones - those the Lua of the drop-in archives of this repository names.

The last test makes up whole games at random, packs each in the ways people pack content, and
compares where every file ends up with where it came from (see test_random_packings).
"""
import collections
import contextlib
import io
import os
import random
import shutil
import struct
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)
import build_addon  # noqa: E402
import content_report  # noqa: E402
import list_content  # noqa: E402
import place_content as P  # noqa: E402
import sort_content  # noqa: E402
import zcg_layout as L  # noqa: E402

CHECKS = [0, 0]


def check(ok, text):
    CHECKS[0] += 1
    if not ok:
        CHECKS[1] += 1
        print('  FAILED: ' + text)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data if isinstance(data, bytes) else data.encode('utf-8'))


def material(base, **more):
    lines = ['"VertexLitGeneric"', '{', '\t"$basetexture" "%s"' % base]
    lines += ['\t"$%s" "%s"' % (key, value) for key, value in sorted(more.items())]
    return '\r\n'.join(lines + ['}', ''])


def texture(name):
    return b'VTF\x00' + name.encode('utf-8')


def model(folders, names, name=''):
    """the least a studio model needs to name its materials (and itself)"""
    head = bytearray(408)
    head[0:4] = b'IDST'
    struct.pack_into('<i', head, 4, 48)
    head[12:12 + len(name)] = name.encode('latin-1')
    at = 408
    folders_at = at + 64 * len(names)
    strings_at = folders_at + 4 * len(folders)
    body, strings = bytearray(strings_at - 408), bytearray()
    for i, name in enumerate(names):
        entry = at + i * 64
        struct.pack_into('<i', body, entry - 408, strings_at + len(strings) - entry)
        strings += name.encode('latin-1') + b'\x00'
    for i, folder in enumerate(folders):
        struct.pack_into('<i', body, folders_at - 408 + i * 4, strings_at + len(strings))
        strings += folder.encode('latin-1') + b'\x00'
    struct.pack_into('<4i', head, 204, len(names), at, len(folders), folders_at)
    return bytes(head + body + strings)


def scan(folder, source='content.zip', order=1):
    return [P.Item(source, rel, full, L.dropin_destination(rel), order)
            for rel, full in sorted(build_addon.walk_files(folder))]


def run(folder, named=(), own=(), **kw):
    items = scan(folder, **kw) if isinstance(folder, str) else folder
    report = P.place(items, set(named), lambda path: path in own)
    return report, dict(report.placed)


def text_of(item):
    with open(item.path, 'rb') as f:
        return f.read().decode('latin-1')


def named_by_the_lua():
    named = set()
    for _archive, _title, wanted in list_content.collect()[0]:
        named.update(wanted)
    return named


# the folder of the user: these folders of materials/models lay one level up, in materials
SHIFTED = ('gate/', 'roscoe/', 'gregrogers/', 'bloo_ltcom_zel/', 'humans/slav/', 'humans/modern/')


def as_the_user_packed_it(path):
    if path.startswith('materials/models/'):
        tail = path[len('materials/models/'):]
        if tail.startswith(SHIFTED) or tail.endswith('/cub_facemap.vmt') or tail.endswith('/cub_facemap.vtf'):
            return 'materials/' + tail
    return path


def supply(folder, named, where):
    """a material with its texture for every named material, a model for every named model"""
    for name in sorted(named):
        if name.endswith('.vmt'):
            base = name[len('materials/'):-len('.vmt')]
            more = {'bumpmap': base + '_nrm'} if base.endswith('napapijri_jacket') else {}
            write(os.path.join(folder, where(name)), material(base, **more))
            write(os.path.join(folder, where(name[:-4] + '.vtf')), texture(base))
            if more:
                write(os.path.join(folder, where(name[:-4] + '_nrm.vtf')), texture(base + '_nrm'))
        elif name.endswith('.mdl'):
            write(os.path.join(folder, where(name)), model([], [], name[len('models/'):]))
            for ext in ('.vvd', '.dx90.vtx', '.phy'):
                write(os.path.join(folder, where(name[:-4] + ext)), b'part of ' + name.encode('utf-8'))


def right_files(placed, named, label):
    wrong = []
    for name in sorted(named):
        item = placed.get(name)
        if name.endswith('.vmt'):
            base = name[len('materials/'):-4]
            if item is None or ('"$basetexture" "%s"' % base) not in text_of(item):
                wrong.append(name)
            tex = placed.get(name[:-4] + '.vtf')
            if tex is None or text_of(tex) != texture(base).decode('latin-1'):
                wrong.append(name[:-4] + '.vtf')
        elif name.endswith('.mdl'):
            if item is None:
                wrong.append(name)
            for ext in ('.vvd', '.dx90.vtx', '.phy'):
                part = placed.get(name[:-4] + ext)
                if part is None or text_of(part) != 'part of ' + name:
                    wrong.append(name[:-4] + ext)
    check(not wrong, '%s: %d files are not at their names, e.g. %s' % (label, len(wrong), wrong[:3]))


def test_the_folder_of_the_user(tmp, named):
    src = os.path.join(tmp, 'user')
    supply(src, named, lambda name: u'content \u2014 \u043a\u043e\u043f\u0438\u044f/' + as_the_user_packed_it(name))
    top = os.path.join(src, u'content \u2014 \u043a\u043e\u043f\u0438\u044f', 'materials')
    # what only the models name (and the models are not here): a folder next to the named ones,
    # a folder of its own whose materials say where they belong, and one that says nothing
    write(os.path.join(top, 'humans/slav/skin/face_d.vtf'), texture('face'))
    write(os.path.join(top, 'adodser/vest/vest.vmt'), material('models/adodser/vest/vest'))
    write(os.path.join(top, 'adodser/vest/vest.vtf'), texture('vest'))
    write(os.path.join(top, 'adodser/boots.vmt'), material('models/adodser/boots_d'))
    write(os.path.join(top, 'adodser/boots_d.vtf'), texture('boots'))
    write(os.path.join(top, 'silent/thing.vtf'), texture('thing'))
    report, placed = run(src, named)
    check('materials/models/humans/slav/skin/face_d.vtf' in placed, 'a folder nobody names goes with the folder above it')
    for name in ('vest/vest.vmt', 'vest/vest.vtf', 'boots.vmt', 'boots_d.vtf'):
        check('materials/models/adodser/' + name in placed, 'materials that say where they belong: ' + name)
    check('materials/silent/thing.vtf' in placed, 'a folder that says nothing stays where it was packed')
    for name in ('face_d.vtf', 'vest.vmt', 'vest.vtf', 'boots.vmt', 'boots_d.vtf', 'thing.vtf'):
        for dest in [d for d in placed if d.endswith('/' + name)]:
            del placed[dest]
    shutil.rmtree(os.path.join(top, 'adodser'))
    shutil.rmtree(os.path.join(top, 'silent'))
    shutil.rmtree(os.path.join(top, 'humans/slav/skin'))
    report, placed = run(src, named)
    right_files(placed, named, 'folders one level up')
    check(not report.missing_named, 'folders one level up: %d names without a file' % len(report.missing_named))
    check(not report.missing_textures, 'folders one level up: %d textures without a file' % len(report.missing_textures))
    check(not report.left_out, 'folders one level up: %d files left out' % len(report.left_out))
    check('materials/models/gate/napapijri_jacket_nrm.vtf' in placed, 'a second texture follows its material')
    stray = [dest for dest in placed if dest.startswith(('materials/gate/', 'materials/humans/', 'materials/roscoe/',
                                                         'materials/gregrogers/', 'materials/bloo_ltcom_zel/'))]
    check(not stray, 'nothing stays one level up: %s' % stray[:3])
    check(len(placed) == len(set(id(item) for item in placed.values())), 'no file is copied twice')
    moved = dict(((src_, dst), n) for (_source, src_, dst), n in report.moves.items())
    top = u'content \u2014 \u043a\u043e\u043f\u0438\u044f/materials/'
    for folder in ('gate', 'roscoe', 'gregrogers', 'bloo_ltcom_zel', 'humans'):
        check((top + folder, 'materials/models/' + folder) in moved, 'the report says that %s was moved' % folder)
    check(len(moved) == 5, 'five folders were moved, the report has %d' % len(moved))
    # armbands lie in materials/zcbands41 and stay there
    check('materials/zcbands41/band_team.vmt' in placed, 'a folder that was right stays')

    # one of four files with the same name is not there: its namesakes are not used for it
    gone = 'materials/models/humans/male/group02/cub_facemap'
    for ext in ('.vmt', '.vtf'):
        os.remove(os.path.join(src, u'content \u2014 \u043a\u043e\u043f\u0438\u044f', as_the_user_packed_it(gone + ext)))
    report, placed = run(src, named)
    check(report.missing_named == [gone + '.vmt'], 'a missing file is reported: %s' % report.missing_named[:3])
    check(gone + '.vmt' not in placed, 'a missing file is not replaced by a namesake')
    right_files(placed, named - {gone + '.vmt'}, 'the other three namesakes')


def test_numbered_folders(tmp, named):
    # "material 1", "material 2" ...: one folder for every folder of the game, files without folders
    folders = sorted(set(os.path.dirname(name) for name in named))
    number = dict((folder, i) for i, folder in enumerate(folders, 1))
    src = os.path.join(tmp, 'numbered')
    supply(src, named, lambda name: 'material %d/%s' % (number[os.path.dirname(name)], os.path.basename(name))
           if name.startswith('materials/') else 'model %d/%s' % (number[os.path.dirname(name)], os.path.basename(name)))
    report, placed = run(src, named)
    right_files(placed, named, 'numbered folders')
    check(not report.missing_named and not report.missing_textures, 'numbered folders: nothing is missing')
    check(not report.left_out, 'numbered folders: %d files left out' % len(report.left_out))
    check(not report.notes, 'numbered folders: no doubts, got %s' % report.notes[:2])

    # only the folders at the top got numbers, what is inside them is as it was:
    # materials/models/humans/slav/... -> "material 8/slav/...". And the same once more with the
    # materials and the textures apart: "material 8" holds the .vmt, "texture 8" the .vtf
    def top_of(name):
        parts = name.split('/')
        cut = 3 if parts[:2] == ['materials', 'models'] else 2
        return '/'.join(parts[:cut]), '/'.join(parts[cut:])

    number = dict((top, i) for i, top in enumerate(sorted(set(top_of(name)[0] for name in named)), 1))

    def renamed(name, apart=False):
        top, rest = top_of(name)
        kind = 'model' if name.startswith('models/') else 'texture' if apart and name.endswith('.vtf') else 'material'
        return '%s %d/%s' % (kind, number[top], rest)

    for label, where in (('numbered top folders', renamed),
                         ('materials and textures apart', lambda name: renamed(name, True))):
        src = os.path.join(tmp, label.replace(' ', '_'))
        supply(src, named, where)
        report, placed = run(src, named)
        right_files(placed, named, label)
        check(not report.missing_named and not report.missing_textures and not report.left_out and not report.notes,
              '%s: nothing missing, left out or doubted: %s' % (label, report.notes[:2]))


def test_one_heap(tmp):
    src = os.path.join(tmp, 'heap')
    write(os.path.join(src, 'stuff/x.vmt'), material('elsewhere/t'))
    write(os.path.join(src, 'lonely/readme.vtf'), texture('nobody'))
    write(os.path.join(src, 'more/twice.vmt'), material('elsewhere/u'))
    write(os.path.join(src, 'sorted/y.vmt'), material('elsewhere/t'))
    write(os.path.join(src, 'sorted/thrice.vmt'), material('elsewhere/t'))
    write(os.path.join(src, 'loose/band.mdl'), model([], [], 'zcband/band.mdl'))
    write(os.path.join(src, 'loose/band.vvd'), b'x')
    write(os.path.join(src, 'loose/renamed.mdl'), model([], [], 'zcband/other.mdl'))
    write(os.path.join(src, 'loose/bare.mdl'), model([], [], 'bare.mdl'))
    report, placed = run(src, ['materials/models/a/x.vmt', 'materials/models/a/twice.vmt', 'materials/models/b/twice.vmt',
                               'materials/models/b/y.vmt', 'materials/models/a/thrice.vmt', 'materials/models/b/thrice.vmt'])
    check('materials/models/a/x.vmt' in placed, 'a loose file is found by its name alone')
    check([(key, tex) for _material, key, tex in report.missing_textures] ==
          [('$basetexture', 'materials/elsewhere/t.vtf'), ('$basetexture', 'materials/elsewhere/u.vtf')][:1],
          'a texture that was not supplied is reported, once: %s' % report.missing_textures)
    check(not any(dest.endswith('twice.vmt') for dest in placed), 'a loose file that fits two names is not used')
    check(any('twice.vmt' in note and 'fits 2 names' in note for note in report.notes), 'and that is said')
    check(placed.get('materials/models/b/thrice.vmt') is not None and 'materials/models/a/thrice.vmt' not in placed,
          'of two names the one its folder went to is taken')
    check(not any('thrice.vmt' in note for note in report.notes), 'without a note')
    check('models/zcband/band.mdl' in placed and 'models/zcband/band.vvd' in placed,
          'a loose model nobody names goes to the path it was compiled for')
    check(sorted(str(item) for item, _why in report.left_out) ==
          ['content.zip: lonely/readme.vtf', 'content.zip: loose/bare.mdl', 'content.zip: loose/renamed.mdl',
           'content.zip: more/twice.vmt'],
          'what nothing names is left out: %s' % [str(item) for item, _why in report.left_out])
    check(dict((item.name, why) for item, why in report.left_out) ==
          {'readme.vtf': 'nothing names it', 'bare.mdl': 'nothing names it', 'renamed.mdl': 'nothing names it',
           'twice.vmt': 'not told from its namesakes, see the notes'},
          'and why: %s' % report.left_out)

    # two different files for one name, neither says more than the other: none is used, said once
    src = os.path.join(tmp, 'heap3')
    write(os.path.join(src, 'one/cap.vmt'), material('elsewhere/t'))
    write(os.path.join(src, 'two/cap.vmt'), material('elsewhere/u'))
    report, placed = run(src, ['materials/models/a/cap.vmt'])
    check(not placed and report.missing_named == ['materials/models/a/cap.vmt'], 'two files for one name: none is used')
    check(report.notes == ['materials/models/a/cap.vmt: 2 different files have this name and nothing says which one '
                           'is meant; none is used: give their folders the names of the folders they come from'],
          'and that is said once: %s' % report.notes)
    check(sorted(why for _item, why in report.left_out) == ['not told from its namesakes, see the notes'] * 2,
          'both are left out for that reason: %s' % report.left_out)
    # ... two copies of one file are no doubt at all
    write(os.path.join(src, 'two/cap.vmt'), material('elsewhere/t'))
    report, placed = run(src, ['materials/models/a/cap.vmt'])
    item = placed.get('materials/models/a/cap.vmt')
    check(item is not None and item.inner == 'one/cap.vmt' and not report.notes and not report.missing_named,
          'two copies of one file: the first is used, without a note (%s)' % report.notes)

    # a file with a place of its own is not taken away for a name it only shares
    src = os.path.join(tmp, 'heap2')
    write(os.path.join(src, 'materials/models/one/shirt.vmt'), material('models/one/shirt'))
    write(os.path.join(src, 'materials/models/one/shirt.vtf'), texture('one'))
    report, placed = run(src, ['materials/models/two/shirt.vmt'])
    check(sorted(placed) == ['materials/models/one/shirt.vmt', 'materials/models/one/shirt.vtf'],
          'a namesake in another folder stays where it is: %s' % sorted(placed))
    check(report.missing_named == ['materials/models/two/shirt.vmt'], 'and the name stays without a file')


def test_models(tmp):
    src = os.path.join(tmp, 'models')
    write(os.path.join(src, 'pack/zcityadodser/m/Male_01.mdl'),
          model(['models\\Adodser\\', 'models\\other\\'], ['Boots', 'legs', 'skin']))
    for ext in ('.vvd', '.dx90.vtx', '.phy'):
        write(os.path.join(src, 'pack/zcityadodser/m/male_01' + ext), b'x')
    write(os.path.join(src, 'pack/elsewhere/male_010.vvd'), b'another model')
    write(os.path.join(src, 'pack/materials/adodser/boots.vmt'), material('models/adodser/boots'))
    write(os.path.join(src, 'pack/materials/adodser/boots.vtf'), texture('boots'))
    write(os.path.join(src, 'pack/materials/adodser/legs.vmt'),
          material('models/adodser/legs_d', bumpmap='models/adodser/legs_n'))
    write(os.path.join(src, 'pack/materials/adodser/legs_d.vtf'), texture('legs_d'))
    write(os.path.join(src, 'pack/materials/adodser/legs_n.vtf'), texture('legs_n'))
    write(os.path.join(src, 'pack/materials/adodser/unused.vtf'), texture('unused'))
    write(os.path.join(src, 'pack/materials/adodser/black/tie.vtf'), texture('tie'))
    report, placed = run(src, ['models/zcityadodser/m/male_01.mdl'])
    for name in ('male_01.mdl', 'male_01.vvd', 'male_01.dx90.vtx', 'male_01.phy'):
        check('models/zcityadodser/m/' + name in placed, 'the model named by Lua: ' + name)
    check(not any(dest.endswith('male_010.vvd') for dest in placed), 'a file of another model does not go with it')
    for name in ('boots.vmt', 'boots.vtf', 'legs.vmt', 'legs_d.vtf', 'legs_n.vtf'):
        check('materials/models/adodser/' + name in placed, 'the material folder of the model: ' + name)
    check('materials/models/adodser/unused.vtf' in placed, 'a texture nobody names goes with its folder')
    check('materials/models/adodser/black/tie.vtf' in placed, 'and so does a folder below it')
    check(not any(dest.startswith('materials/adodser/') for dest in placed), 'nothing stays in materials/adodser')
    check(report.models == 1 and report.materials_wanted == 3, 'one model, three materials')
    check(report.missing_materials == [('models/zcityadodser/m/male_01.mdl', 'skin',
                                        ('materials/models/adodser/skin.vmt', 'materials/models/other/skin.vmt'))],
          'the material that is not there is reported with both places: %s' % report.missing_materials)

    # the same without the model: a material packed with its texture is put where the texture is named
    shutil.rmtree(os.path.join(src, 'pack/zcityadodser'))
    shutil.rmtree(os.path.join(src, 'pack/elsewhere'))
    report, placed = run(src)
    for name in ('boots.vmt', 'boots.vtf', 'legs_d.vtf', 'legs_n.vtf', 'unused.vtf', 'black/tie.vtf'):
        check('materials/models/adodser/' + name in placed, 'without the model: ' + name)
    check('materials/models/adodser/legs.vmt' in placed, 'without the model: a material goes with its folder')

    # ... and stays when the texture is named where it lies
    src = os.path.join(tmp, 'models2')
    write(os.path.join(src, 'materials/adodser/boots.vmt'), material('adodser/boots'))
    write(os.path.join(src, 'materials/adodser/boots.vtf'), texture('boots'))
    report, placed = run(src)
    check(sorted(placed) == ['materials/adodser/boots.vmt', 'materials/adodser/boots.vtf'], 'a folder that is right stays')
    check(not report.moves, 'and nothing is reported as moved')

    # a material in the second folder of a model, and one another material includes
    src = os.path.join(tmp, 'models3')
    write(os.path.join(src, 'models/p/a.mdl'), model(['models/first/', 'models/second/'], ['body']))
    write(os.path.join(src, 'x/second/body.vmt'), 'patch\n{\n\tinclude "materials/models/base/common.vmt"\n'
                                                  '\tinsert\n\t{\n\t\t"$detail" "models/base/fine"\n\t}\n}\n')
    write(os.path.join(src, 'y/common.vmt'), material('models/base/common'))
    write(os.path.join(src, 'y/common.vtf'), texture('common'))
    write(os.path.join(src, 'y/fine.vtf'), texture('fine'))
    report, placed = run(src)
    check('materials/models/second/body.vmt' in placed, 'a material is found for the second folder of a model')
    check('materials/models/first/body.vmt' not in placed, 'and is not copied into the first one')
    for name in ('common.vmt', 'common.vtf', 'fine.vtf'):
        check('materials/models/base/' + name in placed, 'what a patch material names: ' + name)
    check(not report.missing_materials and not report.missing_textures, 'nothing is missing there')

    # a file that is no model
    src = os.path.join(tmp, 'models4')
    write(os.path.join(src, 'models/p/broken.mdl'), b'IDST' + b'\x00' * 20)
    report, placed = run(src)
    check('models/p/broken.mdl' in placed, 'a model that cannot be read is still shipped')
    check(any('broken.mdl' in note for note in report.notes), 'with a note')


def test_reading(tmp):
    def names(text):
        path = os.path.join(tmp, 'reading.vmt')
        write(path, text.encode('latin-1'))
        found = P.read_material(path)
        return sorted(name for _key, name, sure in found.textures if sure), found

    # the ways a texture is written
    got, found = names('"VertexLitGeneric"\r\n{\r\n\t"$BaseTexture" "Models\\Humans\\Male\\Group01\\N_Shirt"\r\n'
                       '\t$bumpmap materials/models/x/shirt_n.vtf // the normal map\r\n'
                       '\t"$detail" "/models/x/fine/"\r\n\t"$phong" "1"\r\n\t"$color2" "[1 0.5 0.5]"\r\n'
                       '\t"$envmap" "env_cubemap"\r\n\t"$surfaceprop" "flesh"\r\n'
                       '\t// "$selfillummask" "models/x/commented"\r\n'
                       '\tProxies { AnimatedTexture { animatedtexturevar "$basetexture" } }\r\n}\r\n')
    check(got == ['models/humans/male/group01/n_shirt', 'models/x/fine', 'models/x/shirt_n'], 'textures of a material: %s' % got)
    check(found.base == 'models/humans/male/group01/n_shirt', 'its base texture')
    got, _found = names('\xef\xbb\xbf"VertexLitGeneric"\n{\n\t"$basetexture" "models/x/marked"\n}\n')
    check(got == ['models/x/marked'], 'a file with a UTF-8 mark: %s' % got)
    got, _found = names('"VertexLitGeneric"\n{\n\t"$basetexture" "models/x/open\n\t"$bumpmap" "models/x/open_n"\n}\n')
    check(got == ['models/x/open', 'models/x/open_n'], 'a quote that is never closed: %s' % got)
    got, _found = names('"VertexLitGeneric"\n{\n\t"$basetexture" "models/x/a" [$WIN32]\n\t"$basetexture" "models/x/b" [$X360]\n'
                        '\t"VertexLitGeneric_DX8"\n\t{\n\t\t"$bumpmap" "models/x/old"\n\t}\n}\n}\n')
    check(got == ['models/x/a', 'models/x/b', 'models/x/old'], 'conditions and nested blocks: %s' % got)
    got, found = names('patch\n{\n\tinclude "Materials\\Models\\X\\Base.VMT"\n'
                       '\tinsert\n\t{\n\t\t"$basetexture" "models/x/skin2"\n\t}\n}\n')
    check(got == ['models/x/skin2'] and found.includes == ['materials/models/x/base.vmt'],
          'a patch material: %s %s' % (got, found.includes))
    got, found = names('')
    check(got == [] and found.base is None, 'an empty file')

    # names that would lead out of the addon folder, or that are no file names
    for path, good in (('materials/models/a/b.vtf', True), ('models/a b/c (2).mdl', True), ('materials/b.vtf', True),
                       ('materials/../x.vtf', False), ('materials/a/../../x.vtf', False), ('../x.vtf', False),
                       ('materials/./x.vtf', False), ('materials//x.vtf', False), ('materials/c:/x.vtf', False),
                       ('materials/a/x?.vtf', False), ('materials/a /x.vtf', False), ('lua/x.vtf', False),
                       ('materials', False), ('materials/a/x.vtf.', False)):
        check(P.is_place(path) == good, 'is_place(%r) must be %s' % (path, good))
    src = os.path.join(tmp, 'escape')
    write(os.path.join(src, 'materials/models/a/out.vmt'), material('../../../escaped', bumpmap='models/a/../../b/up'))
    write(os.path.join(src, 'materials/models/a/escaped.vtf'), texture('escaped'))
    write(os.path.join(src, 'materials/models/a/up.vtf'), texture('up'))
    write(os.path.join(src, 'loose/sneaky.mdl'), model(['..\\..\\'], ['out'], '../../sneaky.mdl'))
    report, placed = run(src)
    check(sorted(placed) == ['materials/models/a/escaped.vtf', 'materials/models/a/out.vmt', 'materials/models/a/up.vtf'],
          'names with .. move nothing: %s' % sorted(placed))
    check(all(P.is_place(dest) for dest in placed), 'every place is inside the addon')


def test_places_kept(tmp):
    # a file that lies at the place another one would be moved to keeps it
    src = os.path.join(tmp, 'kept')
    write(os.path.join(src, 'materials/gate/epl.vmt'), material('models/gate/epl'))
    write(os.path.join(src, 'materials/gate/epl.vtf'), texture('epl'))
    write(os.path.join(src, 'materials/gate/extra.vtf'), texture('the one a level short'))
    write(os.path.join(src, 'materials/models/gate/extra.vtf'), texture('the one in place'))
    report, placed = run(src, ['materials/models/gate/epl.vmt'])
    check(text_of(placed['materials/models/gate/extra.vtf']) == texture('the one in place').decode('latin-1'),
          'a file in its place is not pushed out by one that is moved there')
    # ... and the other one is not left at the path it was packed under: nothing looks there
    check('materials/gate/extra.vtf' not in placed, 'the other version is not put anywhere else: %s' % sorted(placed))
    check([(str(item), why) for item, why in report.left_out] == [('content.zip: materials/gate/extra.vtf', P.PLACE_TAKEN)],
          'it is left out, with the reason: %s' % report.left_out)
    check(len(report.notes) == 1 and report.notes[0].kind == 'version' and 'materials/models/gate/extra.vtf' in report.notes[0],
          'and the two versions are noted: %s' % report.notes)
    # two copies of one file are no two versions
    write(os.path.join(src, 'materials/gate/extra.vtf'), texture('the one in place'))
    report, placed = run(src, ['materials/models/gate/epl.vmt'])
    check('materials/gate/extra.vtf' not in placed and not report.notes, 'a second copy of the same file: no remark')
    # a file of the addon itself has the place
    report, placed = run(src, ['materials/models/gate/epl.vmt'], own=['materials/models/gate/epl.vtf'])
    check(('content.zip: materials/gate/epl.vtf', P.OWN_FILE) in [(str(item), why) for item, why in report.left_out]
          and 'materials/gate/epl.vtf' not in placed, 'a file whose place the addon has itself is left out: %s' % report.left_out)


def test_namesakes(tmp):
    """files called the same in several folders: what tells them apart, and what does not"""
    male, female = 'models/humans/modern/male', 'models/humans/modern/female'

    # numbered folders. The women's vest uses a texture of the men's folder, so its $basetexture
    # points there too - but the texture that lies next to it says which folder this one is
    src = os.path.join(tmp, 'names1')
    write(os.path.join(src, 'material 3/vest.vmt'), material(male + '/vest'))
    write(os.path.join(src, 'material 3/vest.vtf'), texture('the vest of the men'))
    write(os.path.join(src, 'material 3/vest_shared.vtf'), texture('shared'))
    write(os.path.join(src, 'material 3/shirt.vmt'), material('models/humans/male/group01/shirt_shared'))
    write(os.path.join(src, 'material 5/vest.vmt'), material(male + '/vest_shared', bumpmap=female + '/vest_n'))
    write(os.path.join(src, 'material 5/vest_n.vtf'), texture('normal map of the women'))
    write(os.path.join(src, 'models/p/a.mdl'), model(['models/a/b/'], ['shirt']))
    report, placed = run(src, ['materials/' + male + '/vest.vmt'])
    item = placed.get('materials/' + male + '/vest.vmt')
    check(item is not None and item.inner == 'material 3/vest.vmt',
          'of two namesakes the one that lies with its texture is taken: %s' % item)
    item = placed.get('materials/' + female + '/vest.vmt')
    check(item is not None and item.inner == 'material 5/vest.vmt', 'the other one goes where its folder belongs: %s' % item)
    for name in (male + '/vest.vtf', male + '/vest_shared.vtf', female + '/vest_n.vtf'):
        check('materials/' + name + '' in placed, 'the textures of both: ' + name)
    # shirt.vmt is the only file of that name and a model asks for a shirt.vmt - in another folder
    check('materials/' + male + '/shirt.vmt' in placed and 'materials/models/a/b/shirt.vmt' not in placed,
          'a file is not taken out of its folder for a name it only shares: %s' % sorted(d for d in placed if 'shirt' in d))
    check([name for _model, name, _group in report.missing_materials] == ['shirt'], 'that name is reported as missing')
    check(not report.left_out and not report.notes,
          'nothing is left out or doubted there: %s %s' % (report.left_out, report.notes))

    # a material that uses the texture of another folder is not a material of that folder
    src = os.path.join(tmp, 'names2')
    write(os.path.join(src, 'materials/models/models/c/face.vmt'), material('models/a/face_shared'))
    write(os.path.join(src, 'materials/models/models/c/boots.vmt'), material('models/c/boots'))
    write(os.path.join(src, 'materials/models/models/c/boots.vtf'), texture('boots'))
    write(os.path.join(src, 'materials/models/models/a/face_shared.vtf'), texture('shared'))
    report, placed = run(src, ['materials/models/c/boots.vmt', 'materials/models/a/face.vmt'])
    check('materials/models/c/face.vmt' in placed and 'materials/models/a/face.vmt' not in placed,
          'a material goes with its folder, not after its texture: %s' % sorted(d for d in placed if 'face' in d))
    check(report.missing_named == ['materials/models/a/face.vmt'], 'and the name it does not belong to stays empty')
    check('materials/models/a/face_shared.vtf' in placed, 'its texture is found all the same')

    # Lua and a model ask for the same material: that is one name, not two
    src = os.path.join(tmp, 'names3')
    write(os.path.join(src, 'material 1/hat.vmt'), material('models/a/hat'))
    write(os.path.join(src, 'models/p/a.mdl'), model(['models/a/'], ['hat']))
    report, placed = run(src, ['materials/models/a/hat.vmt'])
    check('materials/models/a/hat.vmt' in placed and not report.notes, 'a name asked for twice is one name: %s' % report.notes)

    # the same file name in the folders for men and for women: never one for the other
    for packed in ('materials/models/humans/female/group01', 'materials/humans/female/group01'):
        src = os.path.join(tmp, 'names4', packed.replace('/', '_'))
        write(os.path.join(src, 'content', packed, 'hat.vmt'), material('models/shared/hat'))
        report, placed = run(src, ['materials/models/humans/male/group01/hat.vmt'])
        check(sorted(placed) == [packed + '/hat.vmt']
              and report.missing_named == ['materials/models/humans/male/group01/hat.vmt'],
              'a file for women is not used for men (%s): %s' % (packed, sorted(placed)))

    # a file in a folder that somebody names files in is at home there, whatever else is missing
    src = os.path.join(tmp, 'names7')
    write(os.path.join(src, 'materials/models/one/shirt.vmt'), material('models/shared/cloth'))
    report, placed = run(src, ['materials/models/two/shirt.vmt', 'materials/models/one/hat.vmt'])
    check(sorted(placed) == ['materials/models/one/shirt.vmt'],
          'a file at home is not moved for a name it shares: %s' % sorted(placed))
    check(report.missing_named == ['materials/models/one/hat.vmt', 'materials/models/two/shirt.vmt'], 'both names stay empty')

    # a material for men with the texture for women beside it: the texture goes where the
    # material looks for it, the material stays where the models look for it
    src = os.path.join(tmp, 'names8')
    write(os.path.join(src, 'materials/models/humans/male/group01/extra.vmt'), material('models/humans/female/group01/extra'))
    write(os.path.join(src, 'materials/models/humans/male/group01/extra.vtf'), texture('extra'))
    report, placed = run(src)
    check(sorted(placed) == ['materials/models/humans/female/group01/extra.vtf',
                             'materials/models/humans/male/group01/extra.vmt'],
          'a material does not follow its texture into the folder next door: %s' % sorted(placed))

    # a heap of one folder with a file of another one in it: that file lies with its texture and
    # both say where they belong, whatever the rest of the heap is
    src = os.path.join(tmp, 'names9')
    write(os.path.join(src, 'heap/sheet.vmt'), material('models/x/sheet'))
    write(os.path.join(src, 'heap/sheet.vtf'), texture('sheet'))
    for n in range(1, 6):
        write(os.path.join(src, 'heap/a%d.vmt' % n), material('models/y/a%d' % n))
        write(os.path.join(src, 'heap/a%d.vtf' % n), texture('a%d' % n))
    write(os.path.join(src, 'other/sheet.vmt'), material('models/shared/cloth'))
    report, placed = run(src, ['materials/models/x/sheet.vmt'])
    item = placed.get('materials/models/x/sheet.vmt')
    check(item is not None and item.inner == 'heap/sheet.vmt',
          'a material that lies with its texture is the one meant: %s' % item)
    check('materials/models/x/sheet.vtf' in placed and 'materials/models/y/a3.vmt' in placed
          and 'materials/models/y/a3.vtf' in placed,
          'and the rest of the heap goes its own way')

    # a model that lies at the path it was compiled for is not the model of another path
    src = os.path.join(tmp, 'names5')
    write(os.path.join(src, 'models/p/band.mdl'), model([], [], 'p/band.mdl'))
    write(os.path.join(src, 'models/p/band.vvd'), b'x')
    report, placed = run(src, ['models/p/q/band.mdl'])
    check(sorted(placed) == ['models/p/band.mdl', 'models/p/band.vvd'], 'a model in its own place stays: %s' % sorted(placed))
    # ... one that was only copied to a folder of its own is taken
    src = os.path.join(tmp, 'names6')
    write(os.path.join(src, 'loose/band.mdl'), model([], [], 'p/band.mdl'))
    write(os.path.join(src, 'loose/band.vvd'), b'x')
    report, placed = run(src, ['models/p/q/band.mdl'])
    check(sorted(placed) == ['models/p/q/band.mdl', 'models/p/q/band.vvd'],
          'a loose model is found by its name: %s' % sorted(placed))


def test_packed_from_inside(tmp):
    # the folders of the game without "materials" / "models" in front, and a folder that is none
    src = os.path.join(tmp, 'inside')
    write(os.path.join(src, 'd/shirt.vmt'), material('d/shirt', bumpmap='e/cloth_n'))
    write(os.path.join(src, 'd/shirt.vtf'), texture('shirt'))
    write(os.path.join(src, 'e/cloth_n.vtf'), texture('cloth'))
    write(os.path.join(src, 'e/thing.vmt'), material('models/a/elsewhere'))
    write(os.path.join(src, 'models/gate/epl.vmt'), material('models/gate/epl'))
    write(os.path.join(src, 'models/gate/epl.vtf'), texture('epl'))
    write(os.path.join(src, 'stuff/lost.vtf'), texture('lost'))
    write(os.path.join(src, 'slav/m/male_01.mdl'), model([], [], 'male_01.mdl'))
    write(os.path.join(src, 'slav/m/male_01.vvd'), b'x')
    write(os.path.join(src, 'slav/m/male_02.mdl'), model([], [], 'male_02.mdl'))
    report, placed = run(src, ['materials/d/shirt.vmt', 'materials/models/gate/epl.vmt', 'models/slav/m/male_01.mdl'])
    for name in ('materials/d/shirt.vmt', 'materials/d/shirt.vtf', 'materials/e/cloth_n.vtf', 'materials/models/gate/epl.vmt',
                 'materials/models/gate/epl.vtf', 'models/slav/m/male_01.mdl', 'models/slav/m/male_01.vvd'):
        check(name in placed, 'packed from inside its folder: ' + name)
    check('materials/e/thing.vmt' in placed, 'a file nobody names stays in its folder, with materials in front: %s'
          % sorted(d for d in placed if 'thing' in d))
    check('models/slav/m/male_02.mdl' in placed, 'and so does a model next to a named one')
    check([str(item) for item, _why in report.left_out] == ['content.zip: stuff/lost.vtf'],
          'a folder that nothing knows is not made a folder of the addon: %s' % report.left_out)

    # one upload cut into two archives: a folder that says nothing in one of them says it in the other
    one, two = os.path.join(tmp, 'cut1'), os.path.join(tmp, 'cut2')
    write(os.path.join(one, 'content/materials/gate/epl.vmt'), material('models/gate/epl'))
    write(os.path.join(one, 'content/materials/gate/epl.vtf'), texture('epl'))
    write(os.path.join(two, 'content/materials/gate/extra.vtf'), texture('extra'))
    items = scan(one, source='content.zip', order=1) + scan(two, source='content 2.zip', order=2)
    report, placed = run(items, ['materials/models/gate/epl.vmt'])
    check(sorted(placed) == ['materials/models/gate/epl.vmt', 'materials/models/gate/epl.vtf', 'materials/models/gate/extra.vtf'],
          'the second archive follows the first: %s' % sorted(placed))


def test_folders_of_their_own(tmp):
    # "material 1", "material 2" ... in the repository root, the files right inside: each folder
    # is a source of its own, and what one of them tells says nothing about the next
    one, two, three, four = (os.path.join(tmp, 'own', 'material %d' % n) for n in (1, 2, 3, 4))
    write(os.path.join(one, 'epl.vmt'), material('models/gate/epl'))
    write(os.path.join(one, 'epl.vtf'), texture('epl'))
    write(os.path.join(one, 'Sheet_01.VMT'), material('models/humans/modern/male/sheet_01'))
    write(os.path.join(one, 'sheet_01.vtf'), texture('sheet of the men'))
    write(os.path.join(two, 'sheet_01.vmt'), material('models/humans/modern/female/sheet_01'))
    write(os.path.join(two, 'sheet_01.vtf'), texture('sheet of the women'))
    write(os.path.join(three, 'lost.vtf'), texture('lost'))
    write(os.path.join(four, 'unknown.vmt'), material('models/gone/unknown'))
    write(os.path.join(four, 'beside.vtf'), texture('beside'))
    items = []
    for order, folder in enumerate((one, two, three, four), 1):
        items += scan(folder, source=os.path.basename(folder), order=order)
    report, placed = run(items, ['materials/models/gate/epl.vmt', 'materials/models/humans/modern/male/sheet_01.vmt',
                                 'materials/models/humans/modern/female/sheet_01.vmt'])
    for name, folder in (('gate/epl.vmt', 'material 1'), ('gate/epl.vtf', 'material 1'),
                         ('humans/modern/male/sheet_01.vmt', 'material 1'), ('humans/modern/male/sheet_01.vtf', 'material 1'),
                         ('humans/modern/female/sheet_01.vmt', 'material 2'),
                         ('humans/modern/female/sheet_01.vtf', 'material 2')):
        item = placed.get('materials/models/' + name)
        check(item is not None and item.source == folder,
              'folders of their own: %s comes out of %s (%s)' % (name, folder, item))
    check([str(item) for item, _why in report.left_out] == ['material 3: lost.vtf'],
          'a folder that says nothing is not poured into the folder of another one: %s'
          % sorted(d for d in placed if 'lost' in d))
    check('materials/models/gone/unknown.vmt' in placed and 'materials/models/gone/beside.vtf' in placed,
          'a material nobody names goes where its texture is named, and takes its folder along')
    check(not report.missing_named and not report.notes, 'folders of their own: no doubts, %s' % report.notes)
    # ... also when all the other folders went to one and the same place
    gate, silent = os.path.join(tmp, 'own2', 'material 1'), os.path.join(tmp, 'own2', 'material 2')
    write(os.path.join(gate, 'epl.vmt'), material('models/gate/epl'))
    write(os.path.join(gate, 'epl.vtf'), texture('epl'))
    write(os.path.join(silent, 'lost.vtf'), texture('lost'))
    _report, alone = run(scan(gate, source='material 1', order=1) + scan(silent, source='material 2', order=2),
                         ['materials/models/gate/epl.vmt'])
    check(sorted(alone) == ['materials/models/gate/epl.vmt', 'materials/models/gate/epl.vtf'],
          'the top of one source is not the top of another: %s' % sorted(alone))
    moved = sorted((source, src, dst, n) for (source, src, dst), n in report.moves.items())
    check(moved == [('material 1', '', 'materials/models/gate', 2),
                    ('material 1', '', 'materials/models/humans/modern/male', 2),
                    ('material 2', '', 'materials/models/humans/modern/female', 2),
                    ('material 4', '', 'materials/models/gone', 2)],
          'the report says where each folder went: %s' % moved)


# ---- random packings -------------------------------------------------------------------------
# A made-up game: materials, textures and models in folders that hold many files called the
# same; some materials use a texture of another folder, some files are named by nobody, some
# names have no file. It is packed in one of these ways into one to three uploads, placed, and
# every file is compared with where it came from.
RANDOM_FOLDERS = ['materials/models/a', 'materials/models/a/b', 'materials/models/c', 'materials/d',
                  'materials/models/humans/male/group01', 'materials/models/humans/female/group01',
                  'materials/models/humans/modern/male', 'materials/models/humans/modern/female', 'materials/e/f']
RANDOM_MODEL_FOLDERS = ['models/p', 'models/p/q', 'models/r']
RANDOM_NAMES = ['shirt', 'pants', 'face', 'sheet_01', 'sheet_02', 'boots', 'hat', 'jacket', 'vest']
PACKINGS = ('as it is', 'a level short', 'wrapped', 'numbered folders', 'from inside', 'everything in materials/models',
            'heaps')
NUMBERED, HEAPS = 3, 6


class Dice(object):
    """Random choices that are the same on every Python version, so that a run can be repeated
    anywhere: of the random module only random() is promised to stay as it is."""

    def __init__(self, seed):
        self.random = random.Random(seed).random

    def below(self, count):
        return int(self.random() * count)

    def between(self, low, high):
        return low + self.below(high - low + 1)

    def choice(self, things):
        return things[self.below(len(things))]

    def sample(self, things, count):
        things = list(things)
        for i in range(count):
            j = i + self.below(len(things) - i)
            things[i], things[j] = things[j], things[i]
        return things[:count]


def random_game(rng):
    """{path in the game: content}"""
    game = {}
    for folder in RANDOM_FOLDERS:
        for name in RANDOM_NAMES:
            if rng.random() < 0.4:
                short = folder[len('materials/'):]
                tex = short + '/' + name + ('_d' if rng.random() < 0.3 else '')
                if rng.random() < 0.04:
                    tex = rng.choice(RANDOM_FOLDERS)[len('materials/'):] + '/' + name + '_shared'
                more = {}
                if rng.random() < 0.3:
                    more['bumpmap'] = short + '/' + name + '_n'
                    if rng.random() < 0.9:
                        game['materials/' + more['bumpmap'] + '.vtf'] = texture(more['bumpmap'])
                game[folder + '/' + name + '.vmt'] = material(tex, **more).encode()
                if rng.random() < 0.9:
                    game['materials/' + tex + '.vtf'] = texture(tex)
        if rng.random() < 0.3:
            game[folder + '/unused_%d.vtf' % rng.between(1, 2)] = texture(folder + ' unused')
    for folder in RANDOM_MODEL_FOLDERS:
        for name in ('male_01', 'male_02', 'band'):
            if rng.random() < 0.4:
                folders = [f[len('materials/'):] + '/' for f in rng.sample(RANDOM_FOLDERS, rng.between(1, 2))]
                names = rng.sample(RANDOM_NAMES, rng.between(1, 3))
                inner = (folder[len('models/'):] + '/' + name + '.mdl') if rng.random() < 0.7 else name + '.mdl'
                game[folder + '/' + name + '.mdl'] = model(folders, names, inner)
                for ext in ('.vvd', '.dx90.vtx'):
                    game[folder + '/' + name + ext] = b'part ' + (folder + name).encode()
    return game


def packed_as(path, packing, number):
    """the path a file of the game gets in an upload"""
    parts = path.split('/')
    if packing == 1 and parts[:2] == ['materials', 'models']:
        return ['content', 'materials'] + parts[2:]
    if packing == 2:
        return ['wrap', 'Content'] + parts
    if packing == NUMBERED:
        return ['%s %d' % ('material' if parts[0] == 'materials' else 'model', number['/'.join(parts[:-1])]), parts[-1]]
    if packing == 4:
        return parts[1:] if len(parts) > 2 else parts
    if packing == 5 and parts[0] == 'materials':
        return ['materials', 'models'] + parts[1:]
    if packing == HEAPS:
        return ['heap %d' % number['/'.join(parts[:-1])], parts[-1]]
    return parts


def random_run(seed, tmp):
    """one game, packed and placed: (the packings used, what became of the files)"""
    rng = Dice(seed)
    game = random_game(rng)
    named = set(path for path in game if path.endswith(('.vmt', '.mdl')) and rng.random() < 0.6)
    named |= set(rng.choice(RANDOM_FOLDERS) + '/' + rng.choice(RANDOM_NAMES) + '.vmt' for _ in range(3)) - set(game)
    uploads = rng.between(1, 3)
    packings = [rng.below(len(PACKINGS)) for _ in range(uploads)]
    folders = sorted(set(path.rsplit('/', 1)[0] for path in game))
    # numbered folders: one for every folder of the game. Heaps: folders of the game thrown
    # together as long as no two files get the same name
    number = dict((folder, i) for i, folder in enumerate(rng.sample(folders, len(folders)), 1))
    heaps, heap_of = [], {}
    for folder in rng.sample(folders, len(folders)):
        mine = set(path.rsplit('/', 1)[1] for path in game if path.rsplit('/', 1)[0] == folder)
        for i, heap in enumerate(heaps):
            if not (heap & mine) and rng.random() < 0.7:
                heap |= mine
                heap_of[folder] = i + 1
                break
        else:
            heaps.append(set(mine))
            heap_of[folder] = len(heaps)
    # a material and its textures stand next to each other in a folder sorted by name: somebody
    # who cuts the content into several uploads mostly keeps them together
    written, truth, together, spelled = set(), {}, {}, {}
    for path, data in sorted(game.items()):
        folder, name = path.rsplit('/', 1)
        stem = name.rsplit('.', 1)[0]
        for tail in ('_d', '_n', '_shared'):
            if stem.endswith(tail):
                stem = stem[:-len(tail)]
        if (folder, stem) not in together:
            together[(folder, stem)] = rng.below(uploads)
        upload = together[(folder, stem)] if rng.random() < 0.9 else rng.below(uploads)
        packing = packings[upload]
        parts = packed_as(path, packing, heap_of if packing == HEAPS else number)
        if packing in (NUMBERED, HEAPS):
            parts[0] = 'upload %d %s' % (upload, parts[0])
        if rng.random() < 0.1:
            parts = [part.upper() if rng.random() < 0.5 else part for part in parts]
        # A folder is spelled the way it was made first, as on Windows, where "GATE" and "gate"
        # are one folder: the test puts the same files down on every file system.
        for depth in range(1, len(parts)):
            key = (upload, '/'.join(parts[:depth]).lower())
            parts[depth - 1] = spelled.setdefault(key, parts[depth - 1])
        full = os.path.join(tmp, 's%d' % upload, *parts)
        if full.lower() in written:
            continue        # nobody can put two files there either
        written.add(full.lower())
        write(full, data)
        truth[full] = path
    items = []
    for upload in range(uploads):
        base = os.path.join(tmp, 's%d' % upload)
        if os.path.isdir(base):
            items += scan(base, source='s%d' % upload, order=upload + 1)
    own = set(rng.sample(sorted(game), min(2, len(game)))) if rng.random() < 0.2 else set()
    report = P.place(items, set(named), lambda path: path in own)

    result = collections.Counter(files=len(items))
    places = [dest for dest, _item in report.placed]
    placed, left = set(id(item) for _dest, item in report.placed), set(id(item) for item, _why in report.left_out)
    if len(places) != len(set(places)) or set(places) & own or placed & left \
            or placed | left != set(id(item) for item in items) \
            or not all(P.is_place(dest, item.kind) and dest == dest.lower() for dest, item in report.placed):
        result['broken'] += 1
    where = collections.defaultdict(list)
    for dest, item in report.placed:
        where[id(item)].append(dest)
        if dest in game and game[dest] != build_addon.read_bytes(item.path):
            result['wrong'] += 1          # at a path of the game lies another file than in the game
    for item in items:
        home = truth[item.path]
        if home in own:
            continue
        if home in where.get(id(item), ()):
            result['right'] += 1
        elif id(item) in where:
            result['elsewhere'] += 1
            result['named elsewhere'] += home in named
        else:
            result['left out'] += 1
            result['named left out'] += home in named
    # the result, supplied once more, stays as it is
    out = os.path.join(tmp, 'out')
    for dest, item in report.placed:
        build_addon.copy(item.path, os.path.join(out, dest))
    again = P.place(scan(out, source='out'), set(named), lambda path: path in own)
    if again.left_out or any(dest != item.inner for dest, item in again.placed):
        result['changed again'] += 1

    # The same uploads lying in the materials folder of an installed addon, where its owner puts
    # them for sort_content.py: once as they are, once with a file of the addon next to them that
    # lies where it belongs already. That file must not change where the others go.
    def in_the_addon(with_a_file_in_place):
        files, names = [], set(named)
        for upload in range(uploads):
            base = os.path.join(tmp, 's%d' % upload)
            if os.path.isdir(base):
                for rel, full in sorted(build_addon.walk_files(base)):
                    inner = 'materials/upload %d/%s' % (upload, rel)
                    files.append(P.Item('zcity_csgo_gloves', inner, full, L.dropin_destination(inner), 1))
        if with_a_file_in_place:
            full = os.path.join(tmp, 'in place.vmt')
            write(full, material('models/in_place/zz'))
            there = 'materials/models/in_place/zz.vmt'
            files.append(P.Item('zcity_csgo_gloves', there, full, there, 2))
            names.add(there)
        went_to = collections.defaultdict(list)
        for dest, item in P.place(files, names, lambda path: path in own).placed:
            if item.path in truth:
                went_to[item.path].append(dest)
        return dict((full, sorted(dests)) for full, dests in went_to.items())

    plain, inside = in_the_addon(False), in_the_addon(True)
    if plain != inside:
        result['in the addon: a file in place matters'] += 1
    for full, home in truth.items():
        dests = inside.get(full, ())
        if home in own:
            continue
        result['in the addon: right'] += home in dests
        result['in the addon: named elsewhere'] += bool(dests) and home not in dests and home in named
        result['in the addon: wrong'] += sum(1 for dest in dests if dest in game and game[dest] != build_addon.read_bytes(full))
    return set(PACKINGS[packing] for packing in packings), result


def test_random_packings(tmp, runs=200):
    """What must hold, and what is only kept small.
    Packed in the folders of the game, however shifted: no file at the place of another one, no
    named file anywhere but at its name or left out, and the result, supplied again, stays.
    One numbered folder for each folder of the game: nearly the same. A file is left out when
    nothing tells it from a namesake; it lands at a namesake's place only when what it says
    itself points there (a material that uses the texture of another folder, wanted under a
    name there that has no file) - that has to stay a rare accident.
    Folders thrown together into heaps cannot always be told apart: the same, less strict."""
    total = collections.defaultdict(collections.Counter)
    for seed in range(runs):
        folder = os.path.join(tmp, 'random%d' % seed)
        packings, result = random_run(seed, folder)
        shutil.rmtree(folder, ignore_errors=True)
        kind = 'heaps' if 'heaps' in packings else 'numbered' if 'numbered folders' in packings else 'folders'
        total[kind].update(result)
        total[kind]['runs'] += 1
    for kind in ('folders', 'numbered', 'heaps'):
        got = total[kind]
        print('  random packings, %-9s %3d runs, %5d files: %5d right, %2d at the place of another file, '
              '%3d elsewhere (%d named), %3d left out (%d named)'
              % (kind + ':', got['runs'], got['files'], got['right'], got['wrong'], got['elsewhere'],
                 got['named elsewhere'], got['left out'], got['named left out']))
        check(got['runs'] >= runs // 10, 'random packings: enough runs with %s (%d)' % (kind, got['runs']))
        check(not got['broken'], 'random packings, %s: a place given twice, an own file replaced or a file lost' % kind)
    got = total['folders']
    check(not got['wrong'], 'random packings, folders: %d files at the place of another file' % got['wrong'])
    check(not got['named elsewhere'], 'random packings, folders: %d named files not at their names' % got['named elsewhere'])
    check(not got['named left out'], 'random packings, folders: %d named files left out' % got['named left out'])
    check(not got['changed again'], 'random packings, folders: %d results change when supplied again' % got['changed again'])
    check(got['right'] >= 0.99 * got['files'],
          'random packings, folders: only %d of %d files are right' % (got['right'], got['files']))
    for kind, wrong, right in (('numbered', 0.001, 0.95), ('heaps', 0.002, 0.9)):
        got = total[kind]
        check(got['wrong'] <= wrong * got['files'],
              'random packings, %s: %d of %d files at the place of another file' % (kind, got['wrong'], got['files']))
        check(got['named elsewhere'] <= 5 * wrong * got['files'],
              'random packings, %s: %d of %d named files not at their names' % (kind, got['named elsewhere'], got['files']))
        check(got['right'] >= right * got['files'],
              'random packings, %s: only %d of %d files are right' % (kind, got['right'], got['files']))

    # The same, lying in the materials folder of the addon. (Models and their files have no place
    # below a materials folder: those that nothing names are left out there, so fewer are right.)
    for kind, wrong, right in (('folders', 0, 0.97), ('numbered', 0.001, 0.95), ('heaps', 0.002, 0.9)):
        got, where = total[kind], 'random packings in the materials folder of the addon, %s' % kind
        print('  %s: %d right, %d at the place of another file, %d named files elsewhere'
              % (where, got['in the addon: right'], got['in the addon: wrong'], got['in the addon: named elsewhere']))
        check(not got['in the addon: a file in place matters'],
              '%s: a file that lies in its place changes where the others go (%d runs)'
              % (where, got['in the addon: a file in place matters']))
        check(got['in the addon: wrong'] <= wrong * got['files'],
              '%s: %d of %d files at the place of another file' % (where, got['in the addon: wrong'], got['files']))
        check(got['in the addon: named elsewhere'] <= 5 * wrong * got['files'],
              '%s: %d of %d named files not at their names' % (where, got['in the addon: named elsewhere'], got['files']))
        check(got['in the addon: right'] >= right * got['files'],
              '%s: only %d of %d files are right' % (where, got['in the addon: right'], got['files']))


def test_sources(tmp):
    # own files stay, the later source wins
    one, two = os.path.join(tmp, 'one'), os.path.join(tmp, 'two')
    write(os.path.join(one, 'materials/models/a/x.vmt'), material('models/a/x'))
    write(os.path.join(one, 'materials/models/a/x.vtf'), texture('first'))
    write(os.path.join(one, 'materials/models/a/same.vtf'), texture('same'))
    write(os.path.join(two, 'materials/models/a/x.vtf'), texture('second'))
    write(os.path.join(two, 'materials/models/a/same.vtf'), texture('same'))
    write(os.path.join(two, 'materials/models/a/own.vtf'), texture('theirs'))
    items = scan(one, source='1.zip', order=1) + scan(two, source='2.zip', order=2)
    report, placed = run(items, own=['materials/models/a/own.vtf'])
    check(text_of(placed['materials/models/a/x.vtf']) == texture('second').decode('latin-1'), 'the later source wins')
    check(any('another version' in note for note in report.notes) and len(report.notes) == 1,
          'a different file is noted, the same one is not: %s' % report.notes)
    check('materials/models/a/own.vtf' not in placed, 'a file of the addon is not replaced')
    check(sorted(why for _item, why in report.left_out) ==
          ['a later source has this file', 'a later source has this file', 'the file of this addon is kept'],
          'why files were left out: %s' % report.left_out)

    # ... also when both lie a level short: the earlier one is not found by its name instead
    one, two = os.path.join(tmp, 'three'), os.path.join(tmp, 'four')
    write(os.path.join(one, 'materials/gate/epl.vmt'), material('models/gate/epl'))
    write(os.path.join(one, 'materials/gate/epl.vtf'), texture('first'))
    write(os.path.join(two, 'materials/Gate/epl.vtf'), texture('second'))
    items = scan(one, source='1.zip', order=1) + scan(two, source='2.zip', order=2)
    report, placed = run(items, ['materials/models/gate/epl.vmt'])
    check(sorted(placed) == ['materials/models/gate/epl.vmt', 'materials/models/gate/epl.vtf'],
          'two versions a level short: one file each, %s' % sorted(placed))
    check(text_of(placed['materials/models/gate/epl.vtf']) == texture('second').decode('latin-1'),
          'two versions a level short: the later source wins')

    # what the repository root offers
    root = os.path.join(tmp, 'root')
    for name in ('a.zip', 'b.7z', 'z_city.zip', 'optimized_textures9.7z', 'sport1.zip', 'c.7z.002', 'c.7z.001',
                 'sport1.zip.001', 'notes.txt', 'tools/x.py', 'material 1/x.vmt', '.git/config', 'build/y', '_old/z',
                 'material 2.rar', 'material 3.part1.RAR', 'old.z01', 'README.md', 'rar/inside.vtf'):
        write(os.path.join(root, name), b'')
    check(L.unread_archives(root) == ['material 2.rar', 'material 3.part1.RAR', 'old.z01'],
          'archives nobody reads are named: %s' % L.unread_archives(root))
    check(L.dropin_sources(root) == [
        ('a.zip', 'archive', [os.path.join(root, 'a.zip')]),
        ('b.7z', 'archive', [os.path.join(root, 'b.7z')]),
        ('c.7z', 'volumes', [os.path.join(root, 'c.7z.001'), os.path.join(root, 'c.7z.002')]),
        ('material 1', 'folder', [os.path.join(root, 'material 1')]),
        ('rar', 'folder', [os.path.join(root, 'rar')]),
    ], 'drop-in sources of a repository root: %s' % [s[:2] for s in L.dropin_sources(root)])

    # a zip in two parts, with a Russian folder name stored the way Windows tools do
    whole = io.BytesIO()
    with zipfile.ZipFile(whole, 'w') as z:
        z.writestr('QQQQQ/materials/a.vmt', 'one')
        z.writestr('Deep/Models/B.MDL', 'two')
    data = whole.getvalue().replace(b'QQQQQ', u'\u043f\u0430\u043f\u043a\u0430'.encode('cp866'))
    parts = [os.path.join(tmp, 'c.zip.001'), os.path.join(tmp, 'c.zip.002')]
    write(parts[0], data[:40])
    write(parts[1], data[40:])
    temp = os.path.join(tmp, 'temp')
    files = build_addon.dropin_files(None, temp, 'c.zip', 'volumes', parts)
    check([rel for rel, _full in files] == ['Deep/Models/B.MDL', u'\u043f\u0430\u043f\u043a\u0430/materials/a.vmt'],
          'a split zip is joined and unpacked with its names: %r' % [rel for rel, _full in files])
    check(sorted(os.listdir(temp)) == [os.path.basename(build_addon.dropin_folder(temp, 'c.zip'))],
          'only the unpacked files stay in the temporary folder: %s' % sorted(os.listdir(temp)))
    # unpacking starts from an empty folder: a file put there shows whether it happened again
    mark = os.path.join(build_addon.dropin_folder(temp, 'c.zip'), 'mark.vtf')
    write(mark, b'')
    build_addon.dropin_files(None, temp, 'c.zip', 'volumes', parts)
    check(os.path.isfile(mark), 'an archive that did not change is not unpacked again')
    later = os.stat(parts[1]).st_mtime_ns + 5 * 10 ** 9
    os.utime(parts[1], ns=(later, later))
    build_addon.dropin_files(None, temp, 'c.zip', 'volumes', parts)
    check(not os.path.isfile(mark), 'one that did change is')
    for wrong, why in ((parts[1:], 'without its first part'), ([parts[0]], 'that is cut short')):
        try:
            build_addon.dropin_files(None, temp, 'd.zip', 'volumes', wrong)
            check(False, 'a split archive %s must stop the build' % why)
        except build_addon.BuildError:
            check(True, '')
    # what a removed archive left behind goes away, the rest of the temporary folder stays
    write(os.path.join(temp, '_dropin7/x'), b'')
    write(os.path.join(temp, '_dropin_0123456789ab/x'), b'')
    write(os.path.join(temp, 'sport1/x'), b'')
    build_addon.forget_old_dropins(temp, [('c.zip', 'volumes', parts)])
    check(sorted(os.listdir(temp)) == sorted([os.path.basename(build_addon.dropin_folder(temp, 'c.zip')), 'sport1']),
          'old unpacked drop-ins are removed: %s' % sorted(os.listdir(temp)))

    # files put into the folders of the addon by hand
    check(L.is_own_content('materials/zcity_csgo_gloves/icons/x.png') and
          L.is_own_content('materials/models/weapons/v_models/arms/glove_slick/a.vmt') and
          L.is_own_content('models/zcity_csgo_gloves/v_glove_slick.mdl') and
          not L.is_own_content('materials/models/gate/epl.vmt') and
          not L.is_own_content('materials/models/weapons/v_models/armsx/a.vmt'), 'which content is the own one')


def test_report(tmp):
    # what the build writes down for reading afterwards (in Russian: tools/content_report.py)
    one, two = os.path.join(tmp, 'report1'), os.path.join(tmp, 'report2')
    write(os.path.join(one, 'content/materials/gate/epl.vmt'), material('models/gate/epl', bumpmap='models/gate/epl_n'))
    write(os.path.join(one, 'content/materials/gate/epl.vtf'), texture('epl'))
    write(os.path.join(one, 'content/models/p/band.mdl'), model(['models/gate/'], ['epl', 'strap'], 'p/band.mdl'))
    write(os.path.join(one, 'content/stuff/lost.vtf'), texture('lost'))
    write(os.path.join(one, 'a/cap.vmt'), material('elsewhere/t'))
    write(os.path.join(one, 'b/cap.vmt'), material('elsewhere/u'))
    write(os.path.join(two, 'hat.vmt'), material('models/gate/hat'))
    items = scan(one, source='content.zip', order=1) + scan(two, source='material 1', order=2)
    named = ['materials/models/gate/epl.vmt', 'materials/models/gate/hat.vmt', 'materials/models/gate/gone.vmt',
             'materials/models/gate/cap.vmt', 'models/p/band.mdl']
    report, _placed = run(items, named)
    sources = [{'name': 'content.zip', 'kind': 'archive', 'no_place': ['content/readme.txt']},
               {'name': 'material 1', 'kind': 'folder', 'no_place': []}]
    moved_from = content_report.moved_from
    check(moved_from(sources, 'content.zip', 'content/materials/gate') == 'content/materials/gate/' and
          moved_from(sources, 'content.zip', '') == './' and
          moved_from(sources, 'material 1', '') == 'material 1/' and
          moved_from(sources, 'material 1', 'sub') == 'material 1/sub/',
          'a folder of the repository is shown with its name, a folder of an archive as it is called there')
    path = os.path.join(tmp, 'content_report.txt')
    content_report.write(path, sources, report, named, 'build_addon.py', [u'(a line of the tool)'])
    with open(path, 'rb') as f:
        data = f.read()
    check(data.startswith(b'\xef\xbb\xbf') and b'\r\n' in data and b'\n\n' not in data,
          'the report is UTF-8 with a mark and Windows line ends: Notepad shows it as it is')
    text = data.decode('utf-8-sig').replace('\r\n', '\n')
    for line in (u'(записано build_addon.py)',
                 u'(a line of the tool)',
                 u'Переложено (нашлись по имени или переехали вместе со своей папкой) — файлов: 3',
                 u'    content/materials/gate/  ->  materials/models/gate/    файлов: 2    [content.zip]',
                 u'    material 1/  ->  materials/models/gate/    файлов: 1    [material 1]',
                 u'Не использовано — файлов: 3',
                 u'    content.zip: content/stuff/lost.vtf    (его никто не называет, и лежит он не в папке materials или models)',
                 u'    content.zip: a/cap.vmt    (не отличить от тёзок, см. «Замечания»)',
                 u'Замечания — 1',
                 u'    materials/models/gate/cap.vmt: на это имя есть несколько разных файлов (2), и нечем решить, '
                 u'какой нужен; не взят ни один',
                 u'Lua называет, а файла нет — 2 из 5 ',
                 u'    materials/models/gate/gone.vmt',
                 u'Модель ищет материал, а его нет — 1 из 2',
                 u'    materials/models/gate/strap.vmt  <-  models/p/band.mdl',
                 u'Материал ищет текстуру, а её нет — 2 из 3',
                 u'    materials/models/gate/epl_n.vtf  <-  materials/models/gate/epl.vmt  $bumpmap',
                 u'    materials/models/gate/hat.vtf  <-  materials/models/gate/hat.vmt  $basetexture',
                 u'Не часть аддона (над файлом нет папки lua, materials, models ...) — пропущено',
                 u'    content.zip — файлов: 1',
                 u'        content/readme.txt'):
        check(line in text, 'the report says: %s' % line.strip().encode('ascii', 'backslashreplace').decode('ascii'))
    # every remark and every reason has its Russian words
    for kind, english in P.NOTES.items():
        made = P.Note(kind, *[2 if spec == 'd' else 'x' for spec in
                              [english[i + 1] for i in range(len(english) - 1) if english[i] == '%']])
        check(content_report.note(made) != made and u'%' not in content_report.note(made), 'a remark in Russian: ' + kind)
    for reason in (P.REPLACED, P.OWN_FILE, P.NAMESAKES, P.UNNAMED, P.PLACE_TAKEN):
        check(content_report.why(reason) != reason, 'a reason in Russian: ' + reason)
    check(content_report.note('something else') == 'something else' and content_report.why('other') == 'other',
          'what is not known stays as it is')


# ---- sort_content.py: the same, done to an addon that is installed --------------------------
def tree(folder):
    """{path below the folder: content}"""
    found = {}
    for base, _dirs, files in os.walk(folder):
        for name in files:
            full = os.path.join(base, name)
            found[os.path.relpath(full, folder).replace(os.sep, '/')] = build_addon.read_bytes(full)
    return found


def sort(*args):
    """runs sort_content.py; returns (exit code, what it printed)"""
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = sort_content.main(list(args))
    return code, out.getvalue()


def an_addon(folder):
    """an addon as it is installed: its Lua, its own content, and clothing content put in by hand"""
    lua = '''
        hg.Appearance.Clothes[1].epl = "models/gate/epl"
        hg.Appearance.Clothes[1].shirt = "models/gate/shirt"
        hg.Appearance.Clothes[1].sheet = "models/humans/modern/male/sheet_01"
        hg.Appearance.Clothes[2].sheet = "models/humans/modern/female/sheet_01"
        hg.Appearance.Clothes[1].bib = "models/humans/male/group01/bib"
        hg.Appearance.Clothes[1].gone = "models/gate/gone"
        AppAddModel("Male 10", "models/slav/m/male_10.mdl", false, {})
        local stock = "models/humans/male/group01/normal" -- Z-City has this one itself
    '''
    files = {
        'addon.json': '{}',
        'lua/autorun/clothes.lua': lua,
        # its own
        'materials/zcity_csgo_gloves/icons/moto_1.png': b'png',
        'materials/models/weapons/v_models/arms/glove_x/Left.vmt': material('models/weapons/v_models/arms/glove_x/left'),
        'models/zcity_csgo_gloves/v_glove.mdl': model([], [], 'v_glove.mdl'),
        'materials/put_materials_here.txt': 'note',
        # a level short, with capitals
        'materials/Gate/Epl.VMT': material('models/gate/epl'),
        'materials/Gate/epl.vtf': texture('epl'),
        'materials/Gate/Unused.vtf': texture('unused'),
        # right where it belongs
        'materials/models/gate/shirt.vmt': material('models/gate/shirt', bumpmap='models/gate/shirt_n'),
        'materials/models/gate/shirt.vtf': texture('shirt'),
        # folders of the owner's own, namesakes in them
        'materials/material 1/sheet_01.vmt': material('models/humans/modern/male/sheet_01'),
        'materials/material 1/sheet_01.vtf': texture('sheet of the men'),
        'materials/material 2/sheet_01.vmt': material('models/humans/modern/female/sheet_01'),
        'materials/material 2/sheet_01.vtf': texture('sheet of the women'),
        # materials in the models folder
        'models/humans/male/group01/bib.vmt': material('models/humans/male/group01/bib'),
        'models/humans/male/group01/bib.vtf': texture('bib'),
        # a model in a folder of its own, with its files; it names its materials
        'models/model 1/Male_10.mdl': model(['models\\humans\\slav\\'], ['hair', 'eyes'], 'slav/m/male_10.mdl'),
        'models/model 1/male_10.vvd': b'vvd',
        'models/model 1/male_10.dx90.vtx': b'vtx',
        'materials/slav stuff/hair.vmt': material('models/humans/slav/hair'),
        'materials/slav stuff/hair.vtf': texture('hair'),
        # no place for these: a model among the materials that nothing names
        'materials/odd/thing.mdl': model([], [], 'thing.mdl'),
        # not content, but with capitals
        'materials/Icons/Thing.PNG': b'png2',
    }
    for rel, data in files.items():
        write(os.path.join(folder, rel), data)
    return files


SORTED = {
    'materials/Gate/Epl.VMT': 'materials/models/gate/epl.vmt',
    'materials/Gate/epl.vtf': 'materials/models/gate/epl.vtf',
    'materials/Gate/Unused.vtf': 'materials/models/gate/unused.vtf',
    'materials/material 1/sheet_01.vmt': 'materials/models/humans/modern/male/sheet_01.vmt',
    'materials/material 1/sheet_01.vtf': 'materials/models/humans/modern/male/sheet_01.vtf',
    'materials/material 2/sheet_01.vmt': 'materials/models/humans/modern/female/sheet_01.vmt',
    'materials/material 2/sheet_01.vtf': 'materials/models/humans/modern/female/sheet_01.vtf',
    'models/humans/male/group01/bib.vmt': 'materials/models/humans/male/group01/bib.vmt',
    'models/humans/male/group01/bib.vtf': 'materials/models/humans/male/group01/bib.vtf',
    'models/model 1/Male_10.mdl': 'models/slav/m/male_10.mdl',
    'models/model 1/male_10.vvd': 'models/slav/m/male_10.vvd',
    'models/model 1/male_10.dx90.vtx': 'models/slav/m/male_10.dx90.vtx',
    'materials/slav stuff/hair.vmt': 'materials/models/humans/slav/hair.vmt',
    'materials/slav stuff/hair.vtf': 'materials/models/humans/slav/hair.vtf',
    'materials/odd/thing.mdl': '_not_used/materials/odd/thing.mdl',
    'materials/Icons/Thing.PNG': 'materials/icons/thing.png',
}


def owners(tmp, label, in_place, numbered, inside):
    """items as sort_content.py makes them: files of the addon that lie where they belong, and the
    folders of its owner - put into the materials folder of the addon (inside), or handed over"""
    root = os.path.join(tmp, label + (' inside' if inside else ' dropped'))
    items = []
    for rel, data in sorted(numbered.items()):
        write(os.path.join(root, 'own', rel), data)
        inner = 'materials/' + rel if inside else rel
        items.append(P.Item('zcity_csgo_gloves' if inside else 'materials0000', inner, os.path.join(root, 'own', rel),
                            L.dropin_destination(inner), 2 if inside else 1))
    for rel, data in sorted(in_place.items()):
        write(os.path.join(root, 'addon', rel), data)
        items.append(P.Item('zcity_csgo_gloves', rel, os.path.join(root, 'addon', rel), L.dropin_destination(rel), 3))
    return items


def went(report):
    """{file as it was packed, without a leading materials/: where it was put}"""
    out = {}
    for dest, item in report.placed:
        key = item.inner[len('materials/'):] if item.inner.startswith('materials/materials0000/') else item.inner
        out.setdefault(key, []).append(dest)
    return dict((key, sorted(dests)) for key, dests in out.items())


def test_numbered_folders_of_the_owner(tmp):
    """The owner of the addon collects the files by hand: a folder "materials0000" with numbered
    folders in it, the files flat inside - and puts it into the materials folder of the addon, where
    other files lie right already, or drops it onto sort_content.bat."""
    in_place = {
        'materials/models/gate/shirt.vmt': material('models/gate/shirt'),
        'materials/models/gate/shirt.vtf': texture('shirt'),
    }
    for inside in (True, False):
        how = 'in the addon' if inside else 'dropped'

        # a material that only its name tells, its texture in another numbered folder; a normal
        # map that lies apart from its material
        numbered = {
            'materials0000/materials1/coat.vmt': material('models/shared/cloth'),
            'materials0000/materials 2/cloth.vtf': texture('cloth'),
            'materials0000/materials 3/hat.vmt': material('models/y/hat', bumpmap='models/common/normal'),
            'materials0000/materials 3/hat.vtf': texture('hat'),
            'materials0000/materials 4/normal.vtf': texture('normal'),
        }
        named = ['materials/models/gate/shirt.vmt', 'materials/models/x/coat.vmt', 'materials/models/y/hat.vmt']
        report, _placed = run(owners(tmp, 'by name', in_place, numbered, inside), named)
        got = went(report)
        check(got.get('materials0000/materials1/coat.vmt') == ['materials/models/x/coat.vmt'],
              'numbered folders %s: a material is found by its name: %s' % (how, got.get('materials0000/materials1/coat.vmt')))
        check(got.get('materials0000/materials 2/cloth.vtf') == ['materials/models/shared/cloth.vtf'] and
              got.get('materials0000/materials 4/normal.vtf') == ['materials/models/common/normal.vtf'],
              'numbered folders %s: a texture in another numbered folder is found by the name in the material' % how)
        check(not report.missing_named and got.get('materials/models/gate/shirt.vmt') == ['materials/models/gate/shirt.vmt'],
              'numbered folders %s: nothing is missing, what lay right stays: %s' % (how, report.missing_named))
        check(not report.as_packed, 'numbered folders %s: no file is called unknown: %s' % (how, report.as_packed))

        # A texture nothing is known about - no material names it, nobody names its folder. In the
        # addon it stays where it lies, and that is said: it is not counted as a file in its place.
        # Handed over without a materials folder above it, it has no place and is left out.
        numbered = {
            'materials0000/materials 20/mystery.vtf': texture('mystery'),
            'materials0000/materials 20/mystery too.vtf': texture('mystery too'),
            'materials0000/materials1/coat.vmt': material('models/x/coat'),
            'materials0000/materials1/coat.vtf': texture('coat'),
        }
        named = ['materials/models/gate/shirt.vmt', 'materials/models/x/coat.vmt']
        report, _placed = run(owners(tmp, 'unknown', in_place, numbered, inside), named)
        got = went(report)
        unknown = sorted(item.inner for item in report.as_packed)
        mystery = ['materials0000/materials 20/mystery too.vtf', 'materials0000/materials 20/mystery.vtf']
        if inside:
            check(all(got.get(path) == ['materials/' + path] for path in mystery) and
                  unknown == ['materials/' + path for path in mystery],
                  'numbered folders in the addon: a file nothing is known about stays and is listed as unknown: %s' % unknown)
        else:
            check(not any(path in got for path in mystery) and not unknown and
                  sorted(item.inner for item, why in report.left_out if why == P.UNNAMED) == mystery,
                  'numbered folders dropped: a file nothing is known about is left out: %s' % report.left_out)
        check(got.get('materials0000/materials1/coat.vmt') == ['materials/models/x/coat.vmt'] and
              got.get('materials0000/materials1/coat.vtf') == ['materials/models/x/coat.vtf'],
              'numbered folders %s: ... and the files next to it go where they belong' % how)

        # The Lua names a material in one folder, its textures are kept in another one, and the
        # owner put them together: the material goes where the Lua names it, not after its texture.
        # One material nobody names lies with them.
        numbered = {}
        for name in ('bib1', 'bib2', 'bib3', 'spare'):
            numbered['materials0000/materials 5/%s.vmt' % name] = material('models/bibtex/%s_d' % name)
            numbered['materials0000/materials 5/%s_d.vtf' % name] = texture(name)
        named = ['materials/models/gate/shirt.vmt'] + ['materials/models/humans/male/group01/bib%d.vmt' % n for n in (1, 2, 3)]
        report, _placed = run(owners(tmp, 'textures apart', in_place, numbered, inside), named)
        got = went(report)
        check(all(got.get('materials0000/materials 5/bib%d.vmt' % n) == ['materials/models/humans/male/group01/bib%d.vmt' % n]
                  for n in (1, 2, 3)) and not report.missing_named,
              'numbered folders %s: a named material goes where the Lua names it, not to the folder of its texture: %s'
              % (how, [got.get('materials0000/materials 5/bib%d.vmt' % n) for n in (1, 2, 3)]))
        check(all(got.get('materials0000/materials 5/%s_d.vtf' % name) == ['materials/models/bibtex/%s_d.vtf' % name]
                  for name in ('bib1', 'bib2', 'bib3', 'spare')),
              'numbered folders %s: its texture goes where the material names it' % how)

        # ... but a namesake is not taken for another name: a second sheet of the men is not the
        # sheet of the women, and a face that says it is of another folder is no face of this one
        numbered = {
            'materials0000/materials 6/sheet_01.vmt': material('models/humans/modern/male/sheet_01'),
            'materials0000/materials 6/sheet_01.vtf': texture('sheet of the men'),
            'materials0000/materials 7/sheet_01.vmt': material('models/humans/modern/male/sheet_01', phong='1'),
            'materials0000/materials 7/sheet_01.vtf': texture('another sheet of the men'),
            'materials0000/materials 8/facemap_01.vmt': material('models/humans/modern/male/male_02/facemap_01'),
            'materials0000/materials 8/facemap_01.vtf': texture('face 2'),
            'materials0000/materials 9/facemap_01.vmt': material('models/humans/modern/male/male_03/facemap_01'),
            'materials0000/materials 9/facemap_01.vtf': texture('face 3'),
        }
        named = ['materials/models/gate/shirt.vmt',
                 'materials/models/humans/modern/male/sheet_01.vmt', 'materials/models/humans/modern/female/sheet_01.vmt',
                 'materials/models/humans/modern/male/male_02/facemap_01.vmt',
                 'materials/models/humans/modern/male/male_04/facemap_01.vmt']
        report, placed = run(owners(tmp, 'namesakes', in_place, numbered, inside), named)
        check('materials/models/humans/modern/male/sheet_01.vmt' in placed and
              'materials/models/humans/modern/female/sheet_01.vmt' not in placed,
              'numbered folders %s: a second sheet of the men is not taken for the women' % how)
        check('materials/models/humans/modern/male/male_02/facemap_01.vmt' in placed and
              'materials/models/humans/modern/male/male_04/facemap_01.vmt' not in placed,
              'numbered folders %s: a face of another folder is not taken for a missing one' % how)

        # namesakes that nothing tells apart: three faces, each alone in its numbered folder, all
        # of them using one texture of another folder. Not guessed - and said, also when the
        # files lie in the addon and stay where they are
        numbered = dict(('materials0000/materials %d/cub_facemap.vmt' % n, material('models/humans/male/group01/cub', phong=str(n)))
                        for n in (10, 11, 12))
        groups = ['materials/models/humans/male/%s/cub_facemap.vmt' % g for g in ('group02', 'group03', 'group03m')]
        report, placed = run(owners(tmp, 'undecided', in_place, numbered, inside), ['materials/models/gate/shirt.vmt'] + groups)
        check(not any(path in placed for path in groups), 'numbered folders %s: namesakes that nothing tells apart are not guessed' % how)
        check(sum(1 for note in report.notes if note.kind in ('several names', 'several files')) >= 1,
              'numbered folders %s: ... and the report says so: %s' % (how, report.notes))
        unknown = sorted(item.inner for item in report.as_packed)
        check(unknown == (sorted('materials/' + path for path in numbered) if inside else []),
              'numbered folders %s: ... and they are not counted as files in their places: %s' % (how, unknown))

        check(any(note.kind == 'several names' and 'materials/models/humans/male/group03m' in note
                  and u'group03m' in content_report.note(note) for note in report.notes),
              'numbered folders %s: ... with the folders the file may be of, also in Russian: %s'
              % (how, [content_report.note(note) for note in report.notes][:1]))
        # ... a folder called like the one the file comes from is enough to tell them apart
        renamed = dict((path.replace('materials 10', 'group02').replace('materials 11', 'group03')
                        .replace('materials 12', 'group03m'), data) for path, data in numbered.items())
        report, placed = run(owners(tmp, 'last names', in_place, renamed, inside), ['materials/models/gate/shirt.vmt'] + groups)
        check(all(placed.get(path) is not None and placed[path].inner.split('/')[-2] == path.split('/')[-2] for path in groups),
              'numbered folders %s: namesakes in folders called like their own are told apart' % how)

        # ... unless they are one and the same file: then it does not matter which copy goes where
        numbered = dict(('materials0000/materials %d/cub_facemap.vmt' % n, material('models/humans/male/group01/cub'))
                        for n in (10, 11, 12))
        report, placed = run(owners(tmp, 'twins', in_place, numbered, inside), ['materials/models/gate/shirt.vmt'] + groups)
        check(all(path in placed for path in groups) and not report.missing_named,
              'numbered folders %s: the same file under one name in three folders fills the three names: %s'
              % (how, report.missing_named))
        # (two copies for three names: which name stays empty is not known)
        del numbered['materials0000/materials 12/cub_facemap.vmt']
        report, placed = run(owners(tmp, 'twins short', in_place, numbered, inside), ['materials/models/gate/shirt.vmt'] + groups)
        check(not any(path in placed for path in groups), 'numbered folders %s: two copies for three names are not guessed' % how)

    # A folder that is right - its own files say so - keeps what lies in it: a texture there is
    # not pulled out for a name it only shares with a missing one. The same below such a folder.
    pack = {
        'materials/models/pack/a.vmt': material('models/pack/a'),
        'materials/models/pack/a.vtf': texture('a'),
        'materials/models/pack/normal.vtf': texture('normal of the pack'),
        'materials/models/pack/sub/detail.vtf': texture('detail of the pack'),
        'materials/models/gate/shirt.vmt': material('models/gate/shirt', bumpmap='models/common/normal', detail='models/common/detail'),
        'materials/models/gate/shirt.vtf': texture('shirt'),
    }
    report, placed = run(owners(tmp, 'a right folder', pack, {}, True), ['materials/models/gate/shirt.vmt'])
    check('materials/models/common/normal.vtf' not in placed and 'materials/models/common/detail.vtf' not in placed and
          'materials/models/pack/normal.vtf' in placed and 'materials/models/pack/sub/detail.vtf' in placed,
          'a file is not pulled out of a folder that is right for a name it shares: %s' % sorted(placed))

    # ---- the whole way, through sort_content.py: the screenshot of the owner
    addon = os.path.join(tmp, 'numbered', 'zcity_csgo_gloves')
    files = {
        'lua/autorun/clothes.lua': '''
            hg.Appearance.FacemapsSlots["models/bloo_ltcom_zel/citizens/facemaps/naomi_facemap_new"] = {}
            hg.Appearance.Clothes[1].epl = "models/gate/epl"
            hg.Appearance.Clothes[1].shirt = "models/gate/shirt"
            hg.Appearance.Clothes[1].sheet = "models/humans/modern/male/sheet_01"
            hg.Appearance.Clothes[2].sheet = "models/humans/modern/female/sheet_01"
            hg.Appearance.Clothes[1].bib = "models/humans/male/group01/bib"
        ''',
        'materials/models/gate/shirt.vmt': material('models/gate/shirt'),
        'materials/models/gate/shirt.vtf': texture('shirt'),
        'materials/materials0000/materials1/naomi_facemap_new.vmt': material('models/bloo_ltcom_zel/citizens/facemaps/naomi_facemap_new'),
        'materials/materials0000/materials1/naomi_facemap_new.vtf': texture('naomi'),
        'materials/materials0000/materials 2/Epl.vmt': material('models/gate/textures/epl_d', bumpmap='models/gate/textures/epl_n'),
        'materials/materials0000/materials 2/epl_d.vtf': texture('epl'),
        'materials/materials0000/materials 3/epl_n.vtf': texture('epl normal'),
        'materials/materials0000/materials 4/sheet_01.vmt': material('models/humans/modern/male/sheet_01'),
        'materials/materials0000/materials 4/sheet_01.vtf': texture('sheet of the men'),
        'materials/materials0000/materials 5/sheet_01.vmt': material('models/humans/modern/female/sheet_01'),
        'materials/materials0000/materials 5/sheet_01.vtf': texture('sheet of the women'),
        'materials/materials0000/materials 6/bib.vmt': material('models/shared/cloth'),
    }
    for rel, data in files.items():
        write(os.path.join(addon, rel), data)
    sorted_to = {
        'materials/materials0000/materials1/naomi_facemap_new.vmt': 'materials/models/bloo_ltcom_zel/citizens/facemaps/naomi_facemap_new.vmt',
        'materials/materials0000/materials1/naomi_facemap_new.vtf': 'materials/models/bloo_ltcom_zel/citizens/facemaps/naomi_facemap_new.vtf',
        'materials/materials0000/materials 2/Epl.vmt': 'materials/models/gate/epl.vmt',
        'materials/materials0000/materials 2/epl_d.vtf': 'materials/models/gate/textures/epl_d.vtf',
        'materials/materials0000/materials 3/epl_n.vtf': 'materials/models/gate/textures/epl_n.vtf',
        'materials/materials0000/materials 4/sheet_01.vmt': 'materials/models/humans/modern/male/sheet_01.vmt',
        'materials/materials0000/materials 4/sheet_01.vtf': 'materials/models/humans/modern/male/sheet_01.vtf',
        'materials/materials0000/materials 5/sheet_01.vmt': 'materials/models/humans/modern/female/sheet_01.vmt',
        'materials/materials0000/materials 5/sheet_01.vtf': 'materials/models/humans/modern/female/sheet_01.vtf',
        'materials/materials0000/materials 6/bib.vmt': 'materials/models/humans/male/group01/bib.vmt',
    }
    want = dict((sorted_to.get(rel, rel), data if isinstance(data, bytes) else data.encode('utf-8')) for rel, data in files.items())
    code, text = sort('--addon', addon)
    got = tree(addon)
    report = got.pop(sort_content.REPORT, b'').decode('utf-8-sig')
    check(code == 0 and sorted(got) == sorted(want), 'numbered folders with the files flat inside are sorted: only in one of the two %s'
          % sorted(set(got) ^ set(want)))
    check(got == want, 'numbered folders: no file was changed, lost or made up')
    check(not os.path.isdir(os.path.join(addon, 'materials', 'materials0000')), 'numbered folders: the empty folders are gone')
    check(u'materials/models/shared/cloth.vtf  <-  materials/models/humans/male/group01/bib.vmt' in report,
          'numbered folders: a texture that was not brought along is named in the report')
    check(u'Уже лежит на своём месте: 2\n' in text.replace('\r\n', '\n') and u'Оставлено в тех же папках' not in text and
          u'Оставлено в тех же папках — файлов: 0 ' in report,
          'numbered folders: every file is known, and that is what the tool says')

    # ... a file nothing is known about, put into a numbered folder afterwards: it stays, nothing
    # else moves, and the tool says that it does not know the file - on the screen and in the report
    for name in ('mystery.vtf', 'Mystery Too.vtf'):
        write(os.path.join(addon, 'materials', 'materials0000', 'materials 7', name), texture(name))
    before = tree(addon)
    before.pop(sort_content.REPORT, None)
    code, text = sort('--addon', addon)
    got = tree(addon)
    report = got.pop(sort_content.REPORT, b'').decode('utf-8-sig').replace('\r\n', '\n')
    # (the name is put into lower case, as every path of the game)
    moved = dict((rel.lower() if 'materials 7' in rel else rel, data) for rel, data in before.items())
    check(code == 0 and got == moved and 'materials/materials0000/materials 7/mystery too.vtf' in got,
          'numbered folders: a file nothing is known about stays in its folder: %s' % sorted(set(got) ^ set(moved)))
    text = text.replace('\r\n', '\n')
    check(u'Уже лежит на своём месте: 12\n' in text and u'перемещено внутри аддона: 0\n' in text and
          u'Оставлено в тех же папках (про эти файлы ничего не известно, папки — в отчёте): 2\n' in text,
          'numbered folders: ... and is counted neither as a file in its place nor as a moved one: %s'
          % [line.encode('ascii', 'backslashreplace').decode('ascii') for line in text.split('\n') if u': 2' in line or u': 12' in line])
    check(u'Оставлено в тех же папках — файлов: 2 ' in report and
          u'\n    zcity_csgo_gloves/materials/materials0000/materials 7/    файлов: 2    [zcity_csgo_gloves]\n' in report,
          'numbered folders: ... and the report names its folder')


def test_sorting(tmp):
    # (a path as the game has it: blanks, brackets, Russian letters)
    addon = os.path.join(tmp, u'Program Files (x86)', u'\u0438\u0433\u0440\u0430', 'addons', 'zcity_csgo_gloves')
    files = an_addon(addon)
    want = dict((SORTED.get(rel, rel), data if isinstance(data, bytes) else data.encode('utf-8'))
                for rel, data in files.items())

    # a trial run changes nothing
    before = tree(addon)
    code, text = sort('--addon', addon, '--dry-run')
    after = tree(addon)
    after.pop(sort_content.REPORT, None)
    check(code == 0 and after == before, 'sorting, a trial run: nothing is moved')
    check(u'\u041f\u0420\u041e\u0411\u041d\u042b\u0419' in text, 'and it says that it was a trial run')

    code, text = sort('--addon', addon)
    got = tree(addon)
    report = got.pop(sort_content.REPORT, b'').decode('utf-8-sig')
    check(code == 0, 'sorting an addon in place: exit code %s' % code)
    check(sorted(got) == sorted(want), 'every file is where the game looks for it: only in one of the two %s'
          % sorted(set(got) ^ set(want)))
    check(got == want, 'and no file was changed, lost or made up')
    check(not os.path.isdir(os.path.join(addon, 'materials', 'Gate')) and not os.path.isdir(os.path.join(addon, 'materials', 'material 1'))
          and not os.path.isdir(os.path.join(addon, 'models', 'model 1')) and not os.path.isdir(os.path.join(addon, sort_content.STAGE)),
          'the folders that are empty now are gone, the stage folder too')
    for line in (u'[zcity_csgo_gloves]', u'zcity_csgo_gloves/materials/gate/  ->  materials/models/gate/',
                 u'materials/models/gate/gone.vmt', u'materials/models/humans/slav/eyes.vmt  <-  models/slav/m/male_10.mdl',
                 u'materials/models/gate/shirt_n.vtf  <-  materials/models/gate/shirt.vmt  $bumpmap'):
        check(line in report, 'the report of the sorting has: %s' % line)
    check(u'models/humans/male/group01/normal' not in report, 'a file that Z-City names itself is not asked for')
    check(u': 15\n' in text and sort_content.ASIDE + u' (' in text, 'the screen tells how many files were moved: %r' % text[-900:])

    # once more: nothing left to do
    code, text = sort('--addon', addon)
    again = tree(addon)
    again.pop(sort_content.REPORT, None)
    check(code == 0 and again == want, 'sorting twice changes nothing more')

    # ---- content from outside: a folder and an archive, copied in; what is there stays
    addon2 = os.path.join(tmp, 'addons2', 'zcity_csgo_gloves')
    files2 = {
        'addon.json': '{}',
        'lua/autorun/clothes.lua': files['lua/autorun/clothes.lua'],
        'materials/models/gate/shirt.vmt': material('models/gate/shirt'),
    }
    for rel, data in files2.items():
        write(os.path.join(addon2, rel), data)
    outside = os.path.join(tmp, u'\u043a\u043e\u043d\u0442\u0435\u043d\u0442 \u2014 \u043a\u043e\u043f\u0438\u044f')
    write(os.path.join(outside, 'materials/gate/epl.vmt'), material('models/gate/epl'))
    write(os.path.join(outside, 'materials/gate/epl.vtf'), texture('epl'))
    write(os.path.join(outside, 'materials/gate/shirt.vmt'), material('models/gate/other_shirt'))
    write(os.path.join(outside, 'materials/gate/shirt.vtf'), texture('shirt'))
    write(os.path.join(outside, 'materials/gate/icon.png'), b'png')
    write(os.path.join(outside, 'lua/autorun/more.lua'), 'print("x")')
    write(os.path.join(outside, 'readme.txt'), 'hello')
    archive = os.path.join(tmp, 'material 1.zip')
    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr('material 1/sheet_01.vmt', material('models/humans/modern/male/sheet_01'))
        z.writestr('material 1/sheet_01.vtf', texture('sheet of the men'))
    outside_before = tree(outside)
    code, text = sort('--addon', addon2, outside, archive)
    got = tree(addon2)
    report = got.pop(sort_content.REPORT, b'').decode('utf-8-sig')
    check(code == 0, 'sorting with content from outside: exit code %s' % code)
    check(sorted(got) == ['addon.json', 'lua/autorun/clothes.lua', 'materials/gate/icon.png', 'materials/models/gate/epl.vmt',
                          'materials/models/gate/epl.vtf', 'materials/models/gate/shirt.vmt', 'materials/models/gate/shirt.vtf',
                          'materials/models/humans/modern/male/sheet_01.vmt', 'materials/models/humans/modern/male/sheet_01.vtf'],
          'content from a folder and from an archive is copied to its places: %s' % sorted(got))
    check(got['materials/models/gate/shirt.vmt'] == material('models/gate/shirt').encode(),
          'a file of the addon is not replaced by one from outside')
    check(u'materials/gate/shirt.vmt' in report and u'\u0435\u0433\u043e \u043c\u0435\u0441\u0442\u043e \u0437\u0430\u043d\u044f\u043b' in report,
          'the other version is named in the report, with the reason')
    check(tree(outside) == outside_before and os.path.isfile(archive), 'what was given from outside is left as it is')
    check(u'readme.txt' in report and u'more.lua' not in tree(addon2), 'Lua and notes from outside are not taken')

    # ---- a run that was cut off: the files in the stage folder go where they were going
    addon3 = os.path.join(tmp, 'addons3', 'zcity_csgo_gloves')
    write(os.path.join(addon3, 'lua/autorun/clothes.lua'), files['lua/autorun/clothes.lua'])
    write(os.path.join(addon3, sort_content.STAGE, '000000'), material('models/gate/epl'))
    write(os.path.join(addon3, sort_content.STAGE, '000001'), texture('epl'))
    write(os.path.join(addon3, sort_content.STAGE, 'journal.txt'),
          '000000\tmaterials/models/gate/epl.vmt\tmaterials/Gate/Epl.VMT\n'
          '000001\tmaterials/models/gate/epl.vtf\tmaterials/Gate/epl.vtf\n'
          '000002\tmaterials/models/gate/never.vtf\tmaterials/Gate/never.vtf\n')
    code, text = sort('--addon', addon3)
    got = tree(addon3)
    got.pop(sort_content.REPORT, None)
    check(code == 0 and sorted(got) == ['lua/autorun/clothes.lua', 'materials/models/gate/epl.vmt', 'materials/models/gate/epl.vtf'],
          'a run that was cut off is finished first: %s' % sorted(got))

    # ---- a file that cannot be moved (the game has it open): it stays, nothing is lost
    addon4 = os.path.join(tmp, 'addons4', 'zcity_csgo_gloves')
    an_addon(addon4)
    before = tree(addon4)
    real = os.replace

    def stuck(src, dst):
        if src.replace(os.sep, '/').endswith('materials/Gate/epl.vtf'):
            raise PermissionError(13, 'the file is used by another process')
        return real(src, dst)

    sort_content.os.replace = stuck
    try:
        code, text = sort('--addon', addon4)
    finally:
        sort_content.os.replace = real
    got = tree(addon4)
    got.pop(sort_content.REPORT, None)
    check(code == 2, 'a file that cannot be moved: the exit code says so (%s)' % code)
    check('materials/Gate/epl.vtf' in got and 'materials/models/gate/epl.vmt' in got,
          'it stays where it was, the others are moved')
    check(sorted(got.values()) == sorted(before.values()), 'and no file is lost or made up')
    code, text = sort('--addon', addon4)
    got = tree(addon4)
    got.pop(sort_content.REPORT, None)
    check(code == 0 and 'materials/models/gate/epl.vtf' in got and 'materials/Gate/epl.vtf' not in got,
          'the next run moves it')

    # ---- not an addon
    code, text = sort('--addon', os.path.join(tmp, 'nowhere'))
    check(code == 1 and u'\u041e\u0428\u0418\u0411\u041a\u0410' in text, 'a folder that is no addon is refused')
    code, text = sort('--addon', addon2, os.path.join(tmp, 'no such folder'))
    check(code == 1, 'a source that does not exist is refused')


# the clothes of "[ZCITY] Drill Clothes": materials named from inside the materials folder, in a
# table of pairs - nothing the text of the Lua shows as the name of a file
DRILL = ['players_sheet_02', 'players_sheet_04', 'players_sheet_06', 'players_sheet_07', 'players_sheet_09',
         'sheet_01', 'sheet_16'] + ['sheet_%d' % n for n in range(31, 46)]


def text_names():
    """what the text of the drop-in Lua shows, whether or not Lua can be run here"""
    named = set()
    for archive in L.dropin_archives(ROOT):
        if not archive.lower().endswith('.zip'):
            continue
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                dest = None if info.is_dir() else L.dropin_destination(L.zip_name(info))
                if dest and dest.endswith('.lua'):
                    named |= list_content.names_in(z.read(info).decode('utf-8-sig', 'replace'))
    return named - list_content.stock_names()


def test_namesakes_of_a_pack(tmp):
    """A material the Lua names in several folders - sheet_16.vmt of the Drill clothes and of the
    Appearance Mod - packed with its texture in a folder that says nothing, the texture named in
    a folder of its own. What is packed with it tells which pack it is of; what is left
    undecided is told; what an earlier version of the tool misplaced is put right."""
    male = 'materials/models/humans/modern/male/'
    twice = ('sheet_01', 'sheet_16', 'sheet_31')
    named = set('materials/zcity_drill/%s.vmt' % name for name in DRILL) | set(male + name + '.vmt' for name in twice)

    def pack(label, names, textures='models/drill_pack/', folder='materials 14'):
        root = os.path.join(tmp, 'pack ' + label)
        for name in names:
            write(os.path.join(root, 'materials0000', folder, name + '.vmt'), material(textures + name))
            write(os.path.join(root, 'materials0000', folder, name + '.vtf'), texture(textures + name))
        return root

    def placed_from(root):
        items = [P.Item('addon', 'materials/' + rel, full, 'materials/' + rel.lower(), 1)
                 for rel, full in sorted(build_addon.walk_files(root))]
        report = P.place(items, set(named), lambda path: False)
        where = collections.defaultdict(list)
        for dest, item in report.placed:
            where[item.inner.split('/', 1)[1]].append(dest)
        return report, where

    def kinds(report):
        return sorted(getattr(note, 'kind', '?') for note in report.notes)

    # the whole pack: the nineteen materials only the Drill Lua names say what "models/drill_pack" is
    report, where = placed_from(pack('whole', DRILL))
    wrong = sorted(name for name in DRILL
                   if where.get('materials0000/materials 14/%s.vmt' % name) != ['materials/zcity_drill/%s.vmt' % name]
                   or where.get('materials0000/materials 14/%s.vtf' % name) != ['materials/models/drill_pack/%s.vtf' % name])
    check(not wrong, 'a pack that keeps its textures in a folder of their own: every material goes where the Lua '
                     'names it, namesakes of another pack too, every texture where its material names it: not %s' % wrong)
    check(not report.notes and not [path for path in report.missing_named if 'zcity_drill' in path],
          'nothing of it is missing, nothing to remark: %s' % report.notes)
    check(sorted(path for path in report.missing_named) == sorted(male + name + '.vmt' for name in twice),
          'the namesakes of the other pack stay missing: nothing was taken for them')

    # the three namesakes alone: nothing says which pack they are of
    report, where = placed_from(pack('three', twice))
    check(all(where.get('materials0000/materials 14/%s.vmt' % name) == ['materials/models/drill_pack/%s.vmt' % name] for name in twice),
          'the namesakes alone are not taken for either name: they stay with their textures: %s' % dict(where))
    check(kinds(report) == ['same name'] * 3, 'and each of them is told: %s' % kinds(report))
    told = [note for note in report.notes if 'sheet_16.vmt' in note]
    russian = content_report.note(told[0]) if told else u''
    check(len(told) == 1 and 'materials/models/drill_pack/' in told[0]
          and 'materials/models/humans/modern/male/, materials/zcity_drill/' in told[0],
          'with the place it went to and the folders the Lua names such a file in: %s' % told)
    check(u'materials/zcity_drill/' in russian and u'materials 14/sheet_16.vmt' in russian and russian != told[0],
          'in Russian too: %s' % russian.encode('ascii', 'backslashreplace').decode('ascii'))
    # the next run finds them where this one put them: the names are still empty, so it is told again
    out = os.path.join(tmp, 'pack three, sorted')
    for dest, item in report.placed:
        build_addon.copy(item.path, os.path.join(out, dest))
    items = [P.Item('addon', rel, full, rel, 1) for rel, full in sorted(build_addon.walk_files(out))]
    again = P.place(items, set(named), lambda path: False)
    check(all(dest == item.inner for dest, item in again.placed) and not again.left_out, 'supplied again, nothing moves')
    check(kinds(again) == ['same name'] * 3 and any('materials/models/drill_pack/sheet_16.vmt' in note for note in again.notes),
          'and the three are told again, where they lie now: %s' % again.notes)

    # a file of another pack among them: its texture is named elsewhere, so the others tell nothing about it
    root = pack('a stranger', [name for name in DRILL if name not in twice])
    write(os.path.join(root, 'materials0000', 'materials 14', 'sheet_16.vmt'), material('models/other_pack/sheet_16'))
    write(os.path.join(root, 'materials0000', 'materials 14', 'sheet_16.vtf'), texture('other'))
    report, where = placed_from(root)
    check(where.get('materials0000/materials 14/sheet_16.vmt') == ['materials/models/other_pack/sheet_16.vmt'],
          'a namesake whose texture is named in another folder than those of the pack is not taken for it: %s'
          % where.get('materials0000/materials 14/sheet_16.vmt'))
    check(kinds(report) == ['same name'], 'it is told instead: %s' % kinds(report))

    # the pack cut into two uploads with the same folder in each
    root = pack('cut', [name for name in DRILL if name not in twice])
    more = pack('cut more', twice)
    items = [P.Item(source, 'materials/' + rel, full, None, order)
             for order, (source, base) in enumerate((('one.zip', root), ('two.zip', more)), 1)
             for rel, full in sorted(build_addon.walk_files(base))]
    report = P.place(items, set(named), lambda path: False)
    placed = dict(report.placed)
    check(all('materials/zcity_drill/%s.vmt' % name in placed for name in DRILL) and not report.notes,
          'cut into two archives with the same folder in each: the namesakes are known by the rest all the same: %s'
          % sorted(name for name in DRILL if 'materials/zcity_drill/%s.vmt' % name not in placed))

    # two different files that the rest of the pack speaks for alike: not told apart, none is taken
    root = pack('two versions', [name for name in DRILL if name not in twice] + ['sheet_16'])
    for name in ('players_sheet_02', 'sheet_16'):
        write(os.path.join(root, 'materials0000', 'materials 15', name + '.vmt'),
              material('models/drill_pack/' + name) + ('// another version\n' if name == 'sheet_16' else ''))
        write(os.path.join(root, 'materials0000', 'materials 15', name + '.vtf'), texture('models/drill_pack/' + name))
    report, where = placed_from(root)
    taken = [inner for inner, dests in where.items() if 'materials/zcity_drill/sheet_16.vmt' in dests]
    check(not taken and 'materials/zcity_drill/sheet_16.vmt' in report.missing_named,
          'two different namesakes, each packed with files of the pack: none of the two is taken: %s' % taken)
    check(kinds(report) == ['several files', 'version']
          and any(note.kind == 'several files' and 'materials/zcity_drill/sheet_16.vmt' in note for note in report.notes),
          'and that is told: %s' % report.notes)

    # ---- what the tool of 2.3.0 left: the material at the place of its namesake, its texture where it belongs
    def left_by_230(label, base='zcity_drill/sheet_16', more=()):
        root = os.path.join(tmp, 'left ' + label)
        write(os.path.join(root, 'models/humans/modern/male/sheet_16.vmt'), material(base))
        write(os.path.join(root, 'zcity_drill/sheet_16.vtf'), texture('drill 16'))
        for rel, data in more:
            write(os.path.join(root, rel), data)
        items = [P.Item('addon', 'materials/' + rel, full, 'materials/' + rel.lower(), 1)
                 for rel, full in sorted(build_addon.walk_files(root))]
        report = P.place(items, set(named), lambda path: False)
        return report, dict(report.placed)

    report, placed = left_by_230('as it was')
    there, here = placed.get(male + 'sheet_16.vmt'), placed.get('materials/zcity_drill/sheet_16.vmt')
    check(there is not None and here is there,
          'a material lying at the place of its namesake, made of the very texture of the missing name, is used for that name as well')
    check(kinds(report) == ['also here'] and 'materials/zcity_drill/sheet_16.vmt' in report.notes[0] and male + 'sheet_16.vmt' in report.notes[0],
          'and that is told: %s' % report.notes)
    check('materials/zcity_drill/sheet_16.vmt' not in report.missing_named and male + 'sheet_16.vmt' not in report.missing_named,
          'neither name is missing then')
    report, placed = left_by_230('another texture', base='zcity_drill/sheet_17')
    check('materials/zcity_drill/sheet_16.vmt' not in placed and not report.notes,
          'a material made of another texture is not: %s' % report.notes)
    report, placed = left_by_230('both', more=[('materials 14/sheet_16.vmt', material('zcity_drill/sheet_16') + '// its own\n')])
    here = placed.get('materials/zcity_drill/sheet_16.vmt')
    check(here is not None and here.inner == 'materials/materials 14/sheet_16.vmt' and not report.notes,
          'and with the file of that name at hand, that one is taken: %s' % here)


# (a file Z-City's loader runs after its own sh_shared.lua, which makes the tables)
TABLE_LUA = 'homigrad/new_appearance/sh_shared_table.lua'


def a_table_addon(folder):
    """an installed addon whose Lua names two materials in a table, from inside the materials
    folder - one of them a namesake of a material it names in full and has no file for"""
    files = {
        'lua/' + TABLE_LUA: '''
            hg.Appearance.Clothes[1].sheet16 = "models/humans/modern/male/sheet_16"
            local drill = { {"Drill 07", "zcity_drill/sheet_16"}, {"Drill 01", "zcity_drill/players_sheet_02"} }
            for _, item in ipairs(drill) do hg.Appearance.Clothes[1][item[1]] = item[2] end
        ''',
        'materials/material 5/sheet_16.vmt': material('zcity_drill/sheet_16'),
        'materials/material 5/sheet_16.vtf': texture('drill 16'),
        'materials/material 5/players_sheet_02.vmt': material('zcity_drill/players_sheet_02'),
        'materials/material 5/players_sheet_02.vtf': texture('drill 02'),
    }
    for rel, data in files.items():
        write(os.path.join(folder, rel), data)
    return files


# what running that Lua gives, and where its files belong
TABLE_NAMES = ('materials/zcity_drill/sheet_16.vmt', 'materials/zcity_drill/players_sheet_02.vmt',
               'materials/models/humans/modern/male/sheet_16.vmt')
TABLE_SORTED = ['lua/' + TABLE_LUA, 'materials/zcity_drill/players_sheet_02.vmt', 'materials/zcity_drill/players_sheet_02.vtf',
                'materials/zcity_drill/sheet_16.vmt', 'materials/zcity_drill/sheet_16.vtf']


def test_names_found_by_running(tmp):
    """Names the text of the Lua does not show reach sort_content.py as a list the build makes by
    running that Lua. Without them a file is taken for its namesake of another pack."""
    drill = set('materials/zcity_drill/%s.vmt' % name for name in DRILL)
    text = text_names()
    check(len(DRILL) == 22 and not (drill & text), 'the names of the Drill clothes are not to be read in the text of their Lua')
    check('materials/models/humans/modern/male/sheet_16.vmt' in text and 'materials/models/humans/modern/male/sheet_31.vmt' in text,
          'and two of them are namesakes of materials another pack names')

    # the folder of the owner: the Drill files in a folder that says nothing; the namesakes of the
    # other pack are not at hand
    def trial(label, named, folder):
        root = os.path.join(tmp, 'drill ' + label)
        for name in DRILL:
            write(os.path.join(root, 'materials0000', folder, name + '.vmt'), material('zcity_drill/' + name))
            write(os.path.join(root, 'materials0000', folder, name + '.vtf'), texture('zcity_drill/' + name))
        items = [P.Item('addon', 'materials/' + rel, full, 'materials/' + rel.lower(), 1)
                 for rel, full in sorted(build_addon.walk_files(root))]
        report = P.place(items, set(named), lambda path: False)
        placed = dict((item.inner.rsplit('/', 1)[1], dest) for dest, item in report.placed)
        return sorted(name + ext for name in DRILL for ext in ('.vmt', '.vtf')
                      if placed.get(name + ext) != 'materials/zcity_drill/' + name + ext)

    wrong = trial('known', text | drill, 'materials 14')
    check(not wrong, 'with their names known every Drill file goes to materials/zcity_drill: not %s' % wrong)
    wrong = trial('own folder', text | drill, 'ZCity_Drill')
    check(not wrong, 'and from a folder called like theirs as well: not %s' % wrong)
    # (what the build takes: with the names found by running where Lua can be run - else, as on
    # the computer of the owner, with the list the build left; that is tried further down)
    ran = list_content.run_names() is not None
    wrong = trial('as the build knows them', named_by_the_lua() if ran else text | drill, 'materials 14')
    check(not wrong, 'the names the build takes%s are enough for that: not %s' % ('' if ran else ' (not run here)', wrong))

    # ---- the list
    lua = {'autorun/drill.lua': u'local t = {{"Drill 07", "zcity_drill/sheet_16"}}\r\nprint("\u043e\u0434\u0435\u0436\u0434\u0430")\r\n',
           'homigrad/new_appearance/sh_more.lua': u'hg.Appearance.Clothes[1].epl = "models/gate/epl"\n'}
    lists = os.path.join(tmp, 'lists')
    os.makedirs(lists)
    path = os.path.join(lists, list_content.RUN_LIST)
    list_content.write_run_list(path, ['materials/zcity_drill/sheet_16.vmt', 'materials/models/gate/epl.vmt'], lua)
    names, made_from, ran = list_content.read_run_list(path)
    check(names == {'materials/zcity_drill/sheet_16.vmt', 'materials/models/gate/epl.vmt'} and ran is True,
          'the list of the names found by running is read back: %s' % sorted(names))
    check(sorted(made_from) == sorted(lua), 'with the Lua files it was made from: %s' % sorted(made_from or ()))
    check(made_from['autorun/drill.lua'] == list_content.lua_fingerprint(lua['autorun/drill.lua'].replace(u'\r\n', u'\n')),
          'the line ends of a Lua file do not make it another file')
    check(list_content.read_run_list(os.path.join(lists, 'none.txt')) == (set(), None, False), 'no list: nothing, and it is known')
    not_run = os.path.join(lists, 'not run.txt')
    list_content.write_run_list(not_run, [], lua, ran=False)
    check(list_content.read_run_list(not_run) == (set(), dict((name, list_content.lua_fingerprint(text)) for name, text in lua.items()), False),
          'a list made where Lua could not be run says so')
    failing = os.path.join(lists, 'failed.txt')
    error = "autorun/drill.lua:4: attempt to index local 't' (a nil value)"
    list_content.write_run_list(failing, ['materials/models/gate/epl.vmt'], lua,
                                failed={'autorun/drill.lua': error.replace(' (a', '\t(a') + '\nstack traceback:'})
    check(list_content.read_run_failed(failing) == {'autorun/drill.lua': error + ' stack traceback:'}
          and list_content.read_run_list(failing)[0] == {'materials/models/gate/epl.vmt'},
          'a Lua file that stopped with an error is written into the list, on one line, and is not taken for a name: %s'
          % list_content.read_run_failed(failing))
    check(list_content.read_run_failed(path) == {} and list_content.read_run_failed(os.path.join(lists, 'none.txt')) == {},
          'no such file, no such line')

    # ---- what sort_content.py makes of it
    folder = os.path.join(tmp, 'named', 'lua')
    for name, data in lua.items():
        write(os.path.join(folder, name), data)
    # (the Lua of the gloves is not read)
    write(os.path.join(folder, 'zcity_csgo_gloves', 'sh_data.lua'), 'local own = "models/zcity_csgo_gloves/x.mdl"')
    got = sort_content.names_of([folder], path)
    check(got.named == {'materials/zcity_drill/sheet_16.vmt', 'materials/models/gate/epl.vmt'} and got.files == 2,
          'sort_content.py takes the names of the text and of the list: %s' % sorted(got.named))
    check(got.listed == 2 and got.by_running == 1 and not got.changed and not got.not_run,
          'and knows how many only running shows: %s of %s, changed %s' % (got.by_running, got.listed, got.changed))
    got = sort_content.names_of([folder], os.path.join(lists, 'none.txt'))
    check(got.named == {'materials/models/gate/epl.vmt'} and got.listed is None, 'without the list: the text alone, and that is known')
    got = sort_content.names_of([folder], not_run)
    check(got.not_run and got.listed == 0, 'a list of a build that could not run Lua is told apart')
    check(not got.failed and sort_content.names_of([folder], failing).failed == [('autorun/drill.lua', error + ' stack traceback:')],
          'sort_content.py knows which Lua file stopped with an error when the addon was built')
    write(os.path.join(folder, 'autorun', 'drill.lua'), lua['autorun/drill.lua'] + u'-- changed\n')
    write(os.path.join(folder, 'autorun', 'new.lua'), u'print(1)')
    got = sort_content.names_of([folder], path)
    check(got.changed == ['autorun/drill.lua', 'autorun/new.lua'], 'Lua that was changed or added after the build is named: %s' % got.changed)
    check('materials/zcity_drill/sheet_16.vmt' in got.named, '(the names of the list are used all the same)')
    check(sort_content.names_of([folder], failing).failed == [], 'a Lua file that was changed since is not the one that failed')

    # ---- the whole tool: a material named in a table, a namesake of one the other pack names
    def addon(label):
        root = os.path.join(tmp, 'by running ' + label, 'zcity_csgo_gloves')
        return root, a_table_addon(root)

    root, files = addon('with the list')
    path = os.path.join(lists, 'drill.txt')
    list_content.write_run_list(path, TABLE_NAMES, {TABLE_LUA: files['lua/' + TABLE_LUA]})
    code, text = sort('--addon', root, '--names-list', path)
    got = tree(root)
    got.pop(sort_content.REPORT, None)
    check(code == 0 and sorted(got) == TABLE_SORTED,
          'sort_content.py with the list: a material named in a table goes to its own place, not to its namesake\'s: %s' % sorted(got))
    check(u'\u0432 \u0442\u0435\u043a\u0441\u0442\u0435 Lua \u043d\u0435 \u0432\u0438\u0434\u043d\u044b' in text
          and u'\u0412\u041d\u0418\u041c\u0410\u041d\u0418\u0415' not in text,
          'it tells how many names only running shows, and has nothing to warn of: %r' % text[:500])

    root, files = addon('without the list')
    code, text = sort('--addon', root, '--names-list', os.path.join(lists, 'none.txt'), '--dry-run')
    check(code == 0 and u'\u0412\u041d\u0418\u041c\u0410\u041d\u0418\u0415' in text, 'without the list it warns: %r' % text[:500])

    root, files = addon('changed Lua')
    write(os.path.join(root, 'lua/autorun/mine.lua'), u'local t = {"zcity_mine/shirt_" .. 1}')
    code, text = sort('--addon', root, '--names-list', path, '--dry-run')
    check(code == 0 and u'\u0412\u041d\u0418\u041c\u0410\u041d\u0418\u0415' in text and u'autorun/mine.lua' in text,
          'a Lua file added after the build is named in a warning: %r' % text[:600])

    root, files = addon('failed Lua')
    failing = os.path.join(lists, 'drill failed.txt')
    list_content.write_run_list(failing, TABLE_NAMES, {TABLE_LUA: files['lua/' + TABLE_LUA]}, failed={TABLE_LUA: TABLE_LUA + ':3: boom'})
    code, text = sort('--addon', root, '--names-list', failing, '--dry-run')
    check(code == 0 and u'\u0412\u041d\u0418\u041c\u0410\u041d\u0418\u0415: \u043f\u0440\u0438 \u0441\u0431\u043e\u0440\u043a\u0435' in text
          and TABLE_LUA + u':3: boom' in text,
          'a Lua file that stopped with an error when the addon was built is named in a warning, with the error: %r' % text[:700])


def test_the_build_takes_lua(tmp):
    """build_addon.step_dropins with archives of Lua: what running it tells, an archive that
    brings nothing, two versions of one script"""
    repo = os.path.join(tmp, 'a repository')
    table = '''
        local drill = { {"Drill 07", "zcity_drill/sheet_16"} }
        for _, item in ipairs(drill) do hg.Appearance.Clothes[1][item[1]] = item[2] end
        hg.Appearance.Clothes[1].epl = "models/gate/epl"
    '''

    def archive(name, files):
        os.makedirs(repo, exist_ok=True)
        with zipfile.ZipFile(os.path.join(repo, name), 'w') as z:
            for inner, data in files.items():
                z.writestr(inner, data)

    def build(label):
        out = os.path.join(tmp, 'built ' + label)
        real = build_addon.HERE
        build_addon.HERE = repo
        try:
            return (out,) + tuple(build_addon.step_dropins(None, os.path.join(tmp, 'unpacked ' + label), out))
        finally:
            build_addon.HERE = real

    archive('pack one.zip', {'drill/addon.json': '{"title": "Drill"}', 'drill/lua/' + TABLE_LUA: table})
    archive('pack two.zip', {'rp_update/addon.json': '{"title": "RP"}'})
    out, sources, _content, named, ran = build('first')
    by_name = dict((entry['name'], entry) for entry in sources)
    check(by_name['pack one.zip']['counts']['lua'] == 1 and os.path.isfile(os.path.join(out, 'lua', TABLE_LUA)),
          'the build takes the Lua of an archive')
    check(by_name['pack two.zip']['no_place'] == ['rp_update/addon.json'] and not sum(by_name['pack two.zip']['counts'].values()),
          'an archive with nothing but an addon.json brings nothing, and the build knows which file that was')
    check('materials/models/gate/epl.vmt' in named, 'the names in the text of the Lua are taken')
    scripts, _stock, listed = build_addon.step_sort_tool(out, ran)
    names, made_from, was_run = list_content.read_run_list(os.path.join(out, build_addon.SORT_TOOL_DIR, list_content.RUN_LIST))
    check(sorted(made_from or ()) == [TABLE_LUA], 'the list for sort_content.py tells which Lua it was made from: %s' % sorted(made_from or ()))
    bound = os.path.join(out, 'lua', build_addon.BOUND_LUA)
    if ran['result'] is not None:
        check('materials/zcity_drill/sheet_16.vmt' in named and ran['only'] == {'materials/zcity_drill/sheet_16.vmt'},
              'the build runs the Lua: a name in a table is taken too (%s)' % sorted(ran['only']))
        check(was_run and names == {'materials/zcity_drill/sheet_16.vmt', 'materials/models/gate/epl.vmt'} and listed == 2,
              'and written into the list for sort_content.py: %s' % sorted(names))
        check(any('1 of these names are not to be read' in line for line in build_addon.lua_run_lines(ran)), 'the build tells about it')

        # what the tables hold then, for the game to compare its own with (zcg_content)
        text = io.open(bound, encoding='ascii').read() if os.path.isfile(bound) else ''
        check('\t[%s] = {\n\t\t{ "Clothes/1/Drill 07", "zcity_drill/sheet_16" },\n\t\t{ "Clothes/1/epl", "models/gate/epl" },\n\t},'
              % build_addon.lua_string(TABLE_LUA) in text and ran['bound'] == 2,
              'the build writes the entries that Lua makes into the addon, for the game: %s' % text[-300:])
        check(any('lua/%s' % build_addon.BOUND_LUA in line for line in build_addon.lua_run_lines(ran)), 'and tells where')
        entries = build_addon.bound_entries(ran['result'])
        lua_files = build_addon.lua_names.folder_files(os.path.join(out, 'lua'))
        try:
            build_addon.check_bound(bound, entries, lua_files)
            check(True, 'read back by the check of the addon, the list says what the tables hold')
        except build_addon.BuildError as err:
            check(False, 'read back by the check of the addon, the list says what the tables hold: %s' % err)
        for label, wrong in (('another value', text.replace('zcity_drill/sheet_16', 'zcity_drill/sheet_17')),
                             ('another name', text.replace('Clothes/1/epl', 'Clothes/1/Epl')),
                             ('an entry less', text.replace('\t\t{ "Clothes/1/epl", "models/gate/epl" },\n', ''))):
            wrong_file = os.path.join(tmp, 'wrong sh_bound.lua')
            write(wrong_file, wrong)
            try:
                build_addon.check_bound(wrong_file, entries, lua_files)
                check(False, 'a list that says something else (%s) stops the build' % label)
            except build_addon.BuildError as err:
                check(build_addon.BOUND_LUA in str(err), 'a list that says something else (%s) stops the build: %s' % (label, err))
    else:
        check('materials/zcity_drill/sheet_16.vmt' not in named and not ran['only'], 'where Lua cannot be run a name in a table is not taken')
        check(not was_run and not names and listed == 0, 'the list for sort_content.py says that it was not run')
        check(build_addon.lua_run_lines(ran)[0].startswith('  NOT RUN'), 'and the build says so in capitals')
        check(not os.path.exists(bound) and not ran['bound'], 'and no list of entries is written for the game')

    # a pack whose Lua is not UTF-8 (saved as Windows-1251): two names stay two names
    jacket, sweater = u'\u041a\u0443\u0440\u0442\u043a\u0430'.encode('cp1251'), u'\u0421\u0432\u0438\u0442\u0435\u0440'.encode('cp1251')
    cyrillic = TABLE_LUA.replace('.lua', '_cyrillic.lua')
    archive('pack four.zip', {'cyrillic/lua/' + cyrillic:
                              b'hg.Appearance.Clothes[1]["' + jacket + b'"] = "pack/jacket"\n'
                              b'hg.Appearance.Clothes[1]["' + sweater + b'"] = "pack/sweater"\n'})
    out, _sources, _content, named, ran = build('not utf-8')
    build_addon.step_sort_tool(out, ran)
    names, made_from, _was_run = list_content.read_run_list(os.path.join(out, build_addon.SORT_TOOL_DIR, list_content.RUN_LIST))
    with open(os.path.join(out, 'lua', cyrillic), 'rb') as f:
        on_disk = f.read().decode('utf-8-sig', 'replace')
    check((made_from or {}).get(cyrillic) == list_content.lua_fingerprint(on_disk),
          'a Lua file that is not UTF-8 has the fingerprint sort_content.py makes of the file in the addon')
    if ran['result'] is not None:
        check({'materials/pack/jacket.vmt', 'materials/pack/sweater.vmt'} <= named and {'materials/pack/jacket.vmt', 'materials/pack/sweater.vmt'} <= names,
              'two clothes with names that are not UTF-8: the build takes both materials: %s' % sorted(named))
        text = io.open(os.path.join(out, 'lua', build_addon.BOUND_LUA), encoding='ascii').read()
        check('{ "Clothes/1/\\202\\243\\240\\242\\234\\224", "pack/jacket" },' in text
              and '{ "Clothes/1/\\209\\226\\232\\242\\229\\240", "pack/sweater" },' in text and ran['bound'] == 4,
              'and writes their names for the game byte for byte, in plain ASCII: %s' % text[-400:])
    os.remove(os.path.join(repo, 'pack four.zip'))

    # a pack whose Lua stops with an error half-way: what it adds after that is lost - not silently
    broken = TABLE_LUA.replace('.lua', '_broken.lua')
    archive('pack five.zip', {'broken/lua/' + broken: 'hg.Appearance.Clothes[1].first = "pack/first"\nlocal t = nil\nt.x = 1\n'
                                                      'hg.Appearance.Clothes[1].second = "pack/second"\n'})
    out, _sources, _content, named, ran = build('an error')
    build_addon.step_sort_tool(out, ran)
    failed = list_content.read_run_failed(os.path.join(out, build_addon.SORT_TOOL_DIR, list_content.RUN_LIST))
    if ran['result'] is not None:
        check('materials/pack/first.vmt' in named and 'materials/pack/second.vmt' not in named,
              'a Lua file that stops with an error: what it did before counts, what comes after is not known')
        check(list(failed) == [broken] and failed[broken].startswith(broken + ':3: attempt to index'),
              'the list for sort_content.py names the file and the error: %s' % failed)
        check(any(line.startswith('  STOPPED WITH AN ERROR: ' + broken) for line in build_addon.lua_run_lines(ran)),
              'and the build says so in capitals')
    else:
        check(failed == {}, 'where Lua cannot be run no file is said to have failed')
    os.remove(os.path.join(repo, 'pack five.zip'))

    # two versions of one script: neither is dropped without a word
    archive('pack three.zip', {'other/lua/' + TABLE_LUA: table})
    try:
        build('same twice')
        check(True, 'the same Lua file in two archives is no trouble')
    except build_addon.BuildError as err:
        check(False, 'the same Lua file in two archives is no trouble: %s' % err)
    archive('pack three.zip', {'other/lua/' + TABLE_LUA: table + 'hg.Appearance.Clothes[1].more = "models/gate/more"\n'})
    try:
        build('two versions')
        check(False, 'two versions of one Lua file stop the build')
    except build_addon.BuildError as err:
        check('pack one.zip' in str(err) and 'pack three.zip' in str(err) and TABLE_LUA in str(err),
              'two versions of one Lua file stop the build, and it names both archives: %s' % err)


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='replace')
    named = named_by_the_lua()
    check(len(named) > 500, 'the Lua of the drop-in archives names files (%d)' % len(named))
    tmp = tempfile.mkdtemp(prefix='zcg_content_')
    try:
        test_the_folder_of_the_user(tmp, named)
        test_numbered_folders(tmp, named)
        test_one_heap(tmp)
        test_models(tmp)
        test_reading(tmp)
        test_places_kept(tmp)
        test_namesakes(tmp)
        test_packed_from_inside(tmp)
        test_folders_of_their_own(tmp)
        test_sources(tmp)
        test_report(tmp)
        test_sorting(tmp)
        test_names_found_by_running(tmp)
        test_namesakes_of_a_pack(tmp)
        test_the_build_takes_lua(tmp)
        test_numbered_folders_of_the_owner(tmp)
        test_random_packings(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('test_content.py    %d checks, %d failed' % tuple(CHECKS))
    return 1 if CHECKS[1] else 0


if __name__ == '__main__':
    sys.exit(main())
