-- Z-City CS:GO gloves - shared core: catalogue lookups, console variables and the registration
-- of the gloves in the Z-City appearance system.
--
-- How it plugs into Z-City
--   hg.Appearance.Bodygroups.HANDS[sex][name] = { submodel, needsPointshop, ID = ... } is the list
--   behind the "Gloves" button of the appearance editor; the chosen name is stored in the
--   appearance as ABodygroups.HANDS.  Every CS:GO glove is added to that list with the stock
--   bare-hands submodel ("hands"), so Z-City itself changes nothing on the player model and the
--   glove is drawn by this addon as a separate bone-merged model (cl_render.lua).

local ZCG = ZCGloves

-- ---------------------------------------------------------------------------------------------
-- catalogue lookups
-- ---------------------------------------------------------------------------------------------
ZCG.Variants = {} -- flat list in display order
ZCG.ByID = {} -- "moto_5" -> variant
ZCG.ByName = {} -- "CS:GO Moto 05" -> variant

for _, family in ipairs(ZCG.Families) do
	for index, variant in ipairs(family.variants) do
		variant.family = family
		variant.index = index
		variant.fingerless = family.fingerless
		ZCG.Variants[#ZCG.Variants + 1] = variant
		ZCG.ByID[variant.id] = variant
		ZCG.ByName[variant.name] = variant
	end
end

-- ---------------------------------------------------------------------------------------------
-- console variables (set them on the server, clients receive the values)
-- ---------------------------------------------------------------------------------------------
local FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED)

ZCG.cvAnyModel = CreateConVar("zcg_any_model", "0", FLAGS,
	"CS:GO gloves: 0 = show the gloves only while the player wears the model of his appearance, "
	.. "1 = also on models set by player classes, the model selector etc.", 0, 1)

ZCG.cvHideHands = CreateConVar("zcg_hide_hands", "1", FLAGS,
	"CS:GO gloves: hide the player model's own hands under full-finger gloves (they would poke through).", 0, 1)

-- ---------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------
function ZCG.Print(...)
	MsgC(Color(120, 200, 255), "[CS:GO Gloves] ", color_white, ...)
	MsgC("\n")
end

-- entry of hg.Appearance.PlayerModels for an appearance model name ("Male 01") or nil
function ZCG.AppearanceModel(name)
	local AP = hg and hg.Appearance
	local models = AP and AP.PlayerModels
	if not istable(models) or name == nil then return nil end
	local entry = (istable(models[1]) and models[1][name]) or (istable(models[2]) and models[2][name])
	if istable(entry) then return entry end
	return nil
end

-- name of the material that covers the hands of a player model (lower case)
local DEFAULT_HANDS = "distac/gloves/hands"
local handsNames = {}

function ZCG.HandsMaterialName(modelPath)
	modelPath = string.lower(modelPath or "")
	local cached = handsNames[modelPath]
	if cached then return cached end

	local found
	local AP = hg and hg.Appearance
	local models = AP and AP.PlayerModels
	if istable(models) then
		for sex = 1, 2 do
			for _, entry in pairs(models[sex] or {}) do
				if istable(entry) and isstring(entry.mdl) and string.lower(entry.mdl) == modelPath then
					local slots = entry.submatSlots
					if istable(slots) and isstring(slots.hands) then found = string.lower(slots.hands) end
				end
			end
		end
		handsNames[modelPath] = found or DEFAULT_HANDS
	end
	return found or DEFAULT_HANDS
end

-- should the wearer's own hands be hidden under this glove?
function ZCG.HidesHands(variant)
	if not ZCG.cvHideHands:GetBool() then return false end
	local override = ZCG.Config.HideHands and ZCG.Config.HideHands[variant.family.id]
	if override ~= nil then return override and true or false end
	return not variant.fingerless
end

-- ---------------------------------------------------------------------------------------------
-- registration in the appearance system
-- ---------------------------------------------------------------------------------------------
local BARE_HANDS = "hands" -- submodel of Z-City's own "None" entry

-- returns true when every glove is present in hg.Appearance.Bodygroups.HANDS (adds the missing ones)
function ZCG.Register()
	local AP = hg and hg.Appearance
	local groups = AP and AP.Bodygroups
	if not istable(groups) then return false end

	groups.HANDS = groups.HANDS or {}
	for sex = 1, 2 do
		groups.HANDS[sex] = groups.HANDS[sex] or {}
		local list = groups.HANDS[sex]
		local none = list["None"]
		local submodel = (istable(none) and isstring(none[1])) and none[1] or BARE_HANDS
		for _, variant in ipairs(ZCG.Variants) do
			local entry = list[variant.name]
			if not (istable(entry) and entry.ZCG == variant.id) then
				-- { submodel, needs a pointshop item, ID = pointshop id }; ZCG marks the entry as ours
				list[variant.name] = { submodel, false, ID = "zcg_" .. variant.id, ZCG = variant.id }
			end
		end
	end
	return true
end

function ZCG.Init()
	local ok = ZCG.Register()
	if ok and not ZCG.Ready then
		ZCG.Ready = true
		hook.Run("ZCityCSGOGloves_Ready")
	end
	return ok
end

-- Z-City may load before or after this addon, and it builds its tables at several moments
ZCG.Init()
hook.Add("HomigradRun", "zcg_init", function() ZCG.Init() end)
hook.Add("InitPostEntity", "zcg_init", function() ZCG.Init() end)
hook.Add("ZPointshopLoaded", "zcg_init", function() ZCG.Init() end)

-- keeps trying while Z-City is still loading, afterwards makes sure the entries are still there
-- (a Lua refresh of the gamemode can rebuild the table)
local tries, slow = 0, false
timer.Create("zcg_init", 1, 0, function()
	tries = tries + 1
	local ok = ZCG.Init()
	if slow then return end
	if ok and tries >= 15 then
		slow = true
		timer.Adjust("zcg_init", 10)
	elseif not ok and tries >= 60 then
		slow = true
		ZCG.Print("Z-City (hg.Appearance) was not found - the gloves stay inactive.")
		timer.Adjust("zcg_init", 30)
	end
end)
