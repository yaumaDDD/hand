-- Our own appearance system: the client half that draws what a player wears. The accessories are
-- models of their own, parented to a bone of the player and drawn with him - that is what the
-- catalog keeps a bone, an offset, an angle and a scale for.
--
-- Z-City draws its players through hg.renderOverride, which calls DrawAppearance and
-- RenderAccessoriesCool by name; where nothing calls them (another gamemode, sandbox) the
-- PostPlayerDraw hook below does the same. Either way the accessories are there, and either way
-- they are drawn by this file and not by the Appearance Mod.

ZCO = ZCO or {}

ZCO.AccessoryModels = ZCO.AccessoryModels or {}     -- player -> accessory name -> the model of it

local function accessoryData(name)
	local data = (ZCO.Catalog.Accessories or {})[name]
	if data then return ZCO.AccessoryEntry(name, data) end
	return hg.Accessories and hg.Accessories[name] or nil
end

--- is this entity the one the local player looks through right now (his accessories are not drawn
--- in his own face: the game draws them into the camera otherwise)
local function isLookedThrough(ent)
	local local_player = LocalPlayer()
	if not IsValid(local_player) or not IsValid(ent) then return false end
	local looked = local_player
	if local_player.GetNWEntity then looked = local_player:GetNWEntity("spect", local_player) end
	if not IsValid(looked) then return false end
	local owner = (ent.IsRagdoll and ent:IsRagdoll() and hg and hg.RagdollOwner and hg.RagdollOwner(ent)) or ent
	return owner == looked and GetViewEntity() == looked
end

--- take away the models of the accessories a player does not wear any more
local function pruneAccessories(ply, worn)
	local models = ZCO.AccessoryModels[ply]
	if not models then return end
	for name, model in pairs(models) do
		local keeps = false
		if type(worn) == "table" then
			for index = 1, #worn do
				if worn[index] == name then keeps = true break end
			end
		elseif worn == name then
			keeps = true
		end
		if not keeps then
			if IsValid(model) then model:Remove() end
			models[name] = nil
		end
	end
end

-- A bone of the player to wear an accessory on, or the nearest one of the same family. Not every
-- model has every bone of a citizen: the vests of the catalog are on Bip01_Spine2, the purse is on
-- Bip01_Spine1, and a model that has neither wears nothing at all - the accessory is made and then
-- never drawn, because there is no bone to put it on. So the bones beside the one asked for are
-- tried (nearest first), then the same bone without its number, then its name without the
-- "ValveBiped." in front of it: a spine is a spine, and an accessory on the nearest one is better
-- than one nobody sees.
local BONE_TRIES = {}
local function boneTries(name)
	local tries = BONE_TRIES[name]
	if tries then return tries end
	tries = {}
	local prefix, number = string.match(name, "^(.-)(%d+)$")
	if prefix and prefix ~= "" then
		for step = 1, 4 do
			tries[#tries + 1] = prefix .. (number + step)
			if number - step >= 0 then tries[#tries + 1] = prefix .. (number - step) end
		end
		tries[#tries + 1] = prefix
	end
	local plain = string.match(name, "^ValveBiped%.(.+)$")
	if plain then tries[#tries + 1] = plain end
	BONE_TRIES[name] = tries
	return tries
end

function ZCO.BoneOf(ent, name)
	if not IsValid(ent) or not ent.LookupBone then return nil end
	if not isstring(name) or name == "" then return nil end
	local bone = ent:LookupBone(name)
	if bone then return bone end
	for _, one in ipairs(boneTries(name)) do
		local found = ent:LookupBone(one)
		if found then return found end
	end
	return nil
end

--- one accessory on one player: the model is made once and drawn every frame where it belongs.
--- setup: false = only draw it where it is (the bone matrices are set up already)
function ZCO.DrawAccessory(ply, ent, name, data, isLocal, setup)
	if not IsValid(ply) or not IsValid(ent) or not data then return end
	if not data.model and not data.femmodel then return end

	local female = ZCO.IsFemale(ent)
	local models = ZCO.AccessoryModels[ply]
	if not models then
		models = {}
		ZCO.AccessoryModels[ply] = models
	end

	local model = models[name]
	if not IsValid(model) then
		local path = (female and data.femmodel) or data.model
		if not path or path == "" then return end
		model = ClientsideModel(path, RENDERGROUP_BOTH)
		if not IsValid(model) then return end
		models[name] = model
		model:SetNoDraw(true)
		local offset = (female and data.fempos) or data.malepos or {}
		model:SetModelScale(tonumber(offset[3]) or 1)
		model:SetSkin(tonumber(data.skin) or 0)
		if data.bodygroups then model:SetBodyGroups(data.bodygroups) end
		local bone = data.bone and ZCO.BoneOf(ent, data.bone) or nil
		if bone then model:SetParent(ent, bone) end
		if data.bonemerge then model:AddEffects(EF_BONEMERGE) end
		if data.submat or data.SubMat then model:SetSubMaterial(0, data.submat or data.SubMat) end
		local function away()
			if IsValid(model) then model:Remove() end
			if ZCO.AccessoryModels[ply] then ZCO.AccessoryModels[ply][name] = nil end
		end
		if ply.CallOnRemove then ply:CallOnRemove("zco_accessory_" .. name, away) end
		if ent ~= ply and ent.CallOnRemove then ent:CallOnRemove("zco_accessory_" .. name, away) end
	end

	-- where it is drawn: the bone of the player, the offset and the angle of the catalog
	if setup ~= false then
		if not data.bone then return end
		local bone = ZCO.BoneOf(ent, data.bone)
		if not bone then return end
		-- a bone that was shrunk away (an amputated limb of Z-City) wears nothing
		local scale = ent.GetManipulateBoneScale and ent:GetManipulateBoneScale(bone)
		if scale and scale.LengthSqr and scale:LengthSqr() < 0.1 then return end
		local matrix = ent:GetBoneMatrix(bone)
		if not matrix then return end
		local bonePos, boneAng = matrix:GetTranslation(), matrix:GetAngles()
		local offset = (female and data.fempos) or data.malepos or {}
		local pos, ang = LocalToWorld(offset[1] or Vector(0, 0, 0), offset[2] or Angle(0, 0, 0), bonePos, boneAng)
		model:SetRenderOrigin(pos)
		model:SetRenderAngles(ang)
		if model:GetParent() ~= ent then
			model:SetParent(ent, bone)
		end
	end

	-- the local player does not see his own glasses, mask or cap from the inside
	if isLocal and data.norender then return end
	if not setup or data.bonemerge then
		if data.bSetColor or data.setcolor then
			local color = data.vecColorOveride or data.color
				or (ply.GetPlayerColor and ply:GetPlayerColor())
				or (ply.GetNWVector and ply:GetNWVector("PlayerColor", Vector(1, 1, 1)))
			if color then render.SetColorModulation(color[1] or color.r or 1, color[2] or color.g or 1,
				color[3] or color.b or 1) end
		end
		model:DrawModel()
		if data.bSetColor or data.setcolor then render.SetColorModulation(1, 1, 1) end
	end
end

--- everything a player wears, drawn with him
function ZCO.DrawAppearance(ent, ply, setup)
	if not IsValid(ent) then return end
	ply = IsValid(ply) and ply or ent
	local worn = (ent.GetNetVar and ent:GetNetVar("Accessories")) or ent.zcoPredicted
	if not worn or worn == "none" or worn == "" then
		pruneAccessories(ply, nil)
		return
	end
	if ply:IsPlayer() and ply.Alive and not ply:Alive() and not (ent ~= ply) then return end
	local isLocal = isLookedThrough(ent)
	pruneAccessories(ply, worn)
	if type(worn) == "table" then
		for index = 1, #worn do
			local name = worn[index]
			local data = name and name ~= "" and accessoryData(name) or nil
			if data and not data.cool and not data.needcoolRender then
				ZCO.DrawAccessory(ply, ent, name, data, isLocal, setup)
			end
		end
	else
		local data = accessoryData(worn)
		if data and not data.cool and not data.needcoolRender then
			ZCO.DrawAccessory(ply, ent, worn, data, isLocal, setup)
		end
	end
end

--- the accessories that want a frame of their own (needcoolRender): drawn after the player
function ZCO.DrawCool(ent, ply)
	if not IsValid(ent) then return end
	ply = IsValid(ply) and ply or ent
	local worn = (ent.GetNetVar and ent:GetNetVar("Accessories")) or ent.zcoPredicted
	if type(worn) ~= "table" then return end
	local isLocal = isLookedThrough(ent)
	for index = 1, #worn do
		local name = worn[index]
		local data = name and name ~= "" and accessoryData(name) or nil
		if data and (data.cool or data.needcoolRender) then
			ZCO.DrawAccessory(ply, ent, name, data, isLocal, false)
		end
	end
end

--- what is left of a player who died: his ragdoll wears what he wore
function ZCO.DrawRagdoll(ent, ply)
	if not IsValid(ent) or not IsValid(ply) then return end
	local worn = ply.GetNetVar and ply:GetNetVar("Accessories")
	if worn and worn ~= "" and worn ~= "none" then
		ent.zcoPredicted = worn
		ZCO.DrawAppearance(ent, ply, true)
	end
end

-- --------------------------------------------------------------------------------------
-- the names the rest of the game calls
-- --------------------------------------------------------------------------------------

if type(DrawAppearance) ~= "function" then
	DrawAppearance = function(ent, ply, setup) return ZCO.DrawAppearance(ent, ply, setup) end
end
if type(RenderAccessories) ~= "function" then
	RenderAccessories = function(ply, accessories, setup)
		if not IsValid(ply) then return end
		local worn = accessories
		if type(worn) ~= "table" and type(worn) ~= "string" then
			worn = ply.GetNetVar and ply:GetNetVar("Accessories")
		end
		if not worn then return end
		if worn == "none" or worn == "" then
			pruneAccessories(ply, nil)
			return
		end
		local isLocal = isLookedThrough(ply)
		if type(worn) == "table" then
			for index = 1, #worn do
				local data = worn[index] and worn[index] ~= "" and accessoryData(worn[index]) or nil
				if data and not data.cool and not data.needcoolRender then
					ZCO.DrawAccessory(ply, ply, worn[index], data, isLocal, setup)
				end
			end
		else
			local data = accessoryData(worn)
			if data and not data.cool and not data.needcoolRender then
				ZCO.DrawAccessory(ply, ply, worn, data, isLocal, setup)
			end
		end
	end
end
if type(DrawAccesories) ~= "function" then
	-- (the name Z-City spells this way: the same call, so that nothing that calls it breaks)
	DrawAccesories = function(ply, ent, name, data, isLocal, force, setup)
		if force or not data then
			data = data or accessoryData(name)
		end
		return ZCO.DrawAccessory(ply, ent, name, data, isLocal, setup)
	end
end
if type(CoolRenderAccessories) ~= "function" then
	CoolRenderAccessories = function(ply, _accessories) return ZCO.DrawCool(ply, ply) end
end
if type(RenderAccessoriesCool) ~= "function" then
	RenderAccessoriesCool = function(ent, ply) return ZCO.DrawCool(ent, ply) end
end

-- where no renderOverride of Z-City draws the players (another gamemode, sandbox, a map without
-- it), the accessories are drawn by the hook of the game itself
hook.Add("PostPlayerDraw", "zco_accessories", function(ply)
	if not IsValid(ply) then return end
	if hg and hg.renderOverride then return end       -- Z-City draws him itself: do not draw twice
	ZCO.DrawAppearance(ply, ply)
end)

-- a player who is gone takes his models with him
hook.Add("EntityRemoved", "zco_accessories", function(ent)
	if IsValid(ent) and ZCO.AccessoryModels[ent] then
		for _name, model in pairs(ZCO.AccessoryModels[ent]) do
			if IsValid(model) then model:Remove() end
		end
		ZCO.AccessoryModels[ent] = nil
	end
end)

-- --------------------------------------------------------------------------------------
-- a player whose model is not on this computer
-- --------------------------------------------------------------------------------------
-- The server cannot tell what a player has downloaded: a model may be on the server and not on
-- his computer, or on his computer (from the Workshop, from FastDL) and not on the server. So the
-- client looks for itself - once every five seconds, and one line per model, not per player: a
-- player whose model is not here is the ERROR body, with no submaterial slots for the clothes, no
-- face material to replace, no bones for the accessories and nothing for the gloves to hide, and
-- the game itself tells him nothing about it.
local lookedAt = 0
hook.Add("Think", "zco_model_notice", function()
	if SysTime() < lookedAt then return end
	lookedAt = SysTime() + 5
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local worn = me:GetModel()
	if not isstring(worn) or worn == "" then
		ZCO.ModelGone("", me, true)     -- no model at all: he is invisible, and nothing fits him
	else
		if not ZCO.ModelReady(worn) then ZCO.ModelGone(worn, me, true) end
		for _, ply in ipairs(player.GetAll()) do
			if ply ~= me then
				local model = ply:GetModel()
				if isstring(model) and model ~= "" and not ZCO.ModelReady(model) then ZCO.ModelGone(model, ply) end
			end
		end
	end
end)

-- the models of the accessories are looked at again when the player changes his model
hook.Add("ZCOApplied", "zco_accessories", function(ply)
	if not IsValid(ply) then return end
	local models = ZCO.AccessoryModels[ply]
	if not models then return end
	for name, model in pairs(models) do
		if IsValid(model) then model:Remove() end
		models[name] = nil
	end
end)
