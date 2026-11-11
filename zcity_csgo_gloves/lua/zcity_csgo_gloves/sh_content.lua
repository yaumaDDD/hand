-- Z-City CS:GO gloves - "is the content there?" (console command zcg_content)
--
-- The appearance system of Z-City only keeps names: the models of the player models and of the
-- accessories, the materials of the clothes and of the faces. Clothing packs add such names from
-- Lua; the files themselves (materials/..., models/...) have to be on the disk as well. A name
-- without its file shows as an ERROR model or as purple-black squares.
--
-- A model has names of its own on top of that: the materials it is made of. One of those that is
-- not installed does more harm than a purple patch - see sh_materials.lua.
--
-- zcg_content walks the tables as they are right now - whatever addons filled them - and lists
-- the names whose files this computer does not have:
--   * typed into the console of the game: the files of this player;
--   * typed into the console of a dedicated server (or zcg_content_server by a super admin):
--     the files of the server. It needs the models; the materials only matter to players.
-- A file that is missing where the game looks for it is often there all the same, a folder off
-- (materials/gate/x.vmt for materials/models/gate/x.vmt): the command looks for it by its name
-- and says so. Putting it in place is the job of sort_content.bat in the folder of the addon.
--
-- The names themselves can get lost as well: a Lua file of a clothing pack that did not load, an
-- addon that makes a table anew after others have added to it. The build of this addon runs the
-- Lua of the packs it carries and writes down what the tables hold then (sh_bound.lua, ZCG.Bound);
-- zcg_content compares the tables of the running game with that and names what is not there.

local ZCG = ZCGloves

local function has(path) return file.Exists(path, "GAME") end

local function clean(path)
	path = string.lower(string.gsub(path, "\\", "/"))
	return path
end

-- Calls visit(kind, path, who, entry) for every file the appearance tables name:
--   kind    "model" or "material"
--   path    as the table has it
--   who     what it is for ("male clothes Drill 01")
--   entry   where in the tables it stands ("Clothes/1/Drill 01"): one value per entry
-- (The tools of the addon run the Lua of the clothing packs outside of the game and read the
-- tables with this very function - tools/lua_names.py - so that sort_content.bat looks for the
-- same names zcg_content asks for.)
function ZCG.ContentWalk(visit)
	local function each(tbl, fn)
		if not istable(tbl) then return end
		for key, value in pairs(tbl) do fn(key, value) end
	end
	-- (not every value is a file: "null" is the game's name for a material that draws nothing,
	-- "!name" is a material made by Lua)
	local tell = visit
	visit = function(kind, path, who, entry)
		if not isstring(path) or path == "" then return end
		if kind == "material" and (string.lower(path) == "null" or string.sub(path, 1, 1) == "!") then return end
		tell(kind, path, who, entry)
	end

	local AP = istable(hg) and hg.Appearance
	if istable(AP) then
		for sex = 1, 2 do
			local whose = sex == 2 and "female" or "male"
			each(istable(AP.PlayerModels) and AP.PlayerModels[sex], function(name, entry)
				if istable(entry) then
					visit("model", entry.mdl, "player model " .. tostring(name), "PlayerModels/" .. sex .. "/" .. tostring(name))
				end
			end)
			each(istable(AP.Clothes) and AP.Clothes[sex], function(id, path)
				visit("material", path, whose .. " clothes " .. tostring(id), "Clothes/" .. sex .. "/" .. tostring(id))
			end)
		end
		each(AP.FacemapsSlots, function(slot, faces)
			each(faces, function(name, path)
				visit("material", path, "face " .. tostring(name), "FacemapsSlots/" .. tostring(slot) .. "/" .. tostring(name))
			end)
		end)
		-- (Z-City Appearance Mod) faces made of several materials
		each(AP.MultiFacemaps, function(model, faces)
			each(faces, function(name, slots)
				each(slots, function(slot, path)
					visit("material", path, "face " .. tostring(name),
						"MultiFacemaps/" .. tostring(model) .. "/" .. tostring(name) .. "/" .. tostring(slot))
				end)
			end)
		end)
	end

	each(istable(hg) and hg.Accessories, function(id, data)
		if not istable(data) then return end
		visit("model", data.model, "accessory " .. tostring(id), "Accessories/" .. tostring(id) .. "/model")
		visit("model", data.femmodel, "accessory " .. tostring(id), "Accessories/" .. tostring(id) .. "/femmodel")
	end)
end

-- every model and material the appearance tables name: path -> who wants it
-- (models as "models/x.mdl", materials without "materials/" and without ".vmt")
function ZCG.ContentNeeds()
	local models, materials = {}, {}

	ZCG.ContentWalk(function(kind, path, who)
		path = clean(path)
		if kind == "model" then
			if models[path] == nil then models[path] = who end
		else
			path = string.gsub(path, "^materials/", "")
			path = string.gsub(path, "%.vmt$", "")
			if materials[path] == nil then materials[path] = who end
		end
	end)

	return models, materials
end

-- The materials the models are made of, for every model of the list that is installed and can
-- be read. Returns how many there are and the ones that are in none of the folders their model
-- names: { { paths = { where it may lie, ... }, model = first model that needs it, more = other models } }
function ZCG.ModelMaterialsMissing(models)
	local count, missing, known = 0, {}, {}
	local paths = {}
	for path in pairs(models) do paths[#paths + 1] = path end
	table.sort(paths)

	for _, path in ipairs(paths) do
		local textures = has(path) and ZCG.ModelTextures(path) or nil
		for index = 1, textures and #textures.names or 0 do
			count = count + 1
			local candidates = ZCG.TexturePaths(textures, index)
			local found = false
			for _, candidate in ipairs(candidates) do
				if has("materials/" .. candidate .. ".vmt") then
					found = true
					break
				end
			end
			if not found then
				local key = table.concat(candidates, "|")
				local entry = known[key]
				if entry then
					entry.more = entry.more + 1
				else
					entry = { paths = candidates, model = path, more = 0 }
					known[key] = entry
					missing[#missing + 1] = entry
				end
			end
		end
	end
	return count, missing
end

-- The list of what is not there, sorted: "path  <-  who needs it". askMaterials: also ask the
-- material system of the game about a material without a file (that loads it, so only on
-- request and only on a client). Also returns how many models and materials the tables name and
-- how many materials the installed models are made of.
function ZCG.ContentMissing(askMaterials)
	local models, materials = ZCG.ContentNeeds()
	local missing, modelCount, materialCount = {}, 0, 0

	local function known(name)
		if has("materials/" .. name .. ".vmt") then return true end
		if not (askMaterials and CLIENT) then return false end
		local mat = Material(name)
		return mat ~= nil and not mat:IsError()
	end

	for path, who in pairs(models) do
		modelCount = modelCount + 1
		if not has(path) then missing[#missing + 1] = path .. "  <-  " .. who end
	end
	for name, who in pairs(materials) do
		materialCount = materialCount + 1
		if not known(name) then missing[#missing + 1] = "materials/" .. name .. ".vmt  <-  " .. who end
	end

	local ownCount, own = ZCG.ModelMaterialsMissing(models)
	for _, entry in ipairs(own) do
		local found = false
		for _, name in ipairs(entry.paths) do
			-- (one the tables name as well is in the list already)
			if materials[name] ~= nil or known(name) then
				found = true
				break
			end
		end
		if not found then
			local line = "materials/" .. entry.paths[1] .. ".vmt  <-  material of " .. entry.model
			if entry.more > 0 then line = line .. " and " .. entry.more .. " more models" end
			if #entry.paths > 1 then
				local others = {}
				for i = 2, #entry.paths do others[#others + 1] = "materials/" .. entry.paths[i] .. ".vmt" end
				line = line .. " (or " .. table.concat(others, ", ") .. ")"
			end
			missing[#missing + 1] = line
		end
	end

	table.sort(missing)
	return missing, modelCount, materialCount, ownCount
end

-- ---------------------------------------------------------------------------------------------
-- is everything in the tables that the clothing Lua of this addon puts there?
-- ---------------------------------------------------------------------------------------------
-- ZCG.Bound: Lua file -> { { entry of the tables (as ZCG.ContentWalk names it), its value
-- [, 1 = on the server only, 2 = on clients only] }, ... }. Returns how many entries this side
-- should have and the ones it does not have that way, sorted:
-- { { entry = , want = , by = Lua file, now = the value that is there instead, or nil }, ... }.
-- nil without the list (an addon built without the Lua of clothing packs, or where Lua could not
-- be run).
function ZCG.BoundMissing()
	local bound = ZCG.Bound
	if not istable(bound) then return nil end

	local now = {}
	ZCG.ContentWalk(function(_, path, _, entry) now[entry] = clean(path) end)

	local side = SERVER and 1 or 2
	local count, missing = 0, {}
	for by, entries in pairs(bound) do
		for _, item in ipairs(istable(entries) and entries or {}) do
			if istable(item) and isstring(item[1]) and isstring(item[2]) and (item[3] == nil or item[3] == side) then
				count = count + 1
				local have = now[item[1]]
				if have ~= item[2] then
					missing[#missing + 1] = { entry = item[1], want = item[2], by = tostring(by), now = have }
				end
			end
		end
	end
	table.sort(missing, function(a, b)
		if a.by ~= b.by then return a.by < b.by end
		return a.entry < b.entry
	end)
	return count, missing
end

-- the lines of zcg_content about that, through out(text); returns how many entries are not there
function ZCG.BoundReport(out)
	local count, missing = ZCG.BoundMissing()
	if not count then return 0 end
	if #missing == 0 then
		out("[CS:GO Gloves] the clothing Lua of this addon: all " .. count
			.. " clothes, faces, models and accessories it adds are in the appearance tables")
		return 0
	end

	out("[CS:GO Gloves] the clothing Lua of this addon: " .. #missing .. " of the " .. count
		.. " clothes, faces, models and accessories it adds are NOT in the appearance tables the way it puts them there:")
	local files, order = {}, {}
	for _, item in ipairs(missing) do
		if not files[item.by] then
			files[item.by] = 0
			order[#order + 1] = item.by
		end
		files[item.by] = files[item.by] + 1
	end
	for _, by in ipairs(order) do out("  lua/" .. by .. ": " .. files[by]) end
	local lines = {}
	for i, item in ipairs(missing) do
		lines[i] = item.entry .. " = " .. item.want
			.. (item.now and ("   [there is " .. item.now .. " instead]") or "   [not there]")
	end
	local shown = math.min(#lines, 40)
	for i = 1, shown do out("    " .. lines[i]) end
	if #lines > shown then
		out("    ... and " .. (#lines - shown) .. " more")
		for i, item in ipairs(missing) do lines[i] = "lua/" .. item.by .. ": " .. lines[i] end
		local written = pcall(file.Write, "zcg_bound.txt", table.concat(lines, "\n") .. "\n")
		if written then out("    the whole list is in garrysmod/data/zcg_bound.txt") end
	end
	out("  a Lua file that is named here did not run through (look for its name next to \"error\" further up in the"
		.. " console, on the server too), or something else made these tables anew or uses the same names")
	return #missing
end

-- ---------------------------------------------------------------------------------------------
-- the same file name under another path
-- ---------------------------------------------------------------------------------------------
-- Looked for in the addons and in the game folder first; in everything the game has mounted only
-- when those cannot be listed.
local PLACES = { "THIRDPARTY", "WORKSHOP", "DOWNLOAD", "MOD" }
local MAX_FOLDERS, MAX_SECONDS, MAX_PATHS = 40000, 8, 3

local function walk(root, where, names, found, seen, budget)
	local any = false
	local stack = { root }
	while #stack > 0 do
		local dir = table.remove(stack)
		budget.folders = budget.folders + 1
		if budget.folders > MAX_FOLDERS or SysTime() > budget.stop then
			budget.cut = true
			return any
		end
		local files, dirs = file.Find(dir .. "/*", where)
		for _, name in ipairs(files or {}) do
			any = true
			local lower = string.lower(name)
			if names[lower] then
				local path = string.lower(dir .. "/" .. name)
				if not seen[path] then
					seen[path] = true
					local list = found[lower]
					if not list then
						list = {}
						found[lower] = list
					end
					if #list < MAX_PATHS then list[#list + 1] = dir .. "/" .. name end
				end
			end
		end
		for _, name in ipairs(dirs or {}) do
			any = true
			stack[#stack + 1] = dir .. "/" .. name
		end
	end
	return any
end

-- names: { ["epl.vmt"] = true, ... } (lower case). Returns file name -> { paths, at most three }
-- for the names that exist somewhere below materials/ or models/, and true when the search had
-- to stop before it was through.
function ZCG.FindByName(names)
	local found, seen = {}, {}
	local budget = { folders = 0, stop = SysTime() + MAX_SECONDS, cut = false }
	local any = false
	for _, where in ipairs(PLACES) do
		for _, root in ipairs({ "materials", "models" }) do
			if walk(root, where, names, found, seen, budget) then any = true end
		end
	end
	if not any then
		for _, root in ipairs({ "materials", "models" }) do walk(root, "GAME", names, found, seen, budget) end
	end
	return found, budget.cut
end

local function fileName(line)
	local path = string.match(line, "^(.-)  <%-  ") or line
	return string.lower(string.match(path, "([^/]+)$") or path)
end

-- ---------------------------------------------------------------------------------------------
-- the report
-- ---------------------------------------------------------------------------------------------
-- prints the report line by line through out(text), returns the number of missing files
function ZCG.ContentReport(out)
	local missing, models, materials, own = ZCG.ContentMissing(true)
	out("[CS:GO Gloves] content check on the " .. (SERVER and "server" or "client") .. ": the appearance tables name "
		.. models .. " models and " .. materials .. " materials, the installed models are made of " .. own
		.. " materials; " .. #missing .. " files are missing")
	if #missing == 0 then
		ZCG.BoundReport(out)
		return 0
	end

	-- are they there, in another folder?
	local names = {}
	for _, line in ipairs(missing) do names[fileName(line)] = true end
	local ok, found, cut = pcall(ZCG.FindByName, names)
	if not ok then found, cut = {}, false end

	local lines, elsewhere, example = {}, 0, nil
	for i, line in ipairs(missing) do
		local paths = found[fileName(line)]
		if paths then
			elsewhere = elsewhere + 1
			example = example or paths[1]
			line = line .. "   [a file of that name: " .. table.concat(paths, ", ") .. "]"
		end
		lines[i] = line
	end

	local shown = math.min(#lines, 200)
	for i = 1, shown do out("  " .. lines[i]) end
	if #lines > shown then out("  ... and " .. (#lines - shown) .. " more") end

	local written = pcall(file.Write, "zcg_content.txt", table.concat(lines, "\n") .. "\n")
	if written then out("  the whole list is in garrysmod/data/zcg_content.txt") end

	if elsewhere > 0 then
		out("  " .. elsewhere .. " of them have a file of the same name in another folder (" .. tostring(example) .. " ...):"
			.. " the game only finds a file at its exact path")
		out("  close the game and start sort_content.bat in the folder of this addon (addons/zcity_csgo_gloves):"
			.. " it moves every file to its place")
		out("  (a file it cannot tell from a namesake of another pack stays where it is: its report,"
			.. " sort_content_report.txt, names such files - move those by hand)")
	else
		out("  put the files into the materials and models folders of this addon - in any folders - and start"
			.. " sort_content.bat there: it moves every file to its place. Then start the game again")
	end
	if cut then out("  (the search for the file names was stopped early: there are too many folders)") end
	if own > 0 then
		out("  a material that a model is made of and that is not installed leaves a purple and black part on that model")
	end
	ZCG.BoundReport(out)
	return #missing
end

-- one line when the tables do not hold what the clothing Lua of this addon puts there (a minute
-- after the start: that Lua may add things on timers)
local function boundNotice()
	timer.Simple(65, function()
		local ok, count, missing = pcall(ZCG.BoundMissing)
		if ok and count and istable(missing) and #missing > 0 then
			ZCG.Print(#missing .. " of the " .. count .. " clothes, faces and models that the clothing Lua of this addon adds "
				.. "are not in the appearance tables of the " .. (SERVER and "server" or "client")
				.. " - type zcg_content for the list.")
		end
	end)
end

if SERVER then
	local function command(caller)
		if IsValid(caller) and not caller:IsSuperAdmin() then return end
		ZCG.ContentReport(function(text)
			if IsValid(caller) then caller:PrintMessage(HUD_PRINTCONSOLE, text .. "\n") else print(text) end
		end)
	end
	-- on a listen server "zcg_content" typed into the game runs the client's command, hence two names
	concommand.Add("zcg_content", command)
	concommand.Add("zcg_content_server", command)

	-- one line in the server console when player models or accessories have no model file:
	-- that is always a mistake (ERROR models), unlike materials a dedicated server may not have
	hook.Add("InitPostEntity", "zcg_content", function()
		boundNotice()
		timer.Simple(10, function()
			local ok, models = pcall(ZCG.ContentNeeds)
			if not ok or not istable(models) then return end
			local count = 0
			for path in pairs(models) do
				if not has(path) then count = count + 1 end
			end
			if count > 0 then
				ZCG.Print(count .. " models named by the appearance tables are not on the server - "
					.. "type zcg_content in the server console for the list.")
			end
		end)
	end)
else
	concommand.Add("zcg_content", function() ZCG.ContentReport(print) end)

	-- one line in the console of a player whose game lacks files of the appearance menu
	hook.Add("InitPostEntity", "zcg_content", function()
		boundNotice()
		timer.Simple(15, function()
			local ok, missing = pcall(ZCG.ContentMissing, false)
			if ok and istable(missing) and #missing > 0 then
				ZCG.Print(#missing .. " models and materials of the appearance menu are not installed on this computer - "
					.. "type zcg_content for the list.")
			end
		end)
	end)
end
