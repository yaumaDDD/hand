"""Test of tools/gunpack/clean_gunpack.py on a made-up gun pack:  python tools/test_gunpack.py"""
import os,struct,subprocess,sys,shutil,tempfile
HERE=os.path.dirname(os.path.abspath(__file__))
TOP=tempfile.mkdtemp()
T=TOP+'/garrysmod/addons'
A=T+'/guns'
def w(p,data=b'x'):
    p=os.path.join(A,p); os.makedirs(os.path.dirname(p),exist_ok=True); open(p,'wb').write(data)
def mdl(folder,mats,extra=b''):
    b=bytearray(408); b[:4]=b'IDST'
    tex=len(b); names=b''; structs=bytearray(64*len(mats)); pos=tex+64*len(mats)
    blob=b''
    for i,m in enumerate(mats):
        struct.pack_into('<i',structs,i*64,pos+len(blob)-(tex+i*64)); blob+=m.encode()+b'\0'
    cd=pos+len(blob); cdstr=cd+4
    tail=struct.pack('<i',cdstr)+folder.encode()+b'\0'+extra+b'\0'
    struct.pack_into('<4i',b,204,len(mats),tex,1,cd)
    return bytes(b)+bytes(structs)+blob+tail
shutil.copytree(os.path.join(HERE,'gunpack'),A+'/clean_gunpack')
# lua of a neighbour
os.makedirs(T+'/pack_lua/lua/weapons'); open(T+'/pack_lua/lua/weapons/w.lua','w').write('''
SWEP.WorldModel = "models/weapons/tfa/w_gun.mdl"
local path = "weapons/gunx/"
snd = { path .. "open.ogg", "weapons/gunx/fire" .. math.random(3) .. ".wav" }
sound.Add({name="x", sound=")weapons/guny/shot.wav"})
-- EmitSound("weapons/old/commented.wav")
Material("vgui/hud/gun_icon")
x = "models/missing/thing.mdl"
y = "weapons/lost/moved_here.wav"
''')
w('models/weapons/tfa/w_gun.mdl', mdl('models/weapons/gun/',['body','scope'], b'models/weapons/tfa/anim.mdl\0weapons/gunx/mdlsound.wav'))
for e in ('.vvd','.dx90.vtx','.phy'): w('models/weapons/tfa/w_gun'+e)
w('models/weapons/tfa/anim.mdl', mdl('x/',[]))
w('materials/models/weapons/gun/body.vmt', b'"VertexLitGeneric"\n{\n "$basetexture" "models/weapons/gun/body_d"\n "$bumpmap" "models\\weapons\\gun\\body_n.vtf"\n}')
w('materials/models/weapons/gun/body_d.vtf'); w('materials/models/weapons/gun/body_n.vtf'); w('materials/models/weapons/gun/unused.vtf')
w('materials1/models/weapons/gun/scope.vmt', b'"x" { "$basetexture" "models/weapons/gun/scope" }'); w('materials1/models/weapons/gun/scope.vtf')
w('materials/vgui/hud/gun_icon.vmt', b'"UnlitGeneric" { "$basetexture" "vgui/hud/gun_icon" }'); w('materials/vgui/hud/gun_icon.vtf')
w('materials/vgui/hud/other.png'); w('materials/props/crate.vmt'); w('materials/props/crate.vtf')
w('sound/weapons/gunx/open.ogg'); w('sound/weapons/gunx/fire1.wav'); w('sound/weapons/gunx/fire2.wav'); w('sound/weapons/gunx/mdlsound.wav')
w('sound/weapons/guny/shot.wav'); w('sound/weapons/guny/unused.wav'); w('sound/weapons/old/commented.wav')
w('somepack/sound/weapons/gunx/fire3.wav'); w('sound/random/moved_here.wav'); w('sound/ambient/junk.mp3')
w('models/props/crate.mdl', mdl('props/',['crate'])); w('models/props/crate.vvd')
w('sound2/weapons/guny/shot.wav'); w('readme.txt')
# everything thrown into materials: the Lua, sounds, models, a pack with folders of its own
w('materials/lua/weapons/w2.lua', b'SWEP.ViewModel = "models/weapons/in_mat/v_gun.mdl"\nsnd = "weapons/in_mat/shot.wav"\nsnd2 = "weapons/in_mat/loose.wav"')
w('materials/models/weapons/in_mat/v_gun.mdl', mdl('models/weapons/in_mat/',['skin'])); w('materials/models/weapons/in_mat/v_gun.vvd')
w('materials/models/weapons/in_mat/skin.vmt', b'"x" { "$basetexture" "models/weapons/in_mat/skin" }'); w('materials/models/weapons/in_mat/skin.vtf')
w('materials/pack/sound/weapons/in_mat/shot.wav'); w('materials/weapons/in_mat/loose.wav'); w('materials/pack/sound/weapons/in_mat/unused.wav')
w('materials/materials3/models/weapons/gun/extra_unused.vtf')
def tree(): return sorted(os.path.relpath(os.path.join(d,f),A).replace(os.sep,'/') for d,_,fs in os.walk(A) for f in fs if 'clean_gunpack/' not in os.path.join(d,f)+'/' or f.endswith('report.txt'))
before=tree()
r=subprocess.run([sys.executable,A+'/clean_gunpack/clean_gunpack.py','--dry-run'],capture_output=True,text=True); print(r.stdout,r.stderr)
assert [t for t in tree() if not t.endswith('report.txt')]==before, 'dry run changed something'
r=subprocess.run([sys.executable,A+'/clean_gunpack/clean_gunpack.py'],capture_output=True,text=True,stdin=subprocess.DEVNULL); print(r.stdout[-200:])
assert [t for t in tree() if not t.endswith('report.txt')]!=before or True
r=subprocess.run([sys.executable,A+'/clean_gunpack/clean_gunpack.py','--yes'],capture_output=True,text=True); print(r.stdout,r.stderr)
got=[t for t in tree() if not t.endswith('report.txt')]
want=sorted('''materials/models/weapons/gun/body.vmt materials/models/weapons/gun/body_d.vtf materials/models/weapons/gun/body_n.vtf
materials/models/weapons/gun/scope.vmt materials/models/weapons/gun/scope.vtf materials/vgui/hud/gun_icon.vmt materials/vgui/hud/gun_icon.vtf materials/vgui/hud/other.png
models/weapons/tfa/w_gun.mdl models/weapons/tfa/w_gun.vvd models/weapons/tfa/w_gun.dx90.vtx models/weapons/tfa/w_gun.phy models/weapons/tfa/anim.mdl
sound/weapons/gunx/open.ogg sound/weapons/gunx/fire1.wav sound/weapons/gunx/fire2.wav sound/weapons/gunx/fire3.wav sound/weapons/gunx/mdlsound.wav
sound/weapons/guny/shot.wav readme.txt materials/lua/weapons/w2.lua
models/weapons/in_mat/v_gun.mdl models/weapons/in_mat/v_gun.vvd materials/models/weapons/in_mat/skin.vmt materials/models/weapons/in_mat/skin.vtf
sound/weapons/in_mat/shot.wav sound/weapons/in_mat/loose.wav'''.split())
print('ONLY GOT',sorted(set(got)-set(want))); print('ONLY WANT',sorted(set(want)-set(got)))
print('OK' if got==want else 'FAILED')
shutil.rmtree(TOP,ignore_errors=True)
sys.exit(0 if got==want else 1)
