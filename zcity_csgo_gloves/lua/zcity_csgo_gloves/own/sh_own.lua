-- Our own appearance system: the shared half. Everything the addon needs to dress a player is
-- kept in its own catalog (own/sh_catalog.lua, written by tools/catalog.py while the addon was
-- built) and run by its own code - the Appearance Mod is not needed for any of it: not for the
-- models, not for the clothes, not for the faces, not for the accessories, not for the menu.
--
-- What the rest of the server is used to (the gamemode of Z-City calls ApplyAppearance and
-- DrawAppearance, its player classes call hg.Appearance.ForceApplyAppearance, its equipment looks
-- into hg.Accessories) is all here as well: ZCO.Install() puts the catalog into those tables and
-- defines those functions where nothing defines them. With the Appearance Mod installed nothing is
-- taken away from it - what it has is kept and what it does not have is added.

ZCO = ZCO or {}

ZCO.Version = "2.24.4"
ZCO.Name = "Z-City Own Appearance"
ZCO.Catalog = ZCO.Catalog or {}
ZCO.CatalogCounts = ZCO.CatalogCounts or {}

-- 1 = a man, 2 = a woman (as the tables of the game count them)
ZCO.MALE, ZCO.FEMALE = 1, 2
-- the submaterial slots of a player model, in the order the game asks them for
ZCO.SLOTS = { "main", "pants", "boots", "hands" }
-- how many accessories one player wears at most, and one per place
ZCO.MAX_ATTACHMENTS = 3
-- the places the accessories of Z-City are worn on, in the order the menus list them; an accessory
-- whose pack forgot the field is listed under "none" (sh_auto.lua fills the field in where it can)
ZCO.PLACEMENTS = { "head", "face", "ears", "spine", "torso", "none" }
-- the bodygroups of the clothes, in the order of the menu (HANDS is where the gloves are)
ZCO.GROUPS = { "HANDS", "sheet", "pants", "shoes", "TORSO", "LEGS" }

ZCO.Directory = "zco/"            -- data/zco/ on the server and on the client
ZCO.Extension = ".txt"

-- --------------------------------------------------------------------------------------
-- the catalog as the game wants it
-- --------------------------------------------------------------------------------------

-- an accessory the catalog keeps as { pos = { Vector, Angle, scale }, submat = ..., pointshop = ... }
-- and the tables of the game want as { malepos = {...}, SubMat = ..., bPointShop = ... }
local ACCESSORY_NAMES = {
	pos = "malepos", fempos = "fempos", submat = "SubMat", pointshop = "bPointShop", setcolor = "bSetColor",
	color = "vecColorOveride", disallow = "disallowinappearance", cool = "needcoolRender",
}

local function positions(list)
	if type(list) ~= "table" then return nil end
	local got = {}
	for index, value in ipairs(list) do
		got[index] = value
	end
	return got
end

--- one accessory of the catalog as an entry of hg.Accessories
function ZCO.AccessoryEntry(name, data)
	if type(data) ~= "table" then return nil end
	local got = { name = data.name or name }
	for key, value in pairs(data) do
		if key ~= "name" then
			local name_of = ACCESSORY_NAMES[key] or key
			got[name_of] = (name_of == "malepos" or name_of == "fempos") and positions(value) or value
		end
	end
	if not got.malepos then got.malepos = { Vector(0, 0, 0), Angle(0, 0, 0), 1 } end
	if not got.fempos then got.fempos = got.malepos end
	return got
end

--- every accessory of the catalog, as the tables of the game keep them
function ZCO.Accessories()
	local got = {}
	for name, data in pairs(ZCO.Catalog.Accessories or {}) do
		got[name] = ZCO.AccessoryEntry(name, data)
	end
	return got
end

--- the models of one sex the Lua named: { name = { mdl, sex, submatSlots } }. The automatic
--- choices - the default look, a random one, the model a player who came with none is given, the
--- tables of the game - are made of these alone: what a walk through the folder of the addon found
--- (own/sh_scan.lua) is offered in the menu and worn when a player asks for it, and is never put on
--- anybody by itself.
function ZCO.CatalogModels(sex)
	return (ZCO.Catalog.Models or {})[sex or ZCO.MALE] or {}
end

--- the clothes of one sex the Lua named: { name = the material of the sheet }
function ZCO.CatalogClothes(sex)
	return (ZCO.Catalog.Clothes or {})[sex or ZCO.MALE] or {}
end

--- the models of one sex: the ones the Lua named, and the ones the addon found in its own folder
--- and no Lua names (a model in models/ nobody called AppAddModel for - own/sh_scan.lua). The name
--- of a model that was found is its path: a file has no other name two computers agree on.
function ZCO.Models(sex)
	sex = sex or ZCO.MALE
	local mine = ZCO.CatalogModels(sex)
	if not ZCO.MergeModels then return mine end
	return ZCO.MergeModels(sex, mine)
end

--- the clothes of one sex: the ones the Lua named, and the materials the addon found in its own
--- materials/ and no Lua names (their names are their paths as well)
function ZCO.Clothes(sex)
	sex = sex or ZCO.MALE
	local mine = ZCO.CatalogClothes(sex)
	if not ZCO.MergeClothes then return mine end
	return ZCO.MergeClothes(sex, mine)
end

--- the bodygroups of one group and sex: { name = { submodel, pointshop, id } }
function ZCO.Bodygroups(group, sex)
	return ((ZCO.Catalog.Bodygroups or {})[group] or {})[sex or ZCO.MALE] or {}
end

--- the faces of one model: { name = material } - what its slot allows, and nothing else
function ZCO.Faces(model, sex)
	local catalog = ZCO.Catalog
	local faces = {}
	local slot = (catalog.FacemapOf or {})[model]
	if slot then
		for name, material in pairs((catalog.Facemaps or {})[slot] or {}) do
			faces[name] = material
		end
	end
	-- The path the clothing Lua declared and the path the model has in the menu are not always the
	-- same file (models/zcityadodser/... and models/slav/...), and a slot the Lua named is not
	-- always a material the model carries: the faces of every other path of the same file and of
	-- every slot the model file itself carries are the faces of the model as well (2.24.2).
	local lowered = type(model) == "string" and string.lower(model) or nil
	local base = lowered and string.match(lowered, "([^/]+)$") or nil
	local function takeSlot(one)
		for name, material in pairs((catalog.Facemaps or {})[one] or {}) do
			if faces[name] == nil then faces[name] = material end
		end
	end
	if base ~= nil and #base > 0 then
		for known, one in pairs(catalog.FacemapOf or {}) do
			local other = type(known) == "string" and string.lower(known) or nil
			if other ~= nil and other ~= lowered and #other >= #base and string.sub(other, -#base) == base then
				takeSlot(one)
			end
		end
	end
	local textures = ZCGloves and ZCGloves.ModelTextures and ZCGloves.ModelTextures(model) or nil
	if type(textures) == "table" and type(textures.names) == "table" then
		for index = 1, #textures.names do
			for _, path in ipairs(ZCGloves.TexturePaths(textures, index) or {}) do
				if type(path) == "string" and (catalog.Facemaps or {})[path] then takeSlot(path) end
			end
		end
	end
	-- a model with several face slots (the ones MultiFacemaps knows): every face of every slot
	for known, by_face in pairs(catalog.MultiFacemaps or {}) do
		local other = type(known) == "string" and string.lower(known) or nil
		if known == model or (lowered ~= nil and other ~= nil and other == lowered) then
			for face, by_slot in pairs(by_face) do
				if type(by_slot) == "table" then
					for _slot, material in pairs(by_slot) do
						faces[face] = faces[face] or material
					end
				else
					faces[face] = faces[face] or by_slot
				end
			end
		end
	end
	-- a "Default" with no material behind it is the own face of the model and no choice at all:
	-- a model with nothing but that one is a model nobody wrote a face for (2.24.1)
	local chosen = 0
	for _name, material in pairs(faces) do
		if type(material) == "string" and material ~= "" then chosen = chosen + 1 end
	end
	if chosen == 0 then
		-- a model nobody wrote a face for: the faces of its sex, so that the menu is not empty
		for _slot, by_name in pairs(catalog.Facemaps or {}) do
			local wanted = sex == ZCO.FEMALE and "female" or "male"
			if _slot:find(wanted, 1, true) then
				for name, material in pairs(by_name) do
					faces[name] = material
				end
			end
		end
	end
	faces["Default"] = faces["Default"] or ""
	return faces
end

--- the accessories of one place: { name = entry }
function ZCO.AccessoriesByPlacement(placement)
	local got = {}
	for name, data in pairs(ZCO.Catalog.Accessories or {}) do
		if type(data) == "table" and (data.placement or "none") == (placement or "none") then
			got[name] = data
		end
	end
	return got
end

--- every place the accessories are worn on, with how many accessories it has
function ZCO.Placements()
	local got = {}
	for _name, data in pairs(ZCO.Catalog.Accessories or {}) do
		if type(data) == "table" then
			local place = data.placement or "none"
			got[place] = (got[place] or 0) + 1
		end
	end
	return got
end

-- --------------------------------------------------------------------------------------
-- what a player is wearing
-- --------------------------------------------------------------------------------------

--- a model of the catalog by its name or by its path: name, entry, sex
function ZCO.ModelByName(name)
	-- (a player with no model at all asks with nil: an entry of the catalog that has no path of
	-- its own would answer to it, and the player would be dressed for a model he does not wear)
	if not isstring(name) or name == "" then return nil end
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		local entry = ZCO.Models(sex)[name]
		if entry then return name, entry, sex end
	end
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		for known, entry in pairs(ZCO.Models(sex)) do
			if type(entry) == "table" and entry.mdl == name then return known, entry, sex end
		end
	end
	return nil
end

-- --------------------------------------------------------------------------------------
-- a model that is not installed
-- --------------------------------------------------------------------------------------
-- A player model the appearance names and that this computer does not have leaves the player as
-- the ERROR body: the clothes have no submaterial slots to go into, the face has no material to
-- replace, the accessories have no bones to hang on and the gloves have nothing to hide. Nothing
-- tells him so: the game prints one line of its own on the server ("a model that was not
-- precached") and the player just sees a body that is not his. This side looks, says what is
-- missing in whose look, and gives a player who came with no model at all one that is here -
-- which is the only thing that can be done about an invisible player.

ZCO.Gone = ZCO.Gone or {}   -- model path -> { the players it was seen on }

--- is the file of a model there, in this realm?
-- (A model that is not there is asked about again: a copy from the Workshop or from FastDL may
-- still be on its way while the player is already in the game. One that is there is remembered -
-- a file does not go away while the game runs.)
local readyCache = {}   -- model path -> { ok = is it there, at = when it was asked }
function ZCO.ModelReady(path)
	if not isstring(path) or path == "" then return false end
	local known = readyCache[path]
	local now = SysTime()
	if known and (known.ok or now - known.at < 30) then return known.ok end
	local ok = file.Exists(path, "GAME")
	readyCache[path] = { ok = ok, at = now }
	return ok
end

--- a model that is not here: counted once, told once per model (and named again by zco_models).
--- who: the player it was seen on - he is told in his own console as well.
function ZCO.ModelGone(path, who, you)
	local key = (isstring(path) and path ~= "") and path or "(no model at all)"
	local had = ZCO.Gone[key]
	if had == nil then
		had = {}
		ZCO.Gone[key] = had
		local line = "[Z-City Own] " .. (you and "the model of your look" or "a player model of the appearance")
			.. " is not installed on " .. (SERVER and "the server" or "this computer") .. ": " .. key
			.. (key == "(no model at all)"
				and " - a player without a model is invisible, and the clothes, the face, the accessories and the "
					.. "gloves have nothing to go onto"
				or " - on this computer that player is the ERROR body, and the clothes, the face, the accessories "
					.. "and the gloves have nothing to go onto")
			.. ". zco_models" .. (CLIENT and "_cl" or "") .. " names every model that is missing here"
			.. (SERVER and ", zcg_content every file the appearance asks for" or "")
		ZCGloves.Print(line)
		if SERVER and IsValid(who) and who.PrintMessage then who:PrintMessage(HUD_PRINTCONSOLE, line .. "\n") end
	end
	local nick = IsValid(who) and (who.Nick and who:Nick() or "player") or (isstring(who) and who or nil)
	if nick then
		for _, one in ipairs(had) do if one == nick then return end end
		if #had < 20 then had[#had + 1] = nick end
	end
end

--- the first model of the catalog that IS installed here, in the order of the menu: name, entry
function ZCO.AnyModel(sex)
	local sexes = sex and { sex } or { ZCO.MALE, ZCO.FEMALE }
	for _, one in ipairs(sexes) do
		local names = {}
		for name in pairs(ZCO.CatalogModels(one)) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local entry = ZCO.CatalogModels(one)[name]
			if type(entry) == "table" and ZCO.ModelReady(entry.mdl) then return name, entry end
		end
	end
	return nil
end

--- the lines for zco_models: how many models of the catalog are here, and which are not
function ZCO.ModelReport(out)
	out = out or print
	-- (a name may be in both sexes, with a model of its own in each: every pair is counted)
	local every, have, gone = {}, 0, {}
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		for name, entry in pairs(ZCO.Models(sex)) do
			if type(entry) == "table" and isstring(entry.mdl) and entry.mdl ~= "" then
				local line = name .. "  " .. entry.mdl
				every[line] = true
				if ZCO.ModelReady(entry.mdl) then have = have + 1
				else gone[#gone + 1] = line end
			end
		end
	end
	local names = {}
	for line in pairs(every) do names[#names + 1] = line end
	table.sort(names)
	table.sort(gone)
	out("[Z-City Own] models of the appearance on " .. (SERVER and "the server" or "this computer") .. ": "
		.. have .. " of " .. #names .. " are installed" .. (#gone > 0 and ", " .. #gone .. " are not" or ""))
	for i = 1, math.min(#gone, 60) do out("  not here: " .. gone[i]) end
	if #gone > 60 then out("  ... and " .. (#gone - 60) .. " more") end
	local seenOn = {}
	for path, who in pairs(ZCO.Gone) do
		seenOn[#seenOn + 1] = path .. (#who > 0 and "  (seen on: " .. table.concat(who, ", ") .. ")" or "")
			.. (ZCO.ModelReady(path) and "  - it is there now" or "")
	end
	if #seenOn > 0 then
		table.sort(seenOn)
		out("[Z-City Own] models a player was asked to wear and that are not here:")
		for i = 1, math.min(#seenOn, 60) do out("  " .. seenOn[i]) end
		if #seenOn > 60 then out("  ... and " .. (#seenOn - 60) .. " more") end
	else
		out("[Z-City Own] no player was asked for a model that is not here")
	end
	if SERVER then
		out("  (this is the disk of the server. A player may have a model from the Workshop or from FastDL that "
			.. "the server itself has not: zco_models_cl in the console of that player checks his own computer)")
	end
	return #gone
end

concommand.Add("zco_models" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	ZCO.Install()
	local me = SERVER and (IsValid(ply) and ply or nil) or (CLIENT and LocalPlayer() or nil)
	if IsValid(me) then
		local worn = me:GetModel()
		ZCO.ModelReport(print)
		print("[Z-City Own] you are wearing " .. tostring(isstring(worn) and worn ~= "" and worn or "nothing at all")
			.. (ZCO.ModelReady(worn) and " - it is installed here" or " - it is NOT installed here"))
		return
	end
	ZCO.ModelReport(print)
end, nil, "Which models of the appearance are installed here, and which player was asked for one that is not")

--- the sex of an entity: what its model says (the submodels m_anm / f_anm, as Z-City tells it)
function ZCO.IsFemale(ent)
	if not IsValid(ent) then return false end
	if ent.zcoSex ~= nil and ent.zcoSexModel == ent:GetModel() then return ent.zcoSex end
	local submodels = ent.GetSubModels and ent:GetSubModels()
	if type(submodels) == "table" then
		for index = 1, #submodels do
			local name = type(submodels[index]) == "table" and submodels[index].name or nil
			if name == "models/m_anm.mdl" then
				ent.zcoSex, ent.zcoSexModel = false, ent:GetModel()
				return false
			end
			if name == "models/f_anm.mdl" then
				ent.zcoSex, ent.zcoSexModel = true, ent:GetModel()
				return true
			end
		end
	end
	local _name, entry, sex = ZCO.ModelByName(ent:GetModel())
	local female = entry and entry.sex or (sex == ZCO.FEMALE) or false
	ent.zcoSex, ent.zcoSexModel = female, ent:GetModel()
	return female
end

--- the model entry of an entity (and its sex), by the model it wears right now
function ZCO.ModelOf(ent)
	if not IsValid(ent) then return nil, ZCO.MALE end
	local name, entry = ZCO.ModelByName(ent:GetModel())
	if entry then return entry, (entry.sex and ZCO.FEMALE or ZCO.MALE), name end
	return { mdl = ent:GetModel(), sex = ZCO.IsFemale(ent), submatSlots = {} },
		(ZCO.IsFemale(ent) and ZCO.FEMALE or ZCO.MALE), nil
end

--- the slot of a submaterial of an entity by the material that is in it now (0-based, as the game)
function ZCO.SlotOf(ent, material)
	if not IsValid(ent) or not material then return nil end
	local materials = ent:GetMaterials() or {}
	for index = 1, #materials do
		if materials[index] == material then return index - 1 end
	end
	return nil
end

--- the slots of the clothes of an entity: { main = 0, pants = 1, ... }
--- A model no Lua described - one the addon found in its own models/, one from another addon, one
--- a player set by hand - has no submatSlots in the catalog, and without them there is nowhere to
--- put the clothes. Its own file says them: the header of a .mdl lists the materials of the model in
--- the order of their sub-material indices, and the words of their paths say which of them is the
--- sheet, the trousers, the boots and the hands (ZCO.GuessSlots, own/sh_scan.lua).
function ZCO.Slots(ent)
	local entry = ZCO.ModelOf(ent)
	local got = {}
	if type(entry) ~= "table" then return got end
	local slots = type(entry.submatSlots) == "table" and entry.submatSlots or nil
	if not slots or not next(slots) then
		slots = ZCO.GuessSlots and IsValid(ent) and ZCO.GuessSlots(ent:GetModel()) or nil
	end
	if type(slots) ~= "table" then return got end
	for slot, material in pairs(slots) do
		local found = ZCO.SlotOf(ent, material)
		got[slot] = found or (slot == "main" and 0 or nil)
	end
	return got
end

--- the appearance a player wears right now, read back out of the game (for the menu)
function ZCO.Read(ply)
	if not IsValid(ply) then return ZCO.Default() end
	local got = ZCO.Default()
	local entry, sex = ZCO.ModelOf(ply)
	local name = ZCO.ModelByName(ply:GetModel())
	got.AModel = name or (entry and entry.mdl) or got.AModel
	for _, slot in ipairs(ZCO.SLOTS) do
		local worn = ply.GetNWString and ply:GetNWString("Colthes" .. slot, "")
		if worn and worn ~= "" then got.AClothes[slot] = worn end
	end
	got.AName = (ply.GetNWString and ply:GetNWString("PlayerName", "")) or ""
	if got.AName == "" then got.AName = ply:Nick() end
	local color = ply.GetNWVector and ply:GetNWVector("PlayerColor", nil)
	if color then got.AColor = Color(math.floor(color.x * 255), math.floor(color.y * 255), math.floor(color.z * 255)) end
	local attachments = ply.GetNetVar and ply:GetNetVar("Accessories", nil)
	if type(attachments) == "table" then
		got.AAttachments = {}
		for index = 1, #attachments do
			if attachments[index] and attachments[index] ~= "" then got.AAttachments[#got.AAttachments + 1] = attachments[index] end
		end
	elseif type(attachments) == "string" and attachments ~= "" and attachments ~= "none" then
		got.AAttachments = { attachments }
	end
	local bodygroups = ply.GetNetVar and ply:GetNetVar("ZCOBodygroups", nil)
	if type(bodygroups) == "table" then
		for group, name in pairs(bodygroups) do got.ABodygroups[group] = name end
	end
	local face = ply.GetNWString and ply:GetNWString("ZCOFacemap", "")
	if face and face ~= "" then got.AFacemap = face end
	got.Sex = sex
	return got
end

-- --------------------------------------------------------------------------------------
-- an appearance of our own: the same fields the game is used to
-- --------------------------------------------------------------------------------------

--- an appearance with nothing in it but what has to be there
function ZCO.Default(sex)
	local skeleton = ZCO.Catalog.Skeleton
	local got = {
		AModel = (type(skeleton) == "table" and skeleton.AModel) or "Male 01",
		AClothes = { main = "normal", pants = "normal", boots = "normal" },
		AName = "",
		AColor = Color(180, 180, 180),
		AAttachments = {},
		ABodygroups = {},
		AFacemap = "Default",
	}
	if type(skeleton) == "table" then
		if type(skeleton.AClothes) == "table" then
			for slot, name in pairs(skeleton.AClothes) do got.AClothes[slot] = name end
		end
		if skeleton.AName and skeleton.AName ~= "" then got.AName = skeleton.AName end
		if skeleton.AFacemap then got.AFacemap = skeleton.AFacemap end
		if type(skeleton.AColor) ~= "table" then got.AColor = Color(180, 0, 0) end
	end
	if sex == ZCO.FEMALE then
		local names = {}
		for name in pairs(ZCO.CatalogModels(ZCO.FEMALE)) do names[#names + 1] = name end
		table.sort(names)
		if names[1] then got.AModel = names[1] end
	end
	return got
end

--- a copy of an appearance (colors and tables of it as new ones)
function ZCO.Copy(appearance)
	local got = {}
	for key, value in pairs(appearance or {}) do
		if type(value) == "table" then
			if value.r and value.g and value.b then
				got[key] = Color(value.r, value.g, value.b, value.a or 255)
			else
				local inner = {}
				for name, item in pairs(value) do
					if type(item) == "table" and item.r and item.g and item.b then
						inner[name] = Color(item.r, item.g, item.b, item.a or 255)
					else
						inner[name] = item
					end
				end
				got[key] = inner
			end
		else
			got[key] = value
		end
	end
	return got
end

--- a name a player may wear: 2 to 25 letters of the Russian or the English alphabet and spaces
local ALLOWED = {}
local function allow(letters)
	local count = utf8.len(letters) or 0
	for index = 1, count do
		ALLOWED[utf8.GetChar(letters, index)] = true
	end
end
allow("абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
allow("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
ALLOWED[" "] = true

function ZCO.NameValid(name)
	if type(name) ~= "string" then return false end
	local trimmed = name:match("^%s*(.-)%s*$") or ""
	if trimmed == "" then return false end
	-- counted in letters, not in bytes: a Russian letter is two of them
	local letters = utf8 and utf8.len and utf8.len(trimmed) or #trimmed
	if not letters or letters < 2 or letters > 25 then return false end
	for index = 1, letters do
		local one = utf8.GetChar(trimmed, index)
		if not ALLOWED[one] then return false end
	end
	return true
end

--- a random name of a sex (the names of Z-City, or the ones the catalog brought)
function ZCO.RandomName(sex)
	sex = sex or math.random(1, 2)
	local names = (ZCO.Catalog.RandomNames or {})[sex] or {}
	if #names == 0 then
		for _sex, list in ipairs(ZCO.Catalog.RandomNames or {}) do
			if type(list) == "table" and #list > 0 then
				names = list
				break
			end
		end
	end
	if #names == 0 then return (sex == ZCO.FEMALE and "Жительница" or "Житель") end
	return names[math.random(1, #names)]
end

--- a random appearance: a model, clothes to it, a face, one accessory, a name and a color
function ZCO.Random(sex)
	sex = sex or math.random(1, 2)
	local got = ZCO.Default(sex)
	-- (a model or a material that was found in the folder of the addon and no Lua names is worn
	-- when a player chooses it in the menu, and is never chosen for him: what a walk found may be
	-- a prop, a sheet of another game or a material with no texture - own/sh_scan.lua)
	local models = {}
	for name, entry in pairs(ZCO.CatalogModels(sex)) do
		if type(entry) == "table" and entry.mdl then models[#models + 1] = name end
	end
	table.sort(models)
	if #models > 0 then got.AModel = models[math.random(1, #models)] end
	local clothes = {}
	for name in pairs(ZCO.CatalogClothes(sex)) do clothes[#clothes + 1] = name end
	table.sort(clothes)
	if #clothes > 0 then
		local worn = clothes[math.random(1, #clothes)]
		got.AClothes = { main = worn, pants = worn, boots = worn }
	end
	local entry = ZCO.CatalogModels(sex)[got.AModel]
	local faces = {}
	for name in pairs(ZCO.Faces(entry and entry.mdl or "", sex)) do faces[#faces + 1] = name end
	table.sort(faces)
	if #faces > 0 then got.AFacemap = faces[math.random(1, #faces)] end
	local accessories = {}
	for name, data in pairs(ZCO.Catalog.Accessories or {}) do
		if type(data) == "table" and not data.disallow then accessories[#accessories + 1] = name end
	end
	table.sort(accessories)
	if #accessories > 0 then got.AAttachments = { accessories[math.random(1, #accessories)] } end
	got.AName = ZCO.RandomName(sex)
	got.AColor = Color(math.random(0, 255), math.random(0, 255), math.random(0, 255))
	return got
end

--- is an appearance one this addon can put on a player: every field is checked against the catalog
function ZCO.Validate(appearance)
	if type(appearance) ~= "table" then return false, "not a table" end
	local name, entry, sex = ZCO.ModelByName(appearance.AModel)
	if not entry then
		-- a model that is not in the catalog: the game may still have it (another addon)
		if type(appearance.AModel) ~= "string" or appearance.AModel == "" then return false, "no model" end
		sex = ZCO.FEMALE
		name = appearance.AModel
	end
	if type(appearance.AClothes) ~= "table" then return false, "no clothes" end
	local clothes = 0
	for _slot, worn in pairs(appearance.AClothes) do
		if type(worn) ~= "string" then return false, "clothes are not a string" end
		clothes = clothes + 1
	end
	if clothes > #ZCO.SLOTS then return false, "too many clothes" end
	if appearance.AName ~= nil and appearance.AName ~= "" and not ZCO.NameValid(appearance.AName) then
		return false, "the name is not allowed"
	end
	if type(appearance.AAttachments) ~= "table" then return false, "attachments are not a table" end
	if #appearance.AAttachments > ZCO.MAX_ATTACHMENTS then return false, "too many attachments" end
	local places = {}
	for index = 1, #appearance.AAttachments do
		local worn = appearance.AAttachments[index]
		if type(worn) ~= "string" then return false, "an attachment is not a string" end
		if worn ~= "" then
			local data = (ZCO.Catalog.Accessories or {})[worn]
			if not data then return false, "no such accessory: " .. worn end
			local place = data.placement or "none"
			if places[place] then return false, "two accessories on one place: " .. place end
			places[place] = true
		end
	end
	if type(appearance.ABodygroups) ~= "table" then return false, "bodygroups are not a table" end
	for group, worn in pairs(appearance.ABodygroups) do
		if type(worn) ~= "string" then return false, "a bodygroup is not a string" end
		local known = ZCO.Bodygroups(group, sex)
		if worn ~= "" and next(known) and not known[worn] then return false, "no such bodygroup: " .. group end
	end
	if appearance.AFacemap ~= nil and type(appearance.AFacemap) ~= "string" then return false, "the face is not a string" end
	return true, nil, name, sex
end

--- an appearance with only what a player is allowed to wear: what is not in the catalog is dropped
function ZCO.Clean(appearance)
	local got = ZCO.Copy(appearance or {})
	local _name, entry, sex = ZCO.ModelByName(got.AModel)
	sex = sex or ZCO.MALE
	got.AClothes = got.AClothes or {}
	local clothes = ZCO.Clothes(sex)
	for _, slot in ipairs(ZCO.SLOTS) do
		local worn = got.AClothes[slot]
		if type(worn) ~= "string" or (worn ~= "" and not clothes[worn] and not ZCO.Clothes(ZCO.MALE)[worn]
			and not ZCO.Clothes(ZCO.FEMALE)[worn]) then
			got.AClothes[slot] = clothes["normal"] and "normal" or nil
		end
	end
	got.AAttachments = got.AAttachments or {}
	local kept, places = {}, {}
	for index = 1, #got.AAttachments do
		local worn = got.AAttachments[index]
		local data = type(worn) == "string" and worn ~= "" and (ZCO.Catalog.Accessories or {})[worn] or nil
		if data and not data.disallow then
			local place = data.placement or "none"
			if not places[place] and #kept < ZCO.MAX_ATTACHMENTS then
				kept[#kept + 1] = worn
				places[place] = true
			end
		end
	end
	got.AAttachments = kept
	got.ABodygroups = got.ABodygroups or {}
	for group, worn in pairs(got.ABodygroups) do
		local known = ZCO.Bodygroups(group, sex)
		if type(worn) ~= "string" or (worn ~= "" and next(known) ~= nil and not known[worn]) then
			got.ABodygroups[group] = nil
		end
	end
	if got.AName ~= nil and got.AName ~= "" and not ZCO.NameValid(got.AName) then got.AName = "" end
	if type(got.AFacemap) ~= "string" then got.AFacemap = "Default" end
	if type(got.AColor) ~= "table" or not got.AColor.r then got.AColor = Color(180, 180, 180) end
	return got
end

-- --------------------------------------------------------------------------------------
-- who may wear what
-- --------------------------------------------------------------------------------------

if SERVER then
	ZCO.AccessForAll = CreateConVar("zco_access_for_all", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
		"1: every player may wear everything of the catalog (0: admins and the list of zco_access_steam)", 0, 1)
	ZCO.AccessList = CreateConVar("zco_access_steam", "", { FCVAR_ARCHIVE },
		"STEAM_0:1:1234,STEAM_0:0:4321 - who may wear everything when zco_access_for_all is 0")
else
	ZCO.AccessForAll = CreateClientConVar("zco_access_for_all", "1", true, false)
end

--- may this player wear everything of the catalog?
function ZCO.Access(ply)
	if not IsValid(ply) then return false end
	if ply:IsSuperAdmin() or (ply.IsAdmin and ply:IsAdmin()) then return true end
	local cv = ZCO.AccessForAll
	local every = (cv and cv:GetBool()) or GetGlobalBool("zco_access_for_all")
	if every then return true end
	if SERVER then
		local list = ZCO.AccessList and ZCO.AccessList:GetString() or ""
		local id = ply.SteamID and ply:SteamID() or ""
		for one in list:gmatch("[^,;%s]+") do
			if one == id or one == (ply.SteamID64 and tostring(ply:SteamID64()) or "") then return true end
		end
	end
	return false
end

-- --------------------------------------------------------------------------------------
-- the file an appearance is kept in (data/zco/...): lines of "what<TAB>where<TAB>value"
-- --------------------------------------------------------------------------------------

--- an appearance as the text of its file
function ZCO.Serialize(appearance)
	local lines = { "zco\t1" }
	lines[#lines + 1] = "model\t" .. tostring(appearance.AModel or "")
	for _, slot in ipairs(ZCO.SLOTS) do
		local worn = appearance.AClothes and appearance.AClothes[slot]
		if worn and worn ~= "" then lines[#lines + 1] = "clothes\t" .. slot .. "\t" .. worn end
	end
	for group, worn in pairs(appearance.ABodygroups or {}) do
		if worn and worn ~= "" then lines[#lines + 1] = "body\t" .. group .. "\t" .. worn end
	end
	for index = 1, #(appearance.AAttachments or {}) do
		local worn = appearance.AAttachments[index]
		if worn and worn ~= "" then lines[#lines + 1] = "attach\t" .. worn end
	end
	lines[#lines + 1] = "face\t" .. tostring(appearance.AFacemap or "Default")
	lines[#lines + 1] = "name\t" .. tostring(appearance.AName or "")
	local color = appearance.AColor or Color(180, 180, 180)
	lines[#lines + 1] = "color\t" .. math.floor(color.r or 0) .. "\t" .. math.floor(color.g or 0) .. "\t"
		.. math.floor(color.b or 0)
	return table.concat(lines, "\n") .. "\n"
end

--- the appearance a file keeps (nil when the file is not one of ours or is damaged)
function ZCO.Deserialize(text)
	if type(text) ~= "string" or text == "" then return nil end
	local got = ZCO.Default()
	local ours = false
	for line in text:gmatch("[^\r\n]+") do
		local what, where, value = line:match("^([^\t]*)\t([^\t]*)\t?(.*)$")
		if what == "zco" then
			ours = true
		elseif what == "model" then
			got.AModel = where ~= "" and where or got.AModel
		elseif what == "clothes" then
			got.AClothes[where] = value
		elseif what == "body" then
			got.ABodygroups[where] = value
		elseif what == "attach" then
			if #got.AAttachments < ZCO.MAX_ATTACHMENTS then got.AAttachments[#got.AAttachments + 1] = where end
		elseif what == "face" then
			got.AFacemap = where ~= "" and where or "Default"
		elseif what == "name" then
			got.AName = where
		elseif what == "color" then
			local r, g, b = line:match("^color\t(%d+)\t(%d+)\t(%d+)")
			if r then got.AColor = Color(tonumber(r), tonumber(g), tonumber(b)) end
		end
	end
	if not ours then return nil end
	return got
end

--- the name of the file a player's appearance is kept in
function ZCO.FileOf(ply)
	if not IsValid(ply) then return nil end
	local id = ply.SteamID64 and ply:SteamID64() or nil
	if not id or id == "0" then
		id = ply.SteamID and (ply:SteamID():gsub(":", "_")) or nil
	end
	if not id then return nil end
	return ZCO.Directory .. id .. ZCO.Extension
end

-- --------------------------------------------------------------------------------------
-- the tables and the functions the rest of the server is used to
-- --------------------------------------------------------------------------------------

--- what the game has in its appearance tables right now, taken into the catalog: a pack that
--- adds a model, a piece of clothing or an accessory of its own is not lost (it is read after
--- every file of the game has run, and again whenever the catalog is asked for).
--- The tables of the game are what this server really has - another version of the mod, a pack
--- that was updated on the server - so a name they fill is taken as it stands there, and the
--- catalog keeps what they do not fill. Returns how many names the game added to the catalog.
function ZCO.Harvest()
	local taken = 0
	local catalog = ZCO.Catalog
	local function take(into, name, value)
		if into[name] == nil then taken = taken + 1 end
		into[name] = value
	end
	local function text(value)
		return type(value) == "string" and value ~= "" and value or nil
	end
	local appearance = hg and hg.Appearance
	if type(appearance) == "table" then
		catalog.Models, catalog.Clothes = catalog.Models or {}, catalog.Clothes or {}
		for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
			catalog.Models[sex] = catalog.Models[sex] or {}
			catalog.Clothes[sex] = catalog.Clothes[sex] or {}
			for name, entry in pairs(appearance.PlayerModels and appearance.PlayerModels[sex] or {}) do
				if type(entry) == "table" and text(entry.mdl) then take(catalog.Models[sex], name, entry) end
			end
			for name, material in pairs(appearance.Clothes and appearance.Clothes[sex] or {}) do
				local one = text(material)
				if one then take(catalog.Clothes[sex], name, one) end
			end
		end
		-- the description the menu shows under a piece of clothing (a pack writes it next to it)
		catalog.ClothesDesc = catalog.ClothesDesc or {}
		for name, entry in pairs(appearance.ClothesDesc or {}) do
			if type(entry) == "table" then
				local desc, link = text(entry.desc), text(entry.link)
				if desc or link then take(catalog.ClothesDesc, name, { desc = desc, link = link }) end
			end
		end
		catalog.Bodygroups = catalog.Bodygroups or {}
		for group, by_sex in pairs(appearance.Bodygroups or {}) do
			catalog.Bodygroups[group] = catalog.Bodygroups[group] or {}
			for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
				catalog.Bodygroups[group][sex] = catalog.Bodygroups[group][sex] or {}
				for name, entry in pairs(by_sex[sex] or {}) do
					local submodel = text(type(entry) == "table" and entry[1] or entry)
					if submodel then
						take(catalog.Bodygroups[group][sex], name, {
							submodel = submodel,
							pointshop = type(entry) == "table" and entry[2] or false,
							id = type(entry) == "table" and entry.ID or nil,
						})
					end
				end
			end
		end
		catalog.Facemaps, catalog.FacemapOf = catalog.Facemaps or {}, catalog.FacemapOf or {}
		for slot, by_name in pairs(appearance.FacemapsSlots or {}) do
			catalog.Facemaps[slot] = catalog.Facemaps[slot] or {}
			for name, material in pairs(by_name) do
				local one = text(material)
				if one then take(catalog.Facemaps[slot], name, one) end
			end
		end
		for model, slot in pairs(appearance.FacemapsModels or {}) do
			local one = text(slot)
			if one then take(catalog.FacemapOf, model, one) end
		end
		catalog.MultiFacemaps = catalog.MultiFacemaps or {}
		for model, by_face in pairs(appearance.MultiFacemaps or {}) do
			catalog.MultiFacemaps[model] = catalog.MultiFacemaps[model] or {}
			for face, by_slot in pairs(by_face) do
				if type(by_slot) == "table" and next(by_slot) ~= nil then
					take(catalog.MultiFacemaps[model], face, by_slot)
				end
			end
		end
	end
	local accessories = hg and hg.Accessories
	if type(accessories) == "table" then
		ZCO.Catalog.Accessories = ZCO.Catalog.Accessories or {}
		for name, data in pairs(accessories) do
			if type(data) == "table" and (text(data.model) or text(data.femmodel)) then
				local got = { name = data.name or name }
				for key, value in pairs(data) do
					local ours = key
					for short, long in pairs(ACCESSORY_NAMES) do
						if long == key then
							ours = short
							break
						end
					end
					if ours == "malepos" then ours = "pos" end
					if type(value) ~= "function" then got[ours] = value end
				end
				take(ZCO.Catalog.Accessories, name, got)
			end
		end
	end
	ZCO.Harvested = (ZCO.Harvested or 0) + taken
	return taken
end

--- the catalog into the tables of the game, and the functions of them: with no Appearance Mod
--- installed the gamemode, the player classes and the equipment of Z-City find everything they
--- are used to. Where an appearance system is in place already (the Appearance Mod, or a server
--- that has one of its own) its tables are left as they are - only what it does not have is added,
--- and only the functions that are missing are defined: nothing of anybody else's is broken.
function ZCO.Install()
	-- the decision about the tables of the game is made here, and nothing else has to put content
	-- in them before it is made: what sh_auto.lua finds in this addon would look like the content
	-- of an appearance system of somebody else's, and the catalog would stay out of the tables.
	ZCO.Decided = true
	ZCO.Harvest()
	hg = hg or {}
	local appearance = hg.Appearance
	local made = appearance == nil
	hg.Appearance = appearance or {}
	appearance = hg.Appearance

	-- somebody else's appearance system: its tables are its own, the catalog stays ours. (Entries a
	-- clothing pack made by calling this addon - sh_register.lua - are not such a system: that is
	-- content which arrived, and the catalog belongs next to it. Neither are the gloves of this
	-- addon, which stand in the same tables and mark every entry of theirs.)
	local theirs = not made and (next(appearance.PlayerModels or {}) ~= nil
		or next((appearance.PlayerModels or {})[1] or {}) ~= nil
		or next((appearance.Clothes or {})[1] or {}) ~= nil
		or next(appearance.FacemapsSlots or {}) ~= nil
		or next(appearance.Bodygroups or {}) ~= nil)
	if theirs and ZCGloves and type(ZCGloves.RegisteredOnly) == "function"
		and ZCGloves.RegisteredOnly(appearance) then
		theirs = false
	end
	-- The decision is made once: this is called again and again (sv_own.lua, and the catalog looked
	-- at anew), and from the first call on the tables hold our own catalog as well - taken for the
	-- content of somebody else's, the catalog would never be written into them again.
	if theirs and ZCO.Ours then theirs = false end
	ZCO.Ours = not theirs
	ZCO.Theirs = theirs and true or false
	if theirs then
		ZCO.Installed = true
		ZCO.MadeTables = false
		return ZCO.Define()
	end

	appearance.PlayerModels = appearance.PlayerModels or { {}, {} }
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		appearance.PlayerModels[sex] = appearance.PlayerModels[sex] or {}
		-- (only what the Lua named: a model the addon found in its own folder is worn by a player
		-- who chose it in our menu, and is not offered to the menus of everybody else)
		for name, entry in pairs(ZCO.CatalogModels(sex)) do
			if not appearance.PlayerModels[sex][name] then appearance.PlayerModels[sex][name] = entry end
		end
	end
	appearance.FuckYouModels = appearance.FuckYouModels or { {}, {} }
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		for name, entry in pairs(appearance.PlayerModels[sex] or {}) do
			if type(entry) == "table" and entry.mdl then appearance.FuckYouModels[sex][entry.mdl] = entry end
		end
	end

	appearance.Clothes = appearance.Clothes or { {}, {} }
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		appearance.Clothes[sex] = appearance.Clothes[sex] or {}
		for name, material in pairs(ZCO.CatalogClothes(sex)) do
			if not appearance.Clothes[sex][name] then appearance.Clothes[sex][name] = material end
		end
		if not appearance.Clothes[sex]["normal"] then appearance.Clothes[sex]["normal"] = "" end
	end
	appearance.ClothesDesc = appearance.ClothesDesc or {}
	for name, entry in pairs(ZCO.Catalog.ClothesDesc or {}) do
		if not appearance.ClothesDesc[name] then appearance.ClothesDesc[name] = entry end
	end

	appearance.FacemapsSlots = appearance.FacemapsSlots or {}
	for slot, by_name in pairs(ZCO.Catalog.Facemaps or {}) do
		appearance.FacemapsSlots[slot] = appearance.FacemapsSlots[slot] or {}
		for name, material in pairs(by_name) do
			if appearance.FacemapsSlots[slot][name] == nil then appearance.FacemapsSlots[slot][name] = material end
		end
	end
	appearance.FacemapsModels = appearance.FacemapsModels or {}
	for model, slot in pairs(ZCO.Catalog.FacemapOf or {}) do
		if not appearance.FacemapsModels[model] then appearance.FacemapsModels[model] = slot end
	end
	appearance.MultiFacemaps = appearance.MultiFacemaps or {}
	for model, by_face in pairs(ZCO.Catalog.MultiFacemaps or {}) do
		if not appearance.MultiFacemaps[model] then appearance.MultiFacemaps[model] = by_face end
	end

	appearance.Bodygroups = appearance.Bodygroups or {}
	for _, group in ipairs(ZCO.GROUPS) do
		appearance.Bodygroups[group] = appearance.Bodygroups[group] or {}
	end
	for group, by_sex in pairs(ZCO.Catalog.Bodygroups or {}) do
		appearance.Bodygroups[group] = appearance.Bodygroups[group] or {}
		for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
			appearance.Bodygroups[group][sex] = appearance.Bodygroups[group][sex] or {}
			for name, entry in pairs(by_sex[sex] or {}) do
				if not appearance.Bodygroups[group][sex][name] then
					appearance.Bodygroups[group][sex][name] = { entry.submodel, entry.pointshop and true or false,
						ID = entry.id or ("Standard_BodyGroups_" .. name) }
				end
			end
		end
	end
	appearance.Bodygroups.HANDS = appearance.Bodygroups.HANDS or {}
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		appearance.Bodygroups.HANDS[sex] = appearance.Bodygroups.HANDS[sex] or {}
		appearance.Bodygroups.HANDS[sex]["None"] = appearance.Bodygroups.HANDS[sex]["None"] or { "hands", false }
	end

	appearance.RandomNames = appearance.RandomNames or {}
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		if not appearance.RandomNames[sex] or #appearance.RandomNames[sex] == 0 then
			appearance.RandomNames[sex] = (ZCO.Catalog.RandomNames or {})[sex] or {}
		end
	end
	if type(appearance.SkeletonAppearanceTable) ~= "table" then
		appearance.SkeletonAppearanceTable = ZCO.Copy(ZCO.Default())
	end

	hg.Accessories = hg.Accessories or {}
	for name, data in pairs(ZCO.Catalog.Accessories or {}) do
		if not hg.Accessories[name] then hg.Accessories[name] = ZCO.AccessoryEntry(name, data) end
	end
	hg.Accessories.none = hg.Accessories.none or {}

	-- the point shop: with our own rails everything of the catalog is worn by whoever may wear
	-- anything at all, and the items the gamemode asks for are there
	hg.PointShop = hg.PointShop or {}
	local shop = hg.PointShop
	shop.Items = shop.Items or {}
	if type(shop.CreateItem) ~= "function" then
		function shop:CreateItem(id, name, model, bodygroups, _skin, _color, cost, donate, submats)
			shop.Items[id] = { id = id, name = name, model = model, bodygroups = bodygroups, cost = cost or 0,
				donate = donate and true or false, submats = submats or {} }
			return shop.Items[id]
		end
	end
	local player_meta = FindMetaTable("Player")
	if player_meta and type(player_meta.PS_HasItem) ~= "function" then
		function player_meta:PS_HasItem(id)
			return ZCO.Access(self)
		end
	end
	if player_meta and type(player_meta.GetSubMaterialSlots) ~= "function" then
		function player_meta:GetSubMaterialSlots()
			return ZCO.Slots(self)
		end
	end
	local entity_meta = FindMetaTable("Entity")
	if entity_meta and type(entity_meta.GetSubMaterialIdByName) ~= "function" then
		function entity_meta:GetSubMaterialIdByName(material)
			return ZCO.SlotOf(self, material) or false
		end
	end

	ZCO.Installed = true
	-- the tables were filled here: an appearance system of somebody else's returns above. (That a
	-- clothing pack started a table by calling this addon - sh_register.lua - does not make it
	-- somebody else's: the catalog is there next to the content of the pack, and zco_status says so.)
	ZCO.MadeTables = true
	return ZCO.Define()
end

--- the functions the rest of the server calls by name: defined where nothing defines them
function ZCO.Define()
	local appearance = hg.Appearance
	if type(appearance.IsInvalidName) ~= "function" then
		appearance.IsInvalidName = function(name) return not ZCO.NameValid(name) end
	end
	if type(appearance.GenerateRandomName) ~= "function" then
		appearance.GenerateRandomName = function(sex) return ZCO.RandomName(sex) end
	end
	if type(appearance.GetAccessToAll) ~= "function" then
		appearance.GetAccessToAll = function(ply) return ZCO.Access(ply) end
	end
	if type(appearance.AppearanceValidater) ~= "function" then
		appearance.AppearanceValidater = function(tbl) return ZCO.Validate(tbl) end
	end
	if type(appearance.GetRandomAppearance) ~= "function" then
		appearance.GetRandomAppearance = function() return ZCO.Random() end
	end
	if type(appearance.ValidateFunctions) ~= "table" then
		appearance.ValidateFunctions = {
			AModel = function(value) return ZCO.ModelByName(value) ~= nil end,
			AClothes = function(value) return type(value) == "table" end,
			AName = function(value) return type(value) == "string" and ZCO.NameValid(value) end,
			AColor = function(_value) return true end,
			AAttachments = function(value) return type(value) == "table" and #value <= ZCO.MAX_ATTACHMENTS end,
			ABodygroups = function(value) return type(value) == "table" end,
			AFacemap = function(value) return type(value) == "string" end,
		}
	end
	if type(ThatPlyIsFemale) ~= "function" then
		ThatPlyIsFemale = function(ent) return ZCO.IsFemale(ent) end
	end
	return true
end

--- how much the addon has of its own: for zco_status and for the menu
function ZCO.Counts()
	local catalog = ZCO.Catalog
	local got = {
		models = 0, clothes = 0, faces = 0, bodygroups = 0, accessories = 0, names = 0,
		foundModels = 0, foundClothes = 0,
	}
	for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
		for _name in pairs(ZCO.CatalogModels(sex)) do got.models = got.models + 1 end
		for _name in pairs(ZCO.CatalogClothes(sex)) do got.clothes = got.clothes + 1 end
	end
	-- what the addon found in its own folder and no Lua names (own/sh_scan.lua)
	for _path in pairs((ZCO.Scanned or {}).Models and ZCO.Scanned.Models[ZCO.MALE] or {}) do
		got.foundModels = got.foundModels + 1
	end
	for _name in pairs((ZCO.Scanned or {}).Clothes and ZCO.Scanned.Clothes[ZCO.MALE] or {}) do
		got.foundClothes = got.foundClothes + 1
	end
	for _slot, by_name in pairs(catalog.Facemaps or {}) do
		for _name in pairs(by_name) do got.faces = got.faces + 1 end
	end
	for _group, by_sex in pairs(catalog.Bodygroups or {}) do
		for _sex, by_name in pairs(by_sex) do
			for _name in pairs(by_name) do got.bodygroups = got.bodygroups + 1 end
		end
	end
	for _name in pairs(catalog.Accessories or {}) do got.accessories = got.accessories + 1 end
	for _sex, list in pairs(catalog.RandomNames or {}) do
		if type(list) == "table" then got.names = got.names + #list end
	end
	return got
end

--- the catalog is ready when every file of the game has run: the packs add their own tables then
hook.Add("InitPostEntity", "zco_install", function()
	ZCO.Install()
	if SERVER then
		timer.Simple(5, function() ZCO.Harvest() end)
		timer.Simple(30, function() ZCO.Harvest() end)
	end
end)

-- a pack that loads later than we do is taken in as well: the catalog is looked at again
timer.Create("zco_harvest", 30, 0, function()
	if ZCO.Installed then ZCO.Harvest() end
end)

if CLIENT then
	-- the convars of the access are the ones of the server: the menu shows what is allowed
	ZCO.Ready = true
end
