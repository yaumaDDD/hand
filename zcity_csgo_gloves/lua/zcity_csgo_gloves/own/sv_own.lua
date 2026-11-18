-- Our own appearance system: the server half. It puts an appearance on a player, keeps it in
-- data/zco/ (one file per player, on the server - a client needs no file of its own to be dressed
-- the way he was dressed before), and answers the calls the rest of the server makes by name
-- (ApplyAppearance, hg.Appearance.ForceApplyAppearance) so that the gamemode of Z-City, its player
-- classes and its modes work with this addon alone.

ZCO = ZCO or {}

util.AddNetworkString("zco_set")        -- a client asks for an appearance of its own
util.AddNetworkString("zco_ask")        -- the server asks a client for the file it kept before
util.AddNetworkString("zco_answer")     -- ... and the client answers with it
util.AddNetworkString("zco_got")        -- the server hands a client its saved appearance (the menu)
util.AddNetworkString("zco_say")        -- a line for the chat of one player

-- --------------------------------------------------------------------------------------
-- putting an appearance on a player
-- --------------------------------------------------------------------------------------

--- the appearance on a player: the model, the color, the clothes in their submaterial slots, the
--- face, the bodygroups, the accessories (which the clients draw), and the name over his head.
--- noModelChange: leave the model the gamemode gave him (a mode that dresses him itself).
function ZCO.Apply(ply, appearance, noModelChange)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	appearance = appearance or ZCO.Default()
	ZCO.Install()

	local name, entry, sex = ZCO.ModelByName(appearance.AModel)
	local model = (type(entry) == "table" and entry.mdl) or (type(appearance.AModel) == "string" and appearance.AModel)
	if model and model ~= "" and model ~= ply:GetModel() and not noModelChange then
		ply:SetModel(model)
	end
	entry, sex = ZCO.ModelOf(ply)
	sex = sex or ZCO.MALE

	local color = appearance.AColor
	if type(color) ~= "table" or not color.r then color = Color(180, 180, 180) end
	local vector = Vector((color.r or 0) / 255, (color.g or 0) / 255, (color.b or 0) / 255)
	if ply.SetPlayerColor then ply:SetPlayerColor(vector) end
	if ply.SetNWVector then ply:SetNWVector("PlayerColor", vector) end

	-- the clothes: every slot of the model gets the material its name stands for
	ply:SetSubMaterial()
	local slots = ZCO.Slots(ply)
	local clothes = appearance.AClothes or {}
	local known = ZCO.Clothes(sex)
	for _, slot in ipairs(ZCO.SLOTS) do
		local index = slots[slot]
		if index then
			local worn = clothes[slot]
			local material = (type(worn) == "string" and worn ~= "" and (known[worn]
				or ZCO.Clothes(ZCO.MALE)[worn] or ZCO.Clothes(ZCO.FEMALE)[worn])) or known["normal"] or nil
			if material then ply:SetSubMaterial(index, material) end
			if ply.SetNWString then ply:SetNWString("Colthes" .. slot, type(worn) == "string" and worn or "normal") end
		end
	end

	-- the face: the material of the slot the model has is replaced by the one of the face
	if ply.SetNWString then ply:SetNWString("ZCOFacemap", tostring(appearance.AFacemap or "Default")) end
	local materials = ply:GetMaterials() or {}
	for index = 1, #materials do
		local by_name = (hg.Appearance and hg.Appearance.FacemapsSlots or {})[materials[index]]
			or (ZCO.Catalog.Facemaps or {})[materials[index]]
		if type(by_name) == "table" and by_name[appearance.AFacemap or "Default"] then
			ply:SetSubMaterial(index - 1, by_name[appearance.AFacemap or "Default"])
		end
	end
	-- a model with several face slots: the face is written into every slot it is known for
	local multi = (ZCO.Catalog.MultiFacemaps or {})[ply:GetModel()]
	if type(multi) == "table" then
		local by_slot = multi[appearance.AFacemap or "Default"]
		if type(by_slot) == "table" then
			for index = 1, #materials do
				local material = by_slot[materials[index]]
				if material and material ~= "" then ply:SetSubMaterial(index - 1, material) end
			end
		end
	end

	-- the bodygroups: the submodel whose name the catalog knows is the one that is set
	if ply.SetBodyGroups then ply:SetBodyGroups("00000000000000000000") end
	local groups = ply:GetBodyGroups() or {}
	local wanted = appearance.ABodygroups or {}
	local kept = {}
	for index = 1, #groups do
		local group = groups[index]
		local worn = group and group.name and wanted[group.name] or nil
		if worn and worn ~= "" then
			local entry_of = ZCO.Bodygroups(group.name, sex)[worn]
			local submodel = entry_of and entry_of.submodel or nil
			if submodel and group.submodels then
				for sub = 0, #group.submodels do
					if group.submodels[sub] == submodel then
						ply:SetBodygroup(index - 1, sub)
						kept[group.name] = worn
						break
					end
				end
			end
		end
	end
	if ply.SetNetVar then ply:SetNetVar("ZCOBodygroups", kept) end

	-- the accessories: the clients draw them (own/cl_own_render.lua)
	if ply.SetNetVar then ply:SetNetVar("Accessories", appearance.AAttachments or {}) end

	if ply.SetNWString then
		local name_of = appearance.AName
		if type(name_of) == "string" and name_of ~= "" then ply:SetNWString("PlayerName", name_of) end
	end

	ply.zcoAppearance = ZCO.Copy(appearance)
	ply.zcoCached = ZCO.Copy(appearance)
	-- the field Z-City itself reads: its modes (homicide names a traitor by the name over his
	-- head), its ragdolls (fake/sv_tier_0.lua copies it onto the body) and its admin tools
	ply.CurAppearance = ZCO.Copy(appearance)
	hook.Run("ZCOApplied", ply, ply.zcoAppearance)
	return true
end

--- an appearance only with what the player may wear, on the player
function ZCO.Wear(ply, appearance, noModelChange)
	if not IsValid(ply) then return false end
	local clean = ZCO.Clean(appearance)
	local ok, why = ZCO.Validate(clean)
	if not ok then
		clean = ZCO.Default(ZCO.IsFemale(ply) and ZCO.FEMALE or ZCO.MALE)
	end
	return ZCO.Apply(ply, clean, noModelChange), why
end

-- --------------------------------------------------------------------------------------
-- the files: data/zco/<steamid64>.txt, one per player
-- --------------------------------------------------------------------------------------

function ZCO.Save(ply, appearance)
	local path = ZCO.FileOf(ply)
	if not path then return false end
	file.CreateDir(ZCO.Directory:sub(1, -2))
	file.Write(path, ZCO.Serialize(appearance or ply.zcoAppearance or ZCO.Default()))
	return true
end

function ZCO.Load(ply)
	local path = ZCO.FileOf(ply)
	if not path or not file.Exists(path, "DATA") then return nil end
	local got = ZCO.Deserialize(file.Read(path, "DATA"))
	if not got then return nil end
	return ZCO.Clean(got)
end

-- --------------------------------------------------------------------------------------
-- what the rest of the server calls
-- --------------------------------------------------------------------------------------

local waiting = {}

--- ApplyAppearance(ply, appearance, random, responseIsValid, useCached) - the call the gamemode
--- of Z-City makes when a player spawns. Nothing on the server: the appearance of the file it
--- keeps; no file yet: the client is asked for the one it kept before (his own data/zco/, and the
--- data/zcity/appearances/ of the Appearance Mod), and three seconds later a random one is put on.
function ZCO.ApplyAppearance(client, appearance, random, _responseIsValid, useCached)
	if not IsValid(client) or not client:IsPlayer() then return end
	if random or (client.IsBot and client:IsBot()) or (client.IsRagdoll and client:IsRagdoll()) then
		ZCO.Wear(client, ZCO.Random(client.zcoSex and ZCO.FEMALE or nil))
		return
	end
	if type(appearance) == "table" and next(appearance) ~= nil then
		ZCO.Wear(client, appearance)
		ZCO.Save(client, client.zcoAppearance)
		return
	end
	local saved = ZCO.Load(client)
	if saved then
		ZCO.Wear(client, saved)
		return
	end
	if useCached and client.zcoCached then
		ZCO.Wear(client, client.zcoCached)
		net.Start("zco_ask")
		net.Send(client)
		return
	end
	waiting[client] = CurTime() + 3
	net.Start("zco_ask")
	net.Send(client)
	timer.Create("zco_wait_" .. client:EntIndex(), 3.2, 1, function()
		if waiting[client] and IsValid(client) then
			waiting[client] = nil
			ZCO.Wear(client, ZCO.Random())
		end
	end)
end

if type(ApplyAppearance) ~= "function" then
	ApplyAppearance = function(client, appearance, random, responseIsValid, useCached)
		return ZCO.ApplyAppearance(client, appearance, random, responseIsValid, useCached)
	end
end

net.Receive("zco_answer", function(_length, client)
	local appearance = net.ReadTable()
	if not IsValid(client) then return end
	if type(appearance) ~= "table" or next(appearance) == nil then
		if waiting[client] then
			waiting[client] = nil
			ZCO.Wear(client, ZCO.Random())
		end
		return
	end
	waiting[client] = nil
	local ok = ZCO.Validate(ZCO.Clean(appearance))
	if not ok then
		ZCO.Wear(client, ZCO.Random())
		return
	end
	ZCO.Wear(client, appearance)
	ZCO.Save(client, client.zcoAppearance)
	if client.zcoAppearance then
		net.Start("zco_got")
		net.WriteTable(client.zcoAppearance)
		net.Send(client)
	end
end)

net.Receive("zco_set", function(_length, client)
	local appearance = net.ReadTable()
	if not IsValid(client) or not client:IsPlayer() then return end
	if not ZCO.Access(client) then
		net.Start("zco_say")
		net.WriteString("Внешность на этом сервере выдаёт администрация.")
		net.Send(client)
		return
	end
	local clean = ZCO.Clean(appearance)
	local ok, why = ZCO.Validate(clean)
	if not ok then
		net.Start("zco_say")
		net.WriteString("Так одеться нельзя: " .. tostring(why or "не из списка") .. ".")
		net.Send(client)
		return
	end
	ZCO.Apply(client, clean)
	ZCO.Save(client, client.zcoAppearance)
	hook.Run("ZCOChanged", client, client.zcoAppearance)
end)

--- the saved appearance of a player, to the client that asks for it (its menu shows what is kept)
function ZCO.SendSaved(ply)
	if not IsValid(ply) then return end
	local saved = ZCO.Load(ply) or (ply.zcoAppearance and ZCO.Copy(ply.zcoAppearance)) or ZCO.Default()
	net.Start("zco_got")
	net.WriteTable(saved)
	net.Send(ply)
end

-- --------------------------------------------------------------------------------------
-- the game: whoever spawns is dressed, whoever leaves is written down
-- --------------------------------------------------------------------------------------

hook.Add("PlayerInitialSpawn", "zco_spawn", function(ply)
	ZCO.Install()
	timer.Simple(0.5, function()
		if IsValid(ply) then ZCO.SendSaved(ply) end
	end)
end)

hook.Add("PlayerSpawn", "zco_spawn", function(ply)
	-- the gamemode of Z-City calls ApplyAppearance itself; where nothing calls it, we do
	timer.Simple(0, function()
		if not IsValid(ply) then return end
		if ply.zcoAppearance then
			ZCO.Apply(ply, ply.zcoAppearance)
		else
			ZCO.ApplyAppearance(ply, nil, nil, nil, true)
		end
	end)
end)

hook.Add("PlayerLoadout", "zco_spawn", function(ply)
	if IsValid(ply) and ply.zcoAppearance then
		timer.Simple(0, function()
			if IsValid(ply) then ZCO.Apply(ply, ply.zcoAppearance, true) end
		end)
	end
end)

hook.Add("PlayerDisconnected", "zco_save", function(ply)
	if IsValid(ply) and ply.zcoAppearance then ZCO.Save(ply, ply.zcoAppearance) end
	waiting[ply] = nil
end)

hook.Add("ShutDown", "zco_save", function()
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply.zcoAppearance then ZCO.Save(ply, ply.zcoAppearance) end
	end
end)

-- the point shop of Z-City: the items of the bodygroups are created once it is there, so that
-- nothing that used to be bought is missing (with our own rails everything is worn for free when
-- zco_access_for_all is 1)
hook.Add("ZPointshopLoaded", "zco_pointshop", function()
	ZCO.Install()
	local shop = hg.PointShop
	if type(shop) ~= "table" or type(shop.CreateItem) ~= "function" then return end
	for _group, by_sex in pairs(ZCO.Catalog.Bodygroups or {}) do
		for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
			for name, entry in pairs(by_sex[sex] or {}) do
				local id = entry.id or ("Standard_BodyGroups_" .. name)
				if not shop.Items[id] then
					shop:CreateItem(id, name, "models/zcity/gloves/degloves.mdl", 0, 0, Vector(0, 0, 0), 0,
						entry.pointshop and true or false, {})
				end
			end
		end
	end
end)

-- --------------------------------------------------------------------------------------
-- the console of the server
-- --------------------------------------------------------------------------------------

local function say(ply, text)
	if IsValid(ply) and ply:IsPlayer() then
		ply:PrintMessage(3, text)
	else
		print(text)
	end
end

concommand.Add("zco_status", function(ply)
	ZCO.Install()
	local got = ZCO.Counts()
	say(ply, ("%s %s: моделей %d, одежды %d, лиц %d, бодигрупп %d, аксессуаров %d, имён %d; свои таблицы: %s; доступ: %s")
		:format(ZCO.Name, ZCO.Version, got.models, got.clothes, got.faces, got.bodygroups, got.accessories, got.names,
			ZCO.MadeTables and "созданы аддоном" or "мод внешности на месте",
			ZCO.AccessForAll:GetBool() and "всё всем" or "админам и списку zco_access_steam"))
	if IsValid(ply) and ply:IsPlayer() then
		local files = 0
		for _name in ipairs(file.Find(ZCO.Directory .. "*", "DATA")) do files = files + 1 end
		say(ply, ("Сохранено игроков: %d (data/%s). Твоя внешность: %s"):format(files, ZCO.Directory,
			ply.zcoAppearance and ply.zcoAppearance.AModel or "ещё не применена"))
	end
end, nil, "What this addon has of the appearance and who may wear it")

concommand.Add("zco_reset", function(ply, _cmd, args)
	if IsValid(ply) and ply:IsPlayer() and not ZCO.Access(ply) then
		say(ply, "Только администрация.")
		return
	end
	local who = nil
	if args[1] and args[1] ~= "" then
		local id = tonumber(args[1])
		for _, one in ipairs(player.GetAll()) do
			if (id and one:EntIndex() == id) or one:Nick():lower():find(args[1]:lower(), 1, true) then
				who = one
				break
			end
		end
	else
		who = IsValid(ply) and ply:IsPlayer() and ply or nil
	end
	if not IsValid(who) then
		say(ply, "Кого сбросить: zco_reset <имя или номер игрока>.")
		return
	end
	local path = ZCO.FileOf(who)
	if path and file.Exists(path, "DATA") then file.Delete(path) end
	who.zcoAppearance, who.zcoCached = nil, nil
	ZCO.Wear(who, ZCO.Random())
	say(ply, ("Внешность %s сброшена на случайную."):format(who:Nick()))
end, nil, "Forget the saved appearance of a player and dress him at random")

concommand.Add("zco_dress", function(ply, _cmd, args)
	if IsValid(ply) and ply:IsPlayer() and not ZCO.Access(ply) then
		say(ply, "Только администрация.")
		return
	end
	local who = nil
	for _, one in ipairs(player.GetAll()) do
		if args[1] and (one:Nick():lower():find(args[1]:lower(), 1, true)
			or tostring(one:EntIndex()) == args[1]) then
			who = one
			break
		end
	end
	if not IsValid(who) then
		say(ply, "Кого одеть: zco_dress <игрок> [модель] [одежда].")
		return
	end
	local appearance = ZCO.Copy(who.zcoAppearance or ZCO.Default())
	if args[2] and args[2] ~= "" then appearance.AModel = args[2] end
	if args[3] and args[3] ~= "" then
		appearance.AClothes = { main = args[3], pants = args[3], boots = args[3] }
	end
	ZCO.Wear(who, appearance)
	ZCO.Save(who, who.zcoAppearance)
	say(ply, ("%s одет: %s."):format(who:Nick(), who.zcoAppearance and who.zcoAppearance.AModel or "?"))
end, nil, "Dress a player: zco_dress <player> [model] [clothes]")

concommand.Add("zco_save_all", function(ply)
	if IsValid(ply) and ply:IsPlayer() and not (ZCO.Access(ply) or ply:IsSuperAdmin()) then
		say(ply, "Только администрация.")
		return
	end
	local saved = 0
	for _, one in ipairs(player.GetAll()) do
		if IsValid(one) and one.zcoAppearance and ZCO.Save(one, one.zcoAppearance) then saved = saved + 1 end
	end
	say(ply, ("Сохранено игроков: %d."):format(saved))
end, nil, "Write the appearance of every player into its file")

concommand.Add("zco_list", function(ply, _cmd, args)
	ZCO.Install()
	local what = (args[1] or "clothes"):lower()
	local lines = {}
	if what == "models" then
		for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
			for name, entry in pairs(ZCO.Models(sex)) do
				lines[#lines + 1] = ("[%s] %s = %s"):format(sex == ZCO.FEMALE and "ж" or "м", name, tostring(entry.mdl))
			end
		end
	elseif what == "accessories" or what == "attach" then
		for name, data in pairs(ZCO.Catalog.Accessories or {}) do
			lines[#lines + 1] = ("%s (%s) = %s"):format(name, tostring(data.placement or "-"), tostring(data.model))
		end
	elseif what == "faces" or what == "facemaps" then
		for slot, by_name in pairs(ZCO.Catalog.Facemaps or {}) do
			for name in pairs(by_name) do lines[#lines + 1] = ("%s = %s"):format(name, slot) end
		end
	elseif what == "bodygroups" or what == "groups" then
		for group, by_sex in pairs(ZCO.Catalog.Bodygroups or {}) do
			for sex, by_name in pairs(by_sex) do
				for name, entry in pairs(by_name) do
					lines[#lines + 1] = ("%s [%s] %s = %s"):format(group, sex == ZCO.FEMALE and "ж" or "м", name,
						tostring(entry.submodel))
				end
			end
		end
	else
		for _, sex in ipairs({ ZCO.MALE, ZCO.FEMALE }) do
			for name in pairs(ZCO.Clothes(sex)) do
				lines[#lines + 1] = ("[%s] %s = %s"):format(sex == ZCO.FEMALE and "ж" or "м", name,
					tostring(ZCO.Clothes(sex)[name]))
			end
		end
	end
	table.sort(lines)
	say(ply, ("Каталог, %s: %d"):format(what, #lines))
	for index = 1, math.min(#lines, 200) do say(ply, "  " .. lines[index]) end
	if #lines > 200 then say(ply, ("  ... и ещё %d"):format(#lines - 200)) end
end, nil, "What is in the catalog: zco_list [clothes|models|accessories|faces|bodygroups]")

-- --------------------------------------------------------------------------------------
-- what Z-City calls by name: with this addon alone the gamemode, its modes and its player
-- classes find the functions they were written against
-- --------------------------------------------------------------------------------------

function ZCO.Compat()
	ZCO.Install()
	local appearance = hg.Appearance
	if type(appearance.ForceApplyAppearance) ~= "function" then
		appearance.ForceApplyAppearance = function(ply, tbl, noModelChange)
			if not IsValid(ply) then return end
			return ZCO.Apply(ply, ZCO.Clean(tbl or ZCO.Default()), noModelChange)
		end
	end
	if type(appearance.ApplyAppearance) ~= "function" then
		appearance.ApplyAppearance = function(client, tbl, random, responseIsValid, useCached)
			return ZCO.ApplyAppearance(client, tbl, random, responseIsValid, useCached)
		end
	end
	if type(ApplyAppearanceRagdoll) ~= "function" then
		-- a ragdoll wears what the player wore: the name over it, his clothes, his accessories
		ApplyAppearanceRagdoll = function(ent, ply)
			if not IsValid(ent) or not IsValid(ply) then return end
			local appearance_of = ply.zcoAppearance
			if not appearance_of then return end
			if ent.SetNWString then
				ent:SetNWString("PlayerName", ply:GetNWString("PlayerName", appearance_of.AName or ""))
				for _, slot in ipairs(ZCO.SLOTS) do
					ent:SetNWString("Colthes" .. slot, ply:GetNWString("Colthes" .. slot, "normal"))
				end
			end
			if ent.SetNetVar and ply.GetNetVar then
				ent:SetNetVar("Accessories", ply:GetNetVar("Accessories", ""))
			end
		end
	end
	if type(hg.Appearance.CreateAppearanceFile) ~= "function" then
		hg.Appearance.CreateAppearanceFile = function(name, tbl)
			file.CreateDir(ZCO.Directory:sub(1, -2))
			file.Write(ZCO.Directory .. tostring(name) .. ZCO.Extension, ZCO.Serialize(tbl or ZCO.Default()))
		end
	end
	if type(hg.Appearance.LoadAppearanceFile) ~= "function" then
		hg.Appearance.LoadAppearanceFile = function(name)
			local path = ZCO.Directory .. tostring(name) .. ZCO.Extension
			if not file.Exists(path, "DATA") then return false end
			local got = ZCO.Deserialize(file.Read(path, "DATA"))
			if not got then return false, "the file is damaged (data/" .. path .. ")" end
			return got
		end
	end
	if type(hg.Appearance.GetAppearanceList) ~= "function" then
		hg.Appearance.GetAppearanceList = function()
			local names = {}
			local files = file.Find(ZCO.Directory .. "*", "DATA")
			if type(files) == "table" then
				for index = 1, #files do
					local name = tostring(files[index])
					if name:sub(-#ZCO.Extension) == ZCO.Extension then
						names[#names + 1] = name:sub(1, -#ZCO.Extension - 1)
					end
				end
			end
			return names
		end
	end
	return true
end

-- the appearance tables of the game are ready as soon as the addon is: the gamemode may call
-- ApplyAppearance in the very first second of the map
ZCO.Compat()
hook.Add("InitPostEntity", "zco_compat", function() ZCO.Compat() end)
