# -*- coding: utf-8 -*-
"""The names that still have no file after sort_content.py has sorted everything, filled with
what the addon does hold under ANOTHER name.  (used by sort_content.py)

place_content.py puts a file where the game looks for it when the file has the name that is
looked for. A file under another name is left alone there: that is never a sure thing. Here it
is taken all the same - when nothing else can fill the name - and always as a COPY: the file
that was found stays where it lay, nothing is moved, replaced or deleted, and every copy is
written into the report. What is tried, for a name without a file, in this order:

    renamed    a file whose name is that name with what Windows and people add to a copy:
               "face (1).vmt", "face - Copy.vmt", "face — копия.vmt", "Копия face.vmt".
    model      a model that says itself that it was compiled for that very path, under any file
               name - copied with the files that belong to it (.vvd .vtx .phy .ani), renamed alike.
    material   for a material: a material under any name that is made of the texture with the
               path of the missing material ("renamed_face.vmt" with $basetexture
               "models/x/miranda_facemap4" for materials/models/x/miranda_facemap4.vmt).
    made       for a material: a texture called as the missing material that no material at
               hand is made of. The texture is put beside the place of the material and a plain
               material is written for it.
    namesake   for a file that another FILE asks for (a material of a model, a texture of a
               material): the only file of that name, in whatever folder it lies. For a name the
               Lua tables give this is done only when asked (--fill-namesakes): the tables name
               the same file name in several folders on purpose (male / female, one face of two packs).

A name is filled only when all the files that fit are one and the same file (byte for byte);
several different ones are left for the owner and listed.
"""
from __future__ import print_function

import collections
import hashlib
import io
import os
import posixpath
import re

import vmt

MODEL_PARTS = ('.dx90.vtx', '.dx80.vtx', '.sw.vtx', '.xbox.vtx', '.vtx', '.vvd', '.phy', '.ani')
KINDS = ('.vmt', '.vtf', '.mdl')

RENAMED, MODEL, MATERIAL, MADE, NAMESAKE = 'renamed', 'model', 'material', 'made', 'namesake'

_DECOR = (
    re.compile(r'\s*\(\d+\)$'),                                              # "x (1)"
    re.compile(u'\\s*[-\u2013\u2014_]\\s*(copy|\u043a\u043e\u043f\u0438\u044f)$'),     # "x - Copy", "x — копия"
    re.compile(u'^(copy of|\u043a\u043e\u043f\u0438\u044f)\\s+'),                      # "Copy of x", "Копия x"
    re.compile(r'\s+copy$'),                                                 # "x copy"
)


def split(name):
    """('male_10', '.dx90.vtx') for 'Male_10.dx90.vtx'"""
    low = name.lower()
    for ext in MODEL_PARTS:
        if low.endswith(ext):
            return low[:-len(ext)], ext
    stem, ext = posixpath.splitext(low)
    return stem, ext


def plain_stem(stem):
    """the name without what a copy gets added: 'face' for 'face - копия (2)'"""
    stem = stem.strip().lower()
    while True:
        before = stem
        for pattern in _DECOR:
            stem = pattern.sub(u'', stem).strip()
        if stem == before or not stem:
            return stem or before


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def model_name(data):
    """'models/slav/m/male_10.mdl' - the path a model says it was compiled for"""
    if len(data) < 76 or data[:4] != b'IDST':
        return None
    name = data[12:76].split(b'\x00')[0].decode('latin-1').replace('\\', '/').strip().lower()
    while '//' in name:
        name = name.replace('//', '/')
    name = name.lstrip('/')
    if not name.endswith('.mdl'):
        return None
    return name if name.startswith('models/') else 'models/' + name


def base_texture(data):
    """'models/x/face' - the $basetexture of a material, as a game path without .vtf"""
    try:
        _shader, items = vmt.parse(data.decode('utf-8', 'replace'))
    except Exception:       # (a broken material says nothing)
        return None
    for item in items:
        if isinstance(item, (tuple, list)) and len(item) >= 2 and isinstance(item[0], str) \
                and item[0].lower() == '$basetexture' and isinstance(item[1], str):
            name = item[1].replace('\\', '/').strip().lower().lstrip('/')
            if name.endswith('.vtf'):
                name = name[:-4]
            return name or None
    return None


def plain_material(texture):
    """a material for a texture nobody wrote one for (texture: game path without materials/ and .vtf)"""
    return ('// written by sort_content.bat: the texture was there, its material was not\r\n'
            '"VertexLitGeneric"\r\n{\r\n\t"$basetexture" "%s"\r\n\t"$model" "1"\r\n}\r\n' % texture).encode('utf-8')


class Fill(object):
    """one name that was filled: .dest (path in the addon), .how, .source (path in the addon the
    file was copied from; for MADE the texture), .extra ([paths] written along with it)"""

    def __init__(self, dest, how, source, extra=()):
        self.dest, self.how, self.source, self.extra = dest, how, source, list(extra)


class Result(object):
    def __init__(self):
        self.done = []          # [Fill]
        self.unsure = []        # [(dest, [sources])] several different files fit
        self.failed = []        # [(dest, error)]

    @property
    def files(self):
        return sum(1 + len(one.extra) for one in self.done)


def fill(addon, files, wanted_named=(), wanted_asked=(), namesakes=False, dry=False):
    """addon: its folder. files: [(path in the addon with /, path on the disk)] - everything that
    may be copied from (the materials, models and _not_used folders, without the addon's own files).
    wanted_named: the paths the Lua names that have no file; wanted_asked: [[paths]] - a file
    another file asks for, at any one of these paths (a model looks in several folders).
    Returns a Result."""
    result = Result()
    by_plain = collections.defaultdict(list)    # (plain stem, ext) -> [(rel, full)]
    by_name = collections.defaultdict(list)     # (stem, ext) -> [(rel, full)]
    there = set()
    for rel, full in files:
        stem, ext = split(posixpath.basename(rel))
        there.add(rel.lower())
        by_name[(stem, ext)].append((rel, full))
        plain = plain_stem(stem)
        if plain != stem:
            by_plain[(plain, ext)].append((rel, full))

    cache = {}

    def data_of(full):
        if full not in cache:
            cache[full] = read(full)
        return cache[full]

    def one_file(found):
        """the files that fit, when they are all the same file: (rel, full); else None"""
        digests = set(hashlib.sha1(data_of(full)).digest() for _rel, full in found)
        return sorted(found)[0] if len(digests) == 1 else None

    said = {}       # what the models and materials say, read once: kind -> {name: [(rel, full)]}

    def models_saying():
        if 'mdl' not in said:
            said['mdl'] = collections.defaultdict(list)
            for (stem, ext), group in by_name.items():
                if ext == '.mdl':
                    for rel, full in group:
                        try:
                            with open(full, 'rb') as f:
                                name = model_name(f.read(76))
                        except (OSError, IOError):
                            name = None
                        if name:
                            said['mdl'][name].append((rel, full))
        return said['mdl']

    def materials_of():
        if 'vmt' not in said:
            said['vmt'] = collections.defaultdict(list)
            said['in use'] = set()      # the textures some material is made of, as paths in the addon
            for (stem, ext), group in by_name.items():
                if ext == '.vmt':
                    for rel, full in group:
                        try:
                            texture = base_texture(data_of(full))
                        except (OSError, IOError):
                            texture = None
                        if texture:
                            said['vmt'][posixpath.basename(texture)].append((rel, full))
                            said['in use'].add('materials/' + texture + '.vtf')
        return said['vmt']

    def write(dest, data):
        if dest.lower() in there:
            return False
        if not dry:
            target = os.path.join(addon, dest.replace('/', os.sep))
            if os.path.lexists(target):
                there.add(dest.lower())
                return False
            folder = os.path.dirname(target)
            if not os.path.isdir(folder):
                os.makedirs(folder)
            with open(target + '.zcg_new', 'wb') as f:
                f.write(data)
            os.replace(target + '.zcg_new', target)
        there.add(dest.lower())
        return True

    def parts_of(rel, full):
        """the files that belong to a model: [(ext, full)]"""
        folder = posixpath.dirname(rel)
        stem, _ext = split(posixpath.basename(rel))
        found = []
        for ext in MODEL_PARTS:
            for other, other_full in by_name.get((stem, ext), ()):
                if posixpath.dirname(other) == folder:
                    found.append((ext, other_full))
        return found

    def take(dest, how, source):
        """copies source (rel, full) to dest; a model takes its files along"""
        rel, full = source
        if not write(dest, data_of(full)):
            return False
        extra = []
        if dest.endswith('.mdl'):
            for ext, part in parts_of(rel, full):
                along = dest[:-len('.mdl')] + ext
                if write(along, data_of(part)):
                    extra.append(along)
        result.done.append(Fill(dest, how, rel, extra))
        if dest.endswith('.vmt'):
            # the material that was copied asks for its texture: that one is looked for right away
            texture = base_texture(data_of(full))
            if texture:
                texture = 'materials/' + texture + '.vtf'
                if texture not in there:
                    attempt(texture, True)
        return True

    def try_one(dest, asked):
        """fills dest when something fits; True when it is filled, None when several files fit"""
        stem, ext = split(posixpath.basename(dest))
        if ext not in KINDS:
            return False
        ways = [(RENAMED, [pair for pair in by_plain.get((stem, ext), ())])]
        if ext == '.mdl':
            ways.append((MODEL, [pair for pair in models_saying().get(dest, ()) if pair[0].lower() != dest]))
        if ext == '.vmt':
            # (made of the texture of that very path - of a texture merely called so only when asked)
            ways.append((MATERIAL, [pair for pair in materials_of().get(stem, ())
                                    if split(posixpath.basename(pair[0]))[0] != stem
                                    and (namesakes or base_texture(data_of(pair[1])) == dest[len('materials/'):-len('.vmt')])]))
        if asked or namesakes:
            ways.append((NAMESAKE, list(by_name.get((stem, ext), ()))))
        for how, found in ways:
            if not found:
                continue
            source = one_file(found)
            if source is None:
                result.unsure.append((dest, sorted(rel for rel, _full in found)))
                return None
            return take(dest, how, source)
        if ext == '.vmt':
            # no material at all: a texture of that name will do, with a material written for it
            # (not a texture some other material is made of, in another folder: that is the texture
            # of a namesake - "zcity_drill/sheet_16" is not ".../modern/male/sheet_16")
            materials_of()
            beside = dest[:-len('.vmt')] + '.vtf'
            textures = [pair for pair in list(by_name.get((stem, '.vtf'), ())) + list(by_plain.get((stem, '.vtf'), ()))
                        if namesakes or pair[0].lower() == beside or pair[0].lower() not in said['in use']]
            if textures:
                source = one_file(textures)
                if source is None:
                    result.unsure.append((dest, sorted(rel for rel, _full in textures)))
                    return None
                game_path = beside[len('materials/'):-len('.vtf')]
                extra = []
                if beside.lower() in there:
                    lying = os.path.join(addon, beside.replace('/', os.sep))
                    if os.path.isfile(lying) and data_of(lying) != data_of(source[1]):
                        # another texture lies there under that name: it is the one the material gets
                        source = (beside, lying)
                elif write(beside, data_of(source[1])):
                    extra.append(beside)
                if write(dest, plain_material(game_path)):
                    result.done.append(Fill(dest, MADE, source[0], extra))
                    return True
        return False

    def attempt(dest, asked):
        try:
            return try_one(dest, asked)
        except (OSError, IOError) as err:
            result.failed.append((dest, u'%s' % (err,)))
            return False

    for dest in sorted(set(wanted_named)):
        if dest.lower() not in there:
            attempt(dest, False)
    seen = set()
    for group in wanted_asked:
        group = tuple(group)
        if group in seen or any(path.lower() in there for path in group):
            continue
        seen.add(group)
        for dest in group:
            if attempt(dest, True) is not False:
                break
    return result


HOW = {
    RENAMED: u'копия файла с тем же именем, к которому добавлено «(1)», «копия» и т. п.',
    MODEL: u'модель под другим именем, которая сама говорит, что собрана для этого пути',
    MATERIAL: u'материал под другим именем, сделанный из текстуры с путём недостающего материала',
    MADE: u'материала не было, была текстура с его именем: материал написан заново',
    NAMESAKE: u'единственный файл с таким именем, из другой папки',
}


def lines(result, dry=False):
    """what was filled, for the report: every file"""
    out = []
    if result.done:
        out.append(u'Подставлено под недостающие имена — имён: %d, файлов: %d%s'
                   % (len(result.done), result.files, u' (пробный запуск: ничего не записано)' if dry else u''))
        out.append(u'  Это КОПИИ: исходные файлы лежат где лежали. Если подставлен не тот файл — удалите копию.')
        for how in (RENAMED, MODEL, MATERIAL, MADE, NAMESAKE):
            group = [one for one in result.done if one.how == how]
            if not group:
                continue
            out.append(u'  %s — %d:' % (HOW[how], len(group)))
            for one in sorted(group, key=lambda one: one.dest):
                out.append(u'    %s  <=  %s' % (one.dest, one.source))
                for path in one.extra:
                    out.append(u'        и %s' % path)
    if result.unsure:
        out.append(u'Не подставлено: под имя подходит несколько РАЗНЫХ файлов — %d. Выберите сами и положите нужный:' % len(result.unsure))
        for dest, sources in sorted(result.unsure):
            out.append(u'    %s' % dest)
            for source in sources[:6]:
                out.append(u'        ? %s' % source)
            if len(sources) > 6:
                out.append(u'        … и ещё %d' % (len(sources) - 6))
    if result.failed:
        out.append(u'Не удалось записать — %d:' % len(result.failed))
        out += [u'    %s: %s' % pair for pair in sorted(result.failed)]
    return out


def short(result):
    """the same in a few lines, for the screen"""
    out = []
    if result.done:
        count = collections.Counter(one.how for one in result.done)
        out.append(u'Подставлено под недостающие имена: имён — %d, файлов — %d (копии; исходные файлы на месте):'
                   % (len(result.done), result.files))
        for how in (RENAMED, MODEL, MATERIAL, MADE, NAMESAKE):
            if count[how]:
                out.append(u'  %d — %s' % (count[how], HOW[how]))
    if result.unsure:
        out.append(u'Не подставлено (подходит несколько разных файлов): %d — список в отчёте.' % len(result.unsure))
    if result.failed:
        out.append(u'Не удалось записать: %d — см. отчёт.' % len(result.failed))
    return out
