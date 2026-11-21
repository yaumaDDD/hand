-- Faces in every table the menus of Z-City read (sh_faces.lua).
--
-- Z-City has two systems of faces: FacemapsSlots of the gamemode (what a clothing pack writes by
-- calling AddFacemap) and MultiFacemaps of the Appearance Mod. The menu of the mod lists the faces
-- of a model from MultiFacemaps alone as soon as the model has one entry in it, and the editor of
-- Z-City, its random faces and the LEGACY build read FacemapsSlots alone - so a face that is in
-- one of the two has no button in the menu that reads the other. The shapes of the tables and the
-- way they are read here are taken from the real files: homigrad/new_appearance/sh_shared.lua and
-- derma/cl_appearance_editor1.lua (the gamemode), zcityappearancemod/sh_shared_appearancemod_addition.lua
-- and derma/cl_!!!_appearancemod_buttons.lua (the mod).
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
	-- a scenario leaves what it made behind: the next one starts as the game does
	local function fresh()
		hg, ZCO, ZCGloves = nil, nil, nil
		for _, name in ipairs({ "AppAddModel", "AppAddClothes", "AppAddClothesDesc", "AddFacemap", "AppAddBodygroup" }) do
			_G[name] = nil
		end
	end

	-- the faces the menu of the Appearance Mod lists for a model: MultiFacemaps alone when the
	-- model has an entry in it, the table of the gamemode only where it has none
	-- (cl_!!!_appearancemod_buttons.lua: "if multi then combinedVariants = multi else ... end")
	local function modMenu(AP, model)
		local names = {}
		local multi = AP.MultiFacemaps and AP.MultiFacemaps[string.lower(model)]
		if istable(multi) then
			for name, bySlot in pairs(multi) do
				-- (a face with no material behind it is no face: "Default" is the choice of none)
				for _, path in pairs(istable(bySlot) and bySlot or {}) do
					if isstring(path) and path ~= "" then names[name] = true end
				end
			end
			return names
		end
		local slot = AP.FacemapsModels and AP.FacemapsModels[string.lower(model)]
		local list = slot and AP.FacemapsSlots and AP.FacemapsSlots[slot]
		if istable(list) then
			for name, path in pairs(list) do
				if isstring(path) and path ~= "" then names[name] = true end
			end
		end
		return names
	end
	-- the faces the editor of Z-City lists: FacemapsSlots of the slot the model is told to wear,
	-- by the very key the Lua wrote (cl_appearance_editor1.lua: FacemapsSlots[FacemapsModels[tMdl.mdl]]).
	-- nil where the model is told no slot: there the plain menu lists nothing at all.
	local function plainMenu(AP, model)
		local models = AP.FacemapsModels
		if not istable(models) then return nil end
		local slot = models[model] or models[string.lower(model)]
		if not isstring(slot) then return nil end
		local list = AP.FacemapsSlots and AP.FacemapsSlots[slot]
		if not istable(list) then return nil end
		local names = {}
		for name, path in pairs(list) do
			if isstring(path) and path ~= "" then names[name] = true end
		end
		return names
	end
	local function same(a, b)
		for name in pairs(a) do
			if not b[name] then return false end
		end
		for name in pairs(b) do
			if not a[name] then return false end
		end
		return true
	end

	-- ------------------------------------------- the addon alone: no Z-City, no mod, no pack
	local M = dofile(testdir .. "/gmod_mock.lua")("server")
	local Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	check(hg == nil, "there is no Z-City and no Appearance Mod before the addon loads")
	include("autorun/zcity_csgo_gloves.lua")
	local ZCG = ZCGloves
	eq(ZCG.LoadErrors, nil, "every file of the addon loaded: " .. tostring(ZCG.LoadErrors and ZCG.LoadErrors[1] or ""))
	check(type(ZCG.SyncFaces) == "function", "ZCG.SyncFaces is there")
	check(type(ZCG.FaceReport) == "function", "ZCG.FaceReport is there")
	check(M.convars["zcg_sync_faces"] ~= nil, "the convar zcg_sync_faces is there")
	eq(M.convars["zcg_sync_faces"] and M.convars["zcg_sync_faces"].value, "1", "...and the faces are synced by default")
	check(concommand.list["zcg_faces"] ~= nil, "the console command zcg_faces is there")
	local AP = hg.Appearance
	check(istable(AP), "the own appearance system of this addon made the tables of the game itself")
	check(ZCO ~= nil and ZCO.Ours == true, "...and they are its own, not somebody else's")

	-- the tables were made after sh_faces.lua had run: nothing is synced yet
	local made = ZCG.SyncFaces()
	check(type(made) == "number" and made > 0, "the faces of the catalog are put where the other menu looks: "
		.. tostring(made))
	local faces, multi, models, slots = ZCG.FaceCounts()
	check(faces > 0, "faces in FacemapsSlots: " .. faces)
	check(multi > 0, "faces in MultiFacemaps: " .. multi)
	check(models > 0 and slots > 0, "models with a face: " .. models .. ", face materials: " .. slots)

	-- every face of the mod is one the editor of Z-City and its random faces can hand out as well
	local lost = 0
	for _, byFace in pairs(AP.MultiFacemaps or {}) do
		for name, bySlot in pairs(byFace or {}) do
			for slot, path in pairs(bySlot or {}) do
				if isstring(path) and path ~= "" then
					local list = AP.FacemapsSlots and AP.FacemapsSlots[slot]
					if not (istable(list) and list[name] ~= nil) then lost = lost + 1 end
				end
			end
		end
	end
	eq(lost, 0, "no face is in MultiFacemaps alone")
	-- and both menus list the same faces for a model the plain menu can list any for
	local differ, compared = 0, 0
	for sex = 1, 2 do
		for _, entry in pairs(AP.PlayerModels[sex] or {}) do
			if istable(entry) and isstring(entry.mdl) then
				local plain = plainMenu(AP, entry.mdl)
				if plain then
					compared = compared + 1
					if not same(modMenu(AP, entry.mdl), plain) then differ = differ + 1 end
				end
			end
		end
	end
	check(compared > 0, "models of the menu the editor of Z-City lists faces for: " .. compared)
	eq(differ, 0, "for every one of them both menus list the same faces")

	local was = #ZCG.FaceAdded
	local again = ZCG.SyncFaces()
	eq(again, made, "a second pass makes the same entries anew: " .. tostring(again))
	eq(#ZCG.FaceAdded, was, "...and no more than it had")
	eq(ZCG.FaceClash, 0, "nothing stood in the way: " .. tostring(ZCG.FaceClash))

	local lines = {}
	ZCG.FaceReport(function(text) lines[#lines + 1] = text end)
	check(#lines >= 2, "zcg_content tells about the faces: " .. #lines .. " lines")
	check(string.find(lines[1] or "", "FacemapsSlots", 1, true) ~= nil
		and string.find(lines[1] or "", "MultiFacemaps", 1, true) ~= nil,
		"...how many are in each of the two tables: " .. tostring(lines[1]))
	check(string.find(lines[2] or "", "zcg_sync_faces 0", 1, true) ~= nil,
		"...and how to leave the tables alone: " .. tostring(lines[2]))
	M.command("zcg_faces")
	eq(#M.errors, 0, "the console command runs: " .. table.concat(M.errors, " | "))

	-- no tables of the game at all: nothing is made for the sync
	local kept = hg.Appearance
	hg.Appearance = nil
	eq(ZCG.SyncFaces(), false, "with no tables of the game there is nothing to sync")
	eq(hg.Appearance, nil, "...and no table is made for it")
	hg.Appearance = kept

	-- switched off: what this addon put there is taken back, what others made stays
	M.setConVar("zcg_sync_faces", "0")
	eq(ZCG.SyncFaces(), false, "zcg_sync_faces 0: nothing is synced")
	eq(#ZCG.FaceAdded, 0, "and nothing of this addon is left in the tables")
	local facesOff = ZCG.FaceCounts()
	check(facesOff > 0, "the faces of the catalog are still there: " .. facesOff)
	M.setConVar("zcg_sync_faces", "1")
	made = ZCG.SyncFaces()
	check(type(made) == "number" and made > 0, "switched on again: they come back (" .. tostring(made) .. ")")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	-- --------------------- Z-City and the Appearance Mod are installed, a pack adds its faces
	fresh()
	M = dofile(testdir .. "/gmod_mock.lua")("server")
	Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	Z.install()
	AP = hg.Appearance
	-- The model of the menu and the path the Lua of the gamemode declares are not the same file
	-- (models/slav/... in the menu, models/zcityadodser/... in sh_shared.lua): which models wear a
	-- face material is read out of the model itself, so the faces find their model all the same.
	local SLOT = "models/humans/male/group01/ted_facemap"
	local MENU = "models/slav/m/male_02.mdl"
	local SAID = "models/zcityadodser/m/male_02.mdl"
	M.installModel(MENU, { "ted_facemap", "players_sheet" }, { "models/humans/male/group01" })
	AP.PlayerModels[1]["Male 02"] = { mdl = MENU, sex = false,
		submatSlots = { main = "models/humans/male/group01/players_sheet" } }
	AP.FacemapsSlots = {}
	AP.FacemapsModels = {}
	AP.ModelFaceSlots = { [MENU] = { [SLOT] = true } }
	AP.MultiFacemaps = { [MENU] = { ["Face 11 (New)"] = { [SLOT] = "models/humans/modern/male/male_02/facemap_01" } } }
	include("autorun/zcity_csgo_gloves.lua")
	ZCG = ZCGloves
	eq(ZCG.LoadErrors, nil, "the addon loaded next to Z-City and the mod: "
		.. tostring(ZCG.LoadErrors and ZCG.LoadErrors[1] or ""))
	check(ZCO ~= nil and ZCO.Theirs == true, "their tables are their own: the catalog stays out of them")
	-- the sync ran while the addon loaded, with no command and no timer
	eq(AP.FacemapsSlots[SLOT] and AP.FacemapsSlots[SLOT]["Face 11 (New)"],
		"models/humans/modern/male/male_02/facemap_01",
		"the face of the mod is in the table of the gamemode at once: the editor of Z-City lists it")
	eq(AP.FacemapsModels[MENU], SLOT, "...and the model is told the face material it wears")
	eq(AP.ModelFaceSlots[MENU][SLOT], true, "...in the table the mod looks into as well")

	-- a clothing pack adds its faces the way the packs of Z-City are written
	eq(type(AddFacemap), "function", "the API a pack calls by name is there")
	AddFacemap(SLOT, "Default", "", SAID)
	AddFacemap(SLOT, "Face 1", "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap", SAID)
	AddFacemap(SLOT, "Face 2", "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap2")
	AddFacemap(SLOT, "Face 3", "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap3")
	eq(AP.FacemapsSlots[SLOT]["Face 1"], "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap",
		"the pack wrote the table of the gamemode")
	check(plainMenu(AP, MENU)["Face 1"] == true, "so the editor of Z-City lists its faces")
	eq(AP.MultiFacemaps[MENU]["Face 1"], nil, "the menu of the mod lists none of them: it reads MultiFacemaps alone")
	local before = ZCG.FaceMade.multi
	made = ZCG.SyncFaces()
	check(type(made) == "number" and made > 0, "the sync put them there: " .. tostring(made))
	eq(ZCG.FaceMade.multi - before, 6, "three faces of the pack into MultiFacemaps, for the model of the menu and for the path the Lua declared")
	eq(AP.MultiFacemaps[MENU]["Face 1"] and AP.MultiFacemaps[MENU]["Face 1"][SLOT],
		"models/bloo_ltcom_zel/citizens/facemaps/ted_facemap",
		"the first is in the menu of the mod - for the model of the menu, read out of the model file")
	eq(AP.MultiFacemaps[MENU]["Face 2"] and AP.MultiFacemaps[MENU]["Face 2"][SLOT],
		"models/bloo_ltcom_zel/citizens/facemaps/ted_facemap2",
		"...the second, which the pack declared with no model at all")
	eq(AP.MultiFacemaps[MENU]["Face 3"] and AP.MultiFacemaps[MENU]["Face 3"][SLOT],
		"models/bloo_ltcom_zel/citizens/facemaps/ted_facemap3", "...and the third")
	eq(AP.MultiFacemaps[MENU]["Default"], nil, "a face with no material (\"Default\") is not put anywhere")
	eq(AP.MultiFacemaps[MENU]["Face 11 (New)"][SLOT], "models/humans/modern/male/male_02/facemap_01",
		"the face the mod itself made is left as it was")
	eq(AP.MultiFacemaps[SAID] and AP.MultiFacemaps[SAID]["Face 1"][SLOT],
		"models/bloo_ltcom_zel/citizens/facemaps/ted_facemap",
		"a path the Lua declared is a model that wears the slot as well, as the mod itself takes it")
	check(modMenu(AP, MENU)["Face 1"] == true and modMenu(AP, MENU)["Face 11 (New)"] == true,
		"the menu of the mod lists the faces of the pack and its own")
	check(same(modMenu(AP, MENU), plainMenu(AP, MENU)), "...and both menus list the same faces")

	-- an entry that is there with another value is left alone and counted, and stays somebody
	-- else's from then on: nothing this addon made is put over what the game has
	AddFacemap(SLOT, "Face 4", "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap4")
	ZCG.SyncFaces()
	AP.MultiFacemaps[MENU]["Face 4"][SLOT] = "models/somebody/else"
	made = ZCG.SyncFaces()
	eq(AP.MultiFacemaps[MENU]["Face 4"][SLOT], "models/somebody/else", "a face somebody else put there stays")
	check(ZCG.FaceClash > 0, "...and is counted: " .. tostring(ZCG.FaceClash))
	eq(AP.FacemapsSlots[SLOT]["Face 4"], "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap4",
		"the table of the gamemode keeps what the pack wrote")

	-- a model with two face materials: the plain system knows one slot per model, so none is told
	local TWO = "models/slav/m/male_08.mdl"
	local SLOT2 = "models/humans/female/group01/nobody_facemap"
	AP.MultiFacemaps[TWO] = { ["Face 1"] = { [SLOT] = "models/pack/a", [SLOT2] = "models/pack/b" } }
	made = ZCG.SyncFaces()
	eq(AP.FacemapsModels[TWO], nil, "a model with several face materials is not given one of them")
	eq(AP.FacemapsSlots[SLOT2]["Face 1"], "models/pack/b", "but its faces are in the table of the gamemode")
	eq(AP.ModelFaceSlots[TWO][SLOT], true, "and the model is told both of its face materials")
	eq(AP.ModelFaceSlots[TWO][SLOT2], true, "...both")

	-- the keys the menus ask for in lower case (the mod lower-cases a model, the gamemode does not,
	-- and the game hands the materials of a model out in lower case)
	AddFacemap("Models/Humans/Male/Group01/Mixed_Facemap", "Face 1", "models/mixed/face", "Models/Slav/M/male_09.mdl")
	made = ZCG.SyncFaces()
	eq(AP.FacemapsSlots["models/humans/male/group01/mixed_facemap"]["Face 1"], "models/mixed/face",
		"the faces of a slot are found under its key in lower case")
	eq(AP.FacemapsSlots["Models/Humans/Male/Group01/Mixed_Facemap"]["Face 1"], "models/mixed/face",
		"...and the key the Lua wrote stays")
	eq(AP.FacemapsModels["models/slav/m/male_09.mdl"], "models/humans/male/group01/mixed_facemap",
		"a model is found under its path in lower case and told its slot in the same case")
	eq(AP.FacemapsModels["Models/Slav/M/male_09.mdl"], "Models/Humans/Male/Group01/Mixed_Facemap",
		"...while the entry the gamemode wrote stays as it was")
	eq(AP.MultiFacemaps["models/slav/m/male_09.mdl"] and AP.MultiFacemaps["models/slav/m/male_09.mdl"]["Face 1"]
		and AP.MultiFacemaps["models/slav/m/male_09.mdl"]["Face 1"]["models/humans/male/group01/mixed_facemap"],
		"models/mixed/face", "and the menu of the mod, which asks for the model in lower case, has the face")

	-- switched off: what this addon put there is taken back, what others made stays
	M.setConVar("zcg_sync_faces", "0")
	eq(ZCG.SyncFaces(), false, "zcg_sync_faces 0: nothing is synced")
	eq(AP.MultiFacemaps[MENU]["Face 1"], nil, "the faces this addon put into MultiFacemaps are gone")
	eq(AP.MultiFacemaps[MENU]["Face 2"], nil, "...all of them")
	eq(AP.MultiFacemaps[MENU]["Face 11 (New)"][SLOT], "models/humans/modern/male/male_02/facemap_01",
		"the face the mod itself made stays")
	eq(AP.FacemapsSlots[SLOT]["Face 1"], "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap",
		"and the faces the pack wrote stay")
	eq(AP.FacemapsSlots[SLOT]["Face 11 (New)"], nil, "what was put into FacemapsSlots is gone as well")
	eq(AP.FacemapsSlots[SLOT2], nil, "so is a slot table made for a face of the mod alone")
	eq(AP.FacemapsSlots["models/humans/male/group01/mixed_facemap"], nil, "and a key made in lower case")
	eq(AP.FacemapsModels[MENU], nil, "a model this addon told its slot is told nothing again")
	eq(AP.ModelFaceSlots[TWO], nil, "a model nobody declared leaves no table of its own behind")
	eq(AP.MultiFacemaps[MENU]["Face 4"] and AP.MultiFacemaps[MENU]["Face 4"][SLOT], "models/somebody/else",
		"a face somebody else took over stays where it is")
	eq(#ZCG.FaceAdded, 0, "nothing of this addon is left in the tables")
	M.setConVar("zcg_sync_faces", "1")
	made = ZCG.SyncFaces()
	check(made > 0, "switched on again: the faces come back (" .. tostring(made) .. ")")
	eq(AP.MultiFacemaps[MENU]["Face 1"][SLOT], "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap", "...where they were")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	-- ------------- a model compiled without the slot its faces are registered under (2.23.0):
	-- the gamemode applies a face with FacemapsSlots[material of the player][name of the face],
	-- so a slot key the model file does not carry meant no face ever landed on that model,
	-- whatever the menus showed. The faces are mirrored into the material the model has.
	fresh()
	M = dofile(testdir .. "/gmod_mock.lua")("server")
	Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	Z.install()
	AP = hg.Appearance
	local SLOT3 = "models/humans/male/group01/eric_facemap"
	local OWN = "models/slav/m/male_04.mdl"
	local FACE = "models/slav/m/male_04_face"
	local ONE = "models/slav/m/male_05.mdl"
	local ONEMAT = "models/slav/m/male_05"
	M.installModel(OWN, { "male_04_face", "players_sheet" }, { "models/slav/m" })
	M.installModel(ONE, { "male_05" }, { "models/slav/m" })
	AP.FacemapsSlots = { [SLOT3] = { ["Default"] = "", ["Face 10 (New)"] = "models/humans/modern/male/male_04/facemap_01" } }
	AP.FacemapsModels = { [OWN] = SLOT3, [ONE] = SLOT3 }
	AP.MultiFacemaps = {}
	AP.ModelFaceSlots = {}
	AP.PlayerModels[1]["Male 04"] = { mdl = OWN, sex = false, submatSlots = {} }
	AP.PlayerModels[1]["Male 05"] = { mdl = ONE, sex = false, submatSlots = {} }
	include("autorun/zcity_csgo_gloves.lua")
	ZCG = ZCGloves
	eq(ZCG.LoadErrors, nil, "the addon loaded: " .. tostring(ZCG.LoadErrors and ZCG.LoadErrors[1] or ""))
	check((ZCG.FaceMade.alias or 0) > 0, "faces mirrored into the materials the models carry: "
		.. tostring(ZCG.FaceMade.alias))
	eq(AP.FacemapsSlots[FACE] and AP.FacemapsSlots[FACE]["Face 10 (New)"],
		"models/humans/modern/male/male_04/facemap_01",
		"the model whose own material reads as a face (..._face) takes the faces of its slot on it")
	eq(AP.FacemapsSlots[ONEMAT] and AP.FacemapsSlots[ONEMAT]["Face 10 (New)"],
		"models/humans/modern/male/male_04/facemap_01",
		"a model of a single material takes them on that material")
	eq(AP.FacemapsSlots["models/slav/m/players_sheet"], nil, "the sheet of the body is left alone")
	eq(AP.MultiFacemaps[string.lower(OWN)] and AP.MultiFacemaps[string.lower(OWN)]["Face 10 (New)"]
		and AP.MultiFacemaps[string.lower(OWN)]["Face 10 (New)"][FACE],
		"models/humans/modern/male/male_04/facemap_01",
		"the menu of the mod lists them for the model under its own material as well")
	local applied
	for _, path in ipairs({ FACE, "models/slav/m/players_sheet" }) do
		local list = AP.FacemapsSlots[path]
		if istable(list) and list["Face 10 (New)"] then applied = list["Face 10 (New)"] end
	end
	eq(applied, "models/humans/modern/male/male_04/facemap_01",
		"the apply of the gamemode (FacemapsSlots[material of the player][face]) finds the face on the model")
	M.newPlayer("Tester", OWN)
	M.command("zcg_face_debug")
	local said = false
	for _, line in ipairs(M.log) do
		if line:find(FACE .. ": faces registered", 1, true) then said = true end
	end
	check(said, "zcg_face_debug names the material the faces are registered under now")

	-- the old way, straight on the player: what he wears is put back on his own materials
	local faceply = M.newPlayer("Лицо", OWN)
	faceply.CurAppearance = { AFacemap = "Face 10 (New)" }
	check(ZCG.ForceFace(faceply) >= 1, "the face the player wears is put back onto the material his model carries")
	eq(faceply:GetSubMaterial(0), "models/humans/modern/male/male_04/facemap_01",
		"... exactly the material the tables name for it")
	faceply.CurAppearance.AFacemap = "Default"
	check(ZCG.ForceFace(faceply) >= 1, "the face of the model itself takes the sub-material back")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))
	M.setConVar("zcg_sync_faces", "0")
	eq(ZCG.SyncFaces(), false, "zcg_sync_faces 0: nothing is synced")
	eq(AP.FacemapsSlots[FACE], nil, "the mirrored faces are taken back with everything else")
	eq(AP.FacemapsSlots[ONEMAT], nil, "...all of them")
	eq(AP.FacemapsSlots[SLOT3]["Face 10 (New)"], "models/humans/modern/male/male_04/facemap_01",
		"the slot the Lua wrote stays as it was")
	M.setConVar("zcg_sync_faces", "1")

	-- ------------------------------------------- a model nobody wrote a face for: the faces of its sex
	-- The clothing Lua of Z-City gives such a model a slot with a "Default" and an empty material and
	-- nothing else (models/slav/m/cohrt.mdl, leet.mdl, johnwick.mdl): both menus then list no face at
	-- all, which is what "there are simply no facemaps in the choice" is. The own menu of this addon
	-- has taken the faces of the sex for such a model since 2.20.0; now the tables the menus of the
	-- game read hold them as well (2.24.1).
	fresh()
	M = dofile(testdir .. "/gmod_mock.lua")("server")
	Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	Z.install()
	AP = hg.Appearance
	local function countNames(set)
		local got = 0
		for _ in pairs(set or {}) do got = got + 1 end
		return got
	end
	local PLAIN = "models/humans/male/group01/van_facemap"
	local BARE = "models/humans/slav/cohrt/cohrt"
	local BARE_MODEL, PLAIN_MODEL = "models/slav/m/cohrt.mdl", "models/slav/m/male_01.mdl"
	M.installModel(PLAIN_MODEL, { "van_facemap", "players_sheet" }, { "models/humans/male/group01" })
	M.installModel(BARE_MODEL, { "cohrt", "players_sheet" }, { "models/humans/slav/cohrt" })
	AP.PlayerModels[1]["Male 01"] = { mdl = PLAIN_MODEL, sex = false }
	AP.PlayerModels[1]["Male Cohrt"] = { mdl = BARE_MODEL, sex = false }
	AP.FacemapsSlots = {
		[PLAIN] = { Default = "", ["Face 1"] = "models/humans/male/group01/van_facemap1",
			["Face 2"] = "models/humans/male/group02/van_facemap" },
		[BARE] = { Default = "" },
	}
	AP.FacemapsModels = { [PLAIN_MODEL] = PLAIN, [BARE_MODEL] = BARE }
	include("autorun/zcity_csgo_gloves.lua")
	ZCG = ZCGloves
	eq(ZCG.LoadErrors, nil, "the addon loaded: " .. tostring(ZCG.LoadErrors and ZCG.LoadErrors[1] or ""))
	check((ZCG.FaceMade or {}).shared > 0, "the addon says how many faces it gave to a model without its own: "
		.. tostring((ZCG.FaceMade or {}).shared))
	local barePlain = plainMenu(AP, BARE_MODEL)
	local bareCount = countNames(barePlain)
	check(barePlain ~= nil and bareCount >= 2,
		"the editor of Z-City lists faces for a model its Lua gave no face to: " .. tostring(bareCount))
	check(barePlain and barePlain["Face 1"] and barePlain["Face 2"],
		"... the faces of its sex, by the names the clothing Lua gave them")
	eq(AP.FacemapsSlots[BARE] and AP.FacemapsSlots[BARE]["Default"], "",
		"... and its own Default is left as the Lua wrote it")
	local bareMod = modMenu(AP, BARE_MODEL)
	check(bareMod["Face 1"] and bareMod["Face 2"], "the menu of the Appearance Mod lists the same faces")
	check(same(bareMod, barePlain), "... and no others")
	eq(AP.FacemapsModels[BARE_MODEL], BARE, "the model is told the slot it wears")
	eq(AP.MultiFacemaps[BARE_MODEL] and AP.MultiFacemaps[BARE_MODEL]["Face 1"][BARE],
		"models/humans/male/group01/van_facemap1", "... in the shape the mod reads: face, then slot")
	-- a model with faces of its own keeps exactly them: the pool is for the ones with none
	local ownPlain = plainMenu(AP, PLAIN_MODEL)
	eq(countNames(ownPlain), 2,
		"a model with its own faces keeps them and gets none of the pool: " .. tostring(countNames(ownPlain)))
	check(ownPlain and ownPlain["Face 1"] and ownPlain["Face 2"], "... the ones its Lua wrote")
	-- the faces of the pool land on the material the model actually carries, so that they are worn
	local bare = M.newPlayer("Корт", BARE_MODEL, { steamid64 = "76561198000000031" })
	bare.CurAppearance = { AFacemap = "Face 1" }
	check(ZCG.ForceFace(bare) >= 1, "a face of the pool is put on the material the model carries")
	eq(bare:GetSubMaterial(0), "models/humans/male/group01/van_facemap1", "... the very face that was chosen")
	-- a second pass changes nothing, and the switch takes the whole of it back
	local was, again = #ZCG.FaceAdded, ZCG.SyncFaces()
	eq(#ZCG.FaceAdded, was, "a second pass adds nothing to it: " .. tostring(again))
	M.setConVar("zcg_sync_faces", "0")
	ZCG.SyncFaces()
	check(not (AP.MultiFacemaps[BARE_MODEL] and AP.MultiFacemaps[BARE_MODEL]["Face 1"]),
		"zcg_sync_faces 0 takes the faces of the pool back with the rest")
	M.setConVar("zcg_sync_faces", "1")
	ZCG.SyncFaces()
	check(AP.MultiFacemaps[BARE_MODEL] and AP.MultiFacemaps[BARE_MODEL]["Face 1"] ~= nil,
		"... and 1 gives them back")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	-- -------------- the path a menu asks for: a model of the menu told its slot by that very path
	-- The editor of Z-City reads FacemapsSlots[FacemapsModels[tMdl.mdl]] - the path of the model
	-- exactly as the menu wrote it (new_appearance/derma/cl_appearance_editor1.lua) - while the
	-- Appearance Mod declares its models in lower case (sh_shared_appearancemod_addition.lua:
	-- "model = string.lower(model)") and everything this addon reads out of a model file is lower
	-- case as well. A model whose faces are in the tables, but under a key no menu asks for, has an
	-- empty choice all the same - so every model of the menu is told its slot by the path the menu
	-- wrote, and its faces are put where the window of the mod looks for them (2.24.2).
	fresh()
	M = dofile(testdir .. "/gmod_mock.lua")("server")
	Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	Z.install()
	AP = hg.Appearance
	local WORN = "models/humans/male/group01/ted_facemap"
	local WRITTEN = "models/slav/m/Male_04.mdl" -- the path the menu wrote
	local LOWER = "models/slav/m/male_04.mdl" -- the same path as the tables know it
	AP.PlayerModels[1]["Male 04"] = { mdl = WRITTEN, sex = false }
	AP.FacemapsSlots = { [WORN] = { Default = "", ["Face 1"] = "models/faces/ted_1",
		["Face 2"] = "models/faces/ted_2" } }
	AP.FacemapsModels = { [LOWER] = WORN }
	AP.MultiFacemaps = { [LOWER] = { ["Face 1"] = { [WORN] = "models/faces/ted_1" } } }
	AP.ModelFaceSlots = { [LOWER] = { [WORN] = true } }
	include("autorun/zcity_csgo_gloves.lua")
	ZCG = ZCGloves
	eq(ZCG.LoadErrors, nil, "the addon loaded: " .. tostring(ZCG.LoadErrors and ZCG.LoadErrors[1] or ""))
	check((ZCG.FaceMade or {}).exact > 0, "the addon says how many keys it wrote by the path a menu asks for: "
		.. tostring((ZCG.FaceMade or {}).exact))
	eq(AP.FacemapsModels[WRITTEN], WORN, "the model of the menu is told its slot by the path the menu wrote")
	eq(AP.FacemapsModels[LOWER], WORN, "... and the key that was there is left as it was")
	-- the editor of Z-City asks by the exact path alone, with no lower case to fall back on
	local exactSlot = AP.FacemapsModels[WRITTEN]
	local exactList = isstring(exactSlot) and AP.FacemapsSlots[exactSlot] or nil
	check(istable(exactList) and exactList["Face 1"] ~= nil and exactList["Face 2"] ~= nil,
		"so the editor of Z-City lists the faces of the model")
	eq(AP.ModelFaceSlots[WRITTEN] and AP.ModelFaceSlots[WRITTEN][WORN], true,
		"... and the model is told its face material by that path as well")
	check(istable(AP.MultiFacemaps[WRITTEN]) and AP.MultiFacemaps[WRITTEN]["Face 1"] ~= nil,
		"the window of the mod has the face under the path the menu wrote, too")
	check(istable(AP.MultiFacemaps[LOWER]) and AP.MultiFacemaps[LOWER]["Face 2"] ~= nil,
		"... and under the one in lower case it asks for, with every face of the slot")
	check(same(modMenu(AP, WRITTEN), modMenu(AP, LOWER)), "both keys list the same faces")
	local exactWas = #ZCG.FaceAdded
	ZCG.SyncFaces()
	eq(#ZCG.FaceAdded, exactWas, "a second pass adds nothing to it")
	eq(ZCG.FaceClash, 0, "and nothing stands in its way: " .. tostring(ZCG.FaceClash))
	M.setConVar("zcg_sync_faces", "0")
	ZCG.SyncFaces()
	eq(AP.FacemapsModels[WRITTEN], nil, "zcg_sync_faces 0 takes the key this addon wrote back")
	eq(AP.FacemapsModels[LOWER], WORN, "... and leaves what the game wrote where it was")
	M.setConVar("zcg_sync_faces", "1")
	ZCG.SyncFaces()
	eq(AP.FacemapsModels[WRITTEN], WORN, "... and 1 writes it again")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	-- ----------------------------- tables with clothes alone: no face table is made for the sync
	fresh()
	M = dofile(testdir .. "/gmod_mock.lua")("server")
	Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	Z.install()
	AP = hg.Appearance
	AP.FacemapsSlots = nil
	AP.MultiFacemaps = nil
	AP.FacemapsModels = nil
	AP.ModelFaceSlots = nil
	include("autorun/zcity_csgo_gloves.lua")
	ZCG = ZCGloves
	check(ZCO ~= nil and ZCO.Theirs == true, "the tables of Z-City are their own")
	eq(AP.MultiFacemaps, nil, "with no face anywhere no table is made for one")
	eq(AP.ModelFaceSlots, nil, "...none of them")
	eq(#ZCG.FaceAdded, 0, "nothing was added")
	lines = {}
	ZCG.FaceReport(function(text) lines[#lines + 1] = text end)
	eq(#lines, 0, "and zcg_content says nothing about faces")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	-- ------------------------- a face that came without its Lua is in both tables at once
	fresh()
	M = dofile(testdir .. "/gmod_mock.lua")("server")
	Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	local VAN = "models/humans/male/group01/van_facemap"
	local MALE = "models/slav/m/male_01.mdl"
	M.installModel(MALE, { "van_facemap", "players_sheet" }, { "models/humans/male/group01" })
	M.luafiles["zcity_csgo_gloves/sh_found.lua"] = [[ZCGloves.Found = {
		"models/any/folder/Van_Facemap_New",
	}]]
	Z.install()
	AP = hg.Appearance
	AP.PlayerModels[1]["Male 01"] = { mdl = MALE, sex = false,
		submatSlots = { main = "models/humans/male/group01/players_sheet" } }
	AP.FacemapsSlots = { [VAN] = { Default = "", ["Face 1"] = "models/bloo_ltcom_zel/citizens/facemaps/van_facemap" } }
	AP.FacemapsModels = { ["models/zcityadodser/m/male_01.mdl"] = VAN }
	AP.MultiFacemaps = { [MALE] = { ["Face 11 (New)"] = { [VAN] = "models/humans/modern/male/male_01/facemap_01" } } }
	include("autorun/zcity_csgo_gloves.lua")
	ZCG = ZCGloves
	eq(ZCG.LoadErrors, nil, "the addon loaded with the list of content without Lua: "
		.. tostring(ZCG.LoadErrors and ZCG.LoadErrors[1] or ""))
	eq(AP.FacemapsSlots[VAN]["van_facemap_new"], "models/any/folder/van_facemap_new",
		"the material nobody names is in the menu as a face of its model")
	eq(AP.MultiFacemaps[MALE]["van_facemap_new"] and AP.MultiFacemaps[MALE]["van_facemap_new"][VAN],
		"models/any/folder/van_facemap_new",
		"...and in the menu of the Appearance Mod at once, not ten seconds later")
	eq(AP.MultiFacemaps[MALE]["Face 1"] and AP.MultiFacemaps[MALE]["Face 1"][VAN],
		"models/bloo_ltcom_zel/citizens/facemaps/van_facemap", "the face the gamemode wrote is there as well")
	eq(AP.FacemapsSlots[VAN]["Face 11 (New)"], "models/humans/modern/male/male_01/facemap_01",
		"and the face of the mod is one the editor of Z-City lists")
	local total = ZCG.FoundApply()
	eq(total, 1, "a second pass of the content without Lua changes nothing: " .. tostring(total))
	check(ZCG.FoundAdded["models/any/folder/van_facemap_new"] ~= nil,
		"the face is still ours: its mirror in MultiFacemaps is not taken for the Lua of a pack")
	eq(AP.FacemapsSlots[VAN]["van_facemap_new"], "models/any/folder/van_facemap_new", "...and it is still there")
	lines = {}
	ZCG.FoundReport(function(text) lines[#lines + 1] = text end)
	check(#lines == 1 and string.find(lines[1], "1 as faces", 1, true) ~= nil,
		"zcg_content tells about it: " .. tostring(lines[1]))
	M.setConVar("zcg_found_content", "0")
	total = ZCG.FoundApply()
	eq(AP.FacemapsSlots[VAN]["van_facemap_new"], nil, "zcg_found_content 0 takes the face out again")
	eq(AP.MultiFacemaps[MALE]["van_facemap_new"], nil,
		"...and out of the menu of the mod with it: no face outlives what it was made of")
	eq(AP.MultiFacemaps[MALE]["Face 11 (New)"][VAN], "models/humans/modern/male/male_01/facemap_01",
		"the face of the mod stays")
	eq(AP.FacemapsSlots[VAN]["Face 1"], "models/bloo_ltcom_zel/citizens/facemaps/van_facemap",
		"...and so do the faces the Lua wrote")
	M.setConVar("zcg_found_content", "1")
	total = ZCG.FoundApply()
	eq(AP.MultiFacemaps[MALE]["van_facemap_new"][VAN], "models/any/folder/van_facemap_new",
		"switched on again: the face is back in both menus")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	-- ---------------------------------------------------------------- the same on the client
	fresh()
	M = dofile(testdir .. "/gmod_mock.lua")("client")
	Z = dofile(testdir .. "/zcity_mock.lua")(M)
	M.luaroot = luaroot
	Z.install()
	AP = hg.Appearance
	M.installModel(MALE, { "van_facemap", "players_sheet" }, { "models/humans/male/group01" })
	AP.PlayerModels[1]["Male 01"] = { mdl = MALE, sex = false,
		submatSlots = { main = "models/humans/male/group01/players_sheet" } }
	AP.FacemapsSlots = { [VAN] = { ["Face 1"] = "models/bloo_ltcom_zel/citizens/facemaps/van_facemap" } }
	AP.MultiFacemaps = { [MALE] = { ["Face 11 (New)"] = { [VAN] = "models/humans/modern/male/male_01/facemap_01" } } }
	include("autorun/zcity_csgo_gloves.lua")
	ZCG = ZCGloves
	eq(ZCG.LoadErrors, nil, "the client loaded every file: " .. tostring(ZCG.LoadErrors and ZCG.LoadErrors[1] or ""))
	check(concommand.list["zcg_faces_cl"] ~= nil, "the client has its own command, zcg_faces_cl")
	check(concommand.list["zcg_faces"] == nil, "...and not the one of the server")
	eq(AP.MultiFacemaps[MALE]["Face 1"][VAN], "models/bloo_ltcom_zel/citizens/facemaps/van_facemap",
		"the menu the player looks at lists the faces of the packs")
	eq(AP.FacemapsSlots[VAN]["Face 11 (New)"], "models/humans/modern/male/male_01/facemap_01",
		"...and the editor of Z-City lists the faces of the mod")
	M.command("zcg_faces_cl")
	eq(#M.errors, 0, "no errors: " .. table.concat(M.errors, " | "))

	return checks, failures
end
