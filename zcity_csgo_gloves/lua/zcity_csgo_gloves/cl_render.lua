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
-- In the same hook the wearer's own hands are taken away, because they would poke through the
-- glove - but only while a glove really is drawn over them. A glove is the only pair of hands its
-- wearer has. A fingerless glove is then drawn with fingers of its own: every glove model contains
-- the bare CS:GO arm it was made for, the build of this addon cuts that arm down to the fingers
-- (tools/patch_models.py), and here they get their skin.
--
-- Taken away in two ways at once, neither of which depends on the other:
--   * A player model of Z-City has a material of its own for the hands: that one is replaced by a
--     material that draws nothing.
--   * The hand and finger bones are shrunk into the wrist for the moment the model is drawn - the
--     way Z-City itself takes the head out of the first-person view. That takes everything along
--     that sits on those bones, whatever material it has and whatever body group it belongs to:
--     the hands of a model without a hands material, the bare arms of a T-shirt body, a glove of
--     the model itself.
-- Up to version 2.2 the bones were only used where there was no material to replace.

local ZCG = ZCGloves
local Config = ZCG.Config

local IsValid = IsValid
local RealTime = RealTime

local cvEnable = CreateClientConVar("zcg_enable", "1", true, false,
	"CS:GO gloves: 0 = do not draw the gloves on this client.", 0, 1)
local cvBonemerge = CreateClientConVar("zcg_bonemerge", "0", true, false,
	"CS:GO gloves: 0 = the addon puts the glove bones on the hand bones itself (default), "
	.. "1 = the engine does it (EF_BONEMERGE). Try the other value if the gloves are not on the hands.", 0, 1)
-- (1 was "only on a model without a hands material" up to version 2.2, and 2 was "on every
-- model": both mean "on every model" now, so that a value saved by an older version does)
local cvHideBones = CreateClientConVar("zcg_hide_bones", "1", true, false,
	"CS:GO gloves: the wearer's own hands under a glove are shrunk into the wrist while the model is drawn, "
	.. "so that nothing of them is left whatever they are made of: 1 = on every model (default; 2 is the same), "
	.. "3 = only on a model that has no material of its own for the hands (as up to version 2.2), 0 = never.", 0, 3)
-- Shrinking the hand bones takes along everything that hangs on them - the end of a jacket's
-- sleeve as well: it is pulled into the wrist, the sleeve gets a pointed end and the cuff of the
-- glove stands out of it, askew. Z-City's own gloves sit on a hand that keeps its shape. So does
-- a CS:GO glove now: on a model that has a material for its hands the bone of the hand - the one
-- the sleeve hangs on - stays as it is, the hand is made invisible by its material, and the
-- glove is drawn over it. Only the fingers are still shrunk away (nothing but fingers hangs on
-- the finger bones): a hand that is made of another material than the one that is hidden would
-- show a second set of fingers in the glove otherwise. The whole hand is shrunk where there is
-- no such material to hide.
local cvWholeHands = CreateClientConVar("zcg_whole_hands", "1", true, false,
	"CS:GO gloves: 1 = under a glove the hand of the model keeps its shape and is only made invisible (its material), "
	.. "so the sleeve of a jacket ends the way it does without a glove (default); only the fingers are shrunk away, the whole "
	.. "hand only on a model without a material for the hands. 0 = zcg_hide_bones decides (as up to version 2.11: shrunk on every model).", 0, 1)

-- how the bones of the hands are treated: 0 never shrunk, 1 on every model, 3 only without a hands material
local function boneMode()
	local mode = cvHideBones:GetInt()
	if mode ~= 0 and cvWholeHands:GetBool() then return 3 end
	return mode
end

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
local handsSlots = {} -- lower-case model path -> { slot = sub-material index (0-based) or false, again = time }

-- index for Entity:SetSubMaterial of the material that covers the hands, nil if the model has none
function ZCG.HandsSlot(ent)
	local model = ent:GetModel()
	if not model then return nil end
	model = string.lower(model)

	local known = handsSlots[model]
	if known and (not known.again or RealTime() < known.again) then return known.slot or nil end

	-- (the whole list of the model, not the one of the game with its gaps: see sh_materials.lua)
	local materials = ZCG.MaterialList(ent)
	if not materials or #materials == 0 then return nil end -- model not loaded yet, ask again later

	local wanted = ZCG.HandsMaterialName(model)
	local slot = false
	for i = 1, #materials do
		if string.lower(materials[i]) == wanted then
			slot = i - 1
			break
		end
	end
	if slot and slot > 31 then slot = false end -- Entity:SetSubMaterial only reaches 0..31

	-- Without the model file the list may have gaps, and a material that is not installed yet may
	-- come: such an answer is only kept for a while.
	local sure = ZCG.ModelTextures(model) ~= nil
	handsSlots[model] = { slot = slot, again = not sure and RealTime() + 10 or nil }
	return slot or nil
end

-- ---------------------------------------------------------------------------------------------
-- the wearer's hand and finger bones
-- ---------------------------------------------------------------------------------------------
local INVALID_BONE = "__INVALIDBONE__" -- Entity:SetBoneMatrix on such a bone is an error pcall cannot catch
local L_HAND, R_HAND = "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_R_Hand"

local handBones = {} -- lower-case model path -> { count = bones of the model, trees = { { hand, below it... }, ... } }

-- for every hand of the model: its bone and every bone below it, parents first. nil when the
-- model has no hand bones. A model that is not loaded yet, or a hand with a bone that cannot be
-- named yet, is asked again once a second; the hands that are known are used meanwhile.
-- Every material of the model that lies on the hands and on nothing else - found in the mesh of
-- the model itself (util.GetModelMeshes: every vertex says which bones it hangs on), not by a
-- name: a hand that is made of another material than the one Z-City calls "hands" (a model of
-- an appearance pack, a hand in two materials, nails of their own) is found all the same.
-- Hiding those materials takes the whole hand away and nothing else: a material that also lies
-- on the arm or the sleeve (less than 9 of 10 of its vertices on the hand bones) is left alone.
-- Returns a list of sub-material slots (0..31), nil when none was found or the mesh cannot be read.
local handSlots = {} -- lower-case model path .. "#" .. bodies -> { slots = { ... } or false, names, shared, shares }
local HAND_SHARE, HAND_WEIGHT = 0.9, 0.5

-- The bodies the entity wears: the number the engine keeps them in, and the same written as one
-- digit per body group. A material may lie on the hands alone in one body (long sleeves) and on
-- the whole bare arm in another (a T-shirt): what is read from the mesh is read for the bodies
-- that are worn.
local function bodiesOf(ent)
	local packed, stride, digits = 0, 1, ""
	for _, group in ipairs(ent.GetBodyGroups and ent:GetBodyGroups() or {}) do
		local num = math.max(tonumber(group.num) or 1, 1)
		local value = ent:GetBodygroup(group.id) or 0
		packed = packed + value * stride
		stride = stride * num
		digits = digits .. tostring(math.min(value, 9))
	end
	return packed, tonumber(digits) or 0
end

-- Short sleeves by the name of a body that is worn ("sheet_tshirt_m"): the surest sign there is,
-- it does not depend on the mesh being read. With such a body the arms are bare, nothing of
-- them is hidden by a material.
local SHORT = { "tshirt", "t_shirt", "t%-shirt", "shortsleeve", "short_sleeve", "sleeveless", "tanktop", "tank_top", "topless", "shirtless", "naked" }
local function shortSleeves(ent)
	for _, group in ipairs(ent.GetBodyGroups and ent:GetBodyGroups() or {}) do
		local value = ent:GetBodygroup(group.id) or 0
		local name = istable(group.submodels) and group.submodels[value]
		if isstring(name) then
			name = string.lower(name)
			for _, word in ipairs(SHORT) do
				if string.find(name, word) then return true end
			end
		end
	end
	return false
end

-- A hand under a sleeve is the hand and a short piece of the wrist. A bare arm goes on up the
-- forearm: vertices far from the hand (further than REACH times the size of the hand) or on bones
-- above the forearm. The number of vertices alone does not tell them apart - the fingers have
-- many, the whole arm has few.
local REACH, STRAY = 1.6, 0.02

local function analyse(ent)
	local model = ent:GetModel()
	if not model then return nil end
	model = string.lower(model)
	local packed = bodiesOf(ent)
	local key = model .. "#" .. packed
	local known = handSlots[key]
	if known then return known end

	local info = ZCG.HandBones(ent)
	local materials = ZCG.MaterialList(ent)
	if not info or not materials or #materials == 0 then return nil end -- (asked again at the next draw)

	known = { slots = false, names = {}, shared = {}, shares = {}, short = shortSleeves(ent), read = false }
	handSlots[key] = known
	if not (util and util.GetModelMeshes) then return known end

	local side, near = {}, {}
	for index, tree in ipairs(info.trees) do
		for _, bone in ipairs(tree) do side[bone] = index end
		local forearm = ent:GetBoneParent(tree[1])
		if forearm and forearm >= 0 then
			near[forearm] = true
			for bone = forearm + 1, (ent:GetBoneCount() or 0) - 1 do
				if ent:GetBoneParent(bone) == forearm then near[bone] = true end
			end
		end
	end

	local ok, meshes = pcall(util.GetModelMeshes, model, 0, packed)
	if not ok or not istable(meshes) then return known end

	-- first the hands themselves: where each is and how large
	local sums, per = {}, {}
	for _, mesh in ipairs(meshes) do
		local name = isstring(mesh.material) and string.lower((string.gsub(mesh.material, "\\", "/"))) or nil
		local vertices = mesh.verticies or mesh.vertices or mesh.triangles
		if name and istable(vertices) then
			local data = per[name] or { all = 0, hand = 0, other = 0, list = {} }
			per[name] = data
			for _, vertex in ipairs(vertices) do
				local hand, arm, which, best = 0, 0, nil, 0
				for _, w in ipairs(vertex.weights or {}) do
					local weight = w.weight or 0
					if side[w.bone] then
						hand = hand + weight
						if weight > best then which, best = side[w.bone], weight end
					elseif near[w.bone] then
						arm = arm + weight
					end
				end
				data.all = data.all + 1
				local onHand = hand >= HAND_WEIGHT
				if onHand then
					data.hand = data.hand + 1
					if vertex.pos and which then
						local sum = sums[which] or { pos = Vector(0, 0, 0), n = 0, list = {} }
						sums[which] = sum
						sum.pos = sum.pos + vertex.pos
						sum.n = sum.n + 1
						sum.list[#sum.list + 1] = vertex.pos
					end
				else
					if hand + arm < HAND_WEIGHT then data.other = data.other + 1 end
					data.list[#data.list + 1] = vertex
				end
			end
		end
	end
	local hands = {}
	for _, sum in pairs(sums) do
		local centre, radius = sum.pos * (1 / sum.n), 0
		for _, pos in ipairs(sum.list) do radius = math.max(radius, centre:Distance(pos)) end
		hands[#hands + 1] = { centre = centre, reach = radius * REACH }
	end

	local slots = {}
	for i = 1, math.min(#materials, 32) do
		local data = per[string.lower(materials[i])]
		if data and data.all > 0 then
			local far, wrist = 0, 0
			for _, vertex in ipairs(data.list) do
				if vertex.pos and #hands > 0 then
					local away = true
					for _, hand in ipairs(hands) do
						if hand.centre:Distance(vertex.pos) <= hand.reach then away = false break end
					end
					if away then far = far + 1 else wrist = wrist + 1 end
				end
			end
			local share = data.hand / data.all
			local text = materials[i] .. " " .. math.floor(share * 100 + 0.5) .. "%"
			if far > 0 or data.other > 0 then
				text = text .. " (far from the hand " .. far .. ", on other bones " .. data.other .. " of " .. data.all .. ")"
			end
			known.shares[#known.shares + 1] = text
			known.read = true
			local alone = (data.hand + wrist) / data.all >= HAND_SHARE and share >= 0.5
				and far <= data.all * STRAY and data.other <= data.all * STRAY
			if alone and not known.short then
				slots[#slots + 1] = i - 1
				known.names[#known.names + 1] = materials[i]
			elseif data.hand > 0 then
				known.shared[i - 1] = true -- on the hands and on something else
			end
		end
	end
	if #slots > 0 then known.slots = slots end
	return known
end

-- was the mesh of the model read (is it known for certain which materials are the hands)?
function ZCG.MeshRead(ent)
	local known = analyse(ent)
	return known ~= nil and known.read == true
end

function ZCG.HandSlots(ent)
	local known = analyse(ent)
	return known and known.slots or nil
end

-- Does the material in this slot lie on the hands and on more than the hands (a bare arm)?
-- Hiding it would take the arm away. false when it does not, or when the mesh cannot be read.
function ZCG.SlotShared(ent, slot)
	local known = analyse(ent)
	return known ~= nil and (known.short or known.shared[slot] == true)
end

-- are the arms bare with the bodies that are worn (by the name of a body)?
function ZCG.ShortSleeves(ent)
	local known = analyse(ent)
	return known ~= nil and known.short == true
end

function ZCG.HandBones(ent)
	local model = ent:GetModel()
	if not model then return nil end
	model = string.lower(model)

	local known = handBones[model]
	if known and (not known.again or RealTime() < known.again) then return known.trees and known or nil end

	local count = ent:GetBoneCount() or 0
	local trees, complete = {}, count > 0
	for _, name in ipairs({ L_HAND, R_HAND }) do
		local hand = count > 0 and ent:LookupBone(name) or nil
		if hand then
			local tree, below = { hand }, { [hand] = true }
			for bone = hand + 1, count - 1 do -- (a bone comes after its parent)
				if below[ent:GetBoneParent(bone)] then
					local boneName = ent:GetBoneName(bone)
					if not boneName or boneName == INVALID_BONE then
						tree, complete = nil, false
						break
					end
					below[bone] = true
					tree[#tree + 1] = bone
				end
			end
			if tree then trees[#trees + 1] = tree end
		end
	end

	known = { count = count, trees = #trees > 0 and trees or nil, again = not complete and RealTime() + 1 or nil }
	handBones[model] = known
	return known.trees and known or nil
end

local SHRINK = 0.05 -- what is left of a hidden hand, measured from the wrist
local IDENTITY = Matrix()

-- Shrinks the hands of an entity into its wrists. Only lasts until the bones are set up again,
-- so it has to happen between Entity:SetupBones() and Entity:DrawModel(). Everything that was
-- changed is noted in state.bones for growHands: bone, matrix, bone, matrix ... and, per hand,
-- where its bones are in that list (state.bones.hands).
local function shrinkHands(ent, state)
	local info = ZCG.HandBones(ent)
	if not info or ent:GetBoneCount() ~= info.count then return false end
	-- (zcg_whole_hands: the bone of the hand itself stays, the fingers go)
	local named = ZCG.HandsSlot(ent)
	if named and ZCG.SlotShared(ent, named) then named = nil end
	local fingersOnly = cvWholeHands:GetBool() and (named ~= nil or ZCG.HandSlots(ent) ~= nil)

	local saved = state.bones
	if not saved then
		saved = { hands = {} }
		state.bones = saved
	end
	local n, hands = 0, 0
	for _, tree in ipairs(info.trees) do
		local hand = tree[1]
		local was = ent:GetBoneMatrix(hand)
		local back = was and was:GetInverse() -- (nil for an arm that is scaled to nothing already)
		if back then
			local first = n + 1
			local small = was * IDENTITY -- a copy
			small:SetScale(was:GetScale() * SHRINK)
			local change = small * back -- what happens to the hand happens to the fingers
			for k = 2, #tree do
				local bone = tree[k]
				local matrix = ent:GetBoneMatrix(bone)
				if matrix then
					saved[n + 1], saved[n + 2] = bone, matrix
					n = n + 2
					ent:SetBoneMatrix(bone, change * matrix)
				end
			end
			local mark, size = hand, was:GetScale().x
			if fingersOnly then
				-- (what tells afterwards whether the bones are still as they were written: a finger)
				mark = n > first and saved[first] or nil
				size = mark and saved[first + 1]:GetScale().x or size
			else
				saved[n + 1], saved[n + 2] = hand, was
				n = n + 2
				ent:SetBoneMatrix(hand, small)
			end

			if mark then
			hands = hands + 1
			local entry = saved.hands[hands]
			if not entry then
				entry = {}
				saved.hands[hands] = entry
			end
			-- (a hand that is smaller than this afterwards is still the one that was written here)
			entry.bone, entry.first, entry.last, entry.limit = mark, first, n, size * 0.5
			end
		end
	end
	saved.n, saved.count, saved.frame = n, hands, FrameNumber()
	return n > 0
end

-- Gives the bones back as they were, for whatever looks at the hands after the model was drawn
-- (the flashlight in the hand, for one). Only what is still there is undone: once the engine has
-- set the bones up again in the meantime, they are whole already - and where it put them.
-- Returns true when there was something to undo, false when the engine had done it, nil when
-- nothing was shrunk.
local function growHands(ent, state)
	local saved = state.bones
	local n = saved and saved.n or 0
	if n == 0 then return nil end
	saved.n = 0
	if saved.frame ~= FrameNumber() or not IsValid(ent) then return nil end
	local count = ent:GetBoneCount() or 0
	local undone = false
	for k = 1, saved.count or 0 do
		local hand = saved.hands[k]
		local now = hand.bone < count and ent:GetBoneMatrix(hand.bone) or nil
		if now and now:GetScale().x < hand.limit then
			undone = true
			for i = hand.first, hand.last, 2 do
				if saved[i] < count then ent:SetBoneMatrix(saved[i], saved[i + 1]) end
			end
		end
	end
	return undone
end

local function forgetHands(state)
	if state.bones then state.bones.n = 0 end
end
ZCG.ShrinkHands, ZCG.GrowHands = shrinkHands, growHands

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
--   mats             the "mats" of the glove whose materials are on the model right now
--   merge            the model was set up for zcg_bonemerge 1
--   copied, total    bones taken from the wearer / bones of the glove (zcg_bonemerge 0)
--   hide             { slot, old } while this addon hides the material of the wearer's hands
--   bones            the hand bones that were shrunk for this draw and what they were before
--   shrunk           the hands were shrunk at the last draw (for zcg_debug)
--   kept             ... and were still shrunk when the wearer had been drawn (for zcg_debug;
--                    false: the engine had set the bones up again by then)
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
	state.mdl, state.path, state.body, state.merge, state.skin, state.mats = nil, nil, nil, nil, nil, nil
	state.drawn = false
end

-- Give the hands back. The value is only touched while it still is our "invisible" material:
-- when the server changed it in the meantime, the new value has already replaced ours.
local function unhideMore(ent, state)
	local more = state.more
	if not more then return end
	state.more = nil
	if not IsValid(ent) then return end
	local invisible = ZCG.HideMaterial()
	for slot, old in pairs(more) do
		if ent:GetSubMaterial(slot) == invisible then
			if old ~= "" then ent:SetSubMaterial(slot, old) else ent:SetSubMaterial(slot, nil) end
		end
	end
end

-- the other materials of the hands (ZCG.HandSlots), next to the one Z-City names
local function hideMore(ent, state, slots, main)
	if not slots then return unhideMore(ent, state) end
	local invisible = ZCG.HideMaterial()
	local more = state.more
	if more then
		-- (another model: other slots)
		local same = true
		for slot in pairs(more) do
			local found = false
			for _, s in ipairs(slots) do if s == slot then found = true end end
			if not found then same = false end
		end
		if not same then
			unhideMore(ent, state)
			more = nil
		end
	end
	for _, slot in ipairs(slots) do
		if slot ~= main then
			local current = ent:GetSubMaterial(slot) or ""
			if current ~= invisible then
				more = more or {}
				more[slot] = current
				ent:SetSubMaterial(slot, invisible)
			end
		end
	end
	state.more = more
end
ZCG.HideMore, ZCG.UnhideMore = hideMore, unhideMore

local function unhide(ent, state)
	unhideMore(ent, state)
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
		forgetHands(state)
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
		state.mdl, state.path, state.body, state.merge, state.skin, state.mats = mdl, variant.model, nil, merge, nil, nil
	end

	if state.body ~= variant.body then
		mdl:SetBodygroup(info.gloves, variant.body)
		state.body = variant.body
	end

	-- A glove whose model does not name its materials brings them along ("mats" in sh_data.lua).
	-- The model is kept from glove to glove, so the materials of the previous one go first.
	if state.mats ~= variant.mats then
		if state.mats then
			for index in pairs(state.mats) do
				mdl:SetSubMaterial(index, nil)
			end
		end
		if variant.mats then
			for index, name in pairs(variant.mats) do
				mdl:SetSubMaterial(index, name)
			end
		end
		state.mats = variant.mats
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

-- What a glove does to the hands of its wearer. Returns
--   the sub-material slot of the hands that the glove hides (nil: the model has none),
--   whether the glove is drawn with its own fingers,
--   whether the hand bones are shrunk while the wearer is drawn.
-- Nothing of that (nil, false, false) when the hands stay as they are.
-- Both ways of taking the hands away are used together (see the top of this file): the material
-- wherever the model has one, the bones on every model unless zcg_hide_bones says otherwise.
-- A fingerless glove hides the hands only when it can show fingers instead, and shows them only
-- when it can hide the hands: two sets of fingers in one glove would be worse than either.
function ZCG.Wearing(ent, variant)
	if not ZCG.HidesHands(variant) then return nil, false, false end
	if variant.fingerless and not (ZCG.FingerMaterial() and ZCG.ArmRemoved(variant.model)) then return nil, false, false end

	local slot = ZCG.HandsSlot(ent)
	-- (a "hands" material that is the bare arm as well - under a T-shirt - is not hidden: the
	-- arm would go with it. The hand is taken away by its bones then, as on a model without
	-- such a material.)
	-- (whatever zcg_whole_hands says: an arm is never hidden)
	if slot and ZCG.SlotShared(ent, slot) then slot = nil end
	local mode = boneMode()
	local bones = mode ~= 0 and (mode ~= 3 or not slot or cvWholeHands:GetBool()) and ZCG.HandBones(ent) ~= nil
	local more = cvWholeHands:GetBool() and ZCG.HandSlots(ent) or nil
	-- Hands that are known for certain to be hidden whole by their materials (the mesh was read)
	-- are hidden and nothing else: no bone of theirs is touched, they stand where they stood.
	if bones and cvWholeHands:GetBool() and (slot or more) and ZCG.MeshRead(ent) then bones = false end
	if not slot and not bones and not more then return nil, false, false end
	-- (the fourth: every other material that lies on the hands alone - hidden as well)
	return slot, variant.fingerless and true or false, bones, more
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
			state.variant, state.shrunk = nil, false
			unhide(ent, state)
			forgetHands(state)
		end
		return
	end

	state = state or getState(ent)
	state.variant, state.shrunk = variant, false
	forgetHands(state)

	-- The glove first: it takes its pose from the hands, and they are only hidden while a glove
	-- really is drawn over them.
	local slot, fingers, bones, more = ZCG.Wearing(ent, variant)
	local drawn = ZCG.DrawGlove(ent, variant, fingers)
	if drawn and slot then
		hide(ent, state, slot)
	else
		unhide(ent, state)
	end
	hideMore(ent, state, drawn and more or nil, slot)
	if drawn and bones then state.shrunk = shrinkHands(ent, state) end
end

-- after the wearer was drawn
local function afterHook(ent)
	local state = states[ent]
	if not state then return end
	local undone = growHands(ent, state)
	if undone ~= nil then state.kept = undone end
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

-- The hands are shrunk from the end of the first hook to the start of the second one, and nothing
-- but the wearer itself should be drawn in between: whatever else is drawn on the wearer in these
-- hooks (a coat of Z-City, something of another addon) is to find the hands whole, as it would
-- without this addon. The hook library of the game runs the hooks of an event in no order that
-- could be asked for. ULib and Srlion's hook library - one of the two is on most servers - have
-- one, under the same names: there this addon runs after the others before the wearer is drawn
-- (so the glove gets its pose from bones nobody touches any more) and ahead of them after it.
-- (HOOK_LOW and HOOK_HIGH: not the "monitor" levels beyond them, which are for looking on, and
-- not POST_HOOK_RETURN / POST_HOOK of Srlion's library, whose hooks get other arguments.)
local HOOK_ID = "zcg_gloves"

local function addHook(event, func, ahead)
	local order = rawget(_G, ahead and "HOOK_HIGH" or "HOOK_LOW")
	if isnumber(order) and pcall(hook.Add, event, HOOK_ID, func, order) then
		-- (a library that did not take it this way is asked again the plain way)
		local ok, hooks = pcall(hook.GetTable)
		hooks = ok and istable(hooks) and hooks[event] or nil
		if istable(hooks) and hooks[HOOK_ID] ~= nil then return order end
	end
	hook.Add(event, HOOK_ID, func)
	return nil
end

-- (what was asked for, for zcg_debug: a number where the library has an order, nil where not)
ZCG.HookOrder = {
	draw = addHook("CoolPostDrawAppearance", guarded(drawHook), false),
	after = addHook("PostDrawAppearance", guarded(afterHook), true),
}

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
		.. ", zcg_hide_hands " .. ZCG.cvHideHands:GetString() .. ", zcg_hide_bones " .. cvHideBones:GetString()
		.. ", zcg_fingers " .. ZCG.cvFingers:GetString() .. ", zcg_any_model " .. ZCG.cvAnyModel:GetString())
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
		local hidden, fingers, shrunk = ZCG.Wearing(ent, variant)
		local how = {}
		if hidden then how[#how + 1] = "their material" end
		if shrunk then how[#how + 1] = "their bones" end
		print("  this glove           : " .. (variant.fingerless and "fingerless" or "full-finger")
			.. ", hides the hands of this model: " .. (#how > 0 and ("yes, by " .. table.concat(how, " and ")) or "no")
			.. ", drawn with its own fingers: " .. tostring(fingers))
	end
	do
		local known = analyse(ent)
		local found = known and known.slots
		print("  materials on the hands alone (read from the mesh): " .. (found and (table.concat(known.names, ", ")
			.. " -> slots " .. table.concat(found, ", ")) or "none found") .. "; hidden under a glove with zcg_whole_hands 1")
		print("  share of each material that lies on the hand bones: " .. (known and #known.shares > 0 and table.concat(known.shares, ", ")
			or "the mesh could not be read") .. " (bodies " .. table.concat({ bodiesOf(ent) }, " / ") .. ")")
		if ZCG.ShortSleeves(ent) then
			print("  short sleeves (by the name of a body that is worn): the arms are bare, no material of them is hidden")
		end
		if slot and ZCG.SlotShared(ent, slot) then
			print("  the hands material also lies on the arm with these bodies: it is NOT hidden, the hand goes by its bones")
		end
	end
	print("  hands material       : " .. ZCG.HandsMaterialName(model) .. " -> slot " .. tostring(slot)
		.. (slot and (", currently \"" .. ent:GetSubMaterial(slot) .. "\"") or ""))
	local handInfo = ZCG.HandBones(ent)
	local below = 0
	for _, tree in ipairs(handInfo and handInfo.trees or {}) do below = below + #tree end
	local mode = boneMode()
	print("  hand bones           : " .. (handInfo and (#handInfo.trees .. " hands, " .. below .. " bones with the fingers") or "none found")
		.. "; under a glove they are " .. (mode == 0 and "never shrunk" or mode == 3 and "shrunk only on a model without a hands material"
			or "shrunk on every model") .. " (zcg_hide_bones " .. cvHideBones:GetInt() .. "; 1 = every model, 3 = only without a hands material, 0 = never"
			.. "; zcg_whole_hands " .. cvWholeHands:GetString() .. ": 1 = a hand that has a material keeps its shape, whatever zcg_hide_bones says)")

	local bones = {}
	for _, name in ipairs({ "L_Hand", "R_Hand", "L_Forearm", "R_Forearm", "L_Wrist", "R_Wrist" }) do
		bones[#bones + 1] = name .. " " .. tostring(ent:LookupBone("ValveBiped.Bip01_" .. name))
	end
	print("  bones of the wearer  : " .. tostring(ent:GetBoneCount()) .. " (" .. table.concat(bones, ", ") .. ")")

	-- What else could draw hands on this entity? The bodies of the model that are switched on,
	-- what hangs on it, what Z-City put on it, and who else draws in the two hooks.
	local bodies = {}
	for _, group in ipairs(ent.GetBodyGroups and ent:GetBodyGroups() or {}) do
		if (tonumber(group.num) or 0) > 1 then
			local value = ent:GetBodygroup(group.id)
			local body = istable(group.submodels) and group.submodels[value] or nil
			bodies[#bodies + 1] = tostring(group.name) .. " = " .. tostring(value) .. " \"" .. tostring(body or "?") .. "\""
		end
	end
	print("  bodies of the model  : " .. (#bodies > 0 and table.concat(bodies, ", ") or "nothing to choose from"))

	local attached = {}
	for _, child in ipairs(ent.GetChildren and ent:GetChildren() or {}) do
		if IsValid(child) and not (state and child == state.mdl) then
			attached[#attached + 1] = tostring(child:GetClass()) .. " " .. tostring(child:GetModel())
				.. (child:IsEffectActive(EF_BONEMERGE) and " (bone-merged)" or "")
		end
	end
	local viewHands = ent.GetHands and ent:GetHands()
	if IsValid(viewHands) then attached[#attached + 1] = "hands of the first-person view " .. tostring(viewHands:GetModel()) end
	print("  attached to it       : " .. (#attached > 0 and table.concat(attached, "; ") or "nothing"))

	-- (Z-City keeps the list with the player, and with the body once the player is dead)
	local worn, listed = {}, {}
	local owner = ent:IsRagdoll() and ent:GetNWEntity("ply") or nil
	for _, holder in ipairs({ ent, IsValid(owner) and owner or nil }) do
		local equipment = holder.GetNetVar and holder:GetNetVar("zc_equipment") or nil
		for _, index in ipairs(istable(equipment) and equipment or {}) do
			local item = not listed[index] and isnumber(index) and Entity(index) or nil
			listed[index] = true
			if IsValid(item) then
				local shown = IsValid(item.renderModel) and item.renderModel:GetModel() or item:GetModel()
				worn[#worn + 1] = tostring(item:GetClass()) .. " " .. tostring(shown)
			end
		end
	end
	print("  equipment of Z-City  : " .. (#worn > 0 and table.concat(worn, "; ") or "none"))

	local gotHooks, hooks = pcall(hook.GetTable)
	for _, event in ipairs({ "CoolPostDrawAppearance", "PostDrawAppearance" }) do
		local names = {}
		for id in pairs(gotHooks and istable(hooks) and istable(hooks[event]) and hooks[event] or {}) do
			names[#names + 1] = tostring(id)
		end
		print("  hooks of " .. event .. ": " .. (#names > 0 and table.concat(names, ", ") or "none"))
	end
	print("  order of these hooks : " .. (ZCG.HookOrder.draw ~= nil
		and "this addon asked to be the last before the wearer is drawn and the first after it"
		or "the hook library has none to ask for (the one of the game runs them as listed)"))

	if state then
		print("  state                : model " .. tostring(state.mdl) .. ", body " .. tostring(state.body)
			.. ", bare arm material \"" .. tostring(state.skin) .. "\""
			.. ", hands material hidden " .. tostring(state.hide ~= nil) .. ", hand bones shrunk " .. tostring(state.shrunk == true)
			.. (state.shrunk and state.kept ~= nil and (state.kept and " (still shrunk after the draw)"
				or " (set up again by the engine by the end of the draw)") or "")
			.. ", last try " .. string.format("%.1f", RealTime() - (state.seen or 0)) .. " s ago")
		if variant and variant.mats then
			-- the glove brings materials the model does not name: what is on the model right now?
			local slots = {}
			for index in pairs(variant.mats) do slots[#slots + 1] = index end
			table.sort(slots)
			local names = IsValid(state.mdl) and state.mdl:GetMaterials() or {}
			for _, index in ipairs(slots) do
				print(string.format("  glove material [%2d]  : %s", index, tostring(names[index + 1]))
					.. " -> wanted \"" .. variant.mats[index] .. "\", set \""
					.. (IsValid(state.mdl) and state.mdl:GetSubMaterial(index) or "") .. "\"")
			end
		end
		if state.drawn then
			print("  drawn                : yes" .. (state.merge and ", bone-merged by the engine"
				or (", " .. tostring(state.copied) .. " of " .. tostring(state.total) .. " bones taken from the wearer")))
		else
			print("  drawn                : NO - " .. tostring(state.why or "not tried"))
		end
	else
		print("  state                : none (the draw hook did not run for this entity)")
	end
	-- The game leaves materials that are not installed out of its list; the model file has them
	-- all (sh_materials.lua). Both are shown: a gap means missing content.
	local found, inModel = ZCG.MaterialCounts(ent)
	local known = {}
	for _, name in ipairs(ZCG.EngineGetMaterials and ZCG.EngineGetMaterials(ent) or {}) do known[name] = true end
	print("  materials of the model: the game names " .. found .. ", the model file "
		.. (inModel and tostring(inModel) or "could not be read")
		.. ((inModel and inModel > found) and (" - " .. (inModel - found) .. " are NOT INSTALLED (type zcg_content)") or ""))
	for i, name in ipairs(ZCG.MaterialList(ent) or {}) do
		print(string.format("    [%2d] %s%s", i - 1, name, known[name] and "" or "   <- not installed"))
	end

	if state and variant then
		state.probe = true
		print("  (the hand bones are printed when this entity is drawn the next time)")
	end
end, nil, "CS:GO gloves: print what the addon knows about you or the player / ragdoll you look at.")
