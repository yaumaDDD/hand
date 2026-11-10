-- A very small imitation of the Garry's Mod Lua environment, just enough to execute the addon
-- outside of the game (see tools/test_lua.py). It only proves that the code paths run and that
-- the logic does what it is meant to do against THIS imitation - it is not the game.
--
-- usage: local M = dofile("gmod_mock.lua")(realm)   -- realm = "server" | "client"

return function(realm)
	local M = { realm = realm, time = 0, frame = 1, log = {}, errors = {}, sounds = {} }

	SERVER = realm == "server"
	CLIENT = realm == "client"

	-- ------------------------------------------------------------------ basics
	function istable(v) return type(v) == "table" and not (getmetatable(v) and getmetatable(v).__ispanel) end
	function isstring(v) return type(v) == "string" end
	function isnumber(v) return type(v) == "number" end
	function isfunction(v) return type(v) == "function" end
	function isbool(v) return type(v) == "boolean" end
	function ispanel(v) return type(v) == "table" and getmetatable(v) ~= nil and getmetatable(v).__ispanel == true end

	function IsValid(v)
		if v == nil or v == false then return false end
		if type(v) ~= "table" then return false end
		local f = v.IsValid
		if not f then return false end
		return f(v)
	end

	function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
	color_white = Color(255, 255, 255, 255)

	local pending = ""
	function MsgC(...) -- one log entry per finished line
		for _, v in ipairs({ ... }) do
			if type(v) == "string" then pending = pending .. v end
		end
		while true do
			local line, rest = pending:match("^(.-)\n(.*)$")
			if not line then break end
			M.log[#M.log + 1] = line
			pending = rest
		end
	end
	function print(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		M.log[#M.log + 1] = table.concat(parts, "\t")
	end
	function ErrorNoHalt(text) M.errors[#M.errors + 1] = text end

	function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
	function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

	function SortedPairs(t)
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local i = 0
		return function()
			i = i + 1
			if keys[i] ~= nil then return keys[i], t[keys[i]] end
		end
	end

	function RealTime() return M.time end
	function CurTime() return M.time end
	function FrameNumber() return M.frame end
	function ScreenScale(n) return n * (M.scrw or 1920) / 640 end
	function ScrW() return M.scrw or 1920 end
	function ScrH() return M.scrh or 1080 end

	FCVAR_ARCHIVE, FCVAR_REPLICATED = 128, 8192
	EF_BONEMERGE = 1
	RENDERGROUP_OPAQUE, RENDERGROUP_BOTH = 7, 9
	HUD_PRINTCONSOLE = 2
	MOUSE_LEFT, MOUSE_RIGHT = 107, 108
	TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = 0, 1, 2, 3, 4

	-- ------------------------------------------------------------------ files
	M.files = {} -- path -> true ("GAME" search path)
	M.included, M.csfiles = {}, {}
	file = {}
	function file.Exists(path, where) return M.files[path] == true end
	function file.Find(pattern, where)
		local dir = pattern:gsub("/%*$", "")
		local files, dirs, seen = {}, {}, {}
		for path in pairs(M.files) do
			if path:sub(1, #dir + 1) == dir .. "/" then
				local rest = path:sub(#dir + 2)
				local first, more = rest:match("^([^/]+)(/?)")
				if more == "/" then
					if not seen[first] then seen[first] = true dirs[#dirs + 1] = first end
				else
					files[#files + 1] = first
				end
			end
		end
		table.sort(files) table.sort(dirs)
		return files, dirs
	end

	function AddCSLuaFile(path)
		assert(SERVER, "AddCSLuaFile on the client")
		M.csfiles[#M.csfiles + 1] = path or "<this file>"
	end
	function include(path)
		M.included[#M.included + 1] = path
		local f = assert(loadfile(M.luaroot .. "/" .. path))
		return f()
	end

	-- ------------------------------------------------------------------ hooks, timers, convars
	hook = { list = {} }
	function hook.Add(name, id, fn)
		hook.list[name] = hook.list[name] or {}
		hook.list[name][id] = fn
	end
	function hook.Remove(name, id) if hook.list[name] then hook.list[name][id] = nil end end
	function hook.Run(name, ...)
		local fns = hook.list[name]
		if not fns then return nil end
		for _, fn in pairs(fns) do
			local a, b, c = fn(...)
			if a ~= nil then return a, b, c end
		end
		return nil
	end

	timer = { list = {} }
	function timer.Create(id, delay, reps, fn) timer.list[id] = { delay = delay, reps = reps, fn = fn, next = M.time + delay } end
	function timer.Adjust(id, delay, reps, fn)
		local t = timer.list[id]
		if not t then return false end
		t.delay = delay
		if reps ~= nil then t.reps = reps end
		if fn then t.fn = fn end
		t.next = M.time + delay
		return true
	end
	function timer.Simple(delay, fn) timer.list[{}] = { delay = delay, reps = 1, fn = fn, next = M.time + delay } end
	function timer.Remove(id) timer.list[id] = nil end

	-- moves the clock forward and fires the timers that are due
	function M.advance(seconds, step)
		step = step or 0.05
		local target = M.time + seconds
		while M.time < target - 1e-9 do
			M.time = M.time + step
			for id, t in pairs(timer.list) do
				if timer.list[id] == t and M.time + 1e-9 >= t.next then
					t.next = M.time + t.delay
					if t.reps ~= 0 then
						t.reps = t.reps - 1
						if t.reps <= 0 then timer.list[id] = nil end
					end
					t.fn()
				end
			end
		end
	end

	M.convars = {}
	local CV = {}
	CV.__index = CV
	function CV:GetString() return self.value end
	function CV:GetBool() return (tonumber(self.value) or 0) ~= 0 end
	function CV:GetInt() return math.floor(tonumber(self.value) or 0) end
	function CV:GetFloat() return tonumber(self.value) or 0 end

	function CreateConVar(name, default, flags, help, min, max)
		assert(type(name) == "string" and type(default) == "string", "CreateConVar: name and default must be strings")
		assert(type(flags) == "number" or type(flags) == "table", "CreateConVar: flags")
		if not M.convars[name] then M.convars[name] = setmetatable({ name = name, value = default, flags = flags }, CV) end
		return M.convars[name]
	end
	function CreateClientConVar(name, default, save, userinfo, help, min, max)
		assert(CLIENT, "CreateClientConVar on the server")
		assert(type(default) == "string")
		return CreateConVar(name, default, 0, help, min, max)
	end
	function GetConVar(name) return M.convars[name] end

	cvars = { callbacks = {} }
	function cvars.AddChangeCallback(name, fn, id) cvars.callbacks[name] = fn end
	function M.setConVar(name, value)
		local cv = assert(M.convars[name], "unknown convar " .. name)
		local old = cv.value
		cv.value = tostring(value)
		if cvars.callbacks[name] then cvars.callbacks[name](name, old, cv.value) end
	end

	concommand = { list = {} }
	function concommand.Add(name, fn, auto, help) concommand.list[name] = { fn = fn, auto = auto } end
	function M.command(name, caller, ...)
		local args = { ... }
		return concommand.list[name].fn(caller, name, args, table.concat(args, " "))
	end

	util = { precached = {} }
	function util.PrecacheModel(path) util.precached[#util.precached + 1] = path end

	resource = { workshop = {}, files = {} }
	function resource.AddWorkshop(id) resource.workshop[#resource.workshop + 1] = id end
	function resource.AddSingleFile(path) resource.files[#resource.files + 1] = path end

	-- ------------------------------------------------------------------ entities
	M.models = {} -- model path -> { materials = {...} } known to the fake engine
	M.entities = {}
	M.csmodels = {} -- every ClientsideModel ever created

	local ENT = {}
	ENT.__index = ENT
	function ENT:IsValid() return not self.removed end
	function ENT:IsPlayer() return self.isplayer == true end
	function ENT:IsRagdoll() return self.class == "prop_ragdoll" end
	function ENT:GetClass() return self.class end
	function ENT:Alive() return self.alive ~= false end
	function ENT:Nick() return self.nick or "player" end
	function ENT:IsSuperAdmin() return self.superadmin == true end
	function ENT:GetModel() return self.model end
	function ENT:SetModel(path) self.model = path end
	function ENT:GetMaterials()
		local info = M.models[self.model]
		local out = {}
		for i, name in ipairs(info and info.materials or {}) do out[i] = name end
		return out
	end
	function ENT:GetSubMaterial(index)
		assert(type(index) == "number", "GetSubMaterial: index must be a number")
		return self.submats[index] or ""
	end
	function ENT:SetSubMaterial(index, mat)
		if index == nil then self.submats = {} return end
		assert(type(index) == "number" and index >= 0 and index <= 31, "SetSubMaterial: bad index " .. tostring(index))
		assert(mat == nil or type(mat) == "string", "SetSubMaterial: material must be a string or nil")
		if mat == "" then mat = nil end
		self.submats[index] = mat
		self.submatWrites = (self.submatWrites or 0) + 1
	end
	function ENT:SetNWString(key, value)
		assert(SERVER or self.clientside or M.allowClientNW, "SetNWString on the client")
		assert(type(value) == "string", "SetNWString: value must be a string")
		self.nw[key] = value
		self.nwWrites = (self.nwWrites or 0) + 1
	end
	function ENT:GetNWString(key, default)
		local v = self.nw[key]
		if v == nil then return default or "" end
		return v
	end
	function ENT:SetNWEntity(key, value) self.nw[key] = value end
	function ENT:GetNWEntity(key, default)
		local v = self.nw[key]
		if v == nil then return default or NULL end
		return v
	end
	function ENT:PrintMessage(kind, text) M.log[#M.log + 1] = "[to " .. self:Nick() .. "] " .. text end
	function ENT:GetEyeTrace() return { Entity = self.lookat or NULL } end
	function ENT:Remove() self.removed = true end
	function ENT:PS_HasItem(id) return self.items ~= nil and self.items[id] == true end
	-- clientside model only
	function ENT:SetNoDraw(b) self.nodraw = b end
	function ENT:DrawShadow(b) self.shadow = b end
	function ENT:SetParent(parent) self.parent = parent self.parentSets = (self.parentSets or 0) + 1 end
	function ENT:GetParent() return self.parent or NULL end
	function ENT:AddEffects(fx) self.effects = bit.bor(self.effects or 0, fx) end
	function ENT:SetBodygroup(id, value)
		assert(type(id) == "number" and type(value) == "number", "SetBodygroup: numbers expected")
		self.bodygroups[id] = value
	end
	function ENT:GetBodygroup(id) return self.bodygroups[id] or 0 end
	function ENT:DrawModel()
		assert(not self.removed, "DrawModel on a removed entity")
		self.draws = (self.draws or 0) + 1
		M.drawn[#M.drawn + 1] = self
	end
	M.drawn = {}

	NULL = setmetatable({ removed = true, nw = {}, submats = {}, bodygroups = {} }, ENT)

	function M.newEntity(class, model, fields)
		local ent = setmetatable({ class = class, model = model, nw = {}, submats = {}, bodygroups = {} }, ENT)
		for k, v in pairs(fields or {}) do ent[k] = v end
		M.entities[#M.entities + 1] = ent
		return ent
	end
	function M.newPlayer(nick, model, fields)
		local ply = M.newEntity("player", model, fields)
		ply.isplayer, ply.nick = true, nick
		M.players[#M.players + 1] = ply
		return ply
	end

	M.players = {}
	player = {}
	function player.GetAll()
		local out = {}
		for _, ply in ipairs(M.players) do if not ply.removed then out[#out + 1] = ply end end
		return out
	end
	function LocalPlayer() return M.localplayer or NULL end

	function ClientsideModel(path, group)
		assert(CLIENT, "ClientsideModel on the server")
		assert(type(path) == "string", "ClientsideModel: path")
		local ent = M.newEntity("class C_BaseFlex", path, { clientside = true })
		M.csmodels[#M.csmodels + 1] = ent
		return ent
	end

	-- ------------------------------------------------------------------ rendering / materials
	M.materials = { ["null"] = true } -- materials that exist
	M.modulation = { 1, 1, 1 }
	render = {}
	function render.GetColorModulation() return M.modulation[1], M.modulation[2], M.modulation[3] end
	function render.SetColorModulation(r, g, b) M.modulation = { r, g, b } end

	function Material(name, flags)
		local exists = M.materials[name] == true or M.files["materials/" .. name] == true
		return { name = name, IsError = function() return not exists end }
	end

	surface = {}
	function surface.CreateFont(name, data)
		assert(type(data.font) == "string" and type(data.size) == "number", "CreateFont")
		M.fonts = M.fonts or {}
		M.fonts[name] = data
	end
	function surface.SetFont(name) assert(M.fonts and M.fonts[name], "unknown font " .. tostring(name)) M.font = name end
	function surface.GetTextSize(text) return #text * (M.fonts[M.font].size * 0.5), M.fonts[M.font].size end
	function surface.SetDrawColor() end
	function surface.SetMaterial(mat) assert(mat and mat.IsError, "SetMaterial: IMaterial expected") end
	function surface.DrawRect() end
	function surface.DrawOutlinedRect() end
	function surface.DrawLine() end
	function surface.DrawTexturedRect() end
	function surface.PlaySound(path) M.sounds[#M.sounds + 1] = path end

	draw = {}
	function draw.RoundedBox() end
	function draw.RoundedBoxEx() end
	function draw.SimpleText(text, font)
		assert(type(text) == "string", "draw.SimpleText: text must be a string")
		assert(M.fonts and M.fonts[font], "unknown font " .. tostring(font))
		M.texts = M.texts or {}
		M.texts[#M.texts + 1] = text
	end

	-- ------------------------------------------------------------------ vgui
	local PANEL = {}
	local panelMeta = { __ispanel = true }
	panelMeta.__index = function(t, k) return PANEL[k] end

	M.panels = {}
	M.hovered = nil
	M.mouse = {}
	M.cursor = { 0, 0 }

	function PANEL:IsValid() return not self.removed end
	function PANEL:GetTable() return self end
	function PANEL:GetParent() return self.parent end
	function PANEL:GetChildren()
		local out = {}
		for _, child in ipairs(self.children) do if not child.removed then out[#out + 1] = child end end
		return out
	end
	function PANEL:SetParent(parent)
		if self.parent then
			for i, child in ipairs(self.parent.children) do
				if child == self then table.remove(self.parent.children, i) break end
			end
		end
		self.parent = parent
		if parent then parent.children[#parent.children + 1] = self end
	end
	function PANEL:SetSize(w, h) self.w, self.h = w, h end
	function PANEL:SetWide(w) self.w = w end
	function PANEL:SetTall(h) self.h = h end
	function PANEL:GetWide() return self.w or 0 end
	function PANEL:GetTall() return self.h or 0 end
	function PANEL:SetPos(x, y)
		assert(type(x) == "number" and type(y) == "number", "SetPos: numbers expected")
		self.x, self.y = x, y
	end
	function PANEL:GetPos() return self.x or 0, self.y or 0 end
	function PANEL:SetZPos(z) self.z = z end
	function PANEL:MoveToFront() end
	function PANEL:CursorPos() return M.cursor[1], M.cursor[2] end
	function PANEL:SetText(text) self.text = text end
	function PANEL:GetText() return self.text or "" end
	function PANEL:SetFont(font) self.font = font end
	function PANEL:SetTextColor(c) self.textColor = c end
	function PANEL:SetTooltip(text) self.tooltip = text end
	function PANEL:IsHovered() return M.hovered == self end
	function PANEL:Dock() end
	function PANEL:Remove()
		-- like the game: invalid at once, OnRemove a frame later (M.flushPanels)
		if self.removed then return end
		self.removed = true
		M.pendingRemoval[#M.pendingRemoval + 1] = self
		for _, child in ipairs(self.children) do child:Remove() end
	end
	M.pendingRemoval = {}
	function M.flushPanels()
		local list = M.pendingRemoval
		M.pendingRemoval = {}
		for _, panel in ipairs(list) do
			if panel.OnRemove then panel:OnRemove() end
		end
	end

	local controls = {} -- user registered classes
	local builtin = {
		Panel = {}, DPanel = {}, DLabel = {}, DFrame = {},
		DButton = { DoClick = function() end },
		DScrollPanel = {
			GetVBar = function(self) return self.vbar end,
			GetCanvas = function(self) return self.canvas end,
		},
		DModelPanel = {
			LayoutEntity = function() end,
			PostDrawModel = function() end,
			PreDrawModel = function() end,
			SetModel = function(self, path)
				if IsValid(self.Entity) then self.Entity:Remove() end
				self.Entity = ClientsideModel(path)
			end,
		},
		DVScrollBar = { SetHideButtons = function() end },
	}

	local function newPanel(class, parent)
		local panel = setmetatable({ class = class, children = {} }, panelMeta)
		M.panels[#M.panels + 1] = panel
		if parent then
			if parent.class == "DScrollPanel" and parent.canvas then parent = parent.canvas end
			panel:SetParent(parent)
		end
		return panel
	end

	vgui = {}
	function vgui.Register(name, tbl, base)
		tbl.Base = base or "Panel"
		controls[name] = tbl
		return tbl
	end
	function vgui.GetControlTable(name) return controls[name] end
	function vgui.Create(class, parent)
		local panel
		if controls[class] then
			panel = vgui.Create(controls[class].Base, parent)
			for k, v in pairs(controls[class]) do panel[k] = v end
			panel.class = class
			if controls[class].Init then controls[class].Init(panel) end -- only the class's own Init, like the game
			return panel
		end
		assert(builtin[class], "vgui.Create: unknown class " .. tostring(class))
		panel = newPanel(class, parent)
		for k, v in pairs(builtin[class]) do panel[k] = v end
		if class == "DScrollPanel" then
			panel.canvas = newPanel("Panel", nil)
			panel.canvas:SetParent(panel)
			panel.vbar = newPanel("DVScrollBar", nil)
			panel.vbar:SetParent(panel)
			for k, v in pairs(builtin.DVScrollBar) do panel.vbar[k] = v end
			panel.vbar.btnGrip = newPanel("DButton", nil)
			panel.vbar.btnGrip:SetParent(panel.vbar)
		end
		return panel
	end
	function vgui.GetHoveredPanel() return M.hovered end

	input = {}
	function input.IsMouseDown(code) return M.mouse[code] == true end

	M.menus = {}
	function DermaMenu()
		local menu = newPanel("DMenu", nil)
		menu.options = {}
		function menu:AddOption(text, fn)
			assert(type(text) == "string", "AddOption: text")
			self.options[#self.options + 1] = { text = text, fn = fn }
		end
		function menu:AddSpacer() self.options[#self.options + 1] = { spacer = true } end
		function menu:Open() self.opened = true end
		M.menus[#M.menus + 1] = menu
		return menu
	end
	-- the player picks an option: its callback runs, then the menu goes away
	function M.pickOption(menu, text)
		for _, option in ipairs(menu.options) do
			if option.text and option.text:sub(1, #text) == text then
				option.fn()
				menu:Remove()
				return true
			end
		end
		error("menu has no option starting with " .. text)
	end

	-- paints (and thinks) a panel tree once, like one frame of the game
	function M.paint(panel)
		if panel.removed then return end
		if panel.Think then panel:Think() end
		if panel.removed then return end
		if panel.Paint then panel:Paint(panel:GetWide(), panel:GetTall()) end
		for _, child in ipairs(panel:GetChildren()) do M.paint(child) end
	end

	return M
end
