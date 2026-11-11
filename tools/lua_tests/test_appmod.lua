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
	check(source:find('hook.Run("HG_AppearanceMenuReady", zpan)', 1, true) ~= nil, "the mod still announces a wrapped window with HG_AppearanceMenuReady")
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

	hook.Run("HG_AppearanceMenuReady", main)
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
	hook.Run("HG_AppearanceMenuReady", second)
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
	hook.Run("HG_AppearanceMenuReady", third)
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
