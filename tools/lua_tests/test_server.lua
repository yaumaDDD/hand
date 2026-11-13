-- Server-side scenarios. Returns function(testdir, luaroot) -> number of checks, list of failures.

return function(testdir, luaroot)
	local checks, failures = 0, {}
	local function check(cond, what)
		checks = checks + 1
		if not cond then failures[#failures + 1] = what end
	end
	local function eq(got, want, what)
		check(got == want, what .. ": got " .. tostring(got) .. ", expected " .. tostring(want))
	end

	local M = dofile(testdir .. "/gmod_mock.lua")("server")
	local Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot

	-- the addon content is installed on the server
	local models = {
		"v_glove_bloodhound", "v_glove_bloodhound_fingerless_brokenfang", "v_glove_bloodhound_fingerless_hydra",
		"v_glove_handwrap_leathery", "v_glove_fingerless", "v_glove_motorcycle", "v_glove_ct_hardknuckle",
		"v_glove_ct_hardknuckle_black", "v_glove_ct_hardknuckle_blue", "v_glove_fullfinger",
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
	M.files["materials/models/weapons/v_models/arms/glove_motorcycle/right/1/glove_motorcycle_right.vtf"] = true
	M.files["materials/models/weapons/v_models/arms/bare/unrelated.vmt"] = true

	-- ---------------------------------------------------------------- loading before Z-City
	include("autorun/zcity_csgo_gloves.lua")
	local ZCG = ZCGloves
	check(ZCG ~= nil, "ZCGloves table exists")
	eq(#ZCG.Variants, 81, "number of gloves")
	eq(#ZCG.Families, 11, "number of glove families")
	eq(ZCG.Ready, nil, "not registered while Z-City is missing")
	eq(#M.csfiles, 10, "files sent to clients")
	eq(#util.precached, 13, "precached models")
	eq(#resource.files, 0, "nothing in FastDL by default")
	eq(#resource.workshop, 0, "no workshop download by default")

	local ids, names = {}, {}
	for _, v in ipairs(ZCG.Variants) do
		check(not ids[v.id], "unique id " .. v.id)
		check(not names[v.name], "unique name " .. v.name)
		ids[v.id], names[v.name] = true, true
		check(ZCG.Models[v.model] ~= nil, "model info for " .. v.id)
		check(M.files[v.model] == true, "model file known for " .. v.id)
		check(v.name:sub(1, 6) == "CS:GO ", "name prefix of " .. v.id)
	end

	do -- Sport (1.3.0): thirteen closed gloves, the thirteen bodies of one model
		local SPORT = "models/zcity_csgo_gloves/v_glove_sporty.mdl"
		local count = 0
		for _, v in ipairs(ZCG.Variants) do
			if v.family.id == "sport" then
				count = count + 1
				eq(v.id, "sport_" .. count, "id of Sport glove " .. count)
				eq(v.name, string.format("CS:GO Sport %02d", count), "name of Sport glove " .. count)
				eq(v.model, SPORT, "model of Sport glove " .. count)
				eq(v.body, count - 1, "body of Sport glove " .. count)
				check(v.mats == nil, "no material is swapped for Sport glove " .. count)
				eq(v.family.fingerless, false, "Sport glove " .. count .. " is a closed one")
			end
		end
		eq(count, 13, "Sport gloves")
		check(ZCG.ByID.sport_13 ~= nil and ZCG.ByName["CS:GO Sport 13"] == ZCG.ByID.sport_13, "a Sport glove is found by id and by name")
	end

	M.advance(3)
	eq(ZCG.Ready, nil, "still waiting for Z-City")
	eq(#M.errors, 0, "no errors while waiting")

	-- ---------------------------------------------------------------- Z-City appears
	Z.install()
	M.advance(1.2)
	eq(ZCG.Ready, true, "registered once Z-City exists")

	local hands = hg.Appearance.Bodygroups.HANDS
	for sex = 1, 2 do
		eq(table.Count(hands[sex]), 3 + 81, "entries in HANDS[" .. sex .. "]")
		local entry = hands[sex]["CS:GO Moto 05"]
		check(entry ~= nil, "moto 05 registered for sex " .. sex)
		eq(entry[1], "hands", "our gloves keep the bare hands submodel")
		eq(entry[2], false, "our gloves are free")
		eq(entry.ID, "zcg_moto_5", "pointshop id")
		eq(entry.ZCG, "moto_5", "marker")
		eq(hands[sex]["Gloves"].ID, "Standard_BodyGroups_Gloves", "stock gloves untouched")
		eq(hands[sex]["None"][1], "hands", "None untouched")
	end

	-- ---------------------------------------------------------------- players
	local function appearance(model, glove)
		return { AModel = model, AClothes = { main = "normal" }, AAttachments = {}, ABodygroups = { HANDS = glove } }
	end

	local alice = M.newPlayer("alice")
	local bob = M.newPlayer("bob")
	local carol = M.newPlayer("carol")
	local dave = M.newPlayer("dave")
	local erin = M.newPlayer("erin") -- no appearance applied yet

	Z.applyAppearance(alice, appearance("Male 01", "CS:GO Moto 05"))
	Z.applyAppearance(bob, appearance("Male 01", nil))
	Z.applyAppearance(carol, appearance("Female 01", "Gloves"))
	Z.applyAppearance(dave, appearance("Male 01", "CS:GO Hydra 02"))
	dave:SetModel(Z.COMBINE) -- a player class replaced the model and kept the appearance

	M.advance(0.5)
	eq(alice:GetNWString("zcg_glove"), "moto_5", "alice wears moto 5")
	eq(bob:GetNWString("zcg_glove"), "none", "bob wears nothing")
	eq(carol:GetNWString("zcg_glove"), "none", "a stock glove is not ours")
	eq(dave:GetNWString("zcg_glove"), "none", "no glove on a class model")
	eq(erin:GetNWString("zcg_glove"), "none", "no appearance, no glove")

	local writes = alice.nwWrites
	M.advance(5)
	eq(alice.nwWrites, writes, "the networked value is only written when it changes")

	-- the model check is not case sensitive
	alice:SetModel("Models/ZCity/M/Male_01.MDL")
	M.advance(0.5)
	eq(alice:GetNWString("zcg_glove"), "moto_5", "model comparison ignores case")
	alice:SetModel(Z.MALE)

	M.setConVar("zcg_any_model", 1)
	M.advance(0.5)
	eq(dave:GetNWString("zcg_glove"), "hydra_2", "zcg_any_model 1 shows gloves on class models")
	M.setConVar("zcg_any_model", 0)
	M.advance(0.5)
	eq(dave:GetNWString("zcg_glove"), "none", "zcg_any_model 0 again")

	-- a new appearance
	Z.applyAppearance(bob, appearance("Male 01", "CS:GO Hand Wraps 12"))
	Z.applyAppearance(alice, appearance("Female 01", "CS:GO Leather"))
	M.advance(0.5)
	eq(bob:GetNWString("zcg_glove"), "handwrap_12", "bob picked hand wraps")
	eq(alice:GetNWString("zcg_glove"), "leather_1", "alice picked leather")

	-- restriction hook
	hook.Add("ZCityCSGOGloves_CanWear", "test", function(ply, variant)
		if variant.family.id == "handwrap" then return false end
	end)
	M.advance(0.5)
	eq(bob:GetNWString("zcg_glove"), "none", "CanWear hook forbids hand wraps")
	eq(alice:GetNWString("zcg_glove"), "leather_1", "CanWear hook leaves the others alone")
	hook.Remove("ZCityCSGOGloves_CanWear", "test")
	M.advance(0.5)
	eq(bob:GetNWString("zcg_glove"), "handwrap_12", "hand wraps are back")

	-- unknown / broken data must not raise errors
	local frank = M.newPlayer("frank")
	frank.CurAppearance = { AModel = "Deleted Model", ABodygroups = { HANDS = "CS:GO Moto 01" } }
	local gina = M.newPlayer("gina")
	gina.CurAppearance = { AModel = "Male 01", ABodygroups = "broken" }
	local hank = M.newPlayer("hank")
	hank.CurAppearance = { AModel = "Male 01", ABodygroups = { HANDS = 5 } }
	hank:SetModel(Z.MALE)
	M.advance(0.5)
	eq(frank:GetNWString("zcg_glove"), "none", "unknown appearance model")
	eq(gina:GetNWString("zcg_glove"), "none", "broken ABodygroups")
	eq(hank:GetNWString("zcg_glove"), "none", "non-string glove name")
	do -- bodies of the menu on a model that names them differently (2.13.0)
		local AP = hg.Appearance
		local LEG = "models/zcity/m/legacy_guy.mdl"
		M.models[LEG] = { materials = M.models[Z.MALE].materials, bones = M.models[Z.MALE].bones, bodygroups = {
			{ "Sheet", { "sheet_m.smd", "sheet_tshirt.smd", "sheet_hood_m.smd" } },
			{ "pants", { "pants_m", "pants_wide_m" } },
			{ "shoes", { "shoes_m", "shoes_02_f" } },
			{ "hands", { "hands.smd", "reggloves_FIN_M.smd" } },
		} }
		AP.PlayerModels[1]["Legacy Guy"] = { mdl = LEG, submatSlots = {}, sex = false }
		local kept = { sheet = AP.Bodygroups.sheet, pants = AP.Bodygroups.pants, shoes = AP.Bodygroups.shoes }
		AP.Bodygroups.sheet = { [1] = { ["Standard"] = { "sheet_m" }, ["T-Shirt"] = { "sheet_tshirt_m" }, ["Hoodie"] = { "sheet_hood_m" }, ["Odessa"] = { "sheet_odessa_m" } } }
		AP.Bodygroups.pants = { [1] = { ["Wide"] = { "pants_wide_m" } } }
		AP.Bodygroups.shoes = { [1] = { ["Sneakers"] = { "shoes_02_m" } } }
		local leg = M.newPlayer("leg", LEG)
		leg.CurAppearance = { AModel = "Legacy Guy", ABodygroups = { sheet = "T-Shirt", pants = "Wide", shoes = "Sneakers" } }
		leg:SetBodygroup(1, 1) -- (Z-City did this one itself: exact names)
		M.advance(0.5)
		eq(leg:GetBodygroup(0), 1, "the T-shirt goes on a model that calls it Sheet / sheet_tshirt.smd")
		eq(leg:GetBodygroup(1), 1, "what Z-City put on by exact name stays")
		eq(leg:GetBodygroup(2), 1, "shoes_02_m is found as shoes_02_f")
		leg:SetBodygroup(0, 2)
		M.advance(0.5)
		eq(leg:GetBodygroup(0), 2, "done once for an appearance: what is changed afterwards (a player class) is left alone")
		leg.CurAppearance = { AModel = "Legacy Guy", ABodygroups = { sheet = "Odessa" } }
		leg:SetBodygroup(0, 0)
		M.advance(0.5)
		eq(leg:GetBodygroup(0), 0, "a body the model does not have at all: nothing is done")
		leg.CurAppearance = { AModel = "Legacy Guy", ABodygroups = { sheet = "Hoodie" } }
		M.setConVar("zcg_fix_bodies", 0)
		M.advance(0.5)
		eq(leg:GetBodygroup(0), 0, "zcg_fix_bodies 0: only by exact name, as Z-City does")
		M.setConVar("zcg_fix_bodies", 1)
		leg.CurAppearance = { AModel = "Legacy Guy", ABodygroups = { sheet = "Hoodie" } }
		M.advance(0.5)
		eq(leg:GetBodygroup(0), 2, "zcg_fix_bodies 1 again: the hoodie is on")
		-- (2.15.2) a glove of Z-City on a model that names its part with ".smd": Z-City cannot put it on
		leg.CurAppearance = { AModel = "Legacy Guy", ABodygroups = { HANDS = "Gloves" } }
		M.advance(0.5)
		eq(leg:GetBodygroup(3), 1, "the glove of Z-City goes on a model that calls it reggloves_FIN_M.smd")
		eq(leg:GetNWString("zcg_glove"), "none", "and no CS:GO glove with it")
		leg.CurAppearance = { AModel = "Legacy Guy", ABodygroups = { HANDS = "CS:GO Moto 05" } }
		M.advance(0.5)
		eq(leg:GetBodygroup(3), 0, "a CS:GO glove: the bare hands are back under it")
		eq(leg:GetNWString("zcg_glove"), "moto_5", "and the CS:GO glove is told")
		leg:SetModel(Z.COMBINE)
		leg.CurAppearance = { AModel = "Legacy Guy", ABodygroups = { sheet = "T-Shirt" } }
		M.advance(0.5)
		check(true, "another model than the one of the appearance: no error")
		AP.Bodygroups.sheet, AP.Bodygroups.pants, AP.Bodygroups.shoes = kept.sheet, kept.pants, kept.shoes
		AP.PlayerModels[1]["Legacy Guy"] = nil
	end
	do -- the older body groups (TORSO, LEGS) for the windows of the Appearance Mod (2.14.0)
		local AP = hg.Appearance
		local OLD = "models/zcityadodser/m/old_guy.mdl"
		M.models[OLD] = { materials = M.models[Z.MALE].materials, bones = M.models[Z.MALE].bones, bodygroups = {
			{ "torso", { "male_standart_top.smd", "male_standart_tshirt.smd", "male_odessa_jacket.smd" } },
			{ "legs", { "male_reference_bottom.smd", "male_reference_boots.smd", "male_reference_bottom_shorts.smd", "male_reference_boots_wider.smd" } },
		} }
		AP.PlayerModels[1]["Old Guy"] = { mdl = OLD, submatSlots = {}, sex = false }
		local keptTorso, keptLegs = AP.Bodygroups.TORSO, AP.Bodygroups.LEGS
		AP.Bodygroups.TORSO = { [1] = { ["Standard Top"] = { "male_standart_top.smd" }, ["T-Shirt"] = { "male_standart_tshirt.smd" },
			["Robotic Arm"] = { "male_robotic_arm.smd" }, ["Odessa Jacket"] = { "male_odessa_jacket.smd" } },
			[2] = { ["Mossman Jacket"] = { "female_mossman_jacket.smd" } } }
		AP.Bodygroups.LEGS = { [1] = { ["Standard Bottom"] = { "male_reference_bottom.smd" }, ["Boots"] = { "male_reference_boots.smd" },
			["Shorts"] = { "male_reference_bottom_shorts.smd" }, ["Boots Wider"] = { "male_reference_boots_wider.smd" } } }
		local old = M.newPlayer("old", OLD)
		local app = { AModel = "Old Guy", ABodygroups = {} }
		local function names(list)
			local out = {}
			for i, item in ipairs(list) do out[i] = item.name .. "=" .. item.index end
			return table.concat(out, ", ")
		end
		local items, has = ZCG.LegacyParts("main", old, app)
		eq(names(items), "Odessa Jacket=2, Standard Top=0, T-Shirt=1", "jacket window: the TORSO parts this model has, by name")
		eq(has, true, "the model has the group")
		eq(items[1].key, "TORSO", "chosen under the name of the group in the list")
		eq(names((ZCG.LegacyParts("pants", old, app))), "Boots=1, Boots Wider=3, Shorts=2, Standard Bottom=0", "pants window: all of LEGS")
		eq(names((ZCG.LegacyParts("boots", old, app))), "Boots=1, Boots Wider=3", "boots window: the boots of LEGS")
		local none, hasNone = ZCG.LegacyParts("main", M.newPlayer("plain", Z.MALE), { AModel = "Male 01", ABodygroups = {} })
		eq(#none, 0, "a model without such a group: nothing")
		eq(hasNone, false, "... and it is said so")
		-- chosen: the server puts it on although the group is called "torso" there
		old.CurAppearance = { AModel = "Old Guy", ABodygroups = { TORSO = "T-Shirt", LEGS = "Shorts" } }
		M.advance(0.5)
		eq(old:GetBodygroup(0), 1, "TORSO = T-Shirt is on")
		eq(old:GetBodygroup(1), 2, "LEGS = Shorts is on")
		AP.Bodygroups.TORSO, AP.Bodygroups.LEGS = keptTorso, keptLegs
		AP.PlayerModels[1]["Old Guy"] = nil
	end
	-- an appearance whose AModel is a raw model path (Z-City allows that)
	frank.CurAppearance.AModel = Z.COMBINE
	frank:SetModel(Z.COMBINE)
	M.advance(0.5)
	eq(frank:GetNWString("zcg_glove"), "moto_1", "raw model path as appearance model")

	-- ---------------------------------------------------------------- ragdolls
	local function ragdollOf(ply)
		local ragdoll = M.newEntity("prop_ragdoll", ply:GetModel())
		ragdoll.CurAppearance = ply.CurAppearance
		ragdoll:SetNWEntity("ply", ply)
		hook.Run("Ragdoll_Create", ply, ragdoll)
		return ragdoll
	end

	-- knocked down: the ragdoll follows its living owner
	local rag = ragdollOf(bob)
	bob.FakeRagdoll = rag
	eq(rag:GetNWString("zcg_glove"), "handwrap_12", "ragdoll gets the glove at creation")
	Z.applyAppearance(bob, appearance("Male 01", "CS:GO Moto 01"))
	M.advance(0.5)
	eq(rag:GetNWString("zcg_glove"), "moto_1", "the ragdoll of a living player follows him")

	-- death: the body keeps what the player wore
	bob.alive = false
	bob.FakeRagdoll = nil
	Z.applyAppearance(bob, appearance("Male 01", nil))
	bob.alive = true
	M.advance(0.5)
	eq(bob:GetNWString("zcg_glove"), "none", "respawned without gloves")
	eq(rag:GetNWString("zcg_glove"), "moto_1", "the dead body keeps its gloves")

	-- a glove picked right before the ragdoll appears (no poll in between)
	Z.applyAppearance(carol, appearance("Female 01", "CS:GO Broken Fang 03"))
	local rag2 = ragdollOf(carol)
	eq(rag2:GetNWString("zcg_glove"), "brokenfang_3", "ragdoll created before the next poll")
	eq(carol:GetNWString("zcg_glove"), "brokenfang_3", "and the player was updated too")

	-- a ragdoll of somebody without gloves, and one made from a non-player
	local rag3 = ragdollOf(erin)
	eq(rag3:GetNWString("zcg_glove"), "none", "ragdoll without gloves")
	local npc = M.newEntity("npc_citizen", Z.MALE)
	local rag4 = M.newEntity("prop_ragdoll", Z.MALE)
	hook.Run("Ragdoll_Create", npc, rag4)
	eq(rag4:GetNWString("zcg_glove"), "none", "ragdoll of a non-player")
	hook.Run("Ragdoll_Create", NULL, rag4)
	hook.Run("Ragdoll_Create", alice, NULL)

	-- a dead player's old ragdoll must not be driven by another owner
	local rag5 = ragdollOf(alice)
	bob.FakeRagdoll = rag5 -- not his ragdoll
	M.advance(0.5)
	eq(rag5:GetNWString("zcg_glove"), "leather_1", "only the owner updates a ragdoll")
	bob.FakeRagdoll = nil

	-- ---------------------------------------------------------------- the table is rebuilt
	hands[1] = { ["None"] = { "hands", false } }
	hands[2]["CS:GO Moto 05"] = nil
	M.advance(21)
	eq(table.Count(hands[1]), 1 + 81, "re-registered after a rebuild")
	check(hands[2]["CS:GO Moto 05"] ~= nil, "single missing entry restored")

	-- ---------------------------------------------------------------- status command
	M.log = {}
	M.command("zcg_status", NULL)
	check(#M.log >= 2, "zcg_status prints something")
	check(M.log[1]:find("zcg_hide_hands 1, zcg_fingers 1", 1, true) ~= nil, "zcg_status shows the settings that are the server's")
	local found = false
	for _, line in ipairs(M.log) do
		if line:find("alice", 1, true) and line:find("leather_1", 1, true) then found = true end
	end
	check(found, "zcg_status lists the players")
	local n = #M.log
	M.command("zcg_status", bob)
	eq(#M.log, n, "zcg_status is for super admins")
	bob.superadmin = true
	M.command("zcg_status", bob)
	check(#M.log > n, "super admins may use zcg_status")

	-- ---------------------------------------------------------------- a material is not installed
	-- (a listen server has the files of the player: the game leaves a missing material out of
	-- Entity:GetMaterials there as well, and Z-City counts in that list when it dresses a player)
	do
		local SLAV = "models/slav/m/male_10.mdl"
		M.installModel(SLAV, { "players_sheet", "hair", "pants", "cross", "hands" },
			{ "models/humans/slav/", "models/humans/male/group01/", "distac/gloves/" }, nil)
		for _, name in ipairs({ "models/humans/male/group01/players_sheet", "distac/gloves/pants", "distac/gloves/cross", "distac/gloves/hands" }) do
			M.files["materials/" .. name .. ".vmt"] = true
		end
		hg.Appearance.PlayerModels[1]["Male 10"] = {
			mdl = SLAV, sex = false,
			submatSlots = { main = "models/humans/male/group01/players_sheet", pants = "distac/gloves/pants",
				boots = "distac/gloves/cross", hands = "distac/gloves/hands" },
		}
		local CLOTHES = hg.Appearance.Clothes[1].normal
		local erin = M.newPlayer("erin", SLAV)
		eq(#ZCG.EngineGetMaterials(erin), 4, "(the imitation: the game names four of the five materials)")
		eq(#erin:GetMaterials(), 5, "server: Entity:GetMaterials names every material of the model")
		Z.applyAppearance(erin, appearance("Male 10", nil))
		eq(erin:GetSubMaterial(0), CLOTHES, "server: the jacket is on the jacket")
		eq(erin:GetSubMaterial(1), "", "server: nothing on the material that is not installed")
		eq(erin:GetSubMaterial(2), CLOTHES, "server: the trousers on the trousers")
		eq(erin:GetSubMaterial(3), CLOTHES, "server: the boots on the boots")
		eq(erin:GetSubMaterial(4), CLOTHES, "server: the hands on the hands")

		-- CompleteMaterialList = false: the list of the game, with its gaps
		ZCG.Config.CompleteMaterialList = false
		include("zcity_csgo_gloves/sh_materials.lua")
		eq(#erin:GetMaterials(), 4, "CompleteMaterialList = false leaves Entity:GetMaterials as the game made it")
		eq(M.entityMeta.GetMaterials, ZCG.EngineGetMaterials, "the function of the game is back")
		eq(#ZCG.MaterialList(erin), 5, "the addon itself still knows the whole list")
		ZCG.Config.CompleteMaterialList = true
		include("zcity_csgo_gloves/sh_materials.lua")
		eq(#erin:GetMaterials(), 5, "and it can be switched on again")
		include("zcity_csgo_gloves/sh_materials.lua")
		eq(#ZCG.EngineGetMaterials(erin), 4, "loading the file again does not wrap the function twice")

		-- the server console is told about the materials too
		M.log = {}
		M.command("zcg_content", NULL)
		local listed = false
		for _, line in ipairs(M.log) do
			if line:find("materials/models/humans/slav/hair.vmt  <-  material of " .. SLAV, 1, true) then listed = true end
		end
		check(listed, "zcg_content on the server lists the material a model lacks")

		-- what the clothing Lua of the addon adds (ZCG.Bound, written by the build): the server
		-- has its own side of the list
		ZCG.Bound = { ["homigrad/new_appearance/sh_shared_pack.lua"] = {
			{ "PlayerModels/1/Male 10", SLAV },
			{ "Clothes/1/of the server", "models/x/server", 1 },
			{ "Clothes/1/of the clients", "models/x/client", 2 },
		} }
		local count, missing = ZCG.BoundMissing()
		eq(count .. " " .. #missing, "2 1", "bound on the server: its entries, without those of the clients")
		eq(missing[1].entry, "Clothes/1/of the server", "bound on the server: the one that is not there")
		M.log = {}
		M.command("zcg_content", NULL)
		local told = 0
		for _, line in ipairs(M.log) do
			if line:find("1 of the 2 clothes, faces, models and accessories it adds are NOT in the appearance tables", 1, true) then told = told + 1 end
		end
		eq(told, 1, "zcg_content in the server console tells about it")
		M.log = {}
		hook.Run("InitPostEntity")
		M.advance(66)
		told = 0
		for _, line in ipairs(M.log) do
			if line:find("are not in the appearance tables of the server - type zcg_content", 1, true) then told = told + 1 end
		end
		eq(told, 1, "and the server console gets one line after the start")
		ZCG.Bound = nil

		erin:Remove()
		hg.Appearance.PlayerModels[1]["Male 10"] = nil
	end

	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	-- ---------------------------------------------------------------- content options
	local function reload(config)
		util.precached, resource.files, resource.workshop = {}, {}, {}
		timer.list = {}
		M.log = {}
		ZCGloves = nil
		include("autorun/zcity_csgo_gloves.lua")
		for k, v in pairs(config) do ZCGloves.Config[k] = v end
		-- sv_core reads the content settings while loading: run it again with the new settings
		util.precached, resource.files, resource.workshop = {}, {}, {}
		M.log = {}
		include("zcity_csgo_gloves/sv_core.lua")
	end

	reload({ WorkshopID = 1234567890 })
	eq(resource.workshop[#resource.workshop], "1234567890", "workshop id is passed as a string")

	reload({ FastDL = true })
	local sent = {}
	for _, path in ipairs(resource.files) do sent[path] = true end
	check(sent["models/zcity_csgo_gloves/v_glove_motorcycle.mdl"], "FastDL: model")
	check(sent["models/zcity_csgo_gloves/v_glove_motorcycle.dx90.vtx"], "FastDL: vtx")
	check(sent["materials/zcity_csgo_gloves/icons/moto_1.png"], "FastDL: icon")
	check(sent["materials/zcity_csgo_gloves/skin/fingers.vmt"] and sent["materials/zcity_csgo_gloves/skin/fingers_color.vtf"],
		"FastDL: the skin of the fingers")
	check(sent["materials/models/weapons/v_models/arms/glove_motorcycle/right/1/glove_motorcycle_right.vtf"], "FastDL: nested texture")
	check(not sent["materials/models/weapons/v_models/arms/bare/unrelated.vmt"], "FastDL: foreign folders are left alone")

	reload({ PrecacheModels = false })
	eq(#util.precached, 0, "precache can be switched off")

	-- the list the build writes when the addon carries the Lua of clothing packs
	local function sentToClients(path)
		local n = 0
		for _, name in ipairs(M.csfiles) do
			if name == path then n = n + 1 end
		end
		return n
	end
	M.csfiles = {}
	reload({})
	eq(ZCGloves.Bound, nil, "bound: an addon without the list of the build loads without it")
	eq(sentToClients("zcity_csgo_gloves/sh_bound.lua"), 0, "bound: and sends none to the clients")
	M.luafiles["zcity_csgo_gloves/sh_bound.lua"] = [[ZCGloves.Bound = { ["a.lua"] = { { "Clothes/1/x", "models/x/y" } } }]]
	M.csfiles = {}
	reload({})
	check(istable(ZCGloves.Bound) and ZCGloves.Bound["a.lua"][1][2] == "models/x/y", "bound: the server reads the list the build wrote")
	eq(sentToClients("zcity_csgo_gloves/sh_bound.lua"), 1, "bound: and sends it to the clients")
	eq(select(2, ZCGloves.BoundMissing())[1].entry, "Clothes/1/x", "bound: the check works with it")
	M.luafiles["zcity_csgo_gloves/sh_bound.lua"] = nil

	-- content missing on the server
	M.files = {}
	reload({ FastDL = true })
	eq(#resource.files, 0, "FastDL without content adds nothing")
	eq(#util.precached, 0, "no precache without content")
	check(#M.log >= 1, "a note is printed when the content is missing")

	eq(#M.errors, 0, "no errors at the end: " .. table.concat(M.errors, " | "))
	return checks, failures
end
