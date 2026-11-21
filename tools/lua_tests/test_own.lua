-- The own appearance system (lua/zcity_csgo_gloves/own/): the catalog of everything the addon has,
-- the server that dresses a player and keeps his look, the client that draws what he wears and
-- opens a menu of its own. Run twice: with no Appearance Mod at all (the addon has to be enough),
-- and with the one of Z-City in place (nothing of it may be broken).
-- Returns function(testdir, luaroot) -> number of checks, list of failures.

return function(testdir, luaroot)
	local checks, failures = 0, {}
	local function check(cond, what)
		checks = checks + 1
		if not cond then failures[#failures + 1] = what end
	end
	local function eq(got, want, what)
		check(got == want, what .. ": got " .. tostring(got) .. ", expected " .. tostring(want))
	end

	-- the glove content of the addon, as in test_server.lua
	local function content(M)
		local models = {
			"v_glove_bloodhound", "v_glove_bloodhound_fingerless_brokenfang", "v_glove_handwrap_leathery",
			"v_glove_fingerless", "v_glove_motorcycle", "v_glove_ct_hardknuckle", "v_glove_fullfinger",
			"v_glove_slick", "v_glove_ct_specialist", "v_glove_sporty",
		}
		for _, name in ipairs(models) do
			for _, ext in ipairs({ ".mdl", ".vvd", ".dx90.vtx" }) do
				M.files["models/zcity_csgo_gloves/" .. name .. ext] = true
			end
		end
		M.files["materials/zcity_csgo_gloves/invisible.vmt"] = true
		M.files["materials/zcity_csgo_gloves/icons/moto_1.png"] = true
		M.files["materials/zcity_csgo_gloves/skin/fingers.vmt"] = true
		M.files["materials/zcity_csgo_gloves/skin/fingers_color.vtf"] = true
		M.files["materials/models/weapons/v_models/arms/glove_motorcycle/glove_motorcycle_left.vmt"] = true
	end

	-- ------------------------------------------------------------------ the server, no Appearance Mod
	local M = dofile(testdir .. "/gmod_mock.lua")("server")
	M.luaroot = luaroot
	content(M)
	check(hg == nil, "there is no Appearance Mod before the addon loads")

	include("autorun/zcity_csgo_gloves.lua")
	eq(ZCGloves.LoadErrors, nil, "every file of the addon loaded: "
		.. tostring(ZCGloves.LoadErrors and ZCGloves.LoadErrors[1] or ""))
	check(ZCO ~= nil, "the own system is there")
	check(ZCO.Installed == true, "the catalog is installed")
	check(ZCO.MadeTables == true, "the tables of the game are made by this addon and not by a mod")

	local counts = ZCO.Counts()
	check(counts.models >= 20, "models in the catalog: " .. counts.models)
	check(counts.clothes >= 200, "pieces of clothing in the catalog: " .. counts.clothes)
	check(counts.faces >= 100, "faces in the catalog: " .. counts.faces)
	check(counts.bodygroups >= 20, "bodygroups in the catalog: " .. counts.bodygroups)
	check(counts.accessories >= 50, "accessories in the catalog: " .. counts.accessories)
	check(counts.names >= 10, "names in the catalog: " .. counts.names)

	-- what the gamemode of Z-City, its modes and its player classes call by name
	check(type(hg) == "table" and type(hg.Appearance) == "table", "hg.Appearance is there")
	check(type(hg.Appearance.PlayerModels) == "table" and next(hg.Appearance.PlayerModels[1] or {}) ~= nil,
		"the player models are in the table")
	check(type(hg.Appearance.Clothes) == "table" and next(hg.Appearance.Clothes[1] or {}) ~= nil,
		"the clothes are in the table")
	check(type(hg.Appearance.Bodygroups) == "table" and next(hg.Appearance.Bodygroups.HANDS[1] or {}) ~= nil,
		"the gloves are in the HANDS bodygroup")
	check(type(hg.Accessories) == "table" and next(hg.Accessories) ~= nil, "the accessories are in the table")
	check(type(hg.Appearance.FacemapsSlots) == "table" and next(hg.Appearance.FacemapsSlots) ~= nil,
		"the faces are in the table")

	-- A model the clothing Lua gave no face to - a slot with a "Default" and an empty material and
	-- nothing else (Cohrt, Leet and John Wick of Z-City are such models): the choice of a face is not
	-- left empty, the model is offered the faces of its sex - in this menu and in the tables the
	-- menus of the game read alike (own/sh_own.lua, sh_faces.lua) (2.24.1)
	if type(ZCGloves.SyncFaces) == "function" then ZCGloves.SyncFaces() end
	local bareSlot = (ZCO.Catalog.FacemapOf or {})["models/slav/m/cohrt.mdl"]
	check(type(bareSlot) == "string" and bareSlot ~= "",
		"a model nobody wrote a face for keeps the slot its Lua named: " .. tostring(bareSlot))
	local bareFaces, bareCount = ZCO.Faces("models/slav/m/cohrt.mdl", ZCO.MALE), 0
	for _name, material in pairs(bareFaces or {}) do
		if type(material) == "string" and material ~= "" then bareCount = bareCount + 1 end
	end
	check(bareCount >= 5, "... and the own menu offers it the faces of its sex: " .. bareCount)
	check(bareFaces and bareFaces["Default"] ~= nil, "... its own Default among them")
	local inTables = 0
	for _name, material in pairs((hg.Appearance.FacemapsSlots or {})[bareSlot or ""] or {}) do
		if type(material) == "string" and material ~= "" then inTables = inTables + 1 end
	end
	check(inTables >= 5, "... and the tables the editor of Z-City reads hold them: " .. inTables)
	local inMulti = 0
	for _name, bySlot in pairs((hg.Appearance.MultiFacemaps or {})["models/slav/m/cohrt.mdl"] or {}) do
		for _slot, material in pairs(istable(bySlot) and bySlot or {}) do
			if type(material) == "string" and material ~= "" then inMulti = inMulti + 1 end
		end
	end
	check(inMulti >= 5, "... and the table the menu of the Appearance Mod reads holds them: " .. inMulti)
	-- The path a menu holds a model under and the path its faces are declared under are not always
	-- the same file: the clothing Lua of Z-City declares the same model as models/zcity/...,
	-- models/zcityadodser/... and models/slav/..., and a model file names materials no Lua declared
	-- a slot for. The faces of every path of the same file, and of every slot the model file itself
	-- carries, are the faces of the model - so the own menu lists them whichever path came by
	-- (own/sh_own.lua, 2.24.2).
	local rochelle = ZCO.Faces("models/slav/f/rochelle.mdl", ZCO.FEMALE)
	eq(rochelle["Face 1"], "models/humans/slav/rochelletrs/trs_rochelle_head_1",
		"the catalog has the faces of a model of its own")
	local elsewhere = ZCO.Faces("models/wherever/else/rochelle.mdl", ZCO.FEMALE)
	eq(elsewhere["Face 1"], rochelle["Face 1"],
		"... and the same model under another path of the same file has the same faces")
	local upper = ZCO.Faces("models/slav/f/ROCHELLE.MDL", ZCO.FEMALE)
	eq(upper["Face 1"], rochelle["Face 1"], "... whatever the case of the path a menu holds")
	local alien = ZCO.Faces("models/nowhere/something_else.mdl", ZCO.FEMALE)
	local alienCount = 0
	for _name, material in pairs(alien or {}) do
		if type(material) == "string" and material ~= "" then alienCount = alienCount + 1 end
	end
	check(alienCount >= 5, "and a model no Lua named at all is offered the faces of its sex: " .. alienCount)
	check(type(ApplyAppearance) == "function", "ApplyAppearance is there for the gamemode")
	check(type(hg.Appearance.ForceApplyAppearance) == "function", "ForceApplyAppearance is there for the modes")
	check(type(hg.Appearance.GetRandomAppearance) == "function", "GetRandomAppearance is there")
	check(type(hg.Appearance.AppearanceValidater) == "function", "AppearanceValidater is there")
	check(type(hg.Appearance.GetAccessToAll) == "function", "GetAccessToAll is there")
	check(type(hg.Appearance.IsInvalidName) == "function", "IsInvalidName is there")
	check(type(hg.Appearance.GenerateRandomName) == "function", "GenerateRandomName is there")
	check(type(hg.Appearance.CreateAppearanceFile) == "function", "a look can be written into a file")
	check(type(hg.Appearance.LoadAppearanceFile) == "function", "... and read back")
	check(type(hg.Appearance.GetAppearanceList) == "function", "the list of the files is there")
	check(type(ThatPlyIsFemale) == "function", "ThatPlyIsFemale is there")
	check(type(ApplyAppearanceRagdoll) == "function", "ApplyAppearanceRagdoll is there")
	check(type(FindMetaTable("Player").PS_HasItem) == "function", "the point shop asks this addon")
	check(type(FindMetaTable("Player").GetSubMaterialSlots) == "function", "the slots of a model are asked")

	-- an accessory keeps its numbers: the bone, the offset, the angle and the scale of the catalog
	local one = nil
	for name in pairs(hg.Accessories) do
		if name ~= "none" and hg.Accessories[name].model then one = hg.Accessories[name] break end
	end
	check(one ~= nil, "an accessory of the catalog is in the table")
	if one then
		check(type(one.bone) == "string" and one.bone ~= "", "it has a bone: " .. tostring(one.bone))
		check(type(one.malepos) == "table" and type(one.malepos[1]) == "table" and one.malepos[1].x ~= nil,
			"it has an offset (a Vector)")
		check(type(one.malepos[2]) == "table" and one.malepos[2].p ~= nil, "it has an angle")
		check(type(one.malepos[3]) == "number", "it has a scale")
	end

	-- our own gloves are in the same table as everything else
	hook.Run("InitPostEntity")
	M.advance(2)
	local gloves = 0
	for name, entry in pairs(hg.Appearance.Bodygroups.HANDS[1] or {}) do
		if type(entry) == "table" and entry.ZCG ~= nil then gloves = gloves + 1 end
		_ = name
	end
	check(gloves >= 10, "the CS:GO gloves of this addon are in the menu tables: " .. gloves)

	-- ------------------------------------------------------------------ a player is dressed
	local ply = M.newPlayer("Игрок", "models/slav/m/male_01.mdl", { steamid64 = "76561198000000001" })
	M.localplayer = ply
	check(ZCO.FileOf(ply) == "zco/76561198000000001.txt", "the file of a player: " .. tostring(ZCO.FileOf(ply)))

	ApplyAppearance(ply)
	local asked = false
	for _, message in ipairs(M.netMessages) do
		if message.name == "zco_ask" then asked = true end
	end
	check(asked, "with nothing saved the client is asked for the look it kept")
	M.netFlush(false)          -- the client has no file either: it answers with nothing
	M.netFlush(true)
	M.advance(4)
	check(ply.zcoAppearance ~= nil, "with nothing kept anywhere a look is made for him once (2.24.0)")
	local madeOnce = ply.zcoAppearance and ply.zcoAppearance.AModel
	check(M.written[ZCO.FileOf(ply)] ~= nil, "... and it is written into his file, so it is not made again")
	ZCO.ApplyAppearance(ply, nil, true)
	eq(ply.zcoAppearance and ply.zcoAppearance.AModel, madeOnce,
		"... the next spawn keeps that look: no random outfit every time")
	M.written[ZCO.FileOf(ply)] = nil
	ply.zcoAppearance, ply.zcoCached = nil, nil

	-- the client answers with the file the Appearance Mod keeps: that file is the save of the
	-- player, and the server puts it on him and hands it to the cache of the gamemode
	net.Start("zco_answer")
	net.WriteTable({
		AModel = "Male 02",
		AClothes = { main = "normal", pants = "normal", boots = "normal" },
		AName = "Из файла",
		AColor = { r = 12, g = 34, b = 56, a = 255 },
		AAttachments = {},
		ABodygroups = {},
		AFacemap = "Default",
	})
	net.SendToServer()
	M.netFlush(true)
	check(ply.zcoAppearance ~= nil, "the look the client kept in the file of the Appearance Mod is put on him")
	eq(ply.zcoAppearance and ply.zcoAppearance.AName, "Из файла", "... with the name it was saved under")
	check(ply.CachedAppearance ~= nil, "the cache of the gamemode holds it: its own spawn path reuses it")

	local look = {
		AModel = "Male 02",
		AClothes = { main = "normal", pants = "normal", boots = "normal" },
		AName = "Вася",
		AColor = Color(12, 34, 56),
		AAttachments = { "armband black" },
		ABodygroups = {},
		AFacemap = "Default",
	}
	check((ZCO.Catalog.Accessories or {})["armband black"] ~= nil, "the accessory of the test is in the catalog")
	net.Start("zco_set")
	net.WriteTable(look)
	net.SendToServer()
	M.netFlush(true)
	eq(ply:GetNWString("PlayerName"), "Вася", "the name is on the player")
	eq(ply:GetModel(), (ZCO.Models(1)["Male 02"] or {}).mdl, "the model is on the player")
	local worn = ply:GetNetVar("Accessories")
	check(type(worn) == "table" and worn[1] == "armband black", "the clients are told what he wears")
	check(M.written["zco/76561198000000001.txt"] ~= nil, "the look is kept on the server")
	-- Z-City reads what a player wears from this field: its modes (homicide names a traitor by the
	-- name over his head), its ragdolls and its admin tools
	check(type(ply.CurAppearance) == "table" and ply.CurAppearance.AName == "Вася",
		"ply.CurAppearance is there for the gamemode: " .. tostring(ply.CurAppearance and ply.CurAppearance.AName))

	local back = ZCO.Load(ply)
	check(back ~= nil, "the file is read back")
	if back then
		eq(back.AModel, "Male 02", "... with the model")
		eq(back.AName, "Вася", "... with the name")
		eq(back.AAttachments[1], "armband black", "... with the accessory")
		eq(back.AColor.r, 12, "... with the color")
		eq(back.AClothes.main, "normal", "... with the clothes")
	end

	-- what is not in the catalog is not put on
	net.Start("zco_set")
	net.WriteTable({ AModel = "Male 02", AClothes = { main = "нет такой одежды" }, AName = "Вася",
		AColor = Color(1, 2, 3), AAttachments = { "нет такого" }, ABodygroups = { HANDS = "нет таких" },
		AFacemap = "Default" })
	net.SendToServer()
	M.netFlush(true)
	local now = ply.zcoAppearance
	check(now ~= nil, "a look with things that are not in the catalog is still put on")
	if now then
		check(#now.AAttachments == 0, "an accessory that is not in the catalog is dropped")
		check(now.ABodygroups.HANDS == nil, "a bodygroup that is not in the catalog is dropped")
		check(now.AClothes.main == nil or ZCO.Clothes(1)[now.AClothes.main] ~= nil
			or ZCO.Clothes(2)[now.AClothes.main] ~= nil, "clothes that are not in the catalog are dropped")
	end

	-- a name of digits is not a name
	net.Start("zco_set")
	net.WriteTable({ AModel = "Male 02", AClothes = {}, AName = "12345", AColor = Color(1, 2, 3),
		AAttachments = {}, ABodygroups = {}, AFacemap = "Default" })
	net.SendToServer()
	M.netFlush(true)
	check(not ZCO.NameValid("12345"), "digits are not a name")
	check(ZCO.NameValid("Вася Пупкин"), "a Russian name is a name")
	check(not ZCO.NameValid("В"), "one letter is not a name")
	check(ZCO.NameValid(string.rep("a", 25)), "25 letters are a name")
	check(not ZCO.NameValid(string.rep("a", 26)), "26 letters are not")

	-- two accessories of one place do not go together
	local places, pair = {}, nil
	for name, data in pairs(ZCO.Catalog.Accessories or {}) do
		local place = data.placement or "none"
		if places[place] and not pair then pair = { places[place], name } end
		places[place] = name
	end
	if pair then
		local two = ZCO.Clean({ AModel = "Male 02", AClothes = {}, AAttachments = { pair[1], pair[2] },
			ABodygroups = {}, AFacemap = "Default", AName = "Вася", AColor = Color(1, 2, 3) })
		eq(#two.AAttachments, 1, "of two accessories on one place one is worn")
		local ok, why = ZCO.Validate({ AModel = "Male 02", AClothes = {}, AAttachments = { pair[1], pair[2] },
			ABodygroups = {}, AFacemap = "Default" })
		check(not ok and type(why) == "string", "and the check says why: " .. tostring(why))
	end
	check(not ZCO.Validate({ AModel = "Male 02", AClothes = {}, AAttachments = { "a", "b", "c", "d" },
		ABodygroups = {} }), "more than three accessories are not a look")

	-- access: everything for everyone, or the admins and the list
	check(ZCO.Access(ply), "by default everybody may choose his look")
	M.setConVar("zco_access_for_all", "0")
	check(not ZCO.Access(ply), "with zco_access_for_all 0 he may not")
	M.setConVar("zco_access_steam", ply:SteamID())
	check(ZCO.Access(ply), "... but a player of the list may")
	M.setConVar("zco_access_for_all", "1")
	local admin = M.newPlayer("Админ", "models/slav/m/male_03.mdl", { steamid64 = "76561198000000002",
		admin = true, steamid = "STEAM_0:1:2" })
	M.setConVar("zco_access_for_all", "0")
	M.setConVar("zco_access_steam", "")
	check(ZCO.Access(admin), "an admin may always")
	M.setConVar("zco_access_for_all", "1")

	-- the commands of the console run
	for _, command in ipairs({ "zco_status", "zco_list", "zco_save_all" }) do
		local ran = concommand.list[command]
		check(ran ~= nil, "the command " .. command .. " is there")
		if ran then
			local ok, err = pcall(ran.fn, ply, command, { "models" })
			check(ok, "the command " .. command .. " runs: " .. tostring(err))
		end
	end
	local before = M.written["zco/76561198000000001.txt"]
	concommand.list["zco_reset"].fn(ply, "zco_reset", { "Игрок" })
	check(M.written["zco/76561198000000001.txt"] == nil or M.written["zco/76561198000000001.txt"] ~= before,
		"zco_reset forgets the look of a player")

	-- the tables of the game are what this server really has: a name they fill is taken as it
	-- stands there (another version of the mod, a pack that was updated on the server)
	hg.Appearance.PlayerModels[1]["Male 02"] = { mdl = "models/другой/male_02.mdl", sex = false,
		submatSlots = { main = "models/другой/sheet" } }
	hg.Appearance.Clothes[1]["normal"] = "models/другой/normal"
	ZCO.Harvest()
	eq((ZCO.Models(1)["Male 02"] or {}).mdl, "models/другой/male_02.mdl",
		"a model the tables of the server fill is taken from there")
	eq(ZCO.Clothes(1)["normal"], "models/другой/normal", "... and a piece of clothing too")
	hg.Appearance.PlayerModels[1]["Male 02"] = ZCO.Catalog.Models[1]["Male 02"]

	-- a pack that adds a model of its own is taken into the catalog
	hg.Appearance.PlayerModels[1]["Свой"] = { mdl = "models/свой.mdl", sex = false, submatSlots = {} }
	hg.Accessories["свой шарф"] = { model = "models/свой_шарф.mdl", bone = "ValveBiped.Bip01_Head1",
		malepos = { Vector(1, 2, 3), Angle(0, 0, 0), 1 }, placement = "neck" }
	ZCO.Harvest()
	check(ZCO.Models(1)["Свой"] ~= nil, "a model another pack added is in the catalog")
	check((ZCO.Catalog.Accessories or {})["свой шарф"] ~= nil, "... and an accessory it added")
	local taken = (ZCO.Catalog.Accessories or {})["свой шарф"]
	check(taken and taken.pos and taken.pos[1] and taken.pos[1].x == 1, "... with its numbers kept")

	-- ------------------------------------------------------------------ a model that is not here
	-- A player model the appearance names and that this server has not leaves the player as the
	-- ERROR body: no slots for the clothes, no material for the face, no bones for the accessories.
	check(ZCO.ModelByName(nil) == nil, "a player with no model at all is not dressed for a model of the catalog")
	check(ZCO.ModelByName("") == nil, "... and an empty name is not a model either")
	check(not ZCO.ModelReady(nil) and not ZCO.ModelReady(""), "no model at all is never ready")
	local far = "models/нет/такого.mdl"
	check(not ZCO.ModelReady(far), "a model whose file is not here is not ready")

	-- one model of the catalog is put on the server: it is the one a player without a model gets
	local one, oneEntry = "Male 01", ZCO.Models(1)["Male 01"]
	check(type(oneEntry) == "table" and isstring(oneEntry.mdl), "the catalog has Male 01: "
		.. tostring(oneEntry and oneEntry.mdl))
	local mats = {}
	for _slot, material in pairs((oneEntry or {}).submatSlots or {}) do mats[#mats + 1] = material end
	M.installModel(oneEntry.mdl, mats, { "models/slav/m" })
	check(ZCO.ModelReady(oneEntry.mdl), "a model whose file is here is ready")
	local anyName, anyEntry = ZCO.AnyModel()
	eq(anyEntry and anyEntry.mdl, oneEntry.mdl, "of the models that are here the first is the one that is given")
	check(anyName ~= nil, "... and it is known by its name: " .. tostring(anyName))
	check(ZCO.AnyModel(ZCO.FEMALE) == nil or select(2, ZCO.AnyModel(ZCO.FEMALE)) ~= nil,
		"a model of one sex alone is looked for in that sex")

	-- a player who came with no model at all is invisible: he gets one that is here
	local bare = M.newPlayer("Пустой", "", { steamid64 = "76561198000000009" })
	ZCO.Apply(bare, { AModel = "", AClothes = {}, AAttachments = {}, ABodygroups = {}, AFacemap = "Default",
		AName = "Пустой", AColor = Color(1, 2, 3) })
	eq(bare:GetModel(), oneEntry.mdl, "a player who came with no model at all is given one that is installed")

	-- a model the server has not is put on the player all the same - the players may have it from
	-- the Workshop or from FastDL, which the server cannot tell - but both consoles are told
	ZCO.Apply(ply, { AModel = far, AClothes = {}, AAttachments = {}, ABodygroups = {}, AFacemap = "Default",
		AName = "Вася", AColor = Color(1, 2, 3) })
	eq(ply:GetModel(), far, "a model the server has not is still put on the player")
	check(ZCO.Gone[far] ~= nil, "... and it is remembered as one that is not here")
	local told, toHim = false, false
	for _, line in ipairs(M.log) do
		if string.find(line, "not installed on the server", 1, true) and string.find(line, far, 1, true) then
			told = true
		end
		if string.find(line, "[to Игрок]", 1, true) and string.find(line, "not installed", 1, true) then
			toHim = true
		end
	end
	check(told, "the server console is told which model of the appearance is not here")
	check(toHim, "... and the player it was seen on is told in his own console")
	local once = 0
	for _, line in ipairs(M.log) do
		if string.find(line, "not installed on the server", 1, true) and string.find(line, far, 1, true) then
			once = once + 1
		end
	end
	ZCO.Apply(ply, { AModel = far, AClothes = {}, AAttachments = {}, ABodygroups = {}, AFacemap = "Default",
		AName = "Вася", AColor = Color(4, 5, 6) })
	local twice = 0
	for _, line in ipairs(M.log) do
		if string.find(line, "not installed on the server", 1, true) and string.find(line, far, 1, true) then
			twice = twice + 1
		end
	end
	eq(twice, once, "the same model is told about once, not every time a player wears it")

	-- a model that is not here and a player without one are named by zco_models
	local ran = concommand.list["zco_models"]
	check(ran ~= nil, "the command zco_models is there")
	if ran then
		-- whose models the server has is the owner's business: a player is told nothing
		local from = #M.log
		local ok, err = pcall(ran.fn, ply, "zco_models", {})
		check(ok, "zco_models runs for a player: " .. tostring(err))
		eq(#M.log, from, "... and tells a player nothing about the disk of the server")

		local boss = M.newPlayer("Хозяин", oneEntry.mdl, { steamid64 = "76561198000000010", superadmin = true })
		from = #M.log
		ok, err = pcall(ran.fn, boss, "zco_models", {})
		check(ok, "zco_models runs for the owner of the server: " .. tostring(err))
		local said, named, seen, yours = false, false, false, false
		for i = from + 1, #M.log do
			if string.find(M.log[i], "models of the appearance on the server", 1, true) then said = true end
			if string.find(M.log[i], far, 1, true) then named = true end
			if string.find(M.log[i], "seen on", 1, true) then seen = true end
			if string.find(M.log[i], "you are wearing", 1, true) then yours = true end
		end
		check(said, "zco_models says how many models of the appearance are installed")
		check(named, "... and names the one that is not here")
		check(seen, "... and the player it was seen on")
		check(yours, "... and which model the one who asked wears himself")
	end

	-- ------------------------------------------------------------------ a saved look stays on
	-- The modes of Z-City dress a player by asking for a RANDOM appearance. The Appearance Mod does
	-- not take his look away on that call (its fix addon wraps ApplyAppearance and applies the saved
	-- look instead), and saves work the same way here.
	check(ZCO.Keep ~= nil and ZCO.Keep:GetBool(), "zco_keep_appearance is on by default")
	local mine = M.newPlayer("Свой", oneEntry.mdl, { steamid64 = "76561198000000020" })
	local look = { AModel = one, AClothes = { main = "normal", pants = "normal", boots = "normal" },
		AName = "Вася Пупкин", AColor = Color(9, 8, 7), AAttachments = {}, ABodygroups = {},
		AFacemap = "Default" }
	ZCO.Save(mine, look)
	check(ZCO.SavedOf(mine) ~= nil, "the look the server keeps for a player is his saved one")
	eq((ZCO.SavedOf(mine) or {}).AName, "Вася Пупкин", "... with its name")
	eq((ZCO.SavedOf(mine) or {}).AModel, one, "... and its model")

	ZCO.ApplyAppearance(mine, nil, true)          -- a mode asks for a random look
	eq(mine.zcoAppearance and mine.zcoAppearance.AName, "Вася Пупкин",
		"a mode that asks for a random look leaves a player the one he saved")
	eq(mine.zcoAppearance and mine.zcoAppearance.AModel, one, "... on the model he chose")
	hg.Appearance.ApplyAppearance(mine, nil, true)
	eq(mine.zcoAppearance and mine.zcoAppearance.AName, "Вася Пупкин",
		"the call the gamemode makes by name keeps it too")

	-- a player who asks for a random look himself gets one (zco_random is userinfo: the server reads it)
	mine.info = { zco_random = "1" }
	check(mine:GetInfoNum("zco_random", 0) == 1, "the server sees zco_random of a player")
	ZCO.ApplyAppearance(mine, nil, true)
	check(mine.zcoAppearance ~= nil and mine.zcoAppearance.AName ~= "Вася Пупкин",
		"a player who asks for a random look in his own console gets a random one")
	mine.info = nil

	-- the server can be told to dress everybody at random on such a call, as before
	M.setConVar("zco_keep_appearance", "0")
	ZCO.ApplyAppearance(mine, nil, true)
	check(mine.zcoAppearance ~= nil and mine.zcoAppearance.AName ~= "Вася Пупкин",
		"zco_keep_appearance 0: every such call dresses the player at random")
	M.setConVar("zco_keep_appearance", "1")
	ZCO.ApplyAppearance(mine, nil, true)
	eq(mine.zcoAppearance and mine.zcoAppearance.AName, "Вася Пупкин",
		"... and 1 gives him his saved look back")

	-- zco_status says which of the two it is, so a player can see it in the game
	M.log = {}
	M.command("zco_status", mine)
	local told = false
	for _, line in ipairs(M.log) do
		if line:find("Сохранённая внешность: остаётся на игроке", 1, true)
			and line:find("твоя: есть", 1, true) then told = true end
	end
	check(told, "zco_status tells a player that his saved look stays on him: "
		.. table.concat(M.log, " | "))
	M.setConVar("zco_keep_appearance", "0")
	M.log = {}
	M.command("zco_status", mine)
	told = false
	for _, line in ipairs(M.log) do
		if line:find("не держится", 1, true) then told = true end
	end
	check(told, "... and that it does not when the server turns it off")
	M.setConVar("zco_keep_appearance", "1")

	-- a bot is dressed at random: it never chooses and never has a look of its own
	local bot = M.newPlayer("Бот", oneEntry.mdl, { steamid64 = "76561198000000021", bot = true })
	check(bot:IsBot(), "the bot of the test is a bot")
	ZCO.Save(bot, look)
	ZCO.ApplyAppearance(bot, nil, true)
	check(bot.zcoAppearance ~= nil and bot.zcoAppearance.AName ~= "Вася Пупкин",
		"a bot is dressed at random even with a file on the server")

	-- nothing saved: his client is asked for the file it keeps before anything is put on him
	local fresh = M.newPlayer("Новый", oneEntry.mdl, { steamid64 = "76561198000000022" })
	check(ZCO.SavedOf(fresh) == nil, "a player with nothing saved has no saved look")
	ZCO.ApplyAppearance(fresh, nil, true)
	local askedFresh = false
	for _, message in ipairs(M.netMessages) do
		if message.name == "zco_ask" then askedFresh = true end
	end
	check(askedFresh, "... and a mode that asks for a random look asks his client for the file it keeps")
	check(fresh.zcoAppearance == nil, "... nothing is put on him while that answer is on its way")
	M.advance(4)
	check(fresh.zcoAppearance ~= nil, "... and when no answer comes a look is made for him once")
	local madeFresh = fresh.zcoAppearance.AModel
	check(M.written[ZCO.FileOf(fresh)] ~= nil, "... it is kept in his file")
	ZCO.ApplyAppearance(fresh, nil, true)
	eq(fresh.zcoAppearance.AModel, madeFresh, "... and the next call keeps it instead of another random one")
	ZCO.Save(fresh, { AModel = "", AClothes = {}, AAttachments = {}, ABodygroups = {}, AFacemap = "Default" })
	check(ZCO.SavedOf(fresh) ~= nil, "a file that is no look is not kept - what he wears now is")
	M.written[ZCO.FileOf(fresh)] = "это не внешность"
	eq((ZCO.SavedOf(fresh) or {}).AName, fresh.zcoCached and fresh.zcoCached.AName,
		"a file that cannot be read is passed over: what he wears is kept")
	fresh.zcoAppearance, fresh.zcoCached = nil, nil
	check(ZCO.SavedOf(fresh) == nil, "a damaged file with nothing behind it is no saved look")
	fresh.zcoCached = look
	eq((ZCO.SavedOf(fresh) or {}).AName, "Вася Пупкин",
		"... and the look he sent before is taken when there is one")

	-- and where the Appearance Mod is installed: its own call is wrapped the way the fix of the mod
	-- wraps it (a pack that carries that fix does not include it here - sh_register.lua makes
	-- hg.AppearanceFix, which the pack looks into first)
	local forced, calls, modded = nil, 0, { calls = 0 }
	modded.fn = function(_client, _appearance, random)
		modded.calls = modded.calls + 1
		modded.random = random
	end
	ApplyAppearance = modded.fn
	hg.Appearance.ApplyAppearance = modded.fn
	hg.Appearance.AppearanceValidater = function(tbl) return type(tbl) == "table" and tbl.AModel ~= nil end
	hg.Appearance.ForceApplyAppearance = function(_client, tbl) forced, calls = tbl, calls + 1 end
	ZCO.OwnApply, ZCO.Keeping = nil, nil
	ZCO.KeepWrap()
	check(ApplyAppearance ~= modded.fn and ApplyAppearance == ZCO.Keeping,
		"the call of the mod is wrapped, as the fix of the mod wraps it")
	mine.zcoCached, mine.zcoAppearance = nil, nil
	mine.CachedAppearance = { AModel = one, AClothes = { main = "normal" }, AAttachments = {},
		ABodygroups = {}, AName = "Модовский", AFacemap = "Default", AColor = Color(1, 2, 3) }
	ApplyAppearance(mine, nil, true)
	check(forced ~= nil and forced.AName == "Модовский",
		"the look the game keeps for a player - what its Apply wrote into CachedAppearance - wins "
		.. "over the copy this server keeps: the order the original module reads it in (2.24.4)")
	eq(calls, 1, "... and it is put on by ForceApplyAppearance of the mod")
	eq(modded.calls, 0, "... and the mod is not asked to dress him at random")
	eq((ZCO.Load(mine) or {}).AName, "Модовский",
		"... and the copy of this server is written from it at once, not at the next spawn")
	-- with no file of his own the cache of the mod is the look of the player - and it is kept
	M.written[ZCO.FileOf(mine)] = nil
	mine.zcoCached, mine.zcoAppearance = nil, nil
	forced, calls = nil, 0
	ApplyAppearance(mine, nil, true)
	check(forced ~= nil and forced.AName == "Модовский",
		"with no file of his own the look the mod cached for the player is put on him")
	eq((ZCO.Load(mine) or {}).AName, "Модовский", "... and it is kept in a file of his own from then on")
	ZCO.Save(mine, look)
	ApplyAppearance(mine, nil, false)
	eq(modded.calls, 1, "a call that does not ask for a random look goes to the mod untouched")
	eq(calls, 1, "... and nothing is forced on the player")
	mine.CachedAppearance = nil
	ZCO.Save(mine, look)
	forced = nil
	ApplyAppearance(mine, nil, true)
	check(forced ~= nil and forced.AName == "Вася Пупкин",
		"with nothing cached by the mod the look the server keeps for the player is used")
	M.setConVar("zco_keep_appearance", "0")
	forced, modded.calls = nil, 0
	ApplyAppearance(mine, nil, true)
	check(forced == nil and modded.calls == 1, "zco_keep_appearance 0: the mod is called as it was")
	M.setConVar("zco_keep_appearance", "1")
	forced, modded.calls = nil, 0
	ApplyAppearance(mine, nil, true)
	check(forced ~= nil and modded.calls == 0, "... and 1 keeps the saved look again")
	local bot2 = M.newPlayer("Бот 2", oneEntry.mdl, { steamid64 = "76561198000000023", bot = true })
	bot2.CachedAppearance = mine.zcoCached
	forced, modded.calls = nil, 0
	ApplyAppearance(bot2, nil, true)
	check(forced == nil and modded.calls == 1, "a bot goes to the mod: it has no look to keep")

	-- a look the mod made at random for a player who has no file of his own would be another one at
	-- the next spawn: what was put on him is kept as his own from now on (2.24.0)
	local nofile = M.newPlayer("Без файла", oneEntry.mdl, { steamid64 = "76561198000000024" })
	check(ZCO.Load(nofile) == nil, "the player of the test has no file of his own on the server")
	nofile.CachedAppearance = { AModel = one, AClothes = { main = "normal" }, AAttachments = {},
		ABodygroups = {}, AName = "Случайный", AFacemap = "Default", AColor = Color(4, 5, 6) }
	forced, modded.calls = nil, 0
	ApplyAppearance(nofile, nil, true)
	check(forced ~= nil and forced.AName == "Случайный", "what the mod cached for him is put on him")
	check(ZCO.Load(nofile) ~= nil, "... and it is kept in a file of his own on the server")
	eq((ZCO.Load(nofile) or {}).AName, "Случайный", "... the very look that was put on him")
	check(#M.netMessages >= 1, "... and his client is told, so it writes the file the mod reads")
	nofile.CachedAppearance = { AModel = one, AClothes = { main = "normal" }, AAttachments = {},
		ABodygroups = {}, AName = "Другой случайный", AFacemap = "Default", AColor = Color(7, 8, 9) }
	forced = nil
	ApplyAppearance(nofile, nil, true)
	eq((forced or {}).AName, "Другой случайный",
		"a look the game put into the cache again is the look of the player once more, and it is kept "
		.. "as his own - his client is told, so it writes the file the game reads and the cache stops "
		.. "changing (2.24.4)")
	eq((ZCO.Load(nofile) or {}).AName, "Другой случайный",
		"... and the copy of this server follows it")

	-- A table this addon wrote into the cache itself is not a look the player applied: a random
	-- dress of our own would otherwise become his look and stay it (2.24.0).
	nofile.zcoCached = nil
	local ours = ZCO.Clean({ AModel = one, AClothes = { main = "normal" }, AAttachments = {},
		ABodygroups = {}, AName = "Наш случайный", AFacemap = "Default", AColor = Color(1, 1, 1) })
	nofile.zcoAppearance, nofile.zcoWore = ours, ours
	nofile.CachedAppearance, nofile.zcoWrote = ours, ours
	nofile.CurAppearance = ours
	ZCO.Save(nofile, look)
	forced = nil
	ApplyAppearance(nofile, nil, true)
	eq((forced or {}).AName, "Вася Пупкин",
		"a random dress of this addon is not the look of the player: the tables it wrote are its own, "
		.. "and the copy this server keeps is used (2.24.0)")
	M.netMessages = {}

	-- ------------------------------------------------------------------ Apply of the editor of Z-City
	-- Its Apply writes the look into the file of the gamemode on the client and into CachedAppearance
	-- on the server, and the look is worn at the next spawn. The copy this server keeps has to follow
	-- it at once: a mode, a relog or a map change in between would keep the copy from before (2.24.4).
	do
		local who = M.newPlayer("Применил", oneEntry.mdl, { steamid64 = "76561198000000025" })
		ZCO.Save(who, look)
		eq((ZCO.Load(who) or {}).AName, "Вася Пупкин", "(the imitation: a copy of this server)")
		who.CachedAppearance = { AModel = one, AClothes = { main = "normal" }, AAttachments = {},
			ABodygroups = {}, AName = "Выбранное", AFacemap = "Face 1", AColor = Color(3, 4, 5) }
		M.netMessages = {}
		M.advance(1.2)
		eq((ZCO.Load(who) or {}).AName, "Выбранное",
			"an Apply of the editor of Z-City is kept by this server at once, not at the next spawn")
		eq(who.zcoAppearance and who.zcoAppearance.AName, "Выбранное",
			"... and it is the look of the player from then on")
		local told = 0
		for _, message in ipairs(M.netMessages) do
			if message.name == "zco_got" then told = told + 1 end
		end
		check(told >= 1, "... and his client is told, so it writes the file the gamemode reads")
		M.netMessages = {}
		M.advance(3)
		eq((ZCO.Load(who) or {}).AName, "Выбранное",
			"... and the watch keeps it: nothing is written again while he applies nothing")
		local sent = 0
		for _, message in ipairs(M.netMessages) do
			if message.name == "zco_got" then sent = sent + 1 end
		end
		eq(sent, 0, "... and nothing is sent to his client again either")

		-- A spawn: the game wore what its Apply put into the cache, and the copy of this server is
		-- from before that Apply. Putting that copy on the player is what took the applied look
		-- away at every spawn; now the copy follows what the game wore, not the other way round.
		ZCO.Save(who, look)
		eq((ZCO.Load(who) or {}).AName, "Вася Пупкин", "(the imitation: the copy is the older one)")
		who.zcoWore = nil
		who.CurAppearance = { AModel = one, AClothes = { main = "normal" }, AAttachments = {},
			ABodygroups = {}, AName = "Выбранное", AFacemap = "Face 1", AColor = Color(3, 4, 5) }
		hook.Run("PlayerSpawn", who)
		M.advance(0.2)
		eq(who.zcoAppearance and who.zcoAppearance.AName, "Выбранное",
			"at a spawn the look the game wore is kept as the look of the player ...")
		eq((ZCO.Load(who) or {}).AName, "Выбранное",
			"... and the copy of this server is written from it, not put over it")
		check(who.zcoWore ~= nil,
			"... and the very same look is put on him once more by the rails of this addon: the wear of "
			.. "the game leaves out the clothes and the face its own tables have no name for, which is "
			.. "the reset of the chosen clothes at every death (2.24.5)")
		eq(who.zcoAppearance.AFacemap, "Face 1", "... with the face he applied")
	end
	M.netMessages = {}

	do -- the content of the addon that no Lua names: found by walking its own folder (own/sh_scan.lua)
		local FOLDER, MODEL = "addons/zcity_csgo_gloves", "models/odd/found_body.mdl"
		local CLOTH, LONELY = "models/odd/found_cloth", "models/odd/lonely"
		ZCGloves.AddonFolder = FOLDER
		M.files[FOLDER .. "/lua/autorun/zcity_csgo_gloves.lua"] = true
		-- a model nobody called AppAddModel for: its parts are beside it and its materials are there
		M.installModel(MODEL, { "players_sheet", "found_pants", "found_boots" }, { "models/odd" })
		for _, ext in ipairs({ ".mdl", ".vvd", ".dx90.vtx" }) do
			M.files[FOLDER .. "/models/odd/found_body" .. ext] = true
		end
		for _, name in ipairs({ "players_sheet", "found_pants", "found_boots" }) do
			M.files["materials/models/odd/" .. name .. ".vmt"] = true
		end
		-- a model without the parts it needs: the game does not read it, so it is not offered
		M.files[FOLDER .. "/models/odd/half_a_model.mdl"] = true
		-- a material no pack calls AddClothes for, with its texture - and one whose texture is not there
		M.files["materials/" .. CLOTH .. ".vmt"] = true
		M.filedata["materials/" .. CLOTH .. ".vmt"] = '"VertexLitGeneric"\n{\n\t"$BaseTexture" "models/odd/found_cloth_color"\n}\n'
		M.files["materials/models/odd/found_cloth_color.vtf"] = true
		M.files[FOLDER .. "/materials/" .. CLOTH .. ".vmt"] = true
		M.files[FOLDER .. "/materials/models/odd/found_cloth_color.vtf"] = true
		M.files["materials/" .. LONELY .. ".vmt"] = true
		M.filedata["materials/" .. LONELY .. ".vmt"] = '"VertexLitGeneric"\n{\n\t"$basetexture" "models/odd/nowhere"\n}\n'
		M.files[FOLDER .. "/materials/" .. LONELY .. ".vmt"] = true
		-- a note, and the gloves of the addon itself: neither of them is something to wear
		M.files[FOLDER .. "/materials/readme.txt"] = true
		M.files[FOLDER .. "/materials/zcity_csgo_gloves/icons/moto_1.png"] = true

		local files, cut = ZCO.ScanAll(true)
		check(istable(files), "the walk through the folder of the addon returns what lies in it")
		eq(#files, 9, "every file of its materials/ and models/ is walked")
		eq(cut, false, "... and the walk was not cut short by its budget")
		local got = ZCO.ScanCounts()
		eq(got.models, 2, "models in the folder of the addon")
		eq(got.complete, 1, "... one of them with the parts a model needs")
		eq(got.brokenModels, 1, "... and one without them")
		eq(got.materials, 2, "materials in it")
		eq(got.textures, 1, "textures")
		eq(got.parts, 2, "parts of models")
		eq(got.other, 1, "files that are no content at all")
		eq(got.own, 1, "... and the gloves of the addon itself are counted apart")

		local worn, clothed = ZCO.ScanWear()
		eq(worn, 1, "one model no Lua names can be worn")
		eq(clothed, 2, "... and two materials no Lua names")
		local names = {}
		for name in pairs(ZCO.Scanned.Clothes[1]) do names[#names + 1] = name end
		table.sort(names)
		eq(table.concat(names, ","), CLOTH .. "," .. LONELY,
			"the materials that can be worn, and nothing of the gloves among them")
		local entry = ZCO.Models(1)[MODEL]
		check(istable(entry) and entry.mdl == MODEL, "the model that was found is in the list of the models")
		check(entry and entry.found == true, "... marked as one the addon found itself")
		check(ZCO.Models(2)[MODEL] ~= nil, "... in both sexes: the menu lists the models of the sex that is chosen")
		eq(ZCO.CatalogModels(1)[MODEL], nil, "... and it is not in the catalog")
		eq(hg.Appearance.PlayerModels[1][MODEL], nil, "... so it is not pushed into the tables of the game either")
		eq(ZCO.Clothes(1)[CLOTH], CLOTH, "a material that was found can be worn")
		eq(ZCO.CatalogClothes(1)[CLOTH], nil, "... and is not in the catalog")
		check(ZCO.IsScanned("model", MODEL) and ZCO.IsScanned("clothes", CLOTH), "... and both say what they are")
		check(not ZCO.IsScanned("model", "Male 01"), "a model the Lua named is not one that was found")
		for _try = 1, 10 do
			local random = ZCO.Random(1)
			check(random.AModel ~= MODEL and random.AClothes.main ~= CLOTH,
				"a random look is made of the catalog alone, not of what the walk found")
		end
		check(ZCO.AnyModel() ~= MODEL, "... and so is the model a player who came with none is given")

		-- the slots of a model nobody described are read out of its own file
		local slots = ZCO.GuessSlots(MODEL)
		check(istable(slots), "the slots of a model no Lua described come out of its own file")
		eq(slots and slots.main, "models/odd/players_sheet", "... the sheet")
		eq(slots and slots.pants, "models/odd/found_pants", "... the trousers")
		eq(slots and slots.boots, "models/odd/found_boots", "... and the boots")
		eq(ZCO.GuessSlots(MODEL), slots, "(the file of the model is not read twice)")
		eq(ZCO.GuessSlots("models/odd/half_a_model.mdl"), nil, "a model whose file cannot be read has no slots")

		-- what a material says about its texture
		eq(ZCO.MaterialTexture(CLOTH), "models/odd/found_cloth_color",
			"the texture a material names is read out of its .vmt, whatever the case of the key")
		check(not ZCO.MaterialBroken(CLOTH), "... and that texture is there")
		eq(ZCO.MaterialTexture(LONELY), "models/odd/nowhere", "a material whose texture is not there says so")
		check(ZCO.MaterialBroken(LONELY), "... and is named as one that draws the ERROR texture")

		-- worn on a player: the model is set, and the clothes go into the slot its file gave
		local boss = M.newPlayer("Хозяин", oneEntry.mdl, { steamid64 = "76561198000000031", superadmin = true })
		local look = { AModel = MODEL, AClothes = { main = CLOTH, pants = LONELY }, AAttachments = {},
			ABodygroups = {}, AFacemap = "Default", AName = "", AColor = Color(200, 200, 200) }
		local ok, why = ZCO.Validate(look)
		check(ok, "a look of what was found is one the server accepts: " .. tostring(why))
		local clean = ZCO.Clean(look)
		eq(clean.AModel, MODEL, "... it keeps the model that was found")
		eq(clean.AClothes.main, CLOTH, "... and the material that was found")
		ZCO.Apply(boss, clean)
		eq(boss:GetModel(), MODEL, "the model that was found is put on the player")
		eq(boss:GetSubMaterial(0), CLOTH, "... the clothes go into the slot the file of the model gave")
		eq(boss:GetSubMaterial(1), LONELY, "... and the trousers into theirs")
		eq(ZCO.Slots(boss).main, 0, "the slots of a player in a model nobody described come from its file")

		M.log = {}
		M.command("zco_status", boss)
		local said = table.concat(M.log, "\n")
		check(string.find(said, "Без Lua найдено в папке аддона: моделей 1, материалов 2", 1, true) ~= nil,
			"zco_status says what was found without Lua: " .. said:sub(1, 400))

		M.log = {}
		M.command("zco_scan", mine)
		check(string.find(table.concat(M.log, "\n"), "Только администрация", 1, true) ~= nil,
			"zco_scan is a command of the owner: another player is told so")
		M.log = {}
		M.command("zco_scan", boss)
		said = table.concat(M.log, "\n")
		check(string.find(said, "Контент без Lua", 1, true) ~= nil, "zco_scan says what it walked through")
		check(string.find(said, "моделей 1, материалов 2", 1, true) ~= nil, "... and what can be worn")
		check(string.find(said, "моделей без частей", 1, true) ~= nil, "... and a model the game cannot read")
		check(string.find(said, "у 1 нет текстуры рядом", 1, true) ~= nil, "... and a material with no texture")
		M.log = {}
		M.command("zco_scan_list", boss)
		said = table.concat(M.log, "\n")
		check(string.find(said, MODEL .. "  —  модель (надеть можно)", 1, true) ~= nil,
			"zco_scan_list names every file: " .. said:sub(1, 600))
		check(string.find(said, "слоты из файла: boots → models/odd/found_boots", 1, true) ~= nil,
			"... and the slots it read out of the model")
		check(string.find(said, "$basetexture models/odd/nowhere — ТЕКСТУРЫ НЕТ", 1, true) ~= nil,
			"... and a material whose texture is not there")
		check(string.find(said, "models/odd/half_a_model.mdl  —  модель неполная", 1, true) ~= nil,
			"... and a model without its parts")
		check(string.find(said, "readme.txt  —  прочий файл (не контент", 1, true) ~= nil,
			"... and a file that is no content at all")
		check(string.find(said, "zcity_csgo_gloves", 1, true) == nil,
			"... without the gloves of the addon itself: they are not clothes")

		-- switched off: what was found is taken back out of the menu, and out of a look that wears it
		M.setConVar("zco_scan_content", "0")
		ZCO.ScanPass(true)
		eq(ZCO.Scanned, nil, "zco_scan_content 0: what was found is taken back")
		eq(ZCO.Models(1)[MODEL], nil, "... the model is not offered any more")
		eq(ZCO.Clothes(1)[CLOTH], nil, "... and the material is not either")
		local back = ZCO.Clean(look)
		check(back.AClothes.main ~= CLOTH, "... so a look that wears it is cleaned back to the catalog")
		M.log = {}
		M.command("zco_scan", boss)
		check(string.find(table.concat(M.log, "\n"), "выключен", 1, true) ~= nil, "... and zco_scan says so")
		M.setConVar("zco_scan_content", "1")
		ZCO.ScanPass(true)
		check(ZCO.Models(1)[MODEL] ~= nil and ZCO.Clothes(1)[CLOTH] ~= nil,
			"... and switching it back on finds everything again")

		-- a copy from the Workshop: the game does not list the folders of an archive it mounted
		ZCGloves.AddonFolder = false
		ZCO.ScanPass(true)
		eq(ZCO.ScanAll(true), nil, "an addon mounted as an archive has no folder to walk through")
		M.log = {}
		M.command("zco_scan", boss)
		check(string.find(table.concat(M.log, "\n"), "смонтирован архивом", 1, true) ~= nil,
			"... and zco_scan says where the list comes from then")
		ZCGloves.AddonFolder = FOLDER
		ZCO.ScanPass(true)

		M.files[FOLDER .. "/lua/autorun/zcity_csgo_gloves.lua"] = nil
		for _, path in ipairs({
			FOLDER .. "/models/odd/found_body.mdl", FOLDER .. "/models/odd/found_body.vvd",
			FOLDER .. "/models/odd/found_body.dx90.vtx", FOLDER .. "/models/odd/half_a_model.mdl",
			FOLDER .. "/materials/" .. CLOTH .. ".vmt", FOLDER .. "/materials/models/odd/found_cloth_color.vtf",
			FOLDER .. "/materials/" .. LONELY .. ".vmt", FOLDER .. "/materials/readme.txt",
			FOLDER .. "/materials/zcity_csgo_gloves/icons/moto_1.png",
			"materials/" .. CLOTH .. ".vmt", "materials/models/odd/found_cloth_color.vtf",
			"materials/" .. LONELY .. ".vmt", "materials/models/odd/players_sheet.vmt",
			"materials/models/odd/found_pants.vmt", "materials/models/odd/found_boots.vmt",
		}) do
			M.files[path] = nil
		end
		M.filedata["materials/" .. CLOTH .. ".vmt"], M.filedata["materials/" .. LONELY .. ".vmt"] = nil, nil
		M.files[MODEL], M.filedata[MODEL], M.models[MODEL] = nil, nil, nil
		ZCGloves.AddonFolder, ZCO.ScanFiles, ZCO.Scanned, ZCO.ScanTried = nil, nil, nil, false
		ZCO.ScanGuess, ZCO.ScanTexture, ZCO.ScanFolder = {}, {}, nil
	end

	-- ------------------------------------------------------------------ the client
	local C = dofile(testdir .. "/gmod_mock.lua")("client")
	local Z = dofile(testdir .. "/zcity_mock.lua")(C)
	C.luaroot = luaroot
	content(C)
	-- the models of the catalog get the skeleton and the materials of the ones the imitation knows
	for _, sex in ipairs({ 1, 2 }) do
		for _name, entry in pairs(ZCO.Models and ZCO.Models(sex) or {}) do
			if type(entry) == "table" and entry.mdl and not C.models[entry.mdl] then
				C.models[entry.mdl] = C.models[sex == 2 and Z.FEMALE or Z.MALE]
			end
		end
	end

	include("autorun/zcity_csgo_gloves.lua")
	eq(ZCGloves.LoadErrors, nil, "every file of the addon loaded on the client: "
		.. tostring(ZCGloves.LoadErrors and ZCGloves.LoadErrors[1] or ""))
	check(ZCO.Installed == true, "the client has the catalog too")
	check(type(DrawAppearance) == "function", "the client draws what a player wears")
	check(type(RenderAccessories) == "function" and type(RenderAccessoriesCool) == "function",
		"... by the names Z-City calls")
	-- zco_random is userinfo: that is how the server knows a player asked for a random look himself
	-- (a player who wants one at every spawn keeps getting one)
	check(C.userinfo and C.userinfo["zco_random"], "zco_random is userinfo: the server can read it")
	check(not (C.userinfo and C.userinfo["zco_selected"]), "... and zco_selected stays his own choice")

	local me = C.newPlayer("Игрок", Z.MALE, { steamid64 = "76561198000000001" })
	C.localplayer = me

	-- the menu
	local frame = ZCO.OpenMenu()
	check(frame ~= nil, "the menu opens")
	check(#ZCO.Categories >= 10, "the categories of the menu: " .. #ZCO.Categories)
	local state = frame.zcoAppearance
	check(type(state) == "table" and state.AModel ~= nil, "the menu starts with what the player wears")
	check(#ZCO.Menu.Items("model", state) >= 10, "the models in the menu: " .. #ZCO.Menu.Items("model", state))
	check(#ZCO.Menu.Items("main", state) >= 50, "the clothes in the menu: " .. #ZCO.Menu.Items("main", state))
	-- (2.24.3) a face whose texture is not on this computer is not offered by the own menu either:
	-- all it could put on the head is a picture that is not the one its name promises
	local bare = ZCO.Menu.Items("face", state)
	check(#bare == 1 and bare[1].title == "Default",
		"without the textures the own menu offers the own face of the model and nothing else: "
			.. tostring(bare[1] and bare[1].title))
	local faceFiles = 0
	local function install(path)
		if type(path) ~= "string" or path == "" then return end
		local rel = string.lower(string.gsub(string.gsub(path, "\\", "/"), "^materials/", ""))
		C.files["materials/" .. string.gsub(rel, "%.vmt$", "") .. ".vmt"] = true
		faceFiles = faceFiles + 1
	end
	for _, faces in pairs(ZCO.Catalog.Facemaps or {}) do
		for _name, path in pairs(faces) do install(path) end
	end
	for _, byface in pairs(ZCO.Catalog.MultiFacemaps or {}) do
		for _name, byslot in pairs(byface) do
			for _slot, path in pairs(byslot) do install(path) end
		end
	end
	check(faceFiles > 50, "the textures of the faces of the catalog are installed: " .. faceFiles)
	ZCGloves.MaterialAnew()
	check(#ZCO.Menu.Items("face", state) >= 5, "the faces in the menu: " .. #ZCO.Menu.Items("face", state))
	check(#ZCO.Menu.Items("attach", state) >= 20, "the accessories in the menu: " .. #ZCO.Menu.Items("attach", state))
	check(#ZCO.Menu.Items("HANDS", state) >= 10, "the gloves in the menu: " .. #ZCO.Menu.Items("HANDS", state))

	-- a click chooses, the preview wears it
	local models = ZCO.Menu.Items("model", state)
	local third = nil
	for _, item in ipairs(models) do
		if item.value == "Male 03" then third = item end
	end
	third = third or models[1]
	ZCO.Menu.Choose(frame, "model", third, state)
	eq(state.AModel, third.value, "a click on a model chooses it")
	eq(frame.zcoPreview.zcoModel, (ZCO.Models(1)[third.value] or ZCO.Models(2)[third.value] or {}).mdl,
		"the preview wears the chosen model")

	-- the accessories: one on a place, another replaces it, the same one takes it off
	local attach = ZCO.Menu.Items("attach", state)
	ZCO.Menu.Choose(frame, "attach", attach[1], state)
	eq(#state.AAttachments, 1, "an accessory is worn")
	local other = nil
	for _, item in ipairs(attach) do
		if item.placement == attach[1].placement and item.value ~= attach[1].value then
			other = item
			break
		end
	end
	if other then
		ZCO.Menu.Choose(frame, "attach", other, state)
		eq(#state.AAttachments, 1, "another accessory of the same place replaces it")
		eq(state.AAttachments[1], other.value, "... with the new one")
		ZCO.Menu.Choose(frame, "attach", other, state)
		eq(#state.AAttachments, 0, "the same accessory once more takes it off")
	end

	-- "Применить": the look goes to the server and into the files of the client
	local apply = nil
	for _, panel in ipairs(C.panels) do
		if panel.class == "DButton" and panel:GetText() == "Применить" then apply = panel end
	end
	check(apply ~= nil, "the menu has a button that applies the look")
	if apply then
		local sent = #C.netMessages
		apply.DoClick(apply)
		check(#C.netMessages > sent, "the look is sent to the server")
		local last = C.netMessages[#C.netMessages]
		eq(last.name, "zco_set", "... as zco_set")
		check(C.written["zco/main.txt"] ~= nil, "and kept in data/zco/ of the client")
		local kept = ZCO.Deserialize(C.written["zco/main.txt"] or "")
		check(kept ~= nil and kept.AModel == state.AModel, "the file of the client holds the same look")
		-- the file the gamemode of Z-City reads is written as well, so that both paths agree
		local theirs = C.written["zcity/appearances/main.json"]
		check(theirs ~= nil, "and into data/zcity/appearances/ of the gamemode, for its own path")
		if theirs then
			local read = util.JSONToTable(theirs)
			eq(read and read.AModel, state.AModel, "... with the same model")
		end
	end

	-- the command the buttons of Z-City open the appearance by: ours answers to it, and gives it
	-- back where the editor that was there is wanted
	local menu_command = concommand.GetTable()["hg_appearance_menu"]
	check(type(menu_command) == "function", "hg_appearance_menu is a command")
	check(ZCO.TakeMenu ~= nil and ZCO.TakeMenu:GetBool(), "our menu takes it by default")
	if IsValid(ZCO.MenuFrame) then ZCO.MenuFrame:Close() end
	check(not IsValid(ZCO.MenuFrame), "the menu is closed before the command is called")
	menu_command()
	check(IsValid(ZCO.MenuFrame), "... and calling it opens the menu of this addon")

	-- a file the gamemode has chosen (hg_appearance_selected) is written as well
	local their_choice = CreateClientConVar("hg_appearance_selected", "cool", true, false, "test")
	hg.Appearance.SelectedAppearance = their_choice
	eq(ZCO.WriteOld("main", state), 2, "both sets of files are written: ours and the one it chose")
	check(C.written["zcity/appearances/cool.json"] ~= nil, "... the chosen one among them")
	hg.Appearance.SelectedAppearance = nil

	local opened = 0
	concommand.list["hg_appearance_menu"] = { fn = function() opened = opened + 1 end }
	C.setConVar("zco_take_menu", "0")
	C.command("hg_appearance_menu", me)
	eq(opened, 1, "zco_take_menu 0 leaves the command to the editor that had it")
	C.setConVar("zco_take_menu", "1")
	C.command("hg_appearance_menu", me)
	eq(opened, 1, "zco_take_menu 1 takes it for our menu again")
	check(IsValid(ZCO.MenuFrame), "... which opens ours")

	-- the chat command opens the menu
	C.localplayer = me
	check(hook.Run("OnPlayerChat", me, "/внешность") == true, "/внешность opens the menu")
	check(hook.Run("OnPlayerChat", me, "/appearance") == true, "/appearance opens it too")
	check(hook.Run("OnPlayerChat", me, "привет") == nil, "ordinary chat is left alone")

	-- what the server keeps arrives and is read
	net.Start("zco_got")
	net.WriteTable({ AModel = "Male 04", AClothes = { main = "normal" }, AName = "Петя",
		AColor = Color(1, 2, 3), AAttachments = {}, ABodygroups = {}, AFacemap = "Default" })
	net.Send(me)
	C.netFlush(false)
	check(ZCO.Saved ~= nil, "the look the server keeps is read")
	if ZCO.Saved then eq(ZCO.Saved.AModel, "Male 04", "... with its model") end

	-- The render of the accessories: every one that has a bone and a model of its own, in name
	-- order. (pairs() has no order it keeps - which accessory a test like this one picks is left
	-- to chance, and a run fails now and then for no reason at all. Picked at random, this test
	-- never once looked at the vests and the purse, which are worn on bones the skeleton of the
	-- imitation has not: Bip01_Spine1 and Bip01_Spine2. They are the reason ZCO.BoneOf exists.)
	local him = C.newPlayer("Другой", Z.MALE, {})
	local names = {}
	for one_name, data in pairs(ZCO.Catalog.Accessories or {}) do
		if data.bone and data.model and not data.cool then names[#names + 1] = one_name end
	end
	table.sort(names)
	check(#names > 0, "accessories to draw are in the catalog: " .. #names)
	local without = 0
	for _, name in ipairs(names) do
		local data = (ZCO.Catalog.Accessories or {})[name]
		if not him:LookupBone(data.bone) then without = without + 1 end
	end
	check(without > 0, "accessories on a bone the skeleton of the imitation has not: " .. without)
	-- the bone asked for, the one beside it, and nothing where the family is not there at all
	eq(ZCO.BoneOf(him, "ValveBiped.Bip01_Head1"), him:LookupBone("ValveBiped.Bip01_Head1"),
		"a bone the model has is taken as it is")
	eq(ZCO.BoneOf(him, "ValveBiped.Bip01_Spine1"), him:LookupBone("ValveBiped.Bip01_Spine4"),
		"...and one it has not is looked for beside it, nearest first")
	eq(ZCO.BoneOf(him, "ValveBiped.Bip01_Tail"), nil, "a bone of a family the model has none of is not made up")
	eq(ZCO.BoneOf(him, ""), nil, "no bone for no name")
	eq(ZCO.BoneOf(nil, "ValveBiped.Bip01_Head1"), nil, "and none for no entity")
	for _, name in ipairs(names) do
		him:SetNetVar("Accessories", { name })
		local before = #C.csmodels
		DrawAppearance(him, him)
		check(#C.csmodels > before, "the accessory is drawn as a model of its own (" .. name .. ")")
		local model = C.csmodels[#C.csmodels]
		check(model ~= nil and model:GetParent() == him, "it is parented to the player (" .. name .. ")")
		local data = (ZCO.Catalog.Accessories or {})[name]
		if data and not him:LookupBone(data.bone) then
			check(ZCO.BoneOf(him, data.bone) ~= nil,
				"...on a bone of the same family: the model has not the one the catalog names (" .. name
				.. " wants " .. tostring(data.bone) .. ")")
		end
		him:SetNetVar("Accessories", {})
		DrawAppearance(him, him)
		check(not IsValid(model), "an accessory that is taken off is removed (" .. name .. ")")
	end

	-- the sets of the Appearance Mod that a player had before are read as ours
	C.written["zcity/appearances/old.json"] = util.TableToJSON({ AModel = "Male 05",
		AClothes = { main = "normal", pants = "normal", boots = "normal" }, AName = "Старый",
		AColor = { r = 200, g = 100, b = 50 }, AAttachments = {}, ABodygroups = {}, AFacemap = "Default" })
	C.pathFiles.DATA = C.pathFiles.DATA or {}
	C.pathFiles.DATA["zcity/appearances/old.json"] = true
	local old = ZCO.ImportOld("old")
	check(old ~= nil, "a set of the old mod is read")
	if old then eq(old.AModel, "Male 05", "... with its model") end
	check(#ZCO.OldList() >= 1, "the sets of the old mod are listed")

	-- the file the Appearance Mod keeps is the save of the player: with no set of his own the client
	-- answers the server with that file, so a look chosen once is not lost (2.24.0)
	do
		local wasLoad, wasSelected = hg.Appearance.LoadAppearanceFile, hg.Appearance.SelectedAppearance
		local wasPreset, wasMine = ZCO.Presets["main"], C.written["zco/main.txt"]
		local wasOld = C.written["zcity/appearances/main.json"]
		local wasThere = (C.pathFiles.DATA or {})["zcity/appearances/main.json"]
		ZCO.Presets["main"], C.written["zco/main.txt"] = nil, nil
		C.written["zcity/appearances/main.json"] = nil
		if C.pathFiles.DATA then C.pathFiles.DATA["zcity/appearances/main.json"] = nil end
		hg.Appearance.LoadAppearanceFile = function()
			return { AModel = "Male 04", AClothes = { main = "normal" }, AName = "Из мода",
				AColor = Color(11, 22, 33), AAttachments = {}, ABodygroups = {}, AFacemap = "Default" }
		end
		hg.Appearance.SelectedAppearance = { GetString = function() return "main" end }
		check(ZCO.LocalAppearance() == nil, "a set of his own the client has none of")
		local sent = #C.netMessages
		C.netReceivers["zco_ask"](8, C.localplayer)
		check(#C.netMessages > sent, "... so the server that asks is answered")
		local last = C.netMessages[#C.netMessages]
		eq(last.name, "zco_answer", "... by zco_answer")
		local answer = last.data and last.data[1]
		check(type(answer) == "table" and answer.AModel == "Male 04",
			"... with the look of the file the Appearance Mod keeps")
		check(type(answer.AColor) == "table" and answer.AColor.r == 11 and answer.AColor.g == 22,
			"... and its color as numbers: a Color of the game does not travel in a table")
		hg.Appearance.LoadAppearanceFile, hg.Appearance.SelectedAppearance = wasLoad, wasSelected
		ZCO.Presets["main"], C.written["zco/main.txt"] = wasPreset, wasMine
		C.written["zcity/appearances/main.json"] = wasOld
		if C.pathFiles.DATA then C.pathFiles.DATA["zcity/appearances/main.json"] = wasThere end
	end

	-- ------------------------------------------------------------------ a model that is not here
	-- The server cannot tell what a player has downloaded, so the client looks for itself: a model
	-- that is not on this computer is the ERROR body, and the game says nothing about it.
	local notice = hook.GetTable().Think and hook.GetTable().Think["zco_model_notice"]
	check(notice ~= nil, "the client looks at the models of its players itself")
	local worn = me:GetModel()
	check(isstring(worn) and worn ~= "", "the player of the test wears a model: " .. tostring(worn))
	check(not ZCO.ModelReady(worn), "... which is not on this computer")
	if notice then
		local from = #C.log
		local ok, err = pcall(notice)
		check(ok, "the look at the models runs: " .. tostring(err))
		check(ZCO.Gone[worn] ~= nil, "a model that is not here is remembered")
		local told, yours = false, false
		for i = from + 1, #C.log do
			if string.find(C.log[i], "not installed on this computer", 1, true) then told = true end
			if string.find(C.log[i], "the model of your look", 1, true) then yours = true end
		end
		check(told, "the console of the player is told that his model is not on his computer")
		check(yours, "... and that it is his own look and not the one of another player")

		local lines = #C.log
		ok, err = pcall(notice)
		check(ok and #C.log == lines, "the same thing is not looked at again straight away")
		C.advance(6)
		from = #C.log
		ok, err = pcall(notice)
		check(ok and #C.log == from, "... and the same model is told about once, not every five seconds")

		-- a player with no model at all is invisible: he is told so in his own console
		local empty = C.newPlayer("Пустой", "", { steamid64 = "76561198000000011" })
		C.localplayer = empty
		C.advance(6)
		from = #C.log
		ok, err = pcall(notice)
		check(ok, "a player with no model at all is looked at as well: " .. tostring(err))
		check(ZCO.Gone["(no model at all)"] ~= nil, "... and remembered")
		local invisible = false
		for i = from + 1, #C.log do
			if string.find(C.log[i], "invisible", 1, true) then invisible = true end
		end
		check(invisible, "the console is told that a player without a model is invisible")
		C.localplayer = me
	end

	local models = concommand.list["zco_models_cl"]
	check(models ~= nil, "the command zco_models_cl is there on the client")
	if models then
		local from = #C.log
		local ok, err = pcall(models.fn, me, "zco_models_cl", {})
		check(ok, "zco_models_cl runs: " .. tostring(err))
		local said, missing = false, false
		for i = from + 1, #C.log do
			if string.find(C.log[i], "models of the appearance on this computer", 1, true) then said = true end
			if string.find(C.log[i], "not here:", 1, true) then missing = true end
		end
		check(said, "zco_models_cl says how many models of the appearance this computer has")
		check(missing, "... and names the ones it has not")
	end

	do -- the menu of what the addon found without Lua (own/cl_own_menu.lua, own/sh_scan.lua)
		local FOLDER, MODEL = "addons/zcity_csgo_gloves", "models/odd/found_body.mdl"
		local CLOTH, TROUSERS = "models/odd/found_cloth", "models/odd/found_pants_cloth"
		ZCGloves.AddonFolder = FOLDER
		C.files[FOLDER .. "/lua/autorun/zcity_csgo_gloves.lua"] = true
		C.installModel(MODEL, { "players_sheet", "found_pants" }, { "models/odd" })
		for _, ext in ipairs({ ".mdl", ".vvd", ".dx90.vtx" }) do
			C.files[FOLDER .. "/models/odd/found_body" .. ext] = true
		end
		for _, name in ipairs({ "players_sheet", "found_pants" }) do
			C.files["materials/models/odd/" .. name .. ".vmt"] = true
		end
		C.files["materials/" .. CLOTH .. ".vmt"] = true
		C.files[FOLDER .. "/materials/" .. CLOTH .. ".vmt"] = true
		C.files["materials/" .. TROUSERS .. ".vmt"] = true
		C.files[FOLDER .. "/materials/" .. TROUSERS .. ".vmt"] = true
		C.files[FOLDER .. "/materials/models/odd/found_cloth_color.vtf"] = true
		ZCO.ScanPass(true)

		local menu = ZCO.OpenMenu()
		check(menu ~= nil, "the menu opens for the list of what was found")
		local look = menu.zcoAppearance
		local found = ZCO.Menu.Items("found", look)
		check(#found >= 3, "the menu has the list of what the addon found without Lua: " .. #found)
		local model, cloth, trousers, notes = nil, nil, nil, 0
		for _, item in ipairs(found) do
			if item.kind == "model" and item.value == MODEL then model = item end
			if item.kind == "clothes" and item.value == CLOTH then cloth = item end
			if item.kind == "clothes" and item.value == TROUSERS then trousers = item end
			if item.kind == "info" then notes = notes + 1 end
		end
		check(model ~= nil, "... with the model that was found")
		eq(model and model.title, "found_body · odd  — модель",
			"... shown by the name of its file and the folder it lies in: " .. tostring(model and model.title))
		check(cloth ~= nil, "... and with a material that was found")
		eq(cloth and cloth.slot, "main", "... which goes into the sheet when the player clicks it")
		eq(trousers and trousers.slot, "pants", "... while one whose path says trousers goes into the trousers")
		check(notes >= 2, "... and it says what cannot be worn, and why: " .. notes)

		-- a click wears them, and the preview puts the clothes where the file of the model says
		ZCO.Menu.Choose(menu, "found", model, look)
		eq(look.AModel, MODEL, "a click on a model that was found wears it")
		eq(menu.zcoPreview.zcoModel, MODEL, "... and the preview shows it")
		ZCO.Menu.Choose(menu, "found", cloth, look)
		eq(look.AClothes.main, CLOTH, "a click on a material puts it into the slot its path asks for")
		ZCO.Menu.Choose(menu, "found", trousers, look)
		eq(look.AClothes.pants, TROUSERS, "... and the trousers into theirs")
		local shown = menu.zcoPreview.Entity
		check(shown ~= nil, "the preview holds the model")
		eq(shown and shown:GetSubMaterial(0), CLOTH,
			"... where the clothes are: the sheet is the slot the file of the model gave")
		eq(shown and shown:GetSubMaterial(1), TROUSERS, "... and the trousers are in theirs")

		-- a file that cannot be worn says why and changes nothing
		local note = nil
		for _, item in ipairs(found) do
			if item.kind == "info" then note = item end
		end
		local before = look.AModel
		ZCO.Menu.Choose(menu, "found", note, look)
		eq(look.AModel, before, "a click on a file that cannot be worn changes nothing")

		-- the same things are in the categories of their own, with a mark that says where they came from
		local listed, marked = false, false
		for _, item in ipairs(ZCO.Menu.Items("model", look)) do
			if item.value == MODEL then
				listed = true
				marked = string.find(item.title, "без Lua", 1, true) ~= nil
			end
		end
		check(listed, "the model that was found is in the category of the models as well")
		check(marked, "... with a mark that says no Lua named it")
		local inClothes = false
		for _, item in ipairs(ZCO.Menu.Items("main", look)) do
			if item.value == CLOTH then
				inClothes = string.find(item.title, "без Lua", 1, true) ~= nil
			end
		end
		check(inClothes, "... and the material is in the category of the clothes, with the same mark")

		-- switched off, the list says so instead of offering what cannot be worn any more
		C.setConVar("zco_scan_content", "0")
		ZCO.ScanPass(true)
		local off = ZCO.Menu.Items("found", look)
		eq(#off, 1, "zco_scan_content 0: the list says the check is off")
		check(off[1] and string.find(off[1].title, "zco_scan_content 0", 1, true) ~= nil,
			"... and names the switch that takes it back")
		local still = false
		for _, item in ipairs(ZCO.Menu.Items("model", look)) do
			if item.value == MODEL then still = true end
		end
		check(not still, "... so the model that was found is not offered any more")
		C.setConVar("zco_scan_content", "1")
		ZCO.ScanPass(true)
		check(#ZCO.Menu.Items("found", look) >= 3, "... and switching it back on brings the list back")

		-- a copy from the Workshop has no folder to walk through: the list says where it comes from
		ZCGloves.AddonFolder = false
		ZCO.ScanPass(true)
		local archive = ZCO.Menu.Items("found", look)
		eq(#archive, 1, "an addon mounted as an archive: the walk finds nothing to list")
		check(archive[1] and string.find(archive[1].hint, "sh_found.lua", 1, true) ~= nil,
			"... and the list names what the build writes instead")

		-- ... and then it wears the models the build or sort_content.bat wrote into the addon: the
		-- folders of an archive are not listed, but its files are there to be read
		C.files["models/odd/found_body.vvd"] = true
		C.files["models/odd/found_body.dx90.vtx"] = true
		ZCGloves.FoundModels = { MODEL, "models/odd/half_a_model.mdl" }
		ZCO.ScanPass(true)
		check(ZCO.Models(1)[MODEL] ~= nil, "a model of that list is offered as a model")
		eq(ZCO.Models(1)["models/odd/half_a_model.mdl"], nil,
			"... and one whose parts are not there is not: the game draws it as an ERROR body")
		archive = ZCO.Menu.Items("found", look)
		eq(#archive, 2, "the list of an archive is the list the build wrote, and the note about it")
		check(archive[1] and archive[1].kind == "model" and archive[1].value == MODEL,
			"... with the model that can be worn")
		ZCO.Menu.Choose(menu, "found", archive[1], look)
		eq(look.AModel, MODEL, "... which a click wears")
		M.log = {}
		C.command("zco_scan_cl", C.localplayer)
		local said = table.concat(C.log, "\n")
		check(string.find(said, "смонтирован архивом", 1, true) ~= nil, "zco_scan says it is an archive")
		check(string.find(said, "материалов 0, моделей 2", 1, true) ~= nil, "... and what the list holds")
		check(string.find(said, "Моделей из этого списка можно надеть: 1", 1, true) ~= nil,
			"... and how many of them can be worn: " .. said:sub(1, 400))
		ZCGloves.FoundModels = nil
		C.files["models/odd/found_body.vvd"], C.files["models/odd/found_body.dx90.vtx"] = nil, nil

		ZCGloves.AddonFolder, ZCO.ScanFiles, ZCO.Scanned, ZCO.ScanTried = nil, nil, nil, false
		ZCO.ScanGuess, ZCO.ScanTexture, ZCO.ScanFolder = {}, {}, nil
	end

	return checks, failures
end
