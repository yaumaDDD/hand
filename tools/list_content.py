#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Which materials and models does the Lua of the drop-in archives name?

    python tools/list_content.py            a summary by addon and folder
    python tools/list_content.py --files    every name

The drop-in archives (see "Drop-in archives" in zcg_layout.py) bring Lua that adds clothes,
player models and accessories to the appearance menu of Z-City by name; the files behind those
names have to be put into the materials and models folders of the addon. This script reads the
names out of the Lua text, leaves out the ones Z-City itself uses (z_city.zip) and prints where
the rest is expected.

Reading the text finds what is written out as "models/..." or "materials/...". A name the Lua
puts together from pieces ("face" .. i) or writes from inside the materials folder
("zcity_drill/sheet_16") is not found that way, so the Lua is also run, where that is possible
(tools/lua_names.py, it needs the lupa module): the listing has both. The names found by running
go into the addon as a list (RUN_LIST) for sort_content.py, which cannot run Lua where it works.
The exact answer for a running game is the console command zcg_content of the addon.
"""
import hashlib
import json
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import glua  # noqa: E402
import zcg_layout as L  # noqa: E402

LITERAL = re.compile(r'''(["'])((?:models|materials|sound)/[A-Za-z0-9_\-./ !+()]*?)\1''')
SOUND_TYPES = ('.wav', '.mp3', '.ogg')


def strip_comments(text):
    """the Lua without its comments (names in commented-out lines are not used by anything)"""
    lua = glua.to_lua(text)
    lua = re.sub(r'--\[(=*)\[.*?\]\1\]', '', lua, flags=re.S)
    out = []
    for line in lua.split('\n'):
        # a "--" outside of a string ends the line
        quote, i = None, 0
        while i < len(line):
            c = line[i]
            if quote:
                if c == '\\':
                    i += 1
                elif c == quote:
                    quote = None
            elif c in '"\'':
                quote = c
            elif line.startswith('--', i):
                line = line[:i]
                break
            i += 1
        out.append(line)
    return '\n'.join(out)


def readable(text):
    """a text of Lua that was read byte for byte (lua_names.lua_text): what is not UTF-8 in it
    as the question marks any other way of reading it gives - fit to be written anywhere"""
    return text.encode('utf-8', 'surrogateescape').decode('utf-8', 'replace')


def names_in(text):
    """game files named by a piece of Lua: set of paths like materials/x.vmt, models/y.mdl"""
    found = set()
    for _quote, name in LITERAL.findall(strip_comments(readable(text))):
        name = name.strip().lower().rstrip('/')
        ext = os.path.splitext(name)[1]
        if name.startswith('models/') and ext == '.mdl':
            found.add(name)
        elif name.startswith('materials/'):
            found.add(name if ext else name + '.vmt')
        elif name.startswith('models/') and not ext:
            found.add('materials/' + name + '.vmt')  # a material of a model
        elif name.startswith('sound/') and ext in SOUND_TYPES:
            found.add(name)
    return found


STOCK_LIST = 'stock_names.txt'


def stock_names():
    """the files Z-City itself names: out of its source (z_city.zip in the repository), or out of
    the list the build ships next to these scripts where that archive is not at hand"""
    if _STOCK:
        return set(_STOCK[0])
    path = os.path.join(ROOT, 'z_city.zip')
    found = set()
    if os.path.isfile(path):
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                if info.filename.lower().endswith('.lua'):
                    found |= names_in(z.read(info).decode('utf-8-sig', 'replace'))
    elif os.path.isfile(os.path.join(HERE, STOCK_LIST)):
        with open(os.path.join(HERE, STOCK_LIST), 'r', encoding='utf-8') as f:
            found = set(line.strip() for line in f if line.strip() and not line.startswith('#'))
    _STOCK.append(frozenset(found))
    return found


_STOCK = []     # read once


# ---- the names found by running the Lua, as the build ships them next to these scripts --------
RUN_LIST = 'lua_names.txt'


def lua_fingerprint(text):
    """what tells whether a Lua file is still the one a list was made from (the same for a text
    read byte for byte and one read with question marks for what is not UTF-8)"""
    return hashlib.sha1(readable(text).replace('\r\n', '\n').encode('utf-8')).hexdigest()


def write_run_list(path, names, lua_files, ran=True, failed=None):
    """names: game paths; lua_files: {path below lua/: text} the names were found in.
    ran=False: the Lua could not be run where the addon was built - the list says so.
    failed: {Lua file: the error} - the files that stopped with an error when they were run."""
    lines = [
        '# Materials and models that the Lua of this addon puts into the appearance tables of Z-City -',
        '# found by RUNNING that Lua while the addon was built (build_addon.py, tools/lua_names.py).',
        '# sort_content.py looks for these names on top of the ones it reads in the text of the Lua:',
        '# it has no Lua to run on the computer of the addon\'s owner.',
        '# "lua <sha1> <file>" - the Lua files the list was made from.',
        '# "failed <file><tab><error>" - a Lua file that stopped with an error: what it adds after that is not here.',
    ]
    if not ran:
        lines.append('not-run')
    for name in sorted(lua_files):
        lines.append('lua %s %s' % (lua_fingerprint(lua_files[name]), name))
    for name in sorted(failed or ()):
        lines.append('failed %s\t%s' % (name, ' '.join(readable(u'%s' % failed[name]).split())))
    lines += sorted(names)
    # (a file name that cannot be written is written with question marks: it then counts as changed)
    with open(path, 'w', encoding='utf-8', errors='replace', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


def read_run_list(path=None):
    """(names, {Lua file below lua/: fingerprint}, was the Lua run) out of the list;
    (set(), None, False) when there is no list"""
    path = path or os.path.join(HERE, RUN_LIST)
    if not os.path.isfile(path):
        return set(), None, False
    names, made_from, ran = set(), {}, True
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if line == 'not-run':
                ran = False
            elif line.startswith('lua '):
                parts = line.split(' ', 2)
                if len(parts) == 3:
                    made_from[parts[2]] = parts[1]
            elif line.startswith('failed '):
                continue        # (read_run_failed)
            else:
                names.add(line)
    return names, made_from, ran


def read_run_failed(path=None):
    """{Lua file below lua/: the error} - the files the list says stopped with an error when the
    addon was built"""
    path = path or os.path.join(HERE, RUN_LIST)
    failed = {}
    if os.path.isfile(path):
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                if line.startswith('failed '):
                    name, _tab, message = line[len('failed '):].rstrip('\r\n').partition('\t')
                    if name.strip():
                        failed[name.strip()] = message.strip()
    return failed


def addon_title(z, names, inner):
    """title of the addon a file of a drop-in archive belongs to (from the addon.json next to it)"""
    parts = inner.split('/')
    for k in range(len(parts) - 1, 0, -1):
        for candidate in ('/'.join(parts[:k]) + '.json', '/'.join(parts[:k]) + '/addon.json'):
            if candidate in names:
                try:
                    return json.loads(z.read(names[candidate]).decode('utf-8-sig', 'replace')).get('title') or candidate
                except ValueError:
                    return candidate
    return None


def collect():
    """[(archive, addon title, {game path: [Lua files that name it]})] and the names of Z-City.
    The names are read in the text of the Lua and, where Lua can be run (lupa), found by running
    it as well; what the files of Z-City itself put into its tables is left out either way."""
    if _COLLECTED:
        return _COLLECTED[0]
    stock = stock_names()
    by_title, order, owner = {}, [], {}
    for archive in L.dropin_archives(ROOT):
        if not archive.lower().endswith('.zip'):
            continue
        with zipfile.ZipFile(archive) as z:
            names = {L.zip_name(info): info for info in z.infolist()}
            for inner, info in sorted(names.items()):
                dest = None if info.is_dir() else L.dropin_destination(inner)
                if not dest or not dest.endswith('.lua'):
                    continue
                title = addon_title(z, names, inner) or os.path.basename(archive)
                key = (os.path.basename(archive), title)
                if key not in by_title:
                    by_title[key] = {}
                    order.append(key)
                owner[dest] = key       # (of two files for one path the later archive has it)
                for name in names_in(z.read(info).decode('utf-8-sig', 'replace')) - stock:
                    by_title[key].setdefault(name, []).append(dest)

    ran = run_names()
    if ran is not None:
        for name, info in ran.names.items():
            key = owner.get('lua/' + info['by'])
            if key is not None and name not in stock and name not in by_title[key]:
                by_title[key][name] = ['lua/' + info['by']]
        for wanted in by_title.values():
            for name in ran.stock.intersection(wanted):
                del wanted[name]

    order.sort(key=lambda key: (key[0], key[1]))
    result = [(archive, title, by_title[(archive, title)]) for archive, title in order]
    _COLLECTED.append((result, stock))
    return result, stock


_COLLECTED = []     # made once


def run_names():
    """what running the Lua of the drop-in archives finds (a lua_names.Result), None where Lua
    cannot be run or the tool for that was not shipped (sort_content/ in an installed addon)"""
    if not _RAN:
        result = None
        try:
            import lua_names
        except ImportError:
            lua_names = None
        if lua_names is not None and lua_names.available():
            files = dict((path, text) for path, (text, _archive) in lua_names.dropin_files(ROOT).items())
            result = lua_names.run_addon(files)[0]
        _RAN.append(result)
    return _RAN[0]


_RAN = []           # run once


FILES_HEAD = u'''\
ЭТО НЕ СПИСОК ФАЙЛОВ, КОТОРЫЕ НУЖНО СОБРАТЬ.
Здесь только имена, которые называет Lua одежды. Игре нужно больше: каждый материал (.vmt) тянет
свои текстуры (.vtf - их бывает несколько, и называются они не обязательно так же), каждая модель
(.mdl) - свои материалы и файлы .vvd / .vtx / .phy. Выбирать файлы по этому списку не надо:
положите в аддон папки materials и models исходных аддонов ЦЕЛИКОМ, как есть, и запустите
sort_content.bat - он сам найдёт каждому файлу место (README, "Куда класть файлы").
Список показывает, из каких папок игры Lua что-то берёт.
'''


def main():
    every = '--files' in sys.argv[1:]
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(errors='replace')
    result, _stock = collect()
    shipped = os.path.join(ROOT, 'build', L.ADDON_DIRNAME)
    total = have = 0
    if every:
        # (this listing is kept as docs/content_names.txt and read by the owner of the addon)
        print(FILES_HEAD)
    for archive, title, wanted in result:
        print('%s  [%s]' % (title, archive))
        if not wanted:
            print('    names no files of its own')
        folders = {}
        for name in wanted:
            folders.setdefault(os.path.dirname(name), []).append(name)
        for folder, names in sorted(folders.items()):
            present = sum(1 for name in names if os.path.isfile(os.path.join(shipped, name)))
            total += len(names)
            have += present
            print('    %-62s %3d names%s' % (folder + '/', len(names), ', %d in the build' % present if present else ''))
            if every:
                for name in sorted(names):
                    print('        ' + os.path.basename(name))
        print('')
    if every or not os.path.isdir(shipped):
        print('%d names in all' % total)
    else:
        print('%d names in all, %d of them are files of the last build (build/%s)' % (total, have, L.ADDON_DIRNAME))
    return 0


if __name__ == '__main__':
    sys.exit(main())
