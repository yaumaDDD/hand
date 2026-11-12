#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Which materials and models does the Lua of the clothing packs ask the game for - found by
running it.

    python tools/lua_names.py               the Lua of the drop-in archives of the repository
    python tools/lua_names.py LUA_FOLDER    the Lua of an addon folder (build/zcity_csgo_gloves/lua)

tools/list_content.py reads the text of such Lua and takes every "models/..." and "materials/..."
it finds for a file name. That misses what the text does not spell out that way:

    {"Drill 07", "zcity_drill/sheet_16"}             a material named from inside materials/
    "zcity_rp/shirt_" .. i                           a name put together while running

and a name that is missed is a file sort_content.bat knows nothing about: it may well take it for
a namesake of another pack (sheet_16.vmt is a name three packs use) and move it there.

So the Lua is run - by LuaJIT, in the small imitation of the game in lua_names.lua, in the order
the game and Z-City's loader run it - and the appearance tables are read afterwards with the same
function the console command zcg_content uses in the game (ZCG.ContentWalk of sh_content.lua).
Along the way it is noted which file put a name there, and whether a later file replaced or
dropped it.

This needs the lupa module (pip install lupa) and is done where the addon is built. The names go
into the addon as sort_content/lua_names.txt (list_content.write_run_list), where sort_content.py -
which has no Lua at hand on the computer of the addon's owner - reads them, on top of what it
finds in the text.

The imitation only behaves the way the author believes the game behaves. The exact answer for a
running game is zcg_content.

Lua knows bytes, not letters, and the name of a piece of clothing may be written in any encoding
(a file saved as Windows-1251 is as good to the game as one in UTF-8). The Lua is therefore run
on the very bytes of the files: lua_text() reads a file so that lua_bytes() gives them back, and
the entries of the tables (Result.entries) come back the same way. Two names that are not UTF-8
would otherwise both turn into the same row of question marks - and one of them would be lost.
"""
import codecs
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import glua  # noqa: E402
import zcg_layout as L  # noqa: E402

# the Lua of the gloves themselves: it only speaks of files the addon has from the start
OWN_LUA = L.OWN_LUA
# the files of Z-City that make the appearance tables (below lua/), and the one that loads them
STOCK_FOLDER = 'homigrad/new_appearance/'
LOADER = 'autorun/loader.lua'
REALMS = ('server', 'client')

def _lua():
    try:
        from lupa import luajit21 as lua
    except ImportError:
        try:
            from lupa import luajit20 as lua
        except ImportError:
            return None
    return lua


def available():
    """can the Lua be run here? (the lupa module with LuaJIT)"""
    return _lua() is not None


def is_own(path):
    return path.lower().startswith(OWN_LUA)


def lua_text(data):
    """the text of a Lua file (bytes) - every byte of it is kept: what is not UTF-8 becomes
    characters that lua_bytes() turns back into the bytes they were"""
    if data.startswith(codecs.BOM_UTF8):
        data = data[len(codecs.BOM_UTF8):]
    return data.decode('utf-8', 'surrogateescape')


def lua_bytes(text):
    """the bytes Lua gets for a text (the reverse of lua_text)"""
    return text.encode('utf-8', 'surrogateescape')


def _exact(value):
    """a string that came out of Lua (the runtime hands every byte over as one character)"""
    return value.encode('latin-1').decode('utf-8', 'surrogateescape')


def _shown(value):
    """the same for a string that is only shown, or stands for a file: fit to be written anywhere"""
    return value.encode('latin-1').decode('utf-8', 'replace')


def game_path(kind, path):
    """the file a name of the tables stands for: materials/x.vmt, models/y.mdl"""
    path = path.replace('\\', '/').lower().strip()
    if kind == 'model':
        return path
    if path.startswith('materials/'):
        path = path[len('materials/'):]
    if path.endswith('.vmt'):
        path = path[:-len('.vmt')]
    return 'materials/' + path + '.vmt'


class Result(object):
    def __init__(self):
        self.names = {}     # game path -> {'by': the Lua file that put it there, 'who': what it is for}
        self.stock = set()  # game paths that the files of Z-City itself put there
        self.entries = {}   # realm -> {entry of the tables: (value, the Lua file)} - without Z-City's own
        self.if_installed = set()   # entries that are only added when their file is installed
        self.lost = []      # dicts: path, who, by, during, now (game path or None), entry
        self.errors = []    # (realm, Lua file, message)
        self.ran = {}       # realm -> the Lua files in the order they were run
        self.stubs = []     # globals taken for parts of the game
        self.bound = {}     # realm -> (entries the addon's check looked for, [(entry, wanted, Lua file, found)])


def content_source():
    path = os.path.join(ROOT, L.ADDON_DIRNAME, 'lua', L.ADDON_DIRNAME, 'sh_content.lua')
    with open(path, encoding='utf-8') as f:
        return f.read()


def run(files, stock=(), skip=(), content=None, port=False, bound=None):
    """files: {path below lua/: text in the dialect of the game} - everything the game would
    find there; stock: the paths among them that are Z-City's own; skip: paths that are not run;
    port: load the files with the copy of Z-City's loader in lua_names.lua although the loader
    itself is among them; bound: the text of an sh_bound.lua, for the addon's own check to compare
    the tables with (Result.bound). Returns a Result, or None when there is no Lua to run it with.

    The names are those of a game that has every file installed. Each side is run once more as
    if nothing were: an entry that only shows with its file there (Result.if_installed) is one
    the game may rightly lack."""
    lua = _lua()
    if lua is None:
        return None
    with open(os.path.join(HERE, 'lua_names.lua'), encoding='utf-8') as f:
        imitation = f.read()
    content = content if content is not None else content_source()
    stock = set(path.lower() for path in stock)
    plain = dict((lua_bytes(path.lower()), lua_bytes(glua.to_lua(text, run=True))) for path, text in files.items())

    result = Result()
    seen_lost, stubs = set(), set()
    by_stock, wanted = {}, {}
    def start(realm, bare, check=None):
        # a fresh Lua for each: the files change globals. Texts go in as bytes; with this encoding
        # every byte of a string of Lua comes back as one character (_exact, _shown).
        rt = lua.LuaRuntime(unpack_returned_tuples=True, encoding='latin-1')
        return rt.execute(lua_bytes(imitation))(rt.table_from({
            'files': rt.table_from(plain),
            'content': lua_bytes(content),
            'realm': realm,
            'skip': rt.table_from(dict((lua_bytes(path.lower()), True) for path in skip)),
            'port': bool(port),
            'bare': bare,
            'bound': lua_bytes(check) if check is not None else None,
        }))

    for realm in REALMS:
        got = start(realm, False, bound)
        own = dict((_exact(key), entry) for key, entry in got.entries.items() if _exact(entry.by) not in stock)
        bare = set(_exact(key) for key, entry in start(realm, True).entries.items() if _exact(entry.by) not in stock)
        result.entries[realm] = dict((key, (_exact(entry.path), _exact(entry.by))) for key, entry in own.items())
        result.if_installed |= set(own) - bare
        result.ran[realm] = [_shown(name) for name in got.ran.values()]
        stubs.update(_shown(name) for name in got.stubs.values())
        if got.bound is not None:
            result.bound[realm] = (got.bound.count, [
                (_exact(item.entry), _exact(item.want), _exact(item.by), _exact(item.now) if item.now else None)
                for item in got.bound.missing.values()])
        for entry in got.errors.values():
            result.errors.append((realm, _shown(entry.file), _shown(entry.message)))
        for _key, entry in got.entries.items():
            path = game_path(entry.kind, _shown(entry.path))
            if _exact(entry.by) in stock:
                by_stock[path] = True
            else:
                wanted.setdefault(path, set()).add((_shown(entry.by), _shown(entry.who)))
        for entry in got.lost.values():
            now = game_path(entry.kind, _shown(entry.now)) if entry.now else None
            path = game_path(entry.kind, _shown(entry.path))
            key = (_shown(entry.entry), path, _shown(entry.by), _shown(entry.during), now)
            if key in seen_lost or path == now:
                continue
            seen_lost.add(key)
            result.lost.append({'entry': key[0], 'path': path, 'who': _shown(entry.who), 'by': key[2],
                                'during': key[3], 'now': now})
    result.stock = set(by_stock)
    for path, who in wanted.items():
        if path not in result.stock:
            # (several entries may name one file; the tables are walked in no fixed order)
            by, what = min(who)
            result.names[path] = {'by': by, 'who': what}
    result.lost.sort(key=lambda entry: (entry['by'], entry['during'], entry['entry'], entry['path']))
    result.errors.sort()
    result.stubs = sorted(stubs)
    return result


def stock_files(archive=None):
    """the appearance Lua of Z-City itself out of z_city.zip: {path below lua/: text}"""
    archive = archive or os.path.join(ROOT, 'z_city.zip')
    found = {}
    if not os.path.isfile(archive):
        return found
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            name = info.filename.replace('\\', '/').lower()
            at = name.find('/lua/')
            if at < 0 or not name.endswith('.lua') or info.is_dir():
                continue
            path = name[at + len('/lua/'):]
            if path.startswith(STOCK_FOLDER) or path == LOADER:
                found[path] = lua_text(z.read(info))
    return found


def folder_files(lua_folder):
    """the Lua of an addon folder: {path below lua/: text}"""
    found = {}
    for base, _dirs, names in os.walk(lua_folder):
        for name in names:
            if not name.lower().endswith('.lua'):
                continue
            full = os.path.join(base, name)
            rel = os.path.relpath(full, lua_folder).replace('\\', '/').lower()
            with open(full, 'rb') as f:
                found[rel] = lua_text(f.read())
    return found


def dropin_files(root=None):
    """the Lua the drop-in archives of the repository bring, where the build puts it:
    {path below lua/: (text, archive)}; of two files for one path the later archive has it.
    Without the packs the build leaves out: a version of a pack that is taken
    (zcg_layout.PACK_VERSIONS)."""
    found = {}
    for dest, data, archive, _title in L.dropin_lua(root or ROOT)[0]:
        found[dest[len('lua/'):]] = (lua_text(data), archive)
    return found


def run_addon(files, port=False, bound=None):
    """runs the Lua of an addon ({path below lua/: text}) on top of Z-City's own appearance Lua
    (when z_city.zip is at hand). Returns (Result or None, was Z-City's Lua there?)"""
    stock = stock_files()
    everything = dict(stock)
    everything.update(files)    # a file of the addon at the path of one of Z-City's replaces it
    own_stock = [path for path in stock if path not in files]
    result = run(everything, stock=own_stock, skip=[path for path in files if is_own(path)], port=port, bound=bound)
    return result, bool(stock)


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='replace')
    if not available():
        print('The Lua cannot be run here: the lupa module is missing (pip install lupa).')
        return 2
    if len(sys.argv) > 1:
        files = folder_files(sys.argv[1])
    else:
        files = dict((path, text) for path, (text, _archive) in dropin_files().items())
    result, with_stock = run_addon(files)
    import list_content
    text_names = set()
    for path, text in files.items():
        if not is_own(path):
            text_names |= list_content.names_in(text)
    text_names -= list_content.stock_names()

    print('%d Lua files%s' % (len([p for p in files if not is_own(p)]),
                              '' if with_stock else ' (z_city.zip is not here: run without the Lua of Z-City itself)'))
    print('put into the appearance tables: %d names; Z-City itself: %d' % (len(result.names), len(result.stock)))
    only_run = sorted(set(result.names) - text_names)
    print('not to be read in the text of the Lua: %d' % len(only_run))
    for name in only_run:
        print('    %-60s %s (%s)' % (name, result.names[name]['who'], result.names[name]['by']))
    if result.lost:
        print('replaced or dropped by a later file: %d' % len(result.lost))
        for entry in result.lost:
            print('    %-60s %s, put there by %s, %s while %s ran'
                  % (entry['path'], entry['who'], entry['by'],
                     'replaced by %s' % entry['now'] if entry['now'] else 'dropped', entry['during']))
    if result.errors:
        print('did not run through: %d' % len(result.errors))
        for realm, name, message in result.errors:
            print('    [%s] %s: %s' % (realm, name, message.split('\n')[0]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
