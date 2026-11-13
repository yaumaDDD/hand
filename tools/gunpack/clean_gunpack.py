#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Puts the content of a gun pack where the game reads it and deletes what nothing uses.
(started by clean_gunpack.bat, which lies in the content addon next to sound / materials / models)

What is USED is worked out anew at every start, from the Lua:
  * gunpack_names.txt next to this script - the names in the Lua of Remorseim and of Z-City,
  * the Lua of the addon itself (lua/, gamemodes/, scripts/),
  * the Lua of every other addon in the same "addons" folder and of garrysmod/lua, gamemodes,
  * the folders dropped on the .bat.
A file is used when the Lua names it - in full, or in pieces ("weapons/ak/fire" .. n .. ".wav",
path .. "open.ogg": every file that begins / ends that way stays) - or when a used file needs
it: a model its .vvd / .vtx / .phy / .ani, its materials, the models and sounds named inside
it; a material its textures.

An addon that lists the files it needs (tools/models.txt, materials.txt, sounds.txt - the
Remorseim gun pack does) is sorted by those lists: a listed file that is not at its place is
looked for by its name among everything that was thrown into the addon (and in the folders
dropped on the .bat, from which it is copied) and put where the list wants it; what is still
missing is looked for in the game - its folders, the other addons, the addon archives of the
workshop (.gma: the files are taken out of them; game_files.py) - and copied in; used is what
the lists and the Lua of the addon itself name, and pictures (.png .jpg) are judged as well.

Steps: 1. files in numbered, nested or wrong folders (sound1, pack/materials, everything thrown
into materials: materials/sound/..., materials/models/x.mdl ...) go to their place
(an exact copy of a file that is there already is deleted with the rest); 2. the list of what
is not used is shown, and after Enter those files are deleted. (A missing file is not looked
for by its name alone: the Lua also names files of the game itself, and a file of the same name
moved to such a place would replace the game's.) Only .wav .mp3 .ogg .vmt .vtf .mdl .vvd .vtx .phy .ani below sound,
materials and models are judged; everything else is left alone.

    clean_gunpack.py [--addon DIR] [--yes] [--dry-run] [--keep] [--no-neighbours] [LUA DIRS ...]
    clean_gunpack.py --write-names OUT.txt LUA_DIR_OR_ZIP ...
"""
import argparse
import io
import os
import re
import shutil
import struct
import sys
import zipfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))    # (in the repository: tools/)
try:
    import game_files       # (finds the game and reads its addon archives; lies next to this script)
except ImportError:
    game_files = None

ROOTS = ('sound', 'materials', 'models')
SOUNDS = ('.wav', '.mp3', '.ogg')
MODEL_PARTS = ('.vvd', '.vtx', '.phy', '.ani')
KINDS = SOUNDS + ('.vmt', '.vtf', '.mdl') + MODEL_PARTS
PICTURES = ('.png', '.jpg', '.jpeg')     # judged only in an addon that lists its files
LISTS = ('models.txt', 'materials.txt', 'sounds.txt')   # tools/*.txt of the addon: the files it needs
TEXTS = ('.lua', '.txt', '.json', '.vmt', '.cfg', '.res')
NAMES = 'gunpack_names.txt'
REPORT = 'clean_gunpack_report.txt'
MIN_PIECE = 8          # a piece of a path shorter than this says too little

_TOKEN = re.compile(r'''
      --\[(=*)\[.*?\]\1\]           # long comment
    | /\*.*?\*/
    | (?:--|//)[^\n]*
    | "((?:\\.|[^"\\\n])*)"
    | '((?:\\.|[^'\\\n])*)'
    | \[(=*)\[(.*?)\]\4\]
''', re.S | re.X)
_AFTER = re.compile(r'\s*\.\.')
_BEFORE = re.compile(r'\.\.\s*$')
_IN_MODEL = re.compile(rb'[\w\-./\\ ]+\.(?:mdl|wav|mp3|ogg)', re.I)
_VMT_WORD = re.compile(r'"([^"\r\n]*)"|([^\s"{}]+)')
_PATHLIKE = re.compile(r'^[a-z0-9_\-./ +()!&\']+$')
_ROOT_PART = re.compile(r'^(sound|materials|models)s?\d*$', re.I)


def say(text=u''):
    try:
        print(text)
    except UnicodeEncodeError:
        print(text.encode('ascii', 'replace').decode('ascii'))
    sys.stdout.flush()


def long_path(path):
    path = os.path.abspath(path)
    if os.name == 'nt' and len(path) >= 240 and not path.startswith('\\\\?\\'):
        return '\\\\?\\' + path
    return path


def tidy(name):
    """a name as the Lua writes it -> lower case, forward slashes, no sound flags in front"""
    name = name.replace('\\\\', '/').replace('\\', '/').lower().strip()
    name = name.lstrip(')^#@<>*~!?(')
    while '//' in name:
        name = name.replace('//', '/')
    return name.lstrip('/')


class Names(object):
    """what the Lua names: whole names, beginnings and endings of names"""

    def __init__(self):
        self.whole, self.begin, self.end = set(), set(), set()
        self.files = 0

    def piece(self, text):
        """the beginning of a name; one that says too little ("models/", "weapons/") is dropped"""
        rest = text
        if not _PATHLIKE.match(text):
            return
        for root in ROOTS:
            if rest.startswith(root + '/'):
                rest = rest[len(root) + 1:]
        if len(rest) >= MIN_PIECE or rest.count('/') >= 2 or (rest.count('/') == 1 and len(rest) >= 5):
            self.begin.add(text)

    def take(self, text):
        self.files += 1
        for found in _TOKEN.finditer(text):
            value = found.group(2)
            if value is None:
                value = found.group(3)
            if value is None:
                value = found.group(5)
            if value is None or not 3 <= len(value) <= 200 or '\n' in value:
                continue
            name = tidy(value)
            if len(name) < 3:
                continue
            joined_after = bool(_AFTER.match(text, found.end()))
            joined_before = bool(_BEFORE.search(text[max(0, found.start() - 12):found.start()]))
            if '%' in name:                                   # string.format("fire%d.wav", n)
                head, tail = name.split('%', 1)
                self.piece(head)
                tail = re.sub(r'^[\d.\-]*[a-z]', '', tail)
                if '%' not in tail and os.path.splitext(tail)[1] in KINDS and len(tail) >= MIN_PIECE:
                    self.end.add(tail)
                continue
            self.whole.add(name)
            if joined_after or name.endswith('/'):
                self.piece(name)
            if joined_before:
                stem, ext = os.path.splitext(name)
                if ext in KINDS and len(stem) >= 3 and _PATHLIKE.match(name):
                    self.end.add(name)

    def merge(self, other):
        self.whole |= other.whole
        self.begin |= other.begin
        self.end |= other.end
        self.files += other.files

    def write(self, path, sources):
        with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(u'# names in the Lua of: %s\n# files read: %d\n' % (u', '.join(sources), self.files))
            for mark, names in (('W', self.whole), ('B', self.begin), ('E', self.end)):
                for name in sorted(names):
                    if mark != 'W' or '/' in name or os.path.splitext(name)[1] in KINDS + ('.png', '.jpg'):
                        f.write(u'%s\t%s\n' % (mark, name))

    def read(self, path):
        with io.open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.rstrip('\n')
                if line.startswith('# files read:'):
                    self.files += int(line.split(':')[1])
                elif line[:2] in ('W\t', 'B\t', 'E\t'):
                    {'W': self.whole, 'B': self.begin, 'E': self.end}[line[0]].add(line[2:])


def read_text(data):
    return data.decode('utf-8', 'replace') if isinstance(data, bytes) else data


def lua_of(folder, names, skip=None, everywhere=False):
    """reads every text below the lua-like folders of an addon (or of any folder); everywhere:
    below its sound / materials / models as well (Lua that was thrown in there with the content)"""
    count = 0
    passed = ('.git', 'maps', 'resource', 'particles') + (() if everywhere else ROOTS)
    for base, dirs, files in os.walk(long_path(folder)):
        dirs[:] = [d for d in dirs if d.lower() not in passed]
        if skip and os.path.normcase(base) == os.path.normcase(long_path(skip)):
            dirs[:] = []
            continue
        for name in files:
            if os.path.splitext(name)[1].lower() in ('.lua', '.txt', '.json') and name not in (REPORT, NAMES):
                try:
                    if os.path.getsize(os.path.join(base, name)) > 8 << 20:
                        continue
                    with open(os.path.join(base, name), 'rb') as f:
                        names.take(read_text(f.read()))
                    count += 1
                except (OSError, IOError):
                    pass
    return count


def lua_of_zip(path, names):
    count = 0
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            ext = os.path.splitext(info.filename)[1].lower()
            if ext == '.zip':
                count += lua_of_zip(io.BytesIO(z.read(info)), names)
            elif ext in ('.lua', '.txt', '.json') and info.file_size < 8 << 20:
                names.take(read_text(z.read(info)))
                count += 1
    return count


# ---- the files ---------------------------------------------------------------------------------
def root_of(name):
    """the folder of the game a file belongs to, by what it is"""
    ext = os.path.splitext(name)[1].lower()
    if ext in SOUNDS:
        return 'sound'
    return 'materials' if ext in ('.vmt', '.vtf') + PICTURES else 'models'


def game_path(rel):
    """Where a file belongs: the last folder above it that is named like its folder of the game
    counts, numbered or not (sound/a.wav and materials/models/x.vmt stay where they are):
        materials/dump/materials/models/x.vmt -> materials/models/x.vmt
        materials1/models/x.vmt -> materials/models/x.vmt     pack/sound/a.wav -> sound/a.wav
        materials/pack/sound/weapons/a.wav -> sound/weapons/a.wav
        materials/models/weapons/w.mdl -> models/weapons/w.mdl
    and without such a folder a sound or a model below another folder of the game keeps its path
    below that one (materials/weapons/a.wav -> sound/weapons/a.wav). None: no place is known."""
    parts = rel.split('/')
    root = root_of(parts[-1])
    for i in range(len(parts) - 2, -1, -1):
        found = _ROOT_PART.match(parts[i])
        if found and found.group(1).lower() == root:
            return '/'.join([root] + parts[i + 1:]).lower()
    if root != 'materials' and len(parts) > 1 and _ROOT_PART.match(parts[0]):
        return '/'.join([root] + parts[1:]).lower()
    return None


def read_lists(addon):
    """the files the addon says it needs (tools/models.txt, materials.txt, sounds.txt: a path a
    line, as below garrysmod/) -> list of paths, lower case; None when it has no such lists"""
    out, any_list = [], False
    for name in LISTS:
        path = os.path.join(addon, 'tools', name)
        if not os.path.isfile(path):
            continue
        any_list = True
        with open(path, 'rb') as f:
            data = f.read()
        for line in data.decode('utf-8-sig', 'replace').splitlines():
            line = tidy(line)
            if line and not line.startswith('#') and line.split('/')[0] in ROOTS and '.' in line.rsplit('/', 1)[-1]:
                out.append(line)
    return out if any_list else None


def find_file(base, rel):
    """the file base/rel on the disk, whatever the case its folders and its name are spelled in"""
    path = long_path(base)
    for part in rel.split('/'):
        try:
            match = [name for name in os.listdir(path) if name.lower() == part]
        except OSError:
            return None
        if not match:
            return None
        path = os.path.join(path, match[0])
    return path if os.path.isfile(path) else None


def is_vtx(rel):
    return rel.endswith('.vtx')


def walk(addon, kinds=KINDS):
    """{path below the addon, lower case: path on the disk as it is spelled} of the judged files"""
    out = {}
    top = long_path(addon)
    for base, dirs, files in os.walk(top):
        below = os.path.relpath(base, top).replace(os.sep, '/')
        below = '' if below == '.' else below + '/'
        if not below:
            dirs[:] = [d for d in dirs if d.lower() not in ('lua', 'gamemodes', '.git', 'clean_gunpack', 'tools', 'build')]
        for name in files:
            if os.path.splitext(name)[1].lower() in kinds:
                out[below + name] = os.path.join(base, name)
    return out


def stem_of(rel):
    folder, name = rel.rsplit('/', 1)
    return folder + '/' + name.split('.')[0]


def cstr(data, at):
    end = data.find(b'\x00', at)
    return data[at:end if end >= 0 else len(data)].decode('latin-1')


def needs_of_model(full):
    out = set()
    try:
        with open(full, 'rb') as f:
            b = f.read()
    except (OSError, IOError):
        return out
    try:
        if b[:4] == b'IDST' and len(b) >= 408:
            count, index, cdcount, cdindex = struct.unpack_from('<4i', b, 204)
            if 0 <= count <= 4096 and 0 <= cdcount <= 256:
                mats = []
                for i in range(count):
                    off = index + i * 64
                    mats.append(tidy(cstr(b, off + struct.unpack_from('<i', b, off)[0])))
                folders = [tidy(cstr(b, struct.unpack_from('<i', b, cdindex + i * 4)[0])) for i in range(cdcount)]
                for mat in mats:
                    mat = mat[:-4] if mat.endswith('.vmt') else mat
                    for folder in folders + ['']:
                        out.add(('materials/' + folder.strip('/') + '/' + mat).replace('//', '/') + '.vmt')
    except (struct.error, IndexError):
        pass
    for found in _IN_MODEL.findall(b):
        name = tidy(found.decode('latin-1'))
        if name.endswith('.mdl'):
            out.add(name if name.startswith('models/') else 'models/' + name)
        else:
            out.add(name if name.startswith('sound/') else 'sound/' + name)
    return out


def needs_of_material(full):
    out = set()
    try:
        with io.open(full, 'r', encoding='latin-1') as f:
            text = f.read()
    except (OSError, IOError):
        return out
    for quoted, bare in _VMT_WORD.findall(text):
        word = tidy(quoted or bare).strip('/')
        if not word or len(word) > 260:
            continue
        for ext in ('.vtf', '.vmt'):
            if word.endswith(ext):
                word = word[:-len(ext)]
        base = word if word.startswith('materials/') else 'materials/' + word
        out.add(base + '.vtf')
        out.add(base + '.vmt')
    return out


def named(rel, names):
    """does the Lua name this file (rel: sound/..., materials/..., models/... in lower case)"""
    root, sub = rel.split('/', 1)
    stem, ext = os.path.splitext(rel)
    keys = [rel, sub]
    if root == 'materials':
        keys += [stem, os.path.splitext(sub)[0]]
        if sub.startswith('models/'):
            keys.append(os.path.splitext(sub)[0])
    if any(key in names.whole for key in keys):
        return True
    for key in (rel, sub):
        for i in range(4, len(key) + 1):
            if key[:i] in names.begin:
                return True
    base = rel.rsplit('/', 1)[1]
    for key in (base, rel):
        for i in range(len(key) - 4):
            if key[i:] in names.end and (i == 0 or key is base or key[i - 1] == '/' or '/' not in key[i:]):
                return True
    return False


def used_files(files, names, keep_stems=()):
    """files: {game path: disk path}. -> (set of the used game paths, set of wanted paths that are missing)
    keep_stems: models (path without the ending) whose parts stay even without their .mdl"""
    used, wanted, queue = set(), set(), []
    stems = {}
    for rel in files:
        if os.path.splitext(rel)[1] in MODEL_PARTS:
            stems.setdefault(stem_of(rel), []).append(rel)

    def keep(rel):
        if rel in files:
            if rel not in used:
                used.add(rel)
                queue.append(rel)
        else:
            wanted.add(rel)

    for rel in files:
        if os.path.splitext(rel)[1] not in MODEL_PARTS and named(rel, names):
            keep(rel)
        elif keep_stems and os.path.splitext(rel)[1] in MODEL_PARTS and stem_of(rel) in keep_stems:
            keep(rel)
    while queue:
        rel = queue.pop()
        ext = os.path.splitext(rel)[1]
        if ext == '.mdl':
            for part in stems.get(stem_of(rel), ()):
                keep(part)
            for need in needs_of_model(files[rel]):
                keep(need)
        elif ext == '.vmt':
            for need in needs_of_material(files[rel]):
                keep(need)
    return used, wanted


def prune(top):
    gone = 0
    for base, dirs, files in os.walk(long_path(top), topdown=False):
        if not os.listdir(base):
            try:
                os.rmdir(base)
                gone += 1
            except OSError:
                pass
    return gone


def megabytes(size):
    return (u'%.1f' % (size / 1048576.0)).replace('.', ',')


def same(a, b):
    try:
        if os.path.getsize(a) != os.path.getsize(b):
            return False
        with open(a, 'rb') as fa, open(b, 'rb') as fb:
            while True:
                x, y = fa.read(1 << 20), fb.read(1 << 20)
                if x != y:
                    return False
                if not x:
                    return True
    except (OSError, IOError):
        return False


def move(src, addon, rel, dry):
    dst = long_path(os.path.join(addon, *rel.split('/')))
    if dry:
        return True
    try:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.rename(src, dst)
        return True
    except OSError:
        return False


def run(a):
    here = os.path.dirname(os.path.abspath(__file__))
    addon = os.path.abspath(a.addon or os.path.dirname(here))
    listed_files = read_lists(addon)
    kinds = KINDS + PICTURES if listed_files is not None else KINDS
    if not any(os.path.isdir(os.path.join(addon, root)) for root in ROOTS) and not walk(addon, kinds):
        say(u'В папке %s нет папок sound, materials, models — положите clean_gunpack.bat и папку' % addon)
        say(u'clean_gunpack в папку аддона с контентом ган-пака (рядом с sound / materials / models).')
        return 1
    say(u'Аддон: %s' % addon)

    # ---- what the Lua names
    names = Names()
    listed = os.path.join(here, NAMES)
    if listed_files is not None:
        # The addon says itself which files it needs: that list and its own Lua decide, nothing else.
        names.whole.update(listed_files)
        names.files += 1
        a.no_neighbours = True
        say(u'  списки самого аддона (tools/models.txt, materials.txt, sounds.txt): файлов %d' % len(listed_files))
        say(u'  нужным считается то, что в этих списках и в Lua аддона, и то, что этим файлам нужно')
    elif os.path.isfile(listed):
        names.read(listed)
        say(u'  имена из Lua Remorseim и Z-City (%s): файлов Lua %d' % (NAMES, names.files))
    own = Names()                                   # what the Lua of the addon itself names
    count = lua_of(addon, own, skip=here, everywhere=True)
    names.merge(own)
    if count:
        say(u'  Lua в самом аддоне (где бы он ни лежал, в том числе в materials): файлов %d' % count)
    parent = os.path.dirname(addon)
    if not a.no_neighbours and os.path.basename(parent).lower() == 'addons':
        count = 0
        for other in sorted(os.listdir(parent)):
            full = os.path.join(parent, other)
            if os.path.isdir(full) and os.path.normcase(full) != os.path.normcase(addon):
                count += lua_of(full, names)
        game = os.path.dirname(parent)
        for folder in ('lua', 'gamemodes', 'scripts'):
            if os.path.isdir(os.path.join(game, folder)):
                count += lua_of(os.path.join(game, folder), names)
        say(u'  Lua других аддонов в %s и самой игры: файлов %d' % (parent, count))
    if game_files is not None:
        for extra in list(a.lua):
            if os.path.isdir(extra) and game_files.sure_game(extra):
                a.lua.remove(extra)
                a.game = a.game or game_files.sure_game(extra)
                say(u'  %s — это сама игра: в ней ищутся недостающие файлы' % extra)
    for extra in a.lua:
        if os.path.isdir(extra) and listed_files is not None:
            say(u'  %s: отсюда берутся недостающие файлы списка' % extra)
        elif os.path.isdir(extra):
            say(u'  %s: файлов %d' % (extra, lua_of(extra, names)))
        elif zipfile.is_zipfile(extra):
            say(u'  %s: файлов %d' % (extra, lua_of_zip(extra, names)))
        else:
            say(u'  ВНИМАНИЕ: %s — не папка и не zip, пропущено' % extra)
    if not names.files or not names.whole:
        say(u'Ни одного файла Lua не прочитано — что используется, неизвестно. Ничего не тронуто.')
        return 1

    report = [u'clean_gunpack: %s' % addon, u'']
    # ---- 1. to their places
    on_disk = walk(addon, kinds)
    files, moved, doubles, stray, failed = {}, [], [], [], []
    for rel in sorted(on_disk):
        full = on_disk[rel]
        place = game_path(rel)
        if place is None:
            stray.append(rel)
            continue
        if rel.lower() == place and rel.split('/')[0] == place.split('/')[0] and place not in files:
            files[place] = full
    for rel in sorted(on_disk):
        full = on_disk[rel]
        place = game_path(rel)
        if place is None or files.get(place) == full:
            continue
        if place in files:
            if same(full, files[place]):
                doubles.append((rel, full))
            else:
                stray.append(rel)
            continue
        if move(full, addon, place, a.dry_run):
            moved.append((rel, place))
            files[place] = full if a.dry_run else long_path(os.path.join(addon, *place.split('/')))
        else:
            failed.append(rel)

    # ---- 1b. an addon with lists: a listed file that is not at its place is looked for by its
    # name - among the files of the addon that are not listed themselves, then in the dropped folders
    found, brought, unsure, lacking, keep_stems, protected = [], [], [], [], set(), set()
    taken, in_game = [], []
    if listed_files is not None:
        listed_set = set(listed_files)
        # Pictures are content as well. The lists leave out what Z-City has - but an icon the
        # Lua names is wanted here all the same, and so is the icon the spawn menu looks for by
        # itself, materials/entities/<class>.png. pictures: named with their ending (missing ones
        # are told); optional: a guess at the file (vgui/x -> vgui/x.png or .vmt, the class
        # icons) - taken when it is found, not missed when it is not.
        pictures, optional = set(), set()
        for name in own.whole:
            ext = os.path.splitext(name)[1]
            base = name if name.startswith('materials/') else 'materials/' + name
            if not _PATHLIKE.match(name) or '/' not in name:
                continue
            if ext in PICTURES:
                pictures.add(base)
            elif not ext and base.startswith(('materials/vgui/', 'materials/entities/')):
                optional.update((base + '.png', base + '.vmt'))
        for kind in ('weapons', 'entities'):
            try:
                classes = os.listdir(os.path.join(addon, 'lua', kind))
            except OSError:
                classes = []
            for entry in classes:
                optional.add('materials/entities/%s.png' % os.path.splitext(entry)[0].lower())
        pictures -= listed_set
        optional -= listed_set | pictures
        # (the icons of the spawn menu are never unused)
        names.begin.update(('entities/', 'vgui/entities/'))
        lua_whole = Names()
        lua_whole.whole = own.whole
        wanted_set = listed_set | pictures | optional
        for want in listed_files:
            if os.path.splitext(want)[1] in MODEL_PARTS + ('.mdl',):
                keep_stems.add(stem_of(want))

        def here_already(want):
            if want in files:
                return True
            if is_vtx(want):
                stem = stem_of(want) + '.'
                return any(rel.startswith(stem) and is_vtx(rel) for rel in by_folder.get(want.rsplit('/', 1)[0], ()))
            return False

        def key_of(name):
            """what a file is looked for by: its name; a .vtx by the name of its model (x.dx90.vtx for x.vtx)"""
            name = name.lower()
            return name.split('.')[0] + '.vtx' if name.endswith('.vtx') else name

        def belongs(rel):
            return rel in wanted_set or (is_vtx(rel) and stem_of(rel) + '.vtx' in wanted_set)

        by_folder = {}
        for rel in files:
            by_folder.setdefault(rel.rsplit('/', 1)[0], []).append(rel)
        pool = {}                                   # key -> [(where it lies now (for the score), disk path, game path or None)]
        for rel, full in files.items():
            # (not a file that is wanted where it lies: listed there, or named there by the Lua)
            if not belongs(rel) and not named(rel, lua_whole):
                pool.setdefault(key_of(rel.rsplit('/', 1)[1]), []).append((rel, full, rel))
        for rel in stray:
            pool.setdefault(key_of(rel.rsplit('/', 1)[-1]), []).append((rel.lower(), on_disk[rel], None))
        outside = None

        def score(have, want):
            a_parts, b_parts = have.split('/')[:-1], want.split('/')[:-1]
            n = 0
            while n < len(a_parts) and n < len(b_parts) and a_parts[-1 - n] == b_parts[-1 - n]:
                n += 1
            return n

        def best(candidates, want):
            """the candidates that fit best; one, or several that are the same file"""
            if not candidates:
                return None, False
            top = max(score(c[0], want) for c in candidates)
            fit = [c for c in candidates if score(c[0], want) == top]
            # (the .vtx of one model in one folder - x.dx90.vtx, x.sw.vtx - are one find, not a choice)
            folders = sorted(set(c[0].rsplit('/', 1)[0] for c in fit))
            if len(folders) > 1:
                first = [c for c in fit if c[0].rsplit('/', 1)[0] == folders[0]]
                for folder_name in folders[1:]:
                    other = dict((c[0].rsplit('/', 1)[1], c) for c in fit if c[0].rsplit('/', 1)[0] == folder_name)
                    if len(other) != len(first) or not all(
                            c[0].rsplit('/', 1)[1] in other and same(c[1], other[c[0].rsplit('/', 1)[1]][1]) for c in first):
                        return None, True
                fit = first
            return fit, False

        asked = {}                                  # key -> how many listed files of that name are not at their place
        for want in wanted_set:
            if not here_already(want):
                key = key_of(want.rsplit('/', 1)[1])
                asked[key] = asked.get(key, 0) + 1

        for want in sorted(wanted_set):
            if here_already(want):
                continue
            folder, base = want.rsplit('/', 1)
            fit, torn = best(pool.get(key_of(base), []), want)
            # (several listed files of this name are missing and no folder of the find says which
            # of them it is: w.mdl of which weapon? - it is not guessed)
            if fit and asked.get(key_of(base), 0) > 1 and score(fit[0][0], want) == 0:
                fit, torn = None, True
            if torn:
                # (several different files of that name: none is moved - and none is deleted)
                unsure.append(want)
                protected.update(c[2] for c in pool[key_of(base)] if c[2] is not None)
                continue
            if fit:
                # (every .vtx of the model goes along: x.dx90.vtx, x.dx80.vtx, x.sw.vtx)
                group = [c for c in pool[key_of(base)] if c[0].rsplit('/', 1)[0] == fit[0][0].rsplit('/', 1)[0]] if is_vtx(want) else fit[:1]
                for c in group:
                    dest = folder + '/' + c[0].rsplit('/', 1)[1]
                    if dest in files:
                        continue
                    if move(c[1], addon, dest, a.dry_run):
                        if c[2] is not None:
                            files.pop(c[2], None)
                        elif c[0] in [s.lower() for s in stray]:
                            stray[:] = [s for s in stray if s.lower() != c[0]]
                        files[dest] = c[1] if a.dry_run else long_path(os.path.join(addon, *dest.split('/')))
                        by_folder.setdefault(folder, []).append(dest)
                        found.append((c[0], dest))
                    else:
                        failed.append(c[0])
                pool[key_of(base)] = [c for c in pool[key_of(base)] if c not in group]
                continue
            # ... in the folders that were dropped on the .bat
            if outside is None:
                outside = {}
                for extra in a.lua:
                    if os.path.isdir(extra):
                        top = long_path(extra)
                        for base_dir, _dirs, names_here in os.walk(top):
                            for name in names_here:
                                if os.path.splitext(name)[1].lower() in kinds:
                                    rel = os.path.relpath(os.path.join(base_dir, name), top).replace(os.sep, '/').lower()
                                    outside.setdefault(key_of(name), []).append((rel, os.path.join(base_dir, name), None))
            fit, torn = best(outside.get(key_of(base), []), want)
            if torn:
                unsure.append(want)
            elif fit:
                group = [c for c in outside[key_of(base)] if c[0].rsplit('/', 1)[0] == fit[0][0].rsplit('/', 1)[0]] if is_vtx(want) else fit[:1]
                for c in group:
                    dest = folder + '/' + c[0].rsplit('/', 1)[-1]
                    target = long_path(os.path.join(addon, *dest.split('/')))
                    try:
                        if not a.dry_run:
                            os.makedirs(os.path.dirname(target), exist_ok=True)
                            shutil.copy2(c[1], target)
                        files[dest] = c[1] if a.dry_run else target
                        by_folder.setdefault(folder, []).append(dest)
                        brought.append((c[1], dest))
                    except (OSError, IOError):
                        failed.append(dest)
            elif want not in optional:
                lacking.append(want)

        # ... and in the game itself: its folders, the other addons, the archives of the workshop
        # (.gma - the icons and the rest are taken out of them; nothing else is unpacked)
        maybe = [want for want in sorted(optional) if not here_already(want)]
        game = None
        if (lacking or maybe) and not a.no_game and game_files is not None:
            game = game_files.find(addon=addon, given=a.game)
            if game is None:
                say(u'  Игра не найдена — недостающее в ней не искалось. Перетащите папку GarrysMod на clean_gunpack.bat.')
            else:
                say(u'  Игра: %s — ищу в ней недостающие файлы (по списку и картинки из Lua: %d, возможные иконки: %d) ...' % (
                    game.root, len(lacking), len(maybe)))

        def from_game(wants):
            """looks the wanted files up in the game and brings them; -> the set of those that are there now"""
            if True:
                ask = {}                            # the name looked for -> the wanted file it is for
                for want in wants:
                    if is_vtx(want):
                        for kind in ('.dx90.vtx', '.dx80.vtx', '.sw.vtx', '.vtx'):
                            ask[want[:-4] + kind] = want
                    else:
                        ask[want] = want
                seen = game_files.look(game, ask, skip=[addon], seconds=240)
                inner = os.path.join(game.root, 'garrysmod')
                got, by_archive = set(), {}
                for name in sorted(seen.where):
                    kind, label = seen.where[name]
                    if kind in (game_files.VPK, game_files.OTHER):
                        in_game.append(ask[name])           # the game has it by itself: nothing to bring
                        got.add(ask[name])
                    elif name in seen.archive:
                        by_archive.setdefault(seen.archive[name], set()).add(name)
                    elif kind == game_files.LOOSE and ask[name] not in listed_set:
                        in_game.append(ask[name])           # (in the folder of the game itself: it is shown from there)
                        got.add(ask[name])
                    else:
                        base = {game_files.LOOSE: inner, game_files.DOWNLOAD: os.path.join(inner, 'download')}.get(
                            kind, os.path.join(inner, 'addons', label if isinstance(label, str) else ''))
                        source = find_file(base, name)
                        target = long_path(os.path.join(addon, *name.split('/')))
                        if source is None:
                            continue
                        try:
                            if not a.dry_run:
                                os.makedirs(os.path.dirname(target), exist_ok=True)
                                shutil.copy2(source, target)
                            files[name] = source if a.dry_run else target
                            taken.append((source, name))
                            got.add(ask[name])
                        except (OSError, IOError):
                            failed.append(name)
                for archive in sorted(by_archive):
                    members = by_archive[archive]
                    if a.dry_run:
                        for name in sorted(members):
                            taken.append((archive, name))
                            got.add(ask[name])
                        continue
                    try:
                        title, _all, data = game_files.gma_names(archive, lambda name, members=members: name in members)
                    except (ValueError, OSError, MemoryError) as err:
                        say(u'  ВНИМАНИЕ: не удалось прочитать %s: %s' % (archive, err))
                        continue
                    for name in sorted(data):
                        target = long_path(os.path.join(addon, *name.split('/')))
                        try:
                            os.makedirs(os.path.dirname(target), exist_ok=True)
                            with open(target, 'wb') as f:
                                f.write(data[name])
                            files[name] = target
                            taken.append((u'%s (%s)' % (title or u'?', os.path.basename(archive)), name))
                            got.add(ask[name])
                        except (OSError, IOError):
                            failed.append(name)
                if seen.cut:
                    say(u'  (поиск в игре прерван по времени: просмотрено не всё — запустите ещё раз)')
                if seen.unread:
                    say(u'  (архивов, которые не удалось прочитать: %d)' % len(seen.unread))
                return got

        if game is not None:
            before = len(taken)
            got = from_game(lacking + maybe)
            lacking[:] = [want for want in lacking if want not in got]
            # (a material that came needs its textures: those are asked for as well)
            if not a.dry_run:
                more = set()
                for _source, name in taken[before:]:
                    if name.endswith('.vmt') and name in files:
                        more.update(need for need in needs_of_material(files[name]) if need not in files)
                if more:
                    from_game(sorted(more))

    # ---- 2. what is used
    used, wanted = used_files(files, names, keep_stems)

    unused = sorted(rel for rel in files if rel not in used and rel not in protected)
    size = 0
    for rel in unused:
        try:
            size += os.path.getsize(files[rel])
        except OSError:
            pass
    for _rel, full in doubles:
        try:
            size += os.path.getsize(full)
        except OSError:
            pass

    say()
    say(u'Файлов sound / materials / models: %d' % len(on_disk))
    if moved:
        say(u'  переложено на своё место (из папок с номерами и вложенных): %d' % len(moved))
    if found:
        say(u'  найдено по имени и переложено туда, где их ждёт список аддона: %d' % len(found))
    if brought:
        say(u'  скопировано из перетащенных папок: %d' % len(brought))
    if taken:
        say(u'  %s из игры (папки игры, другие аддоны, архивы мастерской .gma): %d, из них картинок .png / .jpg: %d' % (
            u'будет взято' if a.dry_run else u'взято', len(taken), sum(1 for _s, name in taken if name.endswith(PICTURES))))
    if in_game:
        say(u'  есть в самой игре (её архивы) — в аддон класть не нужно: %d' % len(in_game))
    if protected:
        say(u'  оставлено как есть — несколько разных файлов с именем из списка, какой нужен, неясно: %d' % len(protected))
    if stray:
        say(u'  не тронуто (лежат не в sound / materials / models или место занято другим файлом): %d' % len(stray))
    say(u'  используется: %d' % len(used))
    say(u'  не используется: %d, точных копий: %d — всего %s МБ' % (len(unused), len(doubles), megabytes(size)))

    report.append(u'Переложено на своё место: %d' % len(moved))
    report += [u'  %s -> %s' % pair for pair in moved]
    report.append(u'Найдено по имени: %d' % len(found))
    report += [u'  %s -> %s' % pair for pair in found]
    report.append(u'Скопировано из перетащенных папок: %d' % len(brought))
    report += [u'  %s -> %s' % pair for pair in brought]
    report.append(u'Взято из игры: %d' % len(taken))
    report += [u'  %s -> %s' % pair for pair in taken]
    report.append(u'Есть в самой игре (в аддон не кладётся): %d' % len(in_game))
    report += [u'  ' + rel for rel in in_game]
    if listed_files is not None:
        report.append(u'Файлы списка, которых нет ни в аддоне, ни в игре: %d' % len([w for w in lacking if w in listed_set]))
        report += [u'  ' + rel for rel in lacking if rel in listed_set]
        report.append(u'Картинки, которые называет Lua аддона (в списке их нет), которых нет ни в аддоне, ни в игре: %d' % len([w for w in lacking if w not in listed_set]))
        report += [u'  ' + rel for rel in lacking if rel not in listed_set]
        report.append(u'Файлы списка, для которых нашлось несколько РАЗНЫХ файлов с таким именем (не тронуты): %d' % len(unsure))
        report += [u'  ' + rel for rel in unsure]
    report.append(u'Не тронуто: %d' % len(stray))
    report += [u'  ' + rel for rel in stray]
    missing = sorted(w for w in wanted if os.path.splitext(w)[1] in ('.mdl',) + SOUNDS and w.split('/')[0] in ROOTS)
    report.append(u'Используется: %d' % len(used))
    report.append(u'%s: %d (%s МБ)' % (u'Не используется' if a.keep or a.dry_run else u'Не используется (удаляется)',
                                       len(unused) + len(doubles), megabytes(size)))
    report += [u'  ' + rel for rel in unused] + [u'  %s (копия)' % rel for rel, _ in doubles]
    report.append(u'Модели и звуки, которые нужны моделям аддона, но которых в нём нет: %d (могут быть в игре)' % len(missing))
    report += [u'  ' + rel for rel in missing[:2000]]

    def save():
        try:
            with io.open(os.path.join(addon, REPORT), 'w', encoding='utf-8-sig', newline='\r\n') as f:
                f.write(u'\n'.join(report) + u'\n')
            say(u'Отчёт: %s' % os.path.join(addon, REPORT))
        except (OSError, IOError):
            say(u'ВНИМАНИЕ: отчёт записать не удалось')

    if listed_files is not None:
        lacking_listed = [want for want in lacking if want in listed_set]
        lacking_pictures = [want for want in lacking if want not in listed_set]
        unsure_listed = [want for want in unsure if want in listed_set]
        say(u'  по списку аддона: файлов %d, на месте %d, не хватает %d%s' % (
            len(listed_set), len(listed_set) - len(lacking_listed) - len(unsure_listed), len(lacking_listed),
            (u', неясных (несколько разных файлов с одним именем) %d' % len(unsure_listed)) if unsure_listed else u''))
        say(u'  картинки, которые называет Lua аддона сверх списка: %d, не хватает %d' % (len(pictures), len(lacking_pictures)))
        if lacking:
            say(u'  Чего не хватает — в отчёте: этих файлов нет ни в аддоне, ни в игре, ни в аддонах мастерской на этом')
            say(u'  компьютере. Подпишитесь на аддон, в котором они есть, или перетащите на clean_gunpack.bat папку с ними.')
    todo = [files[rel] for rel in unused] + [full for _rel, full in doubles]
    if not todo:
        say(u'Лишнего нет — удалять нечего.')
        save()
        return 0
    if a.keep or a.dry_run:
        say(u'Ничего не удалено (%s). Список — в отчёте.' % (u'--dry-run' if a.dry_run else u'--keep'))
        save()
        return 0
    save()
    if not a.yes:
        say()
        say(u'Будет УДАЛЕНО файлов: %d (%s МБ). Вернуть их будет нельзя. Список — в отчёте выше.' % (len(todo), megabytes(size)))
        say(u'Нажмите Enter, чтобы удалить, или закройте окно, чтобы ничего не удалять.')
        try:
            if sys.stdin is None or sys.stdin.readline() == '':
                say(u'Ответа нет — ничего не удалено.')
                return 0
        except (OSError, IOError, ValueError):
            say(u'Ответа нет — ничего не удалено.')
            return 0
    gone, not_gone = 0, 0
    for full in todo:
        try:
            os.remove(full)
            gone += 1
        except OSError:
            not_gone += 1
    prune(addon)
    say(u'Удалено файлов: %d, %s МБ.' % (gone, megabytes(size)))
    if not_gone or failed:
        say(u'ВНИМАНИЕ: не удалось удалить или переложить: %d (игра открыта? закройте её и запустите ещё раз)' % (not_gone + len(failed)))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--addon')
    ap.add_argument('--yes', action='store_true', help='delete without asking')
    ap.add_argument('--dry-run', action='store_true', help='change nothing, only tell')
    ap.add_argument('--keep', action='store_true', help='put the files to their places, delete nothing')
    ap.add_argument('--game', help='the folder GarrysMod (found by itself when the addon lies in it or Steam has it)')
    ap.add_argument('--no-game', action='store_true', help='do not look for missing listed files in the game')
    ap.add_argument('--no-neighbours', action='store_true', help='do not read the Lua of the other addons')
    ap.add_argument('--write-names', metavar='OUT')
    ap.add_argument('lua', nargs='*')
    a = ap.parse_args()
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors='replace')
        except (AttributeError, ValueError):
            pass
    if a.write_names:
        names = Names()
        for source in a.lua:
            (lua_of if os.path.isdir(source) else lua_of_zip)(source, names)
        names.write(a.write_names, [os.path.basename(s.rstrip('/\\')) for s in a.lua])
        say(u'%s: files %d, names %d, beginnings %d, endings %d' % (a.write_names, names.files, len(names.whole), len(names.begin), len(names.end)))
        return 0
    return run(a)


if __name__ == '__main__':
    sys.exit(main())
