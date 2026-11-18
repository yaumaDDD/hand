-- Our own appearance system: the content of this addon, found by this addon itself.
--
-- Everything the menu can put on a player comes out of a catalog (own/sh_catalog.lua) written while
-- the addon was built by running the Lua of Z-City and of the clothing packs: what that Lua does
-- not name is not in it. A model somebody threw into models/ of the addon, a material no pack calls
-- AddClothes for - the file lies in the addon, in the very folder the game reads content from, and
-- the menu does not know it. Nothing tells the owner either: the content is there and is not worn.
--
-- Here the addon looks at its own folder instead of asking the Lua of somebody else. materials/ and
-- models/ are the two folders the game reads the content of an addon from, so every file in them is
-- found by walking them, and what no Lua names is offered by the menu of this addon as well: a model
-- as a model, a material as something to wear. The name of such a thing is its path - a file has no
-- other name two computers could agree on - and the menu shows the path as the file name and the
-- folder it lies in, marked "без Lua".
--
-- Which of the materials of a model is the sheet, the trousers, the boots and the hands - the slots
-- the clothes go into - is read out of the model file itself: the header of a .mdl lists its
-- materials in the order of their sub-material indices (ZCGloves.ModelTextures, sh_materials.lua),
-- and the words of their paths say which slot each of them is. The index on the live player is the
-- one the game gives (Entity:GetMaterials, ZCO.SlotOf). So a model nobody described is dressed all
-- the same, on the server and on the client, and no engine call is needed for it.
--
-- What this cannot do, and says instead of doing:
--   a texture (.vtf, .png) is not worn on its own - the game reads it only through the material that
--     names it in its $basetexture, so textures are counted, and a material whose texture is not
--     there is named as one that will draw the ERROR texture;
--   an accessory needs the bone, the offset and the angle it is worn with, and no file has them -
--     only the Lua of its pack writes them, so a model that is not a player model is listed and not
--     offered (a thing hung on a bone at a guess draws somewhere inside the player);
--   the files of this addon itself - the gloves, the arms inside them, their icons - are not
--     clothes: their paths are baked into their models and they are left out of the walk.
--
-- A copy from the Workshop is mounted as an archive the game does not list folder by folder: there
-- this walk finds nothing at all, and what the build wrote (sh_found.lua) is what the menu has.
-- zco_scan says which of the two it is.

ZCO = ZCO or {}

-- 1: what the walk found and no Lua names can be worn; 0: it is taken back out of the menu
if SERVER then
	ZCO.cvScan = CreateConVar("zco_scan_content", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
		"1: the content of this addon that no Lua names - a model in its models/, a material in its materials/ - is found by walking the folder and can be worn (0: only the catalog is in the menu)", 0, 1)
else
	ZCO.cvScan = CreateClientConVar("zco_scan_content", "1", true, false)
end

-- the budget of one walk: the same limits sh_auto.lua gives its walk through materials/
ZCO.SCAN_MAX_FOLDERS, ZCO.SCAN_MAX_SECONDS, ZCO.SCAN_MAX_FILES = 4000, 3, 8000
-- how many .vmt files one walk opens to see the texture each of them names
ZCO.SCAN_MAX_READ = 400
-- how many files of one kind the menu lists, and how many the console prints
ZCO.SCAN_MAX_MENU, ZCO.SCAN_MAX_LIST = 200, 400

ZCO.Scanned = ZCO.Scanned or nil        -- { Models = { [sex] = { path = path } }, Clothes = { [sex] = { name = name } } }
ZCO.ScanFiles = ZCO.ScanFiles or nil    -- every file of the two folders, sorted: { path, kind, own, named, complete }
ZCO.ScanFolder = ZCO.ScanFolder or nil  -- the folder that was walked (false: the addon is an archive)
ZCO.ScanFolders, ZCO.ScanCut = 0, false -- how many folders the last walk went through, and was it cut short
ZCO.ScanStamp = ZCO.ScanStamp or 0      -- grows whenever what was found changes
ZCO.ScanTried = ZCO.ScanTried or false  -- the walk was tried (a copy from the Workshop has no folder to walk)
ZCO.ScanGuess = ZCO.ScanGuess or {}     -- model path -> the slots read out of its file (false: it has none)
ZCO.ScanTexture = ZCO.ScanTexture or {} -- material path -> the texture its .vmt names (false: it names none)

-- the content of this addon itself: the gloves, the arms inside them, the icons - nothing to wear
-- (the roots zcg_layout.py keeps them by, so that the walk and the sorting tool agree)
local OWN_ROOTS = {
	"materials/zcity_csgo_gloves/", "materials/models/weapons/v_models/arms/", "models/zcity_csgo_gloves/",
}

-- the parts of a model, next to its .mdl: without them the game does not read the model at all
local MODEL_PARTS = { ".vvd" }
local MODEL_MESHES = { ".dx90.vtx", ".vtx", ".sw.vtx" }

-- the words a path says a sex by ("female" before "male": the one holds the other)
local FEMALE_WORDS = { "female", "woman", "girl", "/f/", "f_anm", "_f.", "/w" }
local MALE_WORDS = { "male", "man", "boy", "/m/", "m_anm", "_m.", "/h" }

-- the words a path says a slot by, in the order they are tried: the sheet is asked for last, so
-- that a material of the trousers whose path holds "players" is not taken for the body
local SLOT_WORDS = {
	{ "pants", { "pants", "trousers", "jeans", "legs", "shorts" } },
	{ "boots", { "boots", "shoes", "sneakers", "feet", "foot" } },
	{ "hands", { "hands", "gloves", "arms", "hand", "glove" } },
	{ "main", { "sheet", "body", "player", "torso", "clothes", "uniform", "shirt", "head", "suit" } },
}

local function clean(path)
	return ZCGloves.CleanPath and ZCGloves.CleanPath(path) or path
end

local function ownContent(path)
	for _, root in ipairs(OWN_ROOTS) do
		if string.sub(path, 1, #root) == root then
			return true
		end
	end
	return false
end

--- what a file is, by its name: a model, a material, a texture, a part of a model, or something else
function ZCO.ScanKind(name)
	local lower = string.lower(tostring(name or ""))
	if string.sub(lower, -4) == ".mdl" then return "model" end
	if string.sub(lower, -4) == ".vmt" then return "material" end
	if string.sub(lower, -4) == ".vtf" or string.sub(lower, -4) == ".png" or string.sub(lower, -4) == ".jpg"
		or string.sub(lower, -5) == ".jpeg" then
		return "texture"
	end
	if string.sub(lower, -4) == ".vvd" or string.sub(lower, -4) == ".vtx" or string.sub(lower, -4) == ".phy"
		or string.sub(lower, -4) == ".ani" then
		return "part"
	end
	return "other"
end

--- can the game read a model: its .vvd and a mesh beside it, in the folder that was walked or in
--- anything else the game has mounted. Without them a model draws as an ERROR body, and there is
--- nothing to put an appearance on.
local function modelReadable(path, folder, seen)
	local base = string.sub(path, 1, -5)
	local function there(one)
		if seen and seen[one] then return true end
		if folder and file.Exists(folder .. "/" .. one, "GAME") then return true end
		return file.Exists(one, "GAME")
	end
	local parts = false
	for _, ext in ipairs(MODEL_PARTS) do
		if there(base .. ext) then parts = true end
	end
	local mesh = false
	for _, ext in ipairs(MODEL_MESHES) do
		if there(base .. ext) then mesh = true end
	end
	return parts and mesh
end

--- the sex a path says: 2 when it says a woman, 1 when it says a man or says nothing
function ZCO.ScanSex(path)
	path = string.lower(tostring(path or ""))
	for _, word in ipairs(FEMALE_WORDS) do
		if string.find(path, word, 1, true) then return ZCO.FEMALE end
	end
	for _, word in ipairs(MALE_WORDS) do
		if string.find(path, word, 1, true) then return ZCO.MALE end
	end
	return ZCO.MALE
end

--- the slot a material belongs to by the words of its path: what the menu puts it into when the
--- player clicks it in the list of what was found ("main" when its path says nothing)
function ZCO.SlotOfMaterial(path)
	path = string.lower(tostring(path or ""))
	for _, one in ipairs(SLOT_WORDS) do
		if one[1] ~= "main" then
			for _, word in ipairs(one[2]) do
				if string.find(path, word, 1, true) then return one[1] end
			end
		end
	end
	return "main"
end

--- the name the menu shows for a file that was found: its own name and the folder it lies in
function ZCO.ScanTitle(path)
	path = tostring(path or "")
	local parts = {}
	for part in string.gmatch(path, "[^/]+") do parts[#parts + 1] = part end
	local name = parts[#parts] or path
	name = string.gsub(name, "%.[^%.]+$", "")
	local folder = {}
	for index = 2, #parts - 1 do
		folder[#folder + 1] = parts[index]
	end
	if #folder == 0 then return name end
	return name .. " · " .. table.concat(folder, "/")
end

--- the game name of a material: the path without "materials/" and without ".vmt", as the tables
--- of the appearance keep it
local function materialName(path)
	path = clean(path)
	path = string.gsub(path, "^materials/", "")
	path = string.gsub(path, "%.vmt$", "")
	return path
end

-- --------------------------------------------------------------------------------------
-- what the Lua of the packs and our own catalog name
-- --------------------------------------------------------------------------------------

--- every material and every model some Lua names: what the walk has to leave alone, because a
--- thing that is named is in the menu under the name its Lua gave it
local function namedByLua()
	local mats, models = {}, {}
	local function material(value)
		if not isstring(value) or value == "" then return end
		local name = materialName(value)
		if name ~= "" then mats[name] = true end
	end
	local function model(value)
		if not isstring(value) or value == "" then return end
		local path = clean(value)
		if path ~= "" then models[path] = true end
	end
	-- what the tables of the game hold right now (the packs, and what sh_auto.lua put there)
	if ZCGloves.ContentNeeds then
		local ok, needModels, needMats, idle = pcall(ZCGloves.ContentNeeds)
		if ok then
			for path in pairs(needModels or {}) do model(path) end
			for path in pairs(needMats or {}) do material(path) end
			for path in pairs(idle or {}) do material(path) end
		end
	end
	-- and what our own catalog holds (a build with no pack Lua at all, a client with no tables)
	local catalog = ZCO.Catalog or {}
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		for _name, entry in pairs((catalog.Models or {})[sex] or {}) do
			if istable(entry) then model(entry.mdl) end
		end
		for _name, value in pairs((catalog.Clothes or {})[sex] or {}) do material(value) end
	end
	for _slot, by_name in pairs(catalog.Facemaps or {}) do
		for _name, value in pairs(by_name) do material(value) end
	end
	for _model, by_face in pairs(catalog.MultiFacemaps or {}) do
		for _face, by_slot in pairs(by_face) do
			if istable(by_slot) then
				for _one, value in pairs(by_slot) do material(value) end
			else
				material(by_slot)
			end
		end
	end
	for _name, data in pairs(catalog.Accessories or {}) do
		if istable(data) then
			model(data.model)
			model(data.femmodel)
		end
	end
	return mats, models
end

-- --------------------------------------------------------------------------------------
-- the walk
-- --------------------------------------------------------------------------------------

--- walk materials/ and models/ of the folder of this addon and say what every file is. Returns the
-- files (ZCO.ScanFiles, sorted by path) and whether the walk was cut short by its budget. A copy
-- from the Workshop is an archive the game does not list: there it returns nothing at all.
function ZCO.ScanAll(force)
	if istable(ZCO.ScanFiles) and not force then return ZCO.ScanFiles, ZCO.ScanCut end
	local folder = ZCGloves.FindAddonFolder and ZCGloves.FindAddonFolder() or false
	if not folder then
		ZCO.ScanFiles, ZCO.ScanFolder, ZCO.ScanFolders, ZCO.ScanCut = nil, false, 0, false
		ZCO.ScanTried = true
		return nil, false
	end
	ZCO.ScanTried = true
	local stop = SysTime() + ZCO.SCAN_MAX_SECONDS
	local seen, got, folders, cut = {}, {}, 0, false
	local stack = { folder .. "/materials", folder .. "/models" }
	while #stack > 0 do
		local dir = table.remove(stack)
		folders = folders + 1
		if folders > ZCO.SCAN_MAX_FOLDERS or SysTime() > stop then
			cut = true
			break
		end
		local files, dirs = file.Find(dir .. "/*", "GAME")
		for _, name in ipairs(files or {}) do
			local path = clean(string.sub(dir, #folder + 2) .. "/" .. name)
			if path ~= "" and not seen[path] then
				seen[path] = true
				got[#got + 1] = { path = path, kind = ZCO.ScanKind(name), own = ownContent(path) }
			end
		end
		for _, name in ipairs(dirs or {}) do
			stack[#stack + 1] = dir .. "/" .. name
		end
	end
	table.sort(got, function(a, b) return a.path < b.path end)
	if #got > ZCO.SCAN_MAX_FILES then
		cut = true
		while #got > ZCO.SCAN_MAX_FILES do table.remove(got) end
	end

	-- what the Lua of the packs and our catalog name is left alone, and a model is looked at for
	-- the parts it needs: without its .vvd and a mesh the game does not read it at all
	local mats, models = namedByLua()
	for _, one in ipairs(got) do
		if one.kind == "material" then
			one.named = mats[materialName(one.path)] == true
		elseif one.kind == "model" then
			one.named = models[one.path] == true
			one.complete = modelReadable(one.path, folder, seen)
		end
	end
	ZCO.ScanFiles, ZCO.ScanFolder, ZCO.ScanFolders, ZCO.ScanCut = got, folder, folders, cut
	return got, cut
end

-- --------------------------------------------------------------------------------------
-- what the walk found, into the menu
-- --------------------------------------------------------------------------------------

--- what no Lua names, as the menu of this addon offers it: a complete model as a model, a material
--- as something to wear. The names are the paths. Returns how many models and how many materials
--- can be worn; zco_scan_content 0 takes everything back out of the menu.
function ZCO.ScanWear()
	if not (ZCO.cvScan and ZCO.cvScan:GetBool()) then return ZCO.ScanUnwear() end
	local mats, models = namedByLua()
	local found = { Models = { [ZCO.MALE] = {}, [ZCO.FEMALE] = {} }, Clothes = { [ZCO.MALE] = {} } }
	local worn, clothed = 0, 0
	local read = 0
	if not istable(ZCO.ScanFiles) then
		-- A copy from the Workshop: the game does not list the folders of an archive it mounted, so
		-- there is nothing to walk and the list the build or sort_content.bat wrote is what there is.
		-- Its materials are in the tables of the game already (sh_auto.lua puts them there and
		-- ZCO.Harvest takes them into the catalog); its models are worn from here.
		for _, raw in ipairs(ZCGloves.FoundModels or {}) do
			local path = clean(raw)
			if string.sub(path, -4) == ".mdl" and not ownContent(path) and not models[path]
				and modelReadable(path) then
				found.Models[ZCO.MALE][path] = path
				found.Models[ZCO.FEMALE][path] = path
				worn = worn + 1
			end
		end
		ZCO.Scanned = found
		ZCO.ScanRead = 0
		ZCO.ScanStamp = ZCO.ScanStamp + 1
		return worn, 0
	end
	for _, one in ipairs(ZCO.ScanFiles) do
		if not one.own then
			if one.kind == "model" and one.complete and not one.named and not models[one.path] then
				-- (in both sexes: the menu lists the models of the sex that is chosen, and a model
				-- whose path says nothing about it would be lost when the player changes it)
				found.Models[ZCO.MALE][one.path] = one.path
				found.Models[ZCO.FEMALE][one.path] = one.path
				one.sex = ZCO.ScanSex(one.path)
				worn = worn + 1
			elseif one.kind == "material" and not one.named and not mats[materialName(one.path)] then
				local name = materialName(one.path)
				found.Clothes[ZCO.MALE][name] = name
				one.wear = name
				clothed = clothed + 1
				-- the texture a material names, so that one which will draw the ERROR texture says so
				if read < ZCO.SCAN_MAX_READ then
					read = read + 1
					one.texture = ZCO.MaterialTexture(name)
				end
			end
		end
	end
	ZCO.Scanned = found
	ZCO.ScanRead = read
	ZCO.ScanStamp = ZCO.ScanStamp + 1
	return worn, clothed
end

--- take back everything the walk put into the menu (zco_scan_content 0)
function ZCO.ScanUnwear()
	ZCO.Scanned = nil
	for _, one in ipairs(ZCO.ScanFiles or {}) do one.wear = nil end
	ZCO.ScanStamp = ZCO.ScanStamp + 1
	return 0, 0
end

--- walk the folder of the addon and put what no Lua names into the menu; called when the game has
--- started, again a little later (a pack that loads after us is named by then), and by zco_scan
function ZCO.ScanPass(force)
	if not (ZCO.cvScan and ZCO.cvScan:GetBool()) then return ZCO.ScanUnwear() end
	ZCO.ScanAll(force)
	return ZCO.ScanWear()
end

-- is this model/material one the walk found (and not one a Lua named)?
function ZCO.IsScanned(kind, name)
	local got = ZCO.Scanned
	if not istable(got) or not isstring(name) or name == "" then return false end
	if kind == "model" then
		for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
			if (got.Models or {})[sex] and got.Models[sex][name] then return true end
		end
		return false
	end
	local clothes = (got.Clothes or {})[ZCO.MALE] or {}
	return clothes[name] ~= nil
end

--- the models of the catalog and the ones the walk found, as one table (ZCO.Models calls this; the
-- catalog alone is what the automatic choices are made of - ZCO.CatalogModels). Made anew on every
-- call: a pack that loads later than the walk puts its models into the catalog then (ZCO.Harvest),
-- and a table kept from before would hide them.
function ZCO.MergeModels(sex, mine)
	local found = ZCO.Scanned and ZCO.Scanned.Models and ZCO.Scanned.Models[sex] or nil
	if not istable(found) or not next(found) then return mine end
	local got = {}
	for name, entry in pairs(mine or {}) do got[name] = entry end
	for path in pairs(found) do
		if got[path] == nil then
			got[path] = {
				mdl = path,
				sex = ZCO.ScanSex(path) == ZCO.FEMALE,
				submatSlots = {},
				found = true,
			}
		end
	end
	return got
end

--- the clothes of the catalog and the materials the walk found, as one table (ZCO.Clothes calls it),
-- made anew on every call for the same reason
function ZCO.MergeClothes(sex, mine)
	local found = ZCO.Scanned and ZCO.Scanned.Clothes and ZCO.Scanned.Clothes[ZCO.MALE] or nil
	if not istable(found) or not next(found) then return mine end
	local got = {}
	for name, material in pairs(mine or {}) do got[name] = material end
	for name in pairs(found) do
		if got[name] == nil then got[name] = name end
	end
	return got
end

-- --------------------------------------------------------------------------------------
-- the slots of a model nobody described, out of its own file
-- --------------------------------------------------------------------------------------

--- which material of a model is the sheet, the trousers, the boots and the hands: the header of the
-- .mdl lists its materials in the order of their sub-material indices, the first folder of the model
-- that holds a material is the one the game takes, and the words of the path say which slot it is.
--- Returns { main = path, pants = path, ... } in the shape of the submatSlots of the catalog, so that
--- ZCO.SlotOf finds the index of each of them on the player; nil when the file cannot be read.
function ZCO.GuessSlots(model)
	if not isstring(model) or string.sub(clean(model), -4) ~= ".mdl" then return nil end
	model = clean(model)
	local known = ZCO.ScanGuess[model]
	if known ~= nil then return known or nil end
	local got = nil
	local textures = ZCGloves.ModelTextures and ZCGloves.ModelTextures(model) or nil
	if istable(textures) and istable(textures.names) and #textures.names > 0 then
		-- the material the game finds for every index: the first folder of the model that has it
		local paths = {}
		for index = 1, #textures.names do
			local candidates = (ZCGloves.TexturePaths and ZCGloves.TexturePaths(textures, index)) or {}
			for _, candidate in ipairs(candidates) do
				if file.Exists("materials/" .. candidate .. ".vmt", "GAME") then
					paths[index] = candidate
					break
				end
			end
		end
		local slots, taken = {}, {}
		for _, one in ipairs(SLOT_WORDS) do
			for index = 1, #textures.names do
				local path = paths[index]
				if path and not taken[index] then
					for _, word in ipairs(one[2]) do
						if string.find(path, word, 1, true) then
							slots[one[1]] = path
							taken[index] = true
							break
						end
					end
				end
				if slots[one[1]] then
					break
				end
			end
		end
		-- a body nobody called a sheet: the first material of the model is where the clothes go
		if not slots.main then
			for index = 1, #textures.names do
				if paths[index] and not taken[index] then
					slots.main = paths[index]
					break
				end
			end
		end
		if not slots.main and paths[1] then slots.main = paths[1] end
		if next(slots) then got = slots end
	end
	ZCO.ScanGuess[model] = got or false
	return got
end

-- --------------------------------------------------------------------------------------
-- what a material says about its texture
-- --------------------------------------------------------------------------------------

--- the texture a material names in its $basetexture, as a game path without ".vtf" (false when it
--- names none or its file cannot be read). The file is read once and the answer is kept.
function ZCO.MaterialTexture(name)
	if not isstring(name) or name == "" then return false end
	name = materialName(name)
	local known = ZCO.ScanTexture[name]
	if known ~= nil then return known or false end
	local got = false
	local text = file.Read("materials/" .. name .. ".vmt", "GAME")
	if isstring(text) then
		-- (a .vmt is a KeyValues block: "$basetexture" "path/of/the/texture", in any case, and a
		-- path of a texture is a name the game looks for in lower case all the same)
		local lower = string.lower(text)
		local at = string.find(lower, "$basetexture", 1, true)
		if at then
			local value = string.match(string.sub(lower, at), '^%$basetexture["%s]+"([^"]*)"')
			if isstring(value) and value ~= "" then
				value = clean(value)
				value = string.gsub(value, "%.vtf$", "")
				if string.sub(value, 1, 1) == "!" then
					got = false
				else
					got = value
				end
			end
		end
	end
	ZCO.ScanTexture[name] = got or false
	return got or false
end

--- is a texture there, in this realm?
function ZCO.TextureGone(texture)
	if not isstring(texture) or texture == "" then return false end
	return not file.Exists("materials/" .. clean(texture) .. ".vtf", "GAME")
end

--- is the texture of a material there? (a material with no $basetexture of its own draws what its
--- shader gives it - it is not broken)
function ZCO.MaterialBroken(name)
	local texture = ZCO.MaterialTexture(name)
	if not texture then return false end
	return ZCO.TextureGone(texture)
end

-- --------------------------------------------------------------------------------------
-- what the walk found, said out loud
-- --------------------------------------------------------------------------------------

--- how much of what the addon has was found by the walk and not named by any Lua
function ZCO.ScanCounts()
	local got = {
		folders = ZCO.ScanFolders or 0, files = 0, own = 0, models = 0, complete = 0, brokenModels = 0,
		namedModels = 0, materials = 0, namedMaterials = 0, textures = 0, parts = 0, other = 0,
		wearModels = 0, wearMaterials = 0, read = 0, noTexture = 0, cut = ZCO.ScanCut and true or false,
	}
	for _, one in ipairs(ZCO.ScanFiles or {}) do
		got.files = got.files + 1
		if one.own then
			got.own = got.own + 1
		elseif one.kind == "model" then
			got.models = got.models + 1
			if one.complete then
				got.complete = got.complete + 1
			else
				got.brokenModels = got.brokenModels + 1
			end
			if one.named then got.namedModels = got.namedModels + 1 end
		elseif one.kind == "material" then
			got.materials = got.materials + 1
			if one.named then got.namedMaterials = got.namedMaterials + 1 end
			if one.texture ~= nil then
				got.read = got.read + 1
				if one.texture == false or ZCO.TextureGone(one.texture) then
					got.noTexture = got.noTexture + 1
				end
			end
		elseif one.kind == "texture" then
			got.textures = got.textures + 1
		elseif one.kind == "part" then
			got.parts = got.parts + 1
		else
			got.other = got.other + 1
		end
	end
	if istable(ZCO.Scanned) then
		for _path in pairs((ZCO.Scanned.Models or {})[ZCO.MALE] or {}) do got.wearModels = got.wearModels + 1 end
		for _name in pairs((ZCO.Scanned.Clothes or {})[ZCO.MALE] or {}) do
			got.wearMaterials = got.wearMaterials + 1
		end
	end
	return got
end

--- the lines for zco_status and zco_scan: what the addon has that no Lua named
function ZCO.ScanReport(out)
	out = out or print
	local worn = 0
	for _path in pairs((ZCO.Scanned or {}).Models and ZCO.Scanned.Models[ZCO.MALE] or {}) do worn = worn + 1 end
	if not (ZCO.cvScan and ZCO.cvScan:GetBool()) then
		out("  Контент без Lua: выключен (zco_scan_content 0) — в меню только то, что называет Lua.")
		return
	end
	local folder = ZCO.ScanFolder
	if folder == false or (folder == nil and not istable(ZCO.ScanFiles)) then
		ZCO.ScanAll()
		folder = ZCO.ScanFolder
	end
	if not folder then
		local shipped = istable(ZCGloves.Found) and #ZCGloves.Found or 0
		local models = istable(ZCGloves.FoundModels) and #ZCGloves.FoundModels or 0
		out("  Контент без Lua: аддон смонтирован архивом (копия из Мастерской) — игра не перечисляет его")
		out("  папки, поэтому в игре ничего не находится. Список даёт то, что написала сборка или")
		out(("  sort_content.bat (lua/zcity_csgo_gloves/sh_found.lua): материалов %d, моделей %d.")
			:format(shipped, models))
		if worn > 0 then
			out(("    Моделей из этого списка можно надеть: %d — они в меню внешности, в категории «Без Lua».")
				:format(worn))
		end
		return
	end
	local got = ZCO.ScanCounts()
	out(("  Контент без Lua (zco_scan_content 1): %s, папок %d, файлов %d%s — из них своих (перчаток) %d.")
		:format(folder, got.folders, got.files, got.cut and " (обход прерван бюджетом)" or "", got.own))
	out(("    модели: %d, полных %d (есть .vvd и .vtx), названных Lua %d — надеть можно %d.")
		:format(got.models, got.complete, got.namedModels, got.wearModels))
	if got.brokenModels > 0 then
		out(("    моделей без частей (нет .vvd или .vtx — игра их не прочитает): %d.")
			:format(got.brokenModels))
	end
	out(("    материалы: %d, названных Lua %d — надеть можно %d; прочитано .vmt %d, у %d нет текстуры рядом.")
		:format(got.materials, got.namedMaterials, got.wearMaterials, got.read, got.noTexture))
	out(("    текстуры: %d (текстура сама не надевается: её читает материал через $basetexture),")
		:format(got.textures))
	out(("    частей моделей (.vvd/.vtx/.phy): %d, прочих файлов: %d.")
		:format(got.parts, got.other))
	out("    Слоты модели, которую никто не описал, читаются из её файла (.mdl) и сверяются с игрой на")
	out("    живом игроке, поэтому одежда надевается и на неё. Всё найденное — в меню, категория")
	out("    «Без Lua»; список файлов — zco_scan_list" .. (CLIENT and "_cl" or "") .. ".")
end

local function say(ply, text)
	if IsValid(ply) and ply.IsPlayer and ply:IsPlayer() and ply.PrintMessage then
		ply:PrintMessage(3, text)
	else
		print(text)
	end
end

--- walk the folder of the addon now and say what was found
concommand.Add("zco_scan" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then
		say(ply, "Только администрация.")
		return
	end
	local worn, clothed = ZCO.ScanPass(true)
	ZCO.ScanReport(function(text) say(ply, text) end)
	if ZCO.ScanFolder then
		say(ply, ("  Надеть можно: моделей %d, материалов %d — они в меню внешности (zco_menu), в своих")
			:format(worn, clothed))
		say(ply, "  категориях с пометкой «без Lua» и в категории «Без Lua» списком.")
	end
end, nil, "Walk the folder of this addon: which models, materials and textures no Lua names, and which of them can be worn")

--- every file the walk found, with what it is
concommand.Add("zco_scan_list" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then
		say(ply, "Только администрация.")
		return
	end
	ZCO.ScanAll()
	if not istable(ZCO.ScanFiles) then
		say(ply, "[Внешность] Папки аддона не перечисляются (копия из Мастерской смонтирована архивом): список")
		say(ply, "[Внешность] даёт то, что написала сборка — lua/zcity_csgo_gloves/sh_found.lua.")
		return
	end
	local lines = {}
	for _, one in ipairs(ZCO.ScanFiles) do
		if not one.own then
			local what = one.kind
			if one.kind == "model" then
				what = one.complete and (one.named and "модель (названа Lua)" or "модель (надеть можно)")
					or "модель неполная (нет .vvd или .vtx)"
				if one.complete and not one.named then
					local slots = ZCO.GuessSlots(one.path)
					if istable(slots) then
						local named = {}
						for slot, path in pairs(slots) do named[#named + 1] = slot .. " → " .. path end
						table.sort(named)
						what = what .. ", слоты из файла: " .. table.concat(named, ", ")
					end
				end
			elseif one.kind == "material" then
				what = one.named and "материал (назван Lua)" or "материал (надеть можно)"
				local texture = one.texture or ZCO.MaterialTexture(materialName(one.path))
				if texture then
					what = what .. ", $basetexture " .. texture
						.. (file.Exists("materials/" .. texture .. ".vtf", "GAME") and "" or " — ТЕКСТУРЫ НЕТ")
				end
			elseif one.kind == "texture" then
				what = "текстура (не надевается сама: её читает материал)"
			elseif one.kind == "part" then
				what = "часть модели"
			elseif one.kind == "other" then
				what = "прочий файл (не контент: игра его не читает)"
			end
			lines[#lines + 1] = one.path .. "  —  " .. what
		end
	end
	table.sort(lines)
	say(ply, ("[Внешность] Файлы аддона, кроме своих (перчаток): %d"):format(#lines))
	for index = 1, math.min(#lines, ZCO.SCAN_MAX_LIST) do say(ply, "  " .. lines[index]) end
	if #lines > ZCO.SCAN_MAX_LIST then say(ply, ("  ... и ещё %d"):format(#lines - ZCO.SCAN_MAX_LIST)) end
end, nil, "Every model, material and texture in the folder of this addon, with what the addon makes of it")

-- the walk runs when the game has started, and again a little later: a pack that loads after this
-- file may name a material the first walk took for one nobody names
hook.Add("InitPostEntity", "zco_scan", function()
	pcall(ZCO.ScanPass, true)
	if SERVER then
		timer.Simple(5, function() pcall(ZCO.ScanPass, true) end)
		timer.Simple(30, function() pcall(ZCO.ScanPass, true) end)
	end
end)

-- switching the check off takes what it found back out of the menu; switching it on looks again
if cvars and cvars.AddChangeCallback then
	cvars.AddChangeCallback("zco_scan_content", function()
		timer.Simple(0, function() pcall(ZCO.ScanPass, true) end)
	end, "zco_scan")
end
