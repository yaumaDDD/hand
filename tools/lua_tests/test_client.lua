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
	-- The skeleton of the glove models, much reduced (the real ones have 41 bones): the bone
	-- names of a player model, in another order, the wrist helper after the hand.
	local function gloveBones()
		local bones = {}
		local function add(name, parent, x, y, z)
			bones[#bones + 1] = { "ValveBiped.Bip01_" .. name, parent, x, y, z }
			return #bones - 1
		end
		local spine = add("Spine4", -1, 0, 19, -4)
		for _, side in ipairs({ "L", "R" }) do
			local y = side == "L" and 1 or -1
			local clavicle = add(side .. "_Clavicle", spine, 2, 1, 2 * y)
			local upperarm = add(side .. "_UpperArm", clavicle, 5, 0, y)
			local forearm = add(side .. "_Forearm", upperarm, 12.3, 0, 0)
			local hand = add(side .. "_Hand", forearm, 11.5, 0, 0)
			local finger = add(side .. "_Finger1", hand, 3.7, -0.2, 1.4 * y)
			add(side .. "_Finger11", finger, 1.2, 0.1, 0)
			add(side .. "_Wrist", forearm, 11.5, 0, 0)
		end
		return bones
	end
	local function bone(side, part) return "ValveBiped.Bip01_" .. side .. "_" .. part end

	-- (the hard knuckle and broken fang models are "not installed")
	for _, path in ipairs({ MOTO, BLOODHOUND, HYDRA, LEATHER, HANDWRAP }) do
		M.files[path] = true
		M.models[path] = { bones = gloveBones() }
	end
	M.files["materials/zcity_csgo_gloves/icons/moto_5.png"] = true -- the other icons are "missing"
	-- the skin of the fingers inside the fingerless glove models
	local SKIN = "zcity_csgo_gloves/skin/fingers"
	local SKIN_FILE = "materials/" .. SKIN .. ".vmt"
	M.files[SKIN_FILE] = true

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

	-- Is the glove where its wearer was drawn? nil = every bone the two have in common is at the
	-- same place, otherwise the name of a bone that is not.
	local function offBone(glove, wearer)
		if not glove.shown or not wearer.shown then return "nothing was drawn" end
		local common = 0
		for name, m in pairs(glove.shown) do
			if wearer.shown[name] then
				common = common + 1
				if not M.sameMatrix(m, wearer.shown[name]) then return name end
			end
		end
		if common == 0 then return "no bones in common" end
		return nil
	end

	-- the server applied the appearance: clothes on every slot, hands included
	local function dress(ent)
		ent.submats = {}
		for index = 0, #ent:GetMaterials() - 1 do ent.submats[index] = CLOTHES end
	end

	-- ---------------------------------------------------------------- a full-finger glove
	local alice = M.newPlayer("alice", Z.MALE)
	alice:SetPos(Vector(100, 200, 0))
	alice.tpik = Z.tpik -- her arms are not where the animation alone would put them
	dress(alice)
	alice.nw.zcg_glove = "moto_5"

	Z.draw(alice)
	eq(#M.csmodels, 1, "one glove model created")
	local glove = lastModel()
	eq(glove.model, MOTO, "glove model path")
	eq(glove.nodraw, true, "the glove is drawn by hand")
	eq(glove.shadow, false, "no shadow")
	eq(glove.parent, nil, "no parent")
	eq(glove.effects, nil, "not bone merged: the addon places the bones")
	eq(glove:GetBodygroup(0), 4, "body group gloves = variant - 1")
	eq(glove:GetBodygroup(1), 0, "no sleeves")
	eq(glove:GetSubMaterial(0), "null", "the bare arm inside the glove model is hidden")
	eq(glove.draws, 1, "drawn once")
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "the wearer's hands are hidden")
	eq(alice:GetSubMaterial(0), CLOTHES, "the other slots are untouched")
	eq(M.drawn[#M.drawn], alice, "the wearer is drawn after her glove")
	eq(M.drawn[#M.drawn - 1], glove, "the glove is drawn in the hook right before its wearer")

	-- the point of it all: the glove is on the hands that were drawn
	check(not M.sameMatrix(alice.shown[bone("R", "Hand")], alice:GetBoneMatrix(alice:LookupBone(bone("R", "Hand")))),
		"(the imitation: the drawn hand is not where the animation alone puts it)")
	eq(offBone(glove, alice), nil, "every bone of the glove is where the wearer's bone was drawn")
	eq(glove.shownAt, alice.shown["ValveBiped.Bip01_Spine4"]:GetTranslation() - Vector(0, 0, 31),
		"the entity is placed so that the glove takes its light at the wearer's chest")
	eq(glove.setups, 2, "bones set up: once to read the skeleton, once for the draw")

	local writes, boneWrites = alice.submatWrites, glove.boneWrites
	eq(boneWrites, 15, "every bone of the glove was written")
	for _ = 1, 10 do frame() Z.draw(alice) end
	eq(#M.csmodels, 1, "no model is created twice")
	eq(glove.draws, 11, "drawn every frame")
	eq(alice.submatWrites, writes, "the hands are not written again while they stay hidden")
	eq(glove.setups, 12, "the bones are set up once per draw")
	eq(glove.boneWrites, (boneWrites or 0) * 11, "and written again after every set up")
	eq(offBone(glove, alice), nil, "still on the hands")
	eq(hook.list.PostDrawAppearance and hook.list.PostDrawAppearance.zcg_gloves, nil, "nothing is drawn after the wearer any more")

	-- the wearer moves: the glove follows
	alice:SetPos(Vector(-300, 40, 64))
	frame() Z.draw(alice)
	eq(offBone(glove, alice), nil, "the glove follows its wearer")
	eq(glove.shown[bone("L", "Hand")]:GetTranslation(), alice.shown[bone("L", "Hand")]:GetTranslation(), "(left hand, to be explicit)")

	-- an arm that Z-City amputated is scaled to nothing: the glove goes with it
	alice.tpik = function(ent)
		Z.tpik(ent)
		for _, part in ipairs({ "Forearm", "Ulna", "Wrist", "Hand", "Finger1", "Finger11" }) do
			local index = ent:LookupBone(bone("L", part))
			local m = ent:GetBoneMatrix(index)
			m:SetScale(Vector(0.01, 0.01, 0.01))
			ent:SetBoneMatrix(index, m)
		end
	end
	frame() Z.draw(alice)
	eq(offBone(glove, alice), nil, "the glove takes the wearer's bones as they are")
	check(glove.shown[bone("L", "Finger11")]:GetScale().x < 0.02, "the glove of an amputated arm is scaled to nothing with it")
	check(math.abs(glove.shown[bone("R", "Finger11")]:GetScale().x - 1) < 1e-6, "the other one is not")
	alice.tpik = Z.tpik

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

	-- a fingerless glove: other model, and it comes with fingers of its own
	alice.nw.zcg_glove = "bloodhound_2"
	frame() Z.draw(alice)
	eq(#M.csmodels, 2, "a new model for another family")
	eq(glove.removed, true, "the old glove model is removed")
	glove = lastModel()
	eq(glove.model, BLOODHOUND, "bloodhound model")
	eq(glove:GetBodygroup(0), 1, "bloodhound variant")
	eq(glove:GetSubMaterial(0), SKIN, "the fingers inside a fingerless glove get their skin")
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "and the wearer's own hands stay hidden under it")
	local skinWrites = glove.submatWrites
	for _ = 1, 5 do frame() Z.draw(alice) end
	eq(glove.submatWrites, skinWrites, "the skin is set once, not in every frame")

	-- in the hydra model the bare arm is material 1, not 0
	alice.nw.zcg_glove = "hydra_3"
	frame() Z.draw(alice)
	glove = lastModel()
	eq(glove.model, HYDRA, "hydra model")
	eq(glove:GetSubMaterial(1), SKIN, "hydra: the fingers are material 1")
	eq(glove:GetSubMaterial(0), "", "hydra: material 0 is the glove")
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "hydra: hands hidden")

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
	dave:SetPos(Vector(-50, 10, 0))
	dave.tpik = Z.tpik
	dress(dave)
	dave.nw.zcg_glove = "moto_3"
	Z.draw(dave)
	local daveGlove = lastModel()
	eq(ZCG.States[dave].mdl, daveGlove, "glove on a foreign model")
	eq(daveGlove.draws, 1, "drawn on a foreign model")
	eq(dave:GetSubMaterial(0), CLOTHES, "nothing hidden on a foreign model")
	eq(dave.submatWrites, nil, "no sub-material written on a foreign model")

	-- this model has neither the wrist helpers nor finger bones
	eq(offBone(daveGlove, dave), nil, "the bones the model has are taken from it")
	for _, side in ipairs({ "L", "R" }) do
		local forearm, hand = dave.shown[bone(side, "Forearm")], dave.shown[bone(side, "Hand")]
		local wrist = M.copyMatrix(forearm)
		wrist:SetTranslation(hand:GetTranslation())
		check(M.sameMatrix(daveGlove.shown[bone(side, "Wrist")], wrist),
			side .. ": no wrist helper - the rotation of the forearm at the place of the hand")
		local finger = hand * M.matrix(3.7, -0.2, side == "L" and 1.4 or -1.4)
		check(M.sameMatrix(daveGlove.shown[bone(side, "Finger1")], finger),
			side .. ": no finger bones - the fingers keep the pose of the glove model, on the hand")
		check(M.sameMatrix(daveGlove.shown[bone(side, "Finger11")], finger * M.matrix(1.2, 0.1, 0)),
			side .. ": down to the last joint")
	end
	frame() Z.draw(dave)
	eq(offBone(daveGlove, dave), nil, "the same in the next frame")
	check(M.sameMatrix(daveGlove.shown[bone("R", "Finger1")], dave.shown[bone("R", "Hand")] * M.matrix(3.7, -0.2, -1.4)),
		"the pose of the glove model is remembered, not read from bones that were written")

	-- its hands cannot be hidden, so a fingerless glove must not add a second set of fingers
	dave.nw.zcg_glove = "bloodhound_1"
	frame() Z.draw(dave)
	daveGlove = lastModel()
	eq(daveGlove.model, BLOODHOUND, "a fingerless glove on a foreign model")
	eq(daveGlove.draws, 1, "is drawn")
	eq(daveGlove:GetSubMaterial(0), "null", "without its own fingers: the model's hands cannot be hidden")
	eq(dave.submatWrites, nil, "still nothing written on the foreign model")

	-- ---------------------------------------------------------------- convars
	alice:SetModel(Z.MALE)
	dress(alice)
	alice.nw.zcg_glove = "moto_2"
	frame() Z.draw(alice)
	M.setConVar("zcg_hide_hands", 0)
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "zcg_hide_hands 0 gives the hands back")
	check(lastModel().draws >= 1, "the glove is still drawn")
	alice.nw.zcg_glove = "handwrap_2"
	frame() Z.draw(alice)
	eq(lastModel().model, HANDWRAP, "(a fingerless glove)")
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "zcg_hide_hands 0 keeps the hands under a fingerless glove too")
	eq(lastModel():GetSubMaterial(0), "null", "which is then drawn without its own fingers: one pair is enough")
	M.setConVar("zcg_hide_hands", 1)
	local sameModel = lastModel()
	frame() Z.draw(alice)
	eq(lastModel(), sameModel, "(no new model for that)")
	eq(sameModel:GetSubMaterial(0), SKIN, "zcg_hide_hands 1: the fingers of the glove are back")
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "and the wearer's hands are hidden again")

	-- zcg_fingers 0: fingerless gloves as in version 1.0.1
	M.setConVar("zcg_fingers", 0)
	frame() Z.draw(alice)
	eq(sameModel:GetSubMaterial(0), "null", "zcg_fingers 0: the fingers of the glove are not drawn")
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "zcg_fingers 0: the wearer's own fingers are")
	alice.nw.zcg_glove = "moto_2"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "zcg_fingers 0 does not touch full-finger gloves")
	M.setConVar("zcg_fingers", 1)

	ZCG.Config.HideHands = { moto = false, handwrap = false }
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "Config.HideHands can keep the hands of a family")
	alice.nw.zcg_glove = "handwrap_2"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), CLOTHES, "of a fingerless family as well")
	eq(lastModel():GetSubMaterial(0), "null", "its gloves are then drawn without their own fingers")
	alice.nw.zcg_glove = "bloodhound_1"
	frame() Z.draw(alice)
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "the other families are not affected")
	eq(lastModel():GetSubMaterial(0), SKIN, "and keep their fingers")
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
	rag:SetPos(Vector(10, 20, 30))
	Z.draw(rag, alice)
	eq(ZCG.States[rag].mdl, lastModel(), "a fresh ragdoll takes the glove of its owner")
	eq(offBone(lastModel(), rag), nil, "on the hands of the ragdoll")
	eq(rag:GetSubMaterial(HANDS_SLOT), "null", "the ragdoll's hands are hidden too")
	rag.nw.zcg_glove = "none"
	frame() Z.draw(rag, alice)
	eq(rag:GetSubMaterial(HANDS_SLOT), CLOTHES, "the ragdoll's own value wins once it arrived")
	rag.nw.zcg_glove = "handwrap_4"
	rag.nw.ply = NULL
	frame() Z.draw(rag)
	eq(ZCG.States[rag].mdl, lastModel(), "a dead body keeps its glove without an owner")
	eq(lastModel().model, HANDWRAP, "the dead body's own glove")
	eq(lastModel():GetBodygroup(0), 3, "the dead body's own variant")
	eq(lastModel():GetSubMaterial(0), SKIN, "a fingerless glove has its fingers on a ragdoll too")
	eq(rag:GetSubMaterial(HANDS_SLOT), "null", "and the ragdoll's own hands are hidden")

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

	-- ---------------------------------------------------------------- gloves and wearers that are not ready
	local R_HAND = bone("R", "Hand")

	-- a glove model the engine does not hand out bones for yet
	local HARD3 = ZCG.ByID.hardknuckle_3.model
	check(HARD3 ~= ZCG.ByID.hardknuckle_2.model, "(hardknuckle_3 has a model of its own)")
	M.files[HARD3] = true
	M.models[HARD3] = { bones = {} }
	local erin = M.newPlayer("erin", Z.MALE)
	erin.tpik = Z.tpik
	dress(erin)
	erin.nw.zcg_glove = "hardknuckle_3"
	Z.draw(erin)
	local erinGlove = ZCG.States[erin].mdl
	eq(erinGlove.draws, nil, "a glove without bones is not drawn")
	eq(erinGlove.hiddenDraws, 1, "it is drawn invisibly instead, which makes the engine load it")
	eq(erin:GetSubMaterial(HANDS_SLOT), CLOTHES, "the hands stay as long as no glove is drawn over them")
	eq(ZCG.States[erin].why, "the glove model has no bones yet", "the reason is kept for zcg_debug")
	M.models[HARD3].bones = gloveBones()
	frame() Z.draw(erin)
	eq(erinGlove.draws, 1, "drawn as soon as the bones are there")
	eq(offBone(erinGlove, erin), nil, "and on the hands")
	eq(erin:GetSubMaterial(HANDS_SLOT), "null", "now the hands are hidden")
	eq(ZCG.States[erin].why, nil, "no reason left")

	-- a wearer without hand bones
	local CRAB = "models/headcrabclassic.mdl"
	M.models[CRAB] = { materials = { "models/headcrab_classic/headcrabsheet" }, bones = { { "HCclassic.body", -1, 0, 0, 8 } } }
	local frank = M.newPlayer("frank", CRAB)
	frank.nw.zcg_glove = "moto_1"
	Z.draw(frank)
	frame() Z.draw(frank)
	eq(ZCG.States[frank].mdl.draws, nil, "no hand bones: no glove")
	eq(ZCG.States[frank].mdl.hiddenDraws, nil, "(and no invisible draw: the glove model is not the problem)")
	eq(ZCG.States[frank].why, "the wearer's model has no hand bones", "the reason is kept")
	eq(frank.submatWrites, nil, "nothing is hidden on it")

	-- a wearer with one arm only
	local ONEARM = "models/onearm.mdl"
	M.models[ONEARM] = { materials = M.models[Z.MALE].materials, bones = Z.skeleton({ wrist = true, fingers = true, left = false }) }
	local gina = M.newPlayer("gina", ONEARM)
	gina.tpik = Z.tpik
	dress(gina)
	gina.nw.zcg_glove = "moto_1"
	Z.draw(gina)
	local ginaGlove = ZCG.States[gina].mdl
	eq(ginaGlove.draws, 1, "one hand is enough")
	eq(offBone(ginaGlove, gina), nil, "the glove of that hand is on it")
	for _, part in ipairs({ "Clavicle", "UpperArm", "Forearm", "Hand", "Finger1", "Finger11", "Wrist" }) do
		local m = ginaGlove.shown[bone("L", part)]
		check(m:GetScale().x < 0.02 and m:GetTranslation() == gina.shown[R_HAND]:GetTranslation(),
			"the glove of the missing hand is shrunk to nothing (" .. part .. ")")
	end

	-- a wearer whose bones were never set up (somebody calls ZCG.DrawGlove on a model of their own)
	local doll = ClientsideModel(Z.MALE)
	eq(ZCG.DrawGlove(doll, ZCG.ByID.moto_1), false, "no bone matrices: nothing is drawn")
	eq(ZCG.States[doll].why, "the wearer's bones are not set up", "the reason is kept")
	doll:SetupBones()
	eq(ZCG.DrawGlove(doll, ZCG.ByID.moto_1), true, "drawn once the wearer has bones")
	eq(offBone(ZCG.States[doll].mdl, { shown = (function()
		local shown = {}
		for i = 0, doll:GetBoneCount() - 1 do shown[doll:GetBoneName(i)] = doll:GetBoneMatrix(i) end
		return shown
	end)() }), nil, "on its hands")
	ZCG.ClearGlove(doll)
	doll:Remove()

	-- ---------------------------------------------------------------- zcg_bonemerge 1: the engine places the bones
	local byHand = ZCG.States[alice].mdl
	M.setConVar("zcg_bonemerge", 1)
	frame() Z.draw(alice)
	local merged = ZCG.States[alice].mdl
	check(merged ~= byHand and byHand.removed == true, "the glove model is made anew for the other method")
	eq(merged:GetParent(), alice, "parented to the wearer")
	eq(merged.effects, EF_BONEMERGE, "bone merged")
	eq(merged.boneWrites, nil, "the addon writes no bones")
	eq(merged.setups, 1, "but has them merged at the moment of drawing")
	eq(M.drawn[#M.drawn], alice, "the wearer is still drawn after her glove")
	eq(M.drawn[#M.drawn - 1], merged, "the merged glove is drawn in the same hook")
	eq(offBone(merged, alice), nil, "(the imitation of the engine merges the pose of that moment)")
	eq(alice:GetSubMaterial(HANDS_SLOT), "null", "hands hidden as before")
	local parentSets = merged.parentSets
	for _ = 1, 3 do frame() Z.draw(alice) end
	eq(merged.parentSets, parentSets, "the parent is set once")
	eq(merged.setups, 4, "merged again for every draw")

	me.lookat = alice
	M.log = {}
	M.command("zcg_debug", me)
	check(table.concat(M.log, "\n"):find("bone-merged by the engine", 1, true) ~= nil, "zcg_debug names the method in use")
	M.log = {}
	frame() Z.draw(alice)
	check(table.concat(M.log, "\n"):find("(zcg_bonemerge 1)", 1, true) ~= nil, "the bone report works for a merged glove too")
	me.lookat = nil

	M.setConVar("zcg_bonemerge", 0)
	frame() Z.draw(alice)
	check(merged.removed == true and ZCG.States[alice].mdl.parent == nil, "and back to the default")
	eq(offBone(ZCG.States[alice].mdl, alice), nil, "on the hands again")

	-- ---------------------------------------------------------------- zcg_preview / zcg_debug
	dress(me)
	M.command("zcg_preview", me, "moto_9")
	Z.draw(me)
	eq(ZCG.States[me].mdl, lastModel(), "zcg_preview shows a glove on the local player")
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
	local report = table.concat(M.log, "\n")
	check(report:find("zcg_bonemerge 0", 1, true) ~= nil, "the report names the method")
	check(report:find("zcg_fingers 1", 1, true) ~= nil, "and the finger setting")
	check(report:find("finger material      : " .. SKIN, 1, true) ~= nil and report:find("NOT installed", 1, true) == nil,
		"the report names the skin of the fingers")
	check(report:find("full-finger, hides the hands of this model: true, drawn with its own fingers: false", 1, true) ~= nil,
		"the report says what the glove does to the hands")
	check(report:find('bare arm material "null"', 1, true) ~= nil, "and what is on the rest of the bare arm")
	check(report:find("15 of 15 bones taken from the wearer", 1, true) ~= nil, "the report says how many bones were copied")
	check(report:find("R_Wrist 15", 1, true) ~= nil, "the report lists the bones of the wearer that matter")
	M.log = {}
	frame() Z.draw(alice)
	report = table.concat(M.log, "\n")
	check(report:find("ValveBiped.Bip01_L_Hand: wearer", 1, true) ~= nil and report:find("ValveBiped.Bip01_R_Hand: wearer", 1, true) ~= nil,
		"with the next draw the hand bones are printed")
	local _, zero = report:gsub("0%.00 apart", "")
	eq(zero, 2, "both gloves are reported to be on the hands")
	check(report:find("the glove was drawn with exactly these bones", 1, true) ~= nil, "and to be drawn there")
	check(report:find("MOVED", 1, true) == nil, "(nothing is reported as moved)")

	-- an engine that works the bones out again while drawing would be noticed
	local aliceGlove = ZCG.States[alice].mdl
	local realDraw = aliceGlove.DrawModel
	aliceGlove.DrawModel = function(self) M.engineSetup(self) return realDraw(self) end
	M.command("zcg_debug", me)
	M.log = {}
	frame() Z.draw(alice)
	aliceGlove.DrawModel = nil
	report = table.concat(M.log, "\n")
	local _, moved = report:gsub("the engine MOVED this glove bone while drawing", "")
	eq(moved, 2, "zcg_debug notices bones that the engine replaced while drawing")
	M.log = {}
	frame() Z.draw(alice)
	eq(#M.log, 0, "the bone report is printed once")
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

	-- ---------------------------------------------------------------- fingerless gloves that cannot show their fingers
	do
		local function reload()
			ZCGloves = nil
			include("autorun/zcity_csgo_gloves.lua")
			ZCG = ZCGloves
		end
		local function wearer(name, id)
			local ply = M.newPlayer(name, Z.MALE)
			ply.tpik = Z.tpik
			dress(ply)
			ply.nw.zcg_glove = id
			return ply
		end
		local function logged(text)
			local n = 0
			for _, line in ipairs(M.log) do
				if line:find(text, 1, true) then n = n + 1 end
			end
			return n
		end

		-- the content of version 1.0.x under this Lua: there is no skin for the fingers
		M.files[SKIN_FILE] = nil
		reload()
		local hank = wearer("hank", "handwrap_3")
		Z.draw(hank)
		local g = ZCG.States[hank].mdl
		eq(ZCG.FingerMaterial(), nil, "(the finger skin is not installed)")
		eq(g.draws, 1, "without the finger skin the glove is drawn all the same")
		eq(g:GetSubMaterial(0), "null", "without its fingers")
		eq(hank:GetSubMaterial(HANDS_SLOT), CLOTHES, "over the wearer's own hands, as in version 1.0.1")
		hank.nw.zcg_glove = "moto_1"
		frame() Z.draw(hank)
		eq(hank:GetSubMaterial(HANDS_SLOT), "null", "full-finger gloves do not need the skin")
		M.log = {}
		M.command("zcg_finger_tint", me, "0.8")
		eq(logged("is not installed on this client"), 1, "zcg_finger_tint says that the skin is missing")
		me.lookat = hank
		M.log = {}
		M.command("zcg_debug", me)
		eq(logged("NOT installed on this client"), 1, "and so does zcg_debug")
		me.lookat = nil

		-- the content arrives while the game runs
		hank.nw.zcg_glove = "handwrap_3"
		frame() Z.draw(hank)
		g = ZCG.States[hank].mdl
		M.files[SKIN_FILE] = true
		frame() Z.draw(hank)
		eq(g:GetSubMaterial(0), "null", "the skin is not looked for in every frame")
		for _ = 1, 600 do frame() Z.draw(hank) end -- 12 seconds
		eq(ZCG.States[hank].mdl, g, "(still the same glove model)")
		eq(g:GetSubMaterial(0), SKIN, "but it is found once it is installed")
		eq(hank:GetSubMaterial(HANDS_SLOT), "null", "and then the wearer's hands go")

		-- the models of version 1.0.x with the rest of this version: the whole bare arm is in them
		local vtx = HANDWRAP:sub(1, -5) .. ".dx90.vtx"
		local cut = ZCG.Models[HANDWRAP].cut
		check(isnumber(cut) and cut > 0, "(the catalogue knows where the build removed the arm)")
		M.filedata[vtx] = { [cut] = "\7\0\8\0\9\0" } -- a triangle with three corners: it is still drawn
		reload()
		M.log = {}
		M.opened = 0
		local ivy = wearer("ivy", "handwrap_1")
		Z.draw(ivy)
		for _ = 1, 3 do frame() Z.draw(ivy) end
		g = ZCG.States[ivy].mdl
		eq(g.draws, 4, "a glove model of an older version is drawn")
		eq(g:GetSubMaterial(0), "null", "but gets no skin: the arm that is still in it must not show")
		eq(ivy:GetSubMaterial(HANDS_SLOT), CLOTHES, "the wearer keeps the hands instead")
		eq(logged("from an older version"), 1, "the player is told once")
		eq(M.opened, 1, "the model file is looked at once")
		eq(M.openNow, 0, "and closed again")
		eq(ZCG.ArmRemoved(HANDWRAP), false, "ZCG.ArmRemoved tells")
		me.lookat = ivy
		M.log = {}
		M.command("zcg_debug", me)
		eq(logged("OLDER version"), 1, "zcg_debug names the old model")
		eq(logged("fingerless, hides the hands of this model: false, drawn with its own fingers: false"), 1,
			"and what follows from it")
		me.lookat = nil
		frame() Z.draw(ivy) -- (the bone report zcg_debug asked for)
		ivy.nw.zcg_glove = "bloodhound_1"
		frame() Z.draw(ivy)
		eq(ZCG.States[ivy].mdl:GetSubMaterial(0), SKIN, "every model is judged on its own (a file that cannot be read is trusted)")
		eq(ivy:GetSubMaterial(HANDS_SLOT), "null", "so that glove has its fingers")
		ivy.nw.zcg_glove = "moto_1"
		frame() Z.draw(ivy)
		eq(ivy:GetSubMaterial(HANDS_SLOT), "null", "(full-finger gloves hide the hands whatever the files are)")

		-- two equal corners are a triangle, too
		M.filedata[vtx] = { [cut] = "\7\0\7\0\7\1" }
		reload()
		eq(ZCG.ArmRemoved(HANDWRAP), false, "three equal corners are asked for, not two")

		-- the file as the build makes it
		M.filedata[vtx] = { [cut] = "\7\2\7\2\7\2" }
		reload()
		M.log = {}
		local june = wearer("june", "handwrap_1")
		Z.draw(june)
		eq(ZCG.States[june].mdl:GetSubMaterial(0), SKIN, "a model without the arm gets the skin")
		eq(june:GetSubMaterial(HANDS_SLOT), "null", "and replaces the hands")
		eq(logged("from an older version"), 0, "nothing to complain about")
		M.filedata[vtx] = nil

		-- a model that is not installed has no answer yet
		local FANG = ZCG.ByID.brokenfang_1.model
		M.filedata[FANG:sub(1, -5) .. ".dx90.vtx"] = { [ZCG.Models[FANG].cut] = "\1\0\1\0\1\0" }
		eq(ZCG.ArmRemoved(FANG), false, "a model that is not installed cannot have fingers")
		M.files[FANG] = true
		eq(ZCG.ArmRemoved(FANG), false, "(the files are not looked for in every frame)")
		M.advance(11)
		eq(ZCG.ArmRemoved(FANG), true, "it is asked again once the model is there")
		M.files[FANG] = nil
		M.filedata[FANG:sub(1, -5) .. ".dx90.vtx"] = nil

		-- Config.FingerTint and zcg_finger_tint
		reload()
		M.materialObjects[SKIN] = nil
		local kim = wearer("kim", "hydra_1")
		Z.draw(kim)
		check(M.materialObjects[SKIN] == nil or M.materialObjects[SKIN].vectors["$color2"] == nil,
			"the skin keeps its colour unless the config asks for another one")

		reload()
		ZCG.Config.FingerTint = Vector(0.8, 0.7, 0.6)
		frame() Z.draw(kim)
		local skin = M.materialObjects[SKIN]
		eq(skin and skin.vectors["$color2"], Vector(0.8, 0.7, 0.6), "Config.FingerTint is put on the skin")
		M.log = {}
		M.command("zcg_finger_tint", me, "1.1", "1", "0.9")
		eq(skin.vectors["$color2"], Vector(1.1, 1, 0.9), "zcg_finger_tint changes it")
		eq(logged("FingerTint = Vector(1.10, 1.00, 0.90)"), 1, "and prints the line for the config")
		M.command("zcg_finger_tint", me, "0.5")
		eq(skin.vectors["$color2"], Vector(0.5, 0.5, 0.5), "one number is taken for all three")
		M.command("zcg_finger_tint", me, "7", "-1", "1")
		eq(skin.vectors["$color2"], Vector(4, 0, 1), "numbers out of range are clamped")
		M.log = {}
		M.command("zcg_finger_tint", me)
		M.command("zcg_finger_tint", me, "a", "b", "c")
		M.command("zcg_finger_tint", me, "1", "2")
		eq(logged("usage: zcg_finger_tint"), 3, "anything else prints how to use it")
		eq(skin.vectors["$color2"], Vector(4, 0, 1), "and changes nothing")
		me.lookat = kim
		M.log = {}
		M.command("zcg_debug", me)
		eq(logged("tint 4.00 0.00 1.00"), 1, "zcg_debug shows the tint")
		eq(logged("fingerless, hides the hands of this model: true, drawn with its own fingers: true"), 1,
			"and that the glove is drawn with its fingers")
		eq(logged('bare arm material "' .. SKIN .. '"'), 1, "and their material")
		me.lookat = nil
		frame() Z.draw(kim)
		skin.vectors["$color2"] = nil

		-- the fingers can be switched off in the config, or get another material
		reload()
		ZCG.Config.FingerMaterial = false
		local mona = wearer("mona", "hydra_1")
		Z.draw(mona)
		eq(ZCG.States[mona].mdl:GetSubMaterial(1), "null", "Config.FingerMaterial = false: no fingers in the gloves")
		eq(mona:GetSubMaterial(HANDS_SLOT), CLOTHES, "the wearer's own instead")

		reload()
		ZCG.Config.FingerMaterial = "!my_skin"
		local nora = wearer("nora", "hydra_1")
		Z.draw(nora)
		eq(ZCG.States[nora].mdl:GetSubMaterial(1), "!my_skin", "a material made by Lua needs no file")
		eq(nora:GetSubMaterial(HANDS_SLOT), "null", "and replaces the hands like the shipped one")

		eq(#M.errors, 0, "no errors with the fingers: " .. table.concat(M.errors, " | "))
		reload()
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
	eq(ZCG.States[preview].mdl, glove, "the editor model wears the selected glove")
	eq(glove:GetBodygroup(0), 4, "the right variant in the editor")
	eq(glove.draws, 1, "drawn in the editor")
	eq(offBone(glove, preview), nil, "on the hands of the editor model")
	eq(main.accessoriesDrawn, 1, "the original PostDrawModel still runs")
	eq(M.drawn[#M.drawn], glove, "glove drawn after the editor model")
	eq(preview:GetSubMaterial(HANDS_SLOT), CLOTHES, "the hands stay until the glove has been drawn")
	frame() Z.paintViewer(viewer)
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "hands hidden in the editor")
	count = #M.csmodels
	for _ = 1, 5 do frame() Z.paintViewer(viewer) end
	eq(#M.csmodels, count, "no new models while the editor repaints")
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "hidden in every frame although the editor resets the materials")

	-- a fingerless one: its own fingers instead of the hands of the editor model
	main.AppearanceTable.ABodygroups.HANDS = "CS:GO Bloodhound 03"
	frame() Z.paintViewer(viewer)
	eq(lastModel().model, BLOODHOUND, "fingerless glove drawn in the editor")
	eq(lastModel():GetSubMaterial(0), SKIN, "with its fingers")
	frame() Z.paintViewer(viewer)
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "fingerless: the hands of the editor model are hidden as well")
	M.setConVar("zcg_fingers", 0)
	frame() Z.paintViewer(viewer)
	eq(preview:GetSubMaterial(HANDS_SLOT), CLOTHES, "zcg_fingers 0 in the editor: the hands stay")
	eq(lastModel():GetSubMaterial(0), "null", "zcg_fingers 0 in the editor: no fingers in the glove")
	M.setConVar("zcg_fingers", 1)
	frame() Z.paintViewer(viewer)
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "and back")
	eq(lastModel():GetSubMaterial(0), SKIN, "with the fingers")

	-- glove models of an older version (the whole bare arm is in them): no skin, and the hands stay
	M.filedata[HYDRA:sub(1, -5) .. ".dx90.vtx"] = { [ZCG.Models[HYDRA].cut] = "\1\0\2\0\3\0" }
	main.AppearanceTable.ABodygroups.HANDS = "CS:GO Hydra 01"
	frame() Z.paintViewer(viewer)
	frame() Z.paintViewer(viewer)
	eq(lastModel().model, HYDRA, "an old glove model is drawn in the editor")
	eq(lastModel():GetSubMaterial(1), "null", "without skin on its arm")
	eq(preview:GetSubMaterial(HANDS_SLOT), CLOTHES, "and the hands of the editor model stay")
	M.filedata[HYDRA:sub(1, -5) .. ".dx90.vtx"] = nil

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
	eq(ZCG.States[preview].mdl, lastModel(), "glove moved to the new editor entity")
	eq(offBone(lastModel(), preview), nil, "and sits on its hands")
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
	eq(#tiles, 68, "one tile per glove")
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
	frame() Z.paintViewer(viewer)
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "hands hidden for the hovered glove")
	eq(main.AppearanceTable.ABodygroups.HANDS, "Gloves", "hovering does not select")
	M.texts = {}
	M.paint(picker)
	check(table.concat(M.texts, "|"):find("Moto 05 - Finish Line", 1, true) ~= nil, "the hovered glove is named in the header")

	M.hovered = tileOf("bloodhound_1")
	M.paint(picker)
	frame() Z.paintViewer(viewer)
	eq(lastModel().model, BLOODHOUND, "preview follows the cursor")
	eq(lastModel():GetSubMaterial(0), SKIN, "a fingerless preview has its fingers")
	eq(preview:GetSubMaterial(HANDS_SLOT), "null", "and hides the hands of the editor model")

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
	eq(shown, 68 - 13 - 1, "CanSelect hook removes tiles")
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
		eq(ZCG.States[win.viewer.Entity].mdl, lastModel(), "preview on the rebuilt model panel")
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
		eq(ZCG.States[win.viewer.Entity].mdl, lastModel(), "and the preview works there")
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
		eq(ZCG.States[win.viewer.Entity].mdl, lastModel(), "preview works without the button")
		eq(lastModel().draws, 1, "drawn although this editor never sets the bones up itself")

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

	-- ---------------------------------------------------------------- a glove that brings its own materials
	-- The Specialist model names only ten pairs of materials for its eleven gloves: the fifth
	-- one gets its materials from sh_data.lua ("mats").
	do
		local SPECIALIST = "models/zcity_csgo_gloves/v_glove_ct_specialist.mdl"
		local RIGHT5 = "models/weapons/v_models/arms/glove_specialist/glove_specialist_right_5"
		local LEFT5 = "models/weapons/v_models/arms/glove_specialist/glove_specialist_left_5"
		-- the materials of the model as the game lists them: no "_5" between "_4" and "_6"
		local DIR = "models/weapons/v_models/arms/glove_specialist/"
		local materials = { "models/weapons/v_models/arms/bare/bare_arm_133" }
		for _, suffix in ipairs({ "", "_2", "_3", "_4", "_6", "_7", "_8", "_9", "_10", "_11" }) do
			materials[#materials + 1] = DIR .. "glove_specialist_right" .. suffix
			materials[#materials + 1] = DIR .. "glove_specialist_left" .. suffix
		end
		M.files[SPECIALIST] = true
		M.models[SPECIALIST] = { bones = gloveBones(), materials = materials }
		eq(materials[9 + 1], DIR .. "glove_specialist_right_6", "(the imitation: material 9 of the model)")
		eq(materials[10 + 1], DIR .. "glove_specialist_left_6", "(the imitation: material 10 of the model)")

		local five = ZCG.ByID["specialist_5"]
		check(five ~= nil and istable(five.mats), "specialist_5 brings materials")
		eq(five.mats[9], RIGHT5, "its right hand material")
		eq(five.mats[10], LEFT5, "its left hand material")
		eq(table.Count(five.mats), 2, "and nothing else")
		local swapping = 0
		for _, v in ipairs(ZCG.Variants) do
			if v.mats then swapping = swapping + 1 end
		end
		eq(swapping, 1, "no other glove swaps materials")
		eq(ZCG.ByID["specialist_5"].body, 4, "the fifth glove is body value 4")
		eq(ZCG.ByID["specialist_6"].body, 5, "the sixth one is body value 5")

		local eve = M.newPlayer("eve", Z.MALE)
		dress(eve)
		eve.nw.zcg_glove = "specialist_5"
		frame() Z.draw(eve)
		local glove = ZCG.States[eve].mdl
		eq(glove.model, SPECIALIST, "specialist model")
		eq(glove:GetBodygroup(0), 4, "body group of the fifth glove")
		eq(glove:GetSubMaterial(9), RIGHT5, "right hand: the material the model does not name")
		eq(glove:GetSubMaterial(10), LEFT5, "left hand: the material the model does not name")
		eq(glove:GetSubMaterial(0), "null", "the bare arm inside the model is hidden as always")
		eq(glove:GetSubMaterial(1), "", "the other materials are left alone")
		eq(eve:GetSubMaterial(HANDS_SLOT), "null", "the wearer's hands are hidden")
		local draws = glove.draws
		frame() Z.draw(eve)
		eq(glove.draws, draws + 1, "drawn every frame")
		eq(glove:GetSubMaterial(9), RIGHT5, "the material stays")

		-- the next glove of the same model keeps the model: the swapped materials must go
		eve.nw.zcg_glove = "specialist_6"
		frame() Z.draw(eve)
		eq(ZCG.States[eve].mdl, glove, "the model is kept for another glove of the family")
		eq(glove:GetBodygroup(0), 5, "body group of the sixth glove")
		eq(glove:GetSubMaterial(9), "", "right hand: the material of the model again")
		eq(glove:GetSubMaterial(10), "", "left hand: the material of the model again")
		eq(glove:GetSubMaterial(0), "null", "the bare arm stays hidden")

		-- and back
		eve.nw.zcg_glove = "specialist_5"
		frame() Z.draw(eve)
		eq(ZCG.States[eve].mdl, glove, "still the same model")
		eq(glove:GetBodygroup(0), 4, "the fifth glove again")
		eq(glove:GetSubMaterial(9), RIGHT5, "right hand swapped again")
		eq(glove:GetSubMaterial(10), LEFT5, "left hand swapped again")

		-- a glove of another model in between: every model starts without swapped materials
		eve.nw.zcg_glove = "moto_1"
		frame() Z.draw(eve)
		local moto = ZCG.States[eve].mdl
		check(moto ~= glove and glove.removed == true, "the specialist model is removed for another model")
		eq(moto:GetSubMaterial(9), "", "nothing is swapped on the other model (9)")
		eq(moto:GetSubMaterial(10), "", "nothing is swapped on the other model (10)")
		eve.nw.zcg_glove = "specialist_5"
		frame() Z.draw(eve)
		local again = ZCG.States[eve].mdl
		check(again ~= glove and again ~= moto, "a new specialist model")
		eq(again:GetSubMaterial(9), RIGHT5, "the new model gets the material (right)")
		eq(again:GetSubMaterial(10), LEFT5, "the new model gets the material (left)")

		-- the same glove on a model made anew: after the engine dropped the model ...
		again:Remove()
		frame() Z.draw(eve)
		local third = ZCG.States[eve].mdl
		check(third ~= again and not third.removed, "a model the engine removed is made again")
		eq(third:GetBodygroup(0), 4, "the new model shows the fifth glove")
		eq(third:GetSubMaterial(9), RIGHT5, "and has its material (right)")
		eq(third:GetSubMaterial(10), LEFT5, "and has its material (left)")
		-- ... and after the way of drawing changed
		M.setConVar("zcg_bonemerge", 1)
		frame() Z.draw(eve)
		local merged = ZCG.States[eve].mdl
		check(merged ~= third and third.removed == true, "another model for the bone-merged glove")
		eq(merged:GetSubMaterial(9), RIGHT5, "the bone-merged model has the material (right)")
		eq(merged:GetSubMaterial(10), LEFT5, "the bone-merged model has the material (left)")
		M.setConVar("zcg_bonemerge", 0)
		frame() Z.draw(eve)
		again = ZCG.States[eve].mdl
		eq(again:GetSubMaterial(9), RIGHT5, "and so has the one made after switching back")

		-- zcg_preview shows the glove on the local player with the same code
		M.command("zcg_preview", me, "specialist_5")
		frame() Z.draw(me)
		local mine = ZCG.States[me] and ZCG.States[me].mdl
		check(mine ~= nil and mine.model == SPECIALIST, "zcg_preview shows the specialist glove")
		if mine then
			eq(mine:GetSubMaterial(9), RIGHT5, "preview: material (right)")
			eq(mine:GetSubMaterial(10), LEFT5, "preview: material (left)")
		end
		-- zcg_debug tells what the model names, what the glove wants and what is set
		M.log = {}
		M.command("zcg_debug", me)
		local report = table.concat(M.log, "\n")
		check(report:find("glove material [ 9]  : " .. DIR .. "glove_specialist_right_6 -> wanted \"" .. RIGHT5
			.. "\", set \"" .. RIGHT5 .. "\"", 1, true) ~= nil, "zcg_debug reports the swapped material (right)")
		check(report:find("glove material [10]  : " .. DIR .. "glove_specialist_left_6 -> wanted \"" .. LEFT5
			.. "\", set \"" .. LEFT5 .. "\"", 1, true) ~= nil, "zcg_debug reports the swapped material (left)")
		M.command("zcg_preview", me, "specialist_6")
		frame() Z.draw(me)
		M.log = {}
		M.command("zcg_debug", me)
		check(table.concat(M.log, "\n"):find("glove material [", 1, true) == nil, "no such lines for a glove that swaps nothing")
		frame() Z.draw(me) -- (prints the bone report zcg_debug asked for)
		M.command("zcg_preview", me, "off")
		frame() Z.draw(me)

		-- taken off: the model goes, nothing is left behind
		eve.nw.zcg_glove = "none"
		frame() Z.draw(eve)
		eq(eve:GetSubMaterial(HANDS_SLOT), CLOTHES, "hands back when the glove is taken off")
		M.advance(17)
		check(again.removed == true, "the unused model is removed")
		check(ZCG.States[eve] == nil, "state forgotten")
	end

	eq(#M.errors, 0, "no errors at the end: " .. table.concat(M.errors, " | "))
	return checks, failures
end
