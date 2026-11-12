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


def write_run_list(path, names, lua_files, ran=True, failed=None, by=None, titles=None, left_out=()):
    """names: game paths; lua_files: {path below lua/: text} the names were found in.
    ran=False: the Lua could not be run where the addon was built - the list says so.
    failed: {Lua file: the error} - the files that stopped with an error when they were run.
    by: {name: the Lua file that puts it into the tables}; titles: {Lua file: title of its pack}.
    left_out: [(title, the title of the pack that is in the addon instead, names[, only])] -
    the packs whose Lua is not in the addon because another version of them is, each with the
    files that only it names and (only) the files that the addon names and it does not."""
    lines = [
        '# Materials and models that the Lua of this addon puts into the appearance tables of Z-City -',
        '# found by RUNNING that Lua while the addon was built (build_addon.py, tools/lua_names.py).',
        '# sort_content.py looks for these names on top of the ones it reads in the text of the Lua:',
        '# it has no Lua to run on the computer of the addon\'s owner.',
        '# "lua <sha1> <file>" - the Lua files the list was made from.',
        '# "failed <file><tab><error>" - a Lua file that stopped with an error: what it adds after that is not here.',
        '# "title <file><tab><title>" - the pack a Lua file came with.',
        '# "other <title><tab><title>" - a pack whose Lua is NOT in this addon, and the pack that is in it instead:',
        '#     two versions of one addon, of which the game can only have one.',
        '# "spare <name><tab><title>" - a file only such a pack names. The game does not need it with this addon;',
        '#     sort_content.py knows the name so as not to take that file for a namesake that is needed.',
        '# "only <name><tab><title>" - a file this addon names and such a pack does not. Which of the two kinds',
        '#     of files is there tells which version the content at hand belongs to.',
        '# "<name><tab><file>" - a name and the Lua file that puts it into the tables.',
    ]
    if not ran:
        lines.append('not-run')
    for name in sorted(lua_files):
        lines.append('lua %s %s' % (lua_fingerprint(lua_files[name]), name))
    for name in sorted(failed or ()):
        lines.append('failed %s\t%s' % (name, ' '.join(readable(u'%s' % failed[name]).split())))
    for name in sorted(titles or ()):
        if name in lua_files:
            lines.append('title %s\t%s' % (name, ' '.join((u'%s' % titles[name]).split())))
    left_out = sorted((entry[0], entry[1], sorted(entry[2]), sorted(entry[3]) if len(entry) > 3 else [])
                      for entry in left_out)
    for title, instead, _spare, _only in left_out:
        lines.append('other %s\t%s' % (one_line(title), one_line(instead)))
    for title, _instead, spare, _only in left_out:
        lines += ['spare %s\t%s' % (name, one_line(title)) for name in spare]
    for title, _instead, _spare, only in left_out:
        lines += ['only %s\t%s' % (name, one_line(title)) for name in only]
    by = by or {}
    lines += sorted('%s\t%s' % (name, by[name]) if by.get(name) else name for name in names)
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
            elif line.startswith(('failed ', 'title ', 'other ', 'spare ', 'only ')):
                continue        # (read_run_failed, read_run_who, read_run_other, read_run_only)
            else:
                names.add(line.split('\t', 1)[0])
    return names, made_from, ran


def one_line(text):
    return ' '.join((u'%s' % text).split())


def read_run_other(path=None):
    """({file only a left-out pack names: the title of that pack}, {that title: the title of the
    pack that is in the addon instead}) out of the list - as far as it says"""
    path = path or os.path.join(HERE, RUN_LIST)
    spare, instead = {}, {}
    if not os.path.isfile(path):
        return spare, instead
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if line.startswith('other '):
                title, _tab, taken = line[len('other '):].partition('\t')
                if title.strip():
                    instead[title.strip()] = taken.strip()
            elif line.startswith('spare '):
                name, _tab, title = line[len('spare '):].partition('\t')
                if name.strip():
                    spare[name.strip()] = title.strip()
    return spare, instead


def read_run_only(path=None):
    """{a file the addon names and a left-out pack does not: the title of that pack} out of the
    list - as far as it says"""
    path = path or os.path.join(HERE, RUN_LIST)
    only = {}
    if not os.path.isfile(path):
        return only
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if line.startswith('only '):
                name, _tab, title = line[len('only '):].partition('\t')
                if name.strip():
                    only[name.strip()] = title.strip()
    return only


def read_run_who(path=None):
    """({name: the Lua file that puts it into the tables}, {Lua file: title of its pack}) out of
    the list - as far as it says"""
    path = path or os.path.join(HERE, RUN_LIST)
    by, titles = {}, {}
    if not os.path.isfile(path):
        return by, titles
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if not line.strip() or line.startswith('#'):
                continue
            if line.startswith('title '):
                name, _tab, title = line[len('title '):].partition('\t')
                if title.strip():
                    titles[name.strip()] = title.strip()
            elif line.startswith(('lua ', 'failed ', 'other ', 'spare ')) or line.strip() == 'not-run':
                continue
            elif '\t' in line:
                name, _tab, lua = line.partition('\t')
                by[name.strip()] = lua.strip()
    return by, titles


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


def pack_label(title, archive):
    """what a pack is called: its title, or the name of its archive when its addon.json has none"""
    if not title or title.endswith('.json'):
        return archive
    return title


def pack_titles(root=None):
    """{Lua file below lua/, where the build puts it: the title of the pack it came with} - the
    title in the addon.json beside it, else the name of the archive. Only of the packs the build
    takes: a version of a pack that is left out (zcg_layout.PACK_VERSIONS) has no file there."""
    titles = {}
    for dest, _data, archive, title in L.dropin_lua(root or ROOT)[0]:
        titles[dest[len('lua/'):].lower()] = pack_label(title, archive)
    return titles


def collect():
    """[(archive, addon title, {game path: [Lua files that name it]})] and the names of Z-City.
    The names are read in the text of the Lua and, where Lua can be run (lupa), found by running
    it as well; what the files of Z-City itself put into its tables is left out either way.
    Of the packs the build takes - see left_out() for the others."""
    if _COLLECTED:
        return _COLLECTED[0]
    stock = stock_names()
    by_title, order, owner = {}, [], {}
    for dest, data, archive, title in L.dropin_lua(ROOT)[0]:
        key = (archive, title or archive)
        if key not in by_title:
            by_title[key] = {}
            order.append(key)
        owner[dest] = key       # (of two files for one path the later archive has it)
        for name in names_in(data.decode('utf-8-sig', 'replace')) - stock:
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


def other_version_names(taken, instead, files, text_only=False):
    """The materials and models a version of a pack names that the build does not take.
    taken: {path below lua/: text} - the Lua the build takes; instead: the paths among them that
    belong to the version that was taken; files: {path below lua/: text} of the version that was
    left out. Returns every name (game path) the addon would name with that version in the place
    of the other one - in the text of its Lua and, where Lua can be run, in the tables after
    running everything that way. What is in this set and not among the names of the addon as it
    is, only the version that was left out names; the other way round, only the one in it."""
    swapped = dict((path, text) for path, text in taken.items() if path not in instead)
    swapped.update(files)
    names = set()
    for path, text in swapped.items():
        if not L.is_own_lua(path):
            names |= names_in(text)
    if text_only:
        return names
    try:
        import lua_names
    except ImportError:
        return names
    if not lua_names.available():
        return names
    result = lua_names.run_addon(swapped)[0]
    if result is not None:
        names |= set(result.names)
        names -= result.stock
    return names


def left_out():
    """[(archive, title, the title taken instead, {game path: [Lua files]})] - the packs of the
    drop-in archives that are versions of a pack the build takes, each with the names that only
    it names: files the game does not need with this addon."""
    if _LEFT:
        return _LEFT[0]
    stock = stock_names()
    taken_files, left = L.dropin_lua(ROOT)
    try:
        import lua_names
        to_text = lua_names.lua_text
    except ImportError:
        def to_text(data):
            return data.decode('utf-8-sig', 'replace')
    used = set()
    for _archive, _title, wanted in collect()[0]:
        used.update(wanted)
    taken = dict((dest[len('lua/'):], to_text(data)) for dest, data, _archive, _title in taken_files)
    found = []
    for title, instead, archive, files in left:
        theirs = set(dest[len('lua/'):] for dest, _data, _archive, pack in taken_files if pack == instead)
        mine = dict((dest[len('lua/'):], to_text(data)) for dest, data in files)
        names = other_version_names(taken, theirs, mine) - used - stock
        by_file = {}
        for dest, data in files:
            for name in names_in(data.decode('utf-8-sig', 'replace')) & names:
                by_file.setdefault(name, []).append(dest)
        found.append((archive, title, instead, dict((name, by_file.get(name, [])) for name in names)))
    _LEFT.append(found)
    return found


_LEFT = []          # made once


_RAN = []           # run once


OTHER_HEAD = u'''\
%s  [%s]
    НЕ В СБОРКЕ. Это другая версия аддона «%s»: у обеих одни и те же Lua-файлы,
    в игре может быть только одна. Сборка берёт «%s»; эту берёт
    build_addon.bat --pack "%s"%s.
    Файлы, которые называет только эта версия (с этой сборкой игре они не нужны):'''


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
    for archive, title, instead, wanted in left_out():
        print('')
        release = L.VERSION_ZIPS.get(title)
        print(OTHER_HEAD % (title, archive, instead, instead, title,
                            u' (в выпуске на GitHub это архив %s)' % release if release else u''))
        folders = {}
        for name in wanted:
            folders.setdefault(os.path.dirname(name), []).append(name)
        for folder, names in sorted(folders.items()):
            print('    %-62s %3d names' % (folder + '/', len(names)))
            if every:
                for name in sorted(names):
                    print('        ' + os.path.basename(name))
        if not wanted:
            print('    none: it names nothing that the other version does not')
    return 0


if __name__ == '__main__':
    sys.exit(main())
