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
	local worn = ply:GetModel()
	if not noModelChange then
		if model and model ~= "" and model ~= worn then
			-- A model the server itself has not is set all the same: the players may have it from
			-- the Workshop or from FastDL, which the server cannot tell - and refusing it would
			-- leave the player on a body the appearance was not made for. Both consoles are told,
			-- once per model, so that the owner knows what to put on the server.
			if not ZCO.ModelReady(model) then ZCO.ModelGone(model, ply) end
			ply:SetModel(model)
		end
		-- A player who came with no model at all is invisible, and there is nothing on him for
		-- the clothes, the face, the accessories or the gloves to go onto: he gets a model of the
		-- catalog that IS on this server (nothing is forced on a mode that dresses him itself).
		worn = ply:GetModel()
		if not isstring(worn) or worn == "" then
			local _any, anyEntry = ZCO.AnyModel()
			if anyEntry then
				ply:SetModel(anyEntry.mdl)
				ZCGloves.Print("a player came with no model at all (" .. (ply.Nick and ply:Nick() or "?") .. "): he is given "
					.. anyEntry.mdl .. ", the first model of the catalog that is on the server - there is nothing to "
					.. "put an appearance on without one")
			else
				ZCO.ModelGone("", ply, true)
			end
		end
	elseif not ZCO.ModelReady(worn) then
		ZCO.ModelGone(worn, ply)
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
	-- the field the Appearance Mod itself reads before it does anything else (its ApplyAppearance
	-- takes Client.CachedAppearance first, and its own spawn path asks for a random look when that
	-- field is empty): what this addon put on the player is what the mod keeps for him, so his own
	-- path does not dress him at random over it (2.24.0)
	ply.CachedAppearance = ZCO.Copy(appearance)
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
-- a saved look stays on the player
-- --------------------------------------------------------------------------------------
-- The modes of Z-City (Event, Superfighters, Deathmatch and the like) dress a player by asking for
-- a RANDOM appearance: ApplyAppearance(ply, nil, true). The Appearance Mod does not take a player's
-- look away on that call - its fix addon (sh_zcity_appearance_fix.lua, v5) wraps ApplyAppearance
-- and, for a player who is not a bot and whose saved look passes the validator, applies the saved
-- one instead (zcity_appfix_keep_appearance, 1 by default). Saves work the same way here: the look
-- a player chose and the server kept is his, and a mode that asks for a random one does not dress
-- him anew every spawn. Only a player who has nothing saved - and a bot, who never has - is dressed
-- at random, and a player who asks for a random look himself (zco_random 1 in his own console)
-- gets one: the server reads that from his userinfo.

ZCO.Keep = CreateConVar("zco_keep_appearance", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"1: a player who has a saved look keeps it when a gamemode asks for a random one - as the fix of "
	.. "the Appearance Mod does (zcity_appfix_keep_appearance); 0: every such call dresses him at "
	.. "random, as before 2.20.1", 0, 1)

--- is this a look of the catalog? (a damaged file, an empty one, a look of a mod this server has
--- not - none of them is a look a player can be kept in)
local function aLook(got)
	if type(got) ~= "table" or next(got) == nil then return nil end
	local clean = ZCO.Clean(got)
	local ok = ZCO.Validate(clean)
	if not ok then return nil end
	return clean
end

--- the look a player saved, the way the fix of the Appearance Mod reads it (CachedAppearance,
--- CurAppearance): what the server keeps for him in data/zco/, then the look he sent before, then
--- the one he wears right now - the first of them that is a look of the catalog
function ZCO.SavedOf(client)
	if not IsValid(client) then return nil end
	return aLook(ZCO.Load(client)) or aLook(client.zcoCached) or aLook(client.zcoAppearance)
end

--- does this player ask for a random look himself? (zco_random is userinfo, so the server sees it)
local function wantsRandom(client)
	if not client.GetInfoNum then return false end
	return client:GetInfoNum("zco_random", 0) ~= 0
end

--- the face the player wears, put back onto the materials his model actually has - a moment later,
--- because the materials of a model that was just changed are not the ones of this very tick
--- (ZCG.ForceFace, sh_faces.lua: both tables of faces, and every slot a model is known for) (2.24.0)
local function faceAgain(client)
	if not (ZCGloves and ZCGloves.ForceFace) then return end
	for _, delay in ipairs({ 0.5, 2 }) do
		timer.Simple(delay, function()
			if IsValid(client) then ZCGloves.ForceFace(client) end
		end)
	end
end

--- A player whose client keeps no look at all is dressed once - and the look is kept: it is written
--- into his file and sent to his client, which writes it into the file of the Appearance Mod as
--- well, so the next spawn of his reads it back instead of making another random look. That is how
--- the save of the Appearance Mod works, and it is what "no random outfit every time" means here.
function ZCO.DressOnce(client)
	if not IsValid(client) or not client:IsPlayer() then return false end
	if (client.IsBot and client:IsBot()) or wantsRandom(client) then return false end
	if client.zcoAppearance or ZCO.SavedOf(client) then return false end
	ZCO.Wear(client, ZCO.Random(client.zcoSex and ZCO.FEMALE or nil))
	ZCO.Save(client, client.zcoAppearance)
	ZCO.SendSaved(client)
	return true
end
local dressOnce = ZCO.DressOnce

-- --------------------------------------------------------------------------------------
-- what the rest of the server calls
-- --------------------------------------------------------------------------------------

local waiting = {}

--- ApplyAppearance(ply, appearance, random, responseIsValid, useCached) - the call the gamemode
--- of Z-City makes when a player spawns. Nothing on the server: the appearance of the file it
--- keeps; no file yet: the client is asked for the one it kept before (his own data/zco/, and the
--- data/zcity/appearances/ of the Appearance Mod) - and what the client sends is put on him and
--- kept from then on. A look is made on the server only when the client keeps nothing at all, and
--- that look is kept too: the same player is never dressed at random on every spawn (2.24.0).
--- random = true is what the modes ask for: a player who has a saved look keeps it (zco_keep_appearance).
function ZCO.ApplyAppearance(client, appearance, random, _responseIsValid, useCached)
	if not IsValid(client) or not client:IsPlayer() then return end
	local bot = (client.IsBot and client:IsBot()) or (client.IsRagdoll and client:IsRagdoll()) or false
	local sex = client.zcoSex and ZCO.FEMALE or nil
	if random then
		if not bot and ZCO.Keep:GetBool() and not wantsRandom(client) then
			local saved = ZCO.SavedOf(client)
			if saved then
				ZCO.Wear(client, saved)
				return
			end
			-- Nothing of his own on the server: his client is asked for the file it keeps, the way
			-- the Appearance Mod asks (its Get_Appearance), and the answer is worn when it comes.
			-- Until then the player stays as the gamemode dressed him - no random look of our own.
			if not waiting[client] then
				waiting[client] = CurTime() + 3
				net.Start("zco_ask")
				net.Send(client)
				timer.Create("zco_wait_" .. client:EntIndex(), 3.2, 1, function()
					if waiting[client] then
						waiting[client] = nil
						dressOnce(client)
					end
				end)
			end
			return
		end
		ZCO.Wear(client, ZCO.Random(sex))
		return
	end
	if bot then
		ZCO.Wear(client, ZCO.Random(sex))
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
			dressOnce(client)
		end
	end)
end

if type(ApplyAppearance) ~= "function" then
	ApplyAppearance = function(client, appearance, random, responseIsValid, useCached)
		return ZCO.ApplyAppearance(client, appearance, random, responseIsValid, useCached)
	end
	ZCO.OwnApply = ApplyAppearance
end

-- --------------------------------------------------------------------------------------
-- the same where the Appearance Mod is installed
-- --------------------------------------------------------------------------------------
-- The mod keeps a player's saved look on such a call by wrapping ApplyAppearance itself
-- (sh_zcity_appearance_fix.lua of v5, zcity_appfix_keep_appearance). A pack that carries that fix
-- does not include it where this addon is: sh_register.lua makes hg.AppearanceFix, and that is what
-- the pack looks into before the include - so without a wrapper here saves would stop working the
-- very moment the addon is installed. Wrapped is the one function the fix of the mod wraps itself,
-- and only while nobody wrapped it before; the mod's own tables, menus and files are not touched.

--- the look the mod keeps for a player, read the way the fix of the mod reads it
local function theirSaved(client)
	local AP = hg and hg.Appearance
	if not istable(AP) then return nil end
	local saved = client.CachedAppearance or client.CurAppearance
	if not istable(saved) then return nil end
	if isfunction(AP.AppearanceValidater) and not AP.AppearanceValidater(saved) then return nil end
	local copy = table.Copy(saved)
	if isfunction(AP.CheckAttachments) then copy = AP.CheckAttachments(client, copy) end
	return copy
end

--- is this the same look as that one? (what a player sees, not the tables themselves)
local function sameLook(one, two)
	if not istable(one) or not istable(two) then return false end
	if one.AModel ~= two.AModel or one.AName ~= two.AName or one.AFacemap ~= two.AFacemap then
		return false
	end
	local function clothes(of)
		local names = {}
		for slot, worn in pairs(istable(of.AClothes) and of.AClothes or {}) do
			names[#names + 1] = tostring(slot) .. "=" .. tostring(worn)
		end
		table.sort(names)
		return table.concat(names, ",")
	end
	return clothes(one) == clothes(two)
end

--- put that wrapper in place (a pack may load later than we do, so it is tried more than once)
function ZCO.KeepWrap()
	if not (ZCO.Keep and ZCO.Keep:GetBool()) then return end
	local orig = ApplyAppearance
	if not isfunction(orig) or orig == ZCO.Keeping or orig == ZCO.OwnApply then return end
	local AP = hg and hg.Appearance
	if not istable(AP) or not isfunction(AP.ForceApplyAppearance) then return end

	local function wrapped(client, appearance, random, ...)
		local mine = IsValid(client) and client:IsPlayer() and ZCO.Keep:GetBool()
			and not (client.IsBot and client:IsBot()) and not wantsRandom(client)
		if random and mine then
			-- What this addon keeps for the player is his look, and the cache of the mod is read
			-- only where there is none of it: at a spawn the mod fills that cache with a NEW random
			-- look whenever the file of the client is empty, and taking the cache first is what
			-- dressed the player at random every time (2.24.0). A look taken from the cache is kept
			-- as his own from then on, so it is not another random one at the next spawn.
			local saved = ZCO.SavedOf(client) or theirSaved(client)
			if saved then
				AP.ForceApplyAppearance(client, saved)
				faceAgain(client)
				if not sameLook(saved, ZCO.Load(client)) then
					ZCO.Save(client, saved)
					ZCO.SendSaved(client)
				end
				return
			end
		end
		local got = orig(client, appearance, random, ...)
		if mine then faceAgain(client) end
		-- Whatever the mod itself put on the player - its editor after Apply, its own file, a mode
		-- of the gamemode - is kept as the look of this addon: the next spawn does not take it away
		-- and the client writes it into the file the mod reads (2.24.0).
		if mine then
			local now = theirSaved(client)
			if now and not sameLook(now, ZCO.Load(client)) then
				ZCO.Save(client, now)
				ZCO.SendSaved(client)
			end
		end
		return got
	end

	ZCO.Keeping = wrapped
	ApplyAppearance = wrapped
	if AP.ApplyAppearance == orig then AP.ApplyAppearance = wrapped end
end

hook.Add("InitPostEntity", "zco_keep", function()
	timer.Simple(1, ZCO.KeepWrap)
	timer.Simple(5, ZCO.KeepWrap)     -- a pack that puts the mod in place later
end)
hook.Add("PostGamemodeLoaded", "zco_keep", function()
	timer.Simple(1, ZCO.KeepWrap)
end)

net.Receive("zco_answer", function(_length, client)
	local appearance = net.ReadTable()
	if not IsValid(client) then return end
	waiting[client] = nil
	-- The client keeps nothing: a look is made for him once and kept from then on (ZCO.DressOnce),
	-- so that he is not dressed at random on every spawn. A look this server cannot wear is passed
	-- over: the player stays exactly as the gamemode dressed him (2.24.0).
	if type(appearance) ~= "table" or next(appearance) == nil then
		dressOnce(client)
		return
	end
	local clean = ZCO.Clean(appearance)
	if not ZCO.Validate(clean) then return end
	client.CachedAppearance = clean -- the spawn path of the gamemode reuses it from now on
	ZCO.Wear(client, clean)
	ZCO.Save(client, client.zcoAppearance)
	faceAgain(client)
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

-- The gamemode puts a face on the player once, at the wear; a model change, a bodygroup or a heal
-- of Z-City can take it back. After every spawn the face the player wears is put on him again -
-- on the materials his model actually has (ZCG.ForceFace, sh_faces.lua) (2.24.0).
hook.Add("PlayerSpawn", "zco_face", function(ply)
	faceAgain(ply)
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
	-- what the addon found in its own folder and no Lua names (own/sh_scan.lua)
	if got.foundModels > 0 or got.foundClothes > 0 then
		say(ply, ("Без Lua найдено в папке аддона: моделей %d, материалов %d — они в меню (zco_menu), в категории")
			:format(got.foundModels, got.foundClothes))
		say(ply, "«Без Lua» и в своих категориях с пометкой; весь список — zco_scan и zco_scan_list.")
	end
	if IsValid(ply) and ply:IsPlayer() then
		local files = 0
		for _name in ipairs(file.Find(ZCO.Directory .. "*", "DATA")) do files = files + 1 end
		say(ply, ("Сохранено игроков: %d (data/%s). Твоя внешность: %s"):format(files, ZCO.Directory,
			ply.zcoAppearance and ply.zcoAppearance.AModel or "ещё не применена"))
		-- what a mode that asks for a random look does to his saved one
		say(ply, ("Сохранённая внешность: %s; твоя: %s%s"):format(
			ZCO.Keep:GetBool() and "остаётся на игроке, когда режим просит случайную (zco_keep_appearance 1)"
				or "не держится: каждый такой вызов одевает игрока заново (zco_keep_appearance 0)",
			ZCO.SavedOf(ply) and "есть" or "ещё нет",
			ZCO.Keeping and "; вызов Appearance Mod обёрнут аддоном" or ""))
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
