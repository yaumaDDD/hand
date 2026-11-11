# -*- coding: utf-8 -*-
"""Content of other addons, put where the game looks for it.  (used by build_addon.py)

Lua that adds clothes names its files by their path in the game: "models/gate/epl" is the
material materials/models/gate/epl.vmt, and the game finds nothing that is not exactly there.
The files reach the repository in whatever folders somebody packed them in - a level short
(materials/gate/epl.vmt), from inside the materials folder (gate/epl.vmt), in folders of their
own ("material 1/epl.vmt") - so the build does not trust the folders. It follows the names:

    Lua           names materials (.vmt) and models (.mdl)
    a model       names its materials: each of its material folders x each material name
    a material    names its textures (.vtf); a "patch" material also the material it includes

and looks every name up, by file name, among everything supplied. A file name alone is not
enough: clothes for men and for women, for one body and for the next, are full of files called
the same (sheet_01.vmt, facemap.vmt, male_01.mdl). What the name of a file is worth depends on
how the path it was packed under stands to the wanted one (relation()):

    same      the file lies there.
    shift     the wanted path with folders put in or left out at one spot
              (materials/gate/x - materials/models/gate/x): that file, a level off.
    sibling   the same tree, another folder (.../male/group01/x - .../female/group01/x):
              another file. Never taken.
    foreign   folders that say nothing ("material 1/x"): only the file name is left.

A wanted path gets, in this order:
    1. the file that lies there;
    2. a file that is surely meant: one whose path is the wanted one, shifted, and agrees with
       it in the folder too; a texture packed next to the material that names it; a file packed
       next to the one that asks for it; a file that says so itself - a model compiled for that
       path, a material whose own texture lies beside it and is named in that folder;
    3. a file that fits by its name alone - when it is the only one, fits no other name, and
       the folder it lies in did not go somewhere else. The clear ones are placed first: what
       they tell about their folders decides more of the rest.

A file that lies in a folder somebody names files in is at home there: it is moved for a
shifted path only, never for a name it merely shares with a file that is missing.

A file nobody names follows what is known about its folder: where the files next to it went
(a folder that kept its name on the way - materials/gate -> materials/models/gate - took
everything below it along), or what a material and a texture it names, lying together, say
about the folder they lie in. Without any of that it stays where it was packed; packed outside
of a materials / models folder it is left out.

What cannot be decided is reported and never guessed:
    * a file that fits several names by its file name alone,
    * several different files that fit one name equally,
    * a name with no file (it may be a part of the game or of Z-City),
    * a file that no name and no folder claims.

Materials and textures are put below materials/ only, models below models/; a file of the
addon itself is never replaced; of two files for one place the later source has it.

tools/test_content.py tries all of this on made-up files, also on random ones packed in the
ways people pack them.
"""
import collections
import os
import posixpath
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vmt  # noqa: E402

MODEL_PARTS = ('.vvd', '.vtx', '.phy', '.ani')

# material parameters that name a texture
TEXTURE_KEYS = frozenset('$' + key for key in '''
    basetexture basetexture2 bumpmap bumpmap2 normalmap normalmap2 detail detail2 envmapmask
    phongexponenttexture selfillummask selfillumtexture lightwarptexture phongwarptexture
    fresnelrangestexture ambientoccltexture ambientocclusiontexture blendmodulatetexture iris
    corneatexture texture2 tintmasktexture masks1 masks2 sheenmap sheenmapmask
    emissiveblendtexture emissiveblendbasetexture emissiveblendflowtexture fleshinteriortexture
    fleshnormaltexture fleshbordertexture1d fleshsubsurfacetexture fleshcubetexture
    displacementmap paintsplatnormalmap hdrbasetexture hdrcompressedtexture dudvmap
    refracttinttexture flowmap flow_noise_texture decaltexture compress stretch bumpcompress
    bumpstretch'''.split())
# values of such parameters that are not files
NOT_A_FILE = re.compile(r'^(env_cubemap|_rt_.*|_.*|engine/.*|dev/.*|debug/.*|vgui/white.*)$')


# A place in the addon is made of plain folder names. The names come out of files somebody else
# wrote ("$basetexture" "../../x"), so everything that could lead out of the addon folder or that
# Windows refuses as a file name is turned down.
_PART = re.compile(r'^(?!\.+$)[^\x00-\x1f<>:"|?*\\/]*[^\x00-\x1f<>:"|?*\\/. ]$')


# the game reads materials and textures out of materials/ only, models out of models/
ROOT_OF = {'vmt': 'materials', 'vtf': 'materials', 'mdl': 'models', 'part': 'models'}


def is_place(path, kind=None):
    """a path in the addon that a file (of that kind) can be put at"""
    parts = path.split('/')
    if len(parts) < 2 or not all(_PART.match(p) for p in parts):
        return False
    return parts[0] == ROOT_OF[kind] if kind else parts[0] in ('materials', 'models')


def kind_of(name):
    """'vmt', 'vtf', 'mdl', 'part' (another file of a model) or None: not handled here"""
    name = name.lower()
    if name.endswith('.vmt'):
        return 'vmt'
    if name.endswith('.vtf'):
        return 'vtf'
    if name.endswith('.mdl'):
        return 'mdl'
    if name.endswith(MODEL_PARTS):
        return 'part'
    return None


def clean(value):
    """a path the way the game compares it: lower case, forward slashes, none at the ends"""
    return re.sub(r'/+', '/', value.replace('\\', '/').strip().lower()).strip('/')


def texture_path(value):
    value = clean(value)
    if value.endswith('.vtf'):
        value = value[:-4]
    if value.startswith('materials/'):
        value = value[len('materials/'):]
    return value


def common_suffix(a, b):
    """how many of the last parts of two paths are the same"""
    n = 0
    while n < len(a) and n < len(b) and a[-1 - n] == b[-1 - n]:
        n += 1
    return n


class Material(object):
    """what a .vmt names"""

    def __init__(self):
        self.textures = []    # (parameter, texture without materials/ and .vtf, True when surely a texture)
        self.includes = []    # materials/....vmt
        self.base = None      # its $basetexture


def _pairs(items):
    for key, value in items:
        if isinstance(value, str):
            yield key.lower(), value
        else:
            for pair in _pairs(value):
                yield pair


_LOOSE_LINE = re.compile(r'^\s*"?([$%]?[\w.]+)"?[ \t]+"?([^"\n]*?)"?\s*$')


def read_material_text(text):
    """[(parameter in lower case, value)] of the text of a .vmt"""
    if text.startswith('\xef\xbb\xbf'):     # a UTF-8 mark, read as latin-1
        text = text[3:]
    # "$bumpmap" "x" [$X360] - the condition would be read as the next parameter
    text = re.sub(r'\[\s*!?\$\w+[^\]\n]*\]', ' ', text)
    try:
        _shader, items = vmt.parse(text)
        return list(_pairs(items))
    except (ValueError, RecursionError):
        pass
    # not well-formed (a quote that is never closed ...): the game still reads such a file line
    # by line, so do the same
    found = []
    for line in text.replace('\r', '').split('\n'):
        match = _LOOSE_LINE.match(line.split('//')[0])
        if match:
            found.append((match.group(1).lower(), match.group(2)))
    return found


def read_material(path):
    with open(path, 'r', encoding='latin-1') as f:
        found = read_material_text(f.read())
    out = Material()
    for key, value in found:
        if key == 'include':
            name = clean(value)
            if not name:
                continue
            if not name.startswith('materials/'):
                name = 'materials/' + name
            out.includes.append(name if name.endswith('.vmt') else name + '.vmt')
            continue
        if not key.startswith('$'):
            continue
        name = texture_path(value)
        if not name or NOT_A_FILE.match(name) or not re.match(r'^[\w\-./!+() ]*[a-z_][\w\-./!+() ]*$', name):
            continue
        if key in TEXTURE_KEYS:
            out.textures.append((key, name, True))
            if key == '$basetexture' and out.base is None:
                out.base = name
        elif '/' in name and ' ' not in name:
            out.textures.append((key, name, False))     # $envmap and whatever this script does not know
    return out


def _cstr(buf, off):
    if not 0 <= off < len(buf):
        raise ValueError('a name lies outside of the file')
    return buf[off:buf.index(b'\x00', off)].decode('latin-1')


def read_model(path):
    """(material folders, material names) of a .mdl, cleaned; ValueError when it cannot be read"""
    with open(path, 'rb') as f:
        b = f.read()
    if len(b) < 408 or b[:4] != b'IDST':
        raise ValueError('not a studio model')
    try:
        count, index, cdcount, cdindex = struct.unpack_from('<4i', b, 204)
        if not (0 <= count <= 4096 and 0 <= cdcount <= 256):
            raise ValueError('broken header')
        names = []
        for i in range(count):
            off = index + i * 64
            names.append(clean(_cstr(b, off + struct.unpack_from('<i', b, off)[0])))
        folders = [clean(_cstr(b, struct.unpack_from('<i', b, cdindex + i * 4)[0])) for i in range(cdcount)]
    except (struct.error, IndexError) as err:
        raise ValueError(str(err))
    return folders, [name[:-4] if name.endswith('.vmt') else name for name in names]


def read_model_name(path):
    """the path a model was compiled for ("slav/f/female_01.mdl" for models/slav/f/female_01.mdl)"""
    with open(path, 'rb') as f:
        head = f.read(76)
    if len(head) < 76 or head[:4] != b'IDST':
        return None
    name = clean(head[12:76].split(b'\x00')[0].decode('latin-1'))
    if name.startswith('models/'):
        name = name[len('models/'):]
    return name if name.endswith('.mdl') else None


class Item(object):
    """a supplied file"""

    def __init__(self, source, inner, path, default, order):
        self.source = source      # the archive or folder it came in
        self.inner = inner        # its path there, as packed
        self.path = path          # the file on the disk
        self.default = default    # where its folders alone put it (zcg_layout.dropin_destination) or None
        self.order = order        # of two that fit equally the later source wins
        self.parts = [p for p in clean(inner).split('/') if p]
        self.name = self.parts[-1]
        self.folder = (source, '/'.join(self.parts[:-1]))
        self.kind = kind_of(self.name)
        self.dests = []           # where it goes
        self.how = []             # for each of them: 'place' as packed, 'name' found by name, 'folder' went with its folder
        self.material = None
        self.model_name = None    # a model: the path it was compiled for, without models/
        self.replaced = False     # a later source brought a file for the same place: that one is used
        self.crowded = None       # the place it belongs to, when another file has it

    def same_as(self, other):
        if os.path.getsize(self.path) != os.path.getsize(other.path):
            return False
        with open(self.path, 'rb') as a, open(other.path, 'rb') as b:
            return a.read() == b.read()

    def __repr__(self):
        return '%s: %s' % (self.source, self.inner)


class Target(object):
    """a name that wants a file"""

    def __init__(self, path, near=(), group=None, sure=True, asked=None):
        self.path = path
        self.near = set(near)     # folders of the files that name it
        self.group = group        # a model looks for a material in each of its folders: any one will do
        self.sure = sure
        self.asked = asked        # the file that names it, None for Lua


# The remarks of a report and the reasons why a file was left out, in plain English. A report in
# another language (tools/content_report.py) is made from the same pieces.
NOTES = {
    'version': '%s: another version is in %s, the one from %s is used',
    'equal': '%s: %s and %s fit equally, the first one is used',
    'several names': '%s fits %d names by its file name alone and is not used: pack it with its folders',
    'several files': '%s: %d different files have this name and nothing says which one is meant; none is used',
    'unreadable': '%s cannot be read: %s',
    'no materials': '%s: its materials are not followed (%s)',
}
REPLACED = 'a later source has this file'
OWN_FILE = 'the file of this addon is kept'
NAMESAKES = 'not told from its namesakes, see the notes'
UNNAMED = 'nothing names it'
PLACE_TAKEN = 'its place is taken by another file'


class Note(str):
    """a remark: its English text, and what it is made of (kind, args)"""

    def __new__(cls, kind, *args):
        self = str.__new__(cls, NOTES[kind] % args)
        self.kind, self.args = kind, args
        return self


class Report(object):
    def __init__(self):
        self.placed = []          # (path in the addon, Item)
        self.left_out = []        # (Item, why)
        self.notes = []
        self.moves = collections.Counter()   # (source, folder as packed, folder in the addon) -> files
        self.missing_named = []       # paths the Lua names
        self.missing_materials = []   # (model in the addon, material name, the paths it is looked for at)
        self.missing_textures = []    # (material in the addon, parameter, texture path)
        self.models = 0               # models whose materials were followed
        self.materials_wanted = 0     # ... and how many materials they name
        self.textures_wanted = 0      # textures named by the placed materials


def relation(path, wanted):
    """How the path of a supplied file stands to a wanted path with the same file name (both as
    lists of parts). Returns (kind, how many of the last parts are the same), kind being
        'same'
        'shift'    the wanted path with folders put in or left out at one spot:
                   materials/gate/x -> materials/models/gate/x; a level too few or too many
        'sibling'  the same tree, another folder: .../male/group01/x and .../female/group01/x.
                   That is another file, however alike the names are
        'foreign'  folders that have nothing to do with the wanted ones ("material 1/x"):
                   the path says nothing, only the file name is left"""
    same = common_suffix(path, wanted)
    if same == len(path) == len(wanted):
        return 'same', same
    ours, theirs = path[:len(path) - same], wanted[:len(wanted) - same]
    lead = 0
    while lead < len(ours) and lead < len(theirs) and ours[lead] == theirs[lead]:
        lead += 1
    ours, theirs = ours[lead:], theirs[lead:]
    if not ours or not theirs:
        return 'shift', same
    root = 2 if wanted[:2] == ['materials', 'models'] else 1
    if lead > root or any(part in theirs for part in ours):
        return 'sibling', same
    return 'foreign', same


def place(items, named, own):
    """Decides where every supplied file goes.
    items: Item list; named: game paths the Lua names; own(path): the addon has that file itself.
    Returns a Report; nothing is copied here."""
    items = sorted((i for i in items if i.kind), key=lambda i: (i.order, i.inner))
    report = Report()
    taken = {}
    by_name = collections.defaultdict(list)
    in_folder = collections.defaultdict(set)
    for item in items:
        by_name[item.name].append(item)
        in_folder[item.folder].add(item.name)
        # a model below materials/ and the like: packed where the game never looks, so no place
        if item.default is not None and not is_place(item.default, item.kind):
            item.default = None

    def free(path):
        return path not in taken and not own(path)

    def settle(item, dest, how):
        if taken.get(dest) is item:
            return True
        if not is_place(dest, item.kind) or not free(dest):
            return False
        taken[dest] = item
        item.dests.append(dest)
        item.how.append(how)
        return True

    # where the folders alone put a file; of two files with one place the later source has it,
    # and the earlier one is out of the game: it is not looked at for any other name either
    at = {}
    for item in items:
        if item.default is None:
            continue
        earlier = at.get(item.default)
        if earlier is not None:
            earlier.replaced = True
            if not earlier.same_as(item):
                report.notes.append(Note('version', item.default, earlier.source, item.source))
        at[item.default] = item
    for name in list(by_name):
        by_name[name] = [item for item in by_name[name] if not item.replaced]

    def path_of(item):
        return item.default.split('/') if item.default else item.parts

    # Folders that somebody names a file in. A file lying in one of them is at home: it is moved
    # only when its path is a shifted wanted one, never because its name alone fits elsewhere.
    known = set()

    def at_home(item):
        return item.default is not None and posixpath.dirname(item.default) in known

    def satisfied(target):
        if target.group is not None:
            return any(not free(path) for path in target.group)
        return not free(target.path)

    # ---- where the folders went -------------------------------------------------------------
    votes = collections.defaultdict(collections.Counter)
    loose_votes = collections.defaultdict(collections.Counter)
    hints = collections.defaultdict(collections.Counter)     # filled below, from the materials
    counted = set()

    def vote(item, dest):
        src, dst = item.parts[:-1], dest.split('/')[:-1]
        # The folder of the file went to the folder of the place. A folder above that kept its
        # name went along: .../gate/sub -> materials/models/gate/sub says where .../gate went.
        same = common_suffix(src, dst)
        for up in range(0, max(1, same)):
            folder, there = '/'.join(src[:len(src) - up]), '/'.join(dst[:len(dst) - up])
            votes[(item.source, folder)][there] += 1
            if folder:
                # an upload cut into several archives has the same folder in each of them (the
                # top of an archive is the top of that archive only)
                votes[(None, folder)][there] += 1
        # The folder that one lies in says less: "gate" was packed without materials/models in
        # front, and so may be what lies next to it. That is only asked for a file that has no
        # place of its own, and only believed for a folder somebody names files in.
        if 1 <= same < len(dst) and same <= len(src):
            folder, there = '/'.join(src[:len(src) - same]), '/'.join(dst[:len(dst) - same])
            loose_votes[(item.source, folder)][there] += 1

    def count_votes(kind):
        for item in items:
            if item.kind != kind or not item.dests or id(item) in counted:
                continue
            counted.add(id(item))
            vote(item, item.dests[0])

    def with_folder(item, share):
        """the place of a file in the folder that its own folder (or the nearest one above that
        says anything) went to, when more than `share` of that folder went there"""
        source, folder = item.folder
        parts = folder.split('/') if folder else []
        root = ROOT_OF[item.kind]
        for cut in range(len(parts), -1, -1):
            # a folder may hold models and materials at once: each kind follows its own.
            # Asked in this order: the files of the folder that have a place; a material and its
            # texture lying there; the same folder in the other sources; the folder above
            here = '/'.join(parts[:cut])
            for table, origin in ((votes, source), (hints, source), (votes, None), (loose_votes, source)):
                counter = [(count, dest) for dest, count in table.get((origin, here), {}).items()
                           if dest.split('/', 1)[0] == root]
                if counter:
                    break
            if not counter:
                continue
            count, best = max(counter)
            if count <= share * sum(n for n, _dest in counter):
                return None
            there = '/'.join([best] + parts[cut:])
            if table is loose_votes and (item.default is not None or there not in known):
                return None
            if relation(path_of(item), there.split('/') + [item.name])[0] == 'sibling':
                return None
            return there + '/' + item.name
        return None

    undecided = {}

    def resolve(kind, targets, proof=None, home=None, proof_is_sure=False):
        """gives the wanted paths their files.
        proof(item, target): the file itself says that it is the wanted one - for sure (a model
        knows the path it was compiled for) or as a hint (a material uses a texture from there);
        home(item): the place a file claims for itself, whatever is wanted"""
        # 1. the file that lies there already
        for target in targets:
            item = at.get(target.path)
            if item is not None and item.kind == kind and not satisfied(target):
                settle(item, target.path, 'place')

        # 2. a file whose path is the wanted one, shifted; a texture that lies with the material
        #    that names it; a file that says itself where it belongs
        sure, by_name_only = [], []
        for target in targets:
            if satisfied(target):
                continue
            parts = target.path.split('/')
            for item in by_name.get(parts[-1], ()):
                if item.kind != kind or item.dests:
                    continue
                how, same = relation(path_of(item), parts)
                near = item.folder in target.near
                says = bool(proof and proof(item, target))
                claimed = home(item) if home else None
                fit = (-same, -(near + says + (claimed == target.path)), -item.order, target.path, item.inner,
                       target, item)
                if kind == 'vtf' and near:
                    sure.append(fit)
                elif how == 'sibling':
                    continue
                elif how == 'shift' and same >= 2:
                    sure.append(fit)
                elif at_home(item):
                    continue
                elif claimed not in (None, target.path):
                    continue     # it belongs elsewhere and says so
                elif near or (says and proof_is_sure) or claimed == target.path:
                    sure.append(fit)
                elif not says and same < 2 and target.group and target.path != target.group[0]:
                    continue     # of the folders a model looks into only the first one
                else:
                    by_name_only.append(fit)
        sure.sort(key=lambda fit: fit[:5])
        rivals = collections.defaultdict(list)
        for fit in sure:
            rivals[id(fit[5])].append(fit)
        for fit in sure:
            target, item = fit[5], fit[6]
            if item.dests or satisfied(target):
                continue
            for other in rivals[id(target)]:
                if other[6] is not item and other[:2] == fit[:2] and not other[6].dests \
                        and not other[6].same_as(item):
                    report.notes.append(Note('equal', target.path, item, other[6]))
                    break
            settle(item, target.path, 'name')
        count_votes(kind)

        # 3. the file name fits, and maybe a hint. Good enough when nothing speaks against it:
        #    one file, one wanted path, and the folder the file lies in did not go somewhere
        #    else as a whole (a file is not pulled out of its folder for a guess).
        #    Of several the one wins that has more folders in common with the wanted path, then
        #    the one with a hint, then the one whose folder went there - so the clear ones are
        #    placed first and the rest is looked at again, knowing where they went.
        while True:
            wanted_by, fits_for, rank = collections.defaultdict(list), collections.defaultdict(list), {}
            for fit in by_name_only:
                target, item = fit[5], fit[6]
                if item.dests or satisfied(target):
                    continue
                there = with_folder(item, 0.8)
                if there is not None and there != target.path:
                    continue
                rank[id(fit)] = (fit[0], fit[1], 0 if there == target.path else 1)
                wanted_by[id(item)].append(fit)
                fits_for[id(target)].append(fit)
            for fits in list(wanted_by.values()) + list(fits_for.values()):
                best = min(rank[id(fit)] for fit in fits)
                fits[:] = [fit for fit in fits if rank[id(fit)] == best]
            doubts, settled = {}, 0
            for fit in sorted(by_name_only, key=lambda fit: fit[:5]):
                target, item = fit[5], fit[6]
                mine, theirs = wanted_by.get(id(item), ()), fits_for.get(id(target), ())
                if fit not in mine or fit not in theirs or item.dests or satisfied(target):
                    continue
                paths = set(other[5].path for other in mine)      # Lua and a model may want the same one
                if len(paths) > 1:
                    doubts[id(item)] = Note('several names', item, len(paths))
                    continue
                others = [other[6] for other in theirs if other[6] is not item and not other[6].same_as(item)]
                if others:
                    for one in [item] + others:
                        doubts[id(one)] = Note('several files', target.path, len(others) + 1)
                    continue
                if settle(item, target.path, 'name'):
                    settled += 1
            count_votes(kind)
            if not settled:
                undecided.update(doubts)
                break

    def copies(kind, targets):
        """a wanted path that is still empty, and a file that is in use elsewhere but is meant
        here too: the same path shifted (materials/x/a and materials/models/x/a are both named),
        or a texture two materials next to it name by two paths"""
        for target in targets:
            if satisfied(target):
                continue
            parts = target.path.split('/')
            best = None
            for item in by_name.get(parts[-1], ()):
                if item.kind != kind or not item.dests:
                    continue
                how, same = relation(path_of(item), parts)
                if (how == 'shift' and same >= 2) or (kind == 'vtf' and item.folder in target.near):
                    if best is None or (same, item.order) > best[:2]:
                        best = (same, item.order, item)
            if best is not None:
                settle(best[2], target.path, 'name')

    def rest(kind, own_place=None, hint=None):
        """the files nobody asked for: where they say themselves, else with their folder, else
        where a hint points, else where they were packed"""
        todo = []
        for item in items:
            if item.kind != kind or item.dests or item.replaced:
                continue
            dest = None
            if not at_home(item) and id(item) not in undecided:
                # a folder that went somewhere as a whole takes the file along; a hint is better
                # than a bare majority of a mixed folder
                dest = (own_place and own_place(item)) or with_folder(item, 0.8) \
                    or (hint and hint(item)) or with_folder(item, 0.5)
            todo.append((item, dest))
        # a file that stays where it was packed keeps that place; only then others are moved in
        for item, dest in todo:
            if item.default is not None and dest in (None, item.default):
                settle(item, item.default, 'place')
        for item, dest in todo:
            if item.dests:
                continue
            if dest is not None and settle(item, dest, 'folder'):
                continue
            if dest is not None and dest != item.default and is_place(dest, kind):
                # Its place is known and another file has it: a second version of the same file.
                # It is not put at the path it was packed under instead - nothing looks there.
                item.crowded = dest
                rival = taken.get(dest)
                if rival is not None and not rival.same_as(item):
                    report.notes.append(Note('version', dest, item.source, rival.source))
                continue
            if item.default is not None:
                settle(item, item.default, 'place')
        count_votes(kind)

    # ---- what the files say -----------------------------------------------------------------
    materials = [item for item in items if item.kind == 'vmt']
    for item in materials:
        try:
            item.material = read_material(item.path)
        except (OSError, UnicodeError) as err:
            item.material = Material()
            report.notes.append(Note('unreadable', item, err))
    models = {}
    for item in items:
        if item.kind != 'mdl':
            continue
        try:
            item.model_name = read_model_name(item.path)
            models[id(item)] = read_model(item.path)
        except (OSError, ValueError) as err:
            models[id(item)] = err

    for path in named:
        known.add(posixpath.dirname(path))
    for item in materials:
        if item.replaced:
            continue
        beside = set()
        for _key, name, _sure in item.material.textures:
            there = posixpath.dirname('materials/' + name + '.vtf')
            known.add(there)
            # A material packed in one folder with a texture it names: whatever that folder is
            # called, it is the folder of the texture. Asked as long as nothing in the folder
            # has a place yet.
            if posixpath.basename(name) + '.vtf' in in_folder[item.folder] and there not in beside:
                beside.add(there)
                hints[item.folder][there] += 1
        for path in item.material.includes:
            known.add(posixpath.dirname(path))
    for item in items:
        found = models.get(id(item))
        if isinstance(found, tuple) and not item.replaced:
            for folder in found[0]:
                known.add('/'.join(p for p in ('materials', folder) if p))

    # ---- models -----------------------------------------------------------------------------
    def compiled_for(item, target):
        return item.model_name is not None and 'models/' + item.model_name == target.path

    def its_own_path(item):
        """a model nobody names, packed outside of any models folder: the path it was compiled for
        (when it has one: recompiled models often carry their bare file name)"""
        name = item.model_name
        if item.default is None and name and '/' in name and posixpath.basename(name) == item.name:
            return 'models/' + name
        return None

    def where_compiled(item):
        """a model that lies at the very path it was compiled for is not meant for another name"""
        if item.model_name and item.default == 'models/' + item.model_name:
            return item.default
        return None

    resolve('mdl', [Target(path) for path in sorted(named) if path.endswith('.mdl')], compiled_for,
            where_compiled, proof_is_sure=True)
    rest('mdl', its_own_path)
    for item in items:
        if item.kind != 'mdl':
            continue
        stem = item.name[:-len('.mdl')] + '.'
        for part in items:
            if part.kind == 'part' and not part.replaced and part.folder == item.folder and part.name.startswith(stem):
                for dest, how in zip(list(item.dests), list(item.how)):
                    settle(part, posixpath.dirname(dest) + '/' + part.name, how)
    count_votes('part')
    rest('part')

    # ---- materials --------------------------------------------------------------------------
    wanted = collections.OrderedDict()
    for path in sorted(named):
        if path.endswith('.vmt'):
            wanted[path] = Target(path)
    for item in materials:
        if item.replaced:
            continue
        for path in item.material.includes:
            wanted.setdefault(path, Target(path, asked=item)).near.add(item.folder)

    of_models, model_wants = [], []
    for item in items:
        if item.kind != 'mdl' or not item.dests:
            continue
        found = models[id(item)]
        if not isinstance(found, tuple):
            report.notes.append(Note('no materials', item.dests[0], found))
            continue
        folders, names = found
        report.models += 1
        for name in names:
            group = []
            for folder in folders or ['']:
                path = 'materials/' + '/'.join(p for p in (folder, name) if p) + '.vmt'
                if path not in group:
                    group.append(path)
            group = tuple(group)
            model_wants.append((item, name, group))
            for path in group:
                of_models.append(Target(path, near=[item.folder], group=group, asked=item))

    def texture_lies_there(item, target):
        base = item.material.base
        return base is not None and posixpath.dirname('materials/' + base) == posixpath.dirname(target.path)

    def beside_its_texture(item):
        """a material packed together with its own texture: the texture says where both belong"""
        base = item.material.base
        if not base:
            return None
        folder, stem = posixpath.split(base)
        if stem + '.vtf' not in in_folder[item.folder]:
            return None
        dest = '/'.join(p for p in ('materials', folder, item.name) if p)
        if relation(path_of(item), dest.split('/'))[0] == 'sibling':
            return None
        return dest

    def where_its_texture_is(item):
        """a material nobody names and whose folder says nothing: the folder of its texture, when
        that is its own folder a level up or down, or when it has no folder that means anything"""
        base = item.material.base
        if not base or '/' not in base:
            return None
        dest = 'materials/' + posixpath.dirname(base) + '/' + item.name
        how, same = relation(path_of(item), dest.split('/'))
        if item.default is None and how != 'sibling':
            return dest
        return dest if how == 'shift' and same >= 2 else None

    material_targets = list(wanted.values()) + of_models
    resolve('vmt', material_targets, texture_lies_there, beside_its_texture)
    copies('vmt', material_targets)
    # where the materials that nobody names will go counts for their folders too
    for item in materials:
        if not item.dests and not item.replaced and not at_home(item):
            dest = beside_its_texture(item)
            if dest is not None and is_place(dest, 'vmt'):
                vote(item, dest)
    rest('vmt', beside_its_texture, where_its_texture_is)

    # ---- textures ---------------------------------------------------------------------------
    textures = collections.OrderedDict()
    for item in materials:
        if not item.dests:
            continue
        for key, name, sure in item.material.textures:
            path = 'materials/' + name + '.vtf'
            target = textures.get(path)
            if target is None:
                target = textures[path] = Target(path, sure=False, asked=(item, key))
            target.near.add(item.folder)
            if sure and not target.sure:
                target.sure, target.asked = True, (item, key)
    resolve('vtf', list(textures.values()))
    copies('vtf', list(textures.values()))
    rest('vtf')

    # ---- the result -------------------------------------------------------------------------
    for dest in sorted(taken):
        item = taken[dest]
        report.placed.append((dest, item))
        if dest != item.default:
            src, dst = item.parts[:-1], dest.split('/')[:-1]
            same = common_suffix(src, dst)
            if same:
                src, dst = src[:len(src) - same + 1], dst[:len(dst) - same + 1]
            report.moves[(item.source, '/'.join(src), '/'.join(dst))] += 1
    for item in items:
        if item.dests:
            continue
        doubt = undecided.get(id(item))
        if doubt is not None and doubt not in report.notes:
            report.notes.append(doubt)
        if item.replaced:
            why = REPLACED
        elif item.default is not None and own(item.default):
            why = OWN_FILE
        elif item.crowded is not None:
            why = OWN_FILE if own(item.crowded) else PLACE_TAKEN
        elif doubt is not None:
            why = NAMESAKES
        elif item.default is None:
            why = UNNAMED
        else:
            why = PLACE_TAKEN
        report.left_out.append((item, why))

    report.missing_named = [path for path in sorted(named)
                            if path.endswith(('.mdl', '.vmt')) and free(path)]
    report.materials_wanted = len(model_wants)
    for item, name, group in model_wants:
        if all(free(path) for path in group):
            report.missing_materials.append((item.dests[0], name, group))
    for target in list(wanted.values()):
        if target.asked is not None and free(target.path):
            report.missing_textures.append((target.asked.dests[0] if target.asked.dests else str(target.asked),
                                            'include', target.path))
    for target in textures.values():
        if not target.sure:
            continue
        report.textures_wanted += 1
        if free(target.path):
            item, key = target.asked
            report.missing_textures.append((item.dests[0], key, target.path))
    return report
