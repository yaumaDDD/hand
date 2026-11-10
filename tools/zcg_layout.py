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

# archive (without .7z) -> list of (folder inside the archive, destination)
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
}

# ---------------------------------------------------------------------------------------
# Glove families. One entry = one group in the in-game picker.
#   id          - stable internal id; a variant is "<id>_<n>" (networked, never rename)
#   title       - used in the appearance key: "CS:GO <title> NN" (saved in players' appearance
#                 files, never rename either)
#   fingerless  - the wearer's own fingers must stay visible
#   variants    - list of (model, bodygroup "gloves" value, label); the label is only a hint
#                 shown in the picker / catalogue and may be changed freely
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
]

# models that have a complete set of glove materials in the archives
MODELS = []
for _fam in FAMILIES:
    for _model, _body, _label in _fam['variants']:
        if _model not in MODELS:
            MODELS.append(_model)
MODEL_EXTS = ['.mdl', '.vvd', '.dx90.vtx']


def variants():
    """flat list of dicts: id, name (appearance key), family, index (1-based), model, body, label, fingerless"""
    out = []
    for fam in FAMILIES:
        n = len(fam['variants'])
        for i, (model, body, label) in enumerate(fam['variants'], 1):
            out.append(dict(
                id='%s_%d' % (fam['id'], i),
                name=('CS:GO %s %02d' % (fam['title'], i)) if n > 1 else 'CS:GO ' + fam['title'],
                family=fam, index=i, model=model, body=body, label=label, fingerless=fam['fingerless']))
    return out
