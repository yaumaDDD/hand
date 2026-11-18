#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Write lua/zcity_csgo_gloves/own/sh_catalog.lua: every player model, piece of clothing, face,
bodygroup and accessory that the Lua of Z-City and of the clothing packs puts into the appearance
tables - written down as data of the addon itself, so that the addon needs no Appearance Mod.

    python tools/catalog.py [LUA FOLDER] [--out FILE] [--print] [--quiet]

LUA FOLDER is the lua folder of the addon (by default: the Lua the drop-in archives of the
repository bring, as the build sees it). It is run by tools/lua_names.py on top of Z-City's own
appearance Lua out of z_city.zip, and the tables that come out of that run are what is written.
Needs the lupa module (python -m pip install lupa); without it nothing is written and the reason
is said.

The file it writes is data and nothing else - no Lua of anybody else is needed to read it:

    ZCO.Catalog = {
        Models      = { [1] = { ["Male 01"] = { mdl = ..., sex = false, submatSlots = { ... } } }, [2] = ... },
        Clothes     = { [1] = { ["normal"] = "models/humans/male/group01/normal" }, [2] = ... },
        ClothesDesc = { ["normal"] = { desc = ..., link = ... } },
        Facemaps    = { ["models/humans/male/group01/mike_facemap"] = { ["Face 1"] = ... } },
        FacemapOf   = { ["models/slav/m/male_01.mdl"] = "models/humans/male/group01/..." },
        MultiFacemaps = { [model] = { [face] = { [slot] = material } } },
        Bodygroups  = { HANDS = { [1] = { ["Gloves"] = { submodel = ..., pointshop = ..., id = ... } } } },
        Accessories = { ["armband black"] = { model = ..., bone = ..., pos = { Vector(), Angle(), 1 }, ... } },
        RandomNames = { [1] = { ... }, [2] = { ... } },
        Skeleton    = { AModel = ..., AClothes = { ... }, AColor = Color(...), ... },
    }
    ZCO.CatalogCounts = { models = 28, clothes = 462, ... }
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import lua_names  # noqa: E402
import zcg_layout as L  # noqa: E402

CATALOG_LUA = '%s/own/sh_catalog.lua' % L.ADDON_DIRNAME      # below lua/
SECTIONS = ('Models', 'Clothes', 'ClothesDesc', 'Facemaps', 'FacemapOf', 'MultiFacemaps', 'Bodygroups',
            'Accessories', 'RandomNames', 'Skeleton')
# what an accessory keeps, in the order it is written (the rest of its fields follows, sorted)
ACCESSORY_FIRST = ('name', 'model', 'femmodel', 'bone', 'pos', 'fempos', 'placement', 'skin', 'bodygroups',
                   'submat', 'bonemerge', 'norender', 'setcolor', 'color', 'vpos', 'pointshop', 'price',
                   'disallow', 'cool')
RENAME_ACCESSORY = {
    'malepos': 'pos', 'SubMat': 'submat', 'bPointShop': 'pointshop', 'bSetColor': 'setcolor',
    'vecColorOveride': 'color', 'disallowinappearance': 'disallow', 'needcoolRender': 'cool',
}
# fields of an accessory that are functions or entities in the game: no data, nothing to write
DROP_ACCESSORY = ('modelPreRenderCallback', 'ScreenSpaceEffects', 'think', 'Setup')


class CatalogError(Exception):
    pass


# --------------------------------------------------------------------------------------- values


def quote(text):
    """a string as Lua source: every byte of it kept, in \\ddd for what is not printable"""
    out = ['"']
    for char in text:
        code = ord(char)
        if char == '"':
            out.append('\\"')
        elif char == '\\':
            out.append('\\\\')
        elif char == '\n':
            out.append('\\n')
        elif char == '\r':
            out.append('\\r')
        elif char == '\t':
            out.append('\\t')
        elif 32 <= code < 127 or code >= 128:
            out.append(char)
        else:
            out.append('\\%d' % code)
    out.append('"')
    return ''.join(out)


def number(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if float(value).is_integer() and abs(value) < 1e15:
        return '%d' % int(value)
    return ('%.6f' % value).rstrip('0').rstrip('.')


def key_text(key):
    if isinstance(key, bool):
        return '[%s]' % ('true' if key else 'false')
    if isinstance(key, (int, float)):
        return '[%s]' % number(key)
    text = key if isinstance(key, str) else str(key)
    if text.isidentifier() and text not in ('and', 'or', 'not', 'end', 'then', 'function', 'local', 'nil',
                                            'true', 'false', 'for', 'while', 'return', 'if', 'else', 'in'):
        return text
    return '[%s]' % quote(text)


def sort_keys(keys):
    """numbers first (as an array is read), then names: the same data always gives the same file"""
    def order(key):
        if isinstance(key, bool):
            return (2, str(key))
        if isinstance(key, (int, float)):
            return (0, float(key))
        return (1, key if isinstance(key, str) else str(key))
    return sorted(keys, key=order)


def value_text(value, indent, depth=0):
    """Lua source for a value of the catalog (what lua_names.plain_data handed over)"""
    if value is None:
        return None
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return number(value)
    if isinstance(value, str):
        return quote(value)
    if isinstance(value, (list, tuple)):
        parts = [value_text(item, indent, depth + 1) for item in value]
        parts = [part for part in parts if part is not None]
        if not parts:
            return None
        if depth >= 2 and sum(len(part) for part in parts) < 60:
            return '{ ' + ', '.join(parts) + ' }'
        inner = indent + '\t'
        return '{\n' + ''.join('%s%s,\n' % (inner, part) for part in parts) + indent + '}'
    if isinstance(value, dict):
        for kind, maker in (('vector', 'Vector'), ('angle', 'Angle'), ('color', 'Color')):
            if kind in value and isinstance(value[kind], (list, tuple)):
                parts = value[kind]
                if kind == 'color':
                    parts = [int(round(float(part))) for part in parts]
                return '%s(%s)' % (maker, ', '.join(number(part) for part in parts))
        parts = []
        for key in sort_keys(value):
            made = value_text(value[key], indent + ('\t' if depth < 2 else ''), depth + 1)
            if made is not None:
                parts.append('%s = %s' % (key_text(key), made))
        if not parts:
            return None
        if depth >= 3 and sum(len(part) for part in parts) < 70:
            return '{ ' + ', '.join(parts) + ' }'
        inner = indent + '\t'
        return '{\n' + ''.join('%s%s,\n' % (inner, part) for part in parts) + indent + '}'
    return None


# --------------------------------------------------------------------------------------- shapes


def merge(one, two):
    """two catalogs (the run on the server and the one on the clients) as one: what is in either"""
    if one is None:
        return two
    if two is None:
        return one
    if not isinstance(one, dict) or not isinstance(two, dict):
        return one if one is not None else two
    out = dict(one)
    for key, value in two.items():
        out[key] = merge(out.get(key), value) if key in out else value
    return out


def positions(value):
    """{1: {vector: [...]}, 2: {angle: [...]}, 3: scale} (a malepos / fempos of the tables) as a list"""
    if not isinstance(value, dict):
        return None
    parts = dict((key, value[key]) for key in value)
    got = []
    for key in (1, 2, 3):
        if key in parts:
            got.append(parts.pop(key))
        elif str(key) in parts:
            got.append(parts.pop(str(key)))
    for rest in sort_keys(parts):
        got.append(parts[rest])
    return got or None


def an_accessory(name, data):
    """one accessory of hg.Accessories as the catalog keeps it"""
    if not isinstance(data, dict):
        return None
    out = {'name': data.get('name') if isinstance(data.get('name'), str) else name}
    for key, value in data.items():
        if key in DROP_ACCESSORY or not isinstance(key, str):
            continue
        name_of = RENAME_ACCESSORY.get(key, key)
        if name_of in ('pos', 'fempos'):
            value = positions(value)
        if name_of == 'name':
            continue
        out[name_of] = value
    if not out.get('model') and not out.get('femmodel'):
        return None       # (the "none" accessory and its likes: nothing to draw)
    return out


def bodygroup_entry(data):
    """{submodel string, bPointShop, ID = ...} of hg.Appearance.Bodygroups as the catalog keeps it"""
    if isinstance(data, str):
        return {'submodel': data}
    if not isinstance(data, dict):
        return None
    out = {}
    for key, value in data.items():
        if key == 1 or key == '1':
            out['submodel'] = value
        elif key == 2 or key == '2':
            out['pointshop'] = value
        elif key == 3 or key == '3':
            out['submodels'] = value
        elif isinstance(key, str) and key.upper() == 'ID':
            out['id'] = value
        elif isinstance(key, str):
            out[key] = value
    return out or None


def sexed(table):
    """{1: ..., 2: ...} with the keys the dump gives (1 and 2, or '1' and '2')"""
    out = {}
    if not isinstance(table, dict):
        return out
    for key, value in table.items():
        sex = key
        if isinstance(sex, str) and sex.isdigit():
            sex = int(sex)
        if sex in (1, 2):
            out[sex] = value
    return out


def normalize(dump):
    """the tables as the run handed them over -> the catalog of the addon"""
    dump = dump or {}
    catalog = {}

    models = {}
    for sex, names in sexed(dump.get('PlayerModels')).items():
        got = {}
        if isinstance(names, dict):
            for name, data in names.items():
                if isinstance(data, dict):
                    entry = dict(data)
                    entry.setdefault('sex', sex == 2)
                    got[name] = entry
                elif isinstance(data, str):
                    got[name] = {'mdl': data, 'sex': sex == 2}
        if got:
            models[sex] = got
    catalog['Models'] = models

    clothes = {}
    for sex, names in sexed(dump.get('Clothes')).items():
        if isinstance(names, dict):
            got = dict((name, value) for name, value in names.items() if isinstance(value, str))
            if got:
                clothes[sex] = got
    catalog['Clothes'] = clothes

    desc = dump.get('ClothesDesc')
    catalog['ClothesDesc'] = dict((name, value) for name, value in desc.items()
                                  if isinstance(value, dict)) if isinstance(desc, dict) else {}

    catalog['Facemaps'] = dump.get('FacemapsSlots') if isinstance(dump.get('FacemapsSlots'), dict) else {}
    catalog['FacemapOf'] = dump.get('FacemapsModels') if isinstance(dump.get('FacemapsModels'), dict) else {}
    catalog['MultiFacemaps'] = dump.get('MultiFacemaps') if isinstance(dump.get('MultiFacemaps'), dict) else {}

    bodygroups = {}
    source = dump.get('Bodygroups')
    if isinstance(source, dict):
        for group, by_sex in source.items():
            got_sex = {}
            for sex, names in sexed(by_sex).items():
                got = {}
                if isinstance(names, dict):
                    for name, data in names.items():
                        entry = bodygroup_entry(data)
                        if entry:
                            got[name] = entry
                if got:
                    got_sex[sex] = got
            if got_sex:
                bodygroups[group] = got_sex
    catalog['Bodygroups'] = bodygroups

    accessories = {}
    source = dump.get('Accessories')
    if isinstance(source, dict):
        for name, data in source.items():
            if not isinstance(name, str):
                continue
            entry = an_accessory(name, data)
            if entry:
                accessories[name] = entry
    catalog['Accessories'] = accessories

    names = dump.get('RandomNames')
    catalog['RandomNames'] = sexed(names) if isinstance(names, dict) else {}

    skeleton = dump.get('SkeletonAppearanceTable')
    catalog['Skeleton'] = dict(skeleton) if isinstance(skeleton, dict) else {}
    return catalog


def counts(catalog):
    got = {}
    got['models'] = sum(len(part) for part in catalog.get('Models', {}).values())
    got['clothes'] = sum(len(part) for part in catalog.get('Clothes', {}).values())
    got['faces'] = sum(len(part) for part in catalog.get('Facemaps', {}).values())
    got['multifacemaps'] = sum(len(faces) for part in catalog.get('MultiFacemaps', {}).values()
                               for faces in part.values() if isinstance(faces, dict))
    got['bodygroups'] = sum(len(names) for group in catalog.get('Bodygroups', {}).values()
                            for names in group.values())
    got['accessories'] = len(catalog.get('Accessories', {}))
    got['names'] = sum(len(part) for part in catalog.get('RandomNames', {}).values())
    return got


# --------------------------------------------------------------------------------------- the file


def text(catalog, tool='tools/catalog.py'):
    """the Lua source of sh_catalog.lua"""
    got = counts(catalog)
    lines = [
        '-- Written by %s; made anew with every build of the addon.' % tool,
        '--',
        '-- Every player model, piece of clothing, face, bodygroup and accessory the Lua of Z-City and of',
        '-- the clothing packs puts into the appearance tables - written down while the addon was built',
        '-- (tools/lua_names.py runs that Lua) and kept here as data of this addon. The addon reads it and',
        '-- runs the whole appearance itself (lua/zcity_csgo_gloves/own/): no Appearance Mod is needed for',
        '-- the models, the clothes, the faces, the accessories or the menu. Numbers are kept as they are:',
        '-- Vector(), Angle() and Color() are the ones of the game, so this file is data and nothing else.',
        '',
        'ZCO = ZCO or {}',
        '',
        'ZCO.Catalog = {',
    ]
    for section in SECTIONS:
        made = value_text(catalog.get(section), '\t')
        if made is None:
            continue
        lines.append('\t%s = %s,' % (section, made))
    lines.append('}')
    lines.append('')
    lines.append('ZCO.CatalogCounts = {')
    for key in sorted(got):
        lines.append('\t%s = %d,' % (key, got[key]))
    lines.append('}')
    lines.append('')
    return '\n'.join(lines)


def write(path, catalog, tool='tools/catalog.py'):
    folder = os.path.dirname(path)
    if folder and not os.path.isdir(folder):
        os.makedirs(folder)
    data = text(catalog, tool).encode('utf-8')
    with open(path, 'wb') as f:
        f.write(data)
    return len(data)


def gather_files(files, quiet=False):
    """run {path below lua/: text} of the Lua and take the tables out of it:
    (catalog, was Z-City's own Lua there)"""
    if not lua_names.available():
        raise CatalogError('the Lua cannot be run here: the lupa module is missing (pip install lupa)')
    result, stock = lua_names.run_addon(files, catalog=True)
    if result is None:
        raise CatalogError('the Lua did not run')
    dump = {}
    for realm in lua_names.REALMS:
        dump = merge(dump, result.catalog.get(realm) or {})
    if not quiet:
        for realm, name, message in result.errors[:5]:
            print('  [%s] %s: %s' % (realm, name, message.split('\n')[0]))
    return normalize(dump), stock


def gather(lua_folder=None, quiet=False):
    """the same out of a folder of Lua - or, with no folder, out of the Lua the drop-in archives of
    the repository bring, as the build sees it: (catalog, was Z-City's own Lua there)"""
    if lua_folder:
        files = lua_names.folder_files(lua_folder)
    else:
        files = dict((path, text) for path, (text, _archive) in lua_names.dropin_files().items())
    return gather_files(files, quiet)


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='replace')
    argv = list(sys.argv[1:] if argv is None else argv)
    out, show, quiet, folder = None, False, False, None
    while argv:
        arg = argv.pop(0)
        if arg == '--out':
            out = argv.pop(0)
        elif arg == '--print':
            show = True
        elif arg == '--quiet':
            quiet = True
        elif arg.startswith('--'):
            raise CatalogError('unknown key: %s' % arg)
        else:
            folder = arg
    try:
        catalog, stock = gather(folder, quiet)
    except CatalogError as err:
        print('%s' % err)
        return 2
    got = counts(catalog)
    if not any(got.values()):
        print('Nothing came out of the Lua: no catalog is written%s.'
              % ('' if stock else ' (z_city.zip was not found: the Lua of Z-City itself is what fills the tables)'))
        return 1
    path = out or os.path.join(ROOT, L.ADDON_DIRNAME, 'lua', CATALOG_LUA)
    size = write(path, catalog)
    if not quiet:
        print('Каталог внешности (свои рельсы): %s' % path)
        print('  моделей %d, одежды %d, лиц %d, мультифейсов %d, бодигрупп %d, аксессуаров %d, имён %d'
              % (got['models'], got['clothes'], got['faces'], got['multifacemaps'], got['bodygroups'],
                 got['accessories'], got['names']))
        print('  байт: %d%s' % (size, '' if stock else '  (без Lua самого Z-City: только то, что несут паки)'))
    if show:
        sys.stdout.write(text(catalog))
    return 0


if __name__ == '__main__':
    sys.exit(main())
