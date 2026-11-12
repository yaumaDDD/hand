-- Both versions of a pack together (sh_merge.lua): the table file of the version that is not
-- loaded is run in a box and what it adds is put into the menu next to the loaded one.
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

	local M = dofile(testdir .. "/gmod_mock.lua")("server")
	local Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	Z.install()
	local AP = hg.Appearance
	local function tables()
		-- what the loaded (newer) version made
		AP.PlayerModels = { [1] = {
			["Male 01"] = { mdl = Z.MALE, sex = false, submatSlots = {} },
			["Male 10"] = { mdl = "models/slav/m/male_10.mdl", sex = false, submatSlots = { main = "a" } },
			["Male Same"] = { mdl = "models/both/same.mdl", sex = false, submatSlots = {} },
		}, [2] = {} }
		AP.FuckYouModels = { { ["models/slav/m/male_10.mdl"] = AP.PlayerModels[1]["Male 10"] }, {} }
		AP.Clothes = { [1] = { normal = "models/humans/male/group01/normal", shirt = "new/shirt" }, [2] = { normal = "models/humans/female/group01/normal" } }
		AP.FacemapsSlots = { ["models/mossman/face"] = { Default = "", ["Face 1"] = "models/slav/mossman_face1", ["Face 2"] = "models/both/face2" } }
		AP.FacemapsModels = { ["models/slav/m/male_10.mdl"] = "models/humans/male10" }
		AP.MultiFacemaps = { ["models/slav/m/male_10.mdl"] = { ["Face 1"] = { ["models/humans/male10"] = "x" } } }
		AP.ModelFaceSlots = {}
	end
	tables()

	_G.zcg_test_global_hits = 0
	M.luafiles["zcity_csgo_gloves/sh_merged.lua"] = [[ZCGloves.Merged = { { file = "merged/sh_old.lua", title = "Mod LEGACY" } }]]
	M.luafiles["zcity_csgo_gloves/merged/sh_old.lua"] = [[
		hg = hg or {}
		hg.Appearance = hg.Appearance or {}
		hg.Appearance.ModelFaceSlots = hg.Appearance.ModelFaceSlots or {}
		local function models()
			hg.Appearance.PlayerModels = hg.Appearance.PlayerModels or { [1] = {}, [2] = {} }
			local PM = hg.Appearance.PlayerModels
			PM[1]["Male 10"] = { mdl = "models/zcity/m/male_10.mdl", sex = false, submatSlots = { main = "b" } }
			PM[1]["Male Old"] = { mdl = "models/zcity/m/old.mdl", sex = false, submatSlots = {} }
			PM[1]["Male Same"] = { mdl = "models/both/same.mdl", sex = false, submatSlots = {} }
			PM[2]["Female Old"] = { mdl = "models/zcity/f/old.mdl", sex = true, submatSlots = {} }
			hg.Appearance.FuckYouModels = hg.Appearance.FuckYouModels or { {}, {} }
			for _, tbl in pairs(PM[1]) do hg.Appearance.FuckYouModels[1][tbl.mdl] = tbl end
		end
		local function faces()
			local function add(slot, name, mat, model)
				hg.Appearance.FacemapsSlots[slot] = hg.Appearance.FacemapsSlots[slot] or {}
				hg.Appearance.FacemapsSlots[slot][name] = mat
				if model then
					hg.Appearance.FacemapsModels[model] = slot
					hg.Appearance.ModelFaceSlots[model] = { [slot] = true }
					hg.Appearance.MultiFacemaps = hg.Appearance.MultiFacemaps or {}
					hg.Appearance.MultiFacemaps[model] = hg.Appearance.MultiFacemaps[model] or {}
					hg.Appearance.MultiFacemaps[model][name] = { [slot] = mat }
				end
			end
			add("models/mossman/face", "Face 1", "models/slav/mossman_face")
			add("models/mossman/face", "Face 2", "models/both/face2")
			add("models/mossman/face", "Face 9", "models/old/face9")
			add("models/cohrt/face", "Face 1", "models/old/cohrt", "models/zcity/m/old.mdl")
			hg.Appearance.Clothes[1].shirt = "old/shirt"
			hg.Appearance.Clothes[1].coat = "old/coat"
		end
		hook.Add("Initialize", "x_init", function() models() faces() end)
		hook.Add("InitPostEntity", "x_load", function() models() faces() end)
		hook.Add("ZPointshopLoaded", "x_shop", function() zcg_test_global_hits = zcg_test_global_hits + 100 end)
		hook.Add("Think", "x_think", function() zcg_test_global_hits = zcg_test_global_hits + 100 end)
		timer.Create("x_timer", 1, 0, function() end)
	]]
	include("autorun/zcity_csgo_gloves.lua")
	local ZCG = ZCGloves
	local sent = false
	for _, path in ipairs(M.csfiles) do
		if path == "zcity_csgo_gloves/merged/sh_old.lua" then sent = true end
	end
	check(sent, "the table file of the other version is sent to clients")

	local hooksBefore = 0
	local total, made, trouble = ZCG.MergeApply()
	eq(trouble, nil, "the file runs in its box")
	local PM = AP.PlayerModels
	eq(PM[1]["Male 10"].mdl, "models/slav/m/male_10.mdl", "a model of the loaded version keeps its name and its file")
	eq(PM[1]["Male 10 (LEGACY)"] and PM[1]["Male 10 (LEGACY)"].mdl, "models/zcity/m/male_10.mdl", "the model of the other version stands next to it")
	eq(PM[1]["Male 10 (LEGACY)"].submatSlots.main, "b", "with its own slots")
	eq(PM[1]["Male Old"] and PM[1]["Male Old"].mdl, "models/zcity/m/old.mdl", "a model only the other version has is added under its name")
	eq(PM[2]["Female Old"] and PM[2]["Female Old"].sex, true, "women as well")
	eq(PM[1]["Male Same (LEGACY)"], nil, "the same model file is not added twice")
	eq(AP.FuckYouModels[1]["models/zcity/m/male_10.mdl"], PM[1]["Male 10 (LEGACY)"], "the table by model file knows it")
	local slot = AP.FacemapsSlots["models/mossman/face"]
	eq(slot["Face 1"], "models/slav/mossman_face1", "a face of the loaded version stays")
	eq(slot["Face 1 (LEGACY)"], "models/slav/mossman_face", "the other material of that name is a face of its own")
	eq(slot["Face 2 (LEGACY)"], nil, "the same face is not added twice")
	eq(slot["Face 9"], "models/old/face9", "a face only the other version has is added")
	eq(AP.FacemapsSlots["models/cohrt/face"] and AP.FacemapsSlots["models/cohrt/face"]["Face 1"], "models/old/cohrt", "a slot only it has is added")
	eq(AP.FacemapsModels["models/zcity/m/old.mdl"], "models/cohrt/face", "the faces of its models are known by model file")
	check(istable(AP.MultiFacemaps["models/zcity/m/old.mdl"]) and AP.MultiFacemaps["models/slav/m/male_10.mdl"]["Face 1"]["models/humans/male10"] == "x",
		"MultiFacemaps: its models are added, those of the loaded version untouched")
	check(AP.ModelFaceSlots["models/zcity/m/old.mdl"] ~= nil, "ModelFaceSlots as well")
	eq(AP.Clothes[1].shirt, "new/shirt", "clothes of the loaded version are not replaced")
	eq(AP.Clothes[1].coat, "old/coat", "clothes only the other version has are added")
	eq(_G.zcg_test_global_hits, 0, "hooks that are not about the tables are not called")
	check(hook.GetTable == nil or not (hook.GetTable().Think and hook.GetTable().Think.x_think), "and no hook of the file reaches the game")
	check(total > 0 and made == total, "entries are counted: " .. tostring(total))

	local again, madeAgain = ZCG.MergeApply()
	check(again == total and madeAgain == 0, "a second call changes nothing: " .. tostring(again) .. ", " .. tostring(madeAgain))

	-- the tables are made anew
	tables()
	local t2, m2 = ZCG.MergeApply()
	check(t2 == total and m2 == total and AP.PlayerModels[1]["Male 10 (LEGACY)"] ~= nil, "tables made anew get everything again: " .. tostring(t2) .. ", " .. tostring(m2))

	local lines = {}
	ZCG.MergeReport(function(text) lines[#lines + 1] = text end)
	check(#lines == 1 and string.find(lines[1], "\"Mod LEGACY\"", 1, true) and string.find(lines[1], "3 of them player models", 1, true),
		"zcg_content tells: " .. tostring(lines[1]))

	M.setConVar("zcg_merge_versions", "0")
	eq(ZCG.MergeApply(), 0, "zcg_merge_versions 0: nothing is added")
	check(AP.PlayerModels[1]["Male 10 (LEGACY)"] == nil and AP.PlayerModels[1]["Male Old"] == nil and AP.Clothes[1].coat == nil
		and AP.FacemapsSlots["models/cohrt/face"] == nil and AP.PlayerModels[1]["Male 10"].mdl == "models/slav/m/male_10.mdl"
		and AP.Clothes[1].shirt == "new/shirt" and slot["Face 1"] == "models/slav/mossman_face1",
		"and everything that was added is out again - nothing else")
	M.setConVar("zcg_merge_versions", "1")
	check(ZCG.MergeApply() == total, "switched on again: back")

	-- faces whose file is not installed are emptied for the time being (ZCG.FixFaces): they are
	-- the same faces all the same - no second one "(LEGACY)", and the list keeps its own
	slot = AP.FacemapsSlots["models/mossman/face"]
	eq(slot["Face 1 (LEGACY)"], "models/slav/mossman_face", "(the face is there)")
	slot["Face 2"] = ""
	slot["Face 1 (LEGACY)"] = ""
	local t3, m3 = ZCG.MergeApply()
	check(t3 == total and m3 == 0 and slot["Face 2 (LEGACY)"] == nil, "emptied faces: nothing new, nothing forgotten: " .. tostring(t3) .. ", " .. tostring(m3))
	M.setConVar("zcg_merge_versions", "0")
	ZCG.MergeApply()
	eq(slot["Face 1 (LEGACY)"], nil, "an emptied face that was added goes out with the rest")
	eq(slot["Face 2"], "", "one that was not stays")
	slot["Face 2"] = "models/both/face2"
	M.setConVar("zcg_merge_versions", "1")
	ZCG.MergeApply()

	-- a build with the other version: an empty list, an empty file
	ZCG.Merged = {}
	eq(ZCG.MergeApply(), 0, "an empty list: nothing")
	check(AP.PlayerModels[1]["Male Old"] == nil, "(and what a list that is gone had added is gone)")

	-- a file that breaks
	M.luafiles["zcity_csgo_gloves/merged/sh_bad.lua"] = [[error("boom")]]
	ZCG.Merged = { { file = "merged/sh_bad.lua", title = "Bad" } }
	local _, _, bad = ZCG.MergeApply()
	check(isstring(bad) and string.find(bad, "boom", 1, true), "a table file that stops with an error is reported: " .. tostring(bad))
	eq(AP.PlayerModels[1]["Male 10"].mdl, "models/slav/m/male_10.mdl", "and the tables are as they were")

	return checks, failures
end
