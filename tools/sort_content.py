#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Puts the materials and models of clothing addons where the game looks for them - in an addon
that is installed, on the computer of its owner.  (started by sort_content.bat)

    sort_content.py                   sorts what lies in the materials and models folders of the addon
    sort_content.py FOLDER|ZIP ...    also takes in the content of these folders and archives (copies)
    sort_content.py --dry-run ...     only tells what it would do

The game finds a material or a model only at the exact path that the Lua, a model or a material
names; the files of clothing addons tend to arrive a folder off, or in folders of their own. This
script reads the names out of the Lua of the addon (lua/...), finds every file by its name -
tools/place_content.py does that, the same code the build of the addon uses - and moves it to its
place. Nothing is deleted and no file of the addon is overwritten: what cannot be used is moved to
the folder _not_used, and everything is written down in sort_content_report.txt.

The content may be thrown in the way it was collected - the materials folder of one addon, of the
next one ... as materials1, materials2, models1 ... - into the materials folder, into the models
folder, into both, in a folder of their own, or beside the two: every folder is gone through. A
file that nothing names, in a folder nothing is known of, goes where such folders put it: a
numbered folder is a copy of materials/ (models/), the files of a model belong below models/,
materials and textures below materials/ (zcg_layout.merged_destination). What is neither - a
note, a picture - moves along with its folder. A numbered folder that is empty then is removed.

The text of the Lua does not show every name: some are put together while the Lua runs, some are
written from inside the materials folder. There is no Lua to run here, so the build of the addon
ran it and left the names beside this script (lua_names.txt, see list_content.py); they are looked
for as well. A Lua file that was added or changed since is only read - the script says so.

The addon is the folder this script was shipped in (<addon>/sort_content/); --addon names another.
Needs Python 3.7+ and nothing else (sort_content.bat fetches a portable one when there is none).
"""
import argparse
import collections
import io
import os
import shutil
import sys
import tempfile
import zipfile

sys.dont_write_bytecode = True      # no __pycache__ inside an addon folder

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import zcg_layout as L  # noqa: E402
import list_content  # noqa: E402
import place_content as P  # noqa: E402
import content_report  # noqa: E402

STAGE = '_sorting'        # files on their way (with a journal, so that a run that was cut off is finished)
ASIDE = '_not_used'       # files of the addon that have no place in it
REPORT = 'sort_content_report.txt'
ROOTS = ('materials', 'models')
# a file that is no material and no model, and cannot move along with its folder
NOT_CONTENT = u'не материал и не модель (заметка, картинка …), а на его месте уже лежит файл с таким именем'
LEFT_BEHIND = u'не материал и не модель (заметка, картинка …): лежал в папке с номером, из которой всё остальное разложено'
# the folders of an addon that the game reads, and those of this tool: what lies in any other
# folder of the addon is seen by nobody
KNOWN_FOLDERS = L.CONTENT_ROOTS + ('maps', 'gamemodes', 'data', 'data_static', 'sort_content', STAGE, ASIDE)


class UserError(Exception):
    pass


def say(text=u''):
    print(text)
    sys.stdout.flush()


def walk_files(root):
    for base, _dirs, files in os.walk(root):
        for name in files:
            full = os.path.join(base, name)
            yield os.path.relpath(full, root).replace('\\', '/'), full


def long_path(path):
    """Windows refuses paths of 260 characters and more unless they are written this way"""
    if os.name == 'nt' and len(path) >= 240 and not path.startswith('\\\\'):
        return '\\\\?\\' + os.path.abspath(path)
    return path


# ---- what there is ---------------------------------------------------------------------------
def find_addon(given):
    addon = os.path.abspath(given) if given else os.path.dirname(HERE)
    if not os.path.isdir(os.path.join(addon, 'lua')):
        raise UserError(u'Это не папка аддона (в ней нет папки lua): %s\n'
                        u'Запускайте sort_content.bat из папки аддона или укажите её: --addon ПАПКА' % addon)
    return addon


class Names(object):
    """what the Lua of the addon names"""
    def __init__(self):
        self.named = set()          # materials/x.vmt, models/y.mdl - without those of Z-City itself
        self.files = 0              # Lua files that were read
        self.stock_known = False    # is the list of Z-City's own names beside the scripts?
        self.listed = None          # names the build found by running the Lua; None: no such list here
        self.by_running = 0         # ... how many of them the text does not show
        self.not_run = False        # the list says that the Lua could not be run where the addon was built
        self.changed = []           # Lua files that are not the ones the list was made from
        self.failed = []            # (Lua file, error): stopped with an error where the addon was built
        self.by = {}                # name -> the Lua file that names it (below lua/)
        self.titles = {}            # Lua file -> the title of the pack it came with
        # Packs whose Lua is not in the addon: another version of them is (the build took that
        # one, zcg_layout.PACK_VERSIONS).
        self.instead = {}           # title of such a pack -> title of the pack that is in the addon
        self.spare = {}             # a file only such a pack names -> its title
        self.only = {}              # a file the addon names and such a pack does not -> the title of that pack

    def pack(self, name):
        """the pack that names a file: its title, else its Lua file; '' when that is not known"""
        lua = self.by.get(name)
        if not lua:
            return u''
        return self.titles.get(lua) or u'lua/%s' % lua

    def who(self, name):
        """... with the Lua file"""
        lua = self.by.get(name)
        if not lua:
            return u''
        title = self.titles.get(lua)
        return u'%s (lua/%s)' % (title, lua) if title else u'lua/%s' % lua


def names_of(folders, run_list=None):
    """The materials and models the Lua in these folders names, without those of Z-City itself
    (and without the Lua of the gloves: it only speaks of files the addon has from the start):
    what the text of the Lua spells out, and what the build of the addon found by running it
    (run_list: that list, by default the one beside this script). Returns a Names."""
    own = L.OWN_LUA
    result = Names()
    seen = {}
    for number, folder in enumerate(folders):
        for rel, full in walk_files(folder):
            if not rel.lower().endswith('.lua') or rel.lower().startswith(own):
                continue
            result.files += 1
            with open(full, 'rb') as f:
                text = f.read().decode('utf-8-sig', 'replace')
            found = list_content.names_in(text)
            result.named |= found
            # (the list knows the Lua of the addon itself: the first folder)
            key = rel.lower() if number == 0 else u'%s/%s' % (folder, rel)
            seen[key] = list_content.lua_fingerprint(text)
            for name in found:
                result.by.setdefault(name, key)
    stock = list_content.stock_names()
    result.stock_known = bool(stock)

    listed, made_from, ran = list_content.read_run_list(run_list)
    if made_from is not None:
        result.listed = len(listed)
        result.not_run = not ran
        result.by_running = len(listed - result.named - stock)
        result.named |= listed
        result.changed = sorted(name for name, digest in seen.items() if made_from.get(name) != digest)
        # (a file that was changed since is not the one that failed)
        result.failed = sorted((name, message) for name, message in list_content.read_run_failed(run_list).items()
                               if name in seen and made_from.get(name) == seen[name])
        # (the build knows which file puts a name into the tables: that says more than the text)
        by, titles = list_content.read_run_who(run_list)
        result.by.update(by)
        result.titles = titles
        spare, result.instead = list_content.read_run_other(run_list)
        # (a name the Lua in the folder names after all is a name of the addon)
        result.spare = dict((name, title) for name, title in spare.items()
                            if name not in result.named and name not in stock)
        result.only = dict((name, title) for name, title in list_content.read_run_only(run_list).items()
                           if name in result.named and name not in stock)
    result.named -= stock
    return result


def beside(addon):
    """folders of the addon, beside materials/ and models/, that are numbered copies of the two
    ("materials3", put next to materials/ instead of into it): [(folder, 'materials' or 'models')].
    They are gone through as if they lay in that folder."""
    found = []
    try:
        entries = sorted(os.listdir(addon), key=P.natural)
    except OSError:
        return found
    for entry in entries:
        top = L.numbered_root(entry)
        if top and entry.lower() not in KNOWN_FOLDERS and os.path.isdir(os.path.join(addon, entry)):
            found.append((entry, top))
    return found


def stray(addon):
    """[(folder, content files in it)]: folders of the addon that hold materials or models and
    that neither the game nor this tool looks into - a pack that was put beside materials/
    instead of into it"""
    found = []
    try:
        entries = sorted(os.listdir(addon))
    except OSError:
        return found
    for entry in entries:
        full = os.path.join(addon, entry)
        if entry.lower() in KNOWN_FOLDERS or entry.startswith('.') or not os.path.isdir(full) \
                or L.numbered_root(entry):
            continue
        count = sum(1 for rel, _full in walk_files(full) if P.kind_of(rel))
        if count:
            found.append((entry, count))
    return found


def real_folders(names):
    """the folders of the game that these names lie in, with the folders above them"""
    found = set()
    for path in names:
        parts = path.split('/')[:-1]
        for cut in range(1, len(parts) + 1):
            found.add('/'.join(parts[:cut]))
    return found


def numbered_folder(rel, real=()):
    """the outermost folder a file of the addon lies in that is a copy of materials/ or models/
    by its name - a numbered one ("materials/materials3"), or a second one inside the first
    ("materials/materials", "models/my pack/models") - or None.
    real: the folders the game is known to have (real_folders): none of them is such a copy"""
    parts = rel.lower().split('/')[:-1]
    for cut, part in enumerate(parts):
        if (L.numbered_root(part) or (cut and (part == 'materials' or part == parts[0] == 'models'))) \
                and '/'.join(parts[:cut + 1]) not in real:
            return '/'.join(parts[:cut + 1])
    return None


def unpack(archive, temp):
    """the files of an archive, in a folder of their own below temp"""
    dest = tempfile.mkdtemp(prefix='source_', dir=temp)
    lower = archive.lower()
    if lower.endswith('.zip'):
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                if info.is_dir():
                    continue
                parts = [p for p in L.zip_name(info).replace('\\', '/').split('/') if p not in ('', '.')]
                if not parts or '..' in parts:
                    continue
                target = os.path.join(dest, *parts)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with z.open(info) as src, open(long_path(target), 'wb') as f:
                    shutil.copyfileobj(src, f)
        return dest
    if lower.endswith('.7z'):
        try:
            import py7zr
        except ImportError:
            raise UserError(u'Архив .7z здесь не читается: распакуйте его и укажите папку: %s' % archive)
        with py7zr.SevenZipFile(archive) as z:
            z.extractall(dest)
        return dest
    raise UserError(u'Не папка и не архив .zip: %s' % archive)


def collect(addon, sources, temp, real=()):
    """returns (items for place_content, files of the addon that only need lower-case paths,
    files from outside that keep their path, what the sources brought, files of the addon that
    are no content and move along with their folders: [(path, path then - None for a file
    that lies right in a numbered folder)]).
    real: the folders the game is known to have (real_folders)"""
    name = os.path.basename(addon)
    items, lower_case, extra, brought, along = [], [], [], [], []

    order = 0
    for source in sources:
        order += 1
        if not os.path.exists(source):
            raise UserError(u'Нет такой папки или файла: %s' % source)
        label = os.path.basename(os.path.normpath(source)) or source
        if label == name:
            label += u' (%d)' % order      # (reports tell the sources apart by their names)
        root = source if os.path.isdir(source) else unpack(source, temp)
        entry = dict(name=label, kind='folder' if os.path.isdir(source) else 'archive', no_place=[],
                     content=0, other=0, lua=0)
        for rel, full in sorted(walk_files(root)):
            if P.kind_of(rel):
                items.append(P.Item(label, rel, full, L.dropin_destination(rel), order, L.merged_destination(rel),
                                    L.merged_destination(rel, mirror=True)))
                entry['content'] += 1
                continue
            # (a note or a picture: by its folders, read like those of the content beside it)
            dest = L.merged_destination(rel) or L.dropin_destination(rel)
            if dest is None:
                entry['no_place'].append(rel)
            elif dest.split('/', 1)[0] in ROOTS:
                extra.append((full, dest))     # an icon, a note ...: by its folders, as it is
                entry['other'] += 1
            else:
                entry['lua'] += 1              # Lua, sounds: not the business of this tool
        brought.append(entry)

    # The addon itself comes last: what lies in it is not replaced by what comes from outside.
    # Of two of its own files for one place the one that lies there already stays.
    # A numbered folder beside materials/ ("materials3", put next to it instead of into it) is
    # gone through as if it lay in it.
    mine = dict(name=name, kind='folder', no_place=[], content=0, other=0, lua=0, beside=beside(addon), archives=[])
    for top, inside in [(top, None) for top in ROOTS] + mine['beside']:
        for rel, full in sorted(walk_files(os.path.join(addon, top))):
            rel = top + '/' + rel
            if L.is_own_content(rel):
                continue
            seen = rel if inside is None else inside + '/' + rel
            if P.kind_of(rel):
                default = L.dropin_destination(seen)
                item = P.Item(name, rel, full, default, order + (2 if default == rel else 1),
                              L.merged_destination(seen, real), L.merged_destination(seen, real, mirror=True))
                item.in_addon = True
                items.append(item)
                mine['content'] += 1
                continue
            if L.ARCHIVE.search(rel):
                mine['archives'].append(rel)    # (nothing here opens it: it stays, and is told)
                continue
            # (a note, a picture: it moves along with a numbered folder it lies in, and only then)
            if numbered_folder(rel, real) is not None:
                dest = L.merged_destination(seen, real)
                if dest is None or dest == seen.lower() or dest.split('/', 1)[0] not in ROOTS:
                    dest = None                 # right in the numbered folder, or no content at all: see plan
                along.append((rel, dest))
            elif rel != rel.lower():
                lower_case.append((rel, rel.lower()))
    brought.append(mine)
    return items, lower_case, extra, brought, along


# ---- what to do ------------------------------------------------------------------------------
class Job(object):
    def __init__(self):
        self.moves = []     # (path in the addon now, path in the addon then)
        self.aside = []     # (path in the addon now, why it has no place)
        self.copies = []    # (file, path in the addon then)
        self.stay = 0       # files of the addon that lie where they belong
        self.unknown = 0    # ... and those that stay in their folders because nothing is known of them
        self.lowered = 0    # (how many of these get a lower-case path: a move that is not counted as one)
        # numbered folders ("materials/materials3"): folder -> [files in it, of them moved to a
        # place, of them put aside]
        self.numbered = collections.OrderedDict()
        # files of a model that lay below materials/ and go below models/, and the other way round
        self.crossed = collections.Counter()


def plan(addon, items, lower_case, extra, report, along=(), real=()):
    job = Job()

    def count(now, moved=0, aside=0):
        folder = numbered_folder(now, real)
        if folder is not None:
            entry = job.numbered.setdefault(folder, [0, 0, 0])
            entry[0] += 1
            entry[1] += moved
            entry[2] += aside
    places = collections.defaultdict(list)
    for dest, item in report.placed:
        places[id(item)].append(dest)
    reasons = dict((id(item), reason) for item, reason in report.left_out)
    unknown = set(id(item) for item in report.as_packed)

    for item in items:
        dests = places.get(id(item), [])
        if not getattr(item, 'in_addon', False):
            for dest in dests:
                job.copies.append((item.path, dest))
            continue
        if not dests:
            job.aside.append((item.inner, reasons.get(id(item), P.UNNAMED)))
            count(item.inner, aside=1)
            continue
        first = item.inner if item.inner in dests else dests[0]
        if id(item) in unknown and first.lower() == item.inner.lower():
            job.unknown += 1
            job.lowered += first != item.inner
        elif first == item.inner:
            job.stay += 1
        count(item.inner, moved=first.lower() != item.inner.lower())
        if first != item.inner:
            job.moves.append((item.inner, first))
            tops = item.inner.split('/', 1)[0].lower(), first.split('/', 1)[0]
            if tops[0] in ROOTS and tops[0] != tops[1]:
                job.crossed[tops] += 1
        for dest in dests:
            if dest != first:   # one file, wanted at two paths
                job.copies.append((os.path.join(addon, first), dest))
    job.moves += lower_case

    # What is no material and no model moves along with its folder - to a place that is free.
    taken = set(dest for dest, _item in report.placed)
    taken.update(then.lower() for _now, then in job.moves)
    waiting = collections.defaultdict(list)
    # (the later folder first, as with the content: of two numbered folders with a file for one
    # place the later one has it)
    for now, then in sorted(along, key=lambda pair: P.natural(pair[0].lower()), reverse=True):
        if then is None:
            waiting[numbered_folder(now, real)].append(now)     # right in a numbered folder: nowhere to go
            count(now)
        elif then in taken or os.path.lexists(os.path.join(addon, then)):
            job.aside.append((now, NOT_CONTENT))
            count(now, aside=1)
        else:
            taken.add(then)
            job.moves.append((now, then))
            count(now, moved=1)
    # ... and a note that lay right in a numbered folder does not keep that folder there, once
    # everything else has moved out of it
    for folder, notes in waiting.items():
        files, moved, aside = job.numbered[folder]
        if files - moved - aside == len(notes):
            job.aside += [(now, LEFT_BEHIND) for now in notes]
            job.numbered[folder][2] += len(notes)
    for full, dest in extra:
        if not os.path.lexists(os.path.join(addon, dest)):     # (it is there already: an earlier run)
            job.copies.append((full, dest))
    return job


def free_name(path):
    if not os.path.lexists(path):
        return path
    n = 1
    while os.path.lexists('%s.%d' % (path, n)):
        n += 1
    return '%s.%d' % (path, n)


def prune(folder):
    """removes the empty folders below a folder (not the folder itself)"""
    for base, dirs, _files in os.walk(folder, topdown=False):
        for name in dirs:
            try:
                os.rmdir(os.path.join(base, name))
            except OSError:
                pass


def finish(addon, pending, problems):
    """the second half of a move: from the stage to the place. pending: [(staged file, then, before)]"""
    for staged, then, before in pending:
        target = os.path.join(addon, then)
        if os.path.lexists(target):
            # the file that lies there could not be moved away: back to where it came from
            back = os.path.join(addon, before)
            target = back if not os.path.lexists(back) else free_name(os.path.join(addon, ASIDE, before))
            problems.append((before, u'место занято: %s' % then))
        try:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            os.replace(long_path(staged), long_path(target))
        except OSError as err:
            problems.append((before, u'%s' % err))


def resume(addon):
    """a run that was cut off left files in the stage folder: they go where they were going"""
    stage = os.path.join(addon, STAGE)
    journal = os.path.join(stage, 'journal.txt')
    if not os.path.isdir(stage):
        return 0
    pending, problems = [], []
    if os.path.isfile(journal):
        with io.open(journal, encoding='utf-8') as f:
            for line in f:
                parts = line.rstrip('\n').split('\t')
                if len(parts) == 3 and os.path.isfile(os.path.join(stage, parts[0])):
                    pending.append((os.path.join(stage, parts[0]), parts[1], parts[2]))
    finish(addon, pending, problems)
    if os.path.isfile(journal):
        os.remove(journal)
    try:
        os.rmdir(stage)
    except OSError:
        raise UserError(u'В папке %s остались файлы от прерванного запуска, и неизвестно, куда они шли. '
                        u'Разберите её вручную и запустите ещё раз.' % stage)
    return len(pending)


def apply(addon, job):
    """does what the job says. Returns [(path, what went wrong)]"""
    problems = []
    stage = os.path.join(addon, STAGE)
    staged = []
    todo = list(job.moves)
    for now, _reason in job.aside:
        todo.append((now, os.path.relpath(free_name(os.path.join(addon, ASIDE, now)), addon).replace('\\', '/')))
    if todo:
        os.makedirs(stage)
        # First everything that moves leaves the tree: then no file is in the way of another one,
        # and a folder that only differs in the case of its name can be made anew.
        with io.open(os.path.join(stage, 'journal.txt'), 'w', encoding='utf-8') as journal:
            for n, (now, then) in enumerate(todo):
                key = '%06d' % n
                journal.write(u'%s\t%s\t%s\n' % (key, then, now))
                journal.flush()
                try:
                    os.replace(long_path(os.path.join(addon, now)), os.path.join(stage, key))
                except OSError as err:
                    problems.append((now, u'%s' % err))
                    continue
                staged.append((os.path.join(stage, key), then, now))
        for top in ROOTS:
            prune(os.path.join(addon, top))
        for top, _inside in beside(addon):
            prune(os.path.join(addon, top))
            try:
                os.rmdir(os.path.join(addon, top))
            except OSError:
                pass
        finish(addon, staged, problems)
        os.remove(os.path.join(stage, 'journal.txt'))
        try:
            os.rmdir(stage)
        except OSError:
            pass

    for source, dest in job.copies:
        target = os.path.join(addon, dest)
        if os.path.lexists(target):
            continue        # (decided by place_content: only possible when a file could not leave)
        try:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copyfile(long_path(source), long_path(target))
        except OSError as err:
            problems.append((dest, u'%s' % err))
    return problems


# ---- telling about it ------------------------------------------------------------------------
def summary(addon, names, brought, report, job, dry, problems):
    """the lines for the screen and for the head of the report"""
    name = os.path.basename(addon)
    named = names.named
    out = [u'Аддон: %s' % addon,
           u'Lua аддона (файлов: %d) называет материалов и моделей: %d' % (names.files, len(named))]
    if names.by_running:
        out.append(u'  из них %d в тексте Lua не видны — их нашла сборка аддона, запустив этот Lua' % names.by_running)
    if names.listed is None or names.not_run:
        out.append(u'  ВНИМАНИЕ: списка имён, найденных запуском Lua, рядом нет%s. Имена, которые Lua'
                   % (u' (аддон собран там, где Lua запустить было нечем)' if names.not_run else u''))
        out.append(u'  составляет на ходу или пишет без «models/» и «materials/», этому инструменту не известны:')
        out.append(u'  такой файл он может принять за тёзку из другого набора. Возьмите аддон из выпуска на GitHub.')
    elif names.changed:
        out.append(u'  ВНИМАНИЕ: Lua-файлов, добавленных или изменённых после сборки аддона: %d (%s%s).'
                   % (len(names.changed), u', '.join(names.changed[:3]), u' ...' if len(names.changed) > 3 else u''))
        out.append(u'  Они только прочитаны: имена, которые такой Lua составляет на ходу или пишет без «models/» и')
        out.append(u'  «materials/», не известны, и его файл может быть принят за тёзку из другого набора.')
        out.append(u'  Чтобы и они учитывались, Lua нужно добавить в сборку аддона (в репозиторий).')
    if names.failed:
        out.append(u'  ВНИМАНИЕ: при сборке аддона Lua-файлы остановились на ошибке: %d (%s%s).'
                   % (len(names.failed), u', '.join(name for name, _message in names.failed[:3]),
                      u' ...' if len(names.failed) > 3 else u''))
        out.append(u'  Что такой файл добавляет после места ошибки, не известно — и в игре этой одежды, скорее всего,')
        out.append(u'  тоже не будет. Ошибка: %s' % names.failed[0][1])
    if not names.stock_known:
        out.append(u'  (списка имён самого Z-City рядом нет: в «не хватает» попадут и его файлы)')
    for title, taken in sorted(names.instead.items()):
        count = sum(1 for pack in names.spare.values() if pack == title)
        out.append(u'  В этой сборке «%s». «%s» — другая версия того же аддона, её Lua в сборке нет:' % (taken, title))
        out.append(u'  в игре может быть только одна из двух. Файлы, которые называет только та версия (имён: %d),' % count)
        out.append(u'  игре с этой сборкой не нужны; в «не хватает» они не попадают.')
    apart = stray(addon)
    if apart:
        out.append(u'ВНИМАНИЕ: в папке аддона есть папки с материалами и моделями, в которые не смотрит ни игра, ни')
        out.append(u'  этот инструмент: %s%s.'
                   % (u', '.join(u'«%s» (файлов: %d)' % pair for pair in apart[:5]),
                      u' и ещё %d' % (len(apart) - 5) if len(apart) > 5 else u''))
        out.append(u'  Если это одежда — перетащите такую папку на sort_content.bat или переложите её в папку')
        out.append(u'  materials аддона и запустите ещё раз. (Папки с номерами — materials1, models 2 … — он')
        out.append(u'  разбирает и рядом с materials; у этих папок другие имена.)')
    archives = brought[-1].get('archives') or []
    if archives:
        out.append(u'ВНИМАНИЕ: в папках materials и models аддона лежат архивы — %d (%s%s).'
                   % (len(archives), u', '.join(archives[:3]), u' …' if len(archives) > 3 else u''))
        out.append(u'  Этот инструмент их не открывает, и игра тоже: распакуйте их туда же и запустите ещё раз.')
        out.append(u'  (Архив .zip можно перетащить на sort_content.bat; .gma распаковывает gmad.exe из папки bin игры.)')
    outside = brought[-1].get('beside') or []
    if outside:
        out.append(u'Папки с номерами рядом с materials и models (%s%s) разобраны так же, как если бы лежали внутри них.'
                   % (u', '.join(u'«%s»' % folder for folder, _top in outside[:5]),
                      u' и ещё %d' % (len(outside) - 5) if len(outside) > 5 else u''))
    for entry in brought:
        where = u'в папках materials и models аддона' if entry['name'] == name and entry is brought[-1] \
            else u'в «%s»' % entry['name']
        line = u'Файлов контента %s: %d' % (where, entry['content'])
        if entry['other']:
            line += u', прочих файлов для materials / models: %d' % entry['other']
        if entry['lua']:
            line += u'; Lua и звуки (%d) не тронуты — этот инструмент раскладывает только материалы и модели' % entry['lua']
        out.append(line)

    verb = u'Будет' if dry else u'Было'
    moved = len(job.moves) - job.lowered
    out.append(u'')
    if dry:
        out.append(u'ПРОБНЫЙ ЗАПУСК: ничего не перемещено. Вот что было бы сделано.')
    out.append(u'Уже лежит на своём месте: %d' % job.stay)
    if job.unknown:
        out.append(u'Оставлено в тех же папках (про эти файлы ничего не известно, папки — в отчёте): %d' % job.unknown)
    out.append(u'%s перемещено внутри аддона: %d' % (verb, moved))
    out.append(u'%s скопировано в аддон: %d' % (verb, len(job.copies)))
    out.append(u'%s убрано в папку %s (не пригодилось): %d' % (verb, ASIDE, len(job.aside)))
    copies = sum(1 for _now, reason in job.aside if reason == P.COPY)
    if copies:
        out.append(u'  из них точных копий файлов, которые уже лежат на своих местах: %d — их можно удалить' % copies)
    out += numbered_lines(job, dry)
    if problems:
        out.append(u'НЕ УДАЛОСЬ переместить: %d — закройте игру (она держит файлы открытыми) и запустите ещё раз'
                   % len(problems))
        for path, what in problems[:20]:
            out.append(u'    %s: %s' % (path, what))
        if len(problems) > 20:
            out.append(u'    ... и ещё %d' % (len(problems) - 20))

    out.append(u'')
    missing = len(report.missing_named) + len(report.missing_materials) + len(report.missing_textures)
    if missing:
        out.append(u'Не хватает файлов (их нет ни в аддоне, ни в том, что вы дали):')
        out.append(u'    названных в Lua: %d из %d' % (len(report.missing_named), len(named)))
        # (pack by pack: such files come with the content of that pack or of what it depends on)
        packs = content_report.by_pack(report.missing_named, names.pack) if names.by else []
        for label, wanted in packs[:10]:
            out.append(u'        %s — %d: %s' % (label or u'какой Lua называет — не известно', len(wanted),
                                                 content_report.folders_of(wanted)))
        if len(packs) > 10:
            out.append(u'        ... и ещё наборов: %d' % (len(packs) - 10))
        out.append(u'    материалов, которые ищут модели: %d из %d'
                   % (len(report.missing_materials), report.materials_wanted))
        out.append(u'    текстур, которые ищут материалы: %d из %d'
                   % (len(report.missing_textures), report.textures_wanted))
        out.append(u'  Часть из них — файлы самой игры и Z-City, их и не должно быть в аддоне. Остальные нужно')
        out.append(u'  добавить: положите их в папку materials или models аддона (в любые папки; можно целыми')
        out.append(u'  папками materials и models других аддонов, под номерами: materials1, models2 …) и запустите ещё раз.')
        if report.missing_named and len(brought) == 1:
            # (a source is copied from, not moved: what an earlier version did not take is still there)
            out.append(u'  Если папки с контентом вы раньше перетаскивали на sort_content.bat, перетащите их ещё раз:')
            out.append(u'  файл, имени которого прежняя версия не знала, она не взяла, и он остался в той папке.')
    else:
        out.append(u'Все названные файлы на месте.')
    out += content_report.version_lines(content_report.versions_found(report, names.instead, names.spare, names.only))
    other = [text for text in report.notes if getattr(text, 'kind', None) == 'other version']
    if other:
        out.append(u'ВНИМАНИЕ: файлов, которые по имени подошли бы на пустые места, но оказались файлами другой версии'
                   u' аддона: %d' % len(other))
        out.append(u'  (например «%s»). На места, которые называет Lua сборки, они не взяты: туда нужны файлы'
                   % (other[0].args[0],))
        out.append(u'  версии, которая в сборке. Подробности — в отчёте, «Замечания».')
    twice = [text for text in report.notes if getattr(text, 'kind', None) in ('version', 'version here')]
    if twice:
        out.append(u'Разных файлов на одно и то же место: пар — %d. Оставлен тот, что уже лежал на месте, иначе —' % len(twice))
        out.append(u'  из папки, которая позже по имени (materials10 позже materials2); второй убран в %s.' % ASIDE)
        out.append(u'  Какие это файлы — в отчёте, «Замечания».')
    if report.notes:
        out.append(u'Замечаний: %d (файлы-тёзки, которые нечем различить, и т. п.) — см. отчёт' % len(report.notes))
    return out


def numbered_lines(job, dry=False):
    """what became of the folders that are copies of materials/ and models/ by their names
    (Job.numbered), and of the files that lay below the wrong one of the two"""
    out = []
    folders = job.numbered
    if folders:
        files = sum(entry[0] for entry in folders.values())
        moved = sum(entry[1] for entry in folders.values())
        aside = sum(entry[2] for entry in folders.values())
        names = sorted(folders, key=P.natural)
        out.append(u'Папки-копии materials и models (с номером в имени или вложенные: %s%s) — %d:'
                   % (u', '.join(names[:3]), u' …' if len(names) > 3 else u'', len(names)))
        out.append(u'  файлов в них %d; %s на места: %d; в %s: %d; %s: %d'
                   % (files, u'будет переложено' if dry else u'переложено', moved, ASIDE, aside,
                      u'останется' if dry else u'осталось', files - moved - aside))
        if files - moved - aside:
            out.append(u'  Остались файлы, которые лежат прямо в такой папке, без подпапок, и о которых ничего не известно:')
            out.append(u'  куда их класть, по ним не понять. Какие это файлы — в отчёте, «Оставлено в тех же папках».')
    crossed = job.crossed
    if crossed.get(('materials', 'models')):
        out.append(u'Файлов моделей, лежавших в materials, %s в models: %d'
                   % (u'будет переложено' if dry else u'переложено', crossed[('materials', 'models')]))
    if crossed.get(('models', 'materials')):
        out.append(u'Материалов и текстур, лежавших в models, %s в materials: %d'
                   % (u'будет переложено' if dry else u'переложено', crossed[('models', 'materials')]))
    return out


def numbered_list(job):
    """... folder by folder, for the report"""
    out = []
    for folder in sorted(job.numbered, key=P.natural):
        files, moved, aside = job.numbered[folder]
        out.append(u'    %s/    файлов: %d, на места: %d, в %s: %d, осталось: %d'
                   % (folder, files, moved, ASIDE, aside, files - moved - aside))
    return out


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            # (a console shows any text; a file or a pipe gets UTF-8 instead of the code page)
            if stream.isatty():
                stream.reconfigure(errors='replace')
            else:
                stream.reconfigure(encoding='utf-8', errors='replace')

    parser = argparse.ArgumentParser(description='Sorts the materials and models of an installed addon by name.')
    parser.add_argument('sources', nargs='*', help='folders or .zip archives with more content to take in')
    parser.add_argument('--addon', help='the addon folder (default: the one this script lies in)')
    parser.add_argument('--lua', action='append', default=[], help='another folder with Lua that names files')
    parser.add_argument('--names-list', help='the list of the names found by running the Lua '
                                             '(default: %s beside this script)' % list_content.RUN_LIST)
    parser.add_argument('--dry-run', action='store_true', help='only tell what would be done')
    args = parser.parse_args(argv)

    temp = tempfile.mkdtemp(prefix='zcg_sort_')
    try:
        addon = find_addon(args.addon)
        if not args.dry_run:
            resumed = resume(addon)
            if resumed:
                say(u'Прошлый запуск был прерван: файлов доведено до места: %d' % resumed)

        say(u'Читаю Lua аддона ...')
        names = names_of([os.path.join(addon, 'lua')] + args.lua, args.names_list)
        named = names.named
        say(u'Читаю файлы контента ...')
        real = real_folders(set(named) | set(names.spare) | list_content.stock_names())
        items, lower_case, extra, brought, along = collect(addon, args.sources, temp, real)
        say(u'Ищу каждому файлу место (файлов: %d) ...' % len(items))
        report = P.place(items, named, L.is_own_content, set(names.spare))
        job = plan(addon, items, lower_case, extra, report, along, real)

        problems = []
        if not args.dry_run and (job.moves or job.aside or job.copies):
            say(u'Перекладываю ...')
            problems = apply(addon, job)

        head = summary(addon, names, brought, report, job, args.dry_run, problems)
        say()
        for line in head:
            say(line)

        reasons = collections.Counter(content_report.why(reason) for _now, reason in job.aside)
        more = list(head)
        if job.numbered:
            more += [u'', u'Папки-копии materials и models — по папкам:'] + numbered_list(job)
        if job.aside:
            more += [u'', u'Убрано в %s (причины):' % ASIDE] + [u'    %s — файлов: %d' % pair for pair in sorted(reasons.items())]
        listing = os.path.join(addon, REPORT)
        content_report.write(listing, brought, report, named, 'sort_content.py', more, names.who if names.by else None,
                             names.spare)
        say()
        say(u'Подробный отчёт: %s' % listing)
        if not args.dry_run and not problems:
            say(u'Готово. Запустите игру и наберите в консоли zcg_content — он покажет, чего ещё не хватает.')
        return 2 if problems else 0
    except UserError as err:
        say()
        say(u'ОШИБКА: %s' % err)
        return 1
    finally:
        shutil.rmtree(temp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
