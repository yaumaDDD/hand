-- The functions the clothing packs of Z-City call by name.
--
-- The appearance of Z-City grows by calls: a pack names a player model, a piece of clothing, a
-- face, a bodygroup - and the tables of the gamemode take it in, and the menu shows a button for it.
-- Z-City keeps those functions inside its own files (they are local there), so a pack that calls
-- them by name falls over with "attempt to call global 'AppAddModel' (a nil value)" and everything
-- it brings is lost: no button, no clothes, no bodygroup. Which addon the pack came with does not
-- matter, and neither does the order the addons load in.
--
-- This file is that API, and this addon is the one that provides it, so that no other addon is
-- needed for the content a pack brings to reach the menu:
--
--   AppAddModel(name, model, female, submaterialSlots)     a player model and the slots of its clothes
--   AppAddClothes(sex, name, material, description, link)  a piece of clothing, sex 1/"male", 2/"female"
--   AppAddClothesDesc(name, { desc = ..., link = ... })    the description the menu shows for it
--   AddFacemap(slot, name, material, model)                a face: the material of the slot it replaces
--   AppAddBodygroup(group, name, submodel, female, pointshop, donate, cost, psModel, psBodygroups,
--                   psSubmats, psNameOveride)              a bodygroup and its item in the point shop
--
-- Everything is written the way Z-City writes it - the same tables, the same fields, the same
-- shapes - so that the gamemode, the Appearance Mod where it is installed, and the own menu of this
-- addon (own/sh_own.lua takes the tables into its catalog) read it as they are used to.
--
-- Nothing of anybody else is replaced: a function that is there already keeps its place (the
-- gamemode, the Appearance Mod, a fix addon of its own - and one that loads after this file wins,
-- as it should: its own registrations are remembered by it).
--
-- Every call is remembered (ZCGloves.Registered, in the order the calls came) and can be put into
-- the tables again - ZCG.ReplayRegistered(). A table that something makes anew after the packs have
-- run (the gamemode loading later, an addon that starts from scratch) loses what was put into it;
-- the watch of this addon (zcg_heal, sh_content.lua) puts back what is really gone.
--
-- hg.AppearanceFix is the namespace a pack of Z-City looks into before it includes a fix addon of
-- its own - "if not (hg and hg.AppearanceFix and hg.AppearanceFix.AddModel) then
-- include(\"autorun/sh_zcity_appearance_fix.lua\") end": with this addon there, that include does
-- not happen and the pack runs without a file it does not have.

ZCGloves = ZCGloves or {}

local ZCG = ZCGloves

ZCG.Registered = ZCG.Registered or {}          -- key -> { raw, there, args = { n = ..., ... }, what }
ZCG.RegisterOrder = ZCG.RegisterOrder or {}    -- the keys, in the order the calls came
ZCG.RegisterCalls = ZCG.RegisterCalls or 0     -- how many calls the tables took in
ZCG.RegisterBack = ZCG.RegisterBack or 0       -- how many of them went back into a table made anew
ZCG.RegisterAPI = ZCG.RegisterAPI or {}        -- the API of this addon, by the name a pack uses

hg = hg or {}

-- ---------------------------------------------------------------------------------------------
-- the tables, as Z-City has them
-- ---------------------------------------------------------------------------------------------

--- the appearance tables, each of them there (made the way the gamemode makes them). Made when a
--- pack calls for them and not before: an empty hg.Appearance of this addon's making would look to
--- own/sh_own.lua like the tables of somebody else's appearance system.
local function tables()
	hg.Appearance = hg.Appearance or {}
	local AP = hg.Appearance
	AP.PlayerModels = AP.PlayerModels or {}
	AP.PlayerModels[1] = AP.PlayerModels[1] or {}
	AP.PlayerModels[2] = AP.PlayerModels[2] or {}
	AP.FuckYouModels = AP.FuckYouModels or {}
	AP.FuckYouModels[1] = AP.FuckYouModels[1] or {}
	AP.FuckYouModels[2] = AP.FuckYouModels[2] or {}
	AP.Clothes = AP.Clothes or {}
	AP.Clothes[1] = AP.Clothes[1] or {}
	AP.Clothes[2] = AP.Clothes[2] or {}
	AP.ClothesDesc = AP.ClothesDesc or {}
	AP.FacemapsSlots = AP.FacemapsSlots or {}
	AP.FacemapsModels = AP.FacemapsModels or {}
	AP.Bodygroups = AP.Bodygroups or {}
	-- the API on the tables as well, for a pack that calls hg.Appearance.AppAddModel(...)
	for name, fn in pairs(ZCG.RegisterAPI.OnTables or {}) do
		if type(AP[name]) ~= "function" then AP[name] = fn end
	end
	return AP
end

--- what a pack may hand over for the sex of a thing: 1/2, "male"/"female", false/true
local function sexOf(sex)
	if sex == 2 or sex == true then return 2 end
	if type(sex) == "string" then
		local lower = string.lower(sex)
		if lower == "female" or lower == "f" or lower == "2" then return 2 end
	end
	return 1
end

local function text(value)
	return type(value) == "string" and value ~= ""
end

-- ---------------------------------------------------------------------------------------------
-- one call, written into the tables
-- ---------------------------------------------------------------------------------------------

local function rawModel(name, model, female, slots)
	local AP = tables()
	local sex = sexOf(female)
	local entry = { mdl = model, submatSlots = slots, sex = sex == 2 }
	AP.PlayerModels[sex][name] = entry
	-- (the gamemode finds a model by its path as well as by its name: the same entry, twice)
	AP.FuckYouModels[sex][model] = entry
end

local function rawFacemap(slot, name, material, model)
	local AP = tables()
	AP.FacemapsSlots[slot] = AP.FacemapsSlots[slot] or {}
	AP.FacemapsSlots[slot][name] = material
	if model ~= nil then AP.FacemapsModels[model] = slot end
end

local function rawClothes(sex, name, material, description, link)
	local AP = tables()
	local which = sexOf(sex)
	AP.Clothes[which][name] = material
	if description ~= nil or link ~= nil then
		AP.ClothesDesc[name] = { desc = description or "No description provided.", link = link }
	end
end

local function rawClothesDesc(name, entry)
	tables().ClothesDesc[name] = entry
end

local function rawBodygroup(group, name, submodel, female, pointshop, donate, cost, psModel, psBodygroups,
							psSubmats, psOveride)
	local AP = tables()
	local sex = sexOf(female)
	local id = "Standard_BodyGroups_" .. tostring(psOveride or name)
	AP.Bodygroups[group] = AP.Bodygroups[group] or {}
	AP.Bodygroups[group][sex] = AP.Bodygroups[group][sex] or {}
	-- (the entry of Z-City: the submodel, whether the point shop sells it, and the id of its item)
	AP.Bodygroups[group][sex][name] = { submodel, pointshop, ID = id }
	-- the item of the point shop, as the gamemode makes it: on the server, once per id
	local shop = hg.PointShop
	if SERVER and type(shop) == "table" and type(shop.CreateItem) == "function"
		and not (type(shop.Items) == "table" and shop.Items[id] ~= nil) then
		pcall(shop.CreateItem, shop, id,
			type(string.NiceName) == "function" and string.NiceName(name) or tostring(name),
			psModel or "models/zcity/gloves/degloves.mdl", psBodygroups, 0, Vector(0, 0, 0), cost, donate,
			psSubmats or {})
	end
end

-- ---------------------------------------------------------------------------------------------
-- remembered, so that it can be put back
-- ---------------------------------------------------------------------------------------------

local function register(key, kind, raw, there, ...)
	local entry = ZCG.Registered[key]
	if not entry then
		ZCG.RegisterOrder[#ZCG.RegisterOrder + 1] = key
		entry = {}
		ZCG.Registered[key] = entry
	end
	entry.raw = raw
	entry.there = there
	entry.what = kind
	-- (a pack that names the same thing again replaces what was remembered: the last call is the one
	-- that goes back into the tables when they are made anew)
	entry.args = { n = select("#", ...), ... }
	raw(...)
	ZCG.RegisterCalls = ZCG.RegisterCalls + 1
end

--- put the registrations into the tables again: what a table lost comes back, what it still holds
--- is left alone. Returns how many were missing and are there again.
function ZCG.ReplayRegistered()
	local back = 0
	for _, key in ipairs(ZCG.RegisterOrder) do
		local entry = ZCG.Registered[key]
		if entry and entry.raw then
			local there = false
			if entry.there then
				local ok, got = pcall(entry.there)
				there = ok and got and true or false
			end
			if not there then
				local ok, err = pcall(entry.raw, unpack(entry.args, 1, entry.args.n))
				if ok then
					back = back + 1
				elseif type(ErrorNoHalt) == "function" then
					ErrorNoHalt("[CS:GO Gloves] " .. tostring(key) .. " did not go back into the tables: "
						.. tostring(err) .. "\n")
				end
			end
		end
	end
	ZCG.RegisterBack = ZCG.RegisterBack + back
	return back
end

-- ---------------------------------------------------------------------------------------------
-- the API
-- ---------------------------------------------------------------------------------------------

local function addModel(name, model, female, slots)
	if not text(name) or not text(model) then return false end
	local sex = sexOf(female)
	register("model|" .. sex .. "|" .. name, "model", rawModel, function()
		local AP = hg.Appearance
		local list = type(AP) == "table" and type(AP.PlayerModels) == "table" and AP.PlayerModels[sex]
		local entry = type(list) == "table" and list[name]
		return type(entry) == "table" and entry.mdl == model
	end, name, model, female, slots)
	return true
end

local function addFacemap(slot, name, material, model)
	if not text(slot) or not text(name) then return false end
	register("face|" .. slot .. "|" .. name .. "|" .. tostring(model), "face", rawFacemap, function()
		local AP = hg.Appearance
		local list = type(AP) == "table" and type(AP.FacemapsSlots) == "table" and AP.FacemapsSlots[slot]
		return type(list) == "table" and list[name] ~= nil
	end, slot, name, material, model)
	return true
end

local function addClothes(sex, name, material, description, link)
	if not text(name) or not text(material) then return false end
	local which = sexOf(sex)
	register("cloth|" .. which .. "|" .. name, "cloth", rawClothes, function()
		local AP = hg.Appearance
		local list = type(AP) == "table" and type(AP.Clothes) == "table" and AP.Clothes[which]
		return type(list) == "table" and list[name] ~= nil
	end, sex, name, material, description, link)
	return true
end

local function addClothesDesc(name, entry)
	if not text(name) then return false end
	register("clothdesc|" .. name, "clothdesc", rawClothesDesc, function()
		local AP = hg.Appearance
		return type(AP) == "table" and type(AP.ClothesDesc) == "table" and AP.ClothesDesc[name] ~= nil
	end, name, entry)
	return true
end

local function addBodygroup(group, name, submodel, female, ...)
	if not text(group) or not text(name) then return false end
	local sex = sexOf(female)
	register("bg|" .. group .. "|" .. sex .. "|" .. name, "bg", rawBodygroup, function()
		local AP = hg.Appearance
		local by_sex = type(AP) == "table" and type(AP.Bodygroups) == "table" and AP.Bodygroups[group]
		local list = type(by_sex) == "table" and by_sex[sex]
		return type(list) == "table" and list[name] ~= nil
	end, group, name, submodel, female, ...)
	return true
end

ZCG.RegisterAPI.AddModel = addModel
ZCG.RegisterAPI.AddFacemap = addFacemap
ZCG.RegisterAPI.AddClothes = addClothes
ZCG.RegisterAPI.AddClothesDesc = addClothesDesc
ZCG.RegisterAPI.AddBodygroup = addBodygroup
ZCG.RegisterAPI.OnTables = { AppAddModel = addModel, AddFacemap = addFacemap, AppAddClothes = addClothes,
	AppAddClothesDesc = addClothesDesc, AppAddBodygroup = addBodygroup }

-- ---------------------------------------------------------------------------------------------
-- published where the packs look for the API
-- ---------------------------------------------------------------------------------------------
-- A function that is there already is left alone: the gamemode, the Appearance Mod or a fix addon
-- of its own keeps its own. (The names are assigned one by one, not through _G: a Lua file of the
-- game may run with a table of its own in place of the globals, and _G is not always that table.)

if type(AppAddModel) ~= "function" then AppAddModel = addModel end
if type(AddFacemap) ~= "function" then AddFacemap = addFacemap end
if type(AppAddClothes) ~= "function" then AppAddClothes = addClothes end
if type(AppAddClothesDesc) ~= "function" then AppAddClothesDesc = addClothesDesc end
if type(AppAddBodygroup) ~= "function" then AppAddBodygroup = addBodygroup end

-- (on hg.Appearance the API is published by tables(), when a pack first calls for it: the tables of
-- the gamemode are not made here before there is something to put into them)

-- the namespace a pack of Z-City checks before it includes a fix addon of its own
hg.AppearanceFix = hg.AppearanceFix or {}
local Fix = hg.AppearanceFix
ZCG.RegisterAPI.Version = "zcity_csgo_gloves " .. tostring(ZCG.Version or "")
Fix.Version = Fix.Version or ZCG.RegisterAPI.Version
if type(Fix.AddModel) ~= "function" then Fix.AddModel = addModel end
if type(Fix.AddFacemap) ~= "function" then Fix.AddFacemap = addFacemap end
if type(Fix.AddClothes) ~= "function" then Fix.AddClothes = addClothes end
if type(Fix.AddClothesDesc) ~= "function" then Fix.AddClothesDesc = addClothesDesc end
if type(Fix.AddBodygroup) ~= "function" then Fix.AddBodygroup = addBodygroup end
Fix.Data = Fix.Data or ZCG.Registered
Fix.Order = Fix.Order or ZCG.RegisterOrder
Fix.Replay = Fix.Replay or ZCG.ReplayRegistered

-- ---------------------------------------------------------------------------------------------
-- what it did: the console and zcg_content
-- ---------------------------------------------------------------------------------------------

--- whether the appearance tables hold nothing but what clothing packs put there by calling this
--- addon: such tables are content that arrived, not an appearance system of somebody else's, and
--- the catalog of this addon belongs next to them (own/sh_own.lua asks this before it decides that
--- the tables are somebody else's and leaves them alone)
function ZCG.RegisteredOnly(AP)
	if type(AP) ~= "table" or #ZCG.RegisterOrder == 0 then return false end
	local exact, faces, bodygroups = {}, {}, {}
	for _, key in ipairs(ZCG.RegisterOrder) do
		exact[key] = true
		local slot, name = string.match(key, "^face|([^|]*)|([^|]*)|")
		if slot then faces[slot .. "|" .. name] = true end
		local group, sex, name2 = string.match(key, "^bg|([^|]*)|([^|]*)|([^|]*)$")
		if group then bodygroups[group .. "|" .. sex .. "|" .. name2] = true end
	end
	-- What the sync of the faces put into the tables itself (sh_faces.lua: a face of one menu into
	-- the other, the faces of a sex for a model nobody wrote one for) is an entry of this addon and
	-- not the content of an appearance system of somebody else's - without it a pack that called
	-- this API would look like such a system the moment the sync ran (2.24.1).
	local synced = {}
	for _, one in ipairs(ZCG.FaceAdded or {}) do
		local path = one[6]
		if type(path) == "string" then
			local slot, name = string.match(path, "^(.*)/([^/]+)$")
			if slot then synced[slot .. "|" .. name] = true end
		end
	end
	local total, ours = 0, 0
	local function count(list, key)
		if type(list) ~= "table" then return end
		for name, entry in pairs(list) do
			total = total + 1
			-- an entry this addon made itself counts as ours as well: the gloves register their
			-- bodygroups in the same tables (sh_core.lua) and mark every one of them with ZCG
			if key(tostring(name)) or (type(entry) == "table" and entry.ZCG ~= nil) then ours = ours + 1 end
		end
	end
	for sex = 1, 2 do
		count(type(AP.PlayerModels) == "table" and AP.PlayerModels[sex],
			function(name) return exact["model|" .. sex .. "|" .. name] end)
		count(type(AP.Clothes) == "table" and AP.Clothes[sex],
			function(name) return exact["cloth|" .. sex .. "|" .. name] end)
	end
	for slot, list in pairs(type(AP.FacemapsSlots) == "table" and AP.FacemapsSlots or {}) do
		count(list, function(name)
			return faces[tostring(slot) .. "|" .. name] or synced[tostring(slot) .. "|" .. name]
		end)
	end
	for group, by_sex in pairs(type(AP.Bodygroups) == "table" and AP.Bodygroups or {}) do
		for sex = 1, 2 do
			count(type(by_sex) == "table" and by_sex[sex],
				function(name) return bodygroups[tostring(group) .. "|" .. sex .. "|" .. name] end)
		end
	end
	return total > 0 and total == ours
end

--- how many calls of which kind the tables took in: { model = 3, cloth = 40, ... }
function ZCG.RegisterCounts()
	local got = {}
	for _, key in ipairs(ZCG.RegisterOrder) do
		local entry = ZCG.Registered[key]
		local kind = (entry and entry.what) or "other"
		got[kind] = (got[kind] or 0) + 1
	end
	return got
end

--- one line for zcg_content, when a pack registered its content through this addon
function ZCG.RegisterReport(out)
	if #ZCG.RegisterOrder == 0 then return end
	local counts = ZCG.RegisterCounts()
	local names = { model = "models", cloth = "pieces of clothing", clothdesc = "descriptions",
		face = "faces", bg = "bodygroups" }
	local parts, rest = {}, {}
	for kind, label in pairs(names) do
		if counts[kind] then parts[#parts + 1] = counts[kind] .. " " .. label end
	end
	for kind, count in pairs(counts) do
		if not names[kind] then rest[#rest + 1] = count .. " " .. kind end
	end
	table.sort(parts)
	table.sort(rest)
	for _, line in ipairs(rest) do parts[#parts + 1] = line end
	out("  the Lua of the packs registered its content here: " .. #ZCG.RegisterOrder .. " names - "
		.. table.concat(parts, ", ") .. " (zcg_register names every one"
		.. (ZCG.RegisterBack > 0 and (", " .. ZCG.RegisterBack .. " went back into tables made anew") or "")
		.. ")")
end

concommand.Add("zcg_register" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	local lines = {}
	for _, key in ipairs(ZCG.RegisterOrder) do
		local entry = ZCG.Registered[key]
		local there = false
		if entry and entry.there then
			local ok, got = pcall(entry.there)
			there = ok and got and true or false
		end
		lines[#lines + 1] = (there and "  " or "  MISSING  ") .. tostring(key)
	end
	table.sort(lines)
	print("[CS:GO Gloves] the content the Lua of the packs registered through this addon: " .. #lines .. " names")
	for _, line in ipairs(lines) do print(line) end
	if #lines == 0 then
		print("  (no pack called AppAddModel / AppAddClothes / AddFacemap / AppAddBodygroup: the tables hold "
			.. "what the gamemode and its own Lua put there)")
	end
end, nil, "What the Lua of the clothing packs registered through this addon")
