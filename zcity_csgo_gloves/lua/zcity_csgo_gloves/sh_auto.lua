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
	if not (ZCG.cvFound and ZCG.cvFound:GetBool()) or not istable(ZCG.Found) then
		ZCG.FoundRemove()
		ZCG.FoundLeft = 0
		return 0, 0
	end
	local known = survey(AP)
	local total, made, left = 0, 0, 0
	for _, raw in ipairs(ZCG.Found) do
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
	if not istable(ZCG.Found) or #ZCG.Found == 0 then return end
	local ok, total = pcall(ZCG.FoundApply)
	if not ok then
		out("  content without Lua: " .. tostring(total))
		return
	end
	if not (ZCG.cvFound and ZCG.cvFound:GetBool()) then
		out("  content without Lua: sort_content.bat listed " .. #ZCG.Found .. " materials nobody names; zcg_found_content is 0, so none is in the menu")
		return
	end
	local faces, clothes, materials = 0, 0, 0
	for _, entries in pairs(ZCG.FoundAdded) do
		materials = materials + 1
		for _, entry in ipairs(entries) do
			if string.sub(entry[4], 1, 8) == "Clothes/" then clothes = clothes + 1 else faces = faces + 1 end
		end
	end
	out("  content without Lua: sort_content.bat listed " .. #ZCG.Found .. " materials nobody names; " .. materials
		.. " of them are in the menu now (" .. faces .. " as faces, " .. clothes .. " as clothes), " .. ZCG.FoundLeft
		.. " fit nowhere and stay files (zcg_found_list names every one; zcg_found_content 0 takes them out)")
end

local told = -1
local function pass()
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
end
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
	if known and istable(ZCG.Found) then
		local rest = {}
		for _, raw in ipairs(ZCG.Found) do
			local path = clean(raw)
			if not ZCG.FoundAdded[path] and not known.named[path] then rest[#rest + 1] = path end
		end
		table.sort(rest)
		print("[CS:GO Gloves] materials that fit nowhere (they stay files): " .. #rest)
		for _, path in ipairs(rest) do print("  " .. path) end
	end
end)
