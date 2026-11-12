-- Two versions of one clothing pack, together.
--
-- "Z-City Appearance Mod" and "Z-City Appearance Mod LEGACY" bring the same Lua files, so the game
-- can load only one of them. The newer one names nearly everything the older one does; what
-- differs is where the player models of the pack lie (models/slav/... - models/zcity/...) and a
-- few faces. Somebody who has the content of both wants both in the menu.
--
-- The build puts the table file of the version that is NOT loaded into lua/zcity_csgo_gloves/
-- merged/ (ZCGloves.Merged, sh_merged.lua). Here that file is run in a box: it sees a copy of the
-- appearance tables, its hooks and timers are caught and called by hand, so it fills the copy
-- the way it would have filled the tables of the game. Then the copy is compared with the tables:
--
--   a player model      under a name the menu does not have: added. Under a name the menu has
--                       for another model file: added as "<name> (LEGACY)".
--   a face              of a slot/name that is not there: added; one that is there with another
--                       material: added as "<name> (LEGACY)".
--   faces of a model    (MultiFacemaps, FacemapsModels, ModelFaceSlots: by model file) - what
--                       is not there is added.
--   clothes             under a name that is not there: added.
-- Nothing the loaded version made is changed. zcg_merge_versions 0 takes everything out again.

local ZCG = ZCGloves
local DIR = "zcity_csgo_gloves/"

ZCG.cvMerge = CreateConVar("zcg_merge_versions", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Appearance menu: 1 = the models and faces of the other version of the Appearance Mod (the one whose Lua is not loaded) "
	.. "are added to the menu next to those of the loaded one; 0 = they are not.", 0, 1)

ZCG.MergeAdded = ZCG.MergeAdded or {} -- { { table, key, value, where }, ... }
local compiled = {}
local HOOKS = { Initialize = true, InitPostEntity = true, OnGamemodeLoaded = true, PostGamemodeLoaded = true }
local COPIED = { "PlayerModels", "FuckYouModels", "Clothes", "ClothesDesc", "FacemapsSlots", "FacemapsModels",
	"MultiFacemaps", "ModelFaceSlots", "Bodygroups" }

local function nothing() end

-- is the entry still the one that was put there? (A face whose material file is not installed is
-- emptied for the time being - ZCG.FixFaces, sh_content.lua - and is the same face all the same.)
local function stands(entry)
	if not istable(entry[1]) then return false end
	local now = entry[1][entry[2]]
	return now == entry[3] or (now == "" and isstring(entry[3]))
end

local function copy(value, seen)
	if not istable(value) then return value end
	seen = seen or {}
	if seen[value] then return seen[value] end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do out[k] = copy(v, seen) end
	return out
end

local function suffixOf(title)
	if isstring(title) and string.find(string.upper(title), "LEGACY", 1, true) then return " (LEGACY)" end
	return " (2)"
end

-- runs one table file against a copy of the tables; returns the copy, or nil and the error
local function boxed(file)
	local fn = compiled[file]
	if fn == nil then
		fn = CompileFile(DIR .. file) or false
		compiled[file] = fn
	end
	if not fn then return nil, "the file " .. file .. " is not there" end
	local AP = hg.Appearance
	local shadow = setmetatable({}, { __index = AP })
	for _, name in ipairs(COPIED) do
		if istable(AP[name]) then shadow[name] = copy(AP[name]) end
	end
	local caught, later = {}, {}
	local env = setmetatable({
		hg = setmetatable({ Appearance = shadow }, { __index = hg }),
		hook = setmetatable({
			Add = function(event, _id, callback) if HOOKS[event] and isfunction(callback) then caught[#caught + 1] = callback end end,
			Remove = nothing, Run = nothing, Call = nothing,
		}, { __index = hook }),
		timer = setmetatable({
			Simple = function(_delay, callback) if isfunction(callback) then later[#later + 1] = callback end end,
			Create = function(_id, _delay, _times, callback) if isfunction(callback) then later[#later + 1] = callback end end,
			Remove = nothing, Exists = function() return false end,
		}, { __index = timer }),
		concommand = { Add = nothing, Remove = nothing },
		net = setmetatable({ Receive = nothing }, { __index = net or {} }),
		util = setmetatable({ AddNetworkString = nothing, PrecacheModel = nothing }, { __index = util or {} }),
		AddCSLuaFile = nothing,
		print = nothing, Msg = nothing, MsgN = nothing, MsgC = nothing,
		include = nothing,
	}, { __index = _G })
	setfenv(fn, env)
	local ok, err = pcall(fn)
	if not ok then return nil, err end
	for _, callback in ipairs(caught) do
		ok, err = pcall(callback)
		if not ok then return nil, err end
	end
	for i = 1, math.min(#later, 50) do pcall(later[i]) end
	return shadow
end

local function lower(text) return isstring(text) and string.lower(text) or text end

local roots = {} -- name of a table of hg.Appearance -> the table the entries were put into

local function put(list, key, value, where)
	list[key] = value
	local root = string.match(where, "^([^/]+)")
	roots[root] = hg.Appearance[root]
	ZCG.MergeAdded[#ZCG.MergeAdded + 1] = { list, key, value, where, root }
end

-- adds what `theirs` has and `mine` lacks, at any depth
local function addAbsent(mine, theirs, where)
	local count = 0
	for key, value in pairs(theirs) do
		if mine[key] == nil then
			put(mine, key, copy(value), where .. "/" .. tostring(key))
			count = count + 1
		elseif istable(mine[key]) and istable(value) then
			count = count + addAbsent(mine[key], value, where .. "/" .. tostring(key))
		end
	end
	return count
end

local function merge(AP, shadow, suffix)
	local count = 0
	-- player models
	for sex = 1, 2 do
		local mine = istable(AP.PlayerModels) and AP.PlayerModels[sex]
		local theirs = istable(shadow.PlayerModels) and shadow.PlayerModels[sex]
		if istable(mine) and istable(theirs) then
			local files = {}
			for _, entry in pairs(mine) do
				if istable(entry) then files[lower(entry.mdl)] = true end
			end
			for name, entry in pairs(theirs) do
				if istable(entry) and isstring(entry.mdl) and not files[lower(entry.mdl)] then
					local key = name
					if mine[key] ~= nil then key = tostring(name) .. suffix end
					if mine[key] == nil then
						local fresh = copy(entry)
						put(mine, key, fresh, "PlayerModels/" .. sex .. "/" .. tostring(key))
						files[lower(entry.mdl)] = true
						count = count + 1
						local byFile = istable(AP.FuckYouModels) and AP.FuckYouModels[sex]
						if istable(byFile) and byFile[entry.mdl] == nil then
							put(byFile, entry.mdl, fresh, "FuckYouModels/" .. sex .. "/" .. entry.mdl)
						end
					end
				end
			end
		end
	end
	-- faces by slot
	if istable(AP.FacemapsSlots) and istable(shadow.FacemapsSlots) then
		for slot, theirs in pairs(shadow.FacemapsSlots) do
			if istable(theirs) then
				local mine = AP.FacemapsSlots[slot]
				if mine == nil then
					put(AP.FacemapsSlots, slot, copy(theirs), "FacemapsSlots/" .. tostring(slot))
					count = count + 1
				elseif istable(mine) then
					local materials = {}
					for _, path in pairs(mine) do materials[lower(path)] = true end
					for _, entry in ipairs(ZCG.MergeAdded) do
						if entry[1] == mine then materials[lower(entry[3])] = true end
					end
					for name, path in pairs(theirs) do
						-- (an emptied face of that name is this very face, waiting for its file)
						if not materials[lower(path)] and mine[name] ~= "" then
							local key = name
							if mine[key] ~= nil then key = tostring(name) .. suffix end
							if mine[key] == nil then
								put(mine, key, path, "FacemapsSlots/" .. tostring(slot) .. "/" .. tostring(key))
								materials[lower(path)] = true
								count = count + 1
							end
						end
					end
				end
			end
		end
	end
	-- what is kept by model file, and the clothes
	for _, name in ipairs({ "FacemapsModels", "ModelFaceSlots", "MultiFacemaps", "Clothes", "ClothesDesc" }) do
		if istable(shadow[name]) then
			if AP[name] == nil then AP[name] = {} end
			if istable(AP[name]) then count = count + addAbsent(AP[name], shadow[name], name) end
		end
	end
	return count
end

function ZCG.MergeRemove()
	local count = 0
	for i = #ZCG.MergeAdded, 1, -1 do
		local entry = ZCG.MergeAdded[i]
		if stands(entry) then
			entry[1][entry[2]] = nil
			count = count + 1
		end
	end
	ZCG.MergeAdded = {}
	return count
end

-- puts the other version into the tables; returns how many entries stand for it, how many were
-- made by this call, and an error text when its file could not be run. Safe to call again.
function ZCG.MergeApply()
	local AP = hg and hg.Appearance
	if not istable(AP) or not istable(AP.PlayerModels) then return 0, 0 end
	if not istable(ZCG.Merged) or #ZCG.Merged == 0 or not (ZCG.cvMerge and ZCG.cvMerge:GetBool()) then
		ZCG.MergeRemove()
		return 0, 0
	end
	-- (entries of tables that were made anew are forgotten: the old tables are nobody's any more)
	local kept = {}
	for _, entry in ipairs(ZCG.MergeAdded) do
		if stands(entry) and roots[entry[5]] == AP[entry[5]] then kept[#kept + 1] = entry end
	end
	ZCG.MergeAdded = kept
	local before, trouble = #kept, nil
	for _, one in ipairs(ZCG.Merged) do
		local shadow, err = boxed(one.file)
		if shadow then
			merge(AP, shadow, suffixOf(one.title))
		else
			trouble = tostring(err)
		end
	end
	return #ZCG.MergeAdded, #ZCG.MergeAdded - before, trouble
end

function ZCG.MergeReport(out)
	if not istable(ZCG.Merged) or #ZCG.Merged == 0 then return end
	local ok, total, _made, trouble = pcall(ZCG.MergeApply)
	local titles = {}
	for _, one in ipairs(ZCG.Merged) do titles[#titles + 1] = "\"" .. tostring(one.title) .. "\"" end
	if not ok or trouble then
		out("  both versions together: the table file of " .. table.concat(titles, ", ") .. " could not be run: " .. tostring(trouble or total))
		return
	end
	if not (ZCG.cvMerge and ZCG.cvMerge:GetBool()) then
		out("  both versions together: zcg_merge_versions is 0 - what only " .. table.concat(titles, ", ") .. " has is not in the menu")
		return
	end
	local models = 0
	for _, entry in ipairs(ZCG.MergeAdded) do
		if string.sub(entry[4], 1, 13) == "PlayerModels/" then models = models + 1 end
	end
	out("  both versions together: " .. total .. " entries of the menu come from " .. table.concat(titles, ", ")
		.. ", whose Lua is not loaded - " .. models .. " of them player models (zcg_merge_list names them; zcg_merge_versions 0 takes them out)")
end

local told = -1
local function pass()
	local ok, total, _made, trouble = pcall(ZCG.MergeApply)
	if not ok or trouble then
		if told ~= -2 then
			told = -2
			ErrorNoHalt("[CS:GO Gloves] both versions together: " .. tostring(trouble or total) .. "\n")
		end
		return
	end
	if total ~= told and (total > 0 or told > 0) then
		ZCG.Print("both versions of the Appearance Mod together: " .. total .. " entries of the appearance menu were added for the "
			.. "version whose Lua is not loaded (zcg_merge_list names them, zcg_merge_versions 0 takes them out).")
	end
	told = total
end
ZCG.MergePass = pass

hook.Add("InitPostEntity", "zcg_merge", function()
	-- (after the loaded version has filled the tables on this very hook)
	for _, delay in ipairs({ 0, 1, 5, 15, 70 }) do timer.Simple(delay, pass) end
	timer.Create("zcg_merge", 120, 0, pass)
end)
if cvars and cvars.AddChangeCallback then
	cvars.AddChangeCallback("zcg_merge_versions", function() timer.Simple(0, pass) end, "zcg_merge")
end

concommand.Add("zcg_merge_list" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	pcall(ZCG.MergeApply)
	local lines = {}
	for _, entry in ipairs(ZCG.MergeAdded) do
		local value = entry[3]
		if istable(value) then value = value.mdl or "..." end
		lines[#lines + 1] = entry[4] .. "  =  " .. tostring(value)
	end
	table.sort(lines)
	print("[CS:GO Gloves] entries of the appearance menu added for the version whose Lua is not loaded: " .. #lines)
	for _, line in ipairs(lines) do print("  " .. line) end
end)
