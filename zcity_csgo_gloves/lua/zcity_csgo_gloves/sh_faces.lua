-- Faces in every table the menus of Z-City read.
--
-- Z-City keeps faces in two systems that live side by side:
--   FacemapsSlots[slot material][name of the face] = material            (the gamemode itself)
--   MultiFacemaps[model][name of the face][slot material] = material     (Z-City Appearance Mod)
-- A face can be made of several materials, one per slot of the model - that is what the second
-- table is for. The first one holds one material per face and per slot.
--
-- What a clothing pack calls by name, AddFacemap(matOverride, strName, matMaterial, model), writes
-- the FIRST table only - in the gamemode (sh_shared.lua) and in the fix addon the packs carry
-- (sh_zcity_appearance_fix.lua) alike; this addon does the same (sh_register.lua), because that is
-- what the packs expect. The menu of the Appearance Mod, on the other hand, lists the faces of a
-- model from the SECOND one as soon as the model has a single entry in it, and does not look into
-- the first at all (cl_!!!_appearancemod_buttons.lua: "if multi then combinedVariants = multi
-- else ... FacemapsSlots ..."). The models the mod gives faces of its own to are the models of the
-- menu - so a face a pack added the old way is in the tables and is worn when something chooses
-- it, but has no button in that menu. The other way round: the plain menu of Z-City, its editor
-- and the LEGACY build read the FIRST table only, and a face that exists as a multi-facemap alone
-- has no button there.
--
-- Here the two are kept in sync, whichever way a face arrived - from a pack, from the mod, from
-- the list of content without Lua (sh_auto.lua) or from the lines the build wrote (sh_baked.lua):
--   * a face of a slot goes into MultiFacemaps of every model that wears that slot, so that the
--     menu of the mod lists it; which models wear a slot is read from the tables and, where the
--     model file can be opened, from the model itself - the paths a pack declares and the paths
--     the menu shows are not always the same model (models/zcityadodser/... and models/slav/...);
--   * a face of MultiFacemaps goes into FacemapsSlots of its slot, so that the plain menu, the
--     editor of Z-City and the LEGACY build list it as well;
--   * ModelFaceSlots and FacemapsModels get the models and slots that are known, and every key
--     the menus look up in lower case (the mod lower-cases the model it is given, the gamemode
--     does not, and both menus ask for the lower-case path of the model).
-- Nothing is ever replaced: an entry that is there with another value stays as it is and is
-- counted in ZCG.FaceClash. What was added here is taken back when zcg_sync_faces is 0.

local ZCG = ZCGloves

ZCG.cvSyncFaces = CreateConVar("zcg_sync_faces", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
	"Appearance menu: 1 = the two systems of faces Z-City has are kept in sync - a face the clothing "
	.. "Lua put into FacemapsSlots is listed by the menu of the Appearance Mod as well, and a face that "
	.. "is only a multi-facemap is listed by the plain menu of Z-City and by the LEGACY build; "
	.. "0 = the tables are left as the clothing Lua made them and what this addon added is taken back.", 0, 1)

-- what this addon put into the tables, in the order it was put there: { kind, table, key, value,
-- a table made on the way, its path as text }. It is taken back when zcg_sync_faces is 0, and
-- zcg_faces lists it.
ZCG.FaceAdded = ZCG.FaceAdded or {}
local added = ZCG.FaceAdded

ZCG.FaceClash = ZCG.FaceClash or 0 -- an entry that is there with another value: left alone
ZCG.FaceMade = ZCG.FaceMade or { multi = 0, slots = 0, models = 0, lower = 0, alias = 0, shared = 0 }

local function clean(path)
	return string.lower(string.gsub(tostring(path), "\\", "/"))
end

local function has(path) return file.Exists(path, "GAME") end

--- write value at keys of root, making the tables on the way; nothing that is there is replaced
local function put(kind, root, keys, value)
	if type(root) ~= "table" then return false end
	local tbl, soFar = root, ""
	for index = 1, #keys - 1 do
		local key = keys[index]
		soFar = soFar == "" and tostring(key) or soFar .. "/" .. tostring(key)
		local inner = tbl[key]
		if inner == nil then
			inner = {}
			tbl[key] = inner
			added[#added + 1] = { kind, tbl, key, inner, true, soFar }
		elseif type(inner) ~= "table" then
			return false -- something else is there: the face is not put over it
		end
		tbl = inner
	end
	local key = keys[#keys]
	soFar = soFar == "" and tostring(key) or soFar .. "/" .. tostring(key)
	local now = tbl[key]
	if now ~= nil then
		if now ~= value then ZCG.FaceClash = ZCG.FaceClash + 1 end
		return false
	end
	tbl[key] = value
	added[#added + 1] = { kind, tbl, key, value, false, soFar }
	ZCG.FaceMade[kind] = (ZCG.FaceMade[kind] or 0) + 1
	return true
end

local function takeBack()
	for index = #added, 1, -1 do
		local one = added[index]
		local tbl, key, value, made = one[2], one[3], one[4], one[5]
		if type(tbl) == "table" and tbl[key] == value then
			-- a table made on the way stays when somebody put something into it since
			if not (made and next(value) ~= nil) then tbl[key] = nil end
		end
		added[index] = nil
	end
	ZCG.FaceMade = { multi = 0, slots = 0, models = 0, lower = 0, alias = 0, shared = 0 }
	ZCG.FaceClash = 0
end

--- which models wear a face slot, and which slots a model wears: slot -> { model = true },
--- model -> { slot = true }, both lower case. Read out of the tables and, where the model file of
--- a model of the menu can be opened, out of the model itself.
local function slotModels(AP, slots)
	local modelsOf, slotsOf = {}, {}
	local function note(model, slot)
		model, slot = clean(model), clean(slot)
		if model == "" or slot == "" then return end
		modelsOf[slot] = modelsOf[slot] or {}
		modelsOf[slot][model] = true
		slotsOf[model] = slotsOf[model] or {}
		slotsOf[model][slot] = true
	end

	if istable(AP.MultiFacemaps) then
		for model, faces in pairs(AP.MultiFacemaps) do
			if istable(faces) then
				for _, byslot in pairs(faces) do
					if istable(byslot) then
						for slot, path in pairs(byslot) do
							if isstring(path) and path ~= "" then note(model, slot) end
						end
					end
				end
			end
		end
	end
	if istable(AP.ModelFaceSlots) then
		for model, list in pairs(AP.ModelFaceSlots) do
			if istable(list) then
				for slot, yes in pairs(list) do
					if yes then note(model, slot) end
				end
			end
		end
	end
	if istable(AP.FacemapsModels) then
		for model, slot in pairs(AP.FacemapsModels) do
			if isstring(slot) then note(model, slot) end
		end
	end

	-- the models of the menu: a slot their own model file names is a slot they wear, whatever the
	-- Lua declared (and a declaration that names another path of the same model does not help)
	local names = {}
	for slot in pairs(slots or {}) do
		if isstring(slot) then names[clean(slot)] = true end
	end
	if istable(AP.PlayerModels) and ZCG.ModelTextures and ZCG.TexturePaths and next(names) ~= nil then
		for sex = 1, 2 do
			local list = istable(AP.PlayerModels[sex]) and AP.PlayerModels[sex] or {}
			for _, entry in pairs(list) do
				local model = istable(entry) and isstring(entry.mdl) and clean(entry.mdl) or nil
				local textures = model and string.sub(model, -4) == ".mdl" and has(model)
					and ZCG.ModelTextures(model) or nil
				if istable(textures) and istable(textures.names) then
					for index = 1, #textures.names do
						for _, path in ipairs(ZCG.TexturePaths(textures, index) or {}) do
							path = clean(path)
							if names[path] then note(model, path) end
						end
					end
				end
			end
		end
	end
	return modelsOf, slotsOf
end

--- put every face into the table the other menu reads; returns how many entries were added,
--- false when there is nothing to do (no tables, or zcg_sync_faces is 0)
--- What an earlier pass added is taken back first and made anew: a face that is gone from the
--- table it was read from - content without Lua switched off, a table made anew by a Lua refresh -
--- leaves the other table with it, and no entry of this addon outlives what it was made of.
function ZCG.SyncFaces()
	local AP = istable(hg) and hg.Appearance
	if not istable(AP) then return false end
	if #added > 0 then takeBack() end
	if not (ZCG.cvSyncFaces and ZCG.cvSyncFaces:GetBool()) then return false end
	local slots = istable(AP.FacemapsSlots) and AP.FacemapsSlots or nil
	local multi = istable(AP.MultiFacemaps) and AP.MultiFacemaps or nil
	-- no face anywhere: no table is made (the own appearance system of this addon asks whether the
	-- tables are content that arrived or a system of somebody else's - own/sh_own.lua)
	if not slots and not multi then return false end

	local modelsOf, slotsOf = slotModels(AP, slots)
	local made = 0

	-- 1. a face of a slot into MultiFacemaps of every model that wears the slot
	if istable(slots) then
		local want = {}
		for slot, faces in pairs(slots) do
			if isstring(slot) and istable(faces) then
				local models = modelsOf[clean(slot)]
				if istable(models) then
					for name, path in pairs(faces) do
						if isstring(name) and isstring(path) and path ~= "" then
							for model in pairs(models) do want[#want + 1] = { model, name, clean(slot), path } end
						end
					end
				end
			end
		end
		if #want > 0 then
			if not istable(AP.MultiFacemaps) then AP.MultiFacemaps = {} end
			multi = AP.MultiFacemaps
			for _, one in ipairs(want) do
				if put("multi", multi, { one[1], one[2], one[3] }, one[4]) then made = made + 1 end
			end
		end
	end

	-- 2. a face of MultiFacemaps into FacemapsSlots of its slot
	if istable(multi) then
		local want = {}
		for _, faces in pairs(multi) do
			if istable(faces) then
				for name, byslot in pairs(faces) do
					if isstring(name) and istable(byslot) then
						for slot, path in pairs(byslot) do
							if isstring(slot) and isstring(path) and path ~= "" then
								want[#want + 1] = { clean(slot), name, path }
							end
						end
					end
				end
			end
		end
		if #want > 0 then
			if not istable(AP.FacemapsSlots) then AP.FacemapsSlots = {} end
			slots = AP.FacemapsSlots
			for _, one in ipairs(want) do
				if put("slots", slots, { one[1], one[2] }, one[3]) then made = made + 1 end
			end
		end
	end

	-- 3. the models and their slots, where the menus look them up
	local wantModels = {}
	for model, list in pairs(slotsOf) do
		local one, several
		for slot in pairs(list) do
			if one then several = true end
			one = slot
		end
		wantModels[#wantModels + 1] = { model, one, several and true or false }
	end
	if #wantModels > 0 then
		if not istable(AP.ModelFaceSlots) then AP.ModelFaceSlots = {} end
		for _, one in ipairs(wantModels) do
			for slot in pairs(slotsOf[one[1]] or {}) do
				put("models", AP.ModelFaceSlots, { one[1], slot }, true)
			end
			-- the plain system knows one slot per model: it is told the one the model has, where
			-- it has one alone (with several the menu of the mod is the one that lists the faces)
			if not one[3] and one[2] and not istable(AP.FacemapsModels) then AP.FacemapsModels = {} end
			if not one[3] and one[2] and istable(AP.FacemapsModels) then
				put("models", AP.FacemapsModels, { one[1] }, one[2])
			end
		end
	end

	-- 4. a model whose own materials name none of the slots its faces are registered under: the
	-- gamemode applies a face with FacemapsSlots[material of the player][name of the face], so a
	-- slot key the model file does not carry means no face ever lands on that model, whatever the
	-- menus show. The faces of every slot of such a model are mirrored into the material the model
	-- actually has - the one that reads as its face (a path with "face" or "head" in it), the only
	-- material of a model that has one, or the first material no face slot is registered under.
	-- (2.23.0: the faces of the clothing Lua work on every model that carries them, not only on
	-- the models compiled with the slot the Lua named.)
	if istable(slots) and ZCG.ModelTextures then
		local function slotThere(mat)
			return slots[mat] ~= nil or slots[clean(mat)] ~= nil
		end
		local want = {}
		for model, list in pairs(slotsOf) do
			local textures = has(model) and ZCG.ModelTextures(model) or nil
			local paths = {}
			if istable(textures) and istable(textures.names) then
				for index = 1, #textures.names do
					for _, path in ipairs(ZCG.TexturePaths(textures, index) or {}) do
						if isstring(path) and path ~= "" then paths[#paths + 1] = path end
					end
				end
			end
			if #paths > 0 then
				local hit = false
				for _, path in ipairs(paths) do
					local name = clean(path)
					if list[name] or slotThere(name) then hit = true end
				end
				local target
				if not hit then
					for _, path in ipairs(paths) do
						local name = clean(path)
						if name:find("face", 1, true) or name:find("head", 1, true) then
							target = path
							break
						end
					end
					if not target and #paths == 1 then target = paths[1] end
					if not target then
						for _, path in ipairs(paths) do
							if not slotThere(path) then target = path break end
						end
					end
				end
				if not hit and isstring(target) and target ~= "" then
					for slot in pairs(list) do want[#want + 1] = { model, slot, target } end
				end
			end
		end
		for _, one in ipairs(want) do
			local model, slot, target = one[1], one[2], one[3]
			local faces
			for key, value in pairs(slots) do
				if isstring(key) and clean(key) == slot and istable(value) then faces = value break end
			end
			if istable(faces) then
				for name, path in pairs(faces) do
					if isstring(name) and isstring(path) and path ~= "" then
						if put("alias", slots, { target, name }, path) then made = made + 1 end
						if istable(multi) and put("alias", multi, { model, name, clean(target) }, path) then
							made = made + 1
						end
					end
				end
			end
		end
	end

	-- 5. a model of the menu nobody wrote a face for: the faces of its sex, so that the choice of
	-- a face is never empty. The clothing Lua gives a model of Z-City a slot with a "Default" and
	-- an empty material and nothing else (Cohrt, Leet, John Wick) - both menus then list no face at
	-- all, and the own menu of this addon has had the rule for its own catalog since 2.20.0
	-- (own/sh_own.lua: "a model nobody wrote a face for: the faces of its sex, so that the menu is
	-- not empty"). Here the same rule is put into the tables the menus of the game read. (2.24.1)
	if istable(AP.PlayerModels) and istable(slots) then
		--- how many faces a model can be given: the ones of its slot, of the slots its own file
		--- carries and of its multi-facemaps, an empty material ("Default") is no face
		local function usable(model)
			local got = 0
			local function count(list)
				if not istable(list) then return end
				for _, path in pairs(list) do
					if isstring(path) and path ~= "" then got = got + 1 end
				end
			end
			local multi = istable(AP.MultiFacemaps) and (AP.MultiFacemaps[model]
				or AP.MultiFacemaps[clean(model)]) or nil
			if istable(multi) then
				for _, byslot in pairs(multi) do count(byslot) end
			end
			local told = {}
			if istable(AP.FacemapsModels) then
				local one = AP.FacemapsModels[model] or AP.FacemapsModels[clean(model)]
				if isstring(one) and one ~= "" then told[clean(one)] = one end
			end
			if istable(AP.ModelFaceSlots) then
				local list = AP.ModelFaceSlots[model] or AP.ModelFaceSlots[clean(model)]
				if istable(list) then
					for slot, yes in pairs(list) do
						if yes and isstring(slot) and slot ~= "" then told[clean(slot)] = slot end
					end
				end
			end
			for slot in pairs(istable(slotsOf[model]) and slotsOf[model] or {}) do told[slot] = slot end
			for _, slot in pairs(told) do
				count(slots[slot] or slots[clean(slot)])
			end
			return got, told
		end

		--- the material of the model a face goes onto: the slot it is told to wear, else one its
		--- own file names - the one that reads as a face, the only one, or the first no slot is
		--- registered under (the search of the pass above)
		local function targetOf(model, told)
			for _, slot in pairs(told or {}) do
				if isstring(slot) and slot ~= "" then return slot end
			end
			local textures = has(model) and ZCG.ModelTextures and ZCG.ModelTextures(model) or nil
			if not (istable(textures) and istable(textures.names)) then return nil end
			local paths = {}
			for index = 1, #textures.names do
				for _, path in ipairs(ZCG.TexturePaths(textures, index) or {}) do
					if isstring(path) and path ~= "" then paths[#paths + 1] = path end
				end
			end
			if #paths == 0 then return nil end
			for _, path in ipairs(paths) do
				local name = clean(path)
				if name:find("face", 1, true) or name:find("head", 1, true) then return path end
			end
			if #paths == 1 then return paths[1] end
			for _, path in ipairs(paths) do
				if not (slots[path] ~= nil or slots[clean(path)] ~= nil) then return path end
			end
			return nil
		end

		--- the faces of one sex: the slots whose material path names the sex, as the own menu of
		--- this addon takes them (own/sh_own.lua: slot:find("female" or "male"))
		local poolOf = {}
		local function pool(sex)
			if istable(poolOf[sex]) then return poolOf[sex] end
			local got, wanted = {}, sex == 2 and "female" or "male"
			local keys = {}
			for slot in pairs(slots) do
				if isstring(slot) then keys[#keys + 1] = slot end
			end
			table.sort(keys)
			local function take(slot)
				if not istable(slots[slot]) then return end
				for name, path in pairs(slots[slot]) do
					if isstring(name) and isstring(path) and path ~= "" and name ~= "Default" then
						got[name] = got[name] or path
					end
				end
			end
			for _, slot in ipairs(keys) do
				if clean(slot):find(wanted, 1, true) then take(slot) end
			end
			-- a sex nobody wrote a face for at all: the faces there are, whichever model they belong
			-- to - an empty choice is what this pass is here to take away
			if next(got) == nil then
				for _, slot in ipairs(keys) do take(slot) end
			end
			poolOf[sex] = got
			return got
		end

		for sex = 1, 2 do
			local list = istable(AP.PlayerModels[sex]) and AP.PlayerModels[sex] or {}
			for _, entry in pairs(list) do
				local written = istable(entry) and isstring(entry.mdl) and entry.mdl or nil
				local model = written and clean(written) or nil
				if model and model ~= "" then
					local faces, told = usable(model)
					if faces == 0 then
						local target = targetOf(model, told)
						if isstring(target) and target ~= "" then
							if not istable(AP.MultiFacemaps) then AP.MultiFacemaps = {} end
							multi = AP.MultiFacemaps
							if not istable(AP.FacemapsModels) then AP.FacemapsModels = {} end
							if not istable(AP.ModelFaceSlots) then AP.ModelFaceSlots = {} end
							for _, key in ipairs({ written, model }) do
								if put("shared", AP.FacemapsModels, { key }, target) then made = made + 1 end
								if put("shared", AP.ModelFaceSlots, { key, clean(target) }, true) then
									made = made + 1
								end
							end
							for name, path in pairs(pool(sex)) do
								if put("shared", slots, { target, name }, path) then made = made + 1 end
								if put("shared", multi, { model, name, clean(target) }, path) then
									made = made + 1
								end
							end
						end
					end
				end
			end
		end
	end

	-- 6. the keys the menus ask for in lower case: a copy beside the one the Lua wrote
	local function lowerKeys(kind, root, deep)
		if not istable(root) then return end
		local want = {}
		for key, value in pairs(root) do
			if isstring(key) then
				local lower = clean(key)
				if lower ~= key and root[lower] == nil then want[#want + 1] = { lower, value } end
			end
		end
		for _, one in ipairs(want) do
			if deep and istable(one[2]) then
				if not istable(root[one[1]]) then root[one[1]] = {} end
				for name, path in pairs(one[2]) do
					if put(kind, root, { one[1], name }, path) then made = made + 1 end
				end
			elseif put(kind, root, { one[1] }, one[2]) then
				made = made + 1
			end
		end
	end
	lowerKeys("lower", slots, true)
	lowerKeys("lower", AP.MultiFacemaps, false)
	lowerKeys("lower", AP.ModelFaceSlots, false)
	-- A model the menus ask for in lower case is told its slot in lower case as well: the value of
	-- FacemapsModels is the key of FacemapsSlots, and the editor of Z-City looks the one up with
	-- the other (FacemapsSlots[FacemapsModels[model]]) while the game hands the materials of a
	-- model out in lower case - so the two are given the same case wherever both are there.
	-- (FacemapsModels is not one of the tables above: its value is a key, not a face.)
	if istable(AP.FacemapsModels) then
		local want = {}
		for model, slot in pairs(AP.FacemapsModels) do
			if isstring(model) and isstring(slot) then
				local lower, value = clean(model), clean(slot)
				if AP.FacemapsModels[lower] == nil then
					if not (istable(AP.FacemapsSlots) and istable(AP.FacemapsSlots[value])) then value = slot end
					want[#want + 1] = { lower, value }
				end
			end
		end
		for _, one in ipairs(want) do
			if put("lower", AP.FacemapsModels, { one[1] }, one[2]) then made = made + 1 end
		end
	end
	return made
end

--- how many faces the tables hold and what this addon added to them
function ZCG.FaceCounts()
	local AP = istable(hg) and hg.Appearance
	local faces, multi, models, slots = 0, 0, {}, {}
	if istable(AP) then
		if istable(AP.FacemapsSlots) then
			for slot, list in pairs(AP.FacemapsSlots) do
				if isstring(slot) and istable(list) then
					slots[clean(slot)] = true
					for name, path in pairs(list) do
						if isstring(name) and isstring(path) then faces = faces + 1 end
					end
				end
			end
		end
		if istable(AP.MultiFacemaps) then
			for model, list in pairs(AP.MultiFacemaps) do
				if isstring(model) and istable(list) then
					models[clean(model)] = true
					for _, byslot in pairs(list) do
						if istable(byslot) then
							for slot, path in pairs(byslot) do
								if isstring(path) and path ~= "" then
									multi = multi + 1
									slots[clean(slot)] = true
								end
							end
						end
					end
				end
			end
		end
	end
	local count = 0
	for _ in pairs(models) do count = count + 1 end
	local slotCount = 0
	for _ in pairs(slots) do slotCount = slotCount + 1 end
	return faces, multi, count, slotCount
end

--- the lines for zcg_content
function ZCG.FaceReport(out)
	local faces, multi, models, slots = ZCG.FaceCounts()
	if faces == 0 and multi == 0 then return end
	local made = ZCG.FaceMade or {}
	local total = (made.multi or 0) + (made.slots or 0) + (made.models or 0) + (made.lower or 0)
		+ (made.alias or 0) + (made.shared or 0)
	out("  faces: " .. faces .. " in FacemapsSlots, " .. multi .. " in MultiFacemaps, " .. models
		.. " models with a face, " .. slots .. " face materials of a model")
	if total > 0 then
		out("  " .. total .. " of them this addon put where the other menu looks as well ("
			.. (made.multi or 0) .. " into MultiFacemaps, " .. (made.slots or 0) .. " into FacemapsSlots, "
			.. (made.models or 0) .. " models told their slot, " .. (made.lower or 0)
			.. " keys in the lower case the menus ask for, " .. (made.alias or 0)
			.. " mirrored into the material their model actually carries, " .. (made.shared or 0)
			.. " given to a model nobody wrote a face for): a face of the clothing Lua is listed"
			.. " by the menu of the Appearance Mod, and a multi-facemap by the plain menu of Z-City and by the"
			.. " LEGACY build; a model whose Lua named no face but \"Default\" is offered the faces of its sex,"
			.. " so that the choice of a face is never empty (zcg_faces names them, zcg_sync_faces 0 takes them back)")
	end
	if (ZCG.FaceClash or 0) > 0 then
		out("  " .. ZCG.FaceClash .. " face entries are there with another value and are left as they are")
	end
end

-- ---------------------------------------------------------------------------------------------
-- when it runs, and what it says
-- ---------------------------------------------------------------------------------------------
local told = -1

local function pass()
	local ok, made = pcall(ZCG.SyncFaces)
	if not ok then
		if told ~= -2 then
			told = -2
			ErrorNoHalt("[CS:GO Gloves] faces: " .. tostring(made) .. "\n")
		end
		return
	end
	if type(made) == "number" and made > 0 and made ~= told then
		ZCG.Print("faces: " .. made .. " face entries put into the table the other menu reads - the menus of Z-City"
			.. " and of the Appearance Mod list the same faces now (zcg_faces shows them, zcg_sync_faces 0 leaves"
			.. " the tables as the clothing Lua made them).")
	end
	if type(made) == "number" then told = made end
end
ZCG.FacePass = pass

hook.Add("InitPostEntity", "zcg_faces_sync", function()
	pass()
	for _, delay in ipairs({ 1, 5, 15, 70 }) do timer.Simple(delay, pass) end
	timer.Create("zcg_faces_sync", 120, 0, pass)
end)
if cvars and cvars.AddChangeCallback then
	cvars.AddChangeCallback("zcg_sync_faces", function() timer.Simple(0, pass) end, "zcg_faces")
end

concommand.Add("zcg_faces" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	pass()
	local faces, multi, models, slots = ZCG.FaceCounts()
	print("[CS:GO Gloves] faces in the tables: " .. faces .. " in FacemapsSlots, " .. multi .. " in MultiFacemaps, "
		.. models .. " models with a face, " .. slots .. " face materials of a model")
	local made = ZCG.FaceMade or {}
	print("[CS:GO Gloves] put there by this addon: " .. (made.multi or 0) .. " into MultiFacemaps, "
		.. (made.slots or 0) .. " into FacemapsSlots, " .. (made.models or 0) .. " models told their slot, "
		.. (made.lower or 0) .. " keys in lower case, " .. (made.alias or 0)
		.. " mirrored into the material their model carries, " .. (made.shared or 0)
		.. " given to a model nobody wrote a face for; left alone with another value: " .. (ZCG.FaceClash or 0))
	local lines = {}
	for _, one in ipairs(added) do
		lines[#lines + 1] = one[1] .. "  " .. tostring(one[6]) .. (one[5] and "/" or " = " .. tostring(one[4]))
	end
	table.sort(lines)
	print("[CS:GO Gloves] what this addon put into the tables of the game: " .. #lines .. " entries")
	for index = 1, math.min(#lines, 200) do print("  " .. lines[index]) end
	if #lines > 200 then print("  ... and " .. (#lines - 200) .. " more (zcg_sync_faces 0 takes every one back)") end
end, nil, "Put the faces of Z-City into the table the other menu reads as well, and say what was done")

--- the face the player wears, put straight onto the materials his model actually has - the way it
--- was done from the start, in the wear itself (own/sv_own.lua): the gamemode sets a face once, and
--- a model change, a bodygroup, a heal or a dress by the Appearance Mod alone can take it back;
--- this sets the sub-materials again, from both tables of faces - the one of the gamemode
--- (FacemapsSlots) and the one of this addon (ZCO.Catalog.Facemaps), plus every slot a model with
--- several of them is known for (MultiFacemaps) (2.24.0).
--- Returns how many slots were set; 0 when the player wears no face or the tables are not there.
function ZCG.ForceFace(ply)
	if not IsValid(ply) or not ply.GetMaterials then return 0 end
	local AP = istable(hg) and hg.Appearance or nil
	local own = istable(ZCO) and istable(ZCO.Catalog) and ZCO.Catalog or nil
	local slots = istable(AP) and istable(AP.FacemapsSlots) and AP.FacemapsSlots or nil
	local ownSlots = own and istable(own.Facemaps) and own.Facemaps or nil
	if not slots and not ownSlots then return 0 end
	local multi = (istable(AP) and istable(AP.MultiFacemaps) and AP.MultiFacemaps or nil)
		or (own and istable(own.MultiFacemaps) and own.MultiFacemaps or nil)
	local look = istable(ply.CurAppearance) and ply.CurAppearance
		or (istable(ply.CachedAppearance) and ply.CachedAppearance or nil)
	local face = istable(look) and isstring(look.AFacemap) and look.AFacemap or nil
	if not face or face == "" then return 0 end
	local mats = ply:GetMaterials() or {}
	--- the faces of one material of the player, from whichever table names them
	local function listOf(material)
		local key = clean(material)
		local list = (slots and (slots[material] or slots[key])) or nil
		if not istable(list) then list = (ownSlots and (ownSlots[material] or ownSlots[key])) or nil end
		return istable(list) and list or nil
	end
	local done = 0
	if face == "Default" then
		-- the face of the model itself: whatever a face put there is taken back
		for index = 1, #mats do
			if listOf(mats[index]) then
				ply:SetSubMaterial(index - 1, "")
				done = done + 1
			end
		end
		return done
	end
	for index = 1, #mats do
		local list = listOf(mats[index])
		local path = list and list[face] or nil
		if isstring(path) and path ~= "" then
			ply:SetSubMaterial(index - 1, path)
			done = done + 1
		end
	end
	-- a model with several face slots: the face is written into every slot it is known for
	local model = ply.GetModel and ply:GetModel() or nil
	local by_slot = istable(multi) and isstring(model) and istable(multi[model]) and multi[model][face] or nil
	if istable(by_slot) then
		for index = 1, #mats do
			local material = by_slot[mats[index]] or by_slot[clean(mats[index])]
			if isstring(material) and material ~= "" then
				ply:SetSubMaterial(index - 1, material)
				done = done + 1
			end
		end
	end
	return done
end

--- why a face does or does not go onto a player: the materials of the player against the tables
concommand.Add("zcg_face_debug" .. (CLIENT and "_cl" or ""), function(ply)
	if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
	local AP = istable(hg) and hg.Appearance or nil
	local who = CLIENT and { LocalPlayer() } or (player.GetAll and player.GetAll() or {})
	for _, one in ipairs(who) do
		if IsValid(one) then
			local model = one:GetModel() or ""
			local mats = one:GetMaterials() or {}
			local face = SERVER and istable(one.CurAppearance) and one.CurAppearance.AFacemap or nil
			print("[zcg faces] " .. tostring(one:Nick()) .. ": model " .. tostring(model)
				.. "; face chosen: " .. tostring(face) .. "; materials of the player: " .. #mats)
			for index = 1, #mats do
				local path = mats[index]
				local tbl = istable(AP) and istable(AP.FacemapsSlots) and (AP.FacemapsSlots[path] or AP.FacemapsSlots[clean(path)]) or nil
				local names, hit = 0, nil
				if istable(tbl) then
					for name, mat in pairs(tbl) do
						if isstring(mat) then names = names + 1 end
						if name == face then hit = mat end
					end
				end
				print("  [" .. (index - 1) .. "] " .. tostring(path) .. ": faces registered " .. names
					.. (tbl == nil and " (NO FACE SLOT UNDER THIS MATERIAL)" or "")
					.. (hit and ": the face of the player goes here -> " .. tostring(hit)
						or (face and ": no face of this name here" or "")))
			end
			if istable(AP) then
				local lower = clean(model)
				print("  FacemapsModels: " .. (istable(AP.FacemapsModels) and tostring(AP.FacemapsModels[lower] or AP.FacemapsModels[model]) or "no table")
					.. "; MultiFacemaps: " .. (istable(AP.MultiFacemaps) and (istable(AP.MultiFacemaps[lower]) and "yes" or "no model") or "no table")
					.. "; ModelFaceSlots: " .. (istable(AP.ModelFaceSlots) and (istable(AP.ModelFaceSlots[lower]) and "yes" or "no model") or "no table"))
			end
		end
	end
end, nil, "Say why a face does or does not go onto a player: the materials of the player against the tables of faces")

-- (a Lua file loaded again while the game runs)
if hg and istable(hg.Appearance) then pass() end
