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
numbered folder that holds a tree is a copy of materials/ (models/): every file in it is read as
lying at the path it has below that folder, before any name is looked up, and whatever a model
says it was compiled for (place_content.py, "One kind of folder is trusted") - the files of a
model below models/, materials and textures below materials/. A heap under a numbered name goes
by the names; a file of it that nothing names, in a folder nothing is known of, goes where such
folders put it (zcg_layout.merged_destination). What is neither - a note, a picture - moves
along with its folder. A numbered folder that is empty then is removed.

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
import posixpath
import re
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
import game_files  # noqa: E402

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


# The Lua of the other versions of a pack (zcg_layout.PACK_VERSIONS: Appearance Mod and its LEGACY)
# lies in the addon as well: sort_content/versions/<folder>/ holds, by their paths in the addon,
# the files that differ between the builds - a handful of Lua files and the list of names. When
# the content turns out to be that of another version, these files are put in place.
VERSIONS = 'versions'
VERSIONS_INDEX = 'index.txt'     # "<folder><tab><title>" a line


class UserError(Exception):
    pass


def say(text=u''):
    print(text)
    sys.stdout.flush()


class Seen(object):
    """what a walk through the folders came by: every folder is gone into, however deep it lies,
    and this is the count of it - and the list of what could not be read, so that a folder that
    was passed over is told and not just missing from the result"""

    def __init__(self, own=None):
        self.own = own                          # own(path): a folder of the addon's own content - not counted
        self.folders = 0                        # folders gone into
        self.depth, self.deepest = 0, u''       # the deepest one: how many folders down, and its path
        self.kinds = collections.Counter()      # the files: 'mdl', 'part', 'vmt', 'vtf', 'other'; 'own' - of the addon itself
        self.unread = []                        # (folder, why): folders that could not be listed

    def folder(self, path):
        if self.own is not None and self.own(path + '/'):
            return
        self.folders += 1
        depth = path.count('/') + 1
        if depth > self.depth:
            self.depth, self.deepest = depth, path

    @property
    def files(self):
        return sum(count for kind, count in self.kinds.items() if kind != 'own')


def deep(path):
    """a folder the way Windows reads it however long the paths below it get: paths of 260
    characters and more are refused unless they are written like this"""
    if os.name != 'nt':
        return path
    path = os.path.abspath(path)
    if path.startswith('\\\\?\\'):
        return path
    if path.startswith('\\\\'):
        return '\\\\?\\UNC\\' + path[2:]
    return '\\\\?\\' + path


def plain(path):
    """a path without what deep() put in front of it: the way it is shown"""
    if path.startswith('\\\\?\\UNC\\'):
        return '\\\\' + path[8:]
    if path.startswith('\\\\?\\'):
        return path[4:]
    return path


def walk_files(root, seen=None, shown=u''):
    """(path below the folder, the file) for every file below a folder, in every folder below it.
    seen: a Seen that counts the folders (shown: what to call the root in it) and keeps the ones
    that could not be read - without it they are passed over in silence."""
    top = deep(root)
    if not os.path.isdir(top):
        return      # (an addon without a models folder: nothing to go through, and nothing went wrong)

    def failed(err):
        if seen is not None:
            seen.unread.append((plain(getattr(err, 'filename', None) or top), getattr(err, 'strerror', None) or u'%s' % err))

    for base, _dirs, files in os.walk(top, onerror=failed):
        inner = base[len(top):].replace('\\', '/').strip('/')
        if seen is not None and inner:
            seen.folder(shown + inner)
        for name in files:
            yield (inner + '/' + name if inner else name), os.path.join(base, name)


def long_path(path):
    """Windows refuses paths of 260 characters and more unless they are written this way"""
    if os.name == 'nt' and len(path) >= 240:
        return deep(path)
    return path


# ---- what there is ---------------------------------------------------------------------------
def find_addon(given):
    addon = os.path.abspath(given) if given else os.path.dirname(HERE)
    if not os.path.isdir(os.path.join(addon, 'lua')):
        raise UserError(u'Это не папка аддона (в ней нет папки lua): %s\n'
                        u'Запускайте sort_content.bat из папки аддона или укажите её: --addon ПАПКА' % addon)
    return addon


def versions_of(addon):
    """{title of a version: the folder with its files} - the versions the addon can be switched to
    (the one that is in place is among them)"""
    base = os.path.join(addon, 'sort_content', VERSIONS)
    found = {}
    try:
        with io.open(os.path.join(base, VERSIONS_INDEX), encoding='utf-8-sig', errors='replace') as f:
            lines = f.read().splitlines()
    except (OSError, IOError):
        return found
    for line in lines:
        if line.startswith('#') or '\t' not in line:
            continue
        folder, title = line.split('\t', 1)
        folder, title = folder.strip(), title.strip()
        # (a name of one folder, nothing that leads out of the addon)
        if folder and title and folder not in ('.', '..') and not re.search(r'[\\/:]', folder) \
                and os.path.isdir(os.path.join(base, folder)):
            found[title] = os.path.join(base, folder)
    return found


def version_asked(versions, text):
    """the title --use-version means: the title itself, else the only one that has the text in it"""
    wanted = text.strip().lower()
    for title in versions:
        if title.lower() == wanted:
            return title
    fits = [title for title in versions if wanted and wanted in title.lower()]
    if len(fits) == 1:
        return fits[0]
    raise UserError(u'--use-version «%s»: %s. Версии в этом аддоне: %s'
                    % (text, u'подходит несколько' if fits else u'такой версии нет',
                       u', '.join(u'«%s»' % title for title in sorted(versions)) or u'ни одной (в аддоне нет sort_content/versions)'))


def switch_version(addon, folder):
    """puts the files of a version in place (each by its path in the addon, whole or not at all);
    returns (files that were replaced, files that were the same already)"""
    changed = same = 0
    for rel, full in sorted(walk_files(folder)):
        target = os.path.join(addon, rel.replace('/', os.sep))
        with open(long_path(full), 'rb') as f:
            data = f.read()
        try:
            with open(long_path(target), 'rb') as f:
                if f.read() == data:
                    same += 1
                    continue
        except (OSError, IOError):
            pass
        try:
            if not os.path.isdir(long_path(os.path.dirname(target))):
                os.makedirs(long_path(os.path.dirname(target)))
            fresh = target + '.zcg_new'
            with open(long_path(fresh), 'wb') as f:
                f.write(data)
            os.replace(long_path(fresh), long_path(target))
        except (OSError, IOError) as err:
            raise UserError(u'Не удалось заменить файл %s: %s\n'
                            u'Закройте игру (и сервер), если они запущены, и запустите sort_content.bat ещё раз.' % (rel, err))
        changed += 1
    return changed, same


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
        self.switch = set()         # titles of such packs whose Lua the addon carries: it can be switched to them
        self.held = set()           # the same titles when the owner asked to keep the version that is in place

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
    return L.numbered_folder(rel, real)


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


def collect(addon, sources, temp, real=(), seen=None):
    """returns (items for place_content, files of the addon that only need lower-case paths,
    files from outside that keep their path, what the sources brought, files of the addon that
    are no content and move along with their folders: [(path, path then - None for a file
    that lies right in a numbered folder)]).
    real: the folders the game is known to have (real_folders);
    seen: a Seen that counts the folders and the files gone through"""
    name = os.path.basename(addon)
    if seen is None:
        seen = Seen(L.is_own_content)
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
        files = sorted(walk_files(root, seen, label + u': '))
        # (the numbered folders that hold a tree: a file right in one of them is a file of its top)
        trees = L.tree_roots(rel for rel, _full in files if P.kind_of(rel))
        for rel, full in files:
            seen.kinds[P.kind_of(rel) or 'other'] += 1
            if P.kind_of(rel):
                items.append(P.Item(label, rel, full, L.dropin_destination(rel), order,
                                    L.merged_destination(rel, trees=trees),
                                    L.merged_destination(rel, mirror=True, trees=trees), L.numbered_folder(rel)))
                entry['content'] += 1
                continue
            # (a note or a picture: by its folders, read like those of the content beside it)
            dest = L.merged_destination(rel) or L.dropin_destination(rel)
            if dest is None:
                entry['no_place'].append(rel)
            elif dest.split('/', 1)[0] in ROOTS:
                extra.append((full, dest, u'%s: %s' % (label, rel)))    # an icon, a note ...: by its folders, as it is
                entry['other'] += 1
            else:
                entry['lua'] += 1              # Lua, sounds: not the business of this tool
        brought.append(entry)

    # The addon itself comes last: what lies in it is not replaced by what comes from outside.
    # Of two of its own files for one place the one that lies there already stays.
    # A numbered folder beside materials/ ("materials3", put next to it instead of into it) is
    # gone through as if it lay in it.
    mine = dict(name=name, kind='folder', no_place=[], content=0, other=0, lua=0, beside=beside(addon), archives=[])
    files = []
    for top, inside in [(top, None) for top in ROOTS] + mine['beside']:
        for rel, full in sorted(walk_files(os.path.join(addon, top), seen, top + '/')):
            rel = top + '/' + rel
            if L.is_own_content(rel):
                seen.kinds['own'] += 1
            else:
                seen.kinds[P.kind_of(rel) or 'other'] += 1
                files.append((rel, full, rel if inside is None else inside + '/' + rel))
    trees = L.tree_roots((seen for rel, _full, seen in files if P.kind_of(rel)), real)
    for rel, full, seen in files:
        if P.kind_of(rel):
            default = L.dropin_destination(seen)
            item = P.Item(name, rel, full, default, order + (2 if default == rel else 1),
                          L.merged_destination(seen, real, trees=trees),
                          L.merged_destination(seen, real, mirror=True, trees=trees), L.numbered_folder(seen, real))
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
        # ... folder -> the folders below it (and itself) that held files
        self.inside = collections.defaultdict(set)
        # files of a model that lay below materials/ and go below models/, and the other way round
        self.crossed = collections.Counter()
        # what became of every file that was gone through: (where it lay, where it lies then, how) -
        # how: IN_PLACE (it lay right), KEPT (nothing is known of it: it stays), MOVED, COPIED, a
        # reason (put aside), or LEFT (a file of a folder that was handed over: not taken)
        self.fate = []


IN_PLACE, KEPT, MOVED, COPIED, LEFT = 'in place', 'kept', 'moved', 'copied', 'left'


def plan(addon, items, lower_case, extra, report, along=(), real=()):
    job = Job()

    def count(now, moved=0, aside=0):
        folder = numbered_folder(now, real)
        if folder is not None:
            entry = job.numbered.setdefault(folder, [0, 0, 0])
            entry[0] += 1
            entry[1] += moved
            entry[2] += aside
            job.inside[folder].add(posixpath.dirname(now).lower())
    places = collections.defaultdict(list)
    for dest, item in report.placed:
        places[id(item)].append(dest)
    reasons = dict((id(item), reason) for item, reason in report.left_out)
    unknown = set(id(item) for item in report.as_packed)

    for item in items:
        dests = places.get(id(item), [])
        if not getattr(item, 'in_addon', False):
            shown = u'%s: %s' % (item.source, item.inner)
            for dest in dests:
                job.copies.append((item.path, dest))
                job.fate.append((shown, dest, COPIED))
            if not dests:
                job.fate.append((shown, None, reasons.get(id(item), LEFT)))
            continue
        if not dests:
            reason = reasons.get(id(item), P.UNNAMED)
            job.aside.append((item.inner, reason))
            job.fate.append((item.inner, ASIDE + '/' + item.inner, reason))
            count(item.inner, aside=1)
            continue
        first = item.inner if item.inner in dests else dests[0]
        if id(item) in unknown and first.lower() == item.inner.lower():
            job.unknown += 1
            job.lowered += first != item.inner
            job.fate.append((item.inner, first, KEPT))
        elif first == item.inner:
            job.stay += 1
            job.fate.append((item.inner, first, IN_PLACE))
        else:
            job.fate.append((item.inner, first, MOVED))
        count(item.inner, moved=first.lower() != item.inner.lower())
        if first != item.inner:
            job.moves.append((item.inner, first))
            tops = item.inner.split('/', 1)[0].lower(), first.split('/', 1)[0]
            if tops[0] in ROOTS and tops[0] != tops[1]:
                job.crossed[tops] += 1
        for dest in dests:
            if dest != first:   # one file, wanted at two paths
                job.copies.append((os.path.join(addon, first), dest))
                job.fate.append((item.inner, dest, COPIED))
    job.moves += lower_case
    job.fate += [(now, then, MOVED) for now, then in lower_case]

    # What is no material and no model moves along with its folder - to a place that is free.
    taken = set(dest for dest, _item in report.placed)
    taken.update(then.lower() for _now, then in job.moves)
    waiting = collections.defaultdict(list)
    # (the later folder first, as with the content: of two numbered folders with a file for one
    # place the later one has it)
    for now, then in sorted(along, key=lambda pair: P.by_folders(pair[0]), reverse=True):
        if then is None:
            waiting[numbered_folder(now, real)].append(now)     # right in a numbered folder: nowhere to go
            count(now)
        elif then in taken or os.path.lexists(long_path(os.path.join(addon, then))):
            job.aside.append((now, NOT_CONTENT))
            job.fate.append((now, ASIDE + '/' + now, NOT_CONTENT))
            count(now, aside=1)
        else:
            taken.add(then)
            job.moves.append((now, then))
            job.fate.append((now, then, MOVED))
            count(now, moved=1)
    # ... and a note that lay right in a numbered folder does not keep that folder there, once
    # everything else has moved out of it
    for folder, notes in waiting.items():
        files, moved, aside = job.numbered[folder]
        if files - moved - aside == len(notes):
            job.aside += [(now, LEFT_BEHIND) for now in notes]
            job.fate += [(now, ASIDE + '/' + now, LEFT_BEHIND) for now in notes]
            job.numbered[folder][2] += len(notes)
        else:
            job.fate += [(now, now, KEPT) for now in notes]
    for full, dest, shown in extra:
        if not os.path.lexists(long_path(os.path.join(addon, dest))):     # (it is there already: an earlier run)
            job.copies.append((full, dest))
            job.fate.append((shown, dest, COPIED))
    return job


def free_name(path):
    if not os.path.lexists(long_path(path)):
        return path
    n = 1
    while os.path.lexists(long_path('%s.%d' % (path, n))):
        n += 1
    return '%s.%d' % (path, n)


def prune(folder):
    """removes the empty folders below a folder (not the folder itself)"""
    for base, dirs, _files in os.walk(deep(folder), topdown=False):
        for name in dirs:
            try:
                os.rmdir(os.path.join(base, name))
            except OSError:
                pass


def finish(addon, pending, problems):
    """the second half of a move: from the stage to the place. pending: [(staged file, then, before)]"""
    for staged, then, before in pending:
        target = os.path.join(addon, then)
        if os.path.lexists(long_path(target)):
            # the file that lies there could not be moved away: back to where it came from
            back = os.path.join(addon, before)
            target = back if not os.path.lexists(long_path(back)) else free_name(os.path.join(addon, ASIDE, before))
            problems.append((before, u'место занято: %s' % then))
        try:
            os.makedirs(long_path(os.path.dirname(target)), exist_ok=True)
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
        if os.path.lexists(long_path(target)):
            continue        # (decided by place_content: only possible when a file could not leave)
        try:
            os.makedirs(long_path(os.path.dirname(target)), exist_ok=True)
            shutil.copyfile(long_path(source), long_path(target))
        except OSError as err:
            problems.append((dest, u'%s' % err))
    return problems


# ---- telling about it ------------------------------------------------------------------------
def addon_version(addon):
    """the version of the addon these scripts came with, as its Lua tells it ('' when it does not):
    a report that is sent on says which version wrote it"""
    try:
        with io.open(os.path.join(addon, 'lua', 'autorun', L.ADDON_DIRNAME + '.lua'), encoding='utf-8', errors='replace') as f:
            found = re.search(r'ZCGloves\.Version\s*=\s*"([^"\n]{1,40})"', f.read(4000))
    except (OSError, IOError):
        return u''
    return found.group(1) if found else u''


def verify(addon, real=()):
    """The materials and models folders of the addon as they are now, gone through once more -
    every folder below them: how many folders and files of which kind each of the two holds, the
    files that lie below the wrong one (a model below materials/, a material below models/), the
    numbered folders that still hold files, and how many files _not_used holds.
    Returns {'roots': {top: Seen}, 'wrong': [paths], 'numbered': {folder: files}, 'aside': files,
    'unread': [(folder, why)]}."""
    after = dict(roots=collections.OrderedDict(), wrong=[], numbered=collections.Counter(), aside=0, unread=[])
    for top in ROOTS:
        seen = Seen()
        for rel, _full in walk_files(os.path.join(addon, top), seen, top + '/'):
            rel = top + '/' + rel
            kind = P.kind_of(rel) or 'other'
            seen.kinds[kind] += 1
            if L.is_own_content(rel):
                continue
            if kind != 'other' and P.ROOT_OF[kind] != top:
                after['wrong'].append(rel)
            folder = numbered_folder(rel, real)
            if folder is not None:
                after['numbered'][folder] += 1
        after['roots'][top] = seen
        after['unread'] += seen.unread
    for top, _inside in beside(addon):
        count = sum(1 for _pair in walk_files(os.path.join(addon, top)))
        if count:
            after['numbered'][top] += count
    after['aside'] = sum(1 for _pair in walk_files(os.path.join(addon, ASIDE))) if os.path.isdir(os.path.join(addon, ASIDE)) else 0
    return after


def verify_lines(after):
    """what verify() found, for the screen and the report"""
    out = [u'Проверка после раскладки — папки materials и models аддона пройдены ещё раз, каждая подпапка:']
    seen = after['roots']['materials']
    kinds = seen.kinds
    out.append(u'  materials: папок %d, файлов %d — материалов .vmt %d, текстур .vtf %d, прочих %d; файлов моделей: %d'
               % (seen.folders, sum(kinds.values()), kinds['vmt'], kinds['vtf'], kinds['other'], kinds['mdl'] + kinds['part']))
    seen = after['roots']['models']
    kinds = seen.kinds
    out.append(u'  models: папок %d, файлов %d — моделей .mdl %d, файлов к ним (.vvd .vtx .phy .ani) %d, прочих %d; '
               u'материалов и текстур: %d'
               % (seen.folders, sum(kinds.values()), kinds['mdl'], kinds['part'], kinds['other'], kinds['vmt'] + kinds['vtf']))
    wrong = after['wrong']
    if wrong:
        out.append(u'  ВНИМАНИЕ: не в своей папке остались файлы — %d (%s%s): игра их там не видит.'
                   % (len(wrong), u', '.join(wrong[:3]), u' …' if len(wrong) > 3 else u''))
        out.append(u'  Почему они остались — в отчёте, «Все файлы, папка за папкой» и «Не использовано».')
    numbered = after['numbered']
    if numbered:
        names = sorted(numbered, key=P.natural)
        out.append(u'  в папках с номерами осталось файлов: %d (%s%s) — о них ничего не известно, см. отчёт'
                   % (sum(numbered.values()), u', '.join(u'%s — %d' % (name, numbered[name]) for name in names[:3]),
                      u' …' if len(names) > 3 else u''))
    else:
        out.append(u'  папок с номерами (materials1, models2 …) не осталось: всё из них разложено')
    out.append(u'  в папке %s (не пригодилось, ничего не удалено): файлов %d' % (ASIDE, after['aside']))
    out.append(u'  Подпапки внутри materials и models — так и должно быть: игра ищет файл по полному пути,')
    out.append(u'  а materials/models/… — это материалы моделей (по правилам игры они лежат в materials).')
    return out


def state_words(counts, game):
    """'нигде нет — 42, есть в самой игре — 8' for the states of names without a file
    (content_report.Check.states); game: was the game looked into?"""
    parts = []
    if counts.get('nowhere'):
        parts.append((u'нигде нет — %d' if game else u'нет ни в одной папке — %d') % counts['nowhere'])
    if counts.get('same'):
        parts.append(u'под этим именем лежит в другой папке — %d' % counts['same'])
    if counts.get('game'):
        parts.append(u'есть в самой игре — %d' % counts['game'])
    return u', '.join(parts)


def game_lines(game, found, asked):
    """what there is to tell about the game: was it found, what of it was looked through.
    game: a game_files.Game or None; found: game_files.Found or None (nothing was missing);
    asked: 'off' when the user did not want the game looked into"""
    if asked == 'off':
        return []
    if game is None:
        return [u'Игра на этом компьютере не найдена (Steam с Garry’s Mod нет, и аддон лежит не в папке addons игры).',
                u'  Какие из недостающих файлов есть в самой игре, здесь не проверить: это покажет zcg_content в игре.',
                u'  Чтобы проверялось и здесь: перетащите мышью папку игры (GarrysMod — ту, в которой лежит',
                u'  garrysmod) на sort_content.bat — или положите аддон в garrysmod/addons игры и запустите там.']
    out = [u'Игра на этом компьютере: %s' % game.root]
    if found is None:
        return out
    looked = found.looked
    parts = []
    for kinds, words in (((game_files.VPK,), u'архивов игры — %d'),
                         ((game_files.FOLDER,), u'папок в addons — %d'),
                         ((game_files.GMA,), u'аддонов .gma в папке игры — %d'),
                         ((game_files.WORKSHOP,), u'аддонов мастерской — %d'),
                         ((game_files.OTHER,), u'других игр Steam — %d')):
        count = sum(looked.get(kind, 0) for kind in kinds)
        if count:
            parts.append(words % count)
    out.append(u'  недостающие файлы искались и в ней: %s' % (u', '.join(parts) or u'в ней нет ни архивов, ни аддонов'))
    if found.skipped:
        out.append(u'  (в папке addons игры лежит ещё одна копия этого аддона — %s: её файлы не в счёт.'
                   % u', '.join(u'«%s»' % name for name in found.skipped[:3]))
        out.append(u'  В игре должна остаться одна копия аддона — эта.)')
    if found.unread:
        out.append(u'  не прочитано архивов: %d (%s%s) — что в них, не известно'
                   % (len(found.unread), os.path.basename(found.unread[0][0]), u' …' if len(found.unread) > 1 else u''))
    if found.cut:
        out.append(u'  поиск в игре остановлен: слишком долго — просмотрено не всё. Запустите ещё раз: второй раз диск отвечает быстрее.')
    return out


def summary(addon, names, brought, report, job, dry, problems, seen=None, check=None, after=None, game=None,
            found=None, asked=None):
    """the lines for the screen and for the head of the report.
    seen: what collect() went through; check: the close look at what is missing
    (content_report.Check); after: what verify() found once the files were moved; game, found,
    asked: see game_lines()"""
    name = os.path.basename(addon)
    named = names.named
    version = addon_version(addon)
    if check is None:
        check = content_report.Check(report, named)
    out = [u'Аддон: %s%s' % (addon, u'   (версия %s)' % version if version else u''),
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
    if seen is not None:
        # (the proof that no folder was passed over: how many were gone into, and how deep)
        kinds = seen.kinds
        out.append(u'Пройдены все папки и подпапки, до самой глубокой: папок — %d, файлов в них — %d' % (seen.folders, seen.files))
        if seen.depth:
            out.append(u'  самая глубокая — на %d-м уровне: %s/' % (seen.depth, seen.deepest))
        out.append(u'  моделей .mdl — %d, файлов к ним (.vvd .vtx .phy .ani) — %d, материалов .vmt — %d, текстур .vtf — %d, '
                   u'прочих — %d' % (kinds['mdl'], kinds['part'], kinds['vmt'], kinds['vtf'], kinds['other']))
        if kinds['own']:
            out.append(u'  (своих файлов аддона — перчаток — %d: они не в счёт и не трогаются)' % kinds['own'])
        if seen.unread:
            out.append(u'ВНИМАНИЕ: не удалось прочитать папок: %d — что в них лежит, не известно, и оно не разложено:' % len(seen.unread))
            for path, what in seen.unread[:10]:
                out.append(u'    %s: %s' % (path, what))
            if len(seen.unread) > 10:
                out.append(u'    ... и ещё %d' % (len(seen.unread) - 10))

    verb = u'Будет' if dry else u'Было'
    moved = len(job.moves) - job.lowered
    out.append(u'')
    if dry:
        out.append(u'ПРОБНЫЙ ЗАПУСК: ничего не перемещено. Вот что было бы сделано.')
    out.append(u'Уже лежит на своём месте: %d' % job.stay)
    if job.unknown:
        out.append(u'Оставлено в тех же папках (их никто не называет — ни Lua, ни модели: другого места у них нет; папки — в отчёте): %d'
                   % job.unknown)
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
    if after is not None:
        out.append(u'')
        out += verify_lines(after)

    out.append(u'')
    out += game_lines(game, found, asked)
    in_game = found is not None
    missing = len(report.missing_named) + len(report.missing_materials) + len(report.missing_textures)
    if missing:
        out.append(u'Не хватает файлов — в аддоне их нет. Каждое имя искалось и по точному пути, и просто по имени')
        out.append(u'файла — во всех папках и подпапках%s%s:'
                   % (u' (папок: %d)' % seen.folders if seen is not None and seen.folders else u'',
                      u', а потом в самой игре' if in_game else u''))
        out.append(u'    названных в Lua: %d из %d' % (len(report.missing_named), len(named)))
        if check.named:
            out.append(u'        из них: %s' % state_words(check.states(check.named), in_game))
        # (pack by pack: such files come with the content of that pack or of what it depends on)
        packs = content_report.by_pack(report.missing_named, names.pack) if names.by else []
        for label, wanted in packs[:10]:
            out.append(u'        %s — %d: %s' % (label or u'какой Lua называет — не известно', len(wanted),
                                                 content_report.folders_of(wanted)))
        if len(packs) > 10:
            out.append(u'        ... и ещё наборов: %d' % (len(packs) - 10))
        out.append(u'    материалов, которые ищут модели: %d из %d'
                   % (len(report.missing_materials), report.materials_wanted))
        # (a pack of models may bring hundreds that nothing uses: what they miss is not what the
        # clothes of the addon miss)
        for who, words in ((content_report.OURS, u'моделям, которые называет Lua аддона (их %d)'),
                           (content_report.ZCITY, u'моделям, которые называет сам Z-City (их %d)'),
                           (content_report.OTHERS, u'прочим моделям (их %d)')):
            rows = check.of(check.materials, who)
            if rows:
                out.append(u'        %s — %d: %s'
                           % (words % len(set(row.by for row in rows)), len(rows), state_words(check.states(rows), in_game)))
                if who == content_report.OTHERS:
                    # (which pack they came with: its folder says it)
                    out.append(u'            это модели из %s' % content_report.tops_of(set(row.by for row in rows)))
        out.append(u'    текстур, которые ищут материалы: %d из %d'
                   % (len(report.missing_textures), report.textures_wanted))
        for who, words in ((content_report.OURS, u'материалам одежды (их называет Lua или берёт названная модель)'),
                           (content_report.OTHERS, u'прочим материалам (на одежду не влияют)')):
            rows = check.of(check.textures, who)
            if rows:
                out.append(u'        %s — %d: %s' % (words, len(rows), state_words(check.states(rows), in_game)))
        if check.of(check.materials, content_report.OTHERS):
            out.append(u'    («прочие модели» — те, которых не называет ни Lua аддона, ни сам Z-City: набор приносит их сотнями,')
            out.append(u'    а в игре они никому не нужны. Список — в отчёте, отдельно.)')
        ours = [row for row in check.named + check.materials + check.textures if row.who != content_report.OTHERS]
        if in_game:
            left = [row for row in ours if not row.game]
            out.append(u'  ИТОГ для одежды аддона (прочие модели не в счёт):')
            out.append(u'    есть в самой игре — %d%s'
                       % (len(ours) - len(left), u': ' + content_report.game_kinds(check.game_paths(ours)) if len(ours) > len(left) else u''))
            if left:
                out.append(u'    нет ни в аддоне, ни в игре — %d: из Lua — %d, материалов моделей — %d, текстур — %d'
                           % (len(left), sum(1 for row in check.named if not row.game),
                              sum(1 for row in check.materials if row.who != content_report.OTHERS and not row.game),
                              sum(1 for row in check.textures if row.who != content_report.OTHERS and not row.game)))
                # (a game that was not looked through to the end: "nowhere" is not sure then)
                if found.cut:
                    out.append(u'    (но игра просмотрена не вся — поиск остановлен, см. выше: часть этих файлов может лежать там, куда он не дошёл)')
                elif found.unread:
                    out.append(u'    (но не прочитано архивов игры: %d — часть этих файлов может лежать в них)' % len(found.unread))
            else:
                out.append(u'    нет ни в аддоне, ни в игре — 0: всё, чего нет в аддоне, есть в самой игре')
            out.append(u'  То, что есть в самой игре, в аддон класть не нужно. (Если это аддон мастерской, он должен быть')
            out.append(u'  включён — и стоять на сервере и у игроков, как и сам Z-City.)')
            if left:
                out.append(u'  Остальное — файлы других аддонов: какой Lua их называет, видно выше и в отчёте. Пока их нет,')
                out.append(u'  в игре на их месте чёрно-фиолетовые клетки или ERROR.')
        else:
            out.append(u'  Этих файлов нет ни в одной папке аддона. Часть из них — файлы самой игры и Z-City (глаза, рот,')
            out.append(u'  руки и перчатки моделей): в аддоне их и не должно быть. Что из этого есть в игре, покажет')
            out.append(u'  команда zcg_content в консоли игры. Остальное — файлы других аддонов: какой Lua их называет,')
            out.append(u'  видно выше и в отчёте.')
        out.append(u'  Если такой аддон у вас есть папкой — положите его materials и models в папку materials аддона')
        out.append(u'  (как есть, можно под номерами: materials9, models5 …) и запустите ещё раз.')
        if report.missing_named and len(brought) == 1:
            # (a source is copied from, not moved: what an earlier version did not take is still there)
            out.append(u'  Если папки с контентом вы раньше перетаскивали на sort_content.bat, перетащите их ещё раз:')
            out.append(u'  файл, имени которого прежняя версия не знала, она не взяла, и он остался в той папке.')
    else:
        out.append(u'Все названные файлы на месте.')
    out += content_report.version_lines(content_report.versions_found(report, names.instead, names.spare, names.only),
                                        names.switch, names.held)
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


FATE_WORDS = {
    IN_PLACE: u'лежит на своём месте',
    KEPT: u'оставлено как есть: про эти файлы ничего не известно',
    LEFT: u'не взято',
}
NAMES_WIDTH = 150       # how long a line of file names gets in the list of all files


def fate_lines(job, dry=False):
    """Every file that was gone through, folder by folder: where it lay and where it lies now
    (Job.fate) - each folder with the names of its files, so that what a folder deep down held
    and what became of it can be looked up."""
    groups = collections.OrderedDict()
    def order(entry):
        folder, name = posixpath.split(entry[0])
        return P.by_folders(folder), posixpath.dirname(entry[1] or u''), entry[2], P.natural(name.lower())

    for now, then, how in sorted(job.fate, key=order):
        folder, name = posixpath.split(now)
        dest = posixpath.dirname(then) if then else None
        if how in (IN_PLACE, KEPT):
            dest = None
        groups.setdefault((folder, dest, how), []).append(name)
    folders = len(set(folder for folder, _dest, _how in groups))
    out = [u'Все файлы, папка за папкой: где лежал  ->  где %s — папок: %d, файлов: %d'
           % (u'будет лежать' if dry else u'лежит теперь', folders, len(job.fate))]
    for (folder, dest, how), files in groups.items():
        if how == MOVED:
            head = u'%s/  ->  %s/' % (folder, dest)
        elif how == COPIED:
            head = u'%s/  ->  %s/    (копия)' % (folder, dest)
        elif how in FATE_WORDS:
            head = u'%s/    — %s' % (folder, FATE_WORDS[how])
        elif dest is not None:
            head = u'%s/  ->  %s/    (%s)' % (folder, dest, content_report.why(how))
        else:
            head = u'%s/    — не взято: %s' % (folder, content_report.why(how))
        out.append(u'    %s    файлов: %d' % (head, len(files)))
        line = u''
        for name in files:
            if line and len(line) + len(name) + 2 > NAMES_WIDTH:
                out.append(u'        ' + line)
                line = u''
            line += (u', ' if line else u'') + name
        if line:
            out.append(u'        ' + line)
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
        out.append(u'    %s/    папок: %d, файлов: %d, на места: %d, в %s: %d, осталось: %d'
                   % (folder, len(job.inside.get(folder, ())), files, moved, ASIDE, aside, files - moved - aside))
    return out


NO_GAME = ('-', 'no', 'none', 'off', '0')
GAME_SECONDS = 120      # how long the game is looked through before the search is given up


def game_seconds():
    """... or as long as the variable ZCG_GAME_SECONDS says (a slow disk with a thousand addons)"""
    try:
        return float(os.environ.get('ZCG_GAME_SECONDS') or GAME_SECONDS)
    except ValueError:
        return GAME_SECONDS


def game_choice(given, off, addon):
    """The game to look into for the files the addon does not have: ('off', None) when that is
    not wanted (--no-game; --game or the variable ZCG_GAME set to "-"), ('given', Game) for a
    folder that was named, else ('auto', the game found on this computer or None)."""
    value = given if given is not None else os.environ.get('ZCG_GAME')
    if off or (value is not None and value.strip().lower() in NO_GAME):
        return 'off', None
    if value:
        game = game_files.find(given=value)
        if game is None:
            raise UserError(u'Это не папка игры Garry’s Mod (в ней нет папки garrysmod): %s\n'
                            u'Укажите папку GarrysMod — ту, в которой лежит garrysmod: --game "D:\\...\\GarrysMod"' % value)
        return 'given', game
    return 'auto', game_files.find(addon)


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            # (a console shows any text; a file or a pipe gets UTF-8 instead of the code page)
            if stream.isatty():
                stream.reconfigure(errors='replace')
            else:
                stream.reconfigure(encoding='utf-8', errors='replace')

    parser = argparse.ArgumentParser(description='Sorts the materials and models of an installed addon by name.')
    parser.add_argument('sources', nargs='*', help='folders or .zip archives with more content to take in '
                                                   '(the folder of the game itself is taken as --game)')
    parser.add_argument('--addon', help='the addon folder (default: the one this script lies in)')
    parser.add_argument('--lua', action='append', default=[], help='another folder with Lua that names files')
    parser.add_argument('--names-list', help='the list of the names found by running the Lua '
                                             '(default: %s beside this script)' % list_content.RUN_LIST)
    parser.add_argument('--dry-run', action='store_true', help='only tell what would be done')
    parser.add_argument('--game', help='the folder of the game (GarrysMod, the one that holds garrysmod): the files '
                                       'the addon does not have are looked for in it. Default: the game the addon '
                                       'lies in, else the one Steam has; "-" to leave the game alone')
    parser.add_argument('--no-game', action='store_true', help='do not look into the game')
    parser.add_argument('--no-switch', action='store_true',
                        help='keep the version of Appearance Mod the addon has, whatever the content turns out to be '
                             '(by default the Lua of the version the content belongs to is put in place)')
    parser.add_argument('--use-version', metavar='TITLE',
                        help='put the Lua of this version in place, whatever the content says: its title or a part '
                             'of it, e.g. --use-version legacy')
    args = parser.parse_args(argv)
    return run(args)


def run(args, switched=None):
    """switched: the title of the version this very run has put in place before it started over"""
    temp = tempfile.mkdtemp(prefix='zcg_sort_')
    try:
        addon = find_addon(args.addon)
        versions = versions_of(addon)
        if args.names_list is None and versions and os.path.isfile(os.path.join(addon, 'sort_content', list_content.RUN_LIST)):
            # (the list that is switched together with the Lua is the one in the addon)
            args.names_list = os.path.join(addon, 'sort_content', list_content.RUN_LIST)
        if args.use_version and switched is None:
            asked_title = version_asked(versions, args.use_version)
            if args.dry_run:
                say(u'(--dry-run: Lua версии «%s» на место не кладётся)' % asked_title)
            else:
                changed, _same = switch_version(addon, versions[asked_title])
                say(u'Версия по просьбе (--use-version): «%s». %s' % (asked_title, (
                    u'Заменено файлов: %d.' % changed) if changed else u'Она и стояла: файлы те же.'))
            switched = asked_title
        # The folder of the game itself among what was handed over is not content to take in: it
        # is the game to look into (the way to name it without typing: drop it onto the .bat).
        dropped = [source for source in args.sources if os.path.isdir(source) and game_files.sure_game(source)]
        if dropped:
            args.sources = [source for source in args.sources if source not in dropped]
            if args.game is None:
                args.game = game_files.sure_game(dropped[0])
            say(u'Папка «%s» — это сама игра: из неё ничего не берётся, в ней ищутся недостающие файлы.' % dropped[0])
        asked, game = game_choice(args.game, args.no_game, addon)
        if not args.dry_run:
            resumed = resume(addon)
            if resumed:
                say(u'Прошлый запуск был прерван: файлов доведено до места: %d' % resumed)

        say(u'Читаю Lua аддона ...')
        names = names_of([os.path.join(addon, 'lua')] + args.lua, args.names_list)
        if switched is None and not args.no_switch and not args.dry_run:
            names.switch = set(title for title in names.instead if title in versions)
        elif args.no_switch or args.use_version:
            names.held = set(title for title in names.instead if title in versions)
        named = names.named
        say(u'Читаю файлы контента: каждую папку и подпапку ...')
        stock = list_content.stock_names()
        real = real_folders(set(named) | set(names.spare) | stock)
        seen = Seen(L.is_own_content)
        items, lower_case, extra, brought, along = collect(addon, args.sources, temp, real, seen)
        say(u'Ищу каждому файлу место (папок: %d, файлов: %d) ...' % (seen.folders, len(items)))
        report = P.place(items, named, L.is_own_content, set(names.spare))
        job = plan(addon, items, lower_case, extra, report, along, real)

        problems = []
        if not args.dry_run and (job.moves or job.aside or job.copies):
            say(u'Перекладываю ...')
            problems = apply(addon, job)
        after = None
        if not args.dry_run:
            say(u'Проверяю: прохожу папки аддона ещё раз ...')
            after = verify(addon, real)

        # What has no file: looked for once more - by its file name alone, in every folder - and,
        # where the game is at hand, in the game.
        wanted = set(report.missing_named)
        wanted.update(path for _model, _name, group in report.missing_materials for path in group)
        wanted.update(texture for _material, _key, texture in report.missing_textures)
        found = None
        if game is not None and wanted:
            say(u'Ищу недостающие файлы в самой игре (%s) ...' % game.root)
            found = game_files.look(game, wanted, skip=[addon], own_marker='lua/autorun/%s.lua' % L.ADDON_DIRNAME,
                                    seconds=game_seconds())
        check = content_report.Check(report, named, stock, found,
                                     lambda item: (ASIDE + '/' + item.inner) if getattr(item, 'in_addon', False)
                                     else u'%s' % (item,))

        head = summary(addon, names, brought, report, job, args.dry_run, problems, seen, check, after, game, found, asked)
        say()
        for line in head:
            say(line)

        reasons = collections.Counter(content_report.why(reason) for _now, reason in job.aside)
        more = list(head)
        if job.numbered:
            more += [u'', u'Папки-копии materials и models — по папкам (каждая пройдена целиком; «папок» — сколько '
                          u'в ней папок с файлами, на любой глубине):'] + numbered_list(job)
        if job.aside:
            more += [u'', u'Убрано в %s (причины):' % ASIDE] + [u'    %s — файлов: %d' % pair for pair in sorted(reasons.items())]
        tail = []
        if after is not None and after['wrong']:
            tail += [u'', u'Файлы, которые остались не в своей папке — %d' % len(after['wrong'])]
            tail += [u'    ' + path for path in after['wrong']]
        if found is not None and found.unread:
            tail += [u'', u'Архивы игры, которые не удалось прочитать — %d' % len(found.unread)]
            tail += [u'    %s: %s' % pair for pair in found.unread[:200]]
        tail += [u''] + fate_lines(job, args.dry_run)
        listing = os.path.join(addon, REPORT)
        content_report.write(listing, brought, report, named, 'sort_content.py', more, names.who if names.by else None,
                             names.spare, check, tail)
        say()
        say(u'Подробный отчёт (в нём каждая папка и каждый файл): %s' % listing)
        if not args.dry_run and not problems:
            other = [entry for entry in content_report.versions_found(report, names.instead, names.spare, names.only)
                     if content_report.of_the_other_version(entry)]
            if other and other[0]['title'] in names.switch:
                # The Lua of that version lies in the addon: it is put in place, and the whole run
                # starts over with it - its names are other names, its files have other places.
                title = other[0]['title']
                changed, _same = switch_version(addon, versions[title])
                say()
                say(u'=' * 78)
                say(u'Контент — от «%s», а в аддоне стоял Lua «%s».' % (title, other[0]['instead']))
                say(u'Аддон переключён на «%s»: заменено файлов: %d (из sort_content/versions; файлы «%s» лежат там же,'
                    % (title, changed, other[0]['instead']))
                say(u'вернуть их: sort_content.bat --use-version \"%s\"). Скачивать другой архив не нужно.' % other[0]['instead'])
                say(u'Теперь всё проверяется заново — уже с «%s». Итог — тот, что ниже.' % title)
                say(u'=' * 78)
                say()
                args.sources = []       # (they are in the addon by now)
                shutil.rmtree(temp, ignore_errors=True)
                return run(args, switched=title)
            if other and other[0]['title'] in names.held:
                say(u'Файлы разложены. Но контент — от «%s», а в аддоне стоит Lua «%s» (см. «ВНИМАНИЕ» выше) — так вы просили.'
                    % (other[0]['title'], other[0]['instead']))
                say(u'Чтобы аддон переключился на «%s», запустите sort_content.bat без параметров.' % other[0]['title'])
            elif other:
                # (the last line is the one that is read: the content is that of the other version)
                archive = L.VERSION_ZIPS.get(other[0]['title'])
                say(u'Файлы разложены. Но контент — от «%s», а эта сборка — с «%s» (см. «ВНИМАНИЕ» выше):'
                    % (other[0]['title'], other[0]['instead']))
                say(u'возьмите %s, скопируйте его папку поверх этой и запустите sort_content.bat ещё раз.'
                    % (u'архив %s' % archive if archive else u'сборку с «%s»' % other[0]['title']))
            else:
                if switched and not args.use_version:
                    say(u'Аддон переключён на «%s» — по контенту (см. выше).' % switched)
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
