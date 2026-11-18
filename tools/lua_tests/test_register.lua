-- The API the clothing packs of Z-City call by name (sh_register.lua), the content this addon finds
-- in its own folder with no sort_content.bat run (sh_auto.lua), and the places accessories are worn
-- on that their packs forgot (sh_auto.lua).
--
-- Two of the scenarios run the Lua of real packs of Z-City - packs/appearance_mod.lua and
-- packs/clothing_mod.lua, the "custom" files of the owner's folder of Lua ("ALL LUA FOR REWORK.zip",
-- the versions of folder 5) - and packs/zc_balaclava.lua, the patch written to put the masks of
-- Z-City into the menu. They are not changed in any way: what they call has to be there.
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
	local function count(list)
		local got = 0
		for _ in pairs(list or {}) do got = got + 1 end
		return got
	end
	-- the globals of the game are the globals of this file as well, and a scenario leaves what it
	-- made behind: the next one starts as the game does, with nothing of the addon in it
	local function fresh()
		hg, ZCO, ZCGloves = nil, nil, nil
		for _, name in ipairs({ "AppAddModel", "AppAddClothes", "AppAddClothesDesc", "AddFacemap",
			"AppAddBodygroup", "DrawAppearance", "RenderAccessories", "RenderAccessoriesCool" }) do
			_G[name] = nil
		end
	end

	-- ------------------------------------------------------- the server, no Z-City and no mod
	local M = dofile(testdir .. "/gmod_mock.lua")("server")
	M.luaroot = luaroot
	check(hg == nil, "there is no Z-City and no Appearance Mod before the addon loads")

	-- the file the game reads first ("!" in its name), before the Lua of any clothing pack
	include("autorun/!zcity_csgo_gloves.lua")
	eq(ZCGloves.LoadErrors, nil, "the early file loaded: "
		.. tostring(ZCGloves.LoadErrors and ZCGloves.LoadErrors[1] or ""))
	for _, name in ipairs({ "AppAddModel", "AppAddClothes", "AppAddClothesDesc", "AddFacemap", "AppAddBodygroup" }) do
		check(type(_G[name]) == "function", name .. " is there for a pack that calls it by name")
	end
	local Fix = hg and hg.AppearanceFix
	check(type(Fix) == "table", "hg.AppearanceFix is there")
	if type(Fix) == "table" then
		-- a pack of Z-City looks here before it includes a fix addon of its own: with this addon
		-- there the include does not happen, so the pack runs without a file it does not have
		for _, name in ipairs({ "AddModel", "AddClothes", "AddClothesDesc", "AddFacemap", "AddBodygroup", "Replay" }) do
			check(type(Fix[name]) == "function", "hg.AppearanceFix." .. name .. " is there")
		end
		eq(Fix.AddModel, AppAddModel, "... and it is the same function a pack calls by name")
	end
	eq(hg.Appearance, nil, "the tables of the gamemode are not made before a pack asks for them")

	-- a pack registers its content, the way the packs of Z-City are written
	hg.PointShop = { Items = {} }
	function hg.PointShop:CreateItem(id, name, model, bodygroups, skin, color, cost, donate, submats)
		hg.PointShop.Items[id] = { id = id, name = name, model = model, cost = cost, donate = donate }
		return hg.PointShop.Items[id]
	end
	AppAddModel("Pack Male 01", "models/pack/m/male_01.mdl", false, {
		main = "models/humans/male/group01/players_sheet", pants = "pack/pants", boots = "pack/boots",
		hands = "distac/gloves/hands" })
	AppAddModel("Pack Female 01", "models/pack/f/female_01.mdl", true, {
		main = "models/humans/female/group01/players_sheet" })
	AppAddClothes(1, "Pack Jacket", "pack/clothes/jacket", "A jacket of the pack", "http://pack/jacket")
	AppAddClothes("female", "Pack Skirt", "pack/clothes/skirt")
	AddFacemap("models/humans/male/group01/pack_facemap", "Face 1", "pack/facemaps/one",
		"models/pack/m/male_01.mdl")
	AppAddBodygroup("HANDS", "Pack Gloves", "packgloves_M", false, true, true, 300,
		"models/zcity/gloves/degloves.mdl", 0)

	local AP = hg.Appearance
	check(type(AP) == "table", "the tables are there as soon as a pack asks for them")
	eq(AP.PlayerModels[1]["Pack Male 01"].mdl, "models/pack/m/male_01.mdl", "a model is in the table of Z-City")
	eq(AP.PlayerModels[1]["Pack Male 01"].submatSlots.pants, "pack/pants", "... with the slots of its clothes")
	eq(AP.PlayerModels[1]["Pack Male 01"].sex, false, "... and its sex")
	eq(AP.PlayerModels[2]["Pack Female 01"].sex, true, "a female model says so")
	check(AP.FuckYouModels[1]["models/pack/m/male_01.mdl"] == AP.PlayerModels[1]["Pack Male 01"],
		"a model is found by its path as well as by its name")
	eq(AP.Clothes[1]["Pack Jacket"], "pack/clothes/jacket", "a piece of clothing is in the table of Z-City")
	eq(AP.ClothesDesc["Pack Jacket"].desc, "A jacket of the pack", "... with the description the menu shows")
	eq(AP.ClothesDesc["Pack Jacket"].link, "http://pack/jacket", "... and its link")
	eq(AP.Clothes[2]["Pack Skirt"], "pack/clothes/skirt", "the sex may be a word instead of a number")
	eq(AP.ClothesDesc["Pack Skirt"], nil, "clothes without a description get none")
	eq(AP.FacemapsSlots["models/humans/male/group01/pack_facemap"]["Face 1"], "pack/facemaps/one",
		"a face is in the table of Z-City")
	eq(AP.FacemapsModels["models/pack/m/male_01.mdl"], "models/humans/male/group01/pack_facemap",
		"... and the model it belongs to is known")
	local gloves = AP.Bodygroups.HANDS[1]["Pack Gloves"]
	check(type(gloves) == "table", "a bodygroup is in the table of Z-City")
	if gloves then
		eq(gloves[1], "packgloves_M", "... with its submodel")
		eq(gloves[2], true, "... and whether the point shop sells it")
		eq(gloves.ID, "Standard_BodyGroups_Pack Gloves", "... and the id of its item in the point shop")
	end
	check(hg.PointShop.Items["Standard_BodyGroups_Pack Gloves"] ~= nil,
		"the item of the point shop is made for it, as the gamemode makes it")

	check(ZCGloves.RegisteredOnly(AP), "the tables hold nothing but what packs registered through this addon")
	eq(#ZCGloves.RegisterOrder, 6, "every call is remembered")
	eq(ZCGloves.RegisterCalls, 6, "... and counted")
	local counts = ZCGloves.RegisterCounts()
	check(counts.model == 2 and counts.cloth == 2 and counts.face == 1 and counts.bg == 1,
		"the calls are counted by kind: " .. tostring(counts.model) .. " models, " .. tostring(counts.cloth)
		.. " clothes, " .. tostring(counts.face) .. " faces, " .. tostring(counts.bg) .. " bodygroups")

	-- the gamemode makes its tables anew afterwards (what the fix addon of Z-City is written for):
	-- what the packs registered goes back in
	AP.PlayerModels = { [1] = {}, [2] = {} }
	AP.Clothes = { [1] = {}, [2] = {} }
	AP.FacemapsSlots, AP.FacemapsModels, AP.Bodygroups = {}, {}, {}
	eq(ZCGloves.ReplayRegistered(), 6, "tables made anew get every registration back")
	eq(AP.PlayerModels[1]["Pack Male 01"].mdl, "models/pack/m/male_01.mdl", "the model is there again")
	eq(AP.Clothes[2]["Pack Skirt"], "pack/clothes/skirt", "... the clothes")
	eq(AP.Bodygroups.HANDS[1]["Pack Gloves"][1], "packgloves_M", "... and the bodygroup")
	eq(ZCGloves.ReplayRegistered(), 0, "a second replay changes nothing: everything is there")
	local lines = {}
	ZCGloves.RegisterReport(function(text) lines[#lines + 1] = text end)
	check(#lines == 1 and string.find(lines[1], "registered its content here", 1, true) ~= nil
		and string.find(lines[1], "2 models", 1, true) ~= nil,
		"zcg_content names what the packs registered: " .. tostring(lines[1]))

	-- the Lua of two real packs of Z-City, unchanged: they look into hg.AppearanceFix and call the API
	dofile(testdir .. "/packs/clothing_mod.lua")
	dofile(testdir .. "/packs/appearance_mod.lua")
	eq(AP.PlayerModels[1]["Adodser Male 01"].mdl, "models/zcityadodser/m/male_01.mdl",
		"the pack of the clothes of Z-City registered its models")
	eq(AP.Clothes[1]["bomber_jacket1"], "models/humans/male/group01/bomberjacket1", "... and its clothes")
	eq(AP.PlayerModels[1]["Male 10"].mdl, "models/zcity/m/male_10.mdl",
		"the pack of the appearance of Z-City registered its models")
	eq(AP.Clothes[1]["femboy"], "models/humans/modern/male/sheet_29", "... and its clothes")
	eq(AP.PlayerModels[2]["Female Mossman"].mdl, "models/zcity/f/mossman.mdl", "... its female models as well")
	check(count(AP.Bodygroups.TORSO and AP.Bodygroups.TORSO[1]) >= 5,
		"the bodygroups of the pack are in the table of Z-City: " .. count(AP.Bodygroups.TORSO[1]))
	check(ZCGloves.RegisterCalls > 200, "every call of the two packs went through: " .. ZCGloves.RegisterCalls)
	check(ZCGloves.RegisteredOnly(AP), "and the tables still hold nothing but what came through this addon")
	-- the faces of the packs: a slot, a name and the material of the face
	local faces = 0
	for _slot, list in pairs(AP.FacemapsSlots) do faces = faces + count(list) end
	check(faces > 100, "the faces of the two packs are in the tables: " .. faces)

	-- the whole addon loads on top of that: its own appearance system is not confused by the
	-- content the packs brought, and its catalog takes that content in
	include("autorun/zcity_csgo_gloves.lua")
	eq(ZCGloves.LoadErrors, nil, "every file of the addon loaded: "
		.. tostring(ZCGloves.LoadErrors and ZCGloves.LoadErrors[1] or ""))
	hook.Run("InitPostEntity")
	check(ZCO ~= nil and ZCO.Installed == true, "the own appearance system is there")
	check(ZCO.Theirs == false, "the content of the packs is not an appearance system of somebody else's")
	check(ZCO.MadeTables == true, "... so the tables are filled from the catalog of this addon next to it")
	eq(ZCO.Models(1)["Pack Male 01"].mdl, "models/pack/m/male_01.mdl",
		"the catalog took the model of the pack in")
	eq(ZCO.Clothes(1)["femboy"], "models/humans/modern/male/sheet_29", "... and the clothes of the real packs")
	check(ZCO.Bodygroups("TORSO", 1)["Odessa Jacket"] ~= nil, "... and their bodygroups")
	check(count(ZCO.Models(1)) > 20, "the models of the catalog and of the packs: " .. count(ZCO.Models(1)))
	check(count(ZCO.Clothes(1)) > 100, "the clothes of them: " .. count(ZCO.Clothes(1)))
	check(not ZCGloves.RegisteredOnly(hg.Appearance),
		"the catalog in the tables is told from the content of the packs")
	-- the point shop of the addon makes the item of a bodygroup registered afterwards
	AppAddBodygroup("HANDS", "Late Gloves", "lategloves_M", false, true, false, 10)
	check(hg.PointShop.Items["Standard_BodyGroups_Late Gloves"] ~= nil,
		"a bodygroup registered later gets its item in the point shop of the addon")
	check(ZCO.Bodygroups("HANDS", 1)["Late Gloves"] ~= nil
		or ZCO.Harvest() >= 0, "... and the catalog looks at the tables again for it")
	check(ZCO.Bodygroups("HANDS", 1)["Late Gloves"] ~= nil, "... and has it")
	-- the API is published once: a file loaded again does not make it anew
	local wasModel = AppAddModel
	include("autorun/!zcity_csgo_gloves.lua")
	eq(AppAddModel, wasModel, "the API is not made anew by a file that loads again")
	eq(#M.errors, 0, "no errors on the server: " .. table.concat(M.errors, " | "))

	-- ------------------------------------------------------- the client, no Z-City and no mod
	fresh()
	local C = dofile(testdir .. "/gmod_mock.lua")("client")
	C.luaroot = luaroot
	-- the folder of the addon, as it lies in garrysmod/addons, with materials nobody names
	C.files["addons/zcity_csgo_gloves/lua/autorun/zcity_csgo_gloves.lua"] = true
	C.files["addons/zcity_csgo_gloves/materials/models/humans/male/group01/loose_sheet.vmt"] = true
	C.files["addons/zcity_csgo_gloves/materials/models/humans/male/group01/loose_sheet.vtf"] = true
	C.files["addons/zcity_csgo_gloves/materials/models/humans/female/group02/other_sheet.vmt"] = true
	C.files["addons/zcity_csgo_gloves/materials/models/any/folder/van_facemap_new.vmt"] = true
	-- the content of the addon itself: the gloves, their arms, their icons - nothing to wear
	C.files["addons/zcity_csgo_gloves/materials/zcity_csgo_gloves/icons/moto_1.vmt"] = true
	C.files["addons/zcity_csgo_gloves/materials/models/weapons/v_models/arms/glove_slick/left.vmt"] = true
	-- the list sort_content.bat writes on the computer of the owner, and the build ships
	C.luafiles["zcity_csgo_gloves/sh_found.lua"] = [[ZCGloves.Found = {
		"models/humans/male/group01/loose_sheet",
		"models/humans/female/group02/other_sheet",
		"packs/thrown/sheet_77",
		"props/crate",
	}]]

	include("autorun/!zcity_csgo_gloves.lua")
	include("autorun/zcity_csgo_gloves.lua")
	eq(ZCGloves.LoadErrors, nil, "every file of the addon loaded on the client: "
		.. tostring(ZCGloves.LoadErrors and ZCGloves.LoadErrors[1] or ""))
	eq(ZCGloves.FindAddonFolder(), "addons/zcity_csgo_gloves", "the folder of the addon is found")
	-- the pack of the owner for the masks of Z-City lies in lua/autorun as well: its hooks come
	-- after ours, it writes the place of the masks itself, and this addon leaves what it wrote alone
	dofile(testdir .. "/packs/zc_balaclava.lua")
	check(concommand.list["zcb_debug"] ~= nil, "the command of the pack is there next to ours")
	hook.Run("InitPostEntity")
	check(ZCO.Installed == true and ZCO.Theirs == false, "the own appearance system is there")
	local accessories = hg.Accessories
	check(type(accessories) == "table", "the accessories of the catalog are in the tables of the game")
	eq(accessories["arctic_balaclava"].placement, "face", "the pack of the masks wrote their place itself")
	eq(accessories["arctic_balaclava"].disallowinappearance, nil,
		"... and took them out of the ones that are not offered")
	eq(accessories["phoenix_balaclava"].placement, "face", "... for both of them")
	eq(accessories["pink earmuffs"].placement, nil, "the pink earmuffs came without a place")

	local found, cut = ZCGloves.ScanContent(true)
	eq(found, 3, "the materials of the addon that no Lua names are found by the addon itself")
	eq(cut, false, "... and the walk went through every folder of it")
	local listed = {}
	for _, path in ipairs(ZCGloves.FoundScan or {}) do listed[path] = true end
	check(listed["models/humans/male/group01/loose_sheet"], "a material in a folder of clothes is on the list")
	check(listed["models/any/folder/van_facemap_new"], "... and a face of a model")
	check(not listed["zcity_csgo_gloves/icons/moto_1"], "the icons of the gloves themselves are not content")
	check(not listed["models/weapons/v_models/arms/glove_slick/left"],
		"the arms inside the glove models are not content either")
	check(not listed["models/humans/male/group01/loose_sheet.vtf"], "only the .vmt of a material is looked at")
	-- a material the tables name is not content nobody names: one of the catalog, in the same folder
	local namedName, named = next(ZCO.Clothes(1))
	C.files["addons/zcity_csgo_gloves/materials/" .. named .. ".vmt"] = true
	found = ZCGloves.ScanContent(true)
	listed = {}
	for _, path in ipairs(ZCGloves.FoundScan or {}) do listed[path] = true end
	eq(found, 3, "a material the tables name is not on the list (" .. tostring(namedName) .. ")")
	check(not listed[named], "... and it is not looked at twice")
	eq(ZCGloves.ScanContent(), 3, "a second scan without force does not walk the folders again")

	-- the list of sort_content.bat and the one of the scan are one list, without a path twice
	eq(#ZCGloves.Found, 4, "the list sort_content.bat wrote is read")
	eq(#ZCGloves.FoundAll(), 5, "both lists are worked through, a material of both of them once")
	local total, made = ZCGloves.FoundApply()
	check(total >= 2 and made >= 2, "the materials of both lists are in the menu: " .. total .. " entries, "
		.. made .. " of them made by this call")
	local APc = hg.Appearance
	eq(APc.Clothes[1]["loose_sheet"], "models/humans/male/group01/loose_sheet",
		"a material in a folder of clothes for men is clothes for men")
	eq(APc.Clothes[2]["loose_sheet"], nil, "... and not for women")
	eq(APc.Clothes[2]["other_sheet"], "models/humans/female/group02/other_sheet",
		"a sheet in a folder of clothes for women is clothes for women")
	local again, madeAgain = ZCGloves.FoundApply()
	check(again == total and madeAgain == 0, "a second pass through the list changes nothing: "
		.. tostring(again) .. ", " .. tostring(madeAgain))
	-- switched off: what this addon put in the menu is taken out again
	C.setConVar("zcg_found_content", "0")
	eq(ZCGloves.FoundApply(), 0, "zcg_found_content 0: nothing is in the menu")
	eq(APc.Clothes[1]["loose_sheet"], nil, "... and the clothes it made are gone")
	C.setConVar("zcg_found_content", "1")
	check(ZCGloves.FoundApply() == total, "switched on again: they are back")

	-- the accessories whose packs forgot the place they are worn on: no menu of Z-City lists an
	-- accessory without it, so it draws on the player and there is no button to take it off with
	check(accessories["green earmuffs"].placement == "ears", "the other earmuffs have one")
	C.advance(2) -- the watch of this addon looks again a second after the game has started
	eq(accessories["pink earmuffs"].placement, "ears",
		"the pink earmuffs get the place of the earmuffs that wear the same model")
	eq(accessories["terrorist_band"].placement, "spine", "an armband gets the place its name says")
	check(ZCGloves.PlacementAdded["pink earmuffs"] == "ears", "what was filled in here is remembered")
	eq(ZCGloves.PlacementAdded["arctic_balaclava"], nil, "what a pack wrote is not counted as ours")
	check(accessories["baseball cap"].placement == "head", "a place a pack wrote is left alone")
	local healed, took = ZCGloves.HealAccessories()
	eq(healed, 0, "a second pass finds nothing left to fill in")
	eq(took, 0, "... and takes nothing back")
	local said = false
	for _, line in ipairs(C.log) do
		if string.find(line, "accessories without a place", 1, true) then said = true end
	end
	check(said, "the console says what was filled in for them")

	-- an accessory of a pack that forgot everything but the model it wears
	accessories["pack_balaclava"] = { name = "Pack Balaclava", model = "models/pack/mask.mdl" }
	accessories["pack_cap"] = { name = "Pack Cap", model = "models/pack/head/baseballcap.mdl" }
	accessories["pack_thing"] = { name = "Pack Thing", model = "models/pack/thing.mdl" }
	healed = ZCGloves.HealAccessories()
	eq(healed, 2, "the words of a model and of a name say where it is worn on: " .. healed .. " of them")
	eq(accessories["pack_balaclava"].placement, "face", "a mask goes on the face")
	eq(accessories["pack_cap"].placement, "head", "a cap goes on the head")
	eq(accessories["pack_thing"].placement, nil, "a thing nobody knows of gets no place made up")

	-- zcg_fix_placement 0: what this addon filled in is taken back, what packs wrote stays
	C.setConVar("zcg_fix_placement", "0")
	healed, took = ZCGloves.HealAccessories()
	eq(healed, 0, "zcg_fix_placement 0: nothing is filled in")
	check(took >= 3, "... and what was filled in is taken back: " .. took .. " of them")
	eq(accessories["pink earmuffs"].placement, nil, "the earmuffs are as their pack made them again")
	eq(accessories["pack_balaclava"].placement, nil, "... the accessory a pack brought without a place")
	eq(accessories["arctic_balaclava"].placement, "face", "the place the pack of Z-City wrote stays")
	C.setConVar("zcg_fix_placement", "1")
	healed = ZCGloves.HealAccessories()
	check(healed >= 3, "switched on again: they get their place back (" .. healed .. ")")

	-- a pack that registers its content on the client, after the game has started
	AppAddModel("Pack Male 01", "models/pack/m/male_01.mdl", false, {
		main = "models/humans/male/group01/players_sheet" })
	AppAddClothes(1, "Pack Jacket", "pack/clothes/jacket", "A jacket of the pack")
	AppAddBodygroup("HANDS", "Pack Gloves", "packgloves_M", false, false, false, 0)
	ZCO.Harvest()
	eq(ZCO.Clothes(1)["Pack Jacket"], "pack/clothes/jacket", "the catalog took the clothes of the pack in")

	-- the menu of the addon: a button for the clothes that were found, for the models and the
	-- bodygroups of the packs, and for the accessories by the place they are worn on
	ZCGloves.FoundApply()
	ZCO.Harvest()
	local look = { AModel = "Male 01", AClothes = { main = "normal" }, AName = "Пак",
		AColor = Color(1, 2, 3), AAttachments = {}, ABodygroups = {}, AFacemap = "Default" }
	local function has(items, value)
		for _, item in ipairs(items) do
			if item.value == value then return item end
		end
		return nil
	end
	local models = ZCO.Menu.Items("model", look)
	check(#models >= 10, "the menu has a button for every model of the sex: " .. #models)
	check(has(models, "Pack Male 01") ~= nil, "... and for the model a pack registered")
	check(count(ZCO.Models(1)) + count(ZCO.Models(2)) >= 20,
		"the models of both sexes: " .. count(ZCO.Models(1)) .. " and " .. count(ZCO.Models(2)))
	local clothes = ZCO.Menu.Items("main", look)
	check(#clothes >= 50, "the menu has a button for every piece of clothing: " .. #clothes)
	local jacket = has(clothes, "Pack Jacket")
	check(jacket ~= nil, "... for the clothes a pack registered")
	eq(jacket and jacket.hint, "A jacket of the pack", "... with the description the pack gave")
	local loose = has(clothes, "loose_sheet")
	check(loose ~= nil, "the menu has a button for the clothes that were found in the folder of the addon")
	eq(loose and loose.material, "models/humans/male/group01/loose_sheet", "... which shows their material")
	local attach = ZCO.Menu.Items("attach", look)
	local earmuffs = has(attach, "pink earmuffs")
	check(earmuffs ~= nil, "the menu has a button for the accessory that got its place")
	eq(earmuffs and earmuffs.placement, "ears", "... in the place it is worn on")
	check(has(attach, "arctic_balaclava") ~= nil, "... and for the mask the patch of the pack let in")
	check(has(attach, "pack_balaclava") ~= nil, "... and for the accessory a pack of its own brought")
	local hands = ZCO.Menu.Items("HANDS", look)
	check(has(hands, "Pack Gloves") ~= nil, "... and for the gloves a pack registered")
	local places, order, seen = {}, {}, {}
	for _, item in ipairs(attach) do
		places[item.placement] = (places[item.placement] or 0) + 1
		if not seen[item.placement] then
			seen[item.placement] = true
			order[#order + 1] = item.placement
		end
	end
	check(places.head ~= nil and places.face ~= nil and places.ears ~= nil and places.spine ~= nil,
		"the accessories are listed by the places of Z-City: head, face, ears, spine")
	eq(order[1], "head", "the places are listed in the order of Z-City, head first: " .. table.concat(order, ", "))

	-- the commands of the console are there on the client as well
	check(concommand.list["zcg_register_cl"] ~= nil, "zcg_register names what the packs registered")
	check(concommand.list["zcg_found_scan_cl"] ~= nil, "zcg_found_scan looks through the materials by hand")
	check(concommand.list["zcg_found_list_cl"] ~= nil, "zcg_found_list names what is in the menu")
	lines = {}
	ZCGloves.AccessoryReport(function(text) lines[#lines + 1] = text end)
	check(#lines == 1 and string.find(lines[1], "accessories without the place", 1, true) ~= nil
		and string.find(lines[1], "pink earmuffs (ears)", 1, true) ~= nil,
		"zcg_content tells what it did for the accessories: " .. tostring(lines[1]))
	lines = {}
	ZCGloves.FoundReport(function(text) lines[#lines + 1] = text end)
	check(#lines == 1 and string.find(lines[1], "sort_content.bat listed ", 1, true) ~= nil
		and string.find(lines[1], "sort_content.bat listed 4 of them", 1, true) ~= nil
		and string.find(lines[1], "this addon found 3 more in its own materials/", 1, true) ~= nil
		and string.find(lines[1], "loose_sheet", 1, true) == nil,
		"... and where the content without Lua came from: " .. tostring(lines[1]))
	eq(#C.errors, 0, "no errors on the client: " .. table.concat(C.errors, " | "))

	-- ------------------------------------------------------- the server, Z-City in place
	fresh()
	local S = dofile(testdir .. "/gmod_mock.lua")("server")
	S.luaroot = luaroot
	local Z = dofile(testdir .. "/zcity_mock.lua")(S)
	Z.install()
	local theirs = hg.Appearance
	local theirModel = theirs.PlayerModels[1]["Male 01"]
	include("autorun/!zcity_csgo_gloves.lua")
	check(type(AppAddModel) == "function", "the API is there on a server of Z-City as well")
	AppAddClothes(1, "Pack Jacket", "pack/clothes/jacket")
	check(not ZCGloves.RegisteredOnly(hg.Appearance),
		"the tables of Z-City are not only what came through this addon")
	include("autorun/zcity_csgo_gloves.lua")
	eq(ZCGloves.LoadErrors, nil, "every file of the addon loaded: "
		.. tostring(ZCGloves.LoadErrors and ZCGloves.LoadErrors[1] or ""))
	hook.Run("InitPostEntity")
	check(ZCO.Theirs == true, "the appearance system of Z-City is told from the content of a pack")
	check(ZCO.MadeTables == false, "... and its tables are left to it")
	check(theirs.PlayerModels[1]["Male 01"] == theirModel, "the model of Z-City is untouched")
	eq(theirs.Clothes[1]["Pack Jacket"], "pack/clothes/jacket",
		"what a pack registered through this addon is in the tables of Z-City")
	eq(ZCO.Catalog.Clothes[1]["Pack Jacket"], "pack/clothes/jacket", "... and in the catalog of this addon")
	eq(#S.errors, 0, "no errors: " .. table.concat(S.errors, " | "))

	return checks, failures
end
