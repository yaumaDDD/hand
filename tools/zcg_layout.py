# -*- coding: utf-8 -*-
"""Shared description of how the source archives map onto the addon layout.

Used by build_addon.py (repo root) and by the helper scripts in tools/.
"""
import os
import re

ADDON_DIRNAME = "zcity_csgo_gloves"

# where glove materials live (the path is baked into the .mdl files, do not change)
ARMS_MAT_DIR = "materials/models/weapons/v_models/arms"
# where the addon keeps the models (free to choose, Lua refers to it)
MODELS_DIR = "models/zcity_csgo_gloves"
# Skin of the fingers inside the fingerless glove models: material name below materials/.
# Made by tools/make_skin.py, used by cl_render.lua (Config.FingerMaterial in sh_config.lua).
FINGER_MATERIAL = ADDON_DIRNAME + "/skin/fingers"

# archive (without .7z / .zip) -> list of (folder inside the archive, destination)
# destination for textures is relative to ARMS_MAT_DIR, "@models" means MODELS_DIR
ARCHIVES = {
    "bloodhound":               [("bloodhound", "glove_bloodhound")],
    "bloodhound1":              [("bloodhound1", "glove_bloodhound/bloodhound")],
    "brokenfang":               [("brokenfang", "glove_bloodhound")],
    "brokenfang1":              [("brokenfang1", "glove_bloodhound/brokenfang")],
    "hydra":                    [("hydra", "glove_bloodhound")],
    "hydra1":                   [("hydra1", "glove_bloodhound/hydra")],
    "glove_fingerless":         [("glove_fingerless", "glove_fingerless")],
    "glove_fullfinger":         [("glove_fullfinger", "glove_fullfinger")],
    "glove_hardknuckle":        [("glove_hardknuckle", "glove_hardknuckle")],
    "glove_motorcycle":         [("glove_motorcycle", "glove_motorcycle")],
    "glove_handwrap_leathery":  [("glove_handwrap_leathery", "glove_handwrap_leathery")],
    "glove_handwrap_leathery2": [("glove_handwrap_leathery2", "glove_handwrap_leathery")],
    "glove_handwrap_leathery3": [("glove_handwrap_leathery3", "glove_handwrap_leathery")],
    "models1":                  [("2", "@models")],
    "models2":                  [("1", "@models")],
    # Driver gloves: the VMTs and the shared exponent maps, then one folder per colour
    "driver main":              [("driver main", "glove_slick")],
    "driver main2":             [("driver main2", "glove_slick")],
    "driver main3":             [("driver main3", "glove_slick")],
    # Specialist gloves, the same way
    "specialist":               [("specialist", "glove_specialist")],
}
for _n in range(1, 14):
    ARCHIVES["driver%d" % _n] = [("driver%d" % _n, "glove_slick/%d" % _n)]
for _n in range(1, 12):
    ARCHIVES["specialst%d" % _n] = [("specialst%d" % _n, "glove_specialist/right/%d" % _n)]
# Sport gloves (these came as .zip): the VMTs and the exponent map, then one folder per colour
ARCHIVES["sport main"] = [("sport main", "glove_sporty")]
for _n in range(1, 14):
    ARCHIVES["sport%d" % _n] = [("sport%d" % _n, "glove_sporty/%d" % _n)]

# ---------------------------------------------------------------------------------------
# Corrections to the VMTs of the archives: addon-relative path (lower case) -> {key: value}.
# tools/make_vmts.py applies them before it looks for the textures.
#
# Specialist gloves: the VMTs name bump maps in folders that have none (2, 3, 4, 6, 8), while
# the bump maps that do exist lie in folders 1, 5, 7, 9, 10 and 11, each next to the colour
# texture it was made for (same stripes, lettering, web, diamonds). So every colour gets the
# bump map of its own folder. The five colours without one are printed fabric; they get one of
# the two plain weaves, 9 or 10 - the one whose weave is also baked into their colour texture.
# (The web of 7 does not fit 6: the two webs are drawn differently.)
# ---------------------------------------------------------------------------------------
SPECIALIST_BUMP = {1: 1, 2: 9, 3: 9, 4: 9, 5: 5, 6: 10, 7: 7, 8: 10, 9: 9, 10: 10, 11: 11}
VMT_FIXES = {}
for _n, _bump in SPECIALIST_BUMP.items():
    for _side in ('left', 'right'):
        _name = 'glove_specialist_%s%s' % (_side, '' if _n == 1 else '_%d' % _n)
        VMT_FIXES['%s/glove_specialist/%s.vmt' % (ARMS_MAT_DIR, _name)] = {
            '$bumpmap': 'models/weapons/v_models/arms/glove_specialist/right/%d/glove_specialist_normal_right' % _bump}

# ---------------------------------------------------------------------------------------------
# Drop-in sources
# ---------------------------------------------------------------------------------------------
# Whatever lies in the repository root and is not listed above is taken as a part of some other
# addon - Lua that adds clothes to the appearance menu, materials, models:
#     an archive               anything.zip, anything.7z
#     a split archive          anything.7z.001, .002 ...  (7-Zip "split to volumes"; .zip alike)
#     a folder                 any folder but the ones of the project (PROJECT_DIRS)
# and so are the materials and models somebody put into the folders of the addon skeleton.
#
# Lua and everything else but content goes into the build under the path its folders give it:
#     <anything>/lua/...                       -> lua/...
#     <anything>/materials/...                 -> materials/...        (models, sound ... alike)
#     <anything>/homigrad/...  (no lua folder) -> lua/homigrad/...     (autorun ... alike)
# Whatever has no such folder above it (the addon.json of that addon, notes) is left out.
#
# Materials, textures and models (.vmt .vtf .mdl and the files of a model) are not trusted to
# lie in the right folders. Each of them is put where the Lua, a model or a material that
# names it looks for it: see tools/place_content.py.

# read by the tools only, never shipped
REFERENCE_ARCHIVES = ("z_city.zip", "hands.zip", "hands2.zip")
OPTIMIZED_PREFIX = "optimized_textures"

CONTENT_ROOTS = ("lua", "materials", "models", "sound", "particles", "resource", "scripts")
LUA_ROOTS = ("homigrad", "autorun", "initpost", "entities", "weapons", "effects")
MATERIAL_TYPES = (".vmt", ".vtf", ".png", ".jpg", ".jpeg")


def dropin_archives(root):
    """full paths of the drop-in archives in the repository root, in name order"""
    found = []
    for name in sorted(os.listdir(root)):
        stem, ext = os.path.splitext(name)
        if ext.lower() not in (".zip", ".7z"):
            continue
        if stem in ARCHIVES or name in REFERENCE_ARCHIVES or name.startswith(OPTIMIZED_PREFIX):
            continue
        found.append(os.path.join(root, name))
    return found


# a split archive: content.7z.001, content.7z.002 ... (7-Zip "split to volumes")
VOLUME = re.compile(r'^(.+\.(?:7z|zip))\.(\d{3})$', re.I)
# folders of the repository root that belong to the project; any other one is taken as content
PROJECT_DIRS = (ADDON_DIRNAME, 'tools', 'docs', 'build')


# Content the addon itself owns. Anything else that lies in the materials / models folders of
# its skeleton was put there by hand and is treated like the content of a drop-in archive.
OWN_CONTENT = ("materials/" + ADDON_DIRNAME + "/", ARMS_MAT_DIR + "/", MODELS_DIR + "/")


def is_own_content(path):
    return path.replace("\\", "/").lower().startswith(OWN_CONTENT)


def _reserved(name):
    """an archive name the glove build or the tools use for something else"""
    stem = os.path.splitext(name)[0]
    return stem in ARCHIVES or name in REFERENCE_ARCHIVES or name.startswith(OPTIMIZED_PREFIX)


def dropin_sources(root):
    """Everything in the repository root that brings files of other addons, in name order:
    [(name, kind, paths)] with kind 'archive' (one .zip / .7z), 'volumes' (the parts of a split
    archive, in order; name is the archive without its number) or 'folder'."""
    found, volumes = [], {}
    for name in sorted(os.listdir(root)):
        full = os.path.join(root, name)
        if os.path.isdir(full):
            if not name.startswith(('.', '_')) and name not in PROJECT_DIRS:
                found.append((name, 'folder', [full]))
            continue
        part = VOLUME.match(name)
        if part:
            if not _reserved(part.group(1)):
                volumes.setdefault(part.group(1), []).append(full)
            continue
        if os.path.splitext(name)[1].lower() in ('.zip', '.7z') and not _reserved(name):
            found.append((name, 'archive', [full]))
    for name, parts in volumes.items():
        found.append((name, 'volumes', sorted(parts)))
    found.sort(key=lambda source: source[0])
    return found


# archives of other kinds: nothing here can read them, and saying nothing about one that was
# uploaded would look as if its files were simply missing
_OTHER_ARCHIVE = re.compile(r'\.(rar|r\d\d|z\d\d|tar|gz|tgz|bz2|xz|zst|cab|iso|gma|vpk)$', re.I)


def unread_archives(root):
    """files in the repository root that look like archives and are read by nobody"""
    return sorted(name for name in os.listdir(root)
                  if os.path.isfile(os.path.join(root, name)) and _OTHER_ARCHIVE.search(name))


def dropin_destination(path):
    """path in the addon for a file of a drop-in archive, None when it has no place there"""
    parts = [p for p in path.replace("\\", "/").split("/") if p not in ("", ".")]
    if not parts or ".." in parts:
        return None
    lower = [p.lower() for p in parts]
    dest = None
    for i, name in enumerate(lower[:-1]):
        if name in CONTENT_ROOTS:
            dest = lower[i:]
            break
        if name in LUA_ROOTS:
            dest = ["lua"] + lower[i:]
            break
    if dest is None:
        return None
    # packed from inside the materials folder: models/humans/.../shirt.vmt is a material
    if dest[0] == "models" and os.path.splitext(dest[-1])[1] in MATERIAL_TYPES:
        dest = ["materials"] + dest
    return "/".join(dest)


def zip_name(info):
    """name of a zip entry; Windows tools store non-ASCII names in the OEM code page"""
    name = info.filename
    if not info.flag_bits & 0x800:
        try:
            name = name.encode("cp437").decode("cp866")
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
    return name


# ---------------------------------------------------------------------------------------
# Glove families. One entry = one group in the in-game picker.
#   id          - stable internal id; a variant is "<id>_<n>" (networked, never rename)
#   title       - used in the appearance key: "CS:GO <title> NN" (saved in players' appearance
#                 files, never rename either)
#   fingerless  - the wearer's own fingers must stay visible
#   variants    - list of (model, bodygroup "gloves" value, label); the label is only a hint
#                 shown in the picker / catalogue and may be changed freely
#   materials   - optional, {variant number (1-based): {material of the model: material to use
#                 instead}} for a glove whose model does not name its material. Lua swaps it
#                 with Entity:SetSubMaterial (the "mats" of sh_data.lua).
# ---------------------------------------------------------------------------------------
def _same_model(model, labels):
    return [(model, i, label) for i, label in enumerate(labels)]


FAMILIES = [
    dict(id='bloodhound', title='Bloodhound', fingerless=True, variants=_same_model('v_glove_bloodhound', [
        'Leather', 'Charred', 'Snakebite', 'Bronzed', 'Guerrilla'])),
    dict(id='brokenfang', title='Broken Fang', fingerless=True, variants=_same_model('v_glove_bloodhound_fingerless_brokenfang', [
        'Leather', 'Yellow-banded', 'Jade', 'Needle Point', 'Unhinged'])),
    dict(id='hydra', title='Hydra', fingerless=True, variants=_same_model('v_glove_bloodhound_fingerless_hydra', [
        'Emerald', 'Mangrove', 'Rattler', 'Case Hardened'])),
    dict(id='handwrap', title='Hand Wraps', fingerless=True, variants=_same_model('v_glove_handwrap_leathery', [
        'Leather', 'Overprint', 'Constrictor', 'Slaughter', 'Badlands', 'Duct Tape', 'CAUTION!', 'Desert Shamagh',
        'Arboreal', 'Spruce DDPAT', 'Giraffe', 'Cobalt Skulls'])),
    dict(id='fingerless', title='Fingerless', fingerless=True, variants=_same_model('v_glove_fingerless', ['Black leather'])),
    dict(id='moto', title='Moto', fingerless=False, variants=_same_model('v_glove_motorcycle', [
        'Eclipse', 'Spearmint', 'Smoke Out', 'Blood Pressure', 'Finish Line', 'Boom!', '3rd Commando', 'Cool Mint',
        'Transport', 'POW!', 'Polygon', 'Turtle', 'Sand'])),
    dict(id='hardknuckle', title='Hard Knuckle', fingerless=False, variants=[
        ('v_glove_ct_hardknuckle', 0, 'Tan'),
        ('v_glove_ct_hardknuckle_black', 0, 'Black'),
        ('v_glove_ct_hardknuckle_blue', 0, 'Blue')]),
    dict(id='leather', title='Leather', fingerless=False, variants=_same_model('v_glove_fullfinger', ['Black leather'])),
    # The first one is the material the model itself names; CS:GO never sold it, so it has no
    # name there and gets a description, like the plain gloves above.
    dict(id='driver', title='Driver', fingerless=False, variants=_same_model('v_glove_slick', [
        'Tan leather', 'Lunar Weave', 'Crimson Weave', 'Black Tie', 'King Snake', 'Racing Green', 'Queen Jaguar',
        'Diamondback', 'Imperial Plaid', 'Rezan the Red', 'Convoy', 'Overtake', 'Snow Leopard'])),
    # The model has eleven glove variants but only ten pairs of materials: its fifth variant was
    # given the materials of the sixth. The VMTs of the fifth exist, so it gets them from Lua.
    dict(id='specialist', title='Specialist', fingerless=False, variants=_same_model('v_glove_ct_specialist', [
        'Tiger Strike', 'Buckshot', 'Forest DDPAT', 'Mogul', 'Foundation', 'Crimson Web', 'Emerald Web',
        'Lt. Commander', 'Field Agent', 'Marble Fade', 'Crimson Kimono']),
        materials={5: {'glove_specialist_right_6': 'glove_specialist_right_5',
                       'glove_specialist_left_6': 'glove_specialist_left_5'}}),
    dict(id='sport', title='Sport', fingerless=False, variants=_same_model('v_glove_sporty', [
        'Orange', 'Amphibious', 'Superconductor', 'Hedge Maze', 'Vice', 'Omega', 'Scarlet Shamagh',
        'Big Game', 'Bronze Morph', "Pandora's Box", 'Arid', 'Nocts', 'Slingshot'])),
]

# models that have a complete set of glove materials in the archives
MODELS = []
for _fam in FAMILIES:
    for _model, _body, _label in _fam['variants']:
        if _model not in MODELS:
            MODELS.append(_model)
MODEL_EXTS = ['.mdl', '.vvd', '.dx90.vtx']


def variants():
    """flat list of dicts: id, name (appearance key), family, index (1-based), model, body, label,
    fingerless, mats ({material of the model: material used instead}, usually empty)"""
    out = []
    for fam in FAMILIES:
        n = len(fam['variants'])
        swaps = fam.get('materials', {})
        for i, (model, body, label) in enumerate(fam['variants'], 1):
            out.append(dict(
                id='%s_%d' % (fam['id'], i),
                name=('CS:GO %s %02d' % (fam['title'], i)) if n > 1 else 'CS:GO ' + fam['title'],
                family=fam, index=i, model=model, body=body, label=label, fingerless=fam['fingerless'],
                mats=dict(swaps.get(i, {}))))
    return out


def glove_materials(info, variant):
    """materials of a glove as the game sees them: list of (index for Entity:SetSubMaterial,
    name in the model, name that is drawn) for the meshes of its "gloves" body value.
    info is the model as read by mdl_lite; raises ValueError when a swap names a material
    that this glove does not have."""
    gloves = [bp for bp in info['bodyparts'] if bp['name'] == 'gloves'][0]
    used = gloves['models'][variant['body']]['materials']
    names = [info['textures'][i].lower() for i in used]
    for old in variant['mats']:
        if old.lower() not in names:
            raise ValueError('%s: the model has no material "%s" on this glove' % (variant['id'], old))
    swaps = {old.lower(): new.lower() for old, new in variant['mats'].items()}
    return [(index, name, swaps.get(name, name)) for index, name in zip(used, names)]
