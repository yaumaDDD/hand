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
--
-- A face without its file does harm beyond its own line in the menu: Z-City hands faces out by
-- chance, so everybody may get purple and black squares for a face. zcg_content counts such
-- faces; with zcg_fix_faces 1 they show the own face of the model until the file is there
-- (ZCG.FixFaces).

local ZCG = ZCGloves

local function has(path) return file.Exists(path, "GAME") end

local function clean(path)
	path = string.lower(string.gsub(path, "\\", "/"))
	return path
end

-- Calls visit(kind, path, who, entry, slot, model) for every file the appearance tables name:
--   kind    "model" or "material"
--   path    as the table has it
--   who     what it is for ("male clothes Drill 01")
--   entry   where in the tables it stands ("Clothes/1/Drill 01"): one value per entry
--   slot, model   of a face: the material of the model it is put over, the model it is listed for
-- (The tools of the addon run the Lua of the clothing packs outside of the game and read the
-- tables with this very function - tools/lua_names.py - so that sort_content.bat looks for the
-- same names zcg_content asks for.)
function ZCG.ContentWalk(visit)
	local function each(tbl, fn)
		if not istable(tbl) then return end
		for key, value in pairs(tbl) do fn(key, value) end
	end
	-- (not every value is a file: "null" is the game's name for a material that draws nothing,
	-- "!name" is a material made by Lua. A face whose file is not there holds the empty material
	-- for the time being - ZCG.FixFaces - and is walked with the name the clothing Lua gave it.)
	local faceless = ZCG.Faceless
	local tell = visit
	visit = function(kind, path, who, entry, slot, model)
		if path == "" and faceless and faceless[entry] then path = faceless[entry] end
		if not isstring(path) or path == "" then return end
		if kind == "material" and (string.lower(path) == "null" or string.sub(path, 1, 1) == "!") then return end
		tell(kind, path, who, entry, slot, model)
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
		-- (a face: the fifth argument is the material of the model it is put over - its "slot")
		each(AP.FacemapsSlots, function(slot, faces)
			each(faces, function(name, path)
				visit("material", path, "face " .. tostring(name), "FacemapsSlots/" .. tostring(slot) .. "/" .. tostring(name), slot)
			end)
		end)
		-- (Z-City Appearance Mod) faces made of several materials, by model: the sixth argument
		each(AP.MultiFacemaps, function(model, faces)
			each(faces, function(name, slots)
				each(slots, function(slot, path)
					visit("material", path, "face " .. tostring(name),
						"MultiFacemaps/" .. tostring(model) .. "/" .. tostring(name) .. "/" .. tostring(slot), slot, model)
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

-- The face materials ("slots") that a player model of the menu has, and those models, lower
-- case: { [slot] = true }, { [model] = true }.
-- Z-City changes a face through the name of the material it stands for: for every material of
-- the model it looks up FacemapsSlots[that material][name of the face]. A list of faces for a
-- material that no player model has is a list nobody can wear - a pack that brought player
-- models of its own leaves such lists behind when another pack replaces those models.
-- What the Lua says counts (FacemapsModels, the Appearance Mod's ModelFaceSlots) and what the
-- model file says. nil when that cannot be told: no player models, or one of them is not
-- installed or cannot be read - its materials are not known then.
function ZCG.FaceSlotsInUse()
	local AP = istable(hg) and hg.Appearance
	if not istable(AP) or not istable(AP.PlayerModels) or not istable(AP.FacemapsSlots) then return nil end

	local slots = {}
	for slot in pairs(AP.FacemapsSlots) do
		if isstring(slot) then slots[clean(slot)] = true end
	end
	local said = {}
	local function say(model, slot)
		if not isstring(model) or not isstring(slot) then return end
		model = clean(model)
		said[model] = said[model] or {}
		said[model][clean(slot)] = true
	end
	if istable(AP.FacemapsModels) then
		for model, slot in pairs(AP.FacemapsModels) do say(model, slot) end
	end
	if istable(AP.ModelFaceSlots) then
		for model, list in pairs(AP.ModelFaceSlots) do
			if istable(list) then
				for slot in pairs(list) do say(model, slot) end
			end
		end
	end

	local used, models = {}, {}
	for sex = 1, 2 do
		for _, entry in pairs(istable(AP.PlayerModels[sex]) and AP.PlayerModels[sex] or {}) do
			local model = istable(entry) and isstring(entry.mdl) and clean(entry.mdl) or nil
			if model and not models[model] then
				models[model] = true
				for slot in pairs(said[model] or {}) do used[slot] = true end
				local textures = ZCG.ModelTextures and has(model) and ZCG.ModelTextures(model) or nil
				if not textures then return nil end
				for index = 1, #textures.names do
					for _, path in ipairs(ZCG.TexturePaths(textures, index)) do
						path = clean(path)
						if slots[path] then used[path] = true end
					end
				end
			end
		end
	end
	-- (no slot of any player model known: that is not "nobody can wear a face")
	if next(models) == nil or next(used) == nil then return nil end
	return used, models
end

-- every model and material the appearance tables name: path -> who wants it
-- (models as "models/x.mdl", materials without "materials/" and without ".vmt"). Third: the
-- materials only faces nobody can wear ask for (ZCG.FaceSlotsInUse) - those are not in the second.
-- Fourth: the materials among the second that are faces - { [material] = true }.
function ZCG.ContentNeeds()
	local models, materials, idle, faces = {}, {}, {}, {}
	local ok, used, players = pcall(ZCG.FaceSlotsInUse)
	if not ok then used, players = nil, nil end

	ZCG.ContentWalk(function(kind, path, who, _, slot, model)
		path = clean(path)
		if kind == "model" then
			if models[path] == nil then models[path] = who end
		else
			path = string.gsub(path, "^materials/", "")
			path = string.gsub(path, "%.vmt$", "")
			local nobody = false
			if model ~= nil then
				nobody = players ~= nil and not players[clean(tostring(model))]
			elseif slot ~= nil then
				nobody = used ~= nil and not used[clean(tostring(slot))]
			end
			if nobody then
				if idle[path] == nil then idle[path] = who end
			else
				if materials[path] == nil then materials[path] = who end
				if slot ~= nil then faces[path] = true end
			end
		end
	end)
	for path in pairs(materials) do idle[path] = nil end

	return models, materials, idle, faces
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
-- request and only on a client). Also returns how many models and materials the tables name,
-- how many materials the installed models are made of, - apart, not in the list - the missing
-- files that only faces nobody can wear ask for, and how many of the list are faces.
function ZCG.ContentMissing(askMaterials)
	local models, materials, idle, faces = ZCG.ContentNeeds()
	local missing, modelCount, materialCount, faceCount = {}, 0, 0, 0

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
		if not known(name) then
			missing[#missing + 1] = "materials/" .. name .. ".vmt  <-  " .. who
			if faces[name] then faceCount = faceCount + 1 end
		end
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

	local apart = {}
	for name, who in pairs(idle or {}) do
		if not known(name) then apart[#apart + 1] = "materials/" .. name .. ".vmt  <-  " .. who end
	end

	table.sort(missing)
	table.sort(apart)
	return missing, modelCount, materialCount, ownCount, apart, faceCount
end

-- ---------------------------------------------------------------------------------------------
-- whose folder the files lie in
-- ---------------------------------------------------------------------------------------------
-- The game looks for a file the appearance tables name in everything it has mounted: the folder of
-- this addon, the other addons in garrysmod/addons, the copies from the Workshop, the gamemode and
-- the files of the game itself. A file that only ANOTHER addon has works as long as that addon is
-- on the server - and is gone the moment it is taken off, switched off, or not downloaded by a
-- player (a server has no Workshop copy of anything to give out but the one it mounts itself).
-- An addon that carries its own content is one folder that can be copied, uploaded and counted on.
--
-- zcg_content says how many of the files the tables name lie in the folder of this addon and how
-- many the game finds somewhere else, and zcg_outside names every one of the latter. They are the
-- files to put into the addon: sort_content.bat copies what the clothes need out of the archives
-- of the game and of the Workshop on the computer of the owner (and takes content from any folder
-- or archive dropped onto it), and it never writes anywhere but into the folder of the addon.
--
-- Where the game mounted this addon as an archive - a copy from the Workshop - its files cannot be
-- told from the files of another addon: nothing is counted then, and the report says why.

-- (the convar zcg_own_content is made in sh_core.lua, with the other settings of the server:
-- this file is run on its own by tools/lua_names.py, in a room that has no numbers of the game)
ZCG.Outside = ZCG.Outside or nil       -- the list of the last look, false where there is no folder
ZCG.OutsideOurs = ZCG.OutsideOurs or 0 -- how many of the files are in the folder of this addon
ZCG.OutsideCut = ZCG.OutsideCut or false
ZCG.OwnCount = ZCG.OwnCount or nil     -- { files below its materials/, below its models/, cut }
local MAX_OWN_FILES, MAX_OWN_SECONDS = 4000, 3

--- the files the tables name that the game has, but not in the folder of this addon:
--- { "materials/x.vmt  <-  who", ... }; false where the addon is mounted as an archive, nil where
--- the check is switched off. Second: how many of them lie in the folder of the addon.
--- (A file that is nowhere at all is not listed here: ZCG.ContentMissing names those.)
function ZCG.OutsideContent(force)
	if not (ZCG.cvOwnContent and ZCG.cvOwnContent:GetBool()) then return nil end
	if ZCG.Outside ~= nil and not force then return ZCG.Outside, ZCG.OutsideOurs end
	local ok, folder = pcall(ZCG.FindAddonFolder)
	if not ok or not isstring(folder) or folder == "" then
		ZCG.Outside, ZCG.OutsideOurs, ZCG.OutsideCut = false, 0, false
		return false, 0
	end
	local okNeeds, models, materials = pcall(ZCG.ContentNeeds)
	if not okNeeds or not istable(models) then
		ZCG.Outside, ZCG.OutsideOurs, ZCG.OutsideCut = false, 0, false
		return false, 0
	end
	materials = istable(materials) and materials or {}
	local list, ours, checks, cut = {}, 0, 0, false
	local stop = SysTime() + MAX_OWN_SECONDS
	local function look(path, who)
		if cut then return end
		if checks >= MAX_OWN_FILES or SysTime() > stop then
			cut = true
			return
		end
		checks = checks + 1
		if not has(path) then return end
		if has(folder .. "/" .. path) then
			ours = ours + 1
			return
		end
		list[#list + 1] = path .. "  <-  " .. who
	end
	for path, who in pairs(models) do look(path, who) end
	for name, who in pairs(materials) do look("materials/" .. name .. ".vmt", who) end
	table.sort(list)
	ZCG.Outside, ZCG.OutsideOurs, ZCG.OutsideCut = list, ours, cut
	return list, ours
end

--- how many files this addon carries in the two folders the game reads content from - its own
--- materials/ and models/. The game looks for a material or a model in the materials/ and models/
--- of every addon it has mounted and nowhere else, so those two are where everything this addon
--- needs has to lie: sort_content.bat puts it there (out of the folders and archives of the addon,
--- of what was dropped onto it, and, when it was asked, of the archives of the game), and the Lua
--- of this addon looks for its files there. Returns the two counts and whether the count had to
--- stop; false where the addon is mounted as an archive and the game does not list its folders.
function ZCG.OwnFiles(force)
	if istable(ZCG.OwnCount) and not force then return ZCG.OwnCount[1], ZCG.OwnCount[2], ZCG.OwnCount[3] end
	if ZCG.OwnCount == false and not force then return false end
	local ok, folder = pcall(ZCG.FindAddonFolder)
	if not ok or not isstring(folder) or folder == "" then
		ZCG.OwnCount = false
		return false
	end
	local stop = SysTime() + MAX_OWN_SECONDS
	local folders, cut, counts = 0, false, {}
	for _, root in ipairs({ "materials", "models" }) do
		local total, stack = 0, { folder .. "/" .. root }
		while #stack > 0 do
			local dir = table.remove(stack)
			folders = folders + 1
			-- (the budget of the ownership check: it is folders here and files there, and both are
			-- counts of what is walked, so one number serves for the two)
			if folders > MAX_OWN_FILES or SysTime() > stop then
				cut = true
				break
			end
			local okFind, files, dirs = pcall(file.Find, dir .. "/*", "GAME")
			if okFind then
				total = total + #(files or {})
				for _, name in ipairs(dirs or {}) do stack[#stack + 1] = dir .. "/" .. name end
			end
		end
		counts[root] = total
	end
	ZCG.OwnCount = { counts.materials or 0, counts.models or 0, cut }
	return ZCG.OwnCount[1], ZCG.OwnCount[2], cut
end

--- the lines for zcg_content
function ZCG.OutsideReport(out)
	local outside, ours = ZCG.OutsideContent()
	if outside == nil then return end
	if outside == false then
		out("  whose folder the content lies in is not told here: the game mounted this addon as an archive (a copy"
			.. " from the Workshop), where its files cannot be told from the files of another addon. An unpacked"
			.. " folder in garrysmod/addons is checked (zcg_own_content 0 switches the check off)")
		return
	end
	local mine, his, cutOwn = ZCG.OwnFiles()
	if mine then
		out("  what this addon carries in the two folders the game reads content from: " .. mine .. " files below its"
			.. " own materials/, " .. his .. " below its own models/"
			.. (cutOwn and " (not every folder was gone through: the count has the budget of the check)" or ""))
	end
	if #outside == 0 then
		out("  the content of the menu lies in the folder of this addon: " .. ours .. " files the tables name and the"
			.. " game has are its own - nothing here depends on another addon being on the server")
	else
		out("  " .. #outside .. " files the tables name are NOT in the folder of this addon (" .. ours
			.. " are): the game finds them in another addon, in a copy from the Workshop it has mounted, or among its"
			.. " own files - and they are gone when that addon is taken off the server or a player has not got it")
		out("  sort_content.bat in the folder of this addon puts them into those two folders: what the clothes need it"
			.. " copies out of the archives of the game and of the Workshop and takes out of any folder or archive"
			.. " dropped onto it - and out of a folder of the addon that lies beside materials/ and models/, which the"
			.. " game does not read, by itself. zcg_outside names every file")
		for i = 1, math.min(#outside, 6) do out("    " .. outside[i]) end
		if #outside > 6 then out("    ... and " .. (#outside - 6) .. " more") end
	end
	if ZCG.OutsideCut then
		out("  (not every file was looked at: the check has a budget of " .. MAX_OWN_FILES .. " files and "
			.. MAX_OWN_SECONDS .. " seconds)")
	end
end

concommand.Add("zcg_outside" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	local outside, ours = ZCG.OutsideContent(true)
	if outside == nil then
		print("[CS:GO Gloves] zcg_own_content is 0: whose folder the files lie in is not looked at")
		return
	end
	if outside == false then
		print("[CS:GO Gloves] the folder of this addon is not there to look into: the game mounted it as an archive"
			.. " (a copy from the Workshop). Unpacked into garrysmod/addons, it is checked")
		return
	end
	print("[CS:GO Gloves] files of the appearance menu: " .. ours .. " in the folder of this addon, " .. #outside
		.. " the game has somewhere else")
	local mine, his = ZCG.OwnFiles(true)
	if mine then
		print("[CS:GO Gloves] what this addon carries in the two folders the game reads content from: " .. mine
			.. " files below its own materials/, " .. his .. " below its own models/")
	end
	for i = 1, math.min(#outside, 400) do print("  " .. outside[i]) end
	if #outside > 400 then print("  ... and " .. (#outside - 400) .. " more (the whole list is in data/zcg_content.txt)") end
end, nil, "Name the files of the appearance menu that are not in the folder of this addon")

-- ---------------------------------------------------------------------------------------------
-- a face without its file
-- ---------------------------------------------------------------------------------------------
-- A face is a material Z-City puts over the face of a player model. One whose file is not
-- installed cannot show the picture its name promises: the head keeps the material of the model,
-- or draws purple and black squares - on whoever picks it, and on everybody Z-City gives it to:
-- a random appearance takes any face of the list. Clothing packs name such faces: their textures
-- come with yet another addon that is not installed here (2.24.3: on a server with Z-City and
-- this addon alone, of 243 face textures the tables name there was not one file - every face of
-- the menu was a promise of a picture nobody had).
--
-- A face whose texture is a face texture and is nowhere on this computer is therefore out of the
-- menu on every computer, whatever zcg_fix_faces says: it is given the empty material Z-City
-- itself uses for "Default", so the model keeps its own face instead of a wrong one. The name
-- stays in the list; ZCG.Faceless remembers what stood there, so zcg_content goes on naming the
-- file, and with the file the face is back. ZCG.FaceDropped holds the faces taken out this way.
-- Only a texture that is a face is taken out - the build knows which lines of the clothing Lua
-- are faces and which are clothes (sh_bound.lua), and where it does not, the name of the file
-- tells (a face texture of Z-City is a "facemap" or a "cylmap"). A material that is clothes as
-- well is never touched: taking it out would undress somebody.
--
-- zcg_fix_faces 1: the same for every face without its file, clothes among them. Z-City dresses
-- a player on the server, with the table of the server: there the files of the server decide for
-- everybody. That is right where the players get their content from the very folder the server
-- has, and wrong where they have files the server lacks - the addon cannot know which, so this
-- wider rule is off until the owner of the server switches it on. A computer that has little of
-- the content is left alone even then: a dedicated server needs no materials at all.
-- (2 = on any computer; 0 = only the faces above, and whatever else was changed is put back.)
ZCG.Faceless = ZCG.Faceless or {} -- entry of the tables (as ZCG.ContentWalk names it) -> the material
ZCG.FaceDropped = ZCG.FaceDropped or nil -- the same, of the faces that are out of the menu
local MIN_SHARE = 0.9
local there = {} -- material -> its file is there; asked once, zcg_content asks anew

local function materialName(path)
	path = clean(path)
	path = string.gsub(path, "^materials/", "")
	path = string.gsub(path, "%.vmt$", "")
	return path
end

local function materialThere(name)
	local known = there[name]
	if known == nil then
		known = has("materials/" .. name .. ".vmt")
		there[name] = known
	end
	return known
end

-- Which materials are faces and which are clothes, as the build wrote it down: sh_bound.lua keeps
-- every line the clothing Lua puts into the tables with the entry it goes into, and a line of
-- FacemapsSlots or MultiFacemaps is a face while a line of Clothes is not. Without that list (an
-- addon built without the Lua of the packs) the name of the file tells: a face texture of Z-City
-- is a "facemap", and a "cylmap" in the packs that mirror the citizens of Half-Life 2.
-- (a path is compared the way the build wrote it down: in lower case, with "/", and without the
-- "materials/" in front and the ".vmt" behind that one list has and the other does not)
local function faceKey(path) return materialName(clean(path)) end

local boundWas, facePaths, clothesPaths
local function facePathLists()
	local bound = ZCG.Bound
	if facePaths ~= nil and bound == boundWas then return end
	boundWas, facePaths, clothesPaths = bound, {}, {}
	if not istable(bound) then return end
	for _, list in pairs(bound) do
		for _, item in ipairs(istable(list) and list or {}) do
			if istable(item) and isstring(item[1]) and isstring(item[2]) then
				local where = string.match(item[1], "^([^/]+)/")
				local name = faceKey(item[2])
				if where == "FacemapsSlots" or where == "MultiFacemaps" then
					facePaths[name] = true
				elseif where == "Clothes" then
					clothesPaths[name] = true
				end
			end
		end
	end
end

--- is this material a face texture, and not a piece of clothing that a face list names as well?
function ZCG.IsFaceMaterial(path)
	if not isstring(path) or path == "" then return false end
	facePathLists()
	local name = faceKey(path)
	if clothesPaths[name] then return false end
	if facePaths[name] then return true end
	return string.find(name, "facemap", 1, true) ~= nil or string.find(name, "cylmap", 1, true) ~= nil
end

--- forgets the files that were asked for and not found: content gets mounted while a game runs,
--- and a click on a button of the menu is a good moment to ask the disk again
function ZCG.MaterialAnew()
	for name, found in pairs(there) do
		if not found then there[name] = nil end
	end
end

--- may this material be put on a player? A face whose file is not on this computer can only show
--- a picture that is not the one its name promises, and the model is better left with its own face
--- (2.24.3). The empty material - the one Z-City itself uses for "Default" - is always all right.
function ZCG.MaterialUsable(path)
	if not isstring(path) then return false end
	if path == "" then return true end
	return ZCG.MaterialThere(path)
end

--- is the file of this material on this computer? A material that needs no file ("null", the name
--- GMod gives a material that draws nothing, and "!name", one Lua made) counts as there.
function ZCG.MaterialThere(path)
	if not isstring(path) or path == "" then return false end
	if string.lower(path) == "null" or string.sub(path, 1, 1) == "!" then return true end
	return materialThere(materialName(path))
end

-- fn(table, key, value, entry) for every face
local function eachFace(fn)
	local AP = istable(hg) and hg.Appearance
	if not istable(AP) then return end
	if istable(AP.FacemapsSlots) then
		for slot, faces in pairs(AP.FacemapsSlots) do
			if istable(faces) then
				for name, path in pairs(faces) do
					fn(faces, name, path, "FacemapsSlots/" .. tostring(slot) .. "/" .. tostring(name))
				end
			end
		end
	end
	if istable(AP.MultiFacemaps) then
		for model, faces in pairs(AP.MultiFacemaps) do
			if istable(faces) then
				for name, slots in pairs(faces) do
					if istable(slots) then
						for slot, path in pairs(slots) do
							fn(slots, slot, path,
								"MultiFacemaps/" .. tostring(model) .. "/" .. tostring(name) .. "/" .. tostring(slot))
						end
					end
				end
			end
		end
	end
end

-- how many of the materials the menu names (for something that can be worn) are on this
-- computer, and how many there are
function ZCG.ContentShare()
	local _, materials = ZCG.ContentNeeds()
	local found, all = 0, 0
	for name in pairs(materials) do
		all = all + 1
		if materialThere(name) then found = found + 1 end
	end
	return found, all
end

-- Returns how many face materials have no file and show the own face of their model now (one
-- material may stand in several lists); nil and "off" / "share" when the tables are left as the
-- clothing Lua made them. ZCG.FacesLeft then holds { faces = how many have no file, why = "off" /
-- "share", there = , all = the materials of the menu on this computer and all of them }.
function ZCG.FixFaces()
	local lost = ZCG.Faceless
	local mode = ZCG.cvFixFaces and ZCG.cvFixFaces:GetInt() or 0

	-- the faces, each with the material the clothing Lua gave it
	-- (what stood there is remembered by the name of the entry: two entries that come out under
	-- one name - a "/" in the name of a face - are left alone)
	local faces, times = {}, {}
	eachFace(function(tbl, key, path, entry)
		times[entry] = (times[entry] or 0) + 1
		if not isstring(path) then return end
		if path == "" then path = lost[entry] end -- (nil: a "Default")
		if path then faces[#faces + 1] = { tbl = tbl, key = key, entry = entry, path = path } end
	end)
	for i = #faces, 1, -1 do
		if times[faces[i].entry] > 1 then table.remove(faces, i) end
	end

	local dropped = {} -- faces that are out of the menu whatever the switch says: entry -> material

	local function putBack()
		for _, face in ipairs(faces) do
			if face.tbl[face.key] == "" and not dropped[face.entry] then face.tbl[face.key] = face.path end
		end
		for entry in pairs(lost) do lost[entry] = nil end
		for entry, path in pairs(dropped) do lost[entry] = path end
	end

	local without, files, count = {}, {}, 0
	for _, face in ipairs(faces) do
		local name = materialName(face.path)
		if string.lower(face.path) ~= "null" and string.sub(face.path, 1, 1) ~= "!" and not materialThere(name) then
			without[#without + 1] = face
			if not files[name] then
				files[name] = true
				count = count + 1
			end
		end
	end

	-- out of the menu on every computer: a face whose texture is a face texture and is nowhere here
	-- can only show a face that is not the one its name promises (2.24.3)
	local droppedFiles, droppedCount, keptFiles = {}, 0, {}
	for _, face in ipairs(without) do
		if ZCG.IsFaceMaterial(face.path) then
			dropped[face.entry] = face.path
			face.tbl[face.key] = ""
			droppedCount = droppedCount + 1
			droppedFiles[materialName(face.path)] = true
		else
			keptFiles[materialName(face.path)] = true -- (a face list may name a piece of clothes)
		end
	end
	ZCG.FaceDropped = next(dropped) ~= nil and dropped or nil
	local function countKeys(list)
		local got = 0
		for _ in pairs(list) do got = got + 1 end
		return got
	end
	local droppedMats, keptMats = countKeys(droppedFiles), countKeys(keptFiles)

	ZCG.FacesLeft = nil
	if mode <= 0 then
		putBack()
		ZCG.FacesLeft = { faces = droppedMats, why = "off", dropped = droppedCount, kept = keptMats }
		if droppedMats == 0 then return nil, "off" end
		return droppedMats, "off"
	end
	if mode == 1 then
		local found, all = ZCG.ContentShare()
		if all == 0 or found < MIN_SHARE * all then
			putBack()
			ZCG.FacesLeft = { faces = droppedMats, why = "share", there = found, all = all, dropped = droppedCount,
				kept = keptMats }
			if droppedMats == 0 then return nil, "share" end
			return droppedMats, "share"
		end
	end

	local now = {}
	for _, face in ipairs(without) do
		now[face.entry] = face.path
		face.tbl[face.key] = ""
	end
	-- (a face whose file is there by now gets its material back)
	for _, face in ipairs(faces) do
		if not now[face.entry] and face.tbl[face.key] == "" then face.tbl[face.key] = face.path end
	end
	for entry in pairs(lost) do lost[entry] = nil end
	for entry, path in pairs(now) do lost[entry] = path end
	ZCG.FacesLeft = { faces = count, dropped = droppedCount, kept = 0 }
	return count
end

-- The clothing Lua fills the tables while the game starts, some of it on timers, and a Lua file
-- that is loaded again fills them again: looked at a few times at the start, every two minutes
-- after that, and when the switch is turned. One line in the console when the number changes.
-- Switched off it still takes the faces out of the menu whose texture is a face texture and is
-- nowhere on this computer (2.24.3), so it always has something to look at.
local toldFaces = 0
local function facesPass()
	-- (a file that was not there is asked for again: content gets mounted while a game runs)
	ZCG.MaterialAnew()
	local ok, count = pcall(ZCG.FixFaces)
	if not ok then
		if toldFaces ~= -1 then
			toldFaces = -1
			ErrorNoHalt("[CS:GO Gloves] faces without files: " .. tostring(count) .. "\n")
		end
		return
	end
	count = count or 0
	if count ~= toldFaces then
		if count > 0 then
			-- (the wider rule of the switch is what is offered where the narrow one is all that runs)
			local wider = istable(ZCG.FacesLeft) and ZCG.FacesLeft.why == nil
			ZCG.Print(count .. " face textures of the appearance menu have no file on the " .. (SERVER and "server" or "client")
				.. ": the faces that name them are out of the menu and their models show their own face"
				.. (wider and "" or " - zcg_fix_faces 2 takes every other face without its file out as well")
				.. " (zcg_content names the files and the Lua that names them).")
		elseif toldFaces > 0 then
			ZCG.Print("the faces of the appearance menu are as the clothing Lua made them again.")
		end
		toldFaces = count
	end
end

hook.Add("InitPostEntity", "zcg_faces", function()
	for _, delay in ipairs({ 1, 5, 15, 70 }) do timer.Simple(delay, facesPass) end
	timer.Create("zcg_faces", 120, 0, facesPass)
end)
-- (on the server the switch works at once; a client hears of it with the next look)
if cvars and cvars.AddChangeCallback then
	cvars.AddChangeCallback("zcg_fix_faces", function() timer.Simple(0, facesPass) end, "zcg_faces")
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

-- Packs whose Lua is not in this addon because another version of them is: two versions of one
-- addon bring the same Lua files, and the game can only have one (the build takes one of them,
-- whole). ZCG.BoundLeftOut: title of such a pack -> the title of the version that is here;
-- ZCG.BoundOther: file -> the title of the pack that alone names it; ZCG.BoundOnly: a file this
-- addon names and such a pack does not -> the title of that pack. Returns
-- { { title = , instead = , files = how many files only it names, there = ... are installed,
--     own = how many files only the version in the addon names, ownThere = ... are installed,
--     other = true when the content here is that of the pack that is not in the addon: files of
--             it are here and none of the other kind - or few of them (one or two, or not more
--             than one in four) while most of its own are here: the content of one version
--             carries some files of the other, and that does not make it the other one's }, ... }
-- sorted by title; empty without such packs.
function ZCG.OtherVersions()
	local found = {}
	local left = ZCG.BoundLeftOut
	if not istable(left) then return found end
	local function count(list, title)
		local all, there = 0, 0
		for path, pack in pairs(istable(list) and list or {}) do
			if pack == title and isstring(path) then
				all = all + 1
				if has(path) then there = there + 1 end
			end
		end
		return all, there
	end
	for title, instead in pairs(left) do
		local item = { title = tostring(title), instead = tostring(instead) }
		item.files, item.there = count(ZCG.BoundOther, title)
		item.own, item.ownThere = count(ZCG.BoundOnly, title)
		item.other = item.there > 0 and item.own > 0
			and (item.ownThere == 0
				or ((item.ownThere <= 2 or item.ownThere * 4 <= item.own) and item.there * 2 > item.files))
		found[#found + 1] = item
	end
	table.sort(found, function(a, b) return a.title < b.title end)
	return found
end

-- trouble: entries of this addon are not in the tables - the other version, installed as an addon
-- of its own, is one way to get there
local function tellVersions(out, trouble)
	for _, item in ipairs(ZCG.OtherVersions()) do
		out("[CS:GO Gloves] this addon is built with \"" .. item.instead .. "\". \"" .. item.title
			.. "\" is another version of the same addon and is not in it: the game can only have one of the two")
		if item.files > 0 then
			out("  " .. item.there .. " of the " .. item.files .. " files that only \"" .. item.title .. "\" names are here"
				.. (item.there > 0 and ": the game does not use them with this addon" or ""))
		end
		if item.own > 0 then
			out("  " .. item.ownThere .. " of the " .. item.own .. " files that only \"" .. item.instead .. "\" names are here")
			if item.other then
				out("  IT LOOKS LIKE THE CONTENT HERE IS THAT OF \"" .. item.title .. "\": this addon looks for the files of \""
					.. item.instead .. "\" and finds "
					.. (item.ownThere == 0 and "none" or item.ownThere <= 2 and "next to none" or ("only " .. item.ownThere))
					.. " of them. Close the game and run sort_content.bat in the folder of this addon: it puts the Lua of \""
					.. item.title .. "\" in place by itself (it lies in sort_content/versions)")
			end
		end
		if trouble then
			out("  if \"" .. item.title .. "\" is installed as an addon of its own as well, its Lua files have the same names as"
				.. " the ones in this addon and take their place - that makes a list like the one above. Keep one of the two")
		end
	end
end

-- the lines of zcg_content about that, through out(text); returns how many entries are not there
function ZCG.BoundReport(out)
	local count, missing = ZCG.BoundMissing()
	if not count then return 0 end
	if #missing == 0 then
		out("[CS:GO Gloves] the clothing Lua of this addon: all " .. count
			.. " clothes, faces, models and accessories it adds are in the appearance tables")
		tellVersions(out, false)
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
	tellVersions(out, true)
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

-- The folder of this addon when it lies in garrysmod/addons ("addons/zcity_csgo_gloves"), else
-- false. The game reads its lua, materials, models ... folders and nothing else in it - not
-- _not_used, where sort_content.bat puts what it found no place for, and not a folder that was
-- meant for materials/ and was put beside it.
-- (Looked for when the report is asked for: this file says where it was read from; a player
-- whose Lua came from the server may have the folder all the same.)
local AUTORUN = "/lua/autorun/zcity_csgo_gloves.lua"
function ZCG.FindAddonFolder()
	if ZCG.AddonFolder ~= nil then return ZCG.AddonFolder end
	local info = debug and debug.getinfo and debug.getinfo(1, "S")
	local source = info and isstring(info.source) and string.gsub(info.source, "\\", "/") or ""
	local folder = string.match(source, "^@?(addons/[^/]+)/lua/") or false
	if folder and not file.Exists(folder .. AUTORUN, "GAME") then folder = false end
	if not folder then
		local _, dirs = file.Find("addons/*", "GAME")
		for _, name in ipairs(dirs or {}) do
			if file.Exists("addons/" .. name .. AUTORUN, "GAME") then
				folder = "addons/" .. name
				break
			end
		end
	end
	ZCG.AddonFolder = folder
	return folder
end
-- (the folders of an addon the game does read, and the tool of this one)
local READ = { lua = true, materials = true, models = true, sound = true, resource = true, particles = true,
	scripts = true, maps = true, gamemodes = true, data = true, data_static = true, sort_content = true }

-- names: { ["epl.vmt"] = true, ... } (lower case). Returns file name -> { paths, at most three }
-- for the names that exist somewhere below materials/ or models/; true when the search had to
-- stop before it was through; and the same kind of list for the files that lie in the folder of
-- this addon where the game does not look.
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

	local aside = {}
	local ok, folder = pcall(ZCG.FindAddonFolder)
	if not ok then folder = false end
	if isstring(folder) and folder ~= "" then
		local _, dirs = file.Find(folder .. "/*", "GAME")
		for _, name in ipairs(dirs or {}) do
			if not READ[string.lower(name)] then walk(folder .. "/" .. name, "GAME", names, aside, seen, budget) end
		end
	end
	return found, budget.cut, aside
end

local function fileName(line)
	local path = string.match(line, "^(.-)  <%-  ") or line
	return string.lower(string.match(path, "([^/]+)$") or path)
end

-- ---------------------------------------------------------------------------------------------
-- the report
-- ---------------------------------------------------------------------------------------------
-- Who names a file: for the value of every entry the clothing Lua of this addon puts into the
-- tables (ZCG.Bound) the Lua files that put it there - "models/x.mdl" or the name of a material
-- -> { [Lua file] = true }. nil without the list.
local function namers()
	local bound = ZCG.Bound
	if not istable(bound) then return nil end
	local side = SERVER and 1 or 2
	local by = {}
	for script, entries in pairs(bound) do
		for _, item in ipairs(istable(entries) and entries or {}) do
			if istable(item) and isstring(item[1]) and isstring(item[2]) and (item[3] == nil or item[3] == side) then
				local value = clean(item[2])
				if string.sub(value, -4) ~= ".mdl" then value = materialName(value) end
				by[value] = by[value] or {}
				by[value][tostring(script)] = true
			end
		end
	end
	return by
end

-- the lines of the report that tell which pack the missing files belong to
local function tellNamers(out, missing)
	local by = namers()
	if not by then return end
	local counts, order, others, ofModels = {}, {}, 0, 0
	for _, line in ipairs(missing) do
		local path = string.match(line, "^(.-)  <%-  ") or line
		if string.find(line, "  <-  material of ", 1, true) then
			ofModels = ofModels + 1
		else
			local key = string.sub(path, -4) == ".mdl" and path or materialName(path)
			local scripts = by[key]
			if scripts then
				for script in pairs(scripts) do
					if not counts[script] then
						counts[script] = 0
						order[#order + 1] = script
					end
					counts[script] = counts[script] + 1
				end
			else
				others = others + 1
			end
		end
	end
	table.sort(order, function(a, b)
		if counts[a] ~= counts[b] then return counts[a] > counts[b] end
		return a < b
	end)
	local packs = istable(ZCG.BoundPacks) and ZCG.BoundPacks or {}
	out("  the Lua that names them:")
	for _, script in ipairs(order) do
		local title = packs[script]
		out("    " .. counts[script] .. " - " .. (isstring(title) and (title .. " (lua/" .. script .. ")") or ("lua/" .. script)))
	end
	if others > 0 then out("    " .. others .. " - Z-City itself or another addon (not the clothing Lua of this addon)") end
	if ofModels > 0 then
		out("    " .. ofModels .. " - no Lua: materials that models of the menu are made of (hats and the like)")
	end
end

-- prints the report line by line through out(text), returns the number of missing files
function ZCG.ContentReport(out)
	there = {} -- (the files are asked for anew)
	local fixed, fixedCount = pcall(ZCG.FixFaces)
	local missing, models, materials, own, apart, faceCount = ZCG.ContentMissing(true)
	apart, faceCount = apart or {}, faceCount or 0
	out("[CS:GO Gloves] content check on the " .. (SERVER and "server" or "client") .. ": the appearance tables name "
		.. models .. " models and " .. materials .. " materials, the installed models are made of " .. own
		.. " materials; " .. #missing .. " files are missing")

	-- what goes for the faces
	local function faces()
		local left = ZCG.FacesLeft
		local droppedNow = 0
		for _ in pairs(ZCG.FaceDropped or {}) do droppedNow = droppedNow + 1 end
		if fixed and fixedCount and fixedCount > 0 then
			out("  " .. fixedCount .. " face textures have no file here: the " .. droppedNow .. " faces that name them are out of"
				.. " the menu and their models show their own face, until the file is there (the textures come with the"
				.. " clothing pack that names them - zcg_content names the Lua file)")
			if istable(left) and (left.kept or 0) > 0 then
				out("  " .. left.kept .. " more face textures are not here and are not known to be"
					.. " face textures (a face list may name a piece of clothes): those faces stay in the menu, and whoever"
					.. " gets one of them has purple and black squares for a face (zcg_fix_faces 2 gives them the own face"
					.. " of the model)")
			end
		elseif faceCount > 0 and istable(left) and left.why == "share" then
			out("  " .. faceCount .. " of them are faces, and they stay purple and"
				.. " black squares: only " .. left.there .. " of the " .. left.all .. " materials the menu names are on this"
				.. " computer, which is taken for one without the content (a server needs none) - zcg_fix_faces 2 gives them"
				.. " the own face of the model all the same")
		elseif faceCount > 0 then
			out("  " .. faceCount .. " of them are faces: whoever gets one of them"
				.. " has purple and black squares for a face - and Z-City hands faces out by chance")
			out("  zcg_fix_faces 1 (console of the server, or server.cfg) gives such a face the own face of the model until"
				.. " its file is there - right where the players get their content from the folder the server has")
		elseif droppedNow > 0 then
			out("  no face of the menu is left without its texture: " .. droppedNow .. " faces that had none are out of the"
				.. " menu until the file is there")
		end
		if #apart > 0 then
			out("  " .. #apart .. " more files are named only for faces that no player model of the menu can wear"
				.. " (the list is for a material none of these models has) - they are not counted:")
			for i = 1, math.min(#apart, 4) do out("    " .. apart[i]) end
			if #apart > 4 then out("    ... and " .. (#apart - 4) .. " more") end
		end
	end

	if #missing == 0 then
		-- Nothing is missing: what the addon did about the tables is told all the same - the lines
		-- of the packs, the merged versions, the content without Lua, the accessories, the faces
		-- and whose folder the files lie in are what zcg_content is for, not only what is gone.
		faces()
		ZCG.BoundReport(out)
		if ZCG.FaceReport then ZCG.FaceReport(out) end
		if ZCG.MergeReport then ZCG.MergeReport(out) end
		if ZCG.RegisterReport then ZCG.RegisterReport(out) end
		if ZCG.FoundReport then ZCG.FoundReport(out) end
		if ZCG.AccessoryReport then ZCG.AccessoryReport(out) end
		ZCG.OutsideReport(out)
		return 0
	end

	-- are they there, in another folder?
	local names = {}
	for _, line in ipairs(missing) do names[fileName(line)] = true end
	local ok, found, cut, aside = pcall(ZCG.FindByName, names)
	if not ok then found, cut, aside = {}, true, {} end
	aside = aside or {}

	-- (a namesake that the tables name at the very place where it lies is another file, at home)
	local namedModels, namedMaterials, namedIdle = ZCG.ContentNeeds()
	local function atHome(path)
		path = clean(path)
		if string.sub(path, -4) == ".mdl" then return namedModels[path] ~= nil end
		local name = materialName(path)
		return namedMaterials[name] ~= nil or (namedIdle and namedIdle[name] ~= nil)
	end

	local lines, elsewhere, example, unseen, hidden, nowhere = {}, 0, nil, 0, nil, 0
	for i, line in ipairs(missing) do
		local name = fileName(line)
		local paths, beside = found[name], aside[name]
		if paths then
			local stray, others = {}, {}
			for _, path in ipairs(paths) do
				if atHome(path) then others[#others + 1] = path else stray[#stray + 1] = path end
			end
			if #stray > 0 then
				elsewhere = elsewhere + 1
				example = example or stray[1]
				line = line .. "   [a file of that name: " .. table.concat(stray, ", ") .. "]"
				paths = stray
			else
				line = line .. "   [" .. table.concat(others, ", ") .. " has that name, but is another file: the tables name it there]"
				paths = nil
			end
		end
		if beside then
			unseen = unseen + 1
			hidden = hidden or beside[1]
			line = line .. "   [in the folder of this addon, where the game does not look: " .. table.concat(beside, ", ") .. "]"
		end
		if not paths and not beside then nowhere = nowhere + 1 end
		lines[i] = line
	end

	local shown = math.min(#lines, 200)
	for i = 1, shown do out("  " .. lines[i]) end
	if #lines > shown then out("  ... and " .. (#lines - shown) .. " more") end

	local all = lines
	if #apart > 0 then
		all = {}
		for i, line in ipairs(lines) do all[i] = line end
		all[#all + 1] = ""
		all[#all + 1] = "only for faces that no player model of the menu can wear - not counted:"
		for _, line in ipairs(apart) do all[#all + 1] = line end
	end
	local written = pcall(file.Write, "zcg_content.txt", table.concat(all, "\n") .. "\n")
	if written then out("  the whole list is in garrysmod/data/zcg_content.txt") end

	-- whose they are
	pcall(tellNamers, out, missing)

	-- where they are
	local folder = isstring(ZCG.AddonFolder) and ZCG.AddonFolder ~= "" and ZCG.AddonFolder or nil
	if unseen > 0 then
		out("  " .. unseen .. " of them lie in the folder of this addon outside of materials/ and models/ (" .. tostring(hidden)
			.. " ...): the game does not look there")
		out("  _not_used is where sort_content.bat puts a file it found no place for - its report, sort_content_report.txt,"
			.. " says why; any other folder of the addon - one called materials1, models 2 ..., or a pack put beside"
			.. " materials/ - sort_content.bat goes through itself: the game reads content from materials/ and models/ of"
			.. " the addon alone, so what is in such a folder goes there")
	end
	if elsewhere > 0 then
		out("  " .. elsewhere .. " of them have a file of the same name in another folder (" .. tostring(example) .. " ...):"
			.. " the game only finds a file at its exact path")
		out("  close the game and start sort_content.bat in the folder of this addon (addons/zcity_csgo_gloves):"
			.. " it moves every file to its place")
		out("  (a file it cannot tell from a namesake of another pack stays where it is: its report,"
			.. " sort_content_report.txt, names such files - move those by hand)")
	end
	if nowhere > 0 and not cut then
		if folder then
			out("  " .. nowhere .. " of them are nowhere: in no folder the game reads and nowhere in the folder of this addon"
				.. " (_not_used included), under no path. sort_content.bat deletes nothing: either these files were never"
				.. " brought here, or it left them in a folder that was dropped onto it - sort_content_report.txt names what it"
				.. " did not take and why")
		else
			out("  " .. nowhere .. " of them are in no folder the game reads, under no path: they have to be brought first")
		end
	end
	if elsewhere == 0 then
		out("  put the files into the materials and models folders of this addon - in any folders, or the whole"
			.. " materials and models folders of other addons as materials1, models2 ... - and start"
			.. " sort_content.bat there: it moves every file to its place. Then start the game again")
	end
	if cut then out("  (the search for the file names was stopped early: there are too many folders)") end
	if folder and file.IsDir and file.IsDir(folder .. "/_sorting", "GAME") then
		out("  sort_content.bat was cut off while it moved files (the folder _sorting is still there): start it again,"
			.. " it finishes what it began")
	end

	faces()
	if own > 0 then
		out("  a material that a model is made of and that is not installed leaves a purple and black part on that model")
	end
	if SERVER then
		out("  (this is the disk of the server. What a player sees depends on the files on the computer of that player:"
			.. " zcg_content in the console of the game checks those)")
	end
	ZCG.BoundReport(out)
	if ZCG.FaceReport then ZCG.FaceReport(out) end
	if ZCG.MergeReport then ZCG.MergeReport(out) end
	if ZCG.RegisterReport then ZCG.RegisterReport(out) end
	if ZCG.FoundReport then ZCG.FoundReport(out) end
	if ZCG.AccessoryReport then ZCG.AccessoryReport(out) end
	ZCG.OutsideReport(out)
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

-- The content lines a player's game lost on the way: the Lua of a pack did not run in time or
-- fell over before putting them into the tables. ZCG.Bound holds what the packs put there when
-- the addon was built; a line that is not in the tables now gets the Lua of its pack run once
-- more, in whichever realm the tables live. Clothes, faces, accessories, player models - the
-- bodygroups of merged/ have a pass of their own in sh_merge.lua.
function ZCG.BoundWanted()
	local bound = ZCG.Bound
	local AP = istable(hg) and hg.Appearance
	if not istable(bound) or not istable(AP) then return {} end
	local there = {}
	ZCG.ContentWalk(function(kind, path, who, entry) there[entry] = true end)
	local wanted = {}
	for file, entries in pairs(bound) do
		if istable(entries) then
			for _, one in ipairs(entries) do
				if istable(one) and isstring(one[1]) and not there[one[1]] then wanted[file] = true end
			end
		end
	end
	return wanted
end

local healTried = {}

function ZCG.HealBound()
	local wanted = ZCG.BoundWanted()
	local healed = 0
	local now = RealTime and RealTime() or 0
	for file in pairs(wanted) do
		-- a file that falls over is tried once in two minutes, not on every pass of the watch
		if (healTried[file] or -999) <= now - 120 then
			healTried[file] = now
			local ok, err = pcall(include, file)
			if ok then
				healed = healed + 1
			else
				ZCG.Print("could not run " .. file .. " again: " .. tostring(err))
			end
		end
	end
	if healed > 0 then
		ZCG.Print(healed .. " content files run again - lines of the appearance menu were missing")
	end
	return healed, wanted
end

-- The lines sort_content.bat wrote from the list of the build (sh_baked.lua): the game puts them
-- into the tables itself, whatever order the Lua of the packs loads in and whether it runs at
-- all. A face goes into a slot the tables already know; a line whose place cannot be told stays
-- to ZCG.HealBound, which runs the Lua of its pack again.
local function baked_put(entry, value)
	local AP = hg.Appearance
	local head, rest = string.match(entry, "^([^/]+)/(.+)$")
	if not head then return false end
	if head == "Clothes" or head == "PlayerModels" then
		local sex, name = string.match(rest, "^([12])/(.+)$")
		sex = tonumber(sex)
		if not sex then return false end
		local where = head == "Clothes" and (AP.Clothes or {}) or (AP.PlayerModels or {})
		where[sex] = where[sex] or {}
		if head == "Clothes" then
			if where[sex][name] ~= nil then return false end
			where[sex][name] = value
			AP.Clothes = where
			return true
		end
		if where[sex][name] ~= nil then return false end
		where[sex][name] = { mdl = value, sex = sex }
		AP.PlayerModels = where
		return true
	end
	if head == "Accessories" then
		local id, field = string.match(rest, "^(.+)/([^/]+)$")
		if not id or (field ~= "model" and field ~= "femmodel") then return false end
		hg.Accessories = hg.Accessories or {}
		hg.Accessories[id] = hg.Accessories[id] or {}
		if hg.Accessories[id][field] ~= nil then return false end
		hg.Accessories[id][field] = value
		return true
	end
	if head == "FacemapsSlots" then
		for slot, faces in pairs(AP.FacemapsSlots or {}) do
			if isstring(slot) and istable(faces) and string.sub(rest, 1, #slot + 1) == slot .. "/" then
				local name = string.sub(rest, #slot + 2)
				if faces[name] ~= nil then return false end
				faces[name] = value
				return true
			end
		end
	end
	if head == "MultiFacemaps" then
		for model, faces in pairs(AP.MultiFacemaps or {}) do
			if isstring(model) and istable(faces) and string.sub(rest, 1, #model + 1) == model .. "/" then
				local tail = string.sub(rest, #model + 2)
				for slot in pairs(AP.FacemapsSlots or {}) do
					if isstring(slot) and #tail > #slot + 1 and string.sub(tail, -(#slot + 1)) == "/" .. slot then
						local name = string.sub(tail, 1, #tail - #slot - 1)
						faces[name] = faces[name] or {}
						if istable(faces[name]) and faces[name][slot] ~= nil then return false end
						faces[name][slot] = value
						return true
					end
				end
			end
		end
	end
	return false
end

function ZCG.ApplyBaked()
	local baked = ZCG.Baked
	local AP = istable(hg) and hg.Appearance
	if not istable(baked) or not istable(AP) then return 0 end
	local put = 0
	for _, one in ipairs(baked) do
		if istable(one) and isstring(one[1]) and isstring(one[2]) then
			local side = tonumber(one[3])
			if side == nil or (SERVER and side == 1) or (CLIENT and side == 2) then
				if baked_put(one[1], one[2]) then put = put + 1 end
			end
		end
	end
	if put > 0 then
		ZCG.Print(put .. " lines of the appearance menu put in from " .. "sh_baked.lua")
	end
	return put
end

-- The watch that keeps the menu whole for as long as the game runs, on the client and on the
-- server: every ten seconds the lines of sh_baked.lua are put back into the tables, the merged
-- versions of the packs add what only they have (sh_merge.lua), a line that is still missing
-- gets the Lua of its pack run again, and the faces are put into the table the other menu reads
-- as well (sh_faces.lua). Nothing here depends on the order the addons load in, on the Lua of the
-- packs running at all, or on somebody making the tables anew afterwards.
hook.Add("InitPostEntity", "zcg_heal", function()
	timer.Create("zcg_heal", 10, 0, function()
		-- what the Lua of the packs put into the tables by calling this addon (sh_register.lua):
		-- a table made anew since loses it, and the call is remembered well enough to be made again
		if ZCG.ReplayRegistered then pcall(ZCG.ReplayRegistered) end
		ZCG.ApplyBaked()
		if ZCG.MergePass then pcall(ZCG.MergePass) end
		ZCG.HealBound()
		if ZCG.FoundPass then pcall(ZCG.FoundPass) end
		-- the faces into the table the other menu reads as well (sh_faces.lua) - after everything
		-- that adds a face: the lines of the build, the merged versions, the content without Lua
		if ZCG.FacePass then pcall(ZCG.FacePass) end
	end)
end)

-- What every player's client ends up with, into data/zcg_clients.txt of the server: the version
-- of this addon there and the content files whose lines are still missing after the heal. A
-- player with no line in that file has this addon on the client not at all - no Lua can help
-- then, the files have to reach the player (the Workshop copy the server mounts).
if SERVER then
	if util.AddNetworkString then util.AddNetworkString("zcg_client_content") end
	if net and net.Receive then
		net.Receive("zcg_client_content", function(length, ply)
			local line = os.date("%Y-%m-%d %H:%M:%S") .. "  " .. tostring(ply:Nick()) .. "  " .. net.ReadString()
			local lines = string.Explode("\n", file.Read("zcg_clients.txt", "DATA") or "")
			while #lines > 300 do table.remove(lines, 1) end
			file.Write("zcg_clients.txt", table.concat(lines, "\n") .. line .. "\n")
		end)
	end
	concommand.Add("zcg_clients", function()
		print(file.Read("zcg_clients.txt", "DATA") or "no player reports yet")
	end)
else
	hook.Add("InitPostEntity", "zcg_report", function()
		timer.Simple(45, function()
			if not (net and net.Start) then return end
			local wanted = {}
			for file in pairs(ZCG.BoundWanted()) do wanted[#wanted + 1] = file end
			table.sort(wanted)
			net.Start("zcg_client_content")
			local errs = ZCGloves.LoadErrors or {}
			net.WriteString(ZCG.Version
				.. "  missing: " .. (#wanted > 0 and table.concat(wanted, ", ") or "none")
				.. "  load errors: " .. (#errs > 0 and table.concat(errs, " | ") or "none")
				.. "  cs:go gloves: " .. tostring(#(ZCG.Variants or {})))
			net.SendToServer()
		end)
	end)
end
