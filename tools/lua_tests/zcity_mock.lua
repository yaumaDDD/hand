-- The few parts of Z-City this addon touches, rebuilt from the gamemode source
-- (homigrad/new_appearance/sh_shared.lua, derma/cl_appearance_editor.lua, initpost/.../cl_frame.lua)
-- in a much simplified form. Same table layouts, same call order, none of the real content.

return function(M)
	local Z = {}

	Z.MALE = "models/zcity/m/male_01.mdl"
	Z.FEMALE = "models/zcity/f/female_01.mdl"
	Z.COMBINE = "models/player/combine_soldier.mdl"

	-- A ValveBiped skeleton, much reduced: { name, parent, x, y, z } with the place of every bone
	-- relative to its parent. `with` says what the model has: wrist = the twist helpers of the
	-- forearm (citizens have them), fingers, left = a left arm.
	function Z.skeleton(with)
		local bones = {}
		local function add(name, parent, x, y, z)
			bones[#bones + 1] = { "ValveBiped.Bip01_" .. name, parent, x, y, z }
			return #bones - 1
		end
		local pelvis = add("Pelvis", -1, 0, 0, 38)
		local spine = add("Spine4", pelvis, 0, 0, 16)
		add("Head1", spine, 0, 0, 12)
		for _, side in ipairs({ "L", "R" }) do
			local y = side == "L" and 1 or -1
			if side == "R" or with.left ~= false then
				local clavicle = add(side .. "_Clavicle", spine, 0, 2 * y, 2)
				local upperarm = add(side .. "_UpperArm", clavicle, 0, 6 * y, 0)
				local forearm = add(side .. "_Forearm", upperarm, 12, 0, 0)
				if with.wrist then
					add(side .. "_Ulna", forearm, 6, 0, 0)
					add(side .. "_Wrist", forearm, 11.5, 0, 0)
				end
				local hand = add(side .. "_Hand", forearm, 11.5, 0, 0)
				if with.fingers then
					local finger = add(side .. "_Finger1", hand, 3.7, 0, 1.4 * y)
					add(side .. "_Finger11", finger, 1.2, 0, 0)
				end
			end
		end
		return bones
	end

	-- what Entity:GetMaterials() returns for the player models (1-based, slot = index - 1)
	M.models[Z.MALE] = { bones = Z.skeleton({ wrist = true, fingers = true }), materials = {
		"models/humans/male/group01/players_sheet", "models/humans/male/group01/pants",
		"models/humans/male/group01/boots", "models/humans/male/face", "distac/gloves/hands", "models/humans/eyeball",
	} }
	M.models[Z.FEMALE] = { bones = Z.skeleton({ wrist = true, fingers = true }), materials = {
		"models/humans/female/face", "models/humans/female/group01/players_sheet", "distac/gloves/hands",
		"models/humans/female/group01/pants", "models/humans/female/group01/boots",
	} }
	-- a class model: hands, but neither the wrist helpers nor finger bones
	M.models[Z.COMBINE] = { bones = Z.skeleton({}), materials = { "models/combine_soldier/combinesoldiersheet" } }

	function Z.install()
		hg = hg or {}
		hg.Appearance = hg.Appearance or {}
		local AP = hg.Appearance

		AP.PlayerModels = { [1] = {}, [2] = {} }
		AP.PlayerModels[1]["Male 01"] = {
			mdl = Z.MALE, sex = false,
			submatSlots = { main = "models/humans/male/group01/players_sheet", pants = "models/humans/male/group01/pants",
				boots = "models/humans/male/group01/boots", hands = "distac/gloves/hands" },
		}
		AP.PlayerModels[2]["Female 01"] = {
			mdl = Z.FEMALE, sex = true,
			submatSlots = { main = "models/humans/female/group01/players_sheet", pants = "models/humans/female/group01/pants",
				boots = "models/humans/female/group01/boots", hands = "distac/gloves/hands" },
		}

		AP.Clothes = { [1] = { normal = "models/humans/male/group01/normal" }, [2] = { normal = "models/humans/female/group01/normal" } }

		AP.Bodygroups = AP.Bodygroups or {
			HANDS = {
				[1] = { ["None"] = { "hands", false } },
				[2] = { ["None"] = { "hands", false } },
			},
		}
		-- what the hook ZPointshopLoaded adds in the real gamemode
		for sex, suffix in ipairs({ "M", "F" }) do
			AP.Bodygroups.HANDS[sex]["Gloves"] = { "reggloves_FIN_" .. suffix, true, ID = "Standard_BodyGroups_Gloves" }
			AP.Bodygroups.HANDS[sex]["Winter"] = { "wingloves_FIN_" .. suffix, true, ID = "Standard_BodyGroups_Bikers" }
		end

		function AP.GetAccessToAll(ply) return ply.accessToAll == true end
	end

	-- the server applying an appearance (ForceApplyAppearance, reduced to what matters here)
	function Z.applyAppearance(ply, appearance, noModelChange)
		local entry = hg.Appearance.PlayerModels[1][appearance.AModel] or hg.Appearance.PlayerModels[2][appearance.AModel]
		if not noModelChange then ply:SetModel(entry.mdl) end
		ply:SetSubMaterial()
		local mats = ply:GetMaterials()
		for key, name in pairs(entry.submatSlots) do
			local slot = 1
			for i = 1, #mats do
				if mats[i] == name then slot = i - 1 break end
			end
			ply:SetSubMaterial(slot, hg.Appearance.Clothes[entry.sex and 2 or 1]["normal"])
		end
		ply.CurAppearance = {}
		for k, v in pairs(appearance) do ply.CurAppearance[k] = v end
	end

	-- hg.renderOverride: how Z-City draws a player / ragdoll
	function Z.draw(ent, owner)
		-- DrawPlayerRagdoll: the animation, then the arms are written onto the weapon (TPIK)
		ent:SetupBones()
		if ent.tpik then ent.tpik(ent) end

		-- (for the tests: the pose the entity has when the hooks get it)
		ent.posed = {}
		for i, def in ipairs(M.models[ent.model] and M.models[ent.model].bones or {}) do
			ent.posed[def[1]] = M.copyMatrix(ent.bones[i - 1])
		end

		hook.Run("CoolPostDrawAppearance", ent, owner or ent)
		ent:DrawModel()

		-- In the game a glove that was bone-merged and drawn from here on had the pose of the
		-- animation alone, without the arm placement (version 1.0.0; why exactly is not known).
		-- The imitation makes that explicit, so that a test fails if the drawing moves back here.
		M.engineSetup(ent)
		hook.Run("PostDrawAppearance", ent, owner or ent)
	end

	-- the arm placement of Z-City, reduced to "the arms are somewhere else than the animation
	-- put them": every bone from the forearm down is moved and turned
	function Z.tpik(ent)
		for _, side in ipairs({ "L", "R" }) do
			local shift = side == "L" and 5 or -5
			for _, part in ipairs({ "Forearm", "Ulna", "Wrist", "Hand", "Finger1", "Finger11" }) do
				local bone = ent:LookupBone("ValveBiped.Bip01_" .. side .. "_" .. part)
				if bone then
					local at = ent:GetBoneMatrix(bone):GetTranslation()
					ent:SetBoneMatrix(bone, M.matrix(at.x + 7, at.y + shift, at.z - 9, part == "Forearm" and 20 or 50))
				end
			end
		end
	end

	-- ------------------------------------------------------------------ the appearance editor
	function Z.registerEditor()
		local FRAME = {}
		function FRAME:Init()
			-- the real ZFrame calls First() from timer.Simple(0)
			timer.Simple(0, function()
				if self.First then self:First() end
			end)
		end
		vgui.Register("ZFrame", FRAME, "DFrame")

		local PANEL = {}
		function PANEL:First()
			if self.PostInit then self:PostInit() end
		end

		function PANEL:PostInit()
			local main = self
			local lply = LocalPlayer()
			self.modelPosID = "All"
			self.AppearanceTable = self.AppearanceTable or {
				AModel = "Male 01", AClothes = { main = "normal" }, AAttachments = {}, ABodygroups = {},
			}
			local AP = hg.Appearance
			local tMdl = AP.PlayerModels[1][self.AppearanceTable.AModel] or AP.PlayerModels[2][self.AppearanceTable.AModel]

			local viewer = vgui.Create("DModelPanel", self)
			viewer:SetSize(ScrW() / 2.6, ScrH())
			viewer:SetModel(tMdl.mdl)
			self.viewer = viewer -- (test access only, the real editor keeps it in a local)

			function viewer:LayoutEntity(Entity)
				local tbl = main.AppearanceTable
				tMdl = AP.PlayerModels[1][tbl.AModel] or AP.PlayerModels[2][tbl.AModel]
				Entity:SetSubMaterial()
				if Entity:GetModel() ~= tMdl.mdl then
					Entity:SetModel(tMdl.mdl)
					self:SetModel(tMdl.mdl)
				end
				local mats = Entity:GetMaterials()
				for k, v in SortedPairs(tMdl.submatSlots) do
					local slot = 1
					for i = 1, #mats do
						if mats[i] == v then slot = i - 1 break end
					end
					Entity:SetSubMaterial(slot, AP.Clothes[tMdl.sex and 2 or 1]["normal"])
				end
			end

			function viewer:PostDrawModel(Entity)
				main.accessoriesDrawn = (main.accessoriesDrawn or 0) + 1
				if main.onAccessories then main.onAccessories(Entity) end -- (for the tests)
				Entity:SetupBones()
			end

			local other = vgui.Create("DButton", viewer)
			other:SetText("Facemap")

			local glovesSelector = vgui.Create("DButton", viewer)
			glovesSelector:SetSize(ScreenScale(100), ScreenScale(16))
			glovesSelector:SetText("Gloves")
			function glovesSelector:DoClick()
				main.modelPosID = "Hands"
				glovesSelectorMenu = DermaMenu()
				for k, v in SortedPairs(AP.Bodygroups["HANDS"][tMdl.sex and 2 or 1]) do
					if not lply:PS_HasItem(v["ID"]) and v[2] and not AP.GetAccessToAll(lply) then
						-- not owned
					else
						glovesSelectorMenu:AddOption(k, function()
							surface.PlaySound("player/weapon_draw_02.wav")
							main.AppearanceTable.ABodygroups = main.AppearanceTable.ABodygroups or {}
							main.AppearanceTable.ABodygroups["HANDS"] = k
						end)
					end
				end
				glovesSelectorMenu:Open()
				function glovesSelectorMenu:OnRemove()
					main.modelPosID = "All"
				end
			end
		end

		vgui.Register("HG_AppearanceMenu", PANEL, "ZFrame")
	end

	-- what DModelPanel:Paint does with its entity
	function Z.paintViewer(viewer)
		viewer:LayoutEntity(viewer.Entity)
		if IsValid(viewer.Entity) and viewer:PreDrawModel(viewer.Entity) ~= false then
			viewer.Entity:DrawModel()
			viewer:PostDrawModel(viewer.Entity)
		end
	end

	function Z.openEditor(w, h)
		local parent = vgui.Create("Panel")
		parent:SetSize(w or ScrW(), h or ScrH())
		zpan = vgui.Create("HG_AppearanceMenu", parent)
		zpan:SetSize(parent:GetWide(), parent:GetTall())
		zpan:SetPos(0, 0)
		return zpan
	end

	return Z
end
