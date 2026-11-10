-- Z-City CS:GO gloves - server side.
--
-- Z-City keeps the applied appearance only on the server (ply.CurAppearance), so the server
-- tells every client which glove a player wears through a networked string:
--     ent:GetNWString("zcg_glove")  ->  "moto_5", "none" or "" (not decided yet)
-- The same string is put on the ragdolls Z-City creates for unconscious / dead players.
--
-- The appearance is applied from several places inside Z-City through local functions that
-- cannot be hooked, so the players are simply polled a few times per second - comparing one
-- table field per player costs nothing.

local ZCG = ZCGloves
local Config = ZCG.Config

local NW = "zcg_glove"
local NONE = "none"

-- ---------------------------------------------------------------------------------------------
-- which glove should this player (or any entity that carries an appearance) show?
-- ---------------------------------------------------------------------------------------------
function ZCG.WantedGlove(ent)
	local appearance = ent.CurAppearance
	if not istable(appearance) then return nil end

	local groups = appearance.ABodygroups
	local name = istable(groups) and groups.HANDS
	local variant = name ~= nil and ZCG.ByName[name] or nil
	if not variant then return nil end

	if not ZCG.cvAnyModel:GetBool() then
		-- player classes (police, combine ...) and the model selector replace the model but keep
		-- the appearance table: the gloves were picked for the appearance model only
		local entry = ZCG.AppearanceModel(appearance.AModel)
		local wanted = entry and entry.mdl or appearance.AModel
		local current = ent:GetModel()
		if not isstring(wanted) or not isstring(current) or string.lower(wanted) ~= string.lower(current) then
			return nil
		end
	end

	-- return false from this hook to forbid a glove (donator-only gloves, team restrictions ...)
	if hook.Run("ZCityCSGOGloves_CanWear", ent, variant) == false then return nil end

	return variant
end

local function setGlove(ent, id)
	if ent.zcg_glove == id then return end
	ent.zcg_glove = id
	ent:SetNWString(NW, id)
end

function ZCG.UpdatePlayer(ply)
	local variant = ZCG.WantedGlove(ply)
	local id = variant and variant.id or NONE
	setGlove(ply, id)

	-- the ragdoll of a knocked down (still alive) player follows its owner
	local ragdoll = ply.FakeRagdoll
	if IsValid(ragdoll) and ragdoll.zcg_owner == ply and ply:Alive() then
		setGlove(ragdoll, id)
	end
end

timer.Create("zcg_poll", math.max(tonumber(Config.PollInterval) or 0.3, 0.05), 0, function()
	if not ZCG.Ready then return end
	for _, ply in ipairs(player.GetAll()) do
		ZCG.UpdatePlayer(ply)
	end
end)

-- Z-City calls this for every ragdoll it makes out of a player (knock down and death)
hook.Add("Ragdoll_Create", "zcg_ragdoll", function(ply, ragdoll)
	if not IsValid(ply) or not IsValid(ragdoll) then return end

	local id = NONE
	if ZCG.Ready then
		if ply:IsPlayer() then
			ZCG.UpdatePlayer(ply)
			id = ply.zcg_glove or NONE
		else
			local variant = ZCG.WantedGlove(ply)
			id = variant and variant.id or NONE
		end
	end

	ragdoll.zcg_owner = ply
	ragdoll.zcg_glove = nil
	setGlove(ragdoll, id)
end)

-- ---------------------------------------------------------------------------------------------
-- content delivery
-- ---------------------------------------------------------------------------------------------
local function addFolder(dir, added)
	local files, dirs = file.Find(dir .. "/*", "GAME")
	for _, name in ipairs(files or {}) do
		resource.AddSingleFile(dir .. "/" .. name)
		added.count = added.count + 1
	end
	for _, name in ipairs(dirs or {}) do
		addFolder(dir .. "/" .. name, added)
	end
end

local function setupContent()
	if Config.WorkshopID then
		resource.AddWorkshop(tostring(Config.WorkshopID))
	end

	local firstModel = ZCG.Variants[1].model
	local installed = file.Exists(firstModel, "GAME")

	if Config.FastDL then
		if installed then
			local added = { count = 0 }
			addFolder("models/zcity_csgo_gloves", added)
			addFolder("materials/zcity_csgo_gloves", added)
			local _, dirs = file.Find("materials/models/weapons/v_models/arms/*", "GAME")
			for _, name in ipairs(dirs or {}) do
				if string.sub(name, 1, 6) == "glove_" then
					addFolder("materials/models/weapons/v_models/arms/" .. name, added)
				end
			end
			ZCG.Print("FastDL: " .. added.count .. " files added to the download list.")
		else
			ZCG.Print("FastDL is enabled, but the glove content is not installed on the server - nothing to send.")
		end
	end

	if Config.PrecacheModels and installed then
		for path in pairs(ZCG.Models) do
			if file.Exists(path, "GAME") then util.PrecacheModel(path) end
		end
	end

	if not installed and not Config.WorkshopID then
		ZCG.Print("the glove models are not installed on the server (" .. firstModel .. "). "
			.. "That is fine as long as every player has the addon content.")
	end
end

setupContent()

-- ---------------------------------------------------------------------------------------------
-- zcg_status: what the server thinks (run it in the server console or as a super admin)
-- ---------------------------------------------------------------------------------------------
concommand.Add("zcg_status", function(caller)
	if IsValid(caller) and not caller:IsSuperAdmin() then return end

	local function out(text)
		if IsValid(caller) then caller:PrintMessage(HUD_PRINTCONSOLE, text .. "\n") else print(text) end
	end

	out("[CS:GO Gloves] version " .. ZCG.Version .. ", registered in Z-City: " .. tostring(ZCG.Ready == true)
		.. ", zcg_any_model " .. ZCG.cvAnyModel:GetString() .. ", zcg_hide_hands " .. ZCG.cvHideHands:GetString())
	for _, ply in ipairs(player.GetAll()) do
		local appearance = ply.CurAppearance
		local groups = istable(appearance) and appearance.ABodygroups
		out(string.format("  %-24s glove %-16s appearance HANDS = %s, appearance model = %s, model = %s",
			ply:Nick(), tostring(ply.zcg_glove), tostring(istable(groups) and groups.HANDS or nil),
			tostring(istable(appearance) and appearance.AModel or nil), tostring(ply:GetModel())))
	end
end)
