-- Z-City CS:GO gloves - drawing the gloves on players and their ragdolls.
--
-- Z-City draws every player / ragdoll through hg.renderOverride, which runs two hooks:
--     CoolPostDrawAppearance(ent, owner)   right before ent:DrawModel()
--     PostDrawAppearance(ent, owner)       right after it
-- In the first one the wearer's own hands are hidden (full-finger gloves only, otherwise the
-- skin pokes through the glove), in the second one the glove is drawn.
--
-- The glove is a clientside model made for the c_hands skeleton, which uses the same bone names
-- as a player model, so EF_BONEMERGE puts it on the hands - the same way Z-City draws its own
-- bone-merged accessories.

local ZCG = ZCGloves
local Config = ZCG.Config

local IsValid = IsValid
local RealTime = RealTime
local FrameNumber = FrameNumber

local cvEnable = CreateClientConVar("zcg_enable", "1", true, false,
	"CS:GO gloves: 0 = do not draw the gloves on this client.", 0, 1)

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
--   variant, frame   glove decided by the pre-draw hook and the frame it was decided in
--   seen             RealTime of the last draw
--   mdl, path, body  clientside glove model, its model path and current "gloves" body value
--   hide             { slot, old } while this addon hides the wearer's hands
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
	state.mdl, state.path, state.body = nil, nil, nil
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
local function gloveModel(ent, state, variant)
	local mdl = state.mdl
	if mdl and (not IsValid(mdl) or state.path ~= variant.model) then
		removeModel(state)
		mdl = nil
	end

	local info = ZCG.Models[variant.model]

	if not mdl then
		mdl = ClientsideModel(variant.model, RENDERGROUP_OPAQUE)
		if not IsValid(mdl) then return nil end

		mdl:SetNoDraw(true) -- drawn by hand, in step with its wearer
		mdl:DrawShadow(false)
		mdl:SetParent(ent)
		mdl:AddEffects(EF_BONEMERGE)

		-- the models still contain CS:GO sleeves and a bare arm: only the glove is wanted
		mdl:SetBodygroup(info.sleeves, 0)
		local invisible = ZCG.HideMaterial()
		for _, index in ipairs(info.hide) do
			mdl:SetSubMaterial(index, invisible)
		end

		state.mdl, state.path, state.body = mdl, variant.model, nil
	end

	if state.body ~= variant.body then
		mdl:SetBodygroup(info.gloves, variant.body)
		state.body = variant.body
	end

	if mdl:GetParent() ~= ent then
		mdl:SetParent(ent)
		mdl:AddEffects(EF_BONEMERGE)
	end

	return mdl
end

-- Draws a glove on any entity with a ValveBiped skeleton (players, ragdolls, the model of the
-- appearance editor). Call it right after the entity itself was drawn.
function ZCG.DrawGlove(ent, variant)
	local state = getState(ent)
	state.seen = RealTime()

	if not ZCG.HasModel(variant.model) then return false end
	local mdl = gloveModel(ent, state, variant)
	if not mdl then return false end

	local r, g, b = render.GetColorModulation()
	render.SetColorModulation(1, 1, 1) -- the wearer's player colour must not tint the glove
	mdl:DrawModel()
	render.SetColorModulation(r, g, b)
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

-- ---------------------------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------------------------
local function preDraw(ent)
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
	state.frame = FrameNumber()
	state.seen = RealTime()

	local slot
	if ZCG.HidesHands(variant) and ZCG.HasModel(variant.model) then
		slot = ZCG.HandsSlot(ent)
	end
	if slot then
		hide(ent, state, slot)
	else
		unhide(ent, state)
	end
end

local function postDraw(ent)
	local state = states[ent]
	if not state or not state.variant or state.frame ~= FrameNumber() then return end
	ZCG.DrawGlove(ent, state.variant)
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

hook.Add("CoolPostDrawAppearance", "zcg_gloves", guarded(preDraw))
hook.Add("PostDrawAppearance", "zcg_gloves", guarded(postDraw))

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
	print("  zcg_enable " .. cvEnable:GetString() .. ", zcg_hide_hands " .. ZCG.cvHideHands:GetString()
		.. ", zcg_any_model " .. ZCG.cvAnyModel:GetString())
	print("  hide material        : " .. ZCG.HideMaterial())
	print("  draw errors          : " .. failures)
	print("  entity               : " .. tostring(ent))
	print("  model                : " .. model)
	print("  networked glove      : \"" .. ent:GetNWString(NW, "") .. "\"")
	print("  glove                : " .. (variant and (variant.id .. " / " .. variant.name .. " / " .. variant.model) or "none"))
	if variant then
		print("  glove model installed: " .. tostring(ZCG.HasModel(variant.model)))
	end
	print("  hands material       : " .. ZCG.HandsMaterialName(model) .. " -> slot " .. tostring(slot)
		.. (slot and (", currently \"" .. ent:GetSubMaterial(slot) .. "\"") or ""))
	if state then
		print("  state                : model " .. tostring(state.mdl) .. ", body " .. tostring(state.body)
			.. ", hands hidden " .. tostring(state.hide ~= nil) .. ", last drawn " .. string.format("%.1f", RealTime() - (state.seen or 0)) .. " s ago")
	else
		print("  state                : none (the draw hooks did not run for this entity)")
	end
	print("  materials of the model:")
	for i, name in ipairs(ent:GetMaterials() or {}) do
		print(string.format("    [%2d] %s", i - 1, name))
	end
end, nil, "CS:GO gloves: print what the addon knows about you or the player / ragdoll you look at.")
