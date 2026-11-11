-- Z-City CS:GO gloves - "is the content there?" (console command zcg_content)
--
-- The appearance system of Z-City only keeps names: the models of the player models and of the
-- accessories, the materials of the clothes and of the faces. Clothing packs add such names from
-- Lua; the files themselves (materials/..., models/...) have to be on the disk as well. A name
-- without its file shows as an ERROR model or as purple-black squares.
--
-- zcg_content walks the tables as they are right now - whatever addons filled them - and lists
-- the names whose files this computer does not have:
--   * typed into the console of the game: the files of this player;
--   * typed into the console of a dedicated server (or zcg_content_server by a super admin):
--     the files of the server. It needs the models; the materials only matter to players.

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

-- The list of what is not there, sorted. askMaterials: also ask the material system of the game
-- about a material without a file (that loads it, so only on request and only on a client).
function ZCG.ContentMissing(askMaterials)
	local models, materials = ZCG.ContentNeeds()
	local missing, modelCount, materialCount = {}, 0, 0

	for path, who in pairs(models) do
		modelCount = modelCount + 1
		if not has(path) then missing[#missing + 1] = path .. "  <-  " .. who end
	end
	for name, who in pairs(materials) do
		materialCount = materialCount + 1
		local found = has("materials/" .. name .. ".vmt")
		if not found and askMaterials and CLIENT then
			local mat = Material(name)
			found = mat ~= nil and not mat:IsError()
		end
		if not found then missing[#missing + 1] = "materials/" .. name .. ".vmt  <-  " .. who end
	end

	table.sort(missing)
	return missing, modelCount, materialCount
end

-- prints the report line by line through out(text), returns the number of missing files
function ZCG.ContentReport(out)
	local missing, models, materials = ZCG.ContentMissing(true)
	out("[CS:GO Gloves] content check on the " .. (SERVER and "server" or "client") .. ": the appearance tables name "
		.. models .. " models and " .. materials .. " materials, " .. #missing .. " of them are missing")

	local shown = math.min(#missing, 200)
	for i = 1, shown do out("  " .. missing[i]) end
	if #missing > shown then out("  ... and " .. (#missing - shown) .. " more") end

	if #missing > 0 then
		local ok = pcall(file.Write, "zcg_content.txt", table.concat(missing, "\n") .. "\n")
		if ok then out("  the whole list is in garrysmod/data/zcg_content.txt") end
		out("  put the files into the materials and models folders of an addon (this one will do) and restart the game")
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
end
