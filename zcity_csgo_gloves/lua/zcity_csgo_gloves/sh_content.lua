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

local ZCG = ZCGloves

local function has(path) return file.Exists(path, "GAME") end

local function clean(path)
	path = string.lower(string.gsub(path, "\\", "/"))
	return path
end

-- every model and material the appearance tables name: path -> who wants it
-- (models as "models/x.mdl", materials without "materials/" and without ".vmt")
function ZCG.ContentNeeds()
	local models, materials = {}, {}

	local function model(path, who)
		if not isstring(path) or path == "" then return end
		path = clean(path)
		if models[path] == nil then models[path] = who end
	end
	local function material(path, who)
		if not isstring(path) or path == "" then return end
		path = clean(path)
		path = string.gsub(path, "^materials/", "")
		path = string.gsub(path, "%.vmt$", "")
		if materials[path] == nil then materials[path] = who end
	end
	local function each(tbl, fn)
		if not istable(tbl) then return end
		for key, value in pairs(tbl) do fn(key, value) end
	end

	local AP = istable(hg) and hg.Appearance
	if istable(AP) then
		for sex = 1, 2 do
			local whose = sex == 2 and "female" or "male"
			each(istable(AP.PlayerModels) and AP.PlayerModels[sex], function(name, entry)
				if istable(entry) then model(entry.mdl, "player model " .. tostring(name)) end
			end)
			each(istable(AP.Clothes) and AP.Clothes[sex], function(id, path)
				material(path, whose .. " clothes " .. tostring(id))
			end)
		end
		each(AP.FacemapsSlots, function(_, faces)
			each(faces, function(name, path) material(path, "face " .. tostring(name)) end)
		end)
		-- (Z-City Appearance Mod) faces made of several materials
		each(AP.MultiFacemaps, function(_, faces)
			each(faces, function(name, slots)
				each(slots, function(_, path) material(path, "face " .. tostring(name)) end)
			end)
		end)
	end

	each(istable(hg) and hg.Accessories, function(id, data)
		if not istable(data) then return end
		model(data.model, "accessory " .. tostring(id))
		model(data.femmodel, "accessory " .. tostring(id))
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
	if #missing == 0 then return 0 end

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
	else
		out("  put the files into the materials and models folders of this addon - in any folders - and start"
			.. " sort_content.bat there: it moves every file to its place. Then start the game again")
	end
	if cut then out("  (the search for the file names was stopped early: there are too many folders)") end
	if own > 0 then
		out("  a material that a model is made of and that is not installed leaves a purple and black part on that model")
	end
	return #missing
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
		timer.Simple(15, function()
			local ok, missing = pcall(ZCG.ContentMissing, false)
			if ok and istable(missing) and #missing > 0 then
				ZCG.Print(#missing .. " models and materials of the appearance menu are not installed on this computer - "
					.. "type zcg_content for the list.")
			end
		end)
	end)
end
