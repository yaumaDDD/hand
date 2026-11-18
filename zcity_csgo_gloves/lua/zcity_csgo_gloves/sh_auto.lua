-- Content that came without Lua.
--
-- A material is a thing of the appearance menu only when some Lua puts it into the tables of
-- Z-City. Content that was thrown into the addon without its Lua lies there and nothing wears it.
-- sort_content.bat writes down the materials nobody names - no Lua, no model - into sh_found.lua
-- (ZCGloves.Found = { "models/humans/male/group01/sheet_77", ... }), and here they are put
-- into the tables, each where the tables themselves show that it belongs:
--
--   a face       "<person>_facemap<anything>" / "<person>_cylmap<anything>", where a model of the
--                menu wears "<person>_facemap" or "<person>_cylmap" for a face (van_facemap_new ->
--                the faces of Male 01); or a material in a folder all listed faces of which are
--                faces of one model.
--   clothes      a material in a folder the tables name clothes in - for men, for women or both,
--                as the clothes of that folder are; or a material called "...sheet..." in a
--                folder ".../male/..." or ".../female/...".
--   anything else stays what it is: a file. zcg_content counts those.
--
-- The list is a Lua file of the server: clients get it from the server, so both sides have the
-- same tables whatever files a client has. zcg_found_content 0 takes everything out again.

local ZCG = ZCGloves

ZCG.cvFound = CreateConVar("zcg_found_content", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Appearance menu: 1 = materials that lie in the addon without any Lua naming them (sort_content.bat lists them) are "
	.. "added to the menu where they belong - faces to the faces of their model, clothes to the clothes; 0 = they are not.", 0, 1)

ZCG.cvScan = CreateConVar("zcg_scan_content", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Appearance menu: 1 = this addon looks through the materials/ of its own folder for content that no Lua names - "
	.. "what sort_content.bat writes into sh_found.lua, for an addon where the bat did not run - and puts it into the "
	.. "menu where it belongs; 0 = only the list of sh_found.lua is used.", 0, 1)

ZCG.cvPlacement = CreateConVar("zcg_fix_placement", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Appearance menu: 1 = an accessory whose pack forgot the place it is worn on (hg.Accessories[id].placement, the "
	.. "field the menus list accessories by) gets one - by the accessories that wear the same model, then by the words "
	.. "of its model and name - so that its button appears; 0 = every accessory stays as its pack made it.", 0, 1)

ZCG.FoundAdded = ZCG.FoundAdded or {} -- material -> { { table, key }, ... } the entries made for it
ZCG.FoundLeft = ZCG.FoundLeft or 0   -- materials of the list that fit nowhere

local function clean(path)
	path = string.lower(string.gsub(tostring(path), "\\", "/"))
	path = string.gsub(path, "%.vmt$", "")
	path = string.gsub(path, "^materials/", "")
	return path
end

local function folderOf(path) return string.match(path, "^(.*)/[^/]*$") or "" end
local function nameOf(path) return string.match(path, "([^/]*)$") or path end

local function personOf(name)
	return string.match(name, "^(.-)_facemap") or string.match(name, "^(.-)_cylmap")
end

local function hasSegment(folder, word)
	return string.find("/" .. folder .. "/", "/" .. word .. "/", 1, true) ~= nil
end

-- what the tables tell, without the entries made here
local function survey(AP)
	local mine = {}
	for _, entries in pairs(ZCG.FoundAdded) do
		for _, entry in ipairs(entries) do mine[entry[1]] = mine[entry[1]] or {} mine[entry[1]][entry[2]] = true end
	end
	local known = {
		named = {},        -- material -> true: it is in the tables already
		clothes = {},      -- folder -> { [1] = true, [2] = true }
		faces = {},        -- folder -> { slot = true }
		persons = {},      -- person -> slot, false when two slots share the person
	}
	for sex = 1, 2 do
		local list = istable(AP.Clothes) and AP.Clothes[sex]
		if istable(list) then
			for key, path in pairs(list) do
				if isstring(path) and path ~= "" and not (mine[list] and mine[list][key]) then
					local p = clean(path)
					known.named[p] = true
					local folder = folderOf(p)
					known.clothes[folder] = known.clothes[folder] or {}
					known.clothes[folder][sex] = true
				end
			end
		end
	end
	-- (what the models of the menu are made of is no thing to wear)
	if istable(AP.PlayerModels) then
		for sex = 1, 2 do
			for _, entry in pairs(istable(AP.PlayerModels[sex]) and AP.PlayerModels[sex] or {}) do
				for _, path in pairs(istable(entry) and istable(entry.submatSlots) and entry.submatSlots or {}) do
					if isstring(path) then known.named[clean(path)] = true end
				end
			end
		end
	end
	if istable(AP.FacemapsSlots) then
		for slot, list in pairs(AP.FacemapsSlots) do
			if isstring(slot) and istable(list) then
				local s = clean(slot)
				known.named[s] = true
				local person = personOf(nameOf(s))
				if person and person ~= "" then
					if known.persons[person] == nil then known.persons[person] = slot
					elseif known.persons[person] ~= slot then known.persons[person] = false end
				end
				for key, path in pairs(list) do
					if isstring(path) and path ~= "" and not (mine[list] and mine[list][key]) then
						local p = clean(path)
						known.named[p] = true
						local folder = folderOf(p)
						known.faces[folder] = known.faces[folder] or {}
						known.faces[folder][slot] = true
					end
				end
			end
		end
	end
	return known
end

-- where a material of the list belongs: "face", slot / "clothes", { sexes } / nil
function ZCG.FoundPlace(path, known)
	local folder, name = folderOf(path), nameOf(path)
	local person = personOf(name)
	if person and known.persons[person] then return "face", known.persons[person] end
	local faces, clothes = known.faces[folder], known.clothes[folder]
	if faces and not clothes then
		local slot, several
		for each in pairs(faces) do
			if slot then several = true end
			slot = each
		end
		if slot and not several then return "face", slot end
		return nil
	end
	if clothes and not faces then return "clothes", clothes end
	if faces or clothes then return nil end
	if string.find(name, "sheet", 1, true) then
		if hasSegment(folder, "female") then return "clothes", { [2] = true } end
		if hasSegment(folder, "male") then return "clothes", { [1] = true } end
	end
	return nil
end

local function freeKey(list, name, folder, path)
	local tries = { name, name .. " (" .. nameOf(folder) .. ")" }
	for i = 2, 50 do tries[#tries + 1] = name .. " (" .. i .. ")" end
	for _, key in ipairs(tries) do
		local now = list[key]
		if now == nil then return key end
		if isstring(now) and clean(now) == path then return nil end -- it is there already
	end
	return nil
end

-- --------------------------------------------------------------------------------------
-- the same list, found by this addon itself
-- --------------------------------------------------------------------------------------
-- sh_found.lua is a file sort_content.bat writes on the computer of the owner, and a file the build
-- writes for the addon it publishes: an addon that has neither - content thrown into the folder
-- afterwards, a build of an older version - has materials nobody names and nothing wears. Here the
-- addon looks for them itself, in the materials/ of its own folder when the game can see that
-- folder (ZCG.FindAddonFolder), and puts what it finds next to the list it was given.
--
-- A copy from the Workshop is mounted as an archive the game does not list folder by folder: there
-- this scan finds nothing at all, and the list the build ships is what the menu has. That is why
-- the build writes one (build_addon.py) and the bat writes it again on the owner's computer.
--
-- Only materials are looked for, and only such a one that no table names - the rule the bat has.
-- Of several files with one name the shortest path is taken, as the bat takes it.

-- the content of this addon itself: the gloves, the arms inside them, the icons - nothing to wear
local OWN_ROOTS = { "zcity_csgo_gloves/", "models/weapons/v_models/arms/" }
local SCAN_MAX_FOLDERS, SCAN_MAX_SECONDS, SCAN_MAX_FILES = 4000, 3, 8000

ZCG.FoundScan = ZCG.FoundScan or nil   -- the list of the scan (nil: there is nothing to scan)
ZCG.ScanFolders = ZCG.ScanFolders or 0 -- how many folders the last scan went through
ZCG.ScanCut = ZCG.ScanCut or false     -- the last scan was cut short by its budget

local function ownContent(path)
	for _, root in ipairs(OWN_ROOTS) do
		if string.sub(path, 1, #root) == root then return true end
	end
	return false
end

--- look through the materials of this addon for the ones no table names: the list the bat writes,
--- found by the addon itself. Returns how many were found and whether the walk was cut short.
function ZCG.ScanContent(force)
	if not (ZCG.cvScan and ZCG.cvScan:GetBool()) then
		ZCG.FoundScan = nil
		return 0, false
	end
	if ZCG.FoundScan and not force then return #ZCG.FoundScan, ZCG.ScanCut end
	local folder = ZCG.FindAddonFolder and ZCG.FindAddonFolder() or false
	if not folder then
		-- (a copy from the Workshop: the game does not list the folders of an archive it mounted)
		ZCG.FoundScan, ZCG.ScanCut, ZCG.ScanFolders = nil, false, 0
		return 0, false
	end
	local AP = hg and hg.Appearance
	local known = istable(AP) and survey(AP) or { named = {} }
	local root = folder .. "/materials"
	local stop = SysTime() + SCAN_MAX_SECONDS
	local by_name, folders, cut = {}, 0, false
	local stack = { root }
	while #stack > 0 do
		local dir = table.remove(stack)
		folders = folders + 1
		if folders > SCAN_MAX_FOLDERS or SysTime() > stop then
			cut = true
			break
		end
		local files, dirs = file.Find(dir .. "/*", "GAME")
		for _, name in ipairs(files or {}) do
			local lower = string.lower(name)
			if string.sub(lower, -4) == ".vmt" then
				local path = string.sub(string.lower(dir .. "/" .. name), #root + 2, -5)
				if path ~= "" and not ownContent(path) and not known.named[path] then
					local was = by_name[lower]
					if not was or #path < #was then by_name[lower] = path end
				end
			end
		end
		for _, name in ipairs(dirs or {}) do
			stack[#stack + 1] = dir .. "/" .. name
		end
	end
	local got = {}
	for _, path in pairs(by_name) do
		if #got < SCAN_MAX_FILES then got[#got + 1] = path end
	end
	if #got >= SCAN_MAX_FILES then cut = true end
	table.sort(got)
	ZCG.FoundScan, ZCG.ScanCut, ZCG.ScanFolders = got, cut, folders
	return #got, cut
end

--- the list the menu works through: what sh_found.lua brought and what the scan found, without a
--- path twice
function ZCG.FoundAll()
	local got, seen = {}, {}
	for _, list in ipairs({ ZCG.Found, ZCG.FoundScan }) do
		if istable(list) then
			for _, raw in ipairs(list) do
				local path = clean(raw)
				if path ~= "" and not seen[path] then
					seen[path] = true
					got[#got + 1] = path
				end
			end
		end
	end
	return got
end

-- --------------------------------------------------------------------------------------
-- an accessory that came without the place it is worn on
-- --------------------------------------------------------------------------------------
-- The menus of Z-City list accessories by the place they are worn on - hg.Accessories[id].placement:
-- "head", "face", "ears", "spine", "torso". An accessory whose pack forgot the field draws on the
-- player all the same and has no button in any menu of Z-City: nothing lists it. (The masks of
-- Z-City are the ones that get forgotten - arctic_balaclava, phoenix_balaclava - and a pack of its
-- own is written just to put "face" onto them afterwards.)
--
-- Here the place is filled in for an accessory that has none, and the way it is looked for is the
-- way the content of Z-City itself is made: the accessories that wear the same model say where it
-- belongs (the pink earmuffs wear the model of the green, red and yellow ones, and those are
-- "ears"), and only where no such accessory is there the words of the model and of the name are
-- looked through. A place a pack wrote is left alone, and what was filled in here is taken back
-- when zcg_fix_placement is 0.

ZCG.PlacementAdded = ZCG.PlacementAdded or {}   -- accessory -> the place this addon gave it

-- the places the menus of Z-City know, in the order they are tried
local PLACES = { "head", "face", "ears", "spine", "torso" }

-- a word of a model or of a name -> the place; the first word that is there wins, so a long one
-- stands before the short one it holds ("earmuffs" before "ear")
local PLACE_WORDS = {
	{ "earmuff", "ears" }, { "headphone", "ears" }, { "earring", "ears" }, { "ear", "ears" },
	{ "balaclava", "face" }, { "bandana", "face" }, { "mask", "face" }, { "beard", "face" },
	{ "glasses", "face" }, { "goggles", "face" }, { "visor", "face" }, { "mouth", "face" }, { "face", "face" },
	{ "fedora", "head" }, { "helmet", "head" }, { "hood", "head" }, { "cap", "head" }, { "hat", "head" },
	{ "head", "head" }, { "wig", "head" }, { "hair", "head" },
	{ "backpack", "spine" }, { "wings", "spine" }, { "armband", "spine" }, { "back", "spine" },
	{ "scarf", "torso" }, { "vest", "torso" }, { "chest", "torso" }, { "bag", "torso" }, { "torso", "torso" },
}

local function knownPlace(value)
	if not isstring(value) then return nil end
	local lower = string.lower(value)
	for _, place in ipairs(PLACES) do
		if place == lower then return lower end
	end
	return nil
end

--- the place an accessory is worn on, as the other accessories say it: by the model they share,
--- then by the words of its own model and name
local function placeOf(list, id, entry)
	local models = {}
	for _, field in ipairs({ "model", "femmodel" }) do
		if isstring(entry[field]) and entry[field] ~= "" then models[#models + 1] = string.lower(entry[field]) end
	end
	for _, other in pairs(list) do
		if istable(other) and other ~= entry and knownPlace(other.placement) then
			for _, model in ipairs(models) do
				if string.lower(other.model or "") == model or string.lower(other.femmodel or "") == model then
					return knownPlace(other.placement)
				end
			end
		end
	end
	local words = {}
	for _, model in ipairs(models) do words[#words + 1] = model end
	words[#words + 1] = string.lower(tostring(id))
	if isstring(entry.name) then words[#words + 1] = string.lower(entry.name) end
	for _, where in ipairs(words) do
		for _, word in ipairs(PLACE_WORDS) do
			if string.find(where, word[1], 1, true) then return word[2] end
		end
	end
	return nil
end

--- fill in the places the packs forgot; returns how many accessories got one and how many places
--- were taken back (zcg_fix_placement 0)
function ZCG.HealAccessories()
	local list = hg and hg.Accessories
	if not istable(list) then return 0, 0 end
	-- switched off: what was filled in here is taken back, and only that (an entry a pack wrote
	-- itself - the masks of Z-City, a pack of accessories - is left as its pack made it)
	if not (ZCG.cvPlacement and ZCG.cvPlacement:GetBool()) then
		local took = 0
		for id, place in pairs(ZCG.PlacementAdded) do
			local entry = list[id]
			if istable(entry) and entry.placement == place then
				entry.placement = nil
				took = took + 1
			end
			ZCG.PlacementAdded[id] = nil
		end
		return 0, took
	end
	-- a place this addon gave and somebody took away again is looked for once more (a Lua refresh,
	-- a pack that builds the tables anew)
	for id, place in pairs(ZCG.PlacementAdded) do
		local entry = list[id]
		if not (istable(entry) and entry.placement == place) then ZCG.PlacementAdded[id] = nil end
	end
	local made = 0
	for id, entry in pairs(list) do
		if istable(entry) and not knownPlace(entry.placement) and not ZCG.PlacementAdded[id] then
			local ok, place = pcall(placeOf, list, id, entry)
			if ok and place then
				entry.placement = place
				ZCG.PlacementAdded[id] = place
				made = made + 1
			end
		end
	end
	return made, 0
end

--- one line for zcg_content
function ZCG.AccessoryReport(out)
	local list = hg and hg.Accessories
	if not istable(list) then return end
	local without = 0
	for id, entry in pairs(list) do
		if istable(entry) and not knownPlace(entry.placement) then without = without + 1 end
	end
	local names = {}
	for id, place in pairs(ZCG.PlacementAdded) do names[#names + 1] = tostring(id) .. " (" .. place .. ")" end
	table.sort(names)
	if #names == 0 and without == 0 then return end
	out("  accessories without the place they are worn on: " .. #names .. " got one by this addon"
		.. (without > 0 and (", " .. without .. " have none and no menu of Z-City lists them") or "")
		.. (ZCG.cvPlacement and ZCG.cvPlacement:GetBool() and "" or " - zcg_fix_placement is 0, they are taken back")
		.. (#names > 0 and (" (" .. table.concat(names, ", ", 1, math.min(#names, 6))
			.. (#names > 6 and ", ..." or "") .. "; zcg_fix_placement 0 leaves them as their packs made them)") or ""))
end

-- takes out what was put in (an entry somebody changed since is not touched)
function ZCG.FoundRemove()
	local count = 0
	for path, entries in pairs(ZCG.FoundAdded) do
		for _, entry in ipairs(entries) do
			local list, key = entry[1], entry[2]
			if istable(list) and isstring(list[key]) and clean(list[key]) == path then
				list[key] = nil
				count = count + 1
			end
		end
	end
	ZCG.FoundAdded = {}
	return count
end

-- puts the materials of the list into the tables; returns how many entries are there for them
-- now, and how many were made by this very call. Safe to call again and again.
function ZCG.FoundApply()
	local AP = hg and hg.Appearance
	if not istable(AP) or not istable(AP.Clothes) then return 0, 0 end
	if not (ZCG.cvFound and ZCG.cvFound:GetBool()) or #ZCG.FoundAll() == 0 then
		ZCG.FoundRemove()
		ZCG.FoundLeft = 0
		return 0, 0
	end
	local known = survey(AP)
	local total, made, left = 0, 0, 0
	for _, raw in ipairs(ZCG.FoundAll()) do
		local path = clean(raw)
		local entries = ZCG.FoundAdded[path]
		-- (tables that were made anew since have lost the entries: they are made again)
		local alive = false
		if entries then
			alive = #entries > 0
			for _, entry in ipairs(entries) do
				local owner = entry[3]
				if not (istable(entry[1]) and owner() == entry[1] and isstring(entry[1][entry[2]]) and clean(entry[1][entry[2]]) == path) then
					alive = false
				end
			end
		end
		if alive then
			total = total + #entries
		elseif known.named[path] then
			ZCG.FoundAdded[path] = nil -- some Lua names it by now: it is not ours to add
		else
			local kind, where = ZCG.FoundPlace(path, known)
			local fresh = {}
			if kind == "face" then
				local list = AP.FacemapsSlots[where]
				if istable(list) then
					local key = freeKey(list, nameOf(path), folderOf(path), path)
					if key then
						list[key] = path
						fresh[#fresh + 1] = { list, key, function() return hg.Appearance.FacemapsSlots and hg.Appearance.FacemapsSlots[where] end, "FacemapsSlots/" .. tostring(where) .. "/" .. key }
					end
				end
			elseif kind == "clothes" then
				for sex = 1, 2 do
					local list = where[sex] and AP.Clothes[sex]
					if istable(list) then
						local key = freeKey(list, nameOf(path), folderOf(path), path)
						if key then
							list[key] = path
							fresh[#fresh + 1] = { list, key, function() return hg.Appearance.Clothes and hg.Appearance.Clothes[sex] end, "Clothes/" .. sex .. "/" .. key }
						end
					end
				end
			end
			if #fresh > 0 then
				ZCG.FoundAdded[path] = fresh
				total, made = total + #fresh, made + #fresh
			else
				ZCG.FoundAdded[path] = nil
				if not kind then left = left + 1 end
			end
		end
	end
	ZCG.FoundLeft = left
	return total, made
end

-- lines for zcg_content
function ZCG.FoundReport(out)
	local listed, scanned = istable(ZCG.Found) and #ZCG.Found or 0, istable(ZCG.FoundScan) and #ZCG.FoundScan or 0
	if listed + scanned == 0 then return end
	local where = (listed > 0 and (scanned > 0 and "sort_content.bat listed " .. listed
			.. " of them and this addon found " .. scanned .. " more in its own materials/")
		or (listed > 0 and "sort_content.bat listed " .. listed .. " of them")
		or ("this addon found " .. scanned .. " of them in its own materials/"))
	local ok, total = pcall(ZCG.FoundApply)
	if not ok then
		out("  content without Lua: " .. tostring(total))
		return
	end
	if not (ZCG.cvFound and ZCG.cvFound:GetBool()) then
		out("  content without Lua: " .. #ZCG.FoundAll() .. " materials nobody names - " .. where
			.. "; zcg_found_content is 0, so none is in the menu")
		return
	end
	local faces, clothes, materials = 0, 0, 0
	for _, entries in pairs(ZCG.FoundAdded) do
		materials = materials + 1
		for _, entry in ipairs(entries) do
			if string.sub(entry[4], 1, 8) == "Clothes/" then clothes = clothes + 1 else faces = faces + 1 end
		end
	end
	out("  content without Lua: " .. #ZCG.FoundAll() .. " materials nobody names - " .. where .. "; " .. materials
		.. " of them are in the menu now (" .. faces .. " as faces, " .. clothes .. " as clothes), " .. ZCG.FoundLeft
		.. " fit nowhere and stay files (zcg_found_list names every one; zcg_found_content 0 takes them out)")
end

local told, toldAccessories = -1, -1
local function pass()
	-- what the addon has and no Lua names: found in its own folder, and the places the packs forgot
	pcall(ZCG.ScanContent)
	local healed = 0
	local okHeal, madeAccessories, tookAccessories = pcall(ZCG.HealAccessories)
	if okHeal then healed = madeAccessories end
	-- the own appearance system looks at the tables of the game first (own/sh_own.lua): entries
	-- this addon puts in them must not look to it like the content of a system of somebody else's.
	-- Its hook of InitPostEntity is after this one, so the pass a second later does the rest.
	if ZCO and not ZCO.Decided then return end
	local ok, total, made = pcall(ZCG.FoundApply)
	if not ok then
		if told ~= -2 then
			told = -2
			ErrorNoHalt("[CS:GO Gloves] content without Lua: " .. tostring(total) .. "\n")
		end
		return
	end
	if total ~= told and (total > 0 or told > 0) then
		ZCG.Print("content without Lua: " .. total .. " entries of the appearance menu stand for materials that lie in the addon "
			.. "and that no Lua names (zcg_found_list names them, zcg_found_content 0 takes them out).")
	end
	if healed > 0 and toldAccessories ~= healed then
		ZCG.Print("accessories without a place: " .. healed .. " of them got the place they are worn on, so that the menus "
			.. "of Z-City list them (zcg_fix_placement 0 leaves every accessory as its pack made it).")
	end
	toldAccessories = healed
	told = total
end
ZCG.FoundPass = pass

hook.Add("InitPostEntity", "zcg_found", function()
	pass()
	for _, delay in ipairs({ 1, 5, 15, 70 }) do timer.Simple(delay, pass) end
	timer.Create("zcg_found", 120, 0, pass)
end)
if cvars and cvars.AddChangeCallback then
	cvars.AddChangeCallback("zcg_found_content", function() timer.Simple(0, pass) end, "zcg_found")
	cvars.AddChangeCallback("zcg_scan_content", function() ZCG.FoundScan = nil timer.Simple(0, pass) end, "zcg_found")
	cvars.AddChangeCallback("zcg_fix_placement", function() timer.Simple(0, pass) end, "zcg_found")
end

--- look through the materials of this addon by hand: what it found and what it made of it
concommand.Add("zcg_found_scan" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	local folder = ZCG.FindAddonFolder and ZCG.FindAddonFolder() or false
	if not folder then
		print("[CS:GO Gloves] the folder of this addon is not there to look through: the game mounted it as an "
			.. "archive (a copy from the Workshop). What the build shipped is in lua/zcity_csgo_gloves/sh_found.lua"
			.. (istable(ZCG.Found) and (" - " .. #ZCG.Found .. " materials") or " - and there is none") .. ".")
		return
	end
	local count, cut = ZCG.ScanContent(true)
	print("[CS:GO Gloves] the materials of " .. folder .. "/materials that no Lua and no model names: " .. count
		.. " (" .. ZCG.ScanFolders .. " folders" .. (cut and ", the walk was cut short by its budget" or "") .. ")")
	for _, path in ipairs(ZCG.FoundScan or {}) do print("  " .. path) end
	local made, took = ZCG.HealAccessories()
	print("[CS:GO Gloves] the accessories that got the place they are worn on: " .. made
		.. (took > 0 and (", " .. took .. " places taken back") or ""))
	pcall(ZCG.FoundApply)
	pcall(pass)
end, nil, "Look through the materials of this addon for the content no Lua names, now")
-- (a Lua file loaded again while the game runs)
if hg and istable(hg.Appearance) then pass() end

concommand.Add("zcg_found_list" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	pcall(ZCG.FoundApply)
	local lines = {}
	for path, entries in pairs(ZCG.FoundAdded) do
		for _, entry in ipairs(entries) do lines[#lines + 1] = entry[4] .. "  =  " .. path end
	end
	table.sort(lines)
	print("[CS:GO Gloves] content without Lua in the appearance menu: " .. #lines .. " entries")
	for _, line in ipairs(lines) do print("  " .. line) end
	local known = hg and istable(hg.Appearance) and survey(hg.Appearance)
	if known then
		local rest = {}
		for _, raw in ipairs(ZCG.FoundAll()) do
			local path = clean(raw)
			if not ZCG.FoundAdded[path] and not known.named[path] then rest[#rest + 1] = path end
		end
		table.sort(rest)
		print("[CS:GO Gloves] materials that fit nowhere (they stay files): " .. #rest)
		for _, path in ipairs(rest) do print("  " .. path) end
	end
end)
