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
	"CS:GO gloves: 1 = a glove hides the player model's own hands (they would poke through it; "
	.. "fingerless gloves have fingers of their own), 0 = never hide them.", 0, 1)

ZCG.cvFingers = CreateConVar("zcg_fingers", "1", FLAGS,
	"CS:GO gloves: 1 = fingerless gloves are drawn with the fingers that are part of the glove models, "
	.. "0 = with the player model's own hands, as up to version 1.0.1.", 0, 1)

ZCG.cvFixFaces = CreateConVar("zcg_fix_faces", "0", FLAGS,
	"Appearance menu: 1 = a face whose material file is not installed here shows the own face of the model instead of "
	.. "purple and black squares - on a computer that has the content of the menu as a whole; 2 = on any computer; "
	.. "0 = the faces stay as the clothing Lua made them. Set it on the server. zcg_content tells how many there are.", 0, 2)

ZCG.cvBodies = CreateConVar("zcg_fix_bodies", "1", FLAGS,
	"Appearance menu: 1 = a jacket / T-shirt / trousers / shoes chosen in the menu is also put on a model that calls "
	.. "the same part a little differently (the models of the LEGACY version and other added ones); 0 = only by exact name, as Z-City does.", 0, 1)

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

-- ---------------------------------------------------------------------------------------------
-- bodies (jacket / T-shirt / trousers / shoes / gloves of Z-City) on models that name them differently
-- ---------------------------------------------------------------------------------------------
-- Z-City and the Appearance Mod put a body on by exact names: the body group of the model must be
-- called as the list of the menu calls it, and its part as the entry says ("sheet_tshirt_m").
-- The models of the other version of the pack (LEGACY, models/zcity/...) and other added models
-- may call the same things a little differently ("Sheet", "sheet_tshirt_m.smd", "sheet_tshirt",
-- "sheet_tshirt_f" on a model the menu counts as male): the choice then silently did nothing.
-- Here a name that has no exact match is looked for loosely. A name that matches exactly is left
-- to Z-City, nothing is done twice.
local function loose(name)
	name = string.lower(tostring(name or ""))
	name = string.gsub(name, "%.smd$", "")
	name = string.gsub(name, "%.dmx$", "")
	name = string.gsub(name, "[%s%-]+", "_")
	name = string.gsub(name, "_female$", "")
	name = string.gsub(name, "_male$", "")
	name = string.gsub(name, "_[mf]$", "")
	if name == "hand" then name = "hands" end
	return name
end

local function insensitive(tbl, key)
	if not istable(tbl) or not isstring(key) then return nil end
	if tbl[key] ~= nil then return tbl[key], key end
	local lower = string.lower(key)
	for k, v in pairs(tbl) do
		if isstring(k) and string.lower(k) == lower then return v, k end
	end
	return nil
end

-- The parts of the older body groups (TORSO and LEGS of ZCITY Clothing+: "Standard Top", "Wide Top",
-- "Shorts", "Boots Wider" ...) that the model of this entity has, for one window of the menu:
-- part "main" (jacket) - TORSO, "pants" - LEGS, "boots" - the boots of LEGS.
-- Returns { { key = name of the group in the list, name = name in the menu, group = id, index = part }, ... }
-- sorted by name, and whether the model has such a group at all.
local LEGACY_GROUP = { main = "TORSO", pants = "LEGS", boots = "LEGS" }

function ZCG.LegacyParts(part, ent, appearance)
	local wantedGroup = LEGACY_GROUP[part]
	local AP = hg and hg.Appearance
	local catalog = AP and AP.Bodygroups
	if not wantedGroup or not IsValid(ent) or not istable(appearance) or not istable(catalog) or not ent.GetBodyGroups then return {}, false end
	local list, key = insensitive(catalog, wantedGroup)
	local entry = ZCG.AppearanceModel(appearance.AModel)
	list = istable(list) and list[entry and entry.sex and 2 or 1]
	if not istable(list) then return {}, false end

	local out, has = {}, false
	for _, group in ipairs(ent:GetBodyGroups() or {}) do
		if isstring(group.name) and string.lower(group.name) == string.lower(wantedGroup) and istable(group.submodels) then
			has = true
			for name, data in pairs(list) do
				local wanted = istable(data) and data[1]
				if isstring(name) and isstring(wanted) and (part ~= "boots" or string.find(string.lower(name), "boot", 1, true)) then
					local exact, found
					for index = 0, #group.submodels do
						local sub = group.submodels[index]
						if sub == wanted then exact = index end
						if found == nil and isstring(sub) and loose(sub) == loose(wanted) then found = index end
					end
					local index = exact or found
					if index then out[#out + 1] = { key = key, name = name, group = group.id, index = index } end
				end
			end
			break
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out, has
end

-- Short sleeves by the name of a body that is worn ("sheet_tshirt_m"): the arms are bare. With
-- such a body this addon leaves the wearer alone altogether - nothing of the arms or hands is
-- hidden, shrunk or exchanged; a CS:GO glove is only drawn over the hand.
local SHORT = { "tshirt", "t_shirt", "t%-shirt", "shortsleeve", "short_sleeve", "sleeveless", "tanktop", "tank_top", "topless", "shirtless", "naked" }
function ZCG.ShortSleevesByName(ent)
	for _, group in ipairs(ent.GetBodyGroups and ent:GetBodyGroups() or {}) do
		local value = ent:GetBodygroup(group.id) or 0
		local name = istable(group.submodels) and group.submodels[value]
		-- (not the hands: "handsfortshirt" there is what a T-shirt gets, not what makes one)
		if isstring(name) and not (isstring(group.name) and string.lower(group.name) == "hands") then
			name = string.lower(name)
			for _, word in ipairs(SHORT) do
				if string.find(name, word) then return true end
			end
		end
	end
	return false
end

-- The older models keep the bare arms of a T-shirt as a part of the body group HANDS
-- ("handsfortshirt", in the menu "T-Shirt Hands"): with any other part of that group - the hands
-- alone, a glove - there are no arms under the short sleeves. Returns the index of such a part.
function ZCG.ArmsPart(group)
	if not istable(group) or not istable(group.submodels) then return nil end
	for index = 0, #group.submodels do
		local name = group.submodels[index]
		if isstring(name) then
			name = string.lower(name)
			for _, word in ipairs(SHORT) do
				if string.find(name, word) then return index end
			end
		end
	end
	return nil
end

-- puts on the bodies chosen in the appearance table that Z-City could not put on by exact name.
-- Returns how many body groups were set.
function ZCG.FixBodygroups(ent, appearance)
	if not ZCG.cvBodies:GetBool() then return 0 end
	local AP = hg and hg.Appearance
	local catalog = AP and AP.Bodygroups
	if not IsValid(ent) or not istable(appearance) or not istable(catalog) then return 0 end
	local chosen = appearance.ABodygroups
	if not istable(chosen) or not ent.GetBodyGroups then return 0 end
	local entry = ZCG.AppearanceModel(appearance.AModel)
	local sex = entry and entry.sex and 2 or 1

	local set = 0
	-- (the hands last: whether they are touched depends on the jacket that is on by then)
	local groups, hands = {}, {}
	for _, group in ipairs(ent:GetBodyGroups() or {}) do
		local isHands = isstring(group.name) and string.lower(group.name) == "hands"
		if isHands then hands[#hands + 1] = group else groups[#groups + 1] = group end
	end
	for _, group in ipairs(hands) do groups[#groups + 1] = group end
	for _, group in ipairs(groups) do
		local variant = insensitive(chosen, group.name)
		local list = insensitive(catalog, group.name)
		list = istable(list) and list[sex]
		local data = variant ~= nil and istable(list) and list[variant]
		local wanted = istable(data) and data[1]
		-- (HANDS as well: the models of the Appearance Mod name the glove parts "reggloves_FIN_M.smd"
		-- where Z-City asks for "reggloves_FIN_M", so Z-City itself never puts its gloves on them.
		-- A glove of Z-City is put on the way Z-City means it, on every jacket.)
		-- A CS:GO glove with short sleeves, on a model that keeps the bare arms of a T-shirt as a
		-- part of HANDS: that part instead of the hands alone - without it there are no arms.
		if istable(data) and data.ZCG and isstring(group.name) and string.lower(group.name) == "hands" and ZCG.ShortSleevesByName(ent) then
			local arms = ZCG.ArmsPart(group)
			if arms then
				wanted = nil
				if ent:GetBodygroup(group.id) ~= arms then
					ent:SetBodygroup(group.id, arms)
					set = set + 1
				end
			end
		end
		if isstring(wanted) and istable(group.submodels) then
			local exact, found = false, nil
			local want = loose(wanted)
			for index = 0, #group.submodels do
				local name = group.submodels[index]
				if name == wanted then exact = index end
				if found == nil and isstring(name) and loose(name) == want then found = index end
			end
			-- (an exact name under an exact group name is what Z-City already did)
			local zcity = exact and chosen[group.name] ~= nil and catalog[group.name] ~= nil
			local index = exact or found
			if not zcity and index and ent:GetBodygroup(group.id) ~= index then
				ent:SetBodygroup(group.id, index)
				set = set + 1
			end
		end
	end
	return set
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

-- Do the settings want the wearer's own hands hidden under this glove? (For a fingerless glove
-- that also means: drawn with its own fingers - see ZCG.Wearing in cl_render.lua, which knows
-- whether that is possible.)
function ZCG.HidesHands(variant)
	if not ZCG.cvHideHands:GetBool() then return false end
	if variant.fingerless and not ZCG.cvFingers:GetBool() then return false end
	local override = ZCG.Config.HideHands and ZCG.Config.HideHands[variant.family.id]
	if override ~= nil then return override and true or false end
	return true
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
