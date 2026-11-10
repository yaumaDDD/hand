-- Z-City CS:GO gloves - drawing the gloves on players and their ragdolls.
--
-- Z-City draws every player / ragdoll through hg.renderOverride:
--     DrawPlayerRagdoll(ent, owner)        ent:SetupBones(), then the arms are moved onto the
--                                          weapon by writing bone matrices (TPIK)
--     CoolPostDrawAppearance(ent, owner)   hook, right before ent:DrawModel()
--     ent:DrawModel()
--     PostDrawAppearance(ent, owner)       hook, right after it
--
-- Everything here happens in the first hook, where Z-City itself draws whatever sits on the arms
-- (armour, bandages, tourniquets): at that moment the bone matrices of the wearer hold exactly
-- the pose it is about to be drawn with. Version 1.0.0 drew a bone-merged glove in the second
-- hook and the glove did not get that pose: it hung in the air where the animation alone would
-- have put the hands.
--
-- The glove is a clientside model made for the c_hands skeleton, which uses the same bone names
-- as a player model. By default ("zcg_bonemerge 0") every bone of the glove is set by hand to the
-- matrix of the wearer's bone of the same name, so the glove cannot be anywhere else than on the
-- hands that get drawn. "zcg_bonemerge 1" leaves that to the engine (EF_BONEMERGE) instead.
--
-- In the same hook the wearer's own hands are hidden, because they would poke through the glove -
-- but only while a glove really is drawn over them. A fingerless glove is then drawn with fingers
-- of its own: every glove model contains the bare CS:GO arm it was made for, the build of this
-- addon cuts that arm down to the fingers (tools/patch_models.py), and here they get their skin.

local ZCG = ZCGloves
local Config = ZCG.Config

local IsValid = IsValid
local RealTime = RealTime

local cvEnable = CreateClientConVar("zcg_enable", "1", true, false,
	"CS:GO gloves: 0 = do not draw the gloves on this client.", 0, 1)
local cvBonemerge = CreateClientConVar("zcg_bonemerge", "0", true, false,
	"CS:GO gloves: 0 = the addon puts the glove bones on the hand bones itself (default), "
	.. "1 = the engine does it (EF_BONEMERGE). Try the other value if the gloves are not on the hands.", 0, 1)

-- ---------------------------------------------------------------------------------------------
-- the "draw nothing" material
-- ---------------------------------------------------------------------------------------------
local hideMaterial

function ZCG.HideMaterial()
	if hideMaterial then return hideMaterial end
	if isstring(Config.HideMaterial) and Config.HideMaterial ~= "" then
		hideMaterial = Config.HideMaterial
	else
		-- Z-City itself hides sub-materials with "null"; fall back to our own material without it
		local mat = Material("null")
		if mat and not mat:IsError() then
			hideMaterial = "null"
		else
			hideMaterial = "zcity_csgo_gloves/invisible"
		end
	end
	return hideMaterial
end

-- ---------------------------------------------------------------------------------------------
-- the skin of the fingers inside the fingerless glove models
-- ---------------------------------------------------------------------------------------------
local fingerSkin = { checked = -1000 } -- name: the material, once it is known to be there; tint

-- name of the material, nil while it is not installed on this client (looked for every 10 s)
function ZCG.FingerMaterial()
	if fingerSkin.name then return fingerSkin.name end
	local now = RealTime()
	if now - fingerSkin.checked < 10 then return nil end
	fingerSkin.checked = now

	local name = Config.FingerMaterial
	if not isstring(name) or name == "" then return nil end
	-- ("!name" is a material made by Lua: no file to look for)
	if string.sub(name, 1, 1) ~= "!" and not file.Exists("materials/" .. name .. ".vmt", "GAME") then return nil end

	fingerSkin.name = name
	if isvector(Config.FingerTint) then ZCG.SetFingerTint(Config.FingerTint) end
	return name
end

-- Multiplies the skin with a colour (a Vector, 1 1 1 = as it is) on this client.
-- Returns false when the material is not installed.
function ZCG.SetFingerTint(tint)
	local name = ZCG.FingerMaterial()
	if not name then return false end
	local mat = Material(name)
	if not mat or mat:IsError() then return false end
	mat:SetVector("$color2", tint)
	fingerSkin.tint = tint
	return true
end

-- ---------------------------------------------------------------------------------------------
-- is the content (models) installed on this client?
-- ---------------------------------------------------------------------------------------------
local content = {} -- model path -> { ok = bool, time = last check }
local warned = false

function ZCG.HasModel(path)
	local now = RealTime()
	local state = content[path]
	if state and (state.ok or now - state.time < 10) then return state.ok end

	local ok = file.Exists(path, "GAME")
	content[path] = { ok = ok, time = now }
	if not ok and not warned then
		warned = true
		ZCG.Print("the glove models are not installed on this client (" .. path .. "), gloves will not be drawn. "
			.. "Install the addon content or ask the server owner to set Config.WorkshopID.")
	end
	return ok
end

-- ---------------------------------------------------------------------------------------------
-- are the models on this client the ones this version was built with?
-- ---------------------------------------------------------------------------------------------
-- Up to version 1.0.1 the models were shipped with the whole bare arm in them, and nothing
-- replaces them when only a part of the addon is updated (the Lua files come from the server
-- anyway, and FastDL never downloads a file a second time). Skin on such a model would show a
-- second pair of arms. The build notes where in the .dx90.vtx file the first triangle it removed
-- is stored (ZCG.Models[path].cut): a removed triangle has the same corner three times.
local armRemoved = {} -- model path -> true / false, once the file could be looked at

function ZCG.ArmRemoved(path)
	local known = armRemoved[path]
	if known ~= nil then return known end
	if not ZCG.HasModel(path) then return false end -- (asked again when the model is there)

	local ok = true -- a file that cannot be read is given the benefit of the doubt
	local info = ZCG.Models[path]
	local f = info and info.cut and file.Open(string.sub(path, 1, -5) .. ".dx90.vtx", "rb", "GAME")
	if f then
		f:Seek(info.cut)
		local data = f:Read(6)
		f:Close()
		if isstring(data) and #data == 6 then
			local a1, a2, b1, b2, c1, c2 = string.byte(data, 1, 6)
			ok = a1 == b1 and a2 == b2 and a1 == c1 and a2 == c2
		end
	end
	armRemoved[path] = ok
	if not ok then
		ZCG.Print("the glove models on this client are from an older version of the addon (" .. path .. "): "
			.. "fingerless gloves are drawn without their own fingers. Install the whole addon again "
			.. "(or delete garrysmod/download/models/zcity_csgo_gloves if the server sent the files).")
	end
	return ok
end

-- ---------------------------------------------------------------------------------------------
-- the wearer's own hands
-- ---------------------------------------------------------------------------------------------
local handsSlots = {} -- lower-case model path -> sub-material index (0-based) or false

-- index for Entity:SetSubMaterial of the material that covers the hands, nil if unknown
function ZCG.HandsSlot(ent)
	local model = ent:GetModel()
	if not model then return nil end
	model = string.lower(model)

	local slot = handsSlots[model]
	if slot ~= nil then return slot or nil end

	local materials = ent:GetMaterials()
	if not materials or #materials == 0 then return nil end -- model not loaded yet, ask again later

	local wanted = ZCG.HandsMaterialName(model)
	slot = false
	for i = 1, #materials do
		if string.lower(materials[i]) == wanted then
			slot = i - 1
			break
		end
	end
	if slot and slot > 31 then slot = false end -- Entity:SetSubMaterial only reaches 0..31

	handsSlots[model] = slot
	return slot or nil
end

-- ---------------------------------------------------------------------------------------------
-- per entity state
-- ---------------------------------------------------------------------------------------------
-- state = {
--   variant          glove decided by the draw hook
--   seen             RealTime of the last attempt to draw
--   drawn, why       was the glove drawn at that attempt; if not, the reason (for zcg_debug)
--   mdl, path, body  clientside glove model, its model path and current "gloves" body value
--   skin             material on what is left of the bare arm in that model: the skin of the
--                    fingers, or the "draw nothing" material
--   merge            the model was set up for zcg_bonemerge 1
--   copied, total    bones taken from the wearer / bones of the glove (zcg_bonemerge 0)
--   hide             { slot, old } while this addon hides the wearer's hands
--   probe            zcg_debug asked for a bone report at the next draw
-- }
local states = {}
ZCG.States = states

local function getState(ent)
	local state = states[ent]
	if not state then
		state = {}
		states[ent] = state
	end
	return state
end

local function removeModel(state)
	if IsValid(state.mdl) then state.mdl:Remove() end
	state.mdl, state.path, state.body, state.merge, state.skin = nil, nil, nil, nil, nil
	state.drawn = false
end

-- Give the hands back. The value is only touched while it still is our "invisible" material:
-- when the server changed it in the meantime, the new value has already replaced ours.
local function unhide(ent, state)
	local hidden = state.hide
	if not hidden then return end
	state.hide = nil

	if not IsValid(ent) then return end
	if ent:GetSubMaterial(hidden.slot) ~= ZCG.HideMaterial() then return end
	if hidden.old ~= "" then
		ent:SetSubMaterial(hidden.slot, hidden.old)
	else
		ent:SetSubMaterial(hidden.slot, nil)
	end
end

-- Checked every frame: the server networks its own value whenever the appearance is applied
-- again, which silently replaces ours.
local function hide(ent, state, slot)
	local hidden = state.hide
	if hidden and hidden.slot ~= slot then
		unhide(ent, state) -- the model changed and the hands moved to another slot
	end

	local invisible = ZCG.HideMaterial()
	local current = ent:GetSubMaterial(slot) or ""
	if current ~= invisible then
		state.hide = { slot = slot, old = current }
		ent:SetSubMaterial(slot, invisible)
	end
end

function ZCG.RestoreAll()
	for ent, state in pairs(states) do
		unhide(ent, state)
		removeModel(state)
		states[ent] = nil
	end
end

-- ---------------------------------------------------------------------------------------------
-- the glove model
-- ---------------------------------------------------------------------------------------------
local function gloveModel(ent, state, variant, fingers)
	local merge = cvBonemerge:GetBool()
	local mdl = state.mdl
	if mdl and (not IsValid(mdl) or state.path ~= variant.model or state.merge ~= merge) then
		removeModel(state)
		mdl = nil
	end

	local info = ZCG.Models[variant.model]

	if not mdl then
		mdl = ClientsideModel(variant.model, RENDERGROUP_OPAQUE)
		if not IsValid(mdl) then return nil end

		mdl:SetNoDraw(true) -- drawn by hand, in step with its wearer
		mdl:DrawShadow(false)

		mdl:SetBodygroup(info.sleeves, 0) -- the models also contain CS:GO sleeves
		state.mdl, state.path, state.body, state.merge, state.skin = mdl, variant.model, nil, merge, nil
	end

	if state.body ~= variant.body then
		mdl:SetBodygroup(info.gloves, variant.body)
		state.body = variant.body
	end

	-- What the build left of the bare arm inside the model - the fingers of a fingerless glove,
	-- nothing at all in the other ones - has a material of its own. The fingers get their skin
	-- when the glove replaces the wearer's hands and are not drawn otherwise.
	local skin = fingers and ZCG.FingerMaterial() or ZCG.HideMaterial()
	if state.skin ~= skin then
		for _, index in ipairs(info.bare) do
			mdl:SetSubMaterial(index, skin)
		end
		state.skin = skin
	end

	-- zcg_bonemerge 1 only; otherwise the model has no parent and its bones are written by hand
	if merge and mdl:GetParent() ~= ent then
		mdl:SetPos(ent:GetPos())
		mdl:SetParent(ent)
		mdl:AddEffects(EF_BONEMERGE)
	end

	return mdl
end

-- ---------------------------------------------------------------------------------------------
-- zcg_bonemerge 0: every bone of the glove is put on the wearer's bone of the same name
-- ---------------------------------------------------------------------------------------------
local INVALID_BONE = "__INVALIDBONE__" -- Entity:SetBoneMatrix on such a bone is an error pcall cannot catch
local L_HAND, R_HAND = "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Hand"
local CHEST = "ValveBiped.Bip01_Spine4"
-- The cuff of a glove hangs on the twist helper of the forearm, which not every player model
-- has. Without it: the rotation of the forearm at the place of the hand.
local WRISTS = {
	["ValveBiped.Bip01_L_Wrist"] = "ValveBiped.Bip01_L_Forearm",
	["ValveBiped.Bip01_R_Wrist"] = "ValveBiped.Bip01_R_Forearm",
}

local ANGLE_ZERO = Angle(0, 0, 0)
local LIGHT_OFFSET = Vector(0, 0, 31) -- $illumposition of the glove models: where their lighting is taken
local SCALE_GONE = Vector(0.01, 0.01, 0.01)
local IDENTITY = Matrix()

local skeletons = {} -- glove model path -> bone names, parents, ...
local bonemaps = {} -- glove model path -> wearer model path -> wearer bone for every glove bone

-- A clientside model that was never drawn may not hand out its bones yet. Drawing it once,
-- fully transparent, loads everything; the glove appears a frame later.
local function notReady(mdl, why)
	local blend = render.GetBlend()
	render.SetBlend(0)
	mdl:DrawModel()
	render.SetBlend(blend)
	return false, why
end

local function readSkeleton(mdl, path)
	local skeleton = skeletons[path]
	if skeleton then return skeleton end

	mdl:SetupBones() -- a clientside model has no bones before this
	local count = mdl:GetBoneCount() or 0
	if count <= 0 then return nil end

	local names, parents, index = {}, {}, {}
	for i = 0, count - 1 do
		local name = mdl:GetBoneName(i)
		if not name or name == INVALID_BONE then return nil end -- not loaded yet: asked again in the next frame
		names[i], parents[i], index[name] = name, mdl:GetBoneParent(i) or -1, i
	end

	local left, right = index[L_HAND], index[R_HAND]
	local side, finger, wrists = {}, {}, {}
	for i = 0, count - 1 do
		local name = names[i]
		side[i] = string.find(name, "_L_", 1, true) and 1 or string.find(name, "_R_", 1, true) and 2 or 0

		-- below a hand: the bones that carry the glove itself
		local parent = parents[i]
		finger[i] = parent >= 0 and parent < i and (parent == left or parent == right or finger[parent]) or false

		local forearm = WRISTS[name]
		if forearm then
			forearm = index[forearm]
			wrists[i] = forearm and forearm < i and forearm or false
		end
	end

	skeleton = { count = count, names = names, parents = parents, left = left, right = right,
		side = side, finger = finger, wrists = wrists }
	skeletons[path] = skeleton
	return skeleton
end

local function boneMap(ent, skeleton, path)
	local model = ent:GetModel()
	if not model then return nil end

	local maps = bonemaps[path]
	if not maps then
		maps = {}
		bonemaps[path] = maps
	end

	local map = maps[model]
	-- a model without hand bones may simply not be loaded yet: it is asked again once a second
	if map and (map.usable or RealTime() < map.again) then return map end

	local names, finger = skeleton.names, skeleton.finger
	local bones, copied, needBind = {}, 0, false
	for i = 0, skeleton.count - 1 do
		local bone = ent:LookupBone(names[i])
		if bone then
			bones[i] = bone
			copied = copied + 1
		else
			bones[i] = false
			if finger[i] then needBind = true end
		end
	end

	map = {
		bones = bones, copied = copied, needBind = needBind,
		left = skeleton.left and bones[skeleton.left] or nil,
		right = skeleton.right and bones[skeleton.right] or nil,
		chest = ent:LookupBone(CHEST) or nil,
		again = RealTime() + 1,
	}
	map.usable = (map.left or map.right) and true or false
	maps[model] = map
	return map
end

-- The pose the glove model has on its own, every bone relative to its parent. Only needed for
-- finger bones a wearer does not have, and only right after SetupBones gives the right answer.
local function readBind(mdl, skeleton)
	local world = {}
	for i = 0, skeleton.count - 1 do
		local matrix = mdl:GetBoneMatrix(i)
		if not matrix then return nil end
		world[i] = matrix
	end

	local bind = {}
	for i = 0, skeleton.count - 1 do
		local parent = world[skeleton.parents[i]]
		if parent then bind[i] = parent:GetInverseTR() * world[i] end
	end
	return bind
end

local placed = {} -- scratch: the matrix chosen for every glove bone during one call

-- Returns true, or false and the reason.
local function poseGlove(ent, mdl, state)
	local path = state.path
	local skeleton = readSkeleton(mdl, path)
	if not skeleton then return notReady(mdl, "the glove model has no bones yet") end

	local map = boneMap(ent, skeleton, path)
	if not map or not map.usable then return false, "the wearer's model has no hand bones" end

	local left = map.left and ent:GetBoneMatrix(map.left) or nil
	local right = map.right and ent:GetBoneMatrix(map.right) or nil
	if not left and not right then return false, "the wearer's bones are not set up" end

	-- The bones are placed one by one below. The entity itself only decides where the lighting
	-- is taken: at the wearer's chest, where a bone-merged model would take it too.
	local chest = map.chest and ent:GetBoneMatrix(map.chest) or right or left
	mdl:SetAngles(ANGLE_ZERO)
	mdl:SetPos(chest:GetTranslation() - LIGHT_OFFSET)

	-- Makes the bones writable for this frame. Whatever was written earlier is gone after it.
	mdl:SetupBones()
	local count = skeleton.count
	if mdl:GetBoneCount() ~= count then return notReady(mdl, "the glove model has no bones yet") end

	local bind = skeleton.bind
	if map.needBind and not bind then
		bind = readBind(mdl, skeleton) -- before anything is written
		if not bind then return notReady(mdl, "the glove model has no bone matrices yet") end
		skeleton.bind = bind
	end

	local gone -- the glove of a hand the wearer does not have is shrunk to nothing
	if not (left and right) then
		gone = Matrix()
		gone:SetScale(SCALE_GONE)
		gone:SetTranslation((left or right):GetTranslation())
	end

	local names, parents, bones = skeleton.names, skeleton.parents, map.bones
	local side, wrists = skeleton.side, skeleton.wrists
	for i = 0, count - 1 do
		local matrix
		local hand = side[i] == 1 and left or side[i] == 2 and right or nil
		if side[i] ~= 0 and not hand then
			matrix = gone
		else
			-- the wearer's own bone, as it is: an amputated arm (scaled to nothing) takes its glove along
			local source = bones[i]
			if source then matrix = ent:GetBoneMatrix(source) end

			if not matrix then
				local forearm = wrists[i]
				if forearm ~= nil then
					forearm = forearm and placed[forearm] or nil
					matrix = (forearm or hand) * IDENTITY -- a copy
					matrix:SetTranslation(hand:GetTranslation())
				else
					local parent = parents[i]
					parent = parent >= 0 and parent < i and placed[parent] or nil
					if parent and bind and bind[i] then matrix = parent * bind[i] end
				end
			end
		end

		placed[i] = matrix or false
		-- (a bone nothing could be found for stays where SetupBones put it; none of them carries a glove)
		if matrix and mdl:GetBoneName(i) == names[i] then mdl:SetBoneMatrix(i, matrix) end
	end

	state.copied, state.total = map.copied, count
	return true
end

-- zcg_debug: where are the hand bones of the glove and of its wearer at the moment of drawing?
-- Returns where the glove's hand bones are, to compare with where they are after the draw.
local function reportBones(ent, mdl, state)
	print("[CS:GO Gloves] hand bones at the moment of drawing (zcg_bonemerge " .. (state.merge and 1 or 0) .. "):")
	local before = {}
	for _, name in ipairs({ L_HAND, R_HAND }) do
		local theirs, ours = ent:LookupBone(name), mdl:LookupBone(name)
		local a = theirs and ent:GetBoneMatrix(theirs)
		local b = ours and mdl:GetBoneMatrix(ours)
		if a and b then
			local pa, pb = a:GetTranslation(), b:GetTranslation()
			before[name] = pb
			print(string.format("  %s: wearer (%.1f %.1f %.1f), glove (%.1f %.1f %.1f), %.2f apart",
				name, pa.x, pa.y, pa.z, pb.x, pb.y, pb.z, pa:Distance(pb)))
		else
			print("  " .. name .. ": wearer bone " .. tostring(theirs) .. (a and "" or " (no matrix)")
				.. ", glove bone " .. tostring(ours) .. (b and "" or " (no matrix)"))
		end
	end
	return before
end

-- ... and did the engine draw the glove with these bones, or work out its own?
local function reportDrawn(mdl, before)
	local moved = false
	for name, was in pairs(before) do
		local bone = mdl:LookupBone(name)
		local now = bone and mdl:GetBoneMatrix(bone)
		local far = now and now:GetTranslation():Distance(was) or -1
		if far < 0 or far > 0.01 then
			moved = true
			print(string.format("  %s: the engine MOVED this glove bone while drawing (%.2f units) - please report this", name, far))
		end
	end
	if not moved then print("  the glove was drawn with exactly these bones") end
end

-- Draws a glove on any entity with a ValveBiped skeleton (players, ragdolls, the model of the
-- appearance editor). The glove takes the pose the entity's bones have at this very moment:
-- call it where the entity is drawn. fingers = true: a fingerless glove is drawn with the fingers
-- of its model (only useful when the entity's own hands are hidden, see ZCG.Wearing).
-- Returns true when the glove was drawn.
function ZCG.DrawGlove(ent, variant, fingers)
	local state = getState(ent)
	state.seen = RealTime()
	state.drawn = false

	if not ZCG.HasModel(variant.model) then
		state.why = "the glove model is not installed"
		return false
	end
	local mdl = gloveModel(ent, state, variant, fingers)
	if not mdl then
		state.why = "the glove model could not be created"
		return false
	end

	if state.merge then
		mdl:SetupBones() -- merge now, with the pose the wearer has just been given
	else
		local ok, why = poseGlove(ent, mdl, state)
		if not ok then
			state.why = why
			return false
		end
	end

	local probe
	if state.probe then
		state.probe = nil
		local ok, result = pcall(reportBones, ent, mdl, state)
		if ok then probe = result else print("[CS:GO Gloves] bone report failed: " .. tostring(result)) end
	end

	local r, g, b = render.GetColorModulation()
	render.SetColorModulation(1, 1, 1) -- the wearer's player colour must not tint the glove
	mdl:DrawModel()
	render.SetColorModulation(r, g, b)

	if probe then
		local ok, err = pcall(reportDrawn, mdl, probe)
		if not ok then print("[CS:GO Gloves] bone report failed: " .. tostring(err)) end
	end

	state.drawn, state.why = true, nil
	return true
end

-- removes the glove model of an entity that stopped wearing gloves outside of the hooks below
function ZCG.ClearGlove(ent)
	local state = states[ent]
	if not state then return end
	unhide(ent, state)
	removeModel(state)
	states[ent] = nil
end

-- ---------------------------------------------------------------------------------------------
-- which glove does an entity wear?
-- ---------------------------------------------------------------------------------------------
local NW = "zcg_glove"

-- zcg_preview: a glove forced on the local player, on this client only (for testing)
ZCG.LocalOverride = ZCG.LocalOverride or nil

function ZCG.GloveOf(ent)
	local override = ZCG.LocalOverride
	if override then
		local me = LocalPlayer()
		if ent == me or (not ent:IsPlayer() and ent:GetNWEntity("ply") == me) then return override end
	end

	local id = ent:GetNWString(NW, "")
	if id == "" and not ent:IsPlayer() then
		-- a fresh ragdoll whose own string has not arrived yet: ask its (living) owner
		local owner = ent:GetNWEntity("ply")
		if IsValid(owner) and owner:IsPlayer() then id = owner:GetNWString(NW, "") end
	end
	if id == "" or id == "none" then return nil end
	return ZCG.ByID[id]
end

local function armsGone(ent)
	local organism = ent.new_organism or ent.organism
	return istable(organism) and organism.larmamputated and organism.rarmamputated
end

-- What a glove does to the hands of its wearer. Returns the sub-material slot of the hands
-- that the glove hides (nil: they stay), and whether the glove is drawn with its own fingers.
-- A fingerless glove hides the hands only when it can show fingers instead, and shows them only
-- when it can hide the hands: two sets of fingers in one glove would be worse than either.
function ZCG.Wearing(ent, variant)
	if not ZCG.HidesHands(variant) then return nil, false end
	if variant.fingerless and not (ZCG.FingerMaterial() and ZCG.ArmRemoved(variant.model)) then return nil, false end
	local slot = ZCG.HandsSlot(ent)
	if not slot then return nil, false end
	return slot, variant.fingerless and true or false
end

-- ---------------------------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------------------------
local function drawHook(ent)
	if not IsValid(ent) then return end

	local state = states[ent]
	local variant = cvEnable:GetBool() and ZCG.GloveOf(ent) or nil
	if variant and armsGone(ent) then variant = nil end

	if not variant then
		if state then
			state.variant = nil
			unhide(ent, state)
		end
		return
	end

	state = state or getState(ent)
	state.variant = variant

	-- The glove first: the hands are only hidden while a glove really is drawn over them.
	local slot, fingers = ZCG.Wearing(ent, variant)
	if ZCG.DrawGlove(ent, variant, fingers) and slot then
		hide(ent, state, slot)
	else
		unhide(ent, state)
	end
end

-- A mistake in here would otherwise be repeated for every player in every frame.
local failures = 0
local function guarded(func)
	return function(ent)
		if failures >= 5 then return end
		local ok, err = pcall(func, ent)
		if ok then return end
		failures = failures + 1
		ErrorNoHalt("[CS:GO Gloves] " .. tostring(err) .. "\n")
		if failures >= 5 then
			ZCG.Print("drawing was switched off after repeated errors, please report them.")
			pcall(ZCG.RestoreAll)
		end
	end
end

hook.Add("CoolPostDrawAppearance", "zcg_gloves", guarded(drawHook))
hook.Remove("PostDrawAppearance", "zcg_gloves") -- 1.0.0 drew there; matters when the file is reloaded

-- housekeeping: entities that left, gloves nobody looked at for a while
timer.Create("zcg_housekeeping", 1, 0, function()
	local now = RealTime()
	for ent, state in pairs(states) do
		if not IsValid(ent) then
			removeModel(state)
			states[ent] = nil
		else
			local idle = now - (state.seen or 0)
			-- hands are only kept hidden while the glove is really being drawn over them
			if idle > 1 then unhide(ent, state) end
			if idle > 15 then
				removeModel(state)
				if not state.hide then states[ent] = nil end
			end
		end
	end
end)

cvars.AddChangeCallback("zcg_enable", function(_, _, new)
	if tonumber(new) == 0 then ZCG.RestoreAll() end
end, "zcg_gloves")

-- ---------------------------------------------------------------------------------------------
-- console commands for testing
-- ---------------------------------------------------------------------------------------------
concommand.Add("zcg_preview", function(_, _, args)
	local id = string.lower(args[1] or "")
	if id == "" then
		ZCG.Print("usage: zcg_preview <id>  (shows a glove on yourself, on this client only), zcg_preview off")
		local ids = {}
		for _, variant in ipairs(ZCG.Variants) do ids[#ids + 1] = variant.id end
		print(table.concat(ids, " "))
		return
	end
	if id == "off" or id == "none" or id == "0" then
		ZCG.LocalOverride = nil
		ZCG.Print("preview off")
		return
	end
	local variant = ZCG.ByID[id]
	if not variant then
		ZCG.Print("unknown glove id: " .. id)
		return
	end
	ZCG.LocalOverride = variant
	ZCG.Print("preview: " .. variant.name .. " (" .. variant.label .. ")")
end, function(cmd, argStr)
	local typed = string.lower(string.Trim(argStr or ""))
	local out = {}
	for _, variant in ipairs(ZCG.Variants) do
		if string.sub(variant.id, 1, #typed) == typed then out[#out + 1] = cmd .. " " .. variant.id end
	end
	out[#out + 1] = cmd .. " off"
	return out
end, "CS:GO gloves: show a glove on yourself (this client only). zcg_preview <id> / zcg_preview off")

concommand.Add("zcg_finger_tint", function(_, _, args)
	local r, g, b = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
	if r and not args[2] then g, b = r, r end -- one number: all three
	if not (r and g and b) then
		ZCG.Print("usage: zcg_finger_tint <red> <green> <blue>   (1 1 1 = the skin as it is, 0.8 0.8 0.8 = darker)")
		return
	end
	r, g, b = math.Clamp(r, 0, 4), math.Clamp(g, 0, 4), math.Clamp(b, 0, 4)
	if not ZCG.SetFingerTint(Vector(r, g, b)) then
		ZCG.Print("the skin of the glove fingers (" .. tostring(Config.FingerMaterial) .. ") is not installed on this client")
		return
	end
	ZCG.Print(string.format("finger tint %.2f %.2f %.2f on this client until the game is restarted. To keep it for everybody: "
		.. "FingerTint = Vector(%.2f, %.2f, %.2f) in lua/zcity_csgo_gloves/sh_config.lua", r, g, b, r, g, b))
end, nil, "CS:GO gloves: try a colour for the skin of the glove fingers (this client only). zcg_finger_tint <r> <g> <b>")

concommand.Add("zcg_debug", function()
	local me = LocalPlayer()
	local ent = me
	local target = me:GetEyeTrace().Entity
	if IsValid(target) and (target:IsPlayer() or target:IsRagdoll()) then ent = target end
	if ent == me and IsValid(me.FakeRagdoll) then ent = me.FakeRagdoll end

	local model = ent:GetModel() or "?"
	local variant = ZCG.GloveOf(ent)
	local slot = ZCG.HandsSlot(ent)
	local state = states[ent]

	print("[CS:GO Gloves] version " .. ZCG.Version)
	print("  registered in Z-City : " .. tostring(ZCG.Ready == true))
	print("  zcg_enable " .. cvEnable:GetString() .. ", zcg_bonemerge " .. cvBonemerge:GetString()
		.. ", zcg_hide_hands " .. ZCG.cvHideHands:GetString() .. ", zcg_fingers " .. ZCG.cvFingers:GetString()
		.. ", zcg_any_model " .. ZCG.cvAnyModel:GetString())
	print("  hide material        : " .. ZCG.HideMaterial())
	local tint = fingerSkin.tint
	print("  finger material      : " .. tostring(Config.FingerMaterial)
		.. (ZCG.FingerMaterial() and "" or " - NOT installed on this client")
		.. (tint and string.format(", tint %.2f %.2f %.2f", tint.x, tint.y, tint.z) or ""))
	print("  draw errors          : " .. failures)
	print("  entity               : " .. tostring(ent))
	print("  model                : " .. model)
	print("  networked glove      : \"" .. ent:GetNWString(NW, "") .. "\"")
	print("  glove                : " .. (variant and (variant.id .. " / " .. variant.name .. " / " .. variant.model) or "none"))
	if variant then
		print("  glove model installed: " .. tostring(ZCG.HasModel(variant.model))
			.. (ZCG.HasModel(variant.model) and not ZCG.ArmRemoved(variant.model) and " - but it is the model of an OLDER version of the addon" or ""))
		local hidden, fingers = ZCG.Wearing(ent, variant)
		print("  this glove           : " .. (variant.fingerless and "fingerless" or "full-finger")
			.. ", hides the hands of this model: " .. tostring(hidden ~= nil)
			.. ", drawn with its own fingers: " .. tostring(fingers))
	end
	print("  hands material       : " .. ZCG.HandsMaterialName(model) .. " -> slot " .. tostring(slot)
		.. (slot and (", currently \"" .. ent:GetSubMaterial(slot) .. "\"") or ""))

	local bones = {}
	for _, name in ipairs({ "L_Hand", "R_Hand", "L_Forearm", "R_Forearm", "L_Wrist", "R_Wrist" }) do
		bones[#bones + 1] = name .. " " .. tostring(ent:LookupBone("ValveBiped.Bip01_" .. name))
	end
	print("  bones of the wearer  : " .. tostring(ent:GetBoneCount()) .. " (" .. table.concat(bones, ", ") .. ")")

	if state then
		print("  state                : model " .. tostring(state.mdl) .. ", body " .. tostring(state.body)
			.. ", bare arm material \"" .. tostring(state.skin) .. "\""
			.. ", hands hidden " .. tostring(state.hide ~= nil) .. ", last try " .. string.format("%.1f", RealTime() - (state.seen or 0)) .. " s ago")
		if state.drawn then
			print("  drawn                : yes" .. (state.merge and ", bone-merged by the engine"
				or (", " .. tostring(state.copied) .. " of " .. tostring(state.total) .. " bones taken from the wearer")))
		else
			print("  drawn                : NO - " .. tostring(state.why or "not tried"))
		end
	else
		print("  state                : none (the draw hook did not run for this entity)")
	end
	print("  materials of the model:")
	for i, name in ipairs(ent:GetMaterials() or {}) do
		print(string.format("    [%2d] %s", i - 1, name))
	end

	if state and variant then
		state.probe = true
		print("  (the hand bones are printed when this entity is drawn the next time)")
	end
end, nil, "CS:GO gloves: print what the addon knows about you or the player / ragdoll you look at.")
