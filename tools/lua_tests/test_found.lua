-- Content without Lua (sh_auto.lua): the materials sort_content.bat lists (sh_found.lua) are put
-- into the appearance tables where the tables show that they belong.
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
	local VAN, ERDIM = "models/humans/male/group01/van_facemap", "models/humans/male/group01/erdim_cylmap"
	local function tables()
		AP.Clothes = {
			[1] = { normal = "models/humans/male/group01/normal", drill = "zcity_drill/sheet_16", both = "packs/both/a" },
			[2] = { normal = "models/humans/female/group01/normal", both = "packs/both/a" },
		}
		AP.FacemapsSlots = {
			[VAN] = { Default = "", ["Face 1"] = "models/bloo/facemaps/van_facemap", Mod = "models/humans/modern/male/male_04/facemap_01" },
			[ERDIM] = { Default = "", ["Face 1"] = "models/bloo/facemaps/erdim_facemap", Mixed = "models/mixed/x" },
		}
		AP.Clothes[1].mixed = "models/mixed/y"
	end
	tables()

	M.luafiles["zcity_csgo_gloves/sh_found.lua"] = [[ZCGloves.Found = {
		"models/any/folder/Van_Facemap_New",
		"somewhere/erdim_facemap77",
		"models/humans/modern/male/male_04/facemap_09",
		"zcity_drill/sheet_99",
		"packs/both/b",
		"models/humans/female/group02/my_sheet_3",
		"models/humans/male/group02/my_sheet_3",
		"models/mixed/z",
		"props/crate",
		"models/humans/male/group01/normal",
		"zcity_drill/normal",
		"models/bloo/facemaps/van_facemap",
		"models/humans/male/group01/players_sheet",
	}]]
	include("autorun/zcity_csgo_gloves.lua")
	local ZCG = ZCGloves
	check(istable(ZCG.Found) and #ZCG.Found == 13, "the list sort_content.bat wrote is read")

	local total, made = ZCG.FoundApply()
	eq(AP.FacemapsSlots[VAN]["van_facemap_new"], "models/any/folder/van_facemap_new", "a face called after the face of a model joins the faces of that model")
	eq(AP.FacemapsSlots[ERDIM]["erdim_facemap77"], "somewhere/erdim_facemap77", "...also where the model wears a _cylmap and the face is a _facemap")
	eq(AP.FacemapsSlots[VAN]["facemap_09"], "models/humans/modern/male/male_04/facemap_09", "a material in a folder of faces of one model is a face of that model")
	eq(AP.Clothes[1]["sheet_99"], "zcity_drill/sheet_99", "a material in a folder of clothes for men is clothes for men")
	eq(AP.Clothes[2]["sheet_99"], nil, "...and not for women")
	check(AP.Clothes[1]["b"] == "packs/both/b" and AP.Clothes[2]["b"] == "packs/both/b", "a folder of clothes for both gets it for both")
	eq(AP.Clothes[2]["my_sheet_3"], "models/humans/female/group02/my_sheet_3", "a sheet in a female folder nobody knows: clothes for women")
	eq(AP.Clothes[1]["my_sheet_3"], "models/humans/male/group02/my_sheet_3", "a sheet in a male folder: clothes for men")
	eq(AP.Clothes[1]["normal (zcity_drill)"], "zcity_drill/normal", "a name that is taken gets the folder added")
	eq(AP.Clothes[1]["normal"], "models/humans/male/group01/normal", "...and the entry that had it stays")
	local stray = false
	for _, list in ipairs({ AP.Clothes[1], AP.Clothes[2], AP.FacemapsSlots[VAN], AP.FacemapsSlots[ERDIM] }) do
		for _, path in pairs(list) do
			if path == "models/mixed/z" or path == "props/crate" then stray = true end
		end
	end
	check(not stray, "a material in a folder of faces AND clothes, and one nothing is known about, stay files")
	eq(ZCG.FoundLeft, 2, "they are counted")
	check(AP.Clothes[1]["players_sheet"] == nil, "the sheet the models of the menu are made of is no clothes")
	eq(total, 9, "entries made")
	eq(made, 0, "(they were put in when the Lua file was loaded: Z-City was there)")
	local again, madeAgain = ZCG.FoundApply()
	check(again == 9 and madeAgain == 0, "a second call changes nothing: " .. tostring(again) .. ", " .. tostring(madeAgain))

	-- the tables are made anew (a Lua file loaded again): the entries come back
	tables()
	total, made = ZCG.FoundApply()
	check(total == 9 and made == 9 and AP.Clothes[1]["sheet_99"] == "zcity_drill/sheet_99", "tables made anew get the entries again")

	-- some Lua names the material by now
	AP.Clothes[1]["sheet_99"] = nil
	AP.Clothes[1]["Drill 99"] = "zcity_drill/sheet_99"
	total = ZCG.FoundApply()
	check(total == 8 and AP.Clothes[1]["sheet_99"] == nil, "a material some Lua names by now is not added a second time")

	-- zcg_content tells
	local lines = {}
	ZCG.FoundReport(function(text) lines[#lines + 1] = text end)
	check(#lines == 1 and string.find(lines[1], "13 materials nobody names", 1, true) and string.find(lines[1], "3 as faces, 5 as clothes", 1, true),
		"zcg_content tells how many are in the menu: " .. tostring(lines[1]))

	-- switched off: everything is taken out, what others made stays
	M.setConVar("zcg_found_content", "0")
	total = ZCG.FoundApply()
	eq(total, 0, "zcg_found_content 0: nothing is added")
	check(AP.Clothes[1]["b"] == nil and AP.FacemapsSlots[VAN]["van_facemap_new"] == nil and AP.Clothes[1]["Drill 99"] == "zcity_drill/sheet_99"
		and AP.Clothes[1].normal == "models/humans/male/group01/normal" and AP.FacemapsSlots[VAN].Mod ~= nil,
		"and what was added is taken out - nothing else")
	M.setConVar("zcg_found_content", "1")
	total = ZCG.FoundApply()
	eq(total, 8, "switched on again: they are back")

	-- without the list nothing happens
	ZCG.Found = nil
	eq(ZCG.FoundApply(), 0, "no list: nothing")
	check(AP.Clothes[1]["b"] == nil, "and the entries of a list that is gone are gone")

	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))
	return checks, failures
end
