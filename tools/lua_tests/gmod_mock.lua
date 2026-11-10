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

	-- ------------------------------------------------------------------ vectors, angles, matrices
	local VEC = {}
	VEC.__index = VEC
	function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VEC) end
	VEC.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
	VEC.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
	VEC.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
	function isvector(v) return getmetatable(v) == VEC end
	function VEC:Distance(o) return math.sqrt((self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2) end

	function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

	-- VMatrix, reduced to rotation / scale / translation: 12 numbers, row by row
	-- ( 1  2  3 | 4 )     columns 1-3: where the x, y and z axis of the bone point,
	-- ( 5  6  7 | 8 )     column 4: where the bone is
	-- ( 9 10 11 | 12 )
	local MAT = {}
	MAT.__index = MAT
	local function matrix(t) return setmetatable(t, MAT) end
	function Matrix(data)
		assert(data == nil, "the imitation of Matrix() only builds the identity")
		return matrix({ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 })
	end
	MAT.__mul = function(a, b)
		assert(getmetatable(a) == MAT and getmetatable(b) == MAT, "VMatrix * VMatrix expected")
		local m = {}
		for row = 0, 2 do
			local a1, a2, a3, a4 = a[row * 4 + 1], a[row * 4 + 2], a[row * 4 + 3], a[row * 4 + 4]
			for col = 1, 4 do
				m[row * 4 + col] = a1 * b[col] + a2 * b[4 + col] + a3 * b[8 + col] + (col == 4 and a4 or 0)
			end
		end
		return matrix(m)
	end
	function MAT:GetTranslation() return Vector(self[4], self[8], self[12]) end
	function MAT:SetTranslation(v) self[4], self[8], self[12] = v.x, v.y, v.z end
	function MAT:GetScale()
		local out = {}
		for col = 1, 3 do out[col] = math.sqrt(self[col] ^ 2 + self[4 + col] ^ 2 + self[8 + col] ^ 2) end
		return Vector(out[1], out[2], out[3])
	end
	function MAT:SetScale(v) -- the length of the three axes; rotation and translation stay
		local have, want = self:GetScale(), { v.x, v.y, v.z }
		local old = { have.x, have.y, have.z }
		for col = 1, 3 do
			local f = old[col] > 0 and want[col] / old[col] or 0
			self[col], self[4 + col], self[8 + col] = self[col] * f, self[4 + col] * f, self[8 + col] * f
		end
	end
	function MAT:GetInverseTR() -- like the game: only right for a matrix without scale
		local m = { self[1], self[5], self[9], 0, self[2], self[6], self[10], 0, self[3], self[7], self[11], 0 }
		for row = 0, 2 do
			m[row * 4 + 4] = -(m[row * 4 + 1] * self[4] + m[row * 4 + 2] * self[8] + m[row * 4 + 3] * self[12])
		end
		return matrix(m)
	end

	-- for the tests: a bone at x y z, turned by `yaw` degrees about the z axis, scaled by `scale`
	function M.matrix(x, y, z, yaw, scale)
		local c, sn, k = math.cos(math.rad(yaw or 0)), math.sin(math.rad(yaw or 0)), scale or 1
		return matrix({ c * k, -sn * k, 0, x, sn * k, c * k, 0, y, 0, 0, k, z })
	end
	function M.copyMatrix(m)
		local t = {}
		for i = 1, 12 do t[i] = m[i] end
		return matrix(t)
	end
	function M.sameMatrix(a, b)
		if not a or not b then return false end
		for i = 1, 12 do
			if math.abs(a[i] - b[i]) > 1e-6 then return false end
		end
		return true
	end

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

	-- Reading: M.filedata[path] = { [offset] = "bytes", ... } - what the file holds at some
	-- places, zero bytes everywhere else. A path without an entry cannot be opened.
	M.filedata, M.opened, M.openNow = {}, 0, 0
	function file.Open(path, mode, where)
		assert(mode == "rb" and where == "GAME", "file.Open: only reading from GAME is imitated")
		local data = M.filedata[path]
		if not data then return nil end
		M.opened, M.openNow = M.opened + 1, M.openNow + 1
		local f = { pos = 0 }
		function f:Seek(pos) assert(not self.closed, "Seek on a closed file") self.pos = pos end
		function f:Read(count)
			assert(not self.closed, "Read on a closed file")
			local out = {}
			for i = 0, count - 1 do
				local byte = 0
				for at, bytes in pairs(data) do
					local k = self.pos + i - at
					if k >= 0 and k < #bytes then byte = bytes:byte(k + 1) end
				end
				out[#out + 1] = string.char(byte)
			end
			self.pos = self.pos + count
			return table.concat(out)
		end
		function f:Close()
			assert(not self.closed, "file closed twice")
			self.closed = true
			M.openNow = M.openNow - 1
		end
		return f
	end
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
	function ENT:SetModel(path)
		self.model = path
		self.bones = nil
	end
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
	function ENT:SetPos(v) self.pos = Vector(v.x, v.y, v.z) end
	function ENT:GetPos() return self.pos and Vector(self.pos.x, self.pos.y, self.pos.z) or Vector(0, 0, 0) end
	function ENT:SetAngles(a)
		assert(a.p == 0 and a.y == 0 and a.r == 0, "the imitation does not turn entities")
	end

	-- ---- bones
	-- M.models[path].bones = { { name, parent, x, y, z }, ... }: the pose a model has on its own,
	-- every bone relative to its parent (index from 0, -1 = no parent), translations only.
	local function boneDefs(ent)
		local info = M.models[ent.model]
		return info and info.bones or {}
	end

	-- What the engine does when it sets the bones of an entity up: the animation (here: the pose
	-- of the model itself, then ent.animate), then - for a bone-merged model - the bones of the
	-- parent with the same names. Whatever was written to the bones before is gone.
	function M.engineSetup(ent)
		local pos = ent:GetPos()
		local bones = {}
		for i, def in ipairs(boneDefs(ent)) do
			local parent = def[2] >= 0 and bones[def[2]] or M.matrix(pos.x, pos.y, pos.z)
			bones[i - 1] = parent * M.matrix(def[3], def[4], def[5])
		end
		ent.bones, ent.bonesFrame = bones, M.frame
		if ent.animate then ent.animate(ent) end

		local parent = ent.parent
		if parent and not parent.removed and bit.band(ent.effects or 0, EF_BONEMERGE) ~= 0 and parent.bones then
			for i, def in ipairs(boneDefs(ent)) do
				local theirs = parent:LookupBone(def[1])
				if theirs then bones[i - 1] = M.copyMatrix(parent.bones[theirs]) end
			end
		end
	end

	-- a clientside model knows nothing about its bones before the first SetupBones
	local function ready(ent) return ent.bones ~= nil or not ent.clientside end

	function ENT:SetupBones()
		assert(not self.removed, "SetupBones on a removed entity")
		self.setups = (self.setups or 0) + 1
		M.engineSetup(self)
	end
	function ENT:GetBoneCount()
		if not ready(self) then return 0 end
		return #boneDefs(self)
	end
	function ENT:GetBoneName(index)
		local def = boneDefs(self)[index + 1]
		if not def then return nil end
		if not ready(self) then return "__INVALIDBONE__" end
		return def[1]
	end
	function ENT:GetBoneParent(index)
		local def = boneDefs(self)[index + 1]
		if not def or not ready(self) then return -1 end
		return def[2]
	end
	function ENT:LookupBone(name)
		assert(type(name) == "string", "LookupBone: a bone name expected")
		for i, def in ipairs(boneDefs(self)) do
			if def[1] == name then return i - 1 end
		end
		return nil
	end
	function ENT:GetBoneMatrix(index)
		assert(type(index) == "number", "GetBoneMatrix: a bone index expected")
		local m = self.bones and self.bones[index]
		return m and M.copyMatrix(m) or nil
	end
	function ENT:SetBoneMatrix(index, m)
		assert(type(index) == "number" and getmetatable(m) == MAT, "SetBoneMatrix: (number, VMatrix) expected")
		assert(self.bones and self.bones[index], "SetBoneMatrix on an invalid bone: the game cannot even catch this error")
		assert(self.bonesFrame == M.frame, "SetBoneMatrix without SetupBones in the same frame: the engine throws it away")
		self.bones[index] = M.copyMatrix(m)
		self.boneWrites = (self.boneWrites or 0) + 1
	end

	function ENT:DrawModel()
		assert(not self.removed, "DrawModel on a removed entity")
		-- the engine sets the bones up itself when nobody did in this frame
		if boneDefs(self)[1] and self.bonesFrame ~= M.frame then M.engineSetup(self) end
		if M.blend <= 0 then -- render.SetBlend(0): nothing on the screen
			self.hiddenDraws = (self.hiddenDraws or 0) + 1
			return
		end
		self.draws = (self.draws or 0) + 1
		M.drawn[#M.drawn + 1] = self
		-- what is on the screen now: bone name -> matrix
		local shown = {}
		for i, def in ipairs(boneDefs(self)) do shown[def[1]] = M.copyMatrix(self.bones[i - 1]) end
		self.shown, self.shownAt = shown, self:GetPos()
	end
	M.drawn = {}
	M.blend = 1

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
	function render.GetBlend() return M.blend end
	function render.SetBlend(blend) M.blend = blend end

	-- one object per name, as in the game: what is set on it is set for everybody
	M.materialObjects = {}
	function Material(name, flags)
		local exists = M.materials[name] == true or M.files["materials/" .. name] == true
			or M.files["materials/" .. name .. ".vmt"] == true
		local mat = M.materialObjects[name]
		if not mat then
			mat = { name = name, vectors = {} }
			function mat:SetVector(key, value)
				assert(type(key) == "string" and isvector(value), "IMaterial:SetVector(name, Vector)")
				assert(not self:IsError(), "SetVector on the error material")
				self.vectors[key] = value
			end
			M.materialObjects[name] = mat
		end
		mat.IsError = function() return not exists end
		return mat
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
