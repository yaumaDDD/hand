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
	check(ply.zcoAppearance ~= nil, "three seconds later a random look is on him")
	check(ZCO.ModelByName(ply.zcoAppearance.AModel) ~= nil, "the random look is one of the catalog")

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

	-- the render of the accessories
	local him = C.newPlayer("Другой", Z.MALE, {})
	local name = nil
	for one_name, data in pairs(ZCO.Catalog.Accessories or {}) do
		if data.bone and data.model and not data.cool then
			name = one_name
			break
		end
	end
	check(name ~= nil, "an accessory to draw is in the catalog")
	if name then
		him:SetNetVar("Accessories", { name })
		local before = #C.csmodels
		DrawAppearance(him, him)
		check(#C.csmodels > before, "the accessory is drawn as a model of its own (" .. name .. ")")
		local model = C.csmodels[#C.csmodels]
		check(model ~= nil and model:GetParent() == him, "it is parented to the player")
		him:SetNetVar("Accessories", {})
		DrawAppearance(him, him)
		check(not IsValid(model), "an accessory that is taken off is removed")
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

	return checks, failures
end
