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

What a material says about itself - its texture lies with it, named in some folder - tells
namesakes apart and places files nobody names. It does not outweigh the Lua: a material the Lua
names at one path only, lying in a folder that says nothing ("materials 5"), goes to that path
even when its texture is named elsewhere - materials and their textures are often kept apart.
Such a material tells what the folder of its texture means for the files packed with it: a
namesake lying there - a material the Lua names in several folders - with its texture named in
that same folder is of the same pack, and goes where the Lua names it for that pack.
The same file under one name in several folders (as many copies as names) fills those names:
which copy goes where does not matter. A material that has a place and is made of the very
texture a missing material is called after ("zcity_drill/sheet_16" for
materials/zcity_drill/sheet_16.vmt) is used for that one as well.

One kind of folder is trusted: a numbered copy of the materials or models folder ("materials3",
"models 2") that holds a tree. That is how an owner of the addon keeps the folders of the
addons he took the content from, and throws them into materials/: each file in it lies at its
path in the game already - materials3/models/tnb/x.vmt is materials/models/tnb/x.vmt, a file
right in materials3 is a file of the top of materials - where the addon it comes from has
it and everything that works with that addon looks for it. Such a file is read as lying there
(Item.rooted), before any name is looked up, and is a file that lies in the addon from then
on. What it says itself does not move it: a pack of models is copied from pack to pack
without being compiled again, so the models of tnb/halflife say tnb/halflife2 - and the pack
has a tnb/halflife2 of its own. Of two numbered folders with a file for one place the one
that comes later by its name has it; a file that lies there already keeps it.
Only a heap under a numbered name ("model 14/f/female_01.mdl", the next pack in "model 15/f")
is no tree, and shows: nothing asks for any of its files where a tree would have it, and most
of them are asked for elsewhere, where nothing lies. Its files go by their names.

A file that lies in a folder somebody names files in is at home there: it is moved for a
shifted path only, never for a name it merely shares with a file that is missing. A folder
nobody knows is no home, wherever it lies: that other files below materials/ lie right says
nothing about "materials/my stuff 3", and a file that merely stays where it was packed says
nothing about the folders around it.

A file nobody names follows what is known about its folder: where the files next to it went
(a folder that kept its name on the way - materials/gate -> materials/models/gate - took
everything below it along), or what a material and a texture it names, lying together, say
about the folder they lie in. Without any of that, the folders above it are read the way an
owner of the addon means them (zcg_layout.merged_destination) - a file of a numbered heap as
if that were a tree, a model that lies below materials/ as a file of models/. Where that
gives nothing either, the file stays where it was packed; packed outside of any materials /
models folder it is left out.

What cannot be decided is reported and never guessed:
    * a file that fits several names by its file name alone,
    * several different files that fit one name equally,
    * a name with no file (it may be a part of the game or of Z-City) - and with it every
      supplied file of that name that was not taken for it, wherever it went,
    * a file that no name and no folder claims.

Materials and textures are put below materials/ only, models below models/; a file of the
addon itself is never replaced; of two files for one place the later source has it - of two
folders of one source the one that comes later by its name, a number read as a number
("materials10" after "materials2").

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
# the folders every tree of content starts with
BARE_ROOTS = ('materials', 'models', 'materials/models')


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

    def __init__(self, source, inner, path, default, order, merged=None, mirror=None, root=None):
        self.source = source      # the archive or folder it came in
        self.inner = inner        # its path there, as packed
        self.path = path          # the file on the disk
        self.default = default    # where its folders alone put it (zcg_layout.dropin_destination) or None
        self.lies = default       # ... as it was packed (place() reads a numbered folder that holds a tree as that tree)
        # where it lies when the numbered and repeated materials / models folders above it are
        # read as that folder (zcg_layout.merged_destination)
        self.merged = merged if merged != default else None
        # the numbered folder it lies in (zcg_layout.numbered_folder): "materials/materials3"
        self.root = root if self.merged is not None else None
        self.rooted = False       # that folder holds a tree, and the file lies in it at its path in the game
        # a file of a model that lies below materials/ with no models folder above it: the same
        # path below models/ (merged_destination, mirror=True). The last thing to go by.
        self.mirror = mirror if mirror not in (default, self.merged) else None
        self.order = order        # of two that fit equally the later source wins
        self.parts = [p for p in clean(inner).split('/') if p]
        self.name = self.parts[-1]
        self.folder = (source, '/'.join(self.parts[:-1]))
        # The folder it stands for when its folder is asked where it went: the one it was packed
        # in - or, for a file of a tree in a numbered folder, the folder of the game it lies in.
        self.seat = self.folder
        self.kind = kind_of(self.name)
        self.dests = []           # where it goes
        self.how = []             # for each of them: 'place' as packed, 'name' found by name, 'folder' went with its folder
        self.material = None
        self.model_name = None    # a model: the path it was compiled for, without models/
        self.replaced = False     # a later source brought a file for the same place: that one is used
        self.copy = False         # ... and it is the same file, byte for byte
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
        # a texture: a material the addon needs names it (not only materials of a version of a
        # pack that is not in the addon)
        self.needed = True


# The remarks of a report and the reasons why a file was left out, in plain English. A report in
# another language (tools/content_report.py) is made from the same pieces.
NOTES = {
    'version': '%s: another version is in %s, the one from %s is used',
    'version here': '%s: two different files of one source go there, %s and %s; the second one is used',
    'equal': '%s: %s and %s fit equally, the first one is used',
    'several names': '%s fits %d names by its file name alone (in %s) and is not used: '
                     'give its folder the name of the folder it comes from',
    'several files': '%s: %d different files have this name and nothing says which one is meant; none is used: '
                     'give their folders the names of the folders they come from',
    'unreadable': '%s cannot be read: %s',
    'no materials': '%s: its materials are not followed (%s)',
    'also here': '%s: no file lay there, and the material at %s is made of the texture of this very name, so it is '
                 'this material: it is used here as well. If another material belongs at %s, that one is missing',
    'same name': '%s now lies in %s, where nobody names it. The Lua names a file of that name in %s and none is '
                 'there; this one was not taken for it: nothing says that it is the one. If it is, put it there',
    'same name unused': '%s is not used. The Lua names a file of that name in %s and none is there; this one was '
                        'not taken for it: nothing says that it is the one. If it is, put it there',
    'other version': '%s was put at %s: %s, and that is the place it has in a version of a pack that is not in this '
                     'addon. The Lua of the addon names a file of that name in %s and none is there; this one was not '
                     'taken for it. If it is the one after all, put it there',
    'compiled for other': '%d models lie where the Lua of the addon names a model, and say themselves that they were '
                          'compiled for the place the same model has in a version of the pack that is not in this addon '
                          '(%s). They may be the models of that version: if they look wrong in the game, replace them',
    'came back': '%d models lay at places of a version of the pack that is not in this addon, and say themselves that '
                 'they were compiled for places the Lua of this addon names, where nothing lay: they were put there (%s)',
}
# the reasons in an 'other version' note
SPARE_SAYS = 'it says itself that it belongs there'                 # a model: the path it was compiled for
SPARE_TEXTURE = 'its own texture is named in that folder'           # a material
SPARE_FOLDERS = 'its folders are those of that place'
REPLACED = 'a later source has this file'
COPY = 'a copy of a file that is used'
ORPHAN = 'the model it belongs to is not used'
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
        # Items put where they were packed for want of anything better: nobody names them and
        # nothing is known of their folders, or they are not told from their namesakes
        self.as_packed = []
        # (path in the addon, Item) - files that only a version of a pack names which is not in
        # the addon (the spare names of place()): put at their places, needed by nobody
        self.spare = []
        # (path in the addon, the spare path) - models that lie where the Lua of the addon names a
        # model and say themselves that they were compiled for the place of that other version
        self.misplaced = []
        self.missing_named = []       # paths the Lua names
        self.missing_materials = []   # (model in the addon, material name, the paths it is looked for at)
        self.missing_textures = []    # (material in the addon, parameter, texture path)
        self.models = 0               # models whose materials were followed
        self.materials_wanted = 0     # ... and how many materials they name
        self.textures_wanted = 0      # textures named by the placed materials


def natural(text):
    """a key that sorts "materials10" after "materials2": numbers are read as numbers"""
    return [int(part) if part.isdigit() else part for part in re.split(r'(\d+)', text)]


def by_folders(path):
    """a key that sorts paths the way a file manager lists folders: name by name, each read like
    natural() - "materials/x" before "materials1/x", "materials2/x" before "materials10/x".
    (natural() of the whole path would put "materials/x" after them all: "/" comes after the end
    of a name.)"""
    return [natural(part) for part in path.replace('\\', '/').lower().split('/')]


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


def place(items, named, own, spare=()):
    """Decides where every supplied file goes.
    items: Item list; named: game paths the Lua names; own(path): the addon has that file itself.
    spare: game paths that only the Lua of a pack names which is NOT in the addon - another
    version of a pack that is (zcg_layout.PACK_VERSIONS). The game does not need these files
    with this addon, and none of them is ever missing. They are known for one thing: a file
    that is one of them for sure is put at its own place, and so is not taken by its file name
    for a namesake that the Lua of the addon names. See of_another_version below.
    Returns a Report; nothing is copied here."""
    items = sorted((i for i in items if i.kind), key=lambda i: (i.order, i.inner))
    spare = set(spare) - set(named)
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
        item.lies = item.default

    # ---- what the files say -----------------------------------------------------------------
    unreadable = []
    materials = [item for item in items if item.kind == 'vmt']
    for item in materials:
        try:
            item.material = read_material(item.path)
        except (OSError, UnicodeError) as err:
            item.material = Material()
            unreadable.append(Note('unreadable', item, err))
    models = {}
    for item in items:
        if item.kind != 'mdl':
            continue
        try:
            item.model_name = read_model_name(item.path)
            models[id(item)] = read_model(item.path)
        except (OSError, ValueError) as err:
            models[id(item)] = err

    # ---- trees ------------------------------------------------------------------------------
    # A numbered folder - "materials3", "models 2" - is how an owner keeps the materials and
    # models folders of the addons he took the content from: two folders of one name do not fit
    # into one. Such a folder holds a tree, and a file in it lies at its path in the game
    # already: materials3/models/tnb/x.vmt is materials/models/tnb/x.vmt. That is where the
    # addon it comes from has it, and where everything that works with that addon looks for it -
    # scripts and models that are not at hand as well. So the file is read as lying there, and
    # from here on it is a file that lies in the materials folder like any other: it stays
    # unless a name asks for it at that very path shifted, or its folder is one nobody names
    # anything in and a name finds it there. What the file says itself is not asked: a model
    # that lies in tnb/halflife and was compiled as tnb/halflife2/... stays in tnb/halflife -
    # models are copied from pack to pack without being compiled again, and the pack may well
    # have a tnb/halflife2 of its own.
    #
    # A numbered folder may be a heap instead: files of several folders of the game, thrown
    # together ("model 14/f/female_01.mdl", the next one in "model 15/f"). Read as trees, two
    # heaps would be two versions of one file. A heap shows: nothing asks for any of its files
    # where the tree would have it, and most of them are asked for somewhere else, at a path
    # that is empty. Its files go by their names, as ever.
    roots = collections.defaultdict(list)
    for item in items:
        if item.root is not None and item.merged is not None and is_place(item.merged, item.kind):
            roots[(item.source, item.root)].append(item)
    if roots:
        asked, groups = set(named) | spare, []
        for item in materials:
            asked.update('materials/' + name + '.vtf' for _key, name, _sure in item.material.textures)
            asked.update(item.material.includes)
        for item in items:
            found = models.get(id(item))
            if isinstance(found, tuple):
                folders, names = found
                for name in names:
                    group = ['materials/' + '/'.join(p for p in (folder, name) if p) + '.vmt' for folder in folders or ['']]
                    groups.append(group)
                    asked.update(group)
        lying = set()
        for item in items:
            if item.root is not None and (item.source, item.root) in roots:
                lying.add(item.merged)
            elif item.default is not None:
                lying.add(item.default)
        empty = set(posixpath.basename(path) for path in asked if path not in lying)
        for group in groups:    # (a model looks into each of its folders: one file will do)
            if any(path in lying for path in group):
                empty.discard(posixpath.basename(group[0]))
        for members in roots.values():
            if not any(item.merged in asked for item in members):
                telling = [item for item in members if item.kind != 'part']
                elsewhere = sum(1 for item in telling if item.name in empty)
                if elsewhere * 2 > len(telling):
                    continue    # a heap
            for item in members:
                item.default, item.merged, item.rooted = item.merged, None, True
                item.seat = (item.source, posixpath.dirname(item.default))
                # (its neighbours are the files of that folder of the game - those that lie there
                # and those of the other numbered folders: what is true of files lying together
                # is true of them at once, not only when the tool is run again)
                in_folder[item.seat].add(item.name)

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

    def crowd(item, dest):
        """The place of a file is known and another file has it: a second version of that file, or
        a copy. It is not put anywhere else instead - nothing looks there - and is not looked at
        for any other name."""
        item.crowded = dest
        rival = taken.get(dest)
        if rival is not None:
            item.copy = rival.same_as(item)
            if not item.copy:
                report.notes.append(Note('version here', dest, item.inner, rival.inner) if rival.source == item.source
                                    else Note('version', dest, item.source, rival.source))
        if item in by_name.get(item.name, ()):
            by_name[item.name].remove(item)

    # where the folders alone put a file; of two files with one place the later source has it,
    # and the earlier one is out of the game: it is not looked at for any other name either
    def keeps_the_place(earlier, item):
        """of two files of one source for one place (item comes later in the order of the items):
        does the earlier one have it?"""
        if earlier.rooted != item.rooted:
            return item.rooted      # the file that lies there stays, whatever a numbered folder brings
        if earlier.rooted:
            # (of two numbered folders the one that comes later by its name, a number read as a
            # number; a second materials folder inside the first comes before "materials1")
            return by_folders(earlier.inner) > by_folders(item.inner)
        return earlier.order == item.order and by_folders(earlier.inner) > by_folders(item.inner)

    at, versions = {}, []
    for item in items:
        if item.default is None:
            continue
        earlier = at.get(item.default)
        if earlier is not None:
            if earlier.source == item.source and keeps_the_place(earlier, item):
                earlier, item = item, earlier
            earlier.replaced = True
        at[item.default] = item
    # (each of them is measured against the file that has the place in the end, not the next one)
    for item in items:
        if item.replaced:
            winner = at[item.default]
            item.copy = item.same_as(winner)
            if item.copy:
                pass
            elif item.source == winner.source:
                versions.append((item, Note('version here', item.default, item.inner, winner.inner)))
            else:
                versions.append((item, Note('version', item.default, item.source, winner.source)))
    for name in list(by_name):
        by_name[name] = [item for item in by_name[name] if not item.replaced]
    # A model of a tree moves whole. One that another model has the place of - another model, not
    # a copy - takes its files along: a file the other one has no file of its own for (a .phy)
    # is not put next to that one, and of the two models one remark tells, not one for every
    # file of theirs. id -> where it would lie.
    orphans = {}
    beside_model = collections.defaultdict(list)
    for item in items:
        if item.kind == 'part' and item.rooted:
            beside_model[item.folder].append(item)
    for item in items:
        if item.kind == 'mdl' and item.rooted and item.replaced and not item.copy:
            stem = item.name[:-len('.mdl')] + '.'
            for part in beside_model.get(item.folder, ()):
                if part.name.startswith(stem):
                    orphans[id(part)] = part.default
    report.notes += [note for earlier, note in versions if id(earlier) not in orphans]

    def path_of(item):
        return item.default.split('/') if item.default else item.parts

    # Folders that somebody names a file in. A file lying in one of them is at home: it is moved
    # only when its path is a shifted wanted one, never because its name alone fits elsewhere.
    known = set()

    def at_home(item):
        return item.default is not None and posixpath.dirname(item.default) in known

    def borne_out(item, place):
        """the folder a file was packed in is called like the folder of a place somebody thinks
        it has: .../gate/x for materials/models/gate/x (and not materials 5/x)"""
        how, same = relation(path_of(item), place.split('/'))
        return how == 'same' or (how != 'sibling' and same >= 2)

    def satisfied(target):
        if target.group is not None:
            return any(not free(path) for path in target.group)
        return not free(target.path)

    # ---- where the folders went -------------------------------------------------------------
    votes = collections.defaultdict(collections.Counter)
    loose_votes = collections.defaultdict(collections.Counter)
    hints = collections.defaultdict(collections.Counter)     # filled below, from the materials
    counted = set()
    # Files that stay where they were packed only because nothing says where they belong. Such
    # a file tells nothing about its folder, or about the folders above it.
    silent = set()

    def vote(item, dest):
        src, dst = [p for p in item.seat[1].split('/') if p], dest.split('/')[:-1]
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
            if id(item) not in silent:
                vote(item, item.dests[0])

    def with_folder(item, share, placed_only=False, roots=True):
        """the place of a file in the folder that its own folder (or the nearest one above that
        says anything) went to, when more than `share` of that folder went there.
        placed_only: only what files that have a place tell, no hints.
        roots=False: not what is only known of the materials (models) folder the file lies
        below. That folder is the materials folder - which says where a file goes along to when
        nothing else is known, and nothing about a folder in it that nobody knows ("my stuff 3"):
        a file there is as free to be the one a name asks for as a file in any folder."""
        source, folder = item.seat
        parts = folder.split('/') if folder else []
        root = ROOT_OF[item.kind]
        tables = ((votes, source), (hints, source), (votes, None), (loose_votes, source))
        if placed_only:
            tables = ((votes, source), (votes, None))
        for cut in range(len(parts), -1, -1):
            # a folder may hold models and materials at once: each kind follows its own.
            # Asked in this order: the files of the folder that have a place; a material and its
            # texture lying there; the same folder in the other sources; the folder above
            here = '/'.join(parts[:cut])
            for table, origin in tables:
                counter = [(count, dest) for dest, count in table.get((origin, here), {}).items()
                           if dest.split('/', 1)[0] == root]
                if counter:
                    break
            if not counter:
                continue
            count, best = max(counter)
            if count <= share * sum(n for n, _dest in counter):
                return None
            if not roots and cut < len(parts) and best in BARE_ROOTS \
                    and (here == best or here.endswith('/' + best)):
                return None
            there = '/'.join([best] + parts[cut:])
            if table is loose_votes and (item.default is not None or there not in known):
                return None
            if relation(path_of(item), there.split('/') + [item.name])[0] == 'sibling':
                return None
            return there + '/' + item.name
        return None

    undecided = {}
    merging = set()     # files that go where the names of their folders put them (Item.merged)

    def merged_place(item):
        return item.merged is not None and is_place(item.merged, item.kind)

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

        # A path the Lua names, and no other path with that file name is wanted. (A model may
        # look for the same file there, in one of its folders.) The Lua speaks of the clothes
        # themselves; what a model looks for may as well be a part of the game that nobody
        # has to supply, so a wish of a model alone is not taken as firmly.
        wanted_paths, wishes, single = collections.defaultdict(set), collections.defaultdict(list), {}
        for target in targets:
            name = target.path.rsplit('/', 1)[-1]
            wanted_paths[name].add(target.path)
            wishes[name].append(frozenset(target.group or (target.path,)))

        def the_only_wish(target):
            if target.group is not None or target.asked is not None:
                return False
            name = target.path.rsplit('/', 1)[-1]
            if name not in single:
                single[name] = any(wanted_paths[name] <= wish for wish in wishes[name])
            return single[name]

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
                near = item.folder in target.near or item.seat in target.near
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
                elif claimed not in (None, target.path) and \
                        (proof_is_sure or claimed in wanted_paths[parts[-1]] or not the_only_wish(target)
                         or borne_out(item, claimed)):
                    # It belongs elsewhere and says so: a model that lies at the path it was
                    # compiled for, a namesake, a material in the very folder its texture is
                    # named in. (A material in a folder that says nothing, which the Lua names
                    # at this one path only, is not kept from it by where its texture is named:
                    # a material may well keep its textures in another folder than its own.)
                    continue
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
                there = with_folder(item, 0.8, roots=False)
                if there is not None and there != target.path:
                    # Its folder went elsewhere. For the only wish of the Lua that has to be
                    # known from files that have a place, or be borne out by the name of the
                    # folder: the texture of a material in a folder that says nothing is a hint
                    # for telling namesakes apart, and for files nobody names - no more.
                    if not the_only_wish(target):
                        continue
                    hinted, there = there, with_folder(item, 0.8, placed_only=True, roots=False)
                    if there is None:
                        if borne_out(item, hinted):
                            continue
                    elif there != target.path:
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
                    # One and the same file, as many copies as there are names for it, and
                    # every copy fits every one of these names: which copy goes where does not
                    # matter. (With a copy too few, the name that stays empty would be a guess.)
                    copies_of = {}
                    for other in mine:
                        for rival in fits_for.get(id(other[5]), ()):
                            copies_of[id(rival[6])] = rival[6]
                    twins = len(copies_of) == len(paths) and all(
                        (one is item or one.same_as(item)) and
                        set(f[5].path for f in wanted_by.get(id(one), ())) == paths
                        for one in copies_of.values())
                    if not twins:
                        folders = sorted(posixpath.dirname(path) for path in paths)
                        doubts[id(item)] = Note('several names', item, len(paths),
                                                ', '.join(folders[:4]) + (' ...' if len(folders) > 4 else ''))
                        continue
                    if settle(item, target.path, 'name'):
                        settled += 1
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
                # (a file of the version that is not in the addon is a file of that version: it is
                # not used for a name of the addon either)
                if item.kind != kind or not item.dests or only_spare(item):
                    continue
                how, same = relation(path_of(item), parts)
                if (how == 'shift' and same >= 2) or \
                        (kind == 'vtf' and (item.folder in target.near or item.seat in target.near)):
                    if best is None or (same, item.order) > best[:2]:
                        best = (same, item.order, item)
            if best is not None:
                settle(best[2], target.path, 'name')

    def rest(kind, own_place=None, hint=None):
        """the files nobody asked for: where they say themselves, else with their folder, else
        where a hint points, else where they were packed"""
        todo = []
        for item in items:
            if item.kind != kind or item.dests or item.replaced or item.crowded is not None or id(item) in orphans:
                continue
            dest = None
            if at_home(item):
                pass
            elif id(item) in undecided:
                # (not told from its namesakes: it does not go with its folder as if nobody
                # had asked for it - but where it says itself that it belongs, it may)
                dest = own_place(item) if own_place else None
            else:
                # a folder that went somewhere as a whole takes the file along; a hint is better
                # than a bare majority of a mixed folder
                dest = (own_place and own_place(item)) or with_folder(item, 0.8, roots=False) \
                    or (hint and hint(item)) or with_folder(item, 0.5, roots=False)
                if dest is None and merged_place(item):
                    # Nothing is known but how its folders are called: "materials3" is a copy of
                    # the materials folder, a model below materials/ belongs below models/.
                    dest = item.merged
                    merging.add(id(item))
                    silent.add(id(item))
                if dest is None:
                    # Nothing but the materials (models) folder it lies below is known: it goes
                    # along with that one - and tells nothing about the folders around it.
                    dest = with_folder(item, 0.8) or with_folder(item, 0.5)
                    if dest is not None:
                        silent.add(id(item))
            todo.append((item, dest))
        # a file that stays where it was packed keeps that place; only then others are moved in
        for item, dest in todo:
            if item.default is not None and dest in (None, item.default):
                if settle(item, item.default, 'place') and dest is None and not at_home(item):
                    silent.add(id(item))
        # (of the files that go by the names of their folders alone, the later one first: of
        # two numbered folders with a file for one place the later one has it)
        todo = [pair for pair in todo if id(pair[0]) not in merging] + \
            sorted((pair for pair in todo if id(pair[0]) in merging),
                   key=lambda pair: (pair[0].order, by_folders(pair[0].inner)), reverse=True)
        for item, dest in todo:
            if item.dests:
                continue
            if dest is not None and settle(item, dest, 'folder'):
                continue
            if dest is not None and dest != item.default and is_place(dest, kind):
                # Its place is known and another file has it: a second version of the same file.
                # It is not put at the path it was packed under instead - nothing looks there.
                crowd(item, dest)
                continue
            if item.default is not None and settle(item, item.default, 'place'):
                silent.add(id(item))
        count_votes(kind)

    # ---- the folders somebody names files in ------------------------------------------------
    report.notes += unreadable
    for path in named:
        known.add(posixpath.dirname(path))
    for path in spare:      # (a file that lies in a folder of the other version is at home there)
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
            if posixpath.basename(name) + '.vtf' in in_folder[item.seat] and there not in beside:
                beside.add(there)
                hints[item.seat][there] += 1
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

    def compiled_path(item):
        """the path a model says it was compiled for (when it has one: recompiled models often
        carry their bare file name)"""
        name = item.model_name
        if name and '/' in name and posixpath.basename(name) == item.name:
            return 'models/' + name
        return None

    def its_own_path(item):
        """a model nobody names, packed outside of any models folder: the path it was compiled for"""
        return compiled_path(item) if item.default is None else None

    def where_compiled(item):
        """a model that lies at the very path it was compiled for is not meant for another name"""
        if item.model_name and item.default == 'models/' + item.model_name:
            return item.default
        return None

    # ---- the files of a version that is not in the addon -------------------------------------
    spare_named, wanted_named = collections.defaultdict(list), collections.defaultdict(list)
    for path in sorted(spare):
        spare_named[posixpath.basename(path)].append(path)
    for path in named:
        wanted_named[posixpath.basename(path)].append(path.split('/'))
    asked_by_lua = set(named)
    spared = {}     # id(item) -> why it is known to be a file of the other version
    shut_out = set()    # ... and those of them whose place another file has

    came_back = []

    def of_another_version(kind, says, said, comes_back=False):
        """The files that are, for sure, files only a version left out of the addon names. Each
        of them is put at the place that version names before anything is looked for, and so is
        not taken by its file name for a namesake the Lua of the addon names
        (models/zcity/m/male_10.mdl of one version, models/slav/m/male_10.mdl of the other).
        For sure is: a file that lies there; and, of the files that lie in a folder nobody names
        anything in ("models 7"), one whose folders are those of that place - more of them than
        of any place the Lua of the addon names - and one that says itself that this is its
        place (says(item): a model knows the path it was compiled for; said: that reason).
        A file that says nothing goes where the Lua of the addon wants a file of that name, as
        ever: that is the version the owner has.
        comes_back: the other way round. A file that lies at a place of the other version and
        says itself that it belongs at a place the Lua of the addon names, where nothing lies,
        is put there. (Before it knew of versions this tool took such models by their file
        names; with the other version in the addon they lie at the places of the first.)
        The files that lie at such a place come first: one that lies there is not pushed out by
        one that merely belongs there (the same folders once more, under a number). That one
        has no place then - and, being a file of the other version, is not taken for any name
        of the addon either."""
        mine = [item for item in items if item.kind == kind and item.name in spare_named]
        for lying in (True, False):
            for item in mine:
                if item.dests or item.replaced or item.crowded is not None or (item.default in spare) != lying:
                    continue
                dest = why = None
                if lying:
                    dest = item.default
                    claim = says(item) if comes_back else None
                    if claim in asked_by_lua and at.get(claim) is None and settle(item, claim, 'name'):
                        came_back.append(claim)
                        continue
                elif not at_home(item) and item.default not in asked_by_lua:
                    parts = path_of(item)
                    rivals = max([common_suffix(parts, wanted) for wanted in wanted_named.get(item.name, ())] or [0])
                    best = None
                    for path in spare_named[item.name]:
                        how, same = relation(parts, path.split('/'))
                        if how != 'sibling' and same >= 2 and same > rivals and (best is None or same > best[0]):
                            best = (same, path)
                    claim = says(item)
                    if best is not None:
                        dest, why = best[1], SPARE_FOLDERS
                    elif claim in spare:
                        dest, why = claim, said
                if dest is None:
                    continue
                if settle(item, dest, 'place' if why is None else 'name'):
                    spared[id(item)] = why
                elif why is not None and is_place(dest, kind):
                    crowd(item, dest)
                    shut_out.add(id(item))

    def only_spare(item):
        """it is in use at places of the other version only: what it asks for is not needed"""
        return bool(item.dests) and all(dest in spare for dest in item.dests)

    of_another_version('mdl', compiled_path, SPARE_SAYS, comes_back=True)
    if came_back:
        report.notes.append(Note('came back', len(came_back), ', '.join(sorted(came_back)[:3]) + (' ...' if len(came_back) > 3 else '')))
    resolve('mdl', [Target(path) for path in sorted(named) if path.endswith('.mdl')], compiled_for,
            where_compiled, proof_is_sure=True)
    def follow(part, model):
        """A file of a model whose place another model has. The same model, byte for byte: its
        files belong to the one that lies there as well. Another model: they are not mixed into
        that one, and have no place."""
        dest = posixpath.dirname(model.crowded) + '/' + part.name
        if not model.copy:
            orphans[id(part)] = dest
            return
        orphans.pop(id(part), None)
        if not settle(part, dest, 'folder'):
            crowd(part, dest)

    rest('mdl', its_own_path)
    followers = []
    for item in items:
        if item.kind != 'mdl':
            continue
        stem = item.name[:-len('.mdl')] + '.'
        # (a model out of a numbered folder, or one of the version that is not in the addon)
        lost = not item.dests and item.crowded is not None and (id(item) in merging or id(item) in shut_out)
        for part in items:
            if part.kind == 'part' and not part.replaced and part.folder == item.folder and part.name.startswith(stem):
                for dest, how in zip(list(item.dests), list(item.how)):
                    settle(part, posixpath.dirname(dest) + '/' + part.name, how)
                if lost and not part.dests and part.crowded is None:
                    followers.append((part, item))
                    orphans[id(part)] = None        # (it waits: rest() leaves it alone)
    count_votes('part')
    rest('part')
    # (last: every file that lies at its place has it by now)
    for part, item in followers:
        follow(part, item)

    # A file of a model that lies below materials/, and nothing is known of it: it belongs below
    # models/, and all there is to go by are the folders it lies in. A model goes where its own
    # files went, when they went somewhere together; else to the same path below models/, and
    # its files with it.
    def mirrored(item, dest):
        if settle(item, dest, 'folder'):
            merging.add(id(item))
            silent.add(id(item))
            return True
        crowd(item, dest)
        return False

    def waits(item, kind):
        return item.kind == kind and not item.dests and not item.replaced and item.crowded is None \
            and id(item) not in undecided and id(item) not in orphans \
            and item.mirror is not None and is_place(item.mirror, kind)

    for item in items:
        if not waits(item, 'mdl'):
            continue
        stem = item.name[:-len('.mdl')] + '.'
        parts = [part for part in items if part.kind == 'part' and not part.replaced and part.folder == item.folder
                 and part.name.startswith(stem)]
        went = set(posixpath.dirname(dest) for part in parts for dest in part.dests)
        dest = went.pop() + '/' + item.name if len(went) == 1 else item.mirror
        placed = mirrored(item, dest)
        for part in parts:
            if not part.dests and part.crowded is None:
                if placed:
                    mirrored(part, posixpath.dirname(dest) + '/' + part.name)
                else:
                    follow(part, item)
    for item in items:
        if waits(item, 'part'):
            mirrored(item, item.mirror)

    # ---- materials --------------------------------------------------------------------------
    wanted = collections.OrderedDict()
    for path in sorted(named):
        if path.endswith('.vmt'):
            wanted[path] = Target(path)
    for item in materials:
        if item.replaced:
            continue
        for path in item.material.includes:
            wanted.setdefault(path, Target(path, asked=item)).near.update((item.folder, item.seat))

    of_models, model_wants = [], []
    for item in items:
        if item.kind != 'mdl' or not item.dests:
            continue
        found = models[id(item)]
        if not isinstance(found, tuple):
            report.notes.append(Note('no materials', item.dests[0], found))
            continue
        folders, names = found
        # (a model of a version that is not in the addon: its materials are given their places
        # like those of any model, and none of them counts as wanted or missing)
        counts = not only_spare(item)
        report.models += counts
        for name in names:
            group = []
            for folder in folders or ['']:
                path = 'materials/' + '/'.join(p for p in (folder, name) if p) + '.vmt'
                if path not in group:
                    group.append(path)
            group = tuple(group)
            if counts:
                model_wants.append((item, name, group))
            for path in group:
                of_models.append(Target(path, near=[item.folder, item.seat], group=group, asked=item))

    def texture_lies_there(item, target):
        base = item.material.base
        return base is not None and posixpath.dirname('materials/' + base) == posixpath.dirname(target.path)

    def beside_its_texture(item):
        """a material packed together with its own texture: the texture says where both belong"""
        base = item.material.base
        if not base:
            return None
        folder, stem = posixpath.split(base)
        if stem + '.vtf' not in in_folder[item.seat]:
            return None
        dest = '/'.join(p for p in ('materials', folder, item.name) if p)
        if relation(path_of(item), dest.split('/'))[0] == 'sibling':
            return None
        return dest

    def says_where(item):
        """where a material says that it belongs: with its own texture, when that lies beside
        it; in the folder its texture is named in, when the folder it lies in is called the same"""
        dest = beside_its_texture(item)
        base = item.material.base
        if dest is None and base and '/' in base:
            there = 'materials/' + posixpath.dirname(base) + '/' + item.name
            if borne_out(item, there):
                dest = there
        return dest

    def where_its_texture_is(item):
        """a material nobody names and whose folder says nothing: the folder of its texture, when
        that is its own folder a level up or down, or when it has no folder that means anything"""
        base = item.material.base
        if not base or '/' not in base:
            return None
        dest = 'materials/' + posixpath.dirname(base) + '/' + item.name
        how, same = relation(path_of(item), dest.split('/'))
        if item.default is None and how != 'sibling' and not merged_place(item):
            return dest
        return dest if how == 'shift' and same >= 2 else None

    material_targets = list(wanted.values()) + of_models
    of_another_version('vmt', says_where, SPARE_TEXTURE)
    resolve('vmt', material_targets, texture_lies_there, says_where)

    # A material packed with its own texture says where the two belong: in the folder the texture
    # is named in. Where the Lua names the material at one path only, the Lua was believed
    # instead (above) - and that tells what this folder of textures means for the files packed
    # there: the materials of "materials 14" whose textures are named in models/drill_pack went
    # to zcity_drill. So a sheet_16.vmt lying with them, its texture named in models/drill_pack
    # too, is of that pack - and of the folders the Lua names a sheet_16.vmt in, it is the one
    # of zcity_drill. (Left to itself it would follow its texture, to a place no Lua looks at.)
    pack_of = collections.defaultdict(set)

    def packed_as(item, claim):
        source, folder = item.seat
        keys = [(source, folder, posixpath.dirname(claim))]
        if folder:      # (an upload cut into several archives has the same folder in each of them)
            keys.append((None, folder, posixpath.dirname(claim)))
        return keys

    for item in materials:
        if item.dests and item.how[0] == 'name' and not item.replaced:
            claim = beside_its_texture(item)
            if claim is not None and claim != item.dests[0]:
                for key in packed_as(item, claim):
                    pack_of[key].add(posixpath.dirname(item.dests[0]))
    of_the_pack = collections.OrderedDict()
    for item in materials:
        if item.dests or item.replaced or item.crowded is not None or at_home(item):
            continue
        claim = beside_its_texture(item)
        if claim is None:
            continue
        for key in packed_as(item, claim):
            folders = pack_of.get(key)
            if folders:
                break
        else:
            continue
        fits = [target for target in wanted.values()
                if target.asked is None and not satisfied(target)
                and posixpath.basename(target.path) == item.name and posixpath.dirname(target.path) in folders
                and relation(path_of(item), target.path.split('/'))[0] != 'sibling']
        if len(fits) == 1:
            of_the_pack[fits[0].path] = (item, posixpath.dirname(claim))
    for path, (item, folder) in of_the_pack.items():
        # Another file of that name that lies with its texture, named in that folder too, is
        # another version of this material, whatever it is packed with. Two versions are not
        # told apart: none is taken, as with any two files for one name.
        rivals = [other for other in by_name.get(item.name, ())
                  if other is not item and other.kind == 'vmt' and not other.dests and not at_home(other)
                  and posixpath.dirname(beside_its_texture(other) or '') == folder and not other.same_as(item)]
        if rivals:
            for one in [item] + rivals:
                undecided[id(one)] = Note('several files', path, len(rivals) + 1)
            continue
        settle(item, path, 'name')
    count_votes('vmt')

    copies('vmt', material_targets)

    # A material the Lua names that is still missing, and a material of that name which has a
    # place and is made of the very texture this name stands for - "zcity_drill/sheet_16" for
    # materials/zcity_drill/sheet_16.vmt. It is this material, whatever took it to the other
    # place. (Up to 2.3.0 sort_content.py did not know the names a Lua file writes without
    # "materials/" and gave such a file to its namesake of another pack; there it lies at a
    # named path now, and a file that lies at a named path stays.) It is used here as well -
    # nothing is taken away from the other place - and a note tells about it.
    for target in wanted.values():
        if target.asked is not None or satisfied(target):
            continue
        stem = target.path[len('materials/'):-len('.vmt')]
        same = [item for item in by_name.get(posixpath.basename(target.path), ())
                if item.kind == 'vmt' and item.dests and item.material.base == stem]
        if same and all(one.same_as(same[0]) for one in same[1:]):
            there = same[0].dests[0]
            if settle(same[0], target.path, 'name'):
                report.notes.append(Note('also here', target.path, there, there))
    # where the materials that nobody names will go counts for their folders too
    for item in materials:
        if not item.dests and not item.replaced and item.crowded is None and not at_home(item):
            dest = beside_its_texture(item)
            if dest is not None and is_place(dest, 'vmt'):
                vote(item, dest)
    rest('vmt', beside_its_texture, where_its_texture_is)

    # ---- textures ---------------------------------------------------------------------------
    textures = collections.OrderedDict()
    for item in materials:
        if not item.dests:
            continue
        needed = not only_spare(item)
        for key, name, sure in item.material.textures:
            path = 'materials/' + name + '.vtf'
            target = textures.get(path)
            if target is None:
                target = textures[path] = Target(path, sure=False, asked=(item, key))
                target.needed = False
            target.near.update((item.folder, item.seat))
            # (of the materials that name it, one that the addon needs is the one to tell about)
            if sure and (not target.sure or (needed and not target.needed)):
                target.sure, target.asked = True, (item, key)
            target.needed = target.needed or (needed and sure)
    resolve('vtf', list(textures.values()))
    copies('vtf', list(textures.values()))
    rest('vtf')

    # ---- the result -------------------------------------------------------------------------
    for dest in sorted(taken):
        item = taken[dest]
        report.placed.append((dest, item))
        if dest in spare:
            report.spare.append((dest, item))
        if dest != item.lies:
            src, dst = item.parts[:-1], dest.split('/')[:-1]
            same = common_suffix(src, dst)
            if same:
                src, dst = src[:len(src) - same + 1], dst[:len(dst) - same + 1]
            report.moves[(item.source, '/'.join(src), '/'.join(dst))] += 1
    for item in items:
        if id(item) in silent and item.dests == [item.lies]:
            report.as_packed.append(item)
        doubt = undecided.get(id(item))
        if doubt is not None and doubt not in report.notes and (not item.dests or id(item) in silent):
            # (a file of the addon that could not be told from its namesakes stays where it lies)
            report.notes.append(doubt)
        if item.dests:
            continue
        if id(item) in orphans:
            # (a copy of the file the other model has there is a copy, like the model itself)
            twin = taken.get(orphans[id(item)])
            why = COPY if twin is not None and twin.same_as(item) else ORPHAN
        elif item.replaced:
            # (of two numbered folders of one source none is "later": the other file has the place)
            why = COPY if item.copy else PLACE_TAKEN if item.rooted else REPLACED
        elif item.default is not None and own(item.default):
            why = OWN_FILE
        elif item.crowded is not None:
            why = OWN_FILE if own(item.crowded) else COPY if item.copy else PLACE_TAKEN
        elif doubt is not None:
            why = NAMESAKES
        elif item.default is None:
            why = UNNAMED
        else:
            why = PLACE_TAKEN
        report.left_out.append((item, why))

    # A name of the Lua that stays empty, and a supplied file of that name that is in nobody's
    # use: it was not taken because nothing says that it is the one - and nothing says that it
    # is not. Told with the place the file went to, so that it can be found - and told again by
    # every later run, when the file lies there: as long as the name is empty.
    # (Not told: a file in a folder where the Lua or a model names files - it is at home there;
    # a second version of a file that has its place; a model that knows the path it was compiled
    # for; and a file that is or went next door to the name, .../male_03/x for .../male_04/x:
    # that is another file.)
    asked = set(named)
    asked.update(target.path for target in material_targets)
    homes = set(posixpath.dirname(path) for path in asked)
    empty = collections.defaultdict(list)
    for path in sorted(named):
        if path.endswith(('.mdl', '.vmt')) and free(path):
            empty[posixpath.basename(path)].append(path)
    for item in items:
        if item.name not in empty or item.kind not in ('vmt', 'mdl') or item.replaced \
                or item.crowded is not None or any(dest in asked for dest in item.dests) \
                or undecided.get(id(item)) in report.notes:
            continue
        if id(item) in spared:
            # A file of the other version, by its own word or by its folders, and the name of
            # the addon is empty: told, with the reason - somebody may know better.
            if spared[id(item)] is not None:
                folders = sorted(posixpath.dirname(path) + '/' for path in empty[item.name])
                report.notes.append(Note('other version', item, posixpath.dirname(item.dests[0]) + '/', spared[id(item)],
                                         ', '.join(folders[:4]) + (' ...' if len(folders) > 4 else '')))
            continue
        if item.kind == 'mdl' and item.model_name and '/' in item.model_name:
            continue
        if item.dests and posixpath.dirname(item.dests[0]) in homes:
            continue
        folders = sorted(posixpath.dirname(path) + '/' for path in empty[item.name]
                         if relation(path_of(item), path.split('/'))[0] != 'sibling'
                         and not (item.dests and relation(item.dests[0].split('/'), path.split('/'))[0] == 'sibling'))
        if not folders:
            continue
        folders = ', '.join(folders[:4]) + (' ...' if len(folders) > 4 else '')
        if item.dests:
            report.notes.append(Note('same name', item, posixpath.dirname(item.dests[0]) + '/', folders))
        else:
            report.notes.append(Note('same name unused', item, folders))

    # A model at a place of the addon that says it was compiled for the place of the other
    # version: it lay there, or an earlier version of this tool took it by its file name.
    odd = sorted(dest for dest, item in taken.items()
                 if item.kind == 'mdl' and dest not in spare and item.model_name and 'models/' + item.model_name in spare
                 and posixpath.basename(item.model_name) == item.name and dest in asked)
    if odd:
        report.misplaced = [(dest, 'models/' + taken[dest].model_name) for dest in odd]
        report.notes.append(Note('compiled for other', len(odd), ', '.join(odd[:3]) + (' ...' if len(odd) > 3 else '')))

    report.missing_named = [path for path in sorted(named)
                            if path.endswith(('.mdl', '.vmt')) and free(path)]
    report.materials_wanted = len(model_wants)
    for item, name, group in model_wants:
        if all(free(path) for path in group):
            report.missing_materials.append((item.dests[0], name, group))
    for target in list(wanted.values()):
        if target.asked is not None and free(target.path) and not only_spare(target.asked):
            report.missing_textures.append((target.asked.dests[0] if target.asked.dests else str(target.asked),
                                            'include', target.path))
    for target in textures.values():
        if not target.sure or not target.needed:
            continue
        report.textures_wanted += 1
        if free(target.path):
            item, key = target.asked
            report.missing_textures.append((item.dests[0], key, target.path))
    return report
