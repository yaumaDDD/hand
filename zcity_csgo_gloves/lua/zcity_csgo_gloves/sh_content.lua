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
-- a face without its file
-- ---------------------------------------------------------------------------------------------
-- A face is a material Z-City puts over the face of a player model. One whose file is not
-- installed is purple and black squares - on whoever picks it, and on everybody Z-City gives it
-- to: a random appearance takes any face of the list. Clothing packs name such faces: files
-- that come with yet another addon, names that are plainly wrong.
--
-- zcg_fix_faces 1: a face without its file is given the empty material Z-City itself uses for
-- "Default" - the model keeps its own face. The name stays in the menu; ZCG.Faceless remembers
-- what stood there, so zcg_content goes on naming the file, and with the file the face is back.
-- Z-City dresses a player on the server, with the table of the server: there the files of the
-- server decide for everybody. That is right where the players get their content from the very
-- folder the server has, and wrong where they have files the server lacks - the addon cannot
-- know which, so this is off until the owner of the server switches it on.
-- A computer that has little of the content is left alone even then: a dedicated server needs
-- no materials at all. (2 = on any computer; 0 = never, and whatever was changed is put back.)
ZCG.Faceless = ZCG.Faceless or {} -- entry of the tables (as ZCG.ContentWalk names it) -> the material
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

	local function putBack()
		for _, face in ipairs(faces) do
			if face.tbl[face.key] == "" then face.tbl[face.key] = face.path end
		end
		for entry in pairs(lost) do lost[entry] = nil end
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

	ZCG.FacesLeft = nil
	if mode <= 0 then
		putBack()
		ZCG.FacesLeft = { faces = count, why = "off" }
		return nil, "off"
	end
	if mode == 1 then
		local found, all = ZCG.ContentShare()
		if all == 0 or found < MIN_SHARE * all then
			putBack()
			ZCG.FacesLeft = { faces = count, why = "share", there = found, all = all }
			return nil, "share"
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
	return count
end

-- The clothing Lua fills the tables while the game starts, some of it on timers, and a Lua file
-- that is loaded again fills them again: looked at a few times at the start, every two minutes
-- after that, and when the switch is turned. One line in the console when the number changes.
-- Switched off, with nothing to put back, this does nothing at all.
local toldFaces = 0
local function facesPass()
	local mode = ZCG.cvFixFaces and ZCG.cvFixFaces:GetInt() or 0
	if mode <= 0 and next(ZCG.Faceless) == nil then
		toldFaces = 0
		return
	end
	-- (a file that was not there is asked for again: content gets mounted while a game runs)
	for name, found in pairs(there) do
		if not found then there[name] = nil end
	end
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
			ZCG.Print(count .. " faces of the appearance menu have no material file on the " .. (SERVER and "server" or "client")
				.. ": they show the own face of the model instead of purple and black squares - zcg_content names the files, "
				.. "zcg_fix_faces 0 leaves the faces as they are.")
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
--             it are here and none of the other kind - or one or two of them while most of its
--             own are here: a stray file or two do not make a version }, ... }
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
			and (item.ownThere == 0 or (item.ownThere <= 2 and item.there * 2 > item.files))
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
					.. item.instead .. "\" and finds " .. (item.ownThere == 0 and "none" or "next to none")
					.. " of them. Take the build of this addon that has \"" .. item.title
					.. "\" (the other archive of the release) and copy its folder over this one")
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
		if fixed and fixedCount and fixedCount > 0 then
			out("  " .. fixedCount .. " faces have no material file here: until the file is there they show the own face of the"
				.. " model instead of purple and black squares (zcg_fix_faces 0 leaves them as the clothing Lua made them)")
		elseif faceCount > 0 and istable(left) and left.why == "share" then
			out("  " .. faceCount .. " of them are faces, and they stay purple and black squares: only " .. left.there
				.. " of the " .. left.all .. " materials the menu names are on this computer, which is taken for one without"
				.. " the content (a server needs none) - zcg_fix_faces 2 gives them the own face of the model all the same")
		elseif faceCount > 0 then
			out("  " .. faceCount .. " of them are faces: whoever gets one of them has purple and black squares for a face"
				.. " - and Z-City hands faces out by chance")
			out("  zcg_fix_faces 1 (console of the server, or server.cfg) gives such a face the own face of the model until"
				.. " its file is there - right where the players get their content from the folder the server has")
		end
		if #apart > 0 then
			out("  " .. #apart .. " more files are named only for faces that no player model of the menu can wear"
				.. " (the list is for a material none of these models has) - they are not counted:")
			for i = 1, math.min(#apart, 4) do out("    " .. apart[i]) end
			if #apart > 4 then out("    ... and " .. (#apart - 4) .. " more") end
		end
	end

	if #missing == 0 then
		faces()
		ZCG.BoundReport(out)
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
			.. " says why; a folder called materials1, models 2 ...: start sort_content.bat, it goes through such folders"
			.. " itself; any other folder: move it into the materials folder of the addon and start sort_content.bat")
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
