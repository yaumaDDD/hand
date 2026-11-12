-- The content check (zcg_content) and the appearance editor with the "Z-City Appearance Mod"
-- (apperance.zip in the repository).
--
-- The two pieces of that mod this addon has to live with - the code that wraps the buttons of
-- the editor and the function that builds the "Select Gloves" window - are cut out of the mod's
-- real source file and run against the imitation of the game. If the mod changes so much that
-- they cannot be cut out any more, the scenario fails and the compatibility has to be looked at
-- again.
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

	local M = dofile(testdir .. "/gmod_mock.lua")("client")
	local Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot

	for _, id in ipairs({ "moto_2", "moto_5", "sport_5", "specialist_10", "handwrap_12" }) do
		M.files["materials/zcity_csgo_gloves/icons/" .. id .. ".png"] = true
	end

	Z.install()
	local me = M.newPlayer("me", Z.MALE)
	M.localplayer = me
	-- (the list the build writes when the addon carries the Lua of clothing packs)
	M.luafiles["zcity_csgo_gloves/sh_bound.lua"] = [[ZCGloves.Bound = { ["a.lua"] = { { "Clothes/1/\208\154 \"x\"", "models/x/y" } } }]]
	include("autorun/zcity_csgo_gloves.lua")
	local ZCG = ZCGloves
	check(istable(ZCG.Bound) and ZCG.Bound["a.lua"][1][1] == "Clothes/1/\208\154 \"x\"",
		"bound: a client reads the list the build wrote")
	ZCG.Bound = nil

	local function count(tbl)
		local n = 0
		for _ in pairs(tbl) do n = n + 1 end
		return n
	end
	local function has(list, text)
		for _, line in ipairs(list) do
			if line == text then return true end
		end
		return false
	end

	-- ================================================================ zcg_content
	do
		local AP = hg.Appearance
		AP.Clothes[1].bib = "models/humans/male/group01/Bib"
		AP.Clothes[2].swiss = "materials/models/humans/female/group01/swiss.vmt"
		AP.PlayerModels[1]["Male 10"] = { mdl = "models/slav/m/male_10.mdl", sex = false, submatSlots = {} }
		AP.FacemapsSlots = { ["models/humans/male/group01/ted_facemap"] = { Default = "", ["Face 2"] = "models/faces/ted2" } }
		AP.MultiFacemaps = { ["models/slav/m/male_10.mdl"] = { Scar = { a = "models/faces/scar_a", b = "models/faces/scar_b" } } }
		hg.Accessories = { ["armband red"] = { model = "models/zcband/band_team.mdl", femmodel = "models/zcband/band_team_f.mdl" } }

		local BIB = "materials/models/humans/male/group01/bib.vmt  <-  male clothes bib"
		local SWISS = "materials/models/humans/female/group01/swiss.vmt  <-  female clothes swiss"
		local MALE10 = "models/slav/m/male_10.mdl  <-  player model Male 10"
		local BAND = "models/zcband/band_team.mdl  <-  accessory armband red"
		local BAND_F = "models/zcband/band_team_f.mdl  <-  accessory armband red"
		local FACE = "materials/models/faces/ted2.vmt  <-  face Face 2"
		local SCAR = "materials/models/faces/scar_a.vmt  <-  face Scar"

		local missing, models, materials = ZCG.ContentMissing(false)
		for _, line in ipairs({ BIB, SWISS, MALE10, BAND, BAND_F, FACE, SCAR }) do
			check(has(missing, line), "content: reported as missing: " .. line)
		end
		eq(models, 2 + 1 + 2, "content: models named by the tables (two stock ones, Male 10, two armbands)")
		check(materials >= 6, "content: materials named by the tables")
		for _, line in ipairs(missing) do
			check(line:find("zcity_csgo_gloves", 1, true) == nil, "content: the gloves are not part of this list")
			check(line:find("<-  face Default", 1, true) == nil, "content: an empty material name is nothing to look for")
		end
		local sorted = true
		for i = 2, #missing do
			if missing[i - 1] > missing[i] then sorted = false end
		end
		check(sorted, "content: the list is sorted")

		-- the files arrive
		local before = #missing
		M.files["materials/models/humans/male/group01/bib.vmt"] = true
		M.files["models/slav/m/male_10.mdl"] = true
		M.files["models/zcband/band_team.mdl"] = true
		missing = ZCG.ContentMissing(false)
		eq(#missing, before - 3, "content: three files less are missing once they are there")
		check(not has(missing, BIB) and not has(missing, MALE10) and not has(missing, BAND), "content: and they are the three")
		check(has(missing, BAND_F), "content: the others still are")

		-- a material the file system does not show but the game knows: only the command asks
		M.materials["models/faces/ted2"] = true
		check(has(ZCG.ContentMissing(false), FACE), "content: without asking the material system the face counts as missing")
		check(not has(ZCG.ContentMissing(true), FACE), "content: the command asks the material system")

		M.log = {}
		M.command("zcg_content", me)
		check(#M.log >= 2, "zcg_content prints a report")
		check(M.log[1]:find("content check on the client", 1, true) ~= nil, "zcg_content says whose files were checked")
		local listed = false
		for _, line in ipairs(M.log) do
			if line:find(BAND_F, 1, true) then listed = true end
		end
		check(listed, "zcg_content lists a missing file")
		local told = false
		for _, line in ipairs(M.log) do
			if line:find("the whole list is in garrysmod/data/zcg_content.txt", 1, true) then told = true end
		end
		check(told and M.written["zcg_content.txt"] ~= nil and M.written["zcg_content.txt"]:find(BAND_F, 1, true) ~= nil,
			"and writes the whole list into a file")

		-- ---- the materials a model is made of
		local SLAV = "models/slav/m/male_10.mdl"
		M.installModel(SLAV, { "players_sheet", "Hair", "hands" }, { "models\\Humans\\Slav\\", "distac/gloves/" }, nil)
		M.installModel("models/zcband/band_team.mdl", { "band", "hair" }, { "models/humans/slav/", "distac/gloves/" }, nil)
		M.files["materials/distac/gloves/hands.vmt"] = true
		M.files["materials/models/humans/slav/band.vmt"] = true
		M.advance(11) -- (a model file that could not be read is looked at again after ten seconds)
		local HAIR = "materials/models/humans/slav/hair.vmt  <-  material of " .. SLAV
			.. " and 1 more models (or materials/distac/gloves/hair.vmt)"
		local SHEET = "materials/models/humans/slav/players_sheet.vmt  <-  material of " .. SLAV
			.. " (or materials/distac/gloves/players_sheet.vmt)"
		local own
		before = #ZCG.ContentMissing(false)
		missing, models, materials, own = ZCG.ContentMissing(false)
		eq(own, 5, "content: the materials of the models that are installed are counted")
		check(has(missing, HAIR), "content: a material a model is made of and that is not installed is listed, once for all its models")
		check(has(missing, SHEET), "content: with every folder the model looks into")
		for _, line in ipairs(missing) do
			check(line:find("gloves/hands.vmt  <-", 1, true) == nil and line:find("slav/band.vmt  <-", 1, true) == nil,
				"content: a material that is found in one of the folders is not missing")
		end
		-- a material that the tables name too is listed once
		AP.Clothes[1].sheet = "models/humans/slav/players_sheet"
		missing = ZCG.ContentMissing(false)
		check(not has(missing, SHEET) and has(missing, "materials/models/humans/slav/players_sheet.vmt  <-  male clothes sheet"),
			"content: a material named by the tables and by a model is listed once")
		AP.Clothes[1].sheet = nil

		-- ---- a file of that name lies somewhere else
		M.pathFiles.THIRDPARTY = {
			["materials/Humans/Slav/hair.vmt"] = true, ["materials/humans/slav/players_sheet.vtf"] = true,
			["materials/material 1/swiss.VMT"] = true, ["models/pack/band_team_f.mdl"] = true,
			["materials/a/swiss.vmt"] = true, ["materials/b/swiss.vmt"] = true, ["materials/c/swiss.vmt"] = true,
		}
		M.pathFiles.MOD = { ["materials/Humans/Slav/hair.vmt"] = true, ["materials/x/unrelated.vmt"] = true }
		local found, cut = ZCG.FindByName({ ["hair.vmt"] = true, ["swiss.vmt"] = true, ["band_team_f.mdl"] = true, ["nowhere.vmt"] = true })
		eq(cut, false, "content: the search by name went through")
		eq(found["hair.vmt"] and #found["hair.vmt"], 1, "content: a file found in two search paths is one file")
		eq(found["hair.vmt"] and found["hair.vmt"][1], "materials/Humans/Slav/hair.vmt", "content: where a file of that name lies")
		eq(found["swiss.vmt"] and #found["swiss.vmt"], 3, "content: at most three places are kept for a name")
		eq(found["band_team_f.mdl"] and found["band_team_f.mdl"][1], "models/pack/band_team_f.mdl", "content: models are looked for as well")
		eq(found["nowhere.vmt"], nil, "content: a name that is nowhere")
		eq(found["players_sheet.vtf"], nil, "content: only the names that were asked for")

		local function logged(text)
			local n = 0
			for _, line in ipairs(M.log) do
				if line:find(text, 1, true) then n = n + 1 end
			end
			return n
		end
		M.log = {}
		M.command("zcg_content", me)
		check(M.log[1]:find("the installed models are made of 5 materials", 1, true) ~= nil, "zcg_content counts the materials of the models")
		eq(logged(HAIR .. "   [a file of that name: materials/Humans/Slav/hair.vmt]"), 1, "zcg_content says where a missing file lies")
		eq(logged(BAND_F .. "   [a file of that name: models/pack/band_team_f.mdl]"), 1, "also for a model")
		eq(logged("[a file of that name: materials/humans/slav/players_sheet.vtf"), 0, "a texture is not taken for a material")
		eq(logged("3 of them have a file of the same name in another folder"), 1, "it counts them")
		eq(logged("start sort_content.bat in the folder of this addon"), 1, "and names the tool that moves them")
		eq(logged("sort_content_report.txt, names such files - move those by hand"), 1, "and where that tool tells what it left alone")
		eq(logged("leaves a purple and black part on that model"), 1, "it says what a missing material of a model does")

		-- nothing of that name anywhere: the files have to be brought first
		M.pathFiles = {}
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("[a file of that name"), 0, "zcg_content: no file of that name, no remark")
		eq(logged("put the files into the materials and models folders of this addon"), 1, "it says where to put the files")
		-- (no search path of an addon lists anything: everything the game has mounted is searched)
		M.files["materials/wrong/place/hair.vmt"] = true
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("[a file of that name: materials/wrong/place/hair.vmt]"), 1, "zcg_content looks through everything when the addons cannot be listed")
		M.files["materials/wrong/place/hair.vmt"] = nil

		-- one line for the player when the game has started
		M.log = {}
		hook.Run("InitPostEntity")
		M.advance(16)
		eq(logged("models and materials of the appearance menu are not installed on this computer"), 1,
			"the player is told once that content is missing")
		eq(logged("type zcg_content for the list"), 1, "and how to see the list")

		M.models[SLAV], M.filedata[SLAV] = nil, nil
		M.models["models/zcband/band_team.mdl"], M.filedata["models/zcband/band_team.mdl"] = nil, nil

		-- nothing left to complain about
		AP.Clothes[1].bib, AP.Clothes[2].swiss, AP.PlayerModels[1]["Male 10"] = nil, nil, nil
		AP.FacemapsSlots, AP.MultiFacemaps, hg.Accessories = nil, nil, nil
		eq(#M.errors, 0, "content: no errors: " .. table.concat(M.errors, " | "))
	end

	-- ================================================================ what the clothing Lua adds
	-- The build of the addon runs the Lua of the clothing packs and writes down what the tables
	-- hold then (ZCG.Bound, sh_bound.lua). zcg_content compares the tables of the game with it:
	-- a name that is not there was lost on the way.
	do
		local AP = hg.Appearance
		local function logged(text)
			local n = 0
			for _, line in ipairs(M.log) do
				if line:find(text, 1, true) then n = n + 1 end
			end
			return n
		end
		local clothes = { AP.Clothes[1], AP.Clothes[2] }
		M.advance(120) -- (what the start of the game above left to do)

		eq(ZCG.BoundMissing(), nil, "bound: without the list of the build there is nothing to compare")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("the clothing Lua of this addon"), 0, "and zcg_content says nothing about it")

		ZCG.Bound = {
			["autorun/zcity_drill_clothes.lua"] = {
				{ "Clothes/1/Drill 01", "zcity_drill/players_sheet_02" },
				{ "Clothes/2/Drill 01", "zcity_drill/players_sheet_02" },
				{ "Clothes/1/Drill 07", "zcity_drill/sheet_16" },
			},
			["homigrad/new_appearance/sh_shared_pack.lua"] = {
				{ "PlayerModels/1/Male 10", "models/slav/m/male_10.mdl" },
				{ "FacemapsSlots/models/humans/male/group01/ted_facemap/Face 2", "models/faces/ted2" },
				{ "MultiFacemaps/models/slav/m/male_10.mdl/Scar/a", "models/faces/scar_a" },
				{ "Accessories/armband red/model", "models/zcband/band_team.mdl" },
				{ "Clothes/1/of the server", "models/x/server", 1 },
				{ "Clothes/1/of the clients", "models/x/client", 2 },
			},
		}
		AP.Clothes[1]["Drill 01"] = "zcity_drill/players_sheet_02"
		AP.Clothes[2]["Drill 01"] = "ZCity_Drill\\Players_Sheet_02" -- (capitals and the other slash: the same file)
		AP.Clothes[1]["Drill 07"] = "zcity_drill/sheet_16"
		AP.Clothes[1]["of the clients"] = "models/x/client"
		AP.Clothes[1]["of another addon"] = "models/y/other"
		AP.PlayerModels[1]["Male 10"] = { mdl = "models/slav/m/male_10.mdl", sex = false, submatSlots = {} }
		AP.FacemapsSlots = { ["models/humans/male/group01/ted_facemap"] = { ["Face 2"] = "models/faces/ted2" } }
		AP.MultiFacemaps = { ["models/slav/m/male_10.mdl"] = { Scar = { a = "models/faces/scar_a" } } }
		hg.Accessories = { ["armband red"] = { model = "models/zcband/band_team.mdl" } }

		local count, missing = ZCG.BoundMissing()
		eq(count, 8, "bound: the entries a client should have (not the one of the server)")
		eq(#missing, 0, "bound: they are all there")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("the clothing Lua of this addon: all 8 clothes, faces, models and accessories it adds are in the appearance tables"), 1,
			"zcg_content says that everything the clothing Lua adds is there")
		check(M.log[1]:find("content check on the client", 1, true) ~= nil, "after the content check")
		eq(#ZCG.OtherVersions() .. "|" .. logged("this addon is built with"), "0|0", "versions: an addon without a second version of a pack says nothing about one")

		-- A pack that has two versions: the build took one, and wrote down the other one with the
		-- files that only it names.
		ZCG.BoundLeftOut = { ["Mod OLD"] = "Mod" }
		ZCG.BoundOther = { ["models/old/m/male_10.mdl"] = "Mod OLD", ["models/old/m/eli.mdl"] = "Mod OLD",
			["materials/models/old/face.vmt"] = "Mod OLD", ["models/elsewhere/x.mdl"] = "Another", [5] = "Mod OLD" }
		M.files["models/old/m/eli.mdl"] = true
		local versions = ZCG.OtherVersions()
		eq(#versions .. "|" .. versions[1].title .. "|" .. versions[1].instead .. "|" .. versions[1].files .. "|" .. versions[1].there,
			"1|Mod OLD|Mod|3|1", "versions: the pack that is not in the addon, the one that is, and the files only the first one names")
		eq(versions[1].own .. "|" .. versions[1].ownThere, "0|0", "versions: a build that does not tell which files only its own version names")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("this addon is built with \"Mod\". \"Mod OLD\" is another version of the same addon and is not in it: the game can only have one of the two"), 1,
			"versions: zcg_content tells which version the addon is built with")
		eq(logged("  1 of the 3 files that only \"Mod OLD\" names are here: the game does not use them with this addon"), 1,
			"versions: and how many files of the other one are installed for nothing")
		eq(logged("is installed as an addon of its own as well"), 0, "versions: (no word about trouble while the tables are whole)")
		eq(logged("IT LOOKS LIKE") .. "|" .. logged("files that only \"Mod\" names"), "0|0", "versions: nor a guess about the content without the list for it")

		-- the files only the version in the addon names: which kind is installed tells whose content it is
		ZCG.BoundOnly = { ["models/new/m/male_10.mdl"] = "Mod OLD", ["models/new/m/eli.mdl"] = "Mod OLD", ["models/elsewhere/y.mdl"] = "Another" }
		versions = ZCG.OtherVersions()
		eq(versions[1].own .. "|" .. versions[1].ownThere, "2|0", "versions: the files only the version in the addon names are counted")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("  0 of the 2 files that only \"Mod\" names are here"), 1, "versions: zcg_content tells how many of them are installed")
		eq(logged("IT LOOKS LIKE THE CONTENT HERE IS THAT OF \"Mod OLD\": this addon looks for the files of \"Mod\" and finds none of them. "
			.. "Close the game and run sort_content.bat in the folder of this addon: it puts the Lua of \"Mod OLD\" in place by itself (it lies in sort_content/versions)"), 1,
			"versions: files of the other version and none of this one - the content is that of the other version, and it says so")
		M.files["models/new/m/eli.mdl"] = true
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("  1 of the 2 files that only \"Mod\" names are here") .. "|" .. logged("IT LOOKS LIKE"), "1|0",
			"versions: with files of both it only counts")
		M.files["models/new/m/eli.mdl"] = nil
		-- a stray file of the version in the addon among the files of the other one
		local only, other = {}, {}
		for i = 1, 10 do
			only["models/new/m/n" .. i .. ".mdl"] = "Mod OLD"
			other["models/old/m/o" .. i .. ".mdl"] = "Mod OLD"
			if i <= 7 then M.files["models/old/m/o" .. i .. ".mdl"] = true end
		end
		local keptOther = ZCG.BoundOther
		ZCG.BoundOnly, ZCG.BoundOther = only, other
		M.files["models/new/m/n1.mdl"] = true
		versions = ZCG.OtherVersions()
		eq(versions[1].there .. "/" .. versions[1].files .. " " .. versions[1].ownThere .. "/" .. versions[1].own .. " " .. tostring(versions[1].other),
			"7/10 1/10 true", "versions: most files of the other version and one of this one - still the content of the other version")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("this addon looks for the files of \"Mod\" and finds next to none of them"), 1, "versions: and zcg_content says so")
		M.files["models/new/m/n2.mdl"], M.files["models/new/m/n3.mdl"] = true, true
		eq(ZCG.OtherVersions()[1].other, false, "versions: with more of this one there is no verdict")
		-- (the content of one version carries some files of the other: not more than one in four is few)
		for i = 11, 20 do only["models/new/m/n" .. i .. ".mdl"] = "Mod OLD" end
		M.files["models/new/m/n4.mdl"], M.files["models/new/m/n5.mdl"] = true, true
		versions = ZCG.OtherVersions()
		eq(versions[1].ownThere .. "/" .. versions[1].own .. " " .. tostring(versions[1].other), "5/20 true",
			"versions: most files of the other version and one in four of this one - the content of the other version")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("this addon looks for the files of \"Mod\" and finds only 5 of them"), 1, "versions: and zcg_content says how many")
		M.files["models/new/m/n6.mdl"] = true
		eq(ZCG.OtherVersions()[1].other, false, "versions: with more than one in four there is no verdict")
		for i = 4, 6 do M.files["models/new/m/n" .. i .. ".mdl"] = nil end
		for i = 11, 20 do only["models/new/m/n" .. i .. ".mdl"] = nil end
		for i = 1, 10 do
			M.files["models/new/m/n" .. i .. ".mdl"], M.files["models/old/m/o" .. i .. ".mdl"] = nil, nil
		end
		M.files["models/new/m/n1.mdl"], M.files["models/old/m/o1.mdl"], M.files["models/old/m/o2.mdl"] = true, true, true
		eq(ZCG.OtherVersions()[1].other, false, "versions: nor with a few files of either")
		M.files["models/new/m/n1.mdl"], M.files["models/old/m/o1.mdl"], M.files["models/old/m/o2.mdl"] = nil, nil, nil
		ZCG.BoundOther = keptOther
		ZCG.BoundOnly = { ["models/new/m/male_10.mdl"] = "Mod OLD", ["models/new/m/eli.mdl"] = "Mod OLD", ["models/elsewhere/y.mdl"] = "Another" }
		M.files["models/old/m/eli.mdl"] = nil
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("  0 of the 3 files that only \"Mod OLD\" names are here") .. "|" .. logged("  0 of the 2 files that only \"Mod\" names are here")
			.. "|" .. logged("IT LOOKS LIKE"), "1|1|0", "versions: with files of neither there is nothing to guess from")
		M.files["models/old/m/eli.mdl"] = true
		ZCG.BoundOnly = nil
		M.files["models/old/m/eli.mdl"] = nil
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("  0 of the 3 files that only \"Mod OLD\" names are here") .. "|" .. logged("the game does not use them"), "1|0",
			"versions: none of them installed is told plainly")

		-- one name dropped, one replaced by something else
		AP.Clothes[1]["Drill 07"] = nil
		AP.PlayerModels[1]["Male 10"].mdl = "models/other/male_10.mdl"
		count, missing = ZCG.BoundMissing()
		eq(#missing, 2, "bound: a name that is gone and one that was replaced are found")
		eq(missing[1].entry .. " | " .. tostring(missing[1].now) .. " | " .. missing[1].by,
			"Clothes/1/Drill 07 | nil | autorun/zcity_drill_clothes.lua", "bound: the one that is gone, with its Lua file")
		eq(missing[2].entry .. " | " .. tostring(missing[2].now) .. " | " .. missing[2].want,
			"PlayerModels/1/Male 10 | models/other/male_10.mdl | models/slav/m/male_10.mdl", "bound: the one that was replaced, with what is there")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("2 of the 8 clothes, faces, models and accessories it adds are NOT in the appearance tables"), 1,
			"zcg_content says how many are not there")
		eq(logged("  lua/autorun/zcity_drill_clothes.lua: 1"), 1, "by the Lua file that adds them")
		eq(logged("  lua/homigrad/new_appearance/sh_shared_pack.lua: 1"), 1, "each of them")
		eq(logged("    Clothes/1/Drill 07 = zcity_drill/sheet_16   [not there]"), 1, "the name that is gone")
		eq(logged("    PlayerModels/1/Male 10 = models/slav/m/male_10.mdl   [there is models/other/male_10.mdl instead]"), 1,
			"the name that was replaced")
		eq(logged("this addon is built with \"Mod\". \"Mod OLD\" is another version") .. "|"
			.. logged("  if \"Mod OLD\" is installed as an addon of its own as well, its Lua files have the same names as the ones in this addon and take their place"),
			"1|1", "versions: with entries missing, the other version installed beside this addon is named as a cause")
		ZCG.BoundLeftOut, ZCG.BoundOther, ZCG.BoundOnly = { "not a title" }, "not a table", 7
		M.errors = {}
		M.log = {}
		M.command("zcg_content", me)
		eq(#M.errors .. "|" .. logged("this addon is built with \"not a title\". \"1\" is another version"), "0|1", "versions: a list that is not what it should be is no error")
		ZCG.BoundLeftOut, ZCG.BoundOther, ZCG.BoundOnly = nil, nil, nil

		eq(M.written["zcg_bound.txt"], nil, "a short list is not written into a file")

		-- something makes the table anew after the packs have added to it
		AP.Clothes = { { normal = "models/humans/male/group01/normal" }, {} }
		count, missing = ZCG.BoundMissing()
		eq(#missing, 5, "bound: a table that was made anew lost everything the packs had added")

		-- a long list: the console gets its head, a file gets all of it
		local few = ZCG.Bound
		local many = {}
		for i = 1, 50 do many[i] = { string.format("Clothes/2/Shirt %02d", i), "pack/shirt_" .. i } end
		ZCG.Bound = { ["autorun/many.lua"] = many }
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("50 of the 50 clothes, faces, models and accessories it adds are NOT in the appearance tables"), 1, "bound: a long list is counted")
		eq(logged("    Clothes/2/Shirt 40 = pack/shirt_40   [not there]") + logged("Shirt 41"), 1, "the console gets its first forty lines")
		eq(logged("    ... and 10 more"), 1, "and the number of the rest")
		eq(logged("    the whole list is in garrysmod/data/zcg_bound.txt"), 1, "and where all of them are")
		local text = M.written["zcg_bound.txt"] or ""
		check(text:find("lua/autorun/many.lua: Clothes/2/Shirt 50 = pack/shirt_50   [not there]\n", 1, true) ~= nil
			and select(2, text:gsub("\n", "\n")) == 50, "the file has every entry, with its Lua file")
		ZCG.Bound = few

		-- one line after the start of the game, a minute later (the Lua may add things on timers)
		M.log = {}
		hook.Run("InitPostEntity")
		M.advance(60)
		eq(logged("that the clothing Lua of this addon adds are not in the appearance tables"), 0, "the player is not told before a minute has passed")
		M.advance(6)
		eq(logged("5 of the 8 clothes, faces and models that the clothing Lua of this addon adds are not in the appearance tables of the client"), 1,
			"then once, with the way to the list")

		-- a list the game cannot make sense of does no harm
		ZCG.Bound = { ["x.lua"] = "not a list", [1] = { { "Clothes/1/a" }, "nor this", { "Clothes/1/b", "models/x/b" } } }
		count, missing = ZCG.BoundMissing()
		eq(count .. " " .. #missing .. " " .. tostring(missing[1] and missing[1].by), "1 1 1", "bound: a broken list is read as far as it makes sense")

		ZCG.Bound = nil
		AP.Clothes = clothes
		for _, name in ipairs({ "Drill 01", "Drill 07", "of the clients", "of another addon" }) do
			AP.Clothes[1][name], AP.Clothes[2][name] = nil, nil
		end
		AP.PlayerModels[1]["Male 10"] = nil
		AP.FacemapsSlots, AP.MultiFacemaps, hg.Accessories = nil, nil, nil
		eq(#M.errors, 0, "bound: no errors: " .. table.concat(M.errors, " | "))
	end

	-- ================================================================ faces without their files
	-- What a real server showed: the clothing Lua names faces whose files come with yet another
	-- addon, faces under names that do not exist, and whole lists of faces for a material that
	-- no player model has any more. Z-City hands faces out by chance - purple and black squares
	-- for everybody. Such a face shows the own face of the model until its file is there.
	do
		local AP = hg.Appearance
		local function logged(text)
			local n = 0
			for _, line in ipairs(M.log) do
				if line:find(text, 1, true) then n = n + 1 end
			end
			return n
		end
		M.advance(300)
		local clothes, models = { AP.Clothes[1], AP.Clothes[2] }, { AP.PlayerModels[1], AP.PlayerModels[2] }
		local TED, LAKE = "models/humans/male/group01/ted_facemap", "models/humans/female/group01/lake_facemap"
		local MALE, OTHER = "models/slav/m/male_02.mdl", "models/zcityadodser/f/female_06.mdl"

		-- a menu of forty clothes whose files are all there, and one player model
		AP.Clothes = { {}, {} }
		for i = 1, 40 do
			AP.Clothes[1]["shirt " .. i] = "models/pack/shirt_" .. i
			M.files["materials/models/pack/shirt_" .. i .. ".vmt"] = true
		end
		AP.PlayerModels = { { ["Male 02"] = { mdl = "models/Slav/M/Male_02.mdl", sex = false, submatSlots = {} } }, {} }
		M.installModel(MALE, { "players_sheet", "ted_facemap" }, { "models/humans/male/group01/" }, nil)
		M.files["materials/models/humans/male/group01/players_sheet.vmt"] = true
		M.files["materials/" .. TED .. ".vmt"] = true
		M.files["materials/models/faces/ted_1.vmt"] = true
		AP.FacemapsModels = { [OTHER] = LAKE }
		AP.FacemapsSlots = {
			[TED] = { Default = "", ["Face 1"] = "models/faces/ted_1", ["Face 10 (New)"] = "models/humans/modern/male/male_02/facemap_01",
				["Face 9"] = "Models\\Faces\\Ted_9", Made = "!made_by_lua" },
			[LAKE] = { Default = "", ["Face 1"] = "models/faces/lake_facemap", ["Face 2"] = "models/faces/lake_facemap2" },
		}
		AP.MultiFacemaps = { [MALE] = { ["Face 10 (New)"] = { [TED] = "models/humans/modern/male/male_02/facemap_01" } },
			[OTHER] = { ["Face 1"] = { [LAKE] = "models/faces/lake_facemap" } } }
		M.advance(11)

		-- ---- the faces nobody can wear
		local used, players = ZCG.FaceSlotsInUse()
		check(istable(used) and used[TED] == true and used[LAKE] == nil, "faces: the model file tells which face material a player model has")
		check(istable(players) and players[MALE] == true and players[OTHER] == nil, "faces: and which models are player models")
		local missing, _, materials, _, apart = ZCG.ContentMissing(false)
		local NEW = "materials/models/humans/modern/male/male_02/facemap_01.vmt  <-  face Face 10 (New)"
		local NINE = "materials/models/faces/ted_9.vmt  <-  face Face 9"
		check(has(missing, NEW) and has(missing, NINE) and #missing == 2, "faces: the faces of a player model that have no file are missing: " .. table.concat(missing, " | "))
		check(istable(apart) and #apart == 2 and apart[1] == "materials/models/faces/lake_facemap.vmt  <-  face Face 1"
			and apart[2] == "materials/models/faces/lake_facemap2.vmt  <-  face Face 2",
			"faces: the faces of a material no player model has are listed apart: " .. table.concat(apart or {}, " | "))
		eq(materials, 40 + 3, "faces: and are not counted with the materials of the menu")
		-- (what the Lua says about a model counts as well: a model that is not installed)
		AP.FacemapsModels["models/slav/m/male_02.mdl"] = LAKE
		check(#select(5, ZCG.ContentMissing(false)) == 0 and #ZCG.ContentMissing(false) == 4, "faces: a list the Lua gives to a player model is in use")
		AP.FacemapsModels["models/slav/m/male_02.mdl"] = nil
		-- (no player model known at all: nothing is called unwearable)
		AP.PlayerModels = { {}, {} }
		check(ZCG.FaceSlotsInUse() == nil and #ZCG.ContentMissing(false) == 4, "faces: without player models nothing is set apart")
		AP.PlayerModels = { { ["Male 02"] = { mdl = "models/Slav/M/Male_02.mdl", sex = false, submatSlots = {} } }, {} }

		-- (a player model that is not installed: its materials are not known, nothing is set apart)
		AP.PlayerModels[1]["Male 03"] = { mdl = "models/slav/m/male_03.mdl", sex = false, submatSlots = {} }
		check(ZCG.FaceSlotsInUse() == nil and #select(5, ZCG.ContentMissing(false)) == 0,
			"faces: with a player model that cannot be read nothing is set apart")
		AP.PlayerModels[1]["Male 03"] = nil

		-- ---- the addon does not know whether the players have the files the server lacks: the
		-- faces stay as the clothing Lua made them until the owner says otherwise
		local ted, lake = AP.FacemapsSlots[TED], AP.FacemapsSlots[LAKE]
		local nothing, off = ZCG.FixFaces()
		eq(tostring(nothing) .. "|" .. tostring(off), "nil|off", "faces: left alone by default")
		eq(ted["Face 10 (New)"] .. "|" .. ted["Face 9"] .. "|" .. lake["Face 1"],
			"models/humans/modern/male/male_02/facemap_01|Models\\Faces\\Ted_9|models/faces/lake_facemap", "faces: the tables are as the clothing Lua made them")
		eq(next(ZCG.Faceless), nil, "faces: nothing is remembered")
		eq(ZCG.FacesLeft.faces .. "|" .. ZCG.FacesLeft.why, "4|off", "faces: how many have no file is counted all the same, by file")
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("2 of them are faces: whoever gets one of them has purple and black squares for a face - and Z-City hands faces out by chance"), 1,
			"zcg_content says what faces without files do")
		eq(logged("zcg_fix_faces 1 (console of the server, or server.cfg) gives such a face the own face of the model"), 1,
			"and how to give them the own face of the model")
		eq(ted["Face 10 (New)"], "models/humans/modern/male/male_02/facemap_01", "zcg_content changes nothing by itself")
		hook.Run("InitPostEntity")
		M.advance(200)
		eq(ted["Face 10 (New)"] .. "|" .. logged("faces of the appearance menu have no material file"),
			"models/humans/modern/male/male_02/facemap_01|0", "faces: nor does the running game, and it says nothing")

		-- ---- zcg_fix_faces 1: a face without its file shows the own face of the model
		M.setConVar("zcg_fix_faces", 1)
		local found, all = ZCG.ContentShare()
		eq(found .. " of " .. all, "41 of 43", "faces: how much of the menu this computer has")
		local count, why = ZCG.FixFaces()
		eq(count, 4, "faces: the faces without files are counted by file, those nobody can wear too (" .. tostring(why) .. ")")
		eq(ted["Face 10 (New)"] .. "|" .. ted["Face 9"] .. "|" .. lake["Face 1"] .. "|" .. lake["Face 2"], "|||", "faces: they hold the empty material Z-City uses for Default")
		eq(AP.MultiFacemaps[MALE]["Face 10 (New)"][TED], "", "faces: also where the Appearance Mod lists them by model")
		eq(ted["Face 1"] .. "|" .. ted.Default .. "|" .. ted.Made, "models/faces/ted_1||!made_by_lua", "faces: a face with its file, the default and a material made by Lua stay")
		eq(ZCG.Faceless["FacemapsSlots/" .. TED .. "/Face 9"], "Models\\Faces\\Ted_9", "faces: what stood there is remembered")
		missing, _, materials, _, apart = ZCG.ContentMissing(false)
		check(has(missing, NEW) and has(missing, NINE) and #missing == 2 and #apart == 2 and materials == 43,
			"faces: the files are still named as missing: " .. table.concat(missing, " | "))
		eq(ZCG.FixFaces(), 4, "faces: looked at again, nothing changes")
		ZCG.Bound = { ["pack/faces.lua"] = { { "FacemapsSlots/" .. TED .. "/Face 9", "models/faces/ted_9" },
			{ "FacemapsSlots/" .. TED .. "/Face 10 (New)", "models/humans/modern/male/male_02/facemap_01" },
			{ "Clothes/1/shirt 1", "models/pack/shirt_1" } },
			["pack/lake.lua"] = { { "FacemapsSlots/" .. LAKE .. "/Face 1", "models/faces/lake_facemap" } } }
		ZCG.BoundPacks = { ["pack/faces.lua"] = "The \"Faces\" Pack" }
		local total, gone = ZCG.BoundMissing()
		eq(total .. " " .. #gone, "4 0", "faces: the tables still hold what the clothing Lua put there, as far as the check goes")

		-- the clothing Lua runs again and writes its faces anew
		ted["Face 9"] = "Models\\Faces\\Ted_9"
		eq(ZCG.FixFaces() .. "|" .. ted["Face 9"], "4|", "faces: a face that was written anew is looked after again")

		-- ---- zcg_content
		-- (the folder of the addon is found by its own Lua file, whatever the folder is called)
		M.files["addons/other addon/lua/autorun/other.lua"] = true
		M.log = {}
		M.command("zcg_content", me)
		eq(ZCG.AddonFolder, false, "zcg_content: an addon that is not a folder in addons/ has no folder to look into")
		eq(logged("1 of them are in no folder the game reads") + logged("2 of them are in no folder the game reads"), 1,
			"zcg_content: and the files that are nowhere are said to be in no folder the game reads")
		ZCG.AddonFolder = nil
		M.files["addons/gloves 2.4.1/lua/autorun/zcity_csgo_gloves.lua"] = true
		M.files["addons/gloves 2.4.1/_not_used/materials/Ted_9.vmt"] = true
		M.log = {}
		M.command("zcg_content", me)
		eq(ZCG.AddonFolder, "addons/gloves 2.4.1", "zcg_content finds the folder of the addon by its Lua file")
		eq(logged("[in the folder of this addon, where the game does not look: addons/gloves 2.4.1/_not_used/materials/Ted_9.vmt]"), 1,
			"zcg_content: and looks into it")
		M.files["addons/gloves 2.4.1/lua/autorun/zcity_csgo_gloves.lua"] = nil
		M.files["addons/gloves 2.4.1/_not_used/materials/Ted_9.vmt"] = nil
		M.files["addons/other addon/lua/autorun/other.lua"] = nil
		ZCG.AddonFolder = "addons/zcity_csgo_gloves"
		M.files["addons/zcity_csgo_gloves/_not_used/materials/materials 9/Ted_9.vmt"] = true
		M.files["addons/zcity_csgo_gloves/materials/zcity_csgo_gloves/ted_9.txt"] = true
		M.files["addons/zcity_csgo_gloves/lua/ted_9.vmt"] = true
		M.log = {}
		M.command("zcg_content", me)
		check(M.log[1]:find("the appearance tables name 1 models and 43 materials", 1, true) ~= nil and M.log[1]:find("; 2 files are missing", 1, true) ~= nil,
			"zcg_content counts what can be worn: " .. tostring(M.log[1]))
		eq(logged(NINE .. "   [in the folder of this addon, where the game does not look: addons/zcity_csgo_gloves/_not_used/materials/materials 9/Ted_9.vmt]"), 1,
			"zcg_content finds a file that sort_content.bat put aside")
		eq(logged("1 of them lie in the folder of this addon outside of materials/ and models/ (addons/zcity_csgo_gloves/_not_used/materials/materials 9/Ted_9.vmt ...)"), 1,
			"and says that the game does not look there")
		eq(logged("_not_used is where sort_content.bat puts a file it found no place for"), 1, "and what that folder is")
		eq(logged("1 of them are nowhere: in no folder the game reads and nowhere in the folder of this addon (_not_used included), under no path."
			.. " sort_content.bat deletes nothing: either these files were never brought here, or it left them in a folder that was dropped onto it"), 1,
			"zcg_content says which files are on this computer under no name")
		eq(logged("sort_content.bat was cut off"), 0, "(no word about a run that was cut off)")
		eq(logged("2 more files are named only for faces that no player model of the menu can wear"), 1, "zcg_content tells the faces nobody can wear apart")
		eq(logged("    materials/models/faces/lake_facemap2.vmt  <-  face Face 2"), 1, "and names them")
		eq(logged("4 faces have no material file here: until the file is there they show the own face of the model"), 1,
			"zcg_content says what became of the faces without files")
		eq(logged("  the Lua that names them:"), 1, "zcg_content tells which Lua names the missing files")
		eq(logged("    2 - The \"Faces\" Pack (lua/pack/faces.lua)"), 1, "by the title of its pack")
		eq(logged("pack/lake.lua"), 0, "(not for what is not counted)")
		local text = M.written["zcg_content.txt"] or ""
		check(text:find("only for faces that no player model of the menu can wear - not counted:\nmaterials/models/faces/lake_facemap.vmt", 1, true) ~= nil,
			"the file of zcg_content has the faces nobody can wear, apart")
		-- a namesake that is at home: Z-City has a face of that very name, in its own folder
		ted["Face 3"] = "models/stock/faces/ted_9"
		M.files["materials/models/stock/faces/ted_9.vmt"] = true
		M.files["addons/zcity_csgo_gloves/_not_used/materials/materials 9/Ted_9.vmt"] = nil
		M.log = {}
		M.command("zcg_content", me)
		eq(logged(NINE .. "   [materials/models/stock/faces/ted_9.vmt has that name, but is another file: the tables name it there]"), 1,
			"zcg_content: a file of that name which the tables name where it lies is not taken for the missing one")
		eq(logged("have a file of the same name in another folder"), 0, "zcg_content: and nobody is sent to move it")
		eq(logged("2 of them are nowhere: in no folder the game reads"), 1, "zcg_content: the missing file counts as not there")
		-- (one that nobody names where it lies may be the missing file, a folder off)
		M.files["materials/models/elsewhere/ted_9.vmt"] = true
		M.log = {}
		M.command("zcg_content", me)
		eq(logged(NINE .. "   [a file of that name: materials/models/elsewhere/ted_9.vmt]"), 1,
			"zcg_content: a file of that name which nobody names where it lies is pointed at")
		eq(logged("1 of them have a file of the same name in another folder (materials/models/elsewhere/ted_9.vmt ...)"), 1, "zcg_content: and counted")
		M.files["materials/models/elsewhere/ted_9.vmt"] = nil
		ted["Face 3"] = nil
		M.files["materials/models/stock/faces/ted_9.vmt"] = nil
		M.files["addons/zcity_csgo_gloves/_not_used/materials/materials 9/Ted_9.vmt"] = true
		-- a run of sort_content.bat that was cut off left its files in _sorting, without their names
		M.files["addons/zcity_csgo_gloves/_sorting/000001"] = true
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("sort_content.bat was cut off while it moved files (the folder _sorting is still there): start it again"), 1,
			"zcg_content says that the sorting was cut off")
		M.files["addons/zcity_csgo_gloves/_sorting/000001"] = nil
		-- a file somebody else names, a material of a model
		AP.Clothes[1]["of another addon"] = "models/y/other"
		hg.Accessories = { hat = { model = MALE } }
		M.files["materials/models/humans/male/group01/players_sheet.vmt"] = nil
		M.log = {}
		M.command("zcg_content", me)
		eq(logged("    1 - Z-City itself or another addon (not the clothing Lua of this addon)"), 1, "zcg_content: a file the clothing Lua of this addon does not name")
		eq(logged("    1 - no Lua: materials that models of the menu are made of"), 1, "zcg_content: a material of a model")
		AP.Clothes[1]["of another addon"], hg.Accessories = nil, nil
		M.files["materials/models/humans/male/group01/players_sheet.vmt"] = true
		ZCG.AddonFolder = false

		-- the file arrives: zcg_content asks the disk anew, and the face is back
		M.files["materials/models/faces/ted_9.vmt"] = true
		eq(ZCG.FixFaces(), 4, "faces: (the disk is not asked twice for one file)")
		M.log = {}
		M.command("zcg_content", me)
		eq(ted["Face 9"], "Models\\Faces\\Ted_9", "faces: with its file a face is itself again")
		eq(logged("3 faces have no material file here"), 1, "faces: and is not counted any more")
		eq(ZCG.Faceless["FacemapsSlots/" .. TED .. "/Face 9"], nil, "faces: nor remembered")

		-- ---- a computer without the content is left alone
		for i = 1, 8 do M.files["materials/models/pack/shirt_" .. i .. ".vmt"] = nil end
		M.log = {}
		M.command("zcg_content", me)
		eq(ted["Face 10 (New)"] .. "|" .. lake["Face 1"], "models/humans/modern/male/male_02/facemap_01|models/faces/lake_facemap",
			"faces: where much of the content is missing the faces are put back as the clothing Lua made them")
		eq(next(ZCG.Faceless), nil, "faces: nothing is remembered then")
		eq(logged("1 of them are faces, and they stay purple and black squares: only 34 of the 43 materials the menu names are on this computer"), 1,
			"zcg_content says why the faces were left alone")
		eq(select(2, ZCG.FixFaces()), "share", "faces: and the function says so")
		M.setConVar("zcg_fix_faces", 2)
		eq(ZCG.FixFaces() .. "|" .. ted["Face 10 (New)"], "3|", "faces: zcg_fix_faces 2 does it on any computer")
		M.setConVar("zcg_fix_faces", 0)
		local nothing, off = ZCG.FixFaces()
		eq(tostring(nothing) .. "|" .. tostring(off) .. "|" .. ted["Face 10 (New)"], "nil|off|models/humans/modern/male/male_02/facemap_01",
			"faces: zcg_fix_faces 0 puts everything back")
		eq(ZCG.FacesLeft.faces .. "|" .. ZCG.FacesLeft.why, "3|off", "faces: and says how many there are")
		-- (two entries that come out under one name are never touched)
		AP.FacemapsSlots["models/x"] = { ["y/Face 2"] = "models/faces/nowhere_a" }
		AP.FacemapsSlots["models/x/y"] = { ["Face 2"] = "models/faces/nowhere_b" }
		M.setConVar("zcg_fix_faces", 2)
		ZCG.FixFaces()
		eq(AP.FacemapsSlots["models/x"]["y/Face 2"] .. "|" .. AP.FacemapsSlots["models/x/y"]["Face 2"], "models/faces/nowhere_a|models/faces/nowhere_b",
			"faces: entries that cannot be told apart by name are left alone")
		AP.FacemapsSlots["models/x"], AP.FacemapsSlots["models/x/y"] = nil, nil
		M.setConVar("zcg_fix_faces", 0)
		ZCG.FixFaces()
		M.setConVar("zcg_fix_faces", 1)
		for i = 1, 8 do M.files["materials/models/pack/shirt_" .. i .. ".vmt"] = true end
		M.command("zcg_content", me) -- (asks the disk anew)

		-- ---- by itself, while the game runs
		M.setConVar("zcg_fix_faces", 0)
		M.advance(300) -- (the passes of the starts above see that: nothing to tell)
		eq(ted["Face 10 (New)"], "models/humans/modern/male/male_02/facemap_01", "faces: (switched off, the faces are as the clothing Lua made them)")
		M.setConVar("zcg_fix_faces", 1)
		M.log = {}
		hook.Run("InitPostEntity")
		M.advance(2)
		eq(ted["Face 10 (New)"], "", "faces: a second after the start the faces without files are seen to")
		eq(logged("3 faces of the appearance menu have no material file on the client: they show the own face of the model"), 1, "faces: one line says so")
		ted["Face 10 (New)"] = "models/humans/modern/male/male_02/facemap_01"
		M.advance(125)
		eq(ted["Face 10 (New)"], "", "faces: a clothing Lua that writes its faces anew later is seen to as well")
		eq(logged("faces of the appearance menu have no material file"), 1, "faces: without a second line")
		-- the switch works at once
		M.setConVar("zcg_fix_faces", 0)
		M.advance(0.1)
		eq(ted["Face 10 (New)"] .. "|" .. logged("the faces of the appearance menu are as the clothing Lua made them again"),
			"models/humans/modern/male/male_02/facemap_01|1", "faces: switching it off puts the faces back at once, and says so")
		ZCG.FacesLeft = nil
		M.advance(300)
		eq(ZCG.FacesLeft, nil, "faces: switched off, the running game does not even look")
		M.setConVar("zcg_fix_faces", 1)
		M.advance(0.1)
		eq(ted["Face 10 (New)"] .. "|" .. logged("faces of the appearance menu have no material file"), "|2",
			"faces: switching it on works at once, and says so")
		-- a file that gets mounted while the game runs: the next look finds it
		M.files["materials/models/humans/modern/male/male_02/facemap_01.vmt"] = true
		M.advance(125)
		eq(ted["Face 10 (New)"], "models/humans/modern/male/male_02/facemap_01", "faces: a file that arrives while the game runs brings its face back")
		M.files["materials/models/humans/modern/male/male_02/facemap_01.vmt"] = nil
		M.command("zcg_content", me)
		eq(ted["Face 10 (New)"], "", "faces: (and gone again, the face is seen to again)")
		eq(#M.errors, 0, "faces: no errors: " .. table.concat(M.errors, " | "))

		M.setConVar("zcg_fix_faces", 0)
		ZCG.FixFaces()
		eq(ted["Face 10 (New)"] .. "|" .. tostring(next(ZCG.Faceless)), "models/humans/modern/male/male_02/facemap_01|nil",
			"faces: switched off again, everything is back")
		timer.Remove("zcg_faces")
		ZCG.Bound, ZCG.BoundPacks = nil, nil
		AP.Clothes, AP.PlayerModels = clothes, models
		AP.FacemapsSlots, AP.MultiFacemaps, AP.FacemapsModels = nil, nil, nil
		M.models[MALE], M.filedata[MALE] = nil, nil
		M.advance(300)
	end

	-- ================================================================ the Appearance Mod
	-- tools/test_lua.py unpacks the menu file of the mod and leaves its path here
	local sourcePath = rawget(_G, "ZCG_APPMOD_BUTTONS")
	if not sourcePath then return checks, failures end

	local handle = assert(io.open(sourcePath, "rb"))
	local source = handle:read("*a"):gsub("\r\n", "\n")
	handle:close()

	local function cut(what, pattern)
		local text = source:match(pattern)
		check(text ~= nil, "the source of the Appearance Mod still has " .. what)
		return text
	end
	local function replaceOnce(text, old, new)
		local from, to = text:find(old, 1, true)
		check(from ~= nil and text:find(old, to + 1, true) == nil, "the gloves window of the mod has exactly one: " .. old)
		if not from then return text end
		return text:sub(1, from - 1) .. new .. text:sub(to + 1)
	end

	local resolve = cut("ResolveCurrentModelData", "(local function ResolveCurrentModelData%(appearanceTable%).-\nend)\n")
	local gloves = cut("CreateGlovesIconMenu", "(local function CreateGlovesIconMenu%(.-\nend)\n\nlocal BODYGROUP_PART_CONFIG")
	local defaults = cut("EnsureAppearanceTableDefaults", "(local function EnsureAppearanceTableDefaults%(panel%).-\nend)\n")
	local compat = cut("OpenCompatibilityMenuForPart", "(local function OpenCompatibilityMenuForPart%(.-\nend)\n")
	local findButtons = cut("the code that wraps the buttons", "(    local function FindButtons%(parent%).-\n    end)\n\n    FindButtons%(panel%)")
	-- The mod tells when it has wrapped the buttons of a window - the version of it the build takes
	-- by default. Its LEGACY version (build_addon.py --pack) says nothing: this addon then finds the
	-- wrapped button with its own timer, which looks at the open window every half a second.
	local announces = source:find('hook.Run("HG_AppearanceMenuReady", zpan)', 1, true) ~= nil
	if rawget(_G, "ZCG_APPMOD_TITLE") == "Z-City Appearance Mod LEGACY" then
		check(not announces, "the LEGACY version of the mod does not announce a wrapped window (the timer of this addon finds it)")
	else
		check(announces, "the mod still announces a wrapped window with HG_AppearanceMenuReady")
	end
	local function announce(panel)
		if announces then hook.Run("HG_AppearanceMenuReady", panel) else M.advance(0.6) end
	end
	if not (resolve and gloves and defaults and compat and findButtons) then return checks, failures end

	-- the one piece of the game's dialect in there: "continue" (skips gloves the player does not own)
	gloves = replaceOnce(gloves, "if gloveData and gloveData[2] and not hasAccess and not hasItem then continue end",
		"if not (gloveData and gloveData[2] and not hasAccess and not hasItem) then")
	gloves = replaceOnce(gloves, "        grid:AddItem(icon)\n    end", "        grid:AddItem(icon)\n        end\n    end")
	check(gloves:find("continue", 1, true) == nil, "(no other continue in the gloves window)")

	local chunk = table.concat({
		"local colors = setmetatable({}, { __index = function() return Color(0, 0, 0) end })",
		"local clr_menu = Color(15, 15, 20, 250)",
		"local scrollPositions = {}",
		"local GLOVES_MENU_PREVIEW_COLS = 3",
		"local function EnsurePreviewPanelBounds() end",
		"local function FreezePreviewEntity() end",
		"local function ApplyPreviewAppearance() end",
		"local function GetDefaultHandsMaterialBySex() return 'models/humans/male/group01/normal' end",
		"local function PaintSelectionIcon() end",
		"local function CreateBodygroupIconMenu() end",
		"local function EnsurePartBodygroupButton() end",
		resolve, gloves, defaults, compat,
		"return function(panel)",
		"    local wrappedButtons, expectedButtons = 0, 0",
		"    local buttonMap = { Jacket = 'main', Pants = 'pants', Boots = 'boots', Gloves = 'gloves', Facemap = 'facemap' }",
		findButtons,
		"    FindButtons(panel)",
		"    panel.__AppearanceButtonsHooked = expectedButtons > 0 and wrappedButtons >= expectedButtons",
		"    return panel.__AppearanceButtonsHooked",
		"end",
	}, "\n")
	local compiled, problem = loadstring(chunk, "=appearance mod")
	check(compiled ~= nil, "the code of the Appearance Mod compiles: " .. tostring(problem))
	if not compiled then return checks, failures end
	CreateStyledScrollPanel = function(parent) return vgui.Create("DScrollPanel", parent) end
	local modifyAppearanceMenu = compiled()

	-- ---------------------------------------------------------------- helpers
	local HANDS = hg.Appearance.Bodygroups.HANDS
	eq(count(HANDS[1]), 3 + 81, "(the list of the game: three stock gloves and ours)")

	Z.registerEditor()
	M.advance(1)

	local function glovesButton(main)
		for _, child in ipairs(main.viewer:GetChildren()) do
			if child:GetText() == "Gloves" then return child end
		end
	end
	local function gridOf(panel)
		for _, child in ipairs(panel:GetChildren()) do
			if child.class == "DGrid" then return child end
			local found = gridOf(child)
			if found then return found end
		end
	end
	local function captionOf(tile)
		for _, child in ipairs(tile:GetChildren()) do
			if child.class == "DLabel" then return child:GetText() end
		end
		return "?"
	end
	local function tileOf(frame, caption)
		for _, tile in ipairs(gridOf(frame).Items) do
			if tile ~= frame.zcg_tile and captionOf(tile) == caption then return tile end
		end
	end
	local function captions(frame)
		local out = {}
		for _, tile in ipairs(gridOf(frame).Items) do
			out[#out + 1] = tile == frame.zcg_tile and "<CS:GO>" or captionOf(tile)
		end
		return table.concat(out, "|")
	end
	local function optionTexts(menu)
		local out = {}
		for _, option in ipairs(menu.options) do out[#out + 1] = option.text or "-" end
		return table.concat(out, "|")
	end
	local function pickerTiles()
		local tiles = {}
		for _, panel in ipairs(M.panels) do
			if not panel.removed and panel.zcg_variant then tiles[#tiles + 1] = panel end
		end
		return tiles
	end

	-- ================================================================ this addon first, then the mod
	local main = Z.openEditor(1920, 1080)
	M.advance(0.05) -- PostInit: this addon wraps the viewer and the button
	local button = glovesButton(main)
	local below = button.DoClick
	eq(main.viewer.zcg_wrapped, true, "(attached right after PostInit)")

	eq(modifyAppearanceMenu(main), true, "the mod wraps the buttons of the editor")
	eq(button.__AppearanceModWrapped, true, "(the Gloves button is one of them)")
	eq(button.__AppearanceOriginalDoClick, below, "(the handler of this addon is kept below the mod's)")
	local mods = button.DoClick
	check(mods ~= below, "(the handler of the mod is on the button)")

	announce(main)
	check(button.DoClick ~= mods and button.DoClick == button.zcg_mod, "this addon gets on top of the mod when it announces the window")
	local top = button.DoClick
	M.advance(2)
	eq(button.DoClick, top, "and stays there, wrapped once")

	-- the window of the mod
	me.accessToAll = true
	local created = #M.csmodels
	local frame = button:DoClick()
	check(ispanel(frame) and IsValid(frame), "a click opens the window of the mod")
	eq(frame.title, "Select Gloves - Default", "(its own window)")
	eq(main.modelPosID, "Hands", "(the mod puts the camera on the hands)")
	eq(captions(frame), "<CS:GO>|Gloves|None|Winter", "the window: the tile of this addon first, then the stock gloves, no CS:GO glove by name")
	eq(#M.csmodels - created, 3, "no preview model is made for the 81 gloves")
	eq(count(HANDS[1]), 3 + 81, "the gloves are back in the list after the click (male)")
	eq(count(HANDS[2]), 3 + 81, "the gloves are back in the list after the click (female)")
	check(istable(HANDS[1]["CS:GO Moto 05"]) and HANDS[1]["CS:GO Moto 05"].ZCG == "moto_5", "with the entries they had")

	local tile = frame.zcg_tile
	local stockTile = tileOf(frame, "None")
	eq(tile:GetWide(), stockTile:GetWide(), "the tile is as wide as the tiles of the mod")
	eq(tile:GetTall(), stockTile:GetTall(), "and as tall")
	M.texts, M.rects = {}, {}
	tile:Paint(tile:GetWide(), tile:GetTall())
	check(has(M.texts, "CS:GO gloves..."), "the tile is labelled")
	eq(#M.rects, 4, "no CS:GO glove selected: four icons of the collection")
	for _, rect in ipairs(M.rects) do
		check(rect.x >= 0 and rect.y >= 0 and rect.x + rect.w <= tile:GetWide() and rect.y + rect.h <= tile:GetTall(),
			"the icon stays inside the tile")
	end

	-- a stock glove is chosen the way the mod does it
	tileOf(frame, "Winter"):DoClick()
	M.flushPanels()
	eq(main.AppearanceTable.ABodygroups.HANDS, "Winter", "a stock glove is chosen in the window of the mod")
	check(not IsValid(frame), "(which closes)")
	eq(main.modelPosID, "All", "(and gives the camera back)")

	-- the tile opens the picker
	frame = button:DoClick()
	eq(frame.title, "Select Gloves - Winter", "(the window again)")
	frame.zcg_tile:DoClick()
	M.flushPanels()
	check(not IsValid(frame), "the tile closes the window of the mod")
	check(IsValid(main.zcg_picker), "and opens the picker")
	eq(main.modelPosID, "Hands", "the camera is on the hands while the picker is open")
	eq(#pickerTiles(), 81, "the picker shows every glove")
	for _, pick in ipairs(pickerTiles()) do
		if pick.zcg_variant.id == "sport_5" then pick:DoClick() end
	end
	M.flushPanels()
	eq(main.AppearanceTable.ABodygroups.HANDS, "CS:GO Sport 05", "a glove is chosen in the picker")
	check(not IsValid(main.zcg_picker), "the picker closes")
	eq(main.modelPosID, "All", "and the camera goes back")

	-- with a CS:GO glove selected
	frame = button:DoClick()
	eq(frame.title, "Select Gloves - CS:GO Sport 05", "(the mod names the selected glove in its title)")
	eq(captions(frame), "<CS:GO>|Gloves|None|Winter", "the selected glove is not listed by name either")
	M.texts, M.rects = {}, {}
	frame.zcg_tile:Paint(frame.zcg_tile:GetWide(), frame.zcg_tile:GetTall())
	check(has(M.texts, "Sport 05"), "the tile names the selected glove")
	eq(#M.rects, 1, "and shows its icon")
	eq(M.rects[1] and M.rects[1].mat.name, "zcity_csgo_gloves/icons/sport_5.png", "(that icon)")

	-- a click on the button while the picker is open
	frame.zcg_tile:DoClick()
	M.flushPanels()
	check(IsValid(main.zcg_picker), "(picker open)")
	frame = button:DoClick()
	M.flushPanels()
	check(not IsValid(main.zcg_picker), "a click on Gloves closes the picker")
	check(IsValid(frame), "and opens the window of the mod")
	frame:Close()
	M.flushPanels()

	-- gloves from the pointshop the player does not own: the rule of the mod
	me.accessToAll = nil
	frame = button:DoClick()
	eq(captions(frame), "<CS:GO>|None", "unowned stock gloves are left out by the mod, the tile is there")
	frame:Close()
	M.flushPanels()
	me.accessToAll = true

	-- a female model
	main.AppearanceTable.AModel = "Female 01"
	frame = button:DoClick()
	eq(captions(frame), "<CS:GO>|Gloves|None|Winter", "the window for a female model")
	eq(count(HANDS[2]), 3 + 81, "(the list is whole again)")
	frame:Close()
	M.flushPanels()
	main.AppearanceTable.AModel = "Male 01"

	-- the mod cannot open its window (it does not know the model): the menu of this addon instead
	main.AppearanceTable.AModel = "Nobody"
	local menus = #M.menus
	local result = button:DoClick()
	eq(result, nil, "no window of the mod for a model it does not know")
	eq(#M.menus, menus + 1, "the mod falls back to the menu below it")
	eq(optionTexts(M.menus[#M.menus]), "Gloves|None|Winter|-|CS:GO gloves...  [Sport 05]", "which is the menu of this addon")
	eq(count(HANDS[1]), 3 + 81, "(the list is whole again)")
	M.menus[#M.menus]:Remove()
	M.flushPanels()
	main.AppearanceTable.AModel = "Male 01"

	-- an error inside the mod
	local styled = CreateStyledScrollPanel
	CreateStyledScrollPanel = function() error("boom") end
	M.errors = {}
	result = button:DoClick()
	CreateStyledScrollPanel = styled
	eq(result, nil, "an error of the mod does not get through")
	eq(#M.errors, 1, "it is reported once")
	check(M.errors[1] ~= nil and M.errors[1]:find("boom", 1, true) ~= nil, "(with its message)")
	eq(count(HANDS[1]), 3 + 81, "and the gloves are back in the list")
	M.errors = {}
	frame = button:DoClick()
	eq(captions(frame), "<CS:GO>|Gloves|None|Winter", "the next click works as before")
	frame:Close()
	M.flushPanels()

	-- ================================================================ the mod first, then this addon
	local attach = ZCG.AttachEditor
	ZCG.AttachEditor = function() return false end
	local second = Z.openEditor(1920, 1080)
	M.advance(0.05)
	local button2 = glovesButton(second)
	local stock2 = button2.DoClick
	eq(second.viewer.zcg_wrapped, nil, "(a window this addon has not seen yet)")
	eq(modifyAppearanceMenu(second), true, "(the mod wraps it first)")
	eq(button2.__AppearanceOriginalDoClick, stock2, "(and keeps the stock handler)")
	ZCG.AttachEditor = attach
	announce(second)
	eq(second.viewer.zcg_wrapped, true, "this addon attaches when the mod announces the window")
	check(button2.__AppearanceOriginalDoClick ~= stock2, "its menu goes below the handler of the mod")
	check(button2.DoClick == button2.zcg_mod, "and its other handler on top")

	frame = button2:DoClick()
	eq(captions(frame), "<CS:GO>|Gloves|None|Winter", "mod first: the same window")
	frame:Close()
	M.flushPanels()

	second.AppearanceTable.AModel = "Nobody"
	menus = #M.menus
	button2:DoClick()
	eq(#M.menus, menus + 1, "mod first: it falls back to a menu")
	eq(optionTexts(M.menus[#M.menus]), "Gloves|None|Winter|-|CS:GO gloves...", "mod first: the menu of this addon")
	M.pickOption(M.menus[#M.menus], "CS:GO gloves")
	M.flushPanels()
	check(IsValid(second.zcg_picker), "mod first: the picker opens from that menu")
	second.zcg_picker:Remove()
	M.flushPanels()
	second.AppearanceTable.AModel = "Male 01"

	-- ================================================================ plain mode
	-- the window of the mod has no grid this addon recognises: no tile, every glove by name
	local getItems = M.builtin.DGrid.GetItems
	M.builtin.DGrid.GetItems = nil
	M.log = {}
	frame = button2:DoClick()
	M.builtin.DGrid.GetItems = getItems
	eq(second.zcg_plain, true, "an unknown window switches to the plain mode")
	check(ispanel(frame) and IsValid(frame), "the window is opened once more")
	eq(#gridOf(frame).Items, 3 + 81, "with every glove listed by the mod")
	eq(frame.zcg_tile, nil, "and without the tile")
	local noted = false
	for _, line in ipairs(M.log) do
		if line:find("Appearance Mod", 1, true) then noted = true end
	end
	check(noted, "the console says why")
	tileOf(frame, "CS:GO Moto 05"):DoClick()
	M.flushPanels()
	eq(second.AppearanceTable.ABodygroups.HANDS, "CS:GO Moto 05", "plain mode: a glove is chosen by its name")
	frame = button2:DoClick()
	eq(#gridOf(frame).Items, 3 + 81, "plain mode stays for this window")
	frame:Close()
	M.flushPanels()
	eq(#M.errors, 0, "none of this is an error: " .. table.concat(M.errors, " | "))

	-- ================================================================ the menu of this addon fails below the mod
	local third = Z.openEditor(1920, 1080)
	M.advance(0.05)
	local button3 = glovesButton(third)
	modifyAppearanceMenu(third)
	announce(third)
	local menu3 = button3.__AppearanceOriginalDoClick
	third.AppearanceTable.AModel = "Nobody" -- the mod falls back ...
	ZCG.Config.MenuText = 5 -- ... to a menu that cannot be built
	M.errors = {}
	button3:DoClick()
	ZCG.Config.MenuText = nil
	eq(#M.errors, 1, "a broken menu is reported once")
	eq(third.zcg_plain, true, "and ends in the plain mode")
	check(button3.__AppearanceOriginalDoClick ~= menu3, "the stock handler is back below the mod")
	check(button3.DoClick == button3.zcg_mod, "(the handler of the mod is not touched)")
	M.errors = {}
	menus = #M.menus
	button3:DoClick()
	eq(#M.menus, menus + 1, "the next click: the stock menu")
	eq(#M.menus[#M.menus].options, 3 + 81, "with every glove by name")

	eq(#M.errors, 0, "no errors at the end: " .. table.concat(M.errors, " | "))
	return checks, failures
end
