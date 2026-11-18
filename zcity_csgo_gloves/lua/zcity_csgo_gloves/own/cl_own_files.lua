-- Our own appearance system: the files of the client. The server keeps what a player wears
-- (data/zco/<steamid64>.txt on the server) and hands it to him when he joins; what is kept here are
-- the sets of his own - several looks he can put on in one click, and the ones he had before, in
-- the files of the Appearance Mod (data/zcity/appearances/*.json), which are read as well so that
-- nothing he made before is lost.

ZCO = ZCO or {}

ZCO.Selected = CreateClientConVar("zco_selected", "main", true, false,
	"the set of data/zco/ that is sent to the server when it asks for the look of this client")
-- (userinfo: the server reads it, so that a player who asks for a random look gets one even where
-- a saved look would otherwise be kept - zco_keep_appearance)
ZCO.ForcedRandom = CreateClientConVar("zco_random", "0", true, true,
	"1: ask the server for a random look instead of the one of the files", 0, 1)

ZCO.Presets = ZCO.Presets or {}       -- name -> the appearance of the files of this client
ZCO.Saved = ZCO.Saved or nil          -- the appearance the server keeps for this player

--- where the gamemode of Z-City and the Appearance Mod keep the looks of a player
local OLD_DIRECTORY = "zcity/appearances/"

local function folder()
	return ZCO.Directory:sub(1, -2)
end

local function pathOf(name)
	return ZCO.Directory .. name .. ZCO.Extension
end

--- the names of the sets this client keeps, in alphabetical order
function ZCO.PresetList()
	local names = {}
	local files = file.Find(folder() .. "/*", "DATA")
	if type(files) == "table" then
		for index = 1, #files do
			local name = tostring(files[index])
			if name:sub(-#ZCO.Extension) == ZCO.Extension then
				names[#names + 1] = name:sub(1, -#ZCO.Extension - 1)
			end
		end
	end
	table.sort(names)
	return names
end

--- read one set (nil when there is no such file or it is not one of ours)
function ZCO.LoadPreset(name)
	if type(name) ~= "string" or name == "" then return nil end
	local path = pathOf(name)
	if not file.Exists(path, "DATA") then return nil end
	local got = ZCO.Deserialize(file.Read(path, "DATA"))
	if got then ZCO.Presets[name] = got end
	return got
end

--- write one set
function ZCO.SavePreset(name, appearance)
	if type(name) ~= "string" or name == "" then return false end
	name = name:gsub("[\\/:*?\"<>|]", "_")
	file.CreateDir(folder())
	file.Write(pathOf(name), ZCO.Serialize(appearance or ZCO.Saved or ZCO.Default()))
	ZCO.Presets[name] = appearance or ZCO.Saved or ZCO.Default()
	return true
end

function ZCO.DeletePreset(name)
	if type(name) ~= "string" or name == "" then return false end
	if file.Exists(pathOf(name), "DATA") then file.Delete(pathOf(name)) end
	ZCO.Presets[name] = nil
	return true
end

--- the sets the Appearance Mod kept (data/zcity/appearances/*.json), read into ours: the fields
--- are the same, only the file is another one
function ZCO.OldList()
	local names = {}
	local files = file.Find(OLD_DIRECTORY .. "*", "DATA")
	if type(files) == "table" then
		for index = 1, #files do
			local name = tostring(files[index])
			if name:sub(-5) == ".json" then names[#names + 1] = name:sub(1, -6) end
		end
	end
	table.sort(names)
	return names
end

function ZCO.ImportOld(name, quiet)
	local path = OLD_DIRECTORY .. name .. ".json"
	if not file.Exists(path, "DATA") then return nil end
	local text = file.Read(path, "DATA")
	local got = util.JSONToTable(text or "")
	if type(got) ~= "table" then return nil end
	local appearance = ZCO.Clean({
		AModel = got.AModel,
		AClothes = type(got.AClothes) == "table" and got.AClothes or { main = "normal" },
		AName = got.AName or "",
		AColor = type(got.AColor) == "table" and Color(got.AColor.r or 180, got.AColor.g or 180,
			got.AColor.b or 180) or Color(180, 180, 180),
		AAttachments = type(got.AAttachments) == "table" and got.AAttachments or {},
		ABodygroups = type(got.ABodygroups) == "table" and got.ABodygroups or {},
		AFacemap = got.AFacemap or "Default",
	})
	if not quiet then ZCO.SavePreset(name, appearance) end
	return appearance
end

--- The gamemode of Z-City keeps the look of a player in a file of its own -
--- data/zcity/appearances/<name>.json, the name in hg_appearance_selected - and its client answers
--- with that file when the server asks (the nets Get_Appearance / OnlyGet_Appearance). The look
--- chosen here is written there as well, so that whichever of the two paths dresses the player
--- next dresses him in what he chose, and the editor of Z-City shows the same look.
--- how many files of the gamemode the look was written into (0 when there is nothing to write)
function ZCO.WriteOld(name, appearance)
	local got = appearance or ZCO.Saved
	if type(got) ~= "table" or next(got) == nil then return 0 end
	-- the set of our own, and the one the gamemode has chosen (hg_appearance_selected): its client
	-- answers the server with that file, so it has to hold what the player chose here
	local names, seen = {}, {}
	local function want(one)
		if type(one) ~= "string" or one == "" then return end
		one = one:gsub("[\\/:*?\"<>|]", "_")
		if one == "" or seen[one] then return end
		seen[one] = true
		names[#names + 1] = one
	end
	want(name)
	want(ZCO.Selected:GetString())
	local tables = hg and hg.Appearance
	if type(tables) == "table" and tables.SelectedAppearance and tables.SelectedAppearance.GetString then
		want(tables.SelectedAppearance:GetString())
	end
	if #names == 0 then return 0 end
	file.CreateDir(OLD_DIRECTORY:sub(1, -2))
	-- the way the module of the gamemode writes it: the same folder, the same JSON
	local text = util.TableToJSON(got, true)
	for index = 1, #names do
		file.Write(OLD_DIRECTORY .. names[index] .. ".json", text)
	end
	return #names
end

--- the look this client asks the server for when the server has none of its own: the set of
--- zco_selected, or a random one when zco_random is 1
function ZCO.LocalAppearance()
	if ZCO.ForcedRandom:GetBool() then return nil end
	local name = ZCO.Selected:GetString()
	if name == "" then name = "main" end
	local got = ZCO.LoadPreset(name)
	if got then return got end
	-- the file of the Appearance Mod with that name: read it and keep it as ours
	local old = ZCO.ImportOld(name, true)
	if old then
		ZCO.SavePreset(name, old)
		return old
	end
	return nil
end

-- --------------------------------------------------------------------------------------
-- the server
-- --------------------------------------------------------------------------------------

net.Receive("zco_ask", function()
	local appearance = ZCO.LocalAppearance()
	-- Nothing of our own is kept: the file the Appearance Mod keeps is the save of this player -
	-- the server is asked for it at every spawn, so a look chosen once stays (2.24.0).
	if (not appearance or next(appearance) == nil) and not ZCO.ForcedRandom:GetBool()
		and hg and hg.Appearance
		and hg.Appearance.LoadAppearanceFile and hg.Appearance.SelectedAppearance then
		local got = hg.Appearance.LoadAppearanceFile(hg.Appearance.SelectedAppearance:GetString())
		if type(got) == "table" and next(got) ~= nil then
			appearance = got
			local col = appearance.AColor
			if istable(col) and col.r and col.g and col.b then
				appearance.AColor = { r = col.r, g = col.g, b = col.b, a = col.a or 255 }
			end
		end
	end
	net.Start("zco_answer")
	net.WriteTable(appearance or {})
	net.SendToServer()
end)

net.Receive("zco_got", function()
	local appearance = net.ReadTable()
	if type(appearance) == "table" and next(appearance) ~= nil then
		ZCO.Saved = ZCO.Clean(appearance)
		if type(ZCO.Saved.AColor) == "table" and ZCO.Saved.AColor.r then
			ZCO.Saved.AColor = Color(ZCO.Saved.AColor.r, ZCO.Saved.AColor.g, ZCO.Saved.AColor.b,
				ZCO.Saved.AColor.a or 255)
		end
		ZCO.WriteOld(ZCO.Selected:GetString(), ZCO.Saved)
		hook.Run("ZCOSaved", ZCO.Saved)
	end
end)

net.Receive("zco_say", function()
	local text = net.ReadString()
	if text and text ~= "" then chat.AddText(Color(120, 200, 255), "[Внешность] ", Color(230, 230, 230), text) end
end)

--- ask the server for an appearance (what the menu does when a player chooses his look)
function ZCO.Send(appearance)
	net.Start("zco_set")
	net.WriteTable(appearance or ZCO.Saved or ZCO.Default())
	net.SendToServer()
end

concommand.Add("zco_import", function()
	local taken = 0
	for _, name in ipairs(ZCO.OldList()) do
		if ZCO.ImportOld(name) then taken = taken + 1 end
	end
	chat.AddText(Color(120, 200, 255), "[Внешность] ", Color(230, 230, 230),
		("Перенесено наборов из файлов прежнего мода: %d (data/zco/)."):format(taken))
end, nil, "Read the sets of data/zcity/appearances/ into data/zco/")
