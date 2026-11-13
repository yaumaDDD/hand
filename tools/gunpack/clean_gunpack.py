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

Steps: 1. files in numbered or nested folders (sound1, pack/materials ...) go to their place
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
import struct
import sys
import zipfile

ROOTS = ('sound', 'materials', 'models')
SOUNDS = ('.wav', '.mp3', '.ogg')
MODEL_PARTS = ('.vvd', '.vtx', '.phy', '.ani')
KINDS = SOUNDS + ('.vmt', '.vtf', '.mdl') + MODEL_PARTS
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


def lua_of(folder, names, skip=None):
    """reads every text below the lua-like folders of an addon (or of any folder)"""
    count = 0
    for base, dirs, files in os.walk(long_path(folder)):
        dirs[:] = [d for d in dirs if d.lower() not in ROOTS + ('.git', 'maps', 'resource', 'particles')]
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
def game_path(rel):
    """materials1/models/x.vmt -> materials/models/x.vmt ; pack/sound/a.wav -> sound/a.wav ;
    None when no folder above the file is one of the game"""
    parts = rel.split('/')
    for i, part in enumerate(parts[:-1]):
        found = _ROOT_PART.match(part)
        if found:
            return '/'.join([found.group(1).lower()] + parts[i + 1:]).lower()
    return None


def walk(addon):
    """{path below the addon, lower case: path on the disk as it is spelled} of the judged files"""
    out = {}
    top = long_path(addon)
    for base, dirs, files in os.walk(top):
        below = os.path.relpath(base, top).replace(os.sep, '/')
        below = '' if below == '.' else below + '/'
        if not below:
            dirs[:] = [d for d in dirs if d.lower() not in ('lua', 'gamemodes', '.git', 'clean_gunpack')]
        for name in files:
            if os.path.splitext(name)[1].lower() in KINDS:
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


def used_files(files, names):
    """files: {game path: disk path}. -> (set of the used game paths, set of wanted paths that are missing)"""
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
    if not any(os.path.isdir(os.path.join(addon, root)) for root in ROOTS) and not walk(addon):
        say(u'В папке %s нет папок sound, materials, models — положите clean_gunpack.bat и папку' % addon)
        say(u'clean_gunpack в папку аддона с контентом ган-пака (рядом с sound / materials / models).')
        return 1
    say(u'Аддон: %s' % addon)

    # ---- what the Lua names
    names = Names()
    listed = os.path.join(here, NAMES)
    if os.path.isfile(listed):
        names.read(listed)
        say(u'  имена из Lua Remorseim и Z-City (%s): файлов Lua %d' % (NAMES, names.files))
    count = lua_of(addon, names, skip=here)
    if count:
        say(u'  Lua самого аддона: файлов %d' % count)
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
    for extra in a.lua:
        if os.path.isdir(extra):
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
    on_disk = walk(addon)
    files, moved, doubles, stray, failed = {}, [], [], [], []
    for rel in sorted(on_disk):
        full = on_disk[rel]
        place = game_path(rel)
        if place is None:
            stray.append(rel)
            continue
        if rel.lower() == place and rel.split('/')[0] == place.split('/')[0]:
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

    # ---- 2. what is used
    used, wanted = used_files(files, names)

    unused = sorted(rel for rel in files if rel not in used)
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
    if stray:
        say(u'  не тронуто (лежат не в sound / materials / models или место занято другим файлом): %d' % len(stray))
    say(u'  используется: %d' % len(used))
    say(u'  не используется: %d, точных копий: %d — всего %s МБ' % (len(unused), len(doubles), megabytes(size)))

    report.append(u'Переложено на своё место: %d' % len(moved))
    report += [u'  %s -> %s' % pair for pair in moved]
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
