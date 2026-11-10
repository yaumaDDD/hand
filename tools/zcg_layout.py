# -*- coding: utf-8 -*-
"""Shared description of how the source archives map onto the addon layout.

Used by build_addon.py (repo root) and by the helper scripts in tools/.
"""

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
