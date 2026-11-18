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
	function SysTime() return M.time end
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
	VEC.__mul = function(a, b)
		assert(getmetatable(a) == VEC and type(b) == "number", "the imitation only multiplies Vector * number")
		return Vector(a.x * b, a.y * b, a.z * b)
	end
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
	function MAT:GetForward() return Vector(self[1], self[5], self[9]) end
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
	function MAT:GetInverse() -- nil when there is none, like the game
		local a, b, c, d, e, f, g, h, i = self[1], self[2], self[3], self[5], self[6], self[7], self[9], self[10], self[11]
		local det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
		if math.abs(det) < 1e-12 then return nil end
		local m = {
			(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det, 0,
			(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det, 0,
			(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det, 0,
		}
		for row = 0, 2 do
			m[row * 4 + 4] = -(m[row * 4 + 1] * self[4] + m[row * 4 + 2] * self[8] + m[row * 4 + 3] * self[12])
		end
		return matrix(m)
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
	-- "LUA": the scripts a test hands in, M.luafiles[path] = source; include() runs them. (The
	-- files of the addon under test are not listed there: a scenario gets no script it did not
	-- ask for, whichever folder the tests are pointed at.)
	M.luafiles = {}
	file = {}
	function file.Exists(path, where)
		if where == "LUA" then return M.luafiles[path] ~= nil end
		return M.files[path] == true
	end
	-- what was written into garrysmod/data: M.written[path] = text
	M.written = {}
	function file.IsDir(path, where)
		assert(type(path) == "string", "file.IsDir: path")
		local listed = M.files
		if where ~= nil and where ~= "GAME" then listed = M.pathFiles[where] or {} end
		for name in pairs(listed) do
			if name:sub(1, #path + 1) == path .. "/" then return true end
		end
		return false
	end
	function file.Write(path, text)
		assert(type(path) == "string" and type(text) == "string", "file.Write(path, text)")
		M.written[path] = text
	end

	-- Reading: M.filedata[path] = { [offset] = "bytes", ... } - what the file holds at some
	-- places, zero bytes everywhere else - or the whole file as one string. A path without an
	-- entry cannot be opened.
	M.filedata, M.opened, M.openNow = {}, 0, 0
	function file.Open(path, mode, where)
		assert(mode == "rb" and where == "GAME", "file.Open: only reading from GAME is imitated")
		local data = M.filedata[path]
		if not data then return nil end
		M.opened, M.openNow = M.opened + 1, M.openNow + 1
		local f = { pos = 0 }
		function f:Seek(pos) assert(not self.closed, "Seek on a closed file") self.pos = pos end
		function f:Size()
			assert(not self.closed, "Size of a closed file")
			assert(type(data) == "string", "the imitation only knows the size of a file given as a whole")
			return #data
		end
		function f:Read(count)
			assert(not self.closed, "Read on a closed file")
			assert(type(count) == "number" and count >= 0, "Read: a number of bytes expected")
			if type(data) == "string" then -- like the game: what is there, nothing past the end
				local out = data:sub(self.pos + 1, self.pos + count)
				self.pos = self.pos + #out
				return out
			end
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
		function f:ReadLong() -- 32 bits, little endian, signed; nil at the end of the file
			local bytes = self:Read(4)
			if #bytes < 4 then return nil end
			local a, b, c, d = bytes:byte(1, 4)
			local n = a + b * 256 + c * 65536 + d * 16777216
			if n >= 2147483648 then n = n - 4294967296 end
			return n
		end
		function f:Close()
			assert(not self.closed, "file closed twice")
			self.closed = true
			M.openNow = M.openNow - 1
		end
		return f
	end
	-- M.files is what the game has mounted ("GAME"). Another search path lists what the test put
	-- into M.pathFiles[name] = { path = true }; one the test did not name lists nothing.
	M.pathFiles = {}
	function file.Find(pattern, where)
		assert(type(pattern) == "string", "file.Find: a pattern")
		assert(pattern:sub(-2) == "/*" or pattern:match("^.*%*%.[%a%d]+$"),
			"file.Find: the imitation lists whole folders (dir/*), not one kind of file (dir/*.ext)")
		local dir = pattern:gsub("/%*$", "")
		local files, dirs, seen = {}, {}, {}
		local listed = M.files
		if where ~= nil and where ~= "GAME" then listed = M.pathFiles[where] or {} end
		M.finds = (M.finds or 0) + 1
		for path in pairs(listed) do
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
	function CompileFile(path)
		if M.luafiles[path] ~= nil then return (loadstring(M.luafiles[path], "@" .. path)) end
		return (loadfile(M.luaroot .. "/" .. path))
	end
	function include(path)
		M.included[#M.included + 1] = path
		local f
		if M.luafiles[path] ~= nil then
			f = assert(loadstring(M.luafiles[path], "@" .. path))
		else
			f = assert(loadfile(M.luaroot .. "/" .. path))
		end
		return f()
	end

	-- ------------------------------------------------------------------ hooks, timers, convars
	-- (order: the fourth argument of hook.Add, as a library with priorities takes it. M.hookOrder
	-- = false: a library that refuses such a call; "silent": one that drops the hook instead)
	-- (order: the fourth argument of hook.Add, as a library with priorities takes it: a number,
	-- lower runs earlier, none = 0; hooks of one order run as they were added. M.hookOrder =
	-- false: a library that refuses such a call; "silent": one that drops the hook instead)
	hook = { list = {}, order = {}, added = {}, count = 0 }
	function hook.Add(name, id, fn, order)
		if order ~= nil and M.hookOrder == false then error("bad argument #4 to 'Add'") end
		if order ~= nil and M.hookOrder == "silent" then return end
		hook.list[name] = hook.list[name] or {}
		hook.list[name][id] = fn
		hook.order[name] = hook.order[name] or {}
		hook.order[name][id] = order
		hook.added[name] = hook.added[name] or {}
		if not hook.added[name][id] then
			hook.count = hook.count + 1
			hook.added[name][id] = hook.count
		end
	end
	function hook.GetTable() return hook.list end
	function hook.Remove(name, id)
		if hook.list[name] then hook.list[name][id] = nil end
		if hook.order[name] then hook.order[name][id] = nil end
		if hook.added[name] then hook.added[name][id] = nil end
	end
	function hook.Run(name, ...)
		local fns = hook.list[name]
		if not fns then return nil end
		local ids = {}
		for id in pairs(fns) do ids[#ids + 1] = id end
		local order, added = hook.order[name] or {}, hook.added[name] or {}
		table.sort(ids, function(a, b)
			local oa, ob = tonumber(order[a]) or 0, tonumber(order[b]) or 0
			if oa ~= ob then return oa < ob end
			return (added[a] or 0) < (added[b] or 0)
		end)
		for _, id in ipairs(ids) do
			local fn = fns[id]
			if fn then
				local a, b, c = fn(...)
				if a ~= nil then return a, b, c end
			end
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
		-- (the tests of zcg_hide_bones were written when it alone decided: they run with
		-- zcg_whole_hands 0; what 1, the default, does has checks of its own)
		if name == "zcg_whole_hands" then
			M.wholeHandsDefault = default
			default = "0"
		end
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
	-- Like the game: the materials of the model in the order of their sub-material indices, each
	-- looked for in every folder the model names - and one that is found nowhere is LEFT OUT, so
	-- that everything after it moves up. (A model given by a plain list has all its materials.)
	function ENT:GetMaterials()
		local info = M.models[self.model]
		local out = {}
		if info and info.textures then
			for _, name in ipairs(info.textures.names) do
				for _, dir in ipairs(info.textures.dirs) do
					-- (the material system: lower case, forward slashes)
					local path = string.lower(dir .. "/" .. name):gsub("\\", "/"):gsub("/+", "/"):gsub("^/", "")
					if M.files["materials/" .. path .. ".vmt"] then
						out[#out + 1] = path
						break
					end
				end
			end
			return out
		end
		for i, name in ipairs(info and info.materials or {}) do out[i] = name end
		return out
	end
	M.entityMeta = ENT
	-- the player metatable of the game: the methods of an entity and the ones of a player on top
	local PLAYER = setmetatable({}, { __index = ENT })
	PLAYER.__index = PLAYER
	function FindMetaTable(name)
		if name == "Entity" then return ENT end
		if name == "Player" then return PLAYER end
		return nil
	end
	M.playerMeta = PLAYER
	-- (the index of an entity: its place in M.entities)
	function Entity(index) return M.entities[index] or NULL end
	function ENT:EntIndex()
		for index, ent in ipairs(M.entities) do
			if ent == self then return index end
		end
		return 0
	end

	-- the bytes of a model file that names these materials and folders (nothing else is in it)
	function M.mdlFile(names, dirs)
		local function long(n)
			if n < 0 then n = n + 4294967296 end
			return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
		end
		local header, entry = 408, 64
		local texturesAt = header
		local dirsAt = texturesAt + #names * entry
		local textAt = dirsAt + #dirs * 4
		local text, places = {}, {}
		local function put(str)
			places[#places + 1] = textAt
			text[#text + 1] = str .. "\0"
			textAt = textAt + #str + 1
		end
		for _, name in ipairs(names) do put(name) end
		for _, dir in ipairs(dirs) do put(dir) end

		local out = { "IDST", string.rep("\0", 200), long(#names), long(texturesAt), long(#dirs), long(dirsAt),
			string.rep("\0", header - 220) }
		for i = 1, #names do
			out[#out + 1] = long(places[i] - (texturesAt + (i - 1) * entry)) .. string.rep("\0", entry - 4)
		end
		for i = 1, #dirs do out[#out + 1] = long(places[#names + i]) end
		out[#out + 1] = table.concat(text)
		return table.concat(out)
	end

	-- a model whose file is there: its materials are found (or not) by the files of the test
	function M.installModel(path, names, dirs, bones)
		M.files[path] = true
		M.filedata[path] = M.mdlFile(names, dirs)
		M.models[path] = { bones = bones, textures = { names = names, dirs = dirs } }
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
	-- M.models[path].bodygroups = { { name, { submodel, ... } }, ... } (ids and values from 0)
	function ENT:GetBodyGroups()
		local out = {}
		local info = M.models[self.model]
		for i, group in ipairs(info and info.bodygroups or {}) do
			local submodels = {}
			for k, name in ipairs(group[2]) do submodels[k - 1] = name end
			out[i] = { id = i - 1, name = group[1], num = #group[2], submodels = submodels }
		end
		return out
	end
	-- (what has this entity as its parent; M.entities: every entity the imitation made)
	function ENT:GetChildren()
		local out = {}
		for _, other in ipairs(M.entities) do
			if other.parent == self and not other.removed then out[#out + 1] = other end
		end
		return out
	end
	function ENT:IsEffectActive(fx) return bit.band(self.effects or 0, fx) ~= 0 end
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
	-- (M.models[path].unnamed = { [bone name] = true }: a model that is still loading - the game
	-- has no name for such a bone yet)
	function ENT:GetBoneName(index)
		local def = boneDefs(self)[index + 1]
		if not def then return nil end
		if not ready(self) then return "__INVALIDBONE__" end
		local info = M.models[self.model]
		if info and info.unnamed and info.unnamed[def[1]] then return "__INVALIDBONE__" end
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
	function surface.SetMaterial(mat)
		assert(mat and mat.IsError, "SetMaterial: IMaterial expected")
		M.material = mat
	end
	function surface.DrawRect() end
	function surface.DrawOutlinedRect() end
	function surface.DrawLine() end
	M.rects = {}
	function surface.DrawTexturedRect(x, y, w, h)
		assert(type(x) == "number" and type(y) == "number" and type(w) == "number" and type(h) == "number",
			"DrawTexturedRect: numbers expected")
		M.rects[#M.rects + 1] = { mat = M.material, x = x, y = y, w = w, h = h }
	end
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
	function PANEL:DockMargin() end
	function PANEL:GetSize() return self.w or 0, self.h or 0 end
	function PANEL:GetName() return self.class end
	function PANEL:GetClassName() return self.class end
	function PANEL:LocalToScreen(x, y) return (self.x or 0) + (x or 0), (self.y or 0) + (y or 0) end
	function PANEL:SetVisible(visible) self.hidden = not visible end
	function PANEL:IsVisible() return not self.hidden end
	function PANEL:InvalidateLayout() self.layouts = (self.layouts or 0) + 1 end
	function PANEL:SetContentAlignment() end
	function PANEL:SetMouseInputEnabled() end
	function PANEL:MakePopup() end
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
		Panel = {}, DPanel = {}, DLabel = {},
		DFrame = {
			SetTitle = function(self, title) self.title = title end,
			Center = function(self) self.centered = true end,
			SetBackgroundBlur = function() end,
			SetDeleteOnClose = function() end,
			SetScreenLock = function() end,
			SetDraggable = function() end,
			ShowCloseButton = function() end,
			-- like the game: gone at once, then OnClose
			Close = function(self)
				self:Remove()
				if self.OnClose then self:OnClose() end
			end,
		},
		DGrid = {
			AddItem = function(self, item)
				assert(ispanel(item), "DGrid:AddItem: panel expected")
				item:SetParent(self)
				self.Items[#self.Items + 1] = item
			end,
			GetItems = function(self) return self.Items end,
			SetCols = function(self, n) self.cols = n end,
			SetColWide = function(self, n) self.colWide = n end,
			SetRowHeight = function(self, n) self.rowHeight = n end,
		},
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
			SetAnimated = function() end,
			SetCamPos = function() end,
			SetLookAt = function() end,
			SetFOV = function() end,
		},
		DVScrollBar = {
			SetHideButtons = function() end,
			SetScroll = function(self, value) self.scroll = value end,
			GetScroll = function(self) return self.scroll or 0 end,
		},
		DTextEntry = {
			SetValue = function(self, value) self.value = tostring(value) end,
			GetValue = function(self) return self.value or "" end,
			GetText = function(self) return self.value or "" end,
			SetText = function(self, value) self.value = tostring(value) end,
			SetPlaceholderText = function(self, text) self.placeholder = text end,
			SetEditable = function() end,
			SetUpdateOnType = function() end,
			SetFont = function(self, font) self.font = font end,
			OnChange = function() end,
			OnEnter = function() end,
		},
		DImage = {
			SetImage = function(self, path) self.image = path end,
			GetImage = function(self) return self.image end,
			SetKeepAspect = function() end,
			SetMaterial = function(self, material) self.material = material end,
		},
		DImageButton = {
			SetImage = function(self, path) self.image = path end,
			GetImage = function(self) return self.image end,
			DoClick = function() end,
		},
		DCheckBox = {
			SetValue = function(self, value) self.checked = value and true or false end,
			GetChecked = function(self) return self.checked and true or false end,
			SetText = function(self, text) self.text = text end,
			OnChange = function() end,
		},
		DNumSlider = {
			SetMin = function() end,
			SetMax = function() end,
			SetDecimals = function() end,
			SetValue = function(self, value) self.value = tonumber(value) or 0 end,
			GetValue = function(self) return self.value or 0 end,
			SetText = function(self, text) self.text = text end,
			OnValueChanged = function() end,
		},
		DComboBox = {
			AddChoice = function(self, value, data, select)
				self.Choices = self.Choices or {}
				self.ChoiceData = self.ChoiceData or {}
				self.Choices[#self.Choices + 1] = value
				self.ChoiceData[#self.ChoiceData + 1] = data
				if select then self.value = value end
			end,
			SetValue = function(self, value) self.value = value end,
			GetValue = function(self) return self.value end,
			GetSelected = function(self)
				for index, value in ipairs(self.Choices or {}) do
					if value == self.value then return value, (self.ChoiceData or {})[index] end
				end
				return nil
			end,
			GetOptionData = function(self, index) return (self.ChoiceData or {})[index] end,
			OptionCount = function(self) return #(self.Choices or {}) end,
			SetSortItems = function() end,
			Clear = function(self) self.Choices, self.ChoiceData, self.value = {}, {}, nil end,
			ChooseOption = function(self, _value, index)
				local value = (self.Choices or {})[index]
				self.value = value
				if self.OnSelect then self:OnSelect(index, value, (self.ChoiceData or {})[index]) end
			end,
			OnSelect = function() end,
		},
		DListView = {
			AddColumn = function(self, name)
				self.Columns = self.Columns or {}
				self.Columns[#self.Columns + 1] = name
				return self.Columns[#self.Columns]
			end,
			AddLine = function(self, ...)
				self.Lines = self.Lines or {}
				local line = setmetatable({ class = "DListViewLine", children = {} }, panelMeta)
				line.Columns = { ... }
				self.Lines[#self.Lines + 1] = line
				line:SetParent(self)
				return line
			end,
			GetLines = function(self) return self.Lines or {} end,
			GetSelected = function(self)
				local got = {}
				for _, line in ipairs(self.Lines or {}) do
					if line.selected then got[#got + 1] = line end
				end
				return got
			end,
			GetSelectedLine = function(self)
				for index, line in ipairs(self.Lines or {}) do
					if line.selected then return index, line end
				end
				return nil
			end,
			ClearSelection = function(self)
				for _, line in ipairs(self.Lines or {}) do line.selected = false end
			end,
			Clear = function(self) self.Lines = {} end,
			SetMultiSelect = function() end,
			SetHeaderHeight = function() end,
			SelectItem = function(self, line) if line then line.selected = true end end,
			RemoveLine = function(self, index) table.remove(self.Lines or {}, index) end,
			OnRowSelected = function() end,
			DoDoubleClick = function() end,
		},
		DColorMixer = {
			SetColor = function(self, color) self.color = color end,
			GetValue = function(self) return self.color or Color(255, 255, 255) end,
			SetAlphaBar = function() end,
			SetWangs = function() end,
			SetPalette = function() end,
			EnableAlpha = function() end,
			ValueChanged = function() end,
		},
		DHorizontalDivider = {
			SetLeft = function(self, panel) self.left = panel end,
			SetRight = function(self, panel) self.right = panel end,
			SetDividerWidth = function() end,
			SetLeftWidth = function() end,
			SetLeftMin = function() end,
			SetRightMin = function() end,
		},
	}
	M.builtin = builtin

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
		if class == "DGrid" then panel.Items = {} end
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
	function vgui.GetKeyboardFocus() return nil end

	FILL, LEFT, RIGHT, TOP, BOTTOM = 1, 2, 3, 4, 5
	NOTIFY_ERROR = 1
	M.notes = {}
	notification = { AddLegacy = function(text) M.notes[#M.notes + 1] = text end }
	function string.NiceName(name) return name end

	input = {}
	function input.IsMouseDown(code) return M.mouse[code] == true end
	function input.GetCursorPos() return M.cursor[1], M.cursor[2] end

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

	-- ----------------------------------------------------------------------------------
	-- the rest of the game the own appearance system (lua/zcity_csgo_gloves/own/) uses
	-- ----------------------------------------------------------------------------------
	TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2
	TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = 3, 4
	EF_BONEMERGE = EF_BONEMERGE or 4096
	RENDERGROUP_BOTH = RENDERGROUP_BOTH or 3

	function table.HasValue(list, value)
		for _, item in ipairs(list or {}) do
			if item == value then return true end
		end
		return false
	end
	function table.IsEmpty(list) return next(list or {}) == nil end
	function table.Copy(list)
		local got = {}
		for key, value in pairs(list or {}) do
			got[key] = type(value) == "table" and table.Copy(value) or value
		end
		return got
	end
	function table.Random(list)
		local keys = {}
		for key in pairs(list or {}) do keys[#keys + 1] = key end
		if #keys == 0 then return nil, nil end
		local key = keys[math.random(1, #keys)]
		return list[key], key
	end
	function ColorRand(alpha) return Color(math.random(0, 255), math.random(0, 255), math.random(0, 255),
		alpha and 255 or 255) end

	-- the utf8 library of the game: a Russian letter is two bytes, and one letter is one letter
	utf8 = utf8 or {}
	local function utf8each(text)
		return tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*")
	end
	function utf8.len(text)
		local count = 0
		for _ in utf8each(text) do count = count + 1 end
		return count
	end
	function utf8.GetChar(text, index)
		local at = 0
		for letter in utf8each(text) do
			at = at + 1
			if at == index then return letter end
		end
		return ""
	end
	function utf8.sub(text, from, to)
		local letters, out = {}, {}
		for letter in utf8each(text) do letters[#letters + 1] = letter end
		from = from or 1
		if from < 0 then from = math.max(1, #letters + from + 1) end
		to = to or #letters
		if to < 0 then to = #letters + to + 1 end
		for index = from, math.min(to, #letters) do out[#out + 1] = letters[index] end
		return table.concat(out)
	end

	function LocalToWorld(pos, ang, origin, base)
		-- good enough for the tests: the offset turned by the angle of the bone and moved
		local rad = math.rad((base or Angle(0, 0, 0)).y or 0)
		local x = (pos or vector_origin).x * math.cos(rad) - (pos or vector_origin).y * math.sin(rad)
		local y = (pos or vector_origin).x * math.sin(rad) + (pos or vector_origin).y * math.cos(rad)
		return Vector((origin or vector_origin).x + x, (origin or vector_origin).y + y,
			(origin or vector_origin).z + (pos or vector_origin).z),
			Angle(((base or angle_zero).p or 0) + (ang or angle_zero).p or 0,
				((base or angle_zero).y or 0) + (ang or angle_zero).y or 0,
				((base or angle_zero).r or 0) + (ang or angle_zero).r or 0)
	end
	function GetViewEntity() return M.viewentity or LocalPlayer() end
	M.globals = {}
	function SetGlobalBool(name, value) M.globals[name] = value and true or false end
	function GetGlobalBool(name, default)
		if M.globals[name] == nil then return default and true or false end
		return M.globals[name]
	end
	function SetGlobalString(name, value) M.globals[name] = tostring(value) end
	function GetGlobalString(name, default) return tostring(M.globals[name] or default or "") end

	chat = {}
	M.chat = {}
	function chat.AddText(...)
		local line = {}
		for _, part in ipairs({ ... }) do
			line[#line + 1] = type(part) == "table" and "" or tostring(part)
		end
		M.chat[#M.chat + 1] = table.concat(line)
	end

	file.directories = file.directories or {}
	function file.CreateDir(path)
		assert(type(path) == "string", "file.CreateDir: path")
		file.directories[path] = true
		M.pathFiles.DATA = M.pathFiles.DATA or {}
	end
	function file.Delete(path)
		assert(type(path) == "string", "file.Delete: path")
		local was = M.written[path] ~= nil or (M.pathFiles.DATA or {})[path] == true
		M.written[path] = nil
		if M.pathFiles.DATA then M.pathFiles.DATA[path] = nil end
		return was
	end
	-- data/ is what the addon wrote itself (M.written) plus what the test put there; LUA is what
	-- the test handed in plus the Lua of the addon on disk (the game finds both)
	local existsBefore = file.Exists
	function file.Exists(path, where)
		if where == "DATA" then
			return M.written[path] ~= nil or (M.pathFiles.DATA or {})[path] == true
		end
		if where == "LUA" then
			if M.luafiles[path] ~= nil then return true end
			local handle = io.open(tostring(M.luaroot or "") .. "/" .. path, "rb")
			if handle then
				handle:close()
				return true
			end
			return false
		end
		return existsBefore(path, where)
	end
	function file.Read(path, where)
		if where == "DATA" and M.written[path] ~= nil then return M.written[path] end
		local data = M.filedata[path]
		if type(data) == "string" then return data end
		return nil
	end
	vector_origin = Vector(0, 0, 0)
	angle_zero = Angle(0, 0, 0)

	function PANEL:Clear()
		for index = #self.children, 1, -1 do
			self.children[index]:Remove()
		end
		self.children = {}
	end
	builtin.DScrollPanel.Clear = function(self)
		if self.canvas then self.canvas:Clear() end
	end

	-- the network of the game: a message is written, then M.netSend hands it to whoever receives it
	net = {}
	M.network = {}
	M.netMessages = {}
	function util.AddNetworkString(name)
		assert(type(name) == "string", "AddNetworkString: name")
		M.network[name] = M.network[name] or {}
	end
	local writing = nil
	function net.Start(name)
		assert(type(name) == "string", "net.Start: name")
		writing = { name = name, data = {}, to = nil, server = false }
		M.netMessages[#M.netMessages + 1] = writing
	end
	function net.WriteString(value)
		assert(writing and type(value) == "string", "net.WriteString: a string inside net.Start")
		writing.data[#writing.data + 1] = value
	end
	function net.WriteBool(value)
		assert(writing, "net.WriteBool: inside net.Start")
		writing.data[#writing.data + 1] = value and true or false
	end
	function net.WriteInt(value)
		assert(writing and type(value) == "number", "net.WriteInt: a number inside net.Start")
		writing.data[#writing.data + 1] = value
	end
	function net.WriteFloat(value)
		assert(writing and type(value) == "number", "net.WriteFloat: a number inside net.Start")
		writing.data[#writing.data + 1] = value
	end
	function net.WriteEntity(value)
		assert(writing, "net.WriteEntity: inside net.Start")
		writing.data[#writing.data + 1] = value
	end
	function net.WriteTable(value)
		assert(writing and type(value) == "table", "net.WriteTable: a table inside net.Start")
		writing.data[#writing.data + 1] = table.Copy(value)
	end
	function net.WriteVector(value)
		assert(writing, "net.WriteVector: inside net.Start")
		writing.data[#writing.data + 1] = value
	end
	function net.WriteColor(value)
		assert(writing, "net.WriteColor: inside net.Start")
		writing.data[#writing.data + 1] = value
	end
	function net.Send(target)
		assert(writing, "net.Send: inside net.Start")
		writing.to = target
		writing = nil
	end
	function net.SendToServer()
		assert(writing, "net.SendToServer: inside net.Start")
		writing.server = true
		writing = nil
	end
	function net.Broadcast()
		assert(writing, "net.Broadcast: inside net.Start")
		writing.to = "all"
		writing = nil
	end
	M.netReceivers = {}
	function net.Receive(name, fn)
		assert(type(name) == "string" and type(fn) == "function", "net.Receive(name, fn)")
		M.netReceivers[name] = fn
	end
	--- the messages that were sent, one after another, to their receivers (a test runs this)
	function M.netFlush(toServer)
		local sent = M.netMessages
		M.netMessages = {}
		local got = 0
		local wanted = toServer and true or false
		for _, message in ipairs(sent) do
			if (message.server and true or false) == wanted then
				local fn = M.netReceivers[message.name]
				if fn then
					M.netData = message.data
					M.netAt = 0
					M.netFrom = message.to
					fn(#message.name * 8, message.server and (M.localplayer or NULL) or (M.localplayer or NULL))
					got = got + 1
				end
			end
		end
		return got
	end
	M.netData, M.netAt = {}, 0
	local function readNext(what)
		M.netAt = M.netAt + 1
		local value = M.netData[M.netAt]
		assert(value ~= nil or what == "optional", "net.Read: the message has no value #" .. tostring(M.netAt))
		return value
	end
	function net.ReadString() return tostring(readNext() or "") end
	function net.ReadBool() return readNext() and true or false end
	function net.ReadInt() return tonumber(readNext()) or 0 end
	function net.ReadFloat() return tonumber(readNext()) or 0 end
	function net.ReadTable() return readNext() or {} end
	function net.ReadEntity() return readNext() or NULL end
	function net.ReadVector() return readNext() or vector_origin end
	function net.ReadColor() return readNext() or Color(255, 255, 255) end

	util.TableToJSON = util.TableToJSON or function(value)
		-- enough of JSON for the tests: strings, numbers, booleans and tables of them
		local function of(item)
			local kind = type(item)
			if kind == "string" then return '"' .. item:gsub('"', '\\"') .. '"' end
			if kind == "number" or kind == "boolean" then return tostring(item) end
			if kind ~= "table" then return "null" end
			local array, parts = true, {}
			for index = 1, #item do parts[#parts + 1] = of(item[index]) end
			for key in pairs(item) do
				if type(key) ~= "number" or key < 1 or key > #item then array = false end
			end
			if array then return "[" .. table.concat(parts, ",") .. "]" end
			parts = {}
			for key, value in pairs(item) do parts[#parts + 1] = '"' .. tostring(key) .. '":' .. of(value) end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return of(value)
	end
	util.JSONToTable = util.JSONToTable or function(text)
		local pos = 1
		local function skip()
			pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
		end
		local function value()
			skip()
			local char = text:sub(pos, pos)
			if char == "{" or char == "[" then
				local open, close = char, (char == "{" and "}" or "]")
				local got, index = (char == "{" and {} or {}), 1
				pos = pos + 1
				skip()
				if text:sub(pos, pos) == close then pos = pos + 1 return got end
				while true do
					local key
					if char == "{" then
						skip()
						key = value()
						skip()
						pos = pos + 1      -- the ":"
					end
					local item = value()
					if key ~= nil then got[key] = item else got[index] = item index = index + 1 end
					skip()
					local next_char = text:sub(pos, pos)
					pos = pos + 1
					if next_char ~= "," then break end
				end
				return got
			end
			if char == '"' then
				local rest = text:sub(pos + 1)
				local got = rest:match('^([^"]*)')
				pos = pos + 1 + #got + 1
				return (got:gsub('\\"', '"'))
			end
			if text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
			if text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
			if text:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil end
			local number = text:sub(pos):match("^[-%d.eE+]+")
			pos = pos + #(number or "")
			return tonumber(number)
		end
		local ok, got = pcall(value)
		if not ok then return nil end
		return got
	end

	-- the entity of a player: what the own appearance system asks of it
	function ENT:SetColor(color) self.color = color end
	function ENT:GetColor() return self.color or Color(255, 255, 255) end
	function ENT:SetPlayerColor(vector) self.playerColor = vector end
	function ENT:GetPlayerColor() return self.playerColor or Vector(1, 1, 1) end
	function ENT:SetNWVector(key, value) self.nwvectors = self.nwvectors or {} self.nwvectors[key] = value end
	function ENT:GetNWVector(key, default) return (self.nwvectors or {})[key] or default or vector_origin end
	function ENT:SetNWInt(key, value) self.nwints = self.nwints or {} self.nwints[key] = value end
	function ENT:GetNWInt(key, default) return (self.nwints or {})[key] or default or 0 end
	function ENT:SetNWBool(key, value) self.nwbools = self.nwbools or {} self.nwbools[key] = value and true or false end
	function ENT:GetNWBool(key, default)
		local got = (self.nwbools or {})[key]
		if got == nil then return default and true or false end
		return got
	end
	function ENT:SetNetVar(key, value)
		self.netvars = self.netvars or {}
		self.netvars[key] = value
		if SERVER and self.isplayer then M.replicated = (M.replicated or 0) + 1 end
	end
	function ENT:GetNetVar(key, default)
		local got = (self.netvars or {})[key]
		if got == nil then return default end
		return got
	end
	function ENT:CallOnRemove(id, fn) self.removers = self.removers or {} self.removers[id] = fn end
	function ENT:SetBodyGroups(value)
		assert(type(value) == "string", "SetBodyGroups: the game takes a string of digits")
		self.bodygroups = {}
		for index = 1, #value do
			self.bodygroups[index - 1] = tonumber(value:sub(index, index)) or 0
		end
	end
	function ENT:GetSubModels() return self.submodels end
	function ENT:SetModelScale(scale) self.modelScale = scale end
	function ENT:GetModelScale() return self.modelScale or 1 end
	function ENT:SetSkin(skin) self.skin = skin end
	function ENT:GetSkin() return self.skin or 0 end
	function ENT:SetRenderOrigin(pos) self.renderOrigin = pos end
	function ENT:SetRenderAngles(ang) self.renderAngles = ang end
	function ENT:GetManipulateBoneScale(_bone) return self.boneScale or Vector(1, 1, 1) end
	function ENT:GetFlexIDByName(_name) return nil end
	function ENT:SetFlexWeight() end
	function ENT:GetActiveWeapon() return self.weapon or NULL end
	function ENT:IsBot() return self.bot and true or false end
	-- a player is an admin / a super admin as the gamemode says (the imitation takes the fields
	-- the tests set: admin, superadmin, usergroup)
	function ENT:IsAdmin() return self.admin == true or self.superadmin == true
		or self.usergroup == "admin" or self.usergroup == "superadmin" end
	function ENT:GetUserGroup() return self.usergroup or (self.superadmin and "superadmin" or "user") end
	function ENT:SetUserGroup(name) self.usergroup = name end
	function ENT:SteamID() return self.steamid or "STEAM_0:0:0" end
	function ENT:SteamID64() return self.steamid64 or "0" end
	function ENT:ChatPrint(text)
		assert(type(text) == "string", "ChatPrint: text")
		M.chat[#M.chat + 1] = text
	end

	local oldSetSubMaterial = ENT.SetSubMaterial
	function ENT:SetSubMaterial(index, material)
		if index == nil then
			-- the game resets every slot of the model: SetSubMaterial() with nothing
			self.submaterials = {}
			return
		end
		return oldSetSubMaterial(self, index, material)
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
