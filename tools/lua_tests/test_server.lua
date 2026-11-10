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
		"v_glove_slick", "v_glove_ct_specialist",
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
	eq(#ZCG.Variants, 68, "number of gloves")
	eq(#ZCG.Families, 10, "number of glove families")
	eq(ZCG.Ready, nil, "not registered while Z-City is missing")
	eq(#M.csfiles, 6, "files sent to clients")
	eq(#util.precached, 12, "precached models")
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

	M.advance(3)
	eq(ZCG.Ready, nil, "still waiting for Z-City")
	eq(#M.errors, 0, "no errors while waiting")

	-- ---------------------------------------------------------------- Z-City appears
	Z.install()
	M.advance(1.2)
	eq(ZCG.Ready, true, "registered once Z-City exists")

	local hands = hg.Appearance.Bodygroups.HANDS
	for sex = 1, 2 do
		eq(table.Count(hands[sex]), 3 + 68, "entries in HANDS[" .. sex .. "]")
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
	eq(table.Count(hands[1]), 1 + 68, "re-registered after a rebuild")
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

	-- content missing on the server
	M.files = {}
	reload({ FastDL = true })
	eq(#resource.files, 0, "FastDL without content adds nothing")
	eq(#util.precached, 0, "no precache without content")
	check(#M.log >= 1, "a note is printed when the content is missing")

	eq(#M.errors, 0, "no errors at the end: " .. table.concat(M.errors, " | "))
	return checks, failures
end
