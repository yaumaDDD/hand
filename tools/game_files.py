# -*- coding: utf-8 -*-
"""Which of these files does the game itself have?  (used by sort_content.py)

sort_content.py sees one folder, the addon. A name without a file in it is "missing" there - and
for a player model that is most of what it is made of: the eyes, the mouth and the face of a
citizen are files of the game, its body and its gloves are files of Z-City. Told as missing they
bury the few files that really are. So, after the sorting, the names that have no file in the
addon are looked up where the game looks, on the computer the tool runs on:

    the archives of the game          <game>/garrysmod/*_dir.vpk, <game>/sourceengine/*_dir.vpk ...
    the game folder                   <game>/garrysmod/materials, models, and download/
    addons that are folders           <game>/garrysmod/addons/<name>/
    addons that are archives          *.gma in <game>/garrysmod/addons and in the caches of the game
    the addons of the workshop        <library>/steamapps/workshop/content/4000/<id>/*
    other games of the library        Counter-Strike: Source, Half-Life 2 ...: their archives
                                      (the game shows those that are ticked in its menu)

Nothing is unpacked and nothing is written: an archive lists its files at its front, and only
that list is read. An archive that cannot be read is counted and passed over.

The game is <...>/GarrysMod, the folder that holds garrysmod/. It is found around the addon
(<game>/garrysmod/addons/<addon>), through Steam (its libraries), or named with --game.
What is found is true of this computer: a server and its players need the files as well.
"""
import collections
import io
import os
import re
import struct
import sys
import time

sys.dont_write_bytecode = True

GAME_FOLDERS = ('GarrysMod', 'GarrysModDS')
APP_ID = '4000'
# other games the game can show the files of: (folder in steamapps/common, folder of the game in it)
OTHER_GAMES = (
    ('Counter-Strike Source', 'cstrike'),
    ('Half-Life 2', 'hl2'), ('Half-Life 2', 'episodic'), ('Half-Life 2', 'ep2'), ('Half-Life 2', 'lostcoast'),
    ('Half-Life 2 Deathmatch', 'hl2mp'),
    ('Team Fortress 2', 'tf'),
    ('Day of Defeat Source', 'dod'),
    ('Portal', 'portal'), ('Portal 2', 'portal2'),
    ('Left 4 Dead', 'left4dead'), ('Left 4 Dead 2', 'left4dead2'),
)
# where a file was seen: the kinds, in the order they are looked through
VPK, LOOSE, DOWNLOAD, FOLDER, GMA, WORKSHOP, OTHER = 'vpk', 'loose', 'download', 'folder', 'gma', 'workshop', 'other'
KINDS = (VPK, LOOSE, DOWNLOAD, FOLDER, GMA, WORKSHOP, OTHER)

MAX_LIST = 64 * 1024 * 1024     # the list of files of an archive is never this long: such a file is broken


# ---- the game ---------------------------------------------------------------------------------
def looks_like_game(root):
    """is this the folder that holds garrysmod/ ?"""
    inner = os.path.join(root, 'garrysmod')
    return os.path.isdir(inner) and (os.path.isfile(os.path.join(inner, 'gameinfo.txt'))
                                     or os.path.isfile(os.path.join(inner, 'garrysmod_dir.vpk'))
                                     or os.path.isdir(os.path.join(inner, 'addons')))


def sure_game(path):
    """The game, when a folder is the game itself beyond doubt - <game>, its garrysmod folder, or
    a folder of Steam that holds it (the library, steamapps, common) - else None. Told by
    garrysmod/gameinfo.txt, which every game and every server has. (A pack of content can hold a
    folder called garrysmod too - garrysmod/addons/<pack>/materials ... - and a folder below
    garrysmod is content as well: neither is the game.)"""
    path = os.path.abspath(path)
    tries = [path]
    if os.path.basename(path).lower() == 'garrysmod':
        tries.append(os.path.dirname(path))
    for name in GAME_FOLDERS:
        tries += [os.path.join(path, name), os.path.join(path, 'common', name),
                  os.path.join(path, 'steamapps', 'common', name)]
    for root in tries:
        if os.path.isfile(os.path.join(root, 'garrysmod', 'gameinfo.txt')):
            return root
    return None


def given_game(path):
    """the game for a folder somebody named: <game>, <game>/garrysmod or anything below it"""
    path = os.path.abspath(path)
    if looks_like_game(path):
        return path
    return around(path)


def around(path):
    """the game a folder lies in (<game>/garrysmod/addons/<addon>), or None"""
    path = os.path.abspath(path)
    while True:
        parent = os.path.dirname(path)
        if parent == path:
            return None
        if os.path.basename(path).lower() == 'garrysmod' and looks_like_game(parent):
            return parent
        path = parent


def steam_roots():
    """the folders Steam may be installed in"""
    found = []
    if os.name == 'nt':
        try:
            import winreg
            for hive, key, value in ((winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam', 'SteamPath'),
                                     (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
                                     (winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\Valve\Steam', 'InstallPath')):
                try:
                    with winreg.OpenKey(hive, key) as handle:
                        found.append(winreg.QueryValueEx(handle, value)[0])
                except OSError:
                    pass
        except ImportError:
            pass
        for base in (os.environ.get('ProgramFiles(x86)'), os.environ.get('ProgramFiles')):
            if base:
                found.append(os.path.join(base, 'Steam'))
    else:
        home = os.path.expanduser('~')
        found += [os.path.join(home, '.steam', 'steam'), os.path.join(home, '.steam', 'root'),
                  os.path.join(home, '.local', 'share', 'Steam'),
                  os.path.join(home, '.var', 'app', 'com.valvesoftware.Steam', '.local', 'share', 'Steam'),
                  os.path.join(home, 'Library', 'Application Support', 'Steam')]
    seen, out = set(), []
    for path in found:
        if not isinstance(path, str) or not path:
            continue
        path = os.path.normpath(path)
        key = os.path.normcase(path)
        if key not in seen and os.path.isdir(path):
            seen.add(key)
            out.append(path)
    return out


# a library in libraryfolders.vdf: "path" "D:\\Games" (in a block of its own), or, the older way,
# "1" "D:\\Games" - one pair on a line (the numbers of the installed games are written the same way)
_VDF_PATH = re.compile(r'^[ \t]*"(?:path|\d+)"[ \t]+"([^"\r\n]+)"[ \t]*\r?$', re.I | re.M)


def libraries(steam):
    """the libraries of a Steam folder: itself and what libraryfolders.vdf names"""
    found = [steam]
    for rel in (('steamapps', 'libraryfolders.vdf'), ('config', 'libraryfolders.vdf')):
        try:
            with io.open(os.path.join(steam, *rel), encoding='utf-8', errors='replace') as f:
                text = f.read(1 << 20)
        except (OSError, IOError):
            continue
        for value in _VDF_PATH.findall(text):
            found.append(value.replace('\\\\', '\\'))
    seen, out = set(), []
    for path in found:
        path = os.path.normpath(path)
        key = os.path.normcase(path)
        if key not in seen and os.path.isabs(path) and os.path.isdir(os.path.join(path, 'steamapps')):
            seen.add(key)
            out.append(path)
    return out


class Game(object):
    def __init__(self, root, how, library=None):
        self.root = root            # the folder that holds garrysmod/
        self.how = how              # 'given', 'around' (the addon lies in it) or 'steam'
        # the Steam library it lies in (<library>/steamapps/common/GarrysMod), or None
        if library is None:
            common = os.path.dirname(root)
            apps = os.path.dirname(common)
            if os.path.basename(common).lower() == 'common' and os.path.basename(apps).lower() == 'steamapps':
                library = os.path.dirname(apps)
        self.library = library


def find(addon=None, given=None, steam=None):
    """The game on this computer: named (given), the one the addon lies in, or the one Steam has.
    steam: the folders to look for Steam in (default: where it is installed). Returns a Game or
    None; never raises."""
    try:
        if given:
            root = given_game(given)
            return Game(root, 'given') if root else None
        if addon:
            root = around(addon)
            if root:
                return Game(root, 'around')
        for base in (steam_roots() if steam is None else steam):
            for library in libraries(base):
                for name in GAME_FOLDERS:
                    root = os.path.join(library, 'steamapps', 'common', name)
                    if looks_like_game(root):
                        return Game(root, 'steam', library)
    except Exception:       # (whatever a strange computer does: there is no game then)
        return None
    return None


# ---- archives ---------------------------------------------------------------------------------
def _text(raw):
    return raw.decode('utf-8', 'replace').replace('\\', '/').lower()


def vpk_names(path):
    """the files a *_dir.vpk lists (lower case, forward slashes); ValueError when it is none"""
    with open(path, 'rb') as f:
        head = f.read(28)
        if len(head) < 12:
            raise ValueError('too short')
        signature, version, size = struct.unpack_from('<3I', head)
        if signature != 0x55AA1234:
            raise ValueError('not a vpk')
        if version == 1:
            start = 12
        elif version == 2:
            start = 28
        else:
            raise ValueError('vpk version %d' % version)
        if not 0 < size <= MAX_LIST:
            raise ValueError('broken header')
        f.seek(start)
        data = f.read(size)
    names = []
    pos = 0

    def word():
        end = data.index(b'\x00', pos)
        return data[pos:end], end + 1

    try:
        while True:
            ext, pos = word()
            if not ext:
                break
            ext = _text(ext)
            while True:
                folder, pos = word()
                if not folder:
                    break
                folder = _text(folder).strip('/')
                while True:
                    name, pos = word()
                    if not name:
                        break
                    preload = struct.unpack_from('<H', data, pos + 4)[0]
                    pos += 18 + preload
                    full = _text(name)
                    if ext.strip():
                        full += '.' + ext
                    if folder.strip():
                        full = folder + '/' + full
                    names.append(full)
    except (ValueError, struct.error):
        # (a list that ends early: what was read is what there is)
        if not names:
            raise ValueError('broken list')
    return names


class _Stream(object):
    """the front of a file, read as far as it is asked for; fill() hands out the next bytes"""

    def __init__(self, fill):
        self.fill, self.data, self.pos, self.done = fill, bytearray(), 0, False

    def more(self):
        if self.done or len(self.data) > MAX_LIST:
            raise ValueError('the list of files does not end')
        chunk = self.fill()
        if not chunk:
            self.done = True
            raise ValueError('the file ends inside its list of files')
        self.data += chunk

    def read(self, count):
        while len(self.data) - self.pos < count:
            self.more()
        out = bytes(self.data[self.pos:self.pos + count])
        self.pos += count
        return out

    def word(self):
        while True:
            end = self.data.find(b'\x00', self.pos)
            if end >= 0:
                break
            self.more()
        out = bytes(self.data[self.pos:end])
        self.pos = end + 1
        return out


def gma_names(path):
    """(title, the files) of an addon archive - a .gma, also one that Steam keeps compressed;
    ValueError when the file is none. The files are named the way the game sees them:
    "materials/x.vmt", lower case."""
    with open(path, 'rb') as f:
        head = f.read(4)
        f.seek(0)
        if head == b'GMAD':
            stream = _Stream(lambda: f.read(1 << 16))
        else:
            try:
                import lzma
            except ImportError:
                raise ValueError('compressed, and this Python cannot read that')
            unpack = lzma.LZMADecompressor()

            def fill():
                while not unpack.eof:
                    raw = f.read(1 << 16)
                    if not raw:
                        return b''
                    out = unpack.decompress(raw)
                    if out:
                        return out
                return b''
            stream = _Stream(fill)
        try:
            if stream.read(4) != b'GMAD':
                raise ValueError('not an addon archive')
            version = stream.read(1)[0]
            stream.read(16)                     # who made it and when
            if version > 1:
                while stream.word():            # the content it needs: a list that ends with an empty name
                    pass
            title = stream.word().decode('utf-8', 'replace')
            stream.word()                       # description
            stream.word()                       # author
            stream.read(4)                      # version of the addon
            names = []
            while struct.unpack('<I', stream.read(4))[0]:
                names.append(_text(stream.word()))
                stream.read(12)                 # size, checksum
                if len(names) > 500000:
                    raise ValueError('the list of files does not end')
        except ValueError:
            raise
        except Exception as err:                # (lzma.LZMAError, struct.error ...)
            raise ValueError(str(err) or err.__class__.__name__)
    return title, names


# ---- looking the names up -----------------------------------------------------------------------
class Found(object):
    def __init__(self, game):
        self.game = game
        self.where = {}                         # path -> (kind, label): the first place it was seen at
        self.looked = collections.Counter()     # kind -> archives or folders looked through
        self.unread = []                        # (file, why): archives that could not be read
        self.cut = False                        # stopped: it took too long
        self.skipped = []                       # folders in addons/ that are another copy of this addon

    def by_kind(self, paths=None):
        """kind -> how many of the paths (default: all that were found) were seen there"""
        count = collections.Counter()
        for path in (self.where if paths is None else paths):
            if path in self.where:
                count[self.where[path][0]] += 1
        return count


def _by_folder(wanted):
    folders = collections.defaultdict(list)
    for path in wanted:
        folder, _slash, name = path.rpartition('/')
        folders[folder].append(name)
    return folders


def _loose(base, folders, kind, label, found):
    """the wanted files that lie below a folder as files"""
    if not (os.path.isdir(os.path.join(base, 'materials')) or os.path.isdir(os.path.join(base, 'models'))):
        return False
    for folder, names in folders.items():
        full = os.path.join(base, *folder.split('/'))
        if not os.path.isdir(full):
            continue
        try:
            have = set(name.lower() for name in os.listdir(full))
        except OSError:
            continue
        for name in names:
            if name in have:
                found.where.setdefault(folder + '/' + name, (kind, label))
    return True


def _listed(names, wanted, kind, label, found):
    for name in names:
        if name in wanted:
            found.where.setdefault(name, (kind, label))


def _files(folder, ends=None):
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    return [os.path.join(folder, name) for name in names
            if (ends is None or name.lower().endswith(ends)) and os.path.isfile(os.path.join(folder, name))]


def _dirs(folder):
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return []
    return [os.path.join(folder, name) for name in names if os.path.isdir(os.path.join(folder, name))]


def look(game, wanted, skip=(), own_marker=None, seconds=40):
    """Looks the wanted paths ("materials/x.vmt", lower case) up in the game. skip: folders that
    are not looked into (the addon that is being sorted); own_marker: a path below an addon
    folder that tells a copy of this addon - such a folder is not looked into either, it is
    about to be replaced. Returns a Found; never raises."""
    found = Found(game)
    wanted = set(wanted)
    if not wanted:
        return found
    folders = _by_folder(wanted)
    stop = time.time() + seconds
    skip = set(os.path.normcase(os.path.realpath(path)) for path in skip)

    def late():
        if time.time() > stop:
            found.cut = True
        return found.cut

    def archive(path, kind, label=None, number=None):
        """reads the list of an archive; label: what to call it (default: the title it gives itself)"""
        try:
            if kind in (VPK, OTHER):
                names, title = vpk_names(path), None
            else:
                title, names = gma_names(path)
        except (ValueError, OSError) as err:
            found.unread.append((path, str(err)))
            return
        found.looked[kind] += 1
        label = label or title or os.path.basename(path)
        _listed(names, wanted, kind, label if number is None else (label, number), found)

    try:
        root = game.root
        inner = os.path.join(root, 'garrysmod')
        # the archives of the game: every *_dir.vpk one folder below it
        for folder in _dirs(root):
            for path in _files(folder, '_dir.vpk'):
                if late():
                    return found
                archive(path, VPK, os.path.basename(folder) + '/' + os.path.basename(path))
        # the game folder
        if _loose(inner, folders, LOOSE, 'garrysmod', found):
            found.looked[LOOSE] += 1
        if _loose(os.path.join(inner, 'download'), folders, DOWNLOAD, 'garrysmod/download', found):
            found.looked[DOWNLOAD] += 1
        # addons: folders and archives
        addons = os.path.join(inner, 'addons')
        for folder in _dirs(addons):
            if late():
                return found
            if os.path.normcase(os.path.realpath(folder)) in skip:
                continue
            if own_marker and os.path.isfile(os.path.join(folder, *own_marker.split('/'))):
                found.skipped.append(os.path.basename(folder))
                continue
            if _loose(folder, folders, FOLDER, os.path.basename(folder), found):
                found.looked[FOLDER] += 1
        for path in _files(addons, '.gma'):
            if late():
                return found
            archive(path, GMA)
        for cache in (os.path.join(inner, 'cache', 'workshop'), os.path.join(inner, 'cache', 'srcds')):
            for path in _files(cache):
                if late():
                    return found
                if path.lower().endswith(('.gma', '.cache', '.bin')):
                    archive(path, GMA)
        # the workshop folder of Steam, and the other games of the library
        if game.library:
            # (an addon of the workshop: a folder named by its number with a .gma in it; one from
            # before 2020 is a compressed .bin, in such a folder or right here)
            workshop = os.path.join(game.library, 'steamapps', 'workshop', 'content', APP_ID)
            for folder in _dirs(workshop) + [workshop]:
                number = os.path.basename(folder) if folder != workshop else None
                for path in _files(folder):
                    if late():
                        return found
                    if path.lower().endswith(('.gma', '.bin')):
                        stem = os.path.basename(path).split('.')[0].split('_')[0]
                        archive(path, WORKSHOP, number=number or (stem if stem.isdigit() else '?'))
            common = os.path.join(game.library, 'steamapps', 'common')
            for name, mod in OTHER_GAMES:
                base = os.path.join(common, name, mod)
                if not os.path.isdir(base):
                    continue
                for path in _files(base, '_dir.vpk'):
                    if late():
                        return found
                    archive(path, OTHER, name)
                if _loose(base, folders, OTHER, name, found):
                    found.looked[OTHER] += 1
    except Exception as err:        # (nothing here may stop the sorting: it is done by now)
        found.unread.append((game.root, str(err) or err.__class__.__name__))
    return found
