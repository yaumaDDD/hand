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
	include("autorun/zcity_csgo_gloves.lua")
	local ZCG = ZCGloves

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

		-- nothing left to complain about
		AP.Clothes[1].bib, AP.Clothes[2].swiss, AP.PlayerModels[1]["Male 10"] = nil, nil, nil
		AP.FacemapsSlots, AP.MultiFacemaps, hg.Accessories = nil, nil, nil
		eq(#M.errors, 0, "content: no errors: " .. table.concat(M.errors, " | "))
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
