-- Z-City CS:GO gloves - the materials of a model, all of them.
--
-- Z-City dresses a player by sub-material index: it looks for the material of the jacket, the
-- trousers, the boots and the hands in Entity:GetMaterials() and uses the place where it found
-- the name as the index for Entity:SetSubMaterial. The game leaves every material whose file is
-- missing out of that list, and whatever comes after the gap moves up. One material of a player
-- model that is not installed, and the jacket lands on the trousers, the trousers on the boots,
-- and this addon hides something else instead of the hands under a glove.
-- (https://wiki.facepunch.com/gmod/Entity:GetMaterials, "will not contain materials if they are
-- missing")
--
-- The model file knows the whole list. ZCG.MaterialList reads it there and puts the names the
-- game did find back to their real places. Entity:GetMaterials is made to give the same answer,
-- so the code of Z-City and of the clothing addons gets the right indices without being touched;
-- for a model with all its materials nothing changes. CompleteMaterialList = false in
-- sh_config.lua leaves Entity:GetMaterials alone.

local ZCG = ZCGloves
local Config = ZCG.Config

local ENT = FindMetaTable and FindMetaTable("Entity") or nil
if ENT and isfunction(ENT.GetMaterials) then
	-- the function of the game; kept once, because this file may be loaded again
	ZCG.EngineGetMaterials = ZCG.EngineGetMaterials or ENT.GetMaterials
end
local engineList = ZCG.EngineGetMaterials

-- a path the way the game compares it: lower case, forward slashes, none at the ends
local function clean(path)
	path = string.lower(string.gsub(path, "\\", "/"))
	path = string.gsub(path, "/+", "/")
	path = string.gsub(path, "^/", "")
	path = string.gsub(path, "/$", "")
	return path
end
ZCG.CleanPath = clean

-- ---------------------------------------------------------------------------------------------
-- what a .mdl file says about its materials
-- ---------------------------------------------------------------------------------------------
local HEADER = 408 -- size of the header of a model file
local TEXTURES_AT = 204 -- there: number of materials, where they are, number of folders, where they are
local TEXTURE_SIZE = 64

local function readString(f, at, size)
	if at < 0 or at >= size then return nil end
	f:Seek(at)
	local text = f:Read(math.min(256, size - at))
	if not isstring(text) then return nil end
	local stop = string.find(text, "\0", 1, true)
	if stop then text = string.sub(text, 1, stop - 1) end
	return text
end

local function readModel(f)
	local size = f:Size()
	if not isnumber(size) or size < HEADER then return nil end
	f:Seek(0)
	if f:Read(4) ~= "IDST" then return nil end

	f:Seek(TEXTURES_AT)
	local count, at, dirCount, dirAt = f:ReadLong(), f:ReadLong(), f:ReadLong(), f:ReadLong()
	if not (isnumber(count) and isnumber(at) and isnumber(dirCount) and isnumber(dirAt)) then return nil end
	if count < 0 or count > 1024 or dirCount < 0 or dirCount > 256 then return nil end
	if count > 0 and (at < HEADER or at + count * TEXTURE_SIZE > size) then return nil end
	if dirCount > 0 and (dirAt < HEADER or dirAt + dirCount * 4 > size) then return nil end

	local names, dirs = {}, {}
	for i = 0, count - 1 do
		local entry = at + i * TEXTURE_SIZE
		f:Seek(entry)
		local nameAt = f:ReadLong()
		local name = isnumber(nameAt) and readString(f, entry + nameAt, size) or nil
		if not name or name == "" then return nil end
		names[i + 1] = clean(name)
	end
	for i = 0, dirCount - 1 do
		f:Seek(dirAt + i * 4)
		local textAt = f:ReadLong()
		local dir = isnumber(textAt) and readString(f, textAt, size) or nil
		if not dir then return nil end
		dirs[i + 1] = clean(dir)
	end
	if #dirs == 0 then dirs[1] = "" end -- no folder named: the materials folder itself
	return { names = names, dirs = dirs }
end

local models = {} -- lower-case model path -> { names = {...}, dirs = {...} } or { failed = time }

-- The materials a model file names, in the order of their sub-material indices:
-- { names = { "players_sheet", ... }, dirs = { "models/humans/male/group01", ... } }, all lower
-- case; a material is looked for in every folder in turn. nil when the file cannot be read.
function ZCG.ModelTextures(path)
	if not isstring(path) then return nil end
	local key = string.lower(path)
	-- (a brush entity has a model like "*12": nothing to open)
	if string.sub(key, -4) ~= ".mdl" then return nil end
	local known = models[key]
	if known and (known.names or SysTime() - known.failed < 10) then return known.names and known or nil end

	local result
	local f = file.Open(path, "rb", "GAME")
	if f then
		local ok, read = pcall(readModel, f)
		f:Close()
		if ok then result = read end
	end
	models[key] = result or { failed = SysTime() }
	return result
end

-- the paths a material of a model may have: one for every folder the model names
function ZCG.TexturePaths(textures, index)
	local name, out = textures.names[index], {}
	for i, dir in ipairs(textures.dirs) do
		out[i] = dir ~= "" and (dir .. "/" .. name) or name
	end
	return out
end

-- ---------------------------------------------------------------------------------------------
-- the complete list
-- ---------------------------------------------------------------------------------------------
-- Names the appearance system looks for in the list (lower case): the ones it looks for on this
-- very model, and all of them. A missing material of a model that names several folders is given
-- the path somebody waits for.
local function expectedNames(model)
	local own, any = {}, {}
	local AP = istable(hg) and hg.Appearance
	if not istable(AP) then return own, any end
	model = string.lower(model)

	local function add(name, mine)
		if not isstring(name) or name == "" then return end
		name = clean(name)
		any[name] = true
		if mine then own[name] = true end
	end
	if istable(AP.PlayerModels) then
		for sex = 1, 2 do
			for _, entry in pairs(istable(AP.PlayerModels[sex]) and AP.PlayerModels[sex] or {}) do
				if istable(entry) and istable(entry.submatSlots) then
					local mine = isstring(entry.mdl) and string.lower(entry.mdl) == model
					for _, name in pairs(entry.submatSlots) do add(name, mine) end
				end
			end
		end
	end
	for name in pairs(istable(AP.FacemapsSlots) and AP.FacemapsSlots or {}) do add(name, false) end
	-- (Z-City Appearance Mod) faces made of several materials: model -> face -> { slot = material }
	for path, faces in pairs(istable(AP.MultiFacemaps) and AP.MultiFacemaps or {}) do
		local mine = isstring(path) and string.lower(path) == model
		for _, slots in pairs(istable(faces) and faces or {}) do
			for name in pairs(istable(slots) and slots or {}) do add(name, mine) end
		end
	end
	return own, any
end

-- found: what the game answered. Returns the whole list, or nil when nothing is missing or the
-- two lists cannot be told to belong together.
local function complete(model, found)
	local textures = ZCG.ModelTextures(model)
	if not textures then return nil end
	local names = textures.names
	if #names <= #found then return nil end

	local out, own, any = {}, nil, nil
	local at = 1 -- the next name of the game that has no place yet
	for i = 1, #names do
		local name = names[i]
		local have = found[at]
		local path = isstring(have) and clean(have) or nil
		if path and (path == name or string.sub(path, -#name - 1) == "/" .. name) then
			out[i] = have
			at = at + 1
		else
			if not own then own, any = expectedNames(model) end
			local candidates = ZCG.TexturePaths(textures, i)
			local pick
			for _, candidate in ipairs(candidates) do
				if own[candidate] then
					pick = candidate
					break
				end
			end
			if not pick then
				for _, candidate in ipairs(candidates) do
					if any[candidate] then
						pick = candidate
						break
					end
				end
			end
			out[i] = pick or candidates[1]
		end
	end
	if at ~= #found + 1 then return nil end -- a name of the game that the file does not have
	return out
end

local lists = {} -- lower-case model path -> { count = names the game gave, at = time, full = list or false }

local function listFor(ent, found)
	if not istable(found) then return found end
	local model = ent:GetModel()
	if not isstring(model) or model == "" then return found end

	local key = string.lower(model)
	local now = SysTime()
	local known = lists[key]
	-- (asked again every few seconds: the tables of the appearance system fill up while the
	-- game loads, and files may get mounted)
	if not known or known.count ~= #found or now - known.at > 5 then
		known = { count = #found, at = now, full = complete(model, found) or false }
		lists[key] = known
	end
	local full = known.full
	if not full then return found end

	local copy = {}
	for i = 1, #full do copy[i] = full[i] end
	return copy
end

-- Entity:GetMaterials() with the materials the game left out put back: index - 1 is the
-- sub-material index, whatever is installed. A missing material is named by the path it would
-- have had (lower case).
function ZCG.MaterialList(ent)
	if not engineList then return ent:GetMaterials() end
	return listFor(ent, engineList(ent))
end

-- how many materials the game names for the model of an entity, and how many the model has
-- (nil when the model file cannot be read)
function ZCG.MaterialCounts(ent)
	local found = engineList and engineList(ent) or ent:GetMaterials()
	local textures = ZCG.ModelTextures(ent:GetModel())
	return istable(found) and #found or 0, textures and #textures.names or nil
end

-- ---------------------------------------------------------------------------------------------
-- Entity:GetMaterials
-- ---------------------------------------------------------------------------------------------
local broken = false

local function getMaterials(self, ...)
	local found = engineList(self, ...)
	if broken or not istable(found) then return found end
	local ok, full = pcall(listFor, self, found)
	if ok then return full end
	broken = true
	ErrorNoHalt("[CS:GO Gloves] completing Entity:GetMaterials switched off: " .. tostring(full) .. "\n")
	return found
end

if ENT and engineList then
	-- (the file may be loaded again; a function somebody else has put over ours in the meantime
	-- stays where it is, with the one of the earlier load inside)
	local current, ours = ENT.GetMaterials, ZCG.WrappedGetMaterials
	if Config.CompleteMaterialList ~= false then
		if current == engineList or current == ours then
			ENT.GetMaterials = getMaterials
			ZCG.WrappedGetMaterials = getMaterials
		end
	elseif current == ours then
		ENT.GetMaterials = engineList -- switched off
		ZCG.WrappedGetMaterials = nil
	end
end
