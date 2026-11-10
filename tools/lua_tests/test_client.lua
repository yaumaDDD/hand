-- Client-side scenarios: drawing on players / ragdolls and the appearance editor.
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

	local MOTO = "models/zcity_csgo_gloves/v_glove_motorcycle.mdl"
	local BLOODHOUND = "models/zcity_csgo_gloves/v_glove_bloodhound.mdl"
	local HYDRA = "models/zcity_csgo_gloves/v_glove_bloodhound_fingerless_hydra.mdl"
	local LEATHER = "models/zcity_csgo_gloves/v_glove_fullfinger.mdl"
	local HANDWRAP = "models/zcity_csgo_gloves/v_glove_handwrap_leathery.mdl"
	-- (the hard knuckle and broken fang models are "not installed")
	for _, path in ipairs({ MOTO, BLOODHOUND, HYDRA, LEATHER, HANDWRAP }) do M.files[path] = true end
	M.files["materials/zcity_csgo_gloves/icons/moto_5.png"] = true -- the other icons are "missing"

	local CLOTHES = "models/humans/male/group01/normal"
	local HANDS_SLOT = 4 -- "distac/gloves/hands" is the 5th material of the male mock model
	local HANDS_SLOT_F = 2

	Z.install()
	local me = M.newPlayer("me", Z.MALE)
	M.localplayer = me

	include("autorun/zcity_csgo_gloves.lua")
	local ZCG = ZCGloves
	eq(ZCG.Ready, true, "registered at load when Z-City is already there")
	eq(#M.csfiles, 0, "no AddCSLuaFile on the client")
	eq(ZCG.HideMaterial(), "null", "the game's null material is used when it exists")

	local function frame() M.frame = M.frame + 1 M.advance(0.02, 0.02) end
	local function alive(list)
		local n = 0
		for _, ent in ipairs(list) do if not ent.removed then n = n + 1 end end
		return n
	end
	local function lastModel() return M.csmodels[#M.csmodels] end

	-- the server applied the appearance: clothes on every slot, hands included
	local function dress(ent)
		ent.submats = {}
		for index = 0, #ent:GetMaterials() - 1 do ent.submats[index] = CLOTHES end
	end

	-- ---------------------------------------------------------------- a full-finger glove
	local alice = M.newPlayer("alice", Z.MALE)
	dress(alice)
	alice.nw.zcg_glove = "moto_5"

	Z.draw(alice)
	eq(#M.csmodels, 1, "one glove model created")
	local glove = lastModel()
	eq(glove.model, MOTO, "glove model path")
	eq(glove.nodraw, true, "the glove is drawn by hand")
	eq(glove.shadow, false, "no shadow")
	eq(glove:GetParent(), alice, "parented to the wearer")
	eq(glove.effects, EF_BONEMERGE, "bone merged")
	eq(glove:GetBodygroup(0), 4, "body group gloves = variant - 1")
	eq(glove:GetBodygroup(1), 0, "no sleeves")
	eq(glove:GetSubMaterial(0), "null", "the bare arm inside the glove model is hidden")
	eq(glove.draws, 1, "drawn once")
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "the wearer's hands are hidden")
	eq(alice:GetSubMaterial(0), CLOTHES, "the other slots are untouched")
	eq(M.drawn[#M.drawn], glove, "the glove is drawn after its wearer")
	eq(M.drawn[#M.drawn - 1], alice, "the wearer is drawn first")

	local writes, parents = alice.submatWrites, glove.parentSets
	for _ = 1, 10 do frame() Z.draw(alice) end
	eq(#M.csmodels, 1, "no model is created twice")
	eq(glove.draws, 11, "drawn every frame")
	eq(alice.submatWrites, writes, "the hands are not written again while they stay hidden")
	eq(glove.parentSets, parents, "the parent is not set again")

	-- the engine's colour modulation is put back
	render.SetColorModulation(0.2, 0.4, 0.6)
	frame() Z.draw(alice)
	local r, g, b = render.GetColorModulation()
	check(r == 0.2 and g == 0.4 and b == 0.6, "colour modulation restored")
	render.SetColorModulation(1, 1, 1)

	-- the server networks the clothes again (new appearance): hidden again, new value remembered
	alice.submats[HANDS_SLOT] = "models/humans/male/group01/other"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "hidden again after the server changed the slot")

	-- another colour of the same model: same entity, other body group
	alice.nw.zcg_glove = "moto_7"
	frame() Z.draw(alice)
	eq(#M.csmodels, 1, "same model for another colour")
	eq(glove:GetBodygroup(0), 6, "body group follows the variant")

	-- a fingerless glove: other model, the hands come back with the latest server value
	alice.nw.zcg_glove = "bloodhound_2"
	frame() Z.draw(alice)
	eq(#M.csmodels, 2, "a new model for another family")
	eq(glove.removed, true, "the old glove model is removed")
	glove = lastModel()
	eq(glove.model, BLOODHOUND, "bloodhound model")
	eq(glove:GetBodygroup(0), 1, "bloodhound variant")
	eq(alice:GetSubMaterial(HANDS_SLOT), "models/humans/male/group01/other", "hands restored for fingerless gloves")

	-- hydra hides material 1, not 0
	alice.nw.zcg_glove = "hydra_3"
	frame() Z.draw(alice)
	glove = lastModel()
	eq(glove.model, HYDRA, "hydra model")
	eq(glove:GetSubMaterial(1), "null", "hydra: bare arm is material 1")
	eq(glove:GetSubMaterial(0), "", "hydra: material 0 is the glove")

	-- gloves off
	alice.nw.zcg_glove = "moto_1"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "hidden again")
	alice.nw.zcg_glove = "none"
	local draws = lastModel().draws
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "models/humans/male/group01/other", "hands restored when the glove is taken off")
	eq(lastModel().draws, draws, "nothing is drawn without a glove")
	M.advance(17)
	eq(alive(M.csmodels), 0, "unused glove models are removed")
	check(ZCG.States[alice] == nil, "state forgotten")

	-- hands that had no sub-material at all
	alice.submats = {}
	alice.nw.zcg_glove = "leather_1"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "hidden (no previous sub-material)")
	alice.nw.zcg_glove = "none"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "", "restored to no sub-material")

	-- the server wiped our value while we were hiding (SetSubMaterial() + new clothes): nothing to restore
	dress(alice)
	alice.nw.zcg_glove = "leather_1"
	frame() Z.draw(alice)
	alice.submats[HANDS_SLOT] = "fresh/clothes"
	alice.nw.zcg_glove = "none"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "fresh/clothes", "a newer server value is not overwritten on restore")

	-- ---------------------------------------------------------------- hands reappear when nobody draws
	dress(alice)
	alice.nw.zcg_glove = "moto_2"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "hidden")
	M.advance(2.5) -- e.g. the render override went away
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "hands come back when the glove is not drawn any more")
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "and are hidden again with the next draw")

	-- ---------------------------------------------------------------- model change
	alice:SetModel(Z.FEMALE)
	dress(alice)
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT_F), "null", "hands slot of the new model is hidden")
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "the old slot index is left alone")
	alice.nw.zcg_glove = "none"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT_F), CLOTHES, "restored on the new model")

	-- a model without the hands material (zcg_any_model 1 on a class model): glove drawn, nothing hidden
	local dave = M.newPlayer("dave", Z.COMBINE)
	dress(dave)
	dave.nw.zcg_glove = "moto_3"
	Z.draw(dave)
	eq(lastModel():GetParent(), dave, "glove on a foreign model")
	eq(dave:GetSubMaterial(0), CLOTHES, "nothing hidden on a foreign model")
	eq(dave.submatWrites, nil, "no sub-material written on a foreign model")

	-- ---------------------------------------------------------------- convars
	alice:SetModel(Z.MALE)
	dress(alice)
	alice.nw.zcg_glove = "moto_2"
	frame() Z.draw(alice)
	M.setConVar("zcg_hide_hands", 0)
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "zcg_hide_hands 0 gives the hands back")
	check(lastModel().draws >= 1, "the glove is still drawn")
	M.setConVar("zcg_hide_hands", 1)

	ZCG.Config.HideHands = { moto = false, bloodhound = true }
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "Config.HideHands can keep the hands of a family")
	alice.nw.zcg_glove = "bloodhound_1"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "Config.HideHands can hide the hands of a family")
	ZCG.Config.HideHands = {}
	alice.nw.zcg_glove = "moto_2"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "default again")

	M.setConVar("zcg_enable", 0)
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "zcg_enable 0 restores the hands at once")
	eq(alive(M.csmodels), 0, "zcg_enable 0 removes the glove models")
	local count = #M.csmodels
	frame() Z.draw(alice)
	eq(#M.csmodels, count, "nothing is created while disabled")
	M.setConVar("zcg_enable", 1)
	frame() Z.draw(alice)
	eq(#M.csmodels, count + 1, "drawing again after zcg_enable 1")

	-- ---------------------------------------------------------------- ragdolls
	local rag = M.newEntity("prop_ragdoll", Z.MALE)
	dress(rag)
	rag.nw.ply = alice
	Z.draw(rag, alice)
	eq(lastModel():GetParent(), rag, "a fresh ragdoll takes the glove of its owner")
	eq(rag:GetSubMaterial(HANDS_SLOT), "null", "the ragdoll's hands are hidden too")
	rag.nw.zcg_glove = "none"
	frame() Z.draw(rag, alice)
	eq(rag:GetSubMaterial(HANDS_SLOT), CLOTHES, "the ragdoll's own value wins once it arrived")
	rag.nw.zcg_glove = "handwrap_4"
	rag.nw.ply = NULL
	frame() Z.draw(rag)
	eq(lastModel():GetParent(), rag, "a dead body keeps its glove without an owner")
	eq(lastModel().model, HANDWRAP, "the dead body's own glove")
	eq(lastModel():GetBodygroup(0), 3, "the dead body's own variant")

	local stray = M.newEntity("prop_ragdoll", Z.MALE)
	count = #M.csmodels
	Z.draw(stray)
	eq(#M.csmodels, count, "a ragdoll that is nobody's wears nothing")

	-- the ragdoll disappears: its glove model goes with it
	local ragGlove = lastModel()
	rag:Remove()
	M.advance(1.5)
	eq(ragGlove.removed, true, "glove model of a removed ragdoll is removed")

	-- ---------------------------------------------------------------- amputations
	alice.organism = { larmamputated = true }
	draws = ZCG.States[alice].mdl.draws
	frame() Z.draw(alice)
	eq(ZCG.States[alice].mdl.draws, draws + 1, "one arm left: the glove is drawn")
	alice.organism.rarmamputated = true
	frame() Z.draw(alice)
	eq(ZCG.States[alice].mdl.draws, draws + 1, "no arms, no gloves")
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "hands restored without arms")
	alice.organism = nil

	-- ---------------------------------------------------------------- content missing on this client
	local bob = M.newPlayer("bob", Z.MALE)
	dress(bob)
	bob.nw.zcg_glove = "brokenfang_1" -- its model file is not "installed"
	M.log = {}
	count = #M.csmodels
	Z.draw(bob)
	frame() Z.draw(bob)
	eq(#M.csmodels, count, "no model is created when the file is missing")
	eq(#M.log, 1, "exactly one warning about missing content")
	bob.nw.zcg_glove = "hardknuckle_2" -- full-finger and missing
	frame() Z.draw(bob)
	eq(bob:GetSubMaterial(HANDS_SLOT), CLOTHES, "hands are not hidden when the glove cannot be drawn")
	eq(#M.log, 1, "still one warning")

	-- ---------------------------------------------------------------- zcg_preview / zcg_debug
	dress(me)
	M.command("zcg_preview", me, "moto_9")
	Z.draw(me)
	eq(lastModel():GetParent(), me, "zcg_preview shows a glove on the local player")
	eq(lastModel():GetBodygroup(0), 8, "zcg_preview variant")
	frame() Z.draw(alice)
	eq(ZCG.States[alice].variant.id, "moto_2", "zcg_preview does not touch other players")
	M.command("zcg_preview", me, "nonsense")
	eq(ZCG.LocalOverride.id, "moto_9", "unknown ids are ignored")
	M.command("zcg_preview", me)
	M.command("zcg_preview", me, "off")
	eq(ZCG.LocalOverride, nil, "zcg_preview off")
	frame() Z.draw(me)
	eq(me:GetSubMaterial(HANDS_SLOT), CLOTHES, "preview off restores the hands")
	local auto = concommand.list.zcg_preview.auto("zcg_preview", " mot")
	eq(#auto, 13 + 1, "autocomplete lists the matching ids")

	me.lookat = alice
	M.log = {}
	M.command("zcg_debug", me)
	check(#M.log > 8, "zcg_debug prints a report")
	me.lookat = nil
	M.command("zcg_debug", me)

	eq(#M.errors, 0, "no errors so far: " .. table.concat(M.errors, " | "))

	-- ---------------------------------------------------------------- without the null material
	do
		local saved = M.materials["null"]
		M.materials["null"] = nil
		M.files["materials/zcity_csgo_gloves/invisible"] = true
		ZCGloves = nil
		local keep = { hook.list, timer.list, concommand.list, cvars.callbacks }
		include("autorun/zcity_csgo_gloves.lua")
		eq(ZCGloves.HideMaterial(), "zcity_csgo_gloves/invisible", "own material when the game has no null material")
		ZCGloves.Config.HideMaterial = "engine/occlusionproxy"
		eq(ZCGloves.HideMaterial(), "zcity_csgo_gloves/invisible", "the choice is made once")
		M.materials["null"] = saved
		ZCGloves = nil
		include("autorun/zcity_csgo_gloves.lua")
		ZCG = ZCGloves
		eq(ZCG.HideMaterial(), "null", "null again")
	end

	-- ---------------------------------------------------------------- errors do not repeat forever
	do
		local carol = M.newPlayer("carol", Z.MALE)
		dress(carol)
		carol.nw.zcg_glove = "moto_4"
		Z.draw(carol)
		eq(carol:GetSubMaterial(HANDS_SLOT), "null", "carol's hands hidden")
		local broken = ZCG.States[carol].mdl
		broken.DrawModel = function() error("boom") end
		M.errors = {}
		for _ = 1, 20 do frame() Z.draw(carol) end
		eq(#M.errors, 5, "drawing stops after five errors")
		eq(carol:GetSubMaterial(HANDS_SLOT), CLOTHES, "hands are given back when drawing is switched off")
		eq(broken.removed, true, "models are removed when drawing is switched off")
		M.errors = {}

		-- start over for the editor tests
		ZCGloves = nil
		include("autorun/zcity_csgo_gloves.lua")
		ZCG = ZCGloves
	end

	-- ================================================================ the appearance editor
	Z.registerEditor()
	M.advance(1) -- the timer wraps the freshly registered class
	local class = vgui.GetControlTable("HG_AppearanceMenu")
	local wrappedPostInit = class.PostInit
	M.advance(2)
	eq(class.PostInit, wrappedPostInit, "PostInit is wrapped only once")

	local main = Z.openEditor(1920, 1080)
	check(main.viewer == nil, "the window is not built yet")
	M.advance(0.05) -- timer.Simple(0) -> First -> PostInit
	local viewer = main.viewer
	eq(viewer.zcg_wrapped, true, "attached right after PostInit")
	local button
	for _, child in ipairs(viewer:GetChildren()) do
		if child:GetText() == "Gloves" then button = child end
	end

	-- preview of a selected CS:GO glove
	main.AppearanceTable.ABodygroups.HANDS = "CS:GO Moto 05"
	Z.paintViewer(viewer)
	local preview = viewer.Entity
	glove = lastModel()
	eq(glove:GetParent(), preview, "the editor model wears the selected glove")
	eq(glove:GetBodygroup(0), 4, "the right variant in the editor")
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "hands hidden in the editor")
	eq(main.accessoriesDrawn, 1, "the original PostDrawModel still runs")
	eq(M.drawn[#M.drawn], glove, "glove drawn after the editor model")
	count = #M.csmodels
	for _ = 1, 5 do frame() Z.paintViewer(viewer) end
	eq(#M.csmodels, count, "no new models while the editor repaints")
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "hidden in every frame although the editor resets the materials")

	-- a fingerless one keeps the hands
	main.AppearanceTable.ABodygroups.HANDS = "CS:GO Bloodhound 03"
	frame() Z.paintViewer(viewer)
	eq(preview:GetSubMaterial(HANDS_SLOT), CLOTHES, "fingerless: hands visible in the editor")
	eq(lastModel().model, BLOODHOUND, "fingerless glove drawn in the editor")

	-- a stock glove: ours disappears
	local editorGlove = lastModel()
	main.AppearanceTable.ABodygroups.HANDS = "Gloves"
	frame() Z.paintViewer(viewer)
	eq(editorGlove.removed, true, "the CS:GO glove model is removed for a stock glove")
	check(ZCG.States[preview] == nil, "editor state cleared")

	-- the appearance model changes: the editor swaps its entity
	main.AppearanceTable.ABodygroups.HANDS = "CS:GO Leather"
	main.AppearanceTable.AModel = "Female 01"
	frame() Z.paintViewer(viewer)
	frame() Z.paintViewer(viewer)
	check(viewer.Entity ~= preview, "the editor created a new entity")
	preview = viewer.Entity
	eq(lastModel():GetParent(), preview, "glove moved to the new editor entity")
	eq(preview:GetSubMaterial(HANDS_SLOT_F), "null", "hands hidden on the female model")
	main.AppearanceTable.AModel = "Male 01"
	frame() Z.paintViewer(viewer)
	frame() Z.paintViewer(viewer)
	preview = viewer.Entity

	-- ---------------------------------------------------------------- the Gloves menu
	local function optionTexts(menu)
		local out = {}
		for _, option in ipairs(menu.options) do out[#out + 1] = option.text or "-" end
		return table.concat(out, "|")
	end

	button:DoClick()
	local menu = M.menus[#M.menus]
	eq(optionTexts(menu), "None|-|CS:GO gloves...  [Leather]", "menu: unowned stock gloves are hidden, ours are behind one entry")
	eq(main.modelPosID, "Hands", "camera on the hands while the menu is open")
	eq(menu.opened, true, "menu opened")
	menu:Remove() M.flushPanels()
	eq(main.modelPosID, "All", "camera back when the menu closes")

	me.items = { ["Standard_BodyGroups_Gloves"] = true }
	button:DoClick()
	menu = M.menus[#M.menus]
	eq(optionTexts(menu), "Gloves|None|-|CS:GO gloves...  [Leather]", "menu: owned stock gloves are listed")
	M.pickOption(menu, "Gloves") M.flushPanels()
	eq(main.AppearanceTable.ABodygroups.HANDS, "Gloves", "a stock glove can still be chosen")
	eq(main.modelPosID, "All", "camera back after choosing")
	eq(#M.sounds, 1, "selection sound")

	me.items = nil
	me.accessToAll = true
	button:DoClick()
	menu = M.menus[#M.menus]
	eq(optionTexts(menu), "Gloves|None|Winter|-|CS:GO gloves...", "menu: access to all lists every stock glove")
	me.accessToAll = nil

	-- ---------------------------------------------------------------- the picker
	M.pickOption(menu, "CS:GO gloves") M.flushPanels()
	local picker = main.zcg_picker
	check(IsValid(picker), "picker opened")
	eq(main.modelPosID, "Hands", "camera stays on the hands while the picker is open")

	local tiles = {}
	for _, panel in ipairs(M.panels) do
		if not panel.removed and panel.zcg_variant then tiles[#tiles + 1] = panel end
	end
	eq(#tiles, 44, "one tile per glove")
	local px, py = picker:GetPos()
	check(px >= 0 and px + picker:GetWide() <= 1920, "picker inside the window (x)")
	check(py >= 0 and py + picker:GetTall() <= 1080, "picker inside the window (y)")
	check(px >= 1920 / 2 + 0.45 * 1080, "picker does not cover the hands at 1920x1080")
	local seen = {}
	for _, tile in ipairs(tiles) do
		local x, y = tile:GetPos()
		local key = x .. ":" .. y
		check(not seen[key], "tiles do not overlap (" .. tile.zcg_variant.id .. ")")
		seen[key] = true
		check(x + tile:GetWide() <= picker:GetWide(), "tile inside the picker (" .. tile.zcg_variant.id .. ")")
	end

	M.texts = {}
	M.paint(picker) -- runs every Paint / Think once
	check(#M.texts > 0, "picker painted")
	eq(M.texts[1], "CS:GO gloves", "title shown when nothing is hovered or selected")

	-- hover = try on
	local function tileOf(id)
		for _, tile in ipairs(tiles) do
			if tile.zcg_variant.id == id then return tile end
		end
	end
	M.hovered = tileOf("moto_5")
	M.paint(picker)
	eq(main.zcg_preview and main.zcg_preview.id, "moto_5", "hovering previews a glove")
	frame() Z.paintViewer(viewer)
	eq(lastModel().model, MOTO, "the hovered glove is on the editor model")
	eq(lastModel():GetBodygroup(0), 4, "hovered variant")
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "hands hidden for the hovered glove")
	eq(main.AppearanceTable.ABodygroups.HANDS, "Gloves", "hovering does not select")
	M.texts = {}
	M.paint(picker)
	check(table.concat(M.texts, "|"):find("Moto 05 - Finish Line", 1, true) ~= nil, "the hovered glove is named in the header")

	M.hovered = tileOf("bloodhound_1")
	M.paint(picker)
	frame() Z.paintViewer(viewer)
	eq(lastModel().model, BLOODHOUND, "preview follows the cursor")
	eq(preview:GetSubMaterial(HANDS_SLOT), CLOTHES, "hands back for a fingerless preview")

	M.hovered = picker
	M.paint(picker)
	eq(main.zcg_preview, nil, "no preview when no tile is hovered")
	frame() Z.paintViewer(viewer)
	check(ZCG.States[preview] == nil, "the stock glove is shown again")

	-- a click inside keeps the picker, click on a tile selects
	M.mouse[MOUSE_LEFT] = true
	M.paint(picker)
	check(IsValid(picker), "a click inside the picker keeps it open")
	M.mouse[MOUSE_LEFT] = false
	M.paint(picker)

	M.hovered = tileOf("handwrap_8")
	M.paint(picker)
	local sounds = #M.sounds
	M.hovered:DoClick()
	M.flushPanels()
	eq(main.AppearanceTable.ABodygroups.HANDS, "CS:GO Hand Wraps 08", "clicking a tile selects the glove")
	check(not IsValid(picker), "the picker closes after a choice")
	eq(main.zcg_preview, nil, "preview cleared")
	eq(main.zcg_picker, nil, "picker forgotten")
	eq(main.modelPosID, "All", "camera back after the picker")
	eq(#M.sounds, sounds + 1, "selection sound from the picker")
	M.hovered = nil

	-- click outside closes; the click that opened the picker does not
	button:DoClick()
	menu = M.menus[#M.menus]
	eq(optionTexts(menu), "None|-|CS:GO gloves...  [Hand Wraps 08]", "the menu names the current CS:GO glove")
	M.mouse[MOUSE_LEFT] = true -- still held from choosing the menu entry
	M.pickOption(menu, "CS:GO gloves") M.flushPanels()
	picker = main.zcg_picker
	M.hovered = viewer
	M.paint(picker)
	check(IsValid(picker), "the opening click does not close the picker")
	M.mouse[MOUSE_LEFT] = false
	M.paint(picker)
	M.mouse[MOUSE_LEFT] = true
	M.paint(picker)
	check(not IsValid(picker), "a click outside closes the picker")
	M.flushPanels()
	M.mouse[MOUSE_LEFT] = false
	eq(main.modelPosID, "All", "camera back after closing by a click outside")
	eq(main.AppearanceTable.ABodygroups.HANDS, "CS:GO Hand Wraps 08", "closing does not change the selection")
	M.hovered = nil

	-- the Gloves button while the picker is open: the picker closes, the camera stays
	button:DoClick()
	M.pickOption(M.menus[#M.menus], "CS:GO gloves") M.flushPanels()
	picker = main.zcg_picker
	button:DoClick() -- (the deferred OnRemove of the picker runs after the new menu is open)
	check(not IsValid(picker), "picker closed by the button")
	M.flushPanels()
	eq(main.modelPosID, "Hands", "the camera stays on the hands for the new menu")
	M.menus[#M.menus]:Remove() M.flushPanels()
	eq(main.modelPosID, "All", "and goes back afterwards")

	-- somebody else moved the camera meanwhile: leave it alone
	button:DoClick()
	M.pickOption(M.menus[#M.menus], "CS:GO gloves") M.flushPanels()
	main.zcg_picker:Remove()
	main.modelPosID = "Face"
	M.flushPanels()
	eq(main.modelPosID, "Face", "another menu's camera position is respected")
	main.modelPosID = "All"

	-- the selection hook
	hook.Add("ZCityCSGOGloves_CanSelect", "test", function(ply, variant)
		if variant.family.id == "moto" or variant.id == "leather_1" then return false end
	end)
	button:DoClick()
	M.pickOption(M.menus[#M.menus], "CS:GO gloves") M.flushPanels()
	local shown = 0
	for _, panel in ipairs(M.panels) do
		if not panel.removed and panel.zcg_variant then
			shown = shown + 1
			check(panel.zcg_variant.family.id ~= "moto", "moto hidden by the hook")
		end
	end
	eq(shown, 44 - 13 - 1, "CanSelect hook removes tiles")
	main.zcg_picker:Remove() M.flushPanels()
	hook.Remove("ZCityCSGOGloves_CanSelect", "test")

	-- ---------------------------------------------------------------- other screen sizes
	for _, size in ipairs({ { 1024, 768 }, { 1280, 1024 }, { 1366, 768 }, { 2560, 1440 }, { 3440, 1440 }, { 800, 600 } }) do
		M.scrw, M.scrh = size[1], size[2]
		local tag = size[1] .. "x" .. size[2]
		local win = Z.openEditor(size[1], size[2])
		M.advance(0.1)
		local btn
		for _, child in ipairs(win.viewer:GetChildren()) do
			if child:GetText() == "Gloves" then btn = child end
		end
		btn:DoClick()
		M.pickOption(M.menus[#M.menus], "CS:GO gloves") M.flushPanels()
		local p = win.zcg_picker
		check(IsValid(p), tag .. ": picker opened")
		local x, y = p:GetPos()
		check(x >= 0 and x + p:GetWide() <= size[1], tag .. ": picker inside the window (x)")
		check(y >= 0 and y + p:GetTall() <= size[2], tag .. ": picker inside the window (y)")
		check(p:GetWide() >= 100 and p:GetTall() >= 100, tag .. ": picker has a usable size")
		M.hovered = nil
		M.paint(p)
		win.AppearanceTable.ABodygroups.HANDS = "CS:GO Hand Wraps 08"
		M.hovered = nil
		M.paint(p) -- long name in a possibly narrow header
		p:Remove() M.flushPanels()
		win:Remove() M.flushPanels()
	end
	M.scrw, M.scrh = 1920, 1080

	-- ---------------------------------------------------------------- PostInit runs twice
	do
		local win = Z.openEditor(1920, 1080)
		M.advance(0.05)
		local first = win.viewer
		win:PostInit() -- builds a second model panel
		check(win.viewer ~= first, "a second model panel was built")
		eq(win.viewer.zcg_wrapped, true, "the rebuilt model panel is hooked as well")
		win.AppearanceTable.ABodygroups.HANDS = "CS:GO Moto 01"
		Z.paintViewer(win.viewer)
		eq(lastModel():GetParent(), win.viewer.Entity, "preview on the rebuilt model panel")
		win:Remove() M.flushPanels()
	end

	-- ---------------------------------------------------------------- an editor that is already open
	do
		-- the addon is (re)loaded while an editor built by the unwrapped class is on screen
		local PLAIN = {}
		for k, v in pairs(vgui.GetControlTable("HG_AppearanceMenu")) do PLAIN[k] = v end
		Z.registerEditor() -- fresh, unwrapped class
		local win = Z.openEditor(1920, 1080)
		win:PostInit()
		check(not win.viewer.zcg_wrapped, "built without the addon")
		M.advance(1)
		eq(win.viewer.zcg_wrapped, true, "the timer attaches to an editor that is already open (global zpan)")
		win.AppearanceTable.ABodygroups.HANDS = "CS:GO Moto 01"
		Z.paintViewer(win.viewer)
		eq(lastModel():GetParent(), win.viewer.Entity, "and the preview works there")
		win:Remove() M.flushPanels()
		zpan = nil
	end

	-- ---------------------------------------------------------------- editors this addon does not understand
	do
		-- no Gloves button
		local PANEL = {}
		function PANEL:PostInit()
			self.AppearanceTable = { AModel = "Male 01", ABodygroups = {} }
			local v = vgui.Create("DModelPanel", self)
			v:SetModel(Z.MALE)
			function v:LayoutEntity() end
			function v:PostDrawModel() end
			self.viewer = v
		end
		vgui.Register("HG_AppearanceMenu", PANEL, "DFrame")
		M.advance(1)
		local win = vgui.Create("HG_AppearanceMenu")
		win:PostInit()
		eq(win.viewer.zcg_wrapped, true, "attached without a Gloves button")
		win.AppearanceTable.ABodygroups.HANDS = "CS:GO Moto 02"
		Z.paintViewer(win.viewer)
		eq(lastModel():GetParent(), win.viewer.Entity, "preview works without the button")

		-- no model panel at all
		local PANEL2 = {}
		function PANEL2:PostInit() self.AppearanceTable = {} end
		vgui.Register("HG_AppearanceMenu", PANEL2, "DFrame")
		M.advance(1)
		local win2 = vgui.Create("HG_AppearanceMenu")
		win2:PostInit()
		eq(ZCG.AttachEditor(win2), false, "nothing to attach to: left alone")

		-- a Gloves button whose surroundings changed: our menu fails -> stock menu from then on
		local stockClicks = 0
		local PANEL3 = {}
		function PANEL3:PostInit()
			self.AppearanceTable = nil -- breaks our menu
			local v = vgui.Create("DModelPanel", self)
			v:SetModel(Z.MALE)
			self.viewer = v
			local b = vgui.Create("DButton", v)
			b:SetText("Gloves")
			function b:DoClick() stockClicks = stockClicks + 1 end
			self.button = b
		end
		vgui.Register("HG_AppearanceMenu", PANEL3, "DFrame")
		M.advance(1)
		local win3 = vgui.Create("HG_AppearanceMenu")
		win3:PostInit()
		M.errors = {}
		win3.button:DoClick()
		eq(stockClicks, 1, "the stock menu opens when ours fails")
		eq(#M.errors, 1, "the failure is reported once")
		win3.button:DoClick()
		eq(stockClicks, 2, "the stock menu stays")
		eq(#M.errors, 1, "no further reports")
		Z.paintViewer(win3.viewer) -- AppearanceTable is nil: the preview must cope
		eq(#M.errors, 1, "preview copes with a missing appearance table")
		M.errors = {}
	end

	eq(#M.errors, 0, "no errors at the end: " .. table.concat(M.errors, " | "))
	return checks, failures
end
