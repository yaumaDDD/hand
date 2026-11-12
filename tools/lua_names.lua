-- Loads the Lua that fills the appearance tables of Z-City the way the game would, and tells
-- which models and materials those tables name afterwards.  (run by tools/lua_names.py)
--
-- This is no Garry's Mod. It is the least that lets such files run to their end:
--   * the files are run in the order the game and Z-City's lua/autorun/loader.lua run them
--     (autorun in name order; the loader includes lua/homigrad: files of a folder in name order
--     by their sv_ / sh_ / cl_ marks, then its folders), once as the server and once as a client.
--     The loader that does it is Z-City's own file when it was handed in, and a copy of what it
--     does (below) when not;
--   * hook, timer, include, file.Find (over the files that were handed in) and the helpers of
--     the game's table / string / math libraries really work; the hooks of start-up are called
--     and a minute of timers is let run;
--   * everything else of the game is a "stub": a value that can be called, indexed and
--     calculated with and gives another stub. A global nobody defined is nil, as in the game -
--     so `X = X or {}` makes a table - until some file calls or indexes it: then the files are
--     run again with that global as a stub (it is a part of the game that is not imitated here).
--     The same goes for the fields of hg, the table of Z-City: only its appearance files are
--     loaded here, the rest of the gamemode is not. hg itself is made by Z-City's loader and is
--     not there before: a file that runs earlier and reaches for it fails, here as in the game.
--
-- After every file, hook and timer the tables are read with ZCG.ContentWalk of the addon's own
-- sh_content.lua - the same walk the console command zcg_content does in the game - so what was
-- added, replaced or dropped is known by the file that did it.
--
-- returns function(spec) -> result
--   spec.files     { [path below lua/] = plain Lua (tools/glua.py, run=True) }
--   spec.content   the text of sh_content.lua of the addon
--   spec.realm     "server" or "client"
--   spec.skip      { [path] = true }: files that are there for the game but are not run here
--   spec.port      true: use the copy of Z-City's loader even when the file itself is there
--   spec.bare      true: as if no material and no model were installed (file.Exists and the
--                  like say no): what a file adds only when its content is there shows that way
--   spec.bound     the text of an sh_bound.lua the build made from an earlier run: at the end
--                  the addon's own check (ZCG.BoundMissing) compares the tables with it
--   result.entries { [entry] = { kind, path, who, by } }   what the tables hold at the end
--   result.bound   { count = , missing = { { entry, want, by, now }, ... } }   what that check said
--   result.lost    { { entry, kind, path, who, by, during, now }, ... }
--                  what a file had put there and another file replaced (now = the path it has
--                  now) or dropped (now = nil)
--   result.errors  { { file, message }, ... }   files, hooks and timers that did not run through
--   result.ran     { path, ... }   the files in the order they were run
--   result.stubs   { name, ... }   globals that were taken for parts of the game

local unpack = unpack or table.unpack

-- ------------------------------------------------------------------------------------------
-- stubs
-- ------------------------------------------------------------------------------------------
local STUB = {}
local function stub() return setmetatable({}, STUB) end
local function isStub(v) return type(v) == "table" and getmetatable(v) == STUB end

STUB.__index = function() return stub() end
STUB.__call = function() return stub() end
STUB.__concat = function(a, b)
	return (isStub(a) and "?" or tostring(a)) .. (isStub(b) and "?" or tostring(b))
end
STUB.__tostring = function() return "?" end
STUB.__lt = function() return false end
STUB.__le = function() return false end
STUB.__len = function() return 0 end
for _, name in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
	STUB[name] = function() return stub() end
end

-- a library of the game: what is written here works, the rest of it is stubs
local function library(known)
	return setmetatable(known or {}, { __index = function() return stub() end })
end

-- ------------------------------------------------------------------------------------------
-- one run
-- ------------------------------------------------------------------------------------------
-- fields of hg that the files run here make themselves: one that is missing when a file reaches
-- for it means that the file ran too early - an error here as in the game, nothing to imitate
local MADE_HERE = { Appearance = true, Accessories = true }

-- what the game's own Lua adds to the standard libraries, as far as files use it while loading
local function extendLibraries(env)
	local tbl = {}
	for k, v in pairs(table) do tbl[k] = v end
	function tbl.Copy(t, seen)
		if type(t) ~= "table" then return t end
		seen = seen or {}
		if seen[t] then return seen[t] end
		local copy = {}
		seen[t] = copy
		for k, v in pairs(t) do copy[k] = type(v) == "table" and not isStub(v) and tbl.Copy(v, seen) or v end
		return setmetatable(copy, getmetatable(t))
	end
	function tbl.Merge(dest, source)
		for k, v in pairs(source) do
			if type(v) == "table" and type(dest[k]) == "table" then tbl.Merge(dest[k], v) else dest[k] = v end
		end
		return dest
	end
	function tbl.Inherit(t, base)
		for k, v in pairs(base) do if t[k] == nil then t[k] = v end end
		t.BaseClass = base
		return t
	end
	function tbl.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	function tbl.IsEmpty(t) return next(t) == nil end
	function tbl.Empty(t) for k in pairs(t) do t[k] = nil end end
	function tbl.HasValue(t, value) for _, v in pairs(t) do if v == value then return true end end return false end
	function tbl.KeyFromValue(t, value) for k, v in pairs(t) do if v == value then return k end end end
	function tbl.GetKeys(t) local keys = {} for k in pairs(t) do keys[#keys + 1] = k end return keys end
	function tbl.Add(dest, source) for _, v in ipairs(source or {}) do dest[#dest + 1] = v end return dest end
	function tbl.ForceInsert(t, v) t = t or {} t[#t + 1] = v return t end
	function tbl.RemoveByValue(t, value)
		local key = tbl.KeyFromValue(t, value)
		if not key then return false end
		if type(key) == "number" then table.remove(t, key) else t[key] = nil end
		return key
	end
	function tbl.Reverse(t) local out = {} for i = #t, 1, -1 do out[#out + 1] = t[i] end return out end
	function tbl.ClearKeys(t) local out = {} for _, v in pairs(t) do out[#out + 1] = v end return out end
	function tbl.IsSequential(t) local i = 1 for _ in pairs(t) do if t[i] == nil then return false end i = i + 1 end return true end
	function tbl.Random(t)
		local keys = tbl.GetKeys(t)
		if #keys == 0 then return nil end
		local key = keys[math.random(#keys)]
		return t[key], key
	end
	function tbl.SortByMember(t, member, ascending)
		table.sort(t, function(a, b) if ascending then return a[member] < b[member] end return a[member] > b[member] end)
	end
	tbl.insert, tbl.remove, tbl.concat, tbl.sort = table.insert, table.remove, table.concat, table.sort
	env.table = library(tbl)

	local str = {}
	for k, v in pairs(string) do str[k] = v end
	function str.StartWith(s, start) return string.sub(s, 1, #start) == start end
	str.StartsWith = str.StartWith
	function str.EndsWith(s, tail) return tail == "" or string.sub(s, -#tail) == tail end
	function str.Left(s, n) return string.sub(s, 1, n) end
	function str.Right(s, n) return string.sub(s, -n) end
	function str.Trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
	function str.TrimLeft(s) return (string.gsub(s, "^%s+", "")) end
	function str.TrimRight(s) return (string.gsub(s, "%s+$", "")) end
	function str.Replace(s, find, with)
		find = string.gsub(find, "[%-%^%$%(%)%%%.%[%]%*%+%?]", "%%%0")
		with = string.gsub(with, "%%", "%%%%")
		return (string.gsub(s, find, with))
	end
	function str.Explode(separator, s)
		local out, from = {}, 1
		if separator == "" then
			for i = 1, #s do out[i] = string.sub(s, i, i) end
			return out
		end
		while true do
			local a, b = string.find(s, separator, from, true)
			if not a then break end
			out[#out + 1] = string.sub(s, from, a - 1)
			from = b + 1
		end
		out[#out + 1] = string.sub(s, from)
		return out
	end
	function str.Split(s, separator) return str.Explode(separator, s) end
	function str.Implode(separator, t) return table.concat(t, separator) end
	function str.ToTable(s) return str.Explode("", s) end
	function str.GetExtensionFromFilename(path) return string.match(path, "%.([^%./\\]+)$") end
	function str.StripExtension(path) return (string.gsub(path, "%.[^%./\\]+$", "")) end
	function str.GetFileFromFilename(path) return string.match(path, "[^/\\]+$") or path end
	function str.GetPathFromFilename(path) return string.match(path, "^(.*[/\\])[^/\\]*$") or "" end
	env.string = library(str)
	-- ("x"):StartWith(...): the methods of strings are the string library
	getmetatable("").__index = function(_, key) return env.string[key] end

	local m = {}
	for k, v in pairs(math) do m[k] = v end
	function m.Clamp(v, low, high) return math.min(math.max(v, low), high) end
	function m.Round(v, digits) local mult = 10 ^ (digits or 0) return math.floor(v * mult + 0.5) / mult end
	function m.Truncate(v, digits) local mult = 10 ^ (digits or 0) return (v < 0 and math.ceil or math.floor)(v * mult) / mult end
	function m.Rand(low, high) return low + (high - low) * math.random() end
	function m.Remap(v, a, b, c, d) return c + (d - c) * (v - a) / (b - a) end
	function m.Approach(v, target, step) if v < target then return math.min(v + step, target) end return math.max(v - step, target) end
	function m.Distance(x1, y1, x2, y2) return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) end
	env.math = library(m)

	env.os = library({ time = os.time, date = os.date, clock = os.clock, difftime = os.difftime })
	env.bit = bit
	env.jit = library({ version = "LuaJIT", os = "Windows", arch = "x64" })
	env.debug = library({ traceback = debug.traceback, getinfo = debug.getinfo })
	env.coroutine = coroutine
end

-- Z-City's loader tells by the name of a file where it runs: sv_x.lua and x_sv.lua on the server,
-- cl_ on the clients, sh_ and unmarked ones on both
local SIDES = { sv_ = "sv", sh_ = "sh", cl_ = "cl", _sv = "sv", _sh = "sh", _cl = "cl" }
local function sideOf(name)
	return SIDES[string.sub(name, 1, 3)] or SIDES[string.sub(name, -7, -5)]
end

local function run(spec)
	local server = spec.realm ~= "client"
	local installed = not spec.bare
	local files = {}
	for path, source in pairs(spec.files) do
		path = string.lower(path)
		-- A client only has the files the server sent it. Z-City's loader does not send its
		-- server files (and then, on a client, would try to include one it could see).
		local loaded = string.find(path, "^homigrad/") or string.find(path, "^initpost/")
		local hidden = not server and ((loaded and sideOf(string.match(path, "[^/]+$")) == "sv")
			or string.find(path, "^autorun/server/"))
		if not hidden then files[path] = source end
	end
	local skip = spec.skip or {}
	local errors, ran = {}, {}

	-- the globals of the game
	local env = {}
	env._G = env
	local healed = {}       -- globals that are parts of the game: stubs
	local healedHg = {}     -- fields of hg that are parts of Z-City: stubs
	local missing = nil     -- the next one of those, found by an error: { "global" or "hg", name }

	-- -------------------------------------------------------------------------------------
	-- the virtual lua/ folder
	-- -------------------------------------------------------------------------------------
	local dirs = {}         -- "homigrad/new_appearance" -> { files = { name = true }, dirs = { name = true } }
	local function folder(path)
		local entry = dirs[path]
		if not entry then
			entry = { files = {}, dirs = {} }
			dirs[path] = entry
			if path ~= "" then
				local parent, name = string.match(path, "^(.*)/([^/]+)$")
				if not parent then parent, name = "", path end
				folder(parent).dirs[name] = true
			end
		end
		return entry
	end
	folder("")
	for path in pairs(files) do
		local dir, name = string.match(path, "^(.*)/([^/]+)$")
		if not dir then dir, name = "", path end
		folder(dir).files[name] = true
	end

	local function sorted(set)
		local list = {}
		for name in pairs(set) do list[#list + 1] = name end
		table.sort(list)
		return list
	end

	-- file.Find("homigrad/*", "LUA"): the files and the folders, each in name order
	local function wildcard(pattern)
		pattern = string.gsub(pattern, "[%-%^%$%(%)%%%.%[%]%+%?]", "%%%0")
		return "^" .. string.gsub(pattern, "%*", ".*") .. "$"
	end
	local function findLua(pattern)
		pattern = string.lower(string.gsub(pattern, "\\", "/"))
		local dir, mask = string.match(pattern, "^(.*)/([^/]*)$")
		if not dir then dir, mask = "", pattern end
		local entry = dirs[dir]
		if not entry then return {}, {} end
		mask = wildcard(mask)
		local foundFiles, foundDirs = {}, {}
		for _, name in ipairs(sorted(entry.files)) do
			if string.find(name, mask) then foundFiles[#foundFiles + 1] = name end
		end
		for _, name in ipairs(sorted(entry.dirs)) do
			if string.find(name, mask) then foundDirs[#foundDirs + 1] = name end
		end
		return foundFiles, foundDirs
	end

	-- -------------------------------------------------------------------------------------
	-- running a piece of Lua: errors are kept, and one about a global that is not there stops
	-- the run - it starts again with that global as a part of the game
	-- -------------------------------------------------------------------------------------
	local current = "?"     -- the file whose code runs right now
	local snapshot          -- (defined below) reads the tables after a step

	local function fail(message)
		message = tostring(message)
		local name = string.match(message, "attempt to %a+ global '([%w_]+)' %(a nil value%)")
			or string.match(message, "attempt to perform arithmetic on global '([%w_]+)' %(a nil value%)")
			or string.match(message, "attempt to concatenate global '([%w_]+)' %(a nil value%)")
		local field = string.match(message, "attempt to %a+ field '([%w_]+)' %(a nil value%)")
		if missing == nil then
			if name == "hg" then
				-- (not a part of the game: Z-City's loader makes it, and this file ran before)
			elseif name and not healed[name] then
				missing = { "global", name }
			elseif field and not healedHg[field] and not MADE_HERE[field]
				and type(rawget(env, "hg")) == "table" and rawget(env.hg, field) == nil then
				missing = { "hg", field }
			end
		end
		errors[#errors + 1] = { file = current, message = (string.gsub(message, "\nstack traceback:.*$", "")) }
	end

	local function step(file, fn, ...)
		if missing then return end
		local before = current
		current = file
		local results = { xpcall(fn, function(message) return debug.traceback(tostring(message), 2) end, ...) }
		if not results[1] then fail(results[2]) end
		snapshot(file)
		current = before
		if results[1] then return unpack(results, 2) end
	end

	local function runFile(path)
		path = string.lower(path)
		local source = files[path]
		if source == nil or skip[path] then return end
		ran[#ran + 1] = path
		local chunk, err = loadstring(source, "@" .. path)
		if not chunk then
			errors[#errors + 1] = { file = path, message = tostring(err) }
			return
		end
		setfenv(chunk, env)
		return step(path, chunk)
	end

	-- include("x.lua"): beside the file that asks, or from lua/
	function env.include(path)
		if type(path) ~= "string" then return end
		path = string.lower(string.gsub(path, "\\", "/"))
		local beside = string.match(current, "^(.*)/[^/]+$")
		if beside and files[beside .. "/" .. path] ~= nil then return runFile(beside .. "/" .. path) end
		return runFile(path)
	end
	function env.AddCSLuaFile() end
	function env.IncludeCS(path) return env.include(path) end

	-- -------------------------------------------------------------------------------------
	-- hooks and timers
	-- -------------------------------------------------------------------------------------
	local hooks, hookOrder = {}, {}
	env.hook = library({
		Add = function(event, id, fn)
			if type(fn) ~= "function" or id == nil then return end
			if not hooks[event] then hooks[event], hookOrder[event] = {}, {} end
			if hooks[event][id] == nil then table.insert(hookOrder[event], id) end
			hooks[event][id] = { fn = fn, file = current }
		end,
		Remove = function(event, id)
			if hooks[event] then hooks[event][id] = nil end
		end,
		GetTable = function()
			local out = {}
			for event, list in pairs(hooks) do
				out[event] = {}
				for id, entry in pairs(list) do out[event][id] = entry.fn end
			end
			return out
		end,
	})
	local function runHook(event, ...)
		local result
		for _, id in ipairs(hookOrder[event] or {}) do
			local entry = hooks[event][id]
			if entry then
				local got = { step(entry.file, entry.fn, ...) }
				if result == nil and got[1] ~= nil then result = got end
			end
		end
		if result then return unpack(result) end
	end
	env.hook.Run = runHook
	env.hook.Call = function(event, _gamemode, ...) return runHook(event, ...) end

	local now = 0
	local timers, simple = {}, {}
	env.timer = library({
		Simple = function(delay, fn)
			if type(fn) == "function" then simple[#simple + 1] = { at = now + (tonumber(delay) or 0), fn = fn, file = current } end
		end,
		Create = function(id, delay, repetitions, fn)
			if type(fn) ~= "function" then return end
			delay = math.max(tonumber(delay) or 0, 0.01)
			timers[id] = { at = now + delay, delay = delay, left = tonumber(repetitions) or 0, fn = fn, file = current }
		end,
		Remove = function(id) timers[id] = nil end,
		Exists = function(id) return timers[id] ~= nil end,
		Adjust = function(id, delay, repetitions, fn)
			local entry = timers[id]
			if not entry then return false end
			entry.delay = math.max(tonumber(delay) or entry.delay, 0.01)
			if repetitions ~= nil then entry.left = tonumber(repetitions) or 0 end
			if type(fn) == "function" then entry.fn = fn end
			entry.at = now + entry.delay
			return true
		end,
		RepsLeft = function(id) return timers[id] and timers[id].left or 0 end,
		TimeLeft = function(id) return timers[id] and timers[id].at - now or 0 end,
	})
	env.timer.Destroy = env.timer.Remove

	-- lets the clock run: every timer that falls due is called, in the order of time
	local function wait(seconds, most)
		local stop, calls = now + seconds, 0
		while calls < most and not missing do
			local at, which, id = nil, nil, nil
			for index, entry in ipairs(simple) do
				if at == nil or entry.at < at then at, which, id = entry.at, "simple", index end
			end
			for name, entry in pairs(timers) do
				if at == nil or entry.at < at then at, which, id = entry.at, "timer", name end
			end
			if at == nil or at > stop then break end
			now = math.max(now, at)
			calls = calls + 1
			if which == "simple" then
				local entry = table.remove(simple, id)
				step(entry.file, entry.fn)
			else
				local entry = timers[id]
				if entry.left == 1 then
					timers[id] = nil
				else
					if entry.left > 1 then entry.left = entry.left - 1 end
					entry.at = now + entry.delay
				end
				step(entry.file, entry.fn)
			end
		end
		now = math.max(now, stop)
	end

	-- -------------------------------------------------------------------------------------
	-- the game, as far as loading files goes
	-- -------------------------------------------------------------------------------------
	extendLibraries(env)
	env.SERVER, env.CLIENT, env.MENU_DLL = server, not server, false
	for _, name in ipairs({ "pairs", "ipairs", "next", "type", "tostring", "tonumber", "select", "unpack", "pcall",
		"xpcall", "error", "assert", "rawget", "rawset", "rawequal", "setmetatable", "getmetatable", "setfenv",
		"getfenv", "loadstring", "newproxy", "collectgarbage" }) do
		env[name] = _G[name]
	end
	env.print, env.Msg, env.MsgN, env.MsgC, env.MsgAll = function() end, function() end, function() end, function() end, function() end
	env.ErrorNoHalt, env.ErrorNoHaltWithStack, env.PrintTable = function() end, function() end, function() end
	env.Error = function(...) error(table.concat({ ... }, ""), 2) end
	env.istable = function(v) return type(v) == "table" end
	env.isstring = function(v) return type(v) == "string" end
	env.isnumber = function(v) return type(v) == "number" end
	env.isfunction = function(v) return type(v) == "function" end
	env.isbool = function(v) return type(v) == "boolean" end
	env.isvector, env.isangle, env.isentity, env.ispanel, env.ismatrix = function() return false end, function() return false end,
		function() return false end, function() return false end, function() return false end
	env.IsColor = function(v) return type(v) == "table" and v.r ~= nil and v.g ~= nil and v.b ~= nil end
	env.IsValid = function() return false end
	env.tobool = function(v) return not (v == nil or v == false or v == 0 or v == "0" or v == "false") end
	env.Format = string.format
	env.CurTime, env.RealTime, env.SysTime, env.UnPredictedCurTime = function() return now end, function() return now end,
		function() return now end, function() return now end
	env.FrameTime, env.RealFrameTime, env.FrameNumber = function() return 0.015 end, function() return 0.015 end, function() return 1 end
	env.ScrW, env.ScrH = function() return 1920 end, function() return 1080 end
	env.Model, env.Sound = function(path) return path end, function(path) return path end
	env.Material, env.CreateMaterial = function() return stub() end, function() return stub() end
	local metatables = {}
	env.FindMetaTable = function(name)
		metatables[name] = metatables[name] or library({})
		return metatables[name]
	end
	env.Color = function(r, g, b, a)
		local color = stub()
		color.r, color.g, color.b, color.a = r or 255, g or 255, b or 255, a or 255
		return color
	end
	env.Vector = function(x, y, z)
		local v = stub()
		v.x, v.y, v.z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
		return v
	end
	env.Angle = function(p, y, r)
		local a = stub()
		a.p, a.y, a.r = tonumber(p) or 0, tonumber(y) or 0, tonumber(r) or 0
		return a
	end
	env.Lerp = function(t, a, b) return a + (b - a) * t end
	env.SortedPairs = function(t, descending)
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then a, b = tostring(a), tostring(b) end
			if descending then return a > b end
			return a < b
		end)
		local i = 0
		return function()
			i = i + 1
			if keys[i] ~= nil then return keys[i], t[keys[i]] end
		end
	end
	env.RandomPairs = env.SortedPairs

	-- console variables keep the value they were made with
	local convars = {}
	local function convar(name, default)
		local cv = convars[name]
		if not cv then
			local value = tostring(default == nil and "0" or default)
			cv = library({
				GetString = function() return value end,
				GetInt = function() return math.floor(tonumber(value) or 0) end,
				GetFloat = function() return tonumber(value) or 0 end,
				GetBool = function() return (tonumber(value) or 0) ~= 0 end,
				GetName = function() return name end,
				GetDefault = function() return value end,
			})
			convars[name] = cv
		end
		return cv
	end
	env.CreateConVar = function(name, default) return convar(name, default) end
	env.CreateClientConVar = env.CreateConVar
	env.GetConVar = function(name) return convar(name) end
	env.GetConVarNumber = function(name) return convar(name):GetFloat() end
	env.GetConVarString = function(name) return convar(name):GetString() end
	env.ConVarExists = function(name) return convars[name] ~= nil end

	local function isContent(path)
		path = string.lower(tostring(path))
		return string.find(path, "^materials/") ~= nil or string.find(path, "^models/") ~= nil or string.find(path, "^sound/") ~= nil
	end
	env.file = library({
		Find = function(pattern, where)
			if string.upper(tostring(where)) == "LUA" then return findLua(pattern) end
			return {}, {}
		end,
		-- (the files of the game are taken to be installed: a name is wanted whether or not its
		-- file is there yet)
		Exists = function(path, where)
			path = string.lower(string.gsub(tostring(path), "\\", "/"))
			if string.upper(tostring(where)) == "LUA" then return files[path] ~= nil or dirs[path] ~= nil end
			return installed and isContent(path)
		end,
		IsDir = function(path, where)
			if string.upper(tostring(where)) == "LUA" then return dirs[string.lower(tostring(path))] ~= nil end
			return false
		end,
		Read = function() return nil end,
		Write = function() end, Append = function() end, CreateDir = function() end, Delete = function() end,
		Time = function() return 0 end, Size = function() return 0 end,
	})
	env.util = library({
		AddNetworkString = function() end, PrecacheModel = function() end, PrecacheSound = function() end,
		IsValidModel = function() return installed end, IsValidProp = function() return installed end,
		IsValidRagdoll = function() return installed end,
		JSONToTable = function() return nil end, TableToJSON = function() return "{}" end,
		KeyValuesToTable = function() return {} end, CRC = function() return "0" end,
	})
	env.net = library({ Receive = function() end })
	env.concommand = library({ Add = function() end, Remove = function() end })
	env.cvars = library({ AddChangeCallback = function() end, RemoveChangeCallback = function() end,
		Number = function(_, default) return default or 0 end, String = function(_, default) return default or "" end,
		Bool = function(_, default) return default or false end })
	env.player = library({ GetAll = function() return {} end, GetHumans = function() return {} end, GetBots = function() return {} end,
		GetCount = function() return 0 end, Iterator = function() return function() end end })
	env.ents = library({ GetAll = function() return {} end, FindByClass = function() return {} end, GetCount = function() return 0 end,
		FindByModel = function() return {} end, FindInSphere = function() return {} end, Iterator = function() return function() end end })
	env.engine = library({ ActiveGamemode = function() return "zcity" end, TickInterval = function() return 0.015 end,
		GetAddons = function() return {} end, GetGames = function() return {} end })
	env.game = library({ SinglePlayer = function() return false end, IsDedicated = function() return server end,
		GetMap = function() return "gm_construct" end, MaxPlayers = function() return 32 end })
	env.system = library({ IsWindows = function() return true end, IsLinux = function() return false end, IsOSX = function() return false end })
	env.GetHostName = function() return "server" end
	for _, name in ipairs({ "surface", "draw", "render", "vgui", "derma", "input", "gui", "cam", "language", "resource", "team",
		"scripted_ents", "weapons", "list", "player_manager", "properties", "http", "sound", "effects", "killicon",
		"usermessage", "umsg", "sql", "cookie", "steamworks", "gameevent", "physenv", "navmesh", "duplicator", "undo",
		"cleanup", "constraint", "spawnmenu", "notification", "chat", "markup", "matproxy", "mesh", "halo", "baseclass",
		"drive", "gmod", "gamemode", "debugoverlay", "ai", "saverestore", "presets", "menubar", "dragndrop", "widgets",
		"search", "video", "frame_blend", "permissions", "achievements", "motionsensor", "controlpanel", "construct" }) do
		env[name] = library()
	end
	for index, name in ipairs({ "NODOCK", "FILL", "LEFT", "RIGHT", "TOP", "BOTTOM" }) do env[name] = index - 1 end

	-- Z-City's own table, as its loader makes it. What the files that are run put there is there;
	-- a field one of them calls or indexes without anybody having made it belongs to the rest of
	-- the gamemode and becomes a stub in the next run.
	local function newHg()
		return setmetatable({}, { __index = function(hg, name)
			if not healedHg[name] then return nil end
			local value = stub()
			rawset(hg, name, value)
			return value
		end })
	end

	setmetatable(env, {
		__index = function(_, name)
			if healed[name] then
				local value = stub()
				rawset(env, name, value)
				return value
			end
			-- the numbers of the game: FCVAR_ARCHIVE, TEXT_ALIGN_CENTER ...
			if type(name) == "string" and string.find(name, "^[A-Z][A-Z0-9]*_[A-Z0-9_]+$") then return 0 end
			return nil
		end,
	})
	for name in pairs(spec.stubs or {}) do healed[name] = true end
	for name in pairs(spec.hgStubs or {}) do healedHg[name] = true end

	-- -------------------------------------------------------------------------------------
	-- reading the tables: ZCG.ContentWalk of sh_content.lua, in a room of its own
	-- -------------------------------------------------------------------------------------
	local addon = { Print = function() end }
	local room
	do
		room = setmetatable({ ZCGloves = addon, SERVER = server, CLIENT = not server,
			concommand = library({ Add = function() end }), hook = library({ Add = function() end }),
			timer = library({ Simple = function() end }), file = library({ Exists = function() return false end }),
		}, {
			__index = function(_, name)
				if name == "hg" then return rawget(env, "hg") end
				local value = rawget(env, name)
				if value ~= nil then return value end
				return _G[name]
			end,
		})
		local chunk, err = loadstring(spec.content, "@sh_content.lua")
		if not chunk then error("sh_content.lua: " .. tostring(err)) end
		setfenv(chunk, room)
		chunk()
		if type(addon.ContentWalk) ~= "function" then error("sh_content.lua has no ZCG.ContentWalk") end
	end

	local entries = {}      -- entry -> { kind, path, who, by }
	local lost = {}
	local function clean(path)
		return string.lower((string.gsub(path, "\\", "/")))
	end
	function snapshot(file)
		local seen = {}
		local ok, err = pcall(addon.ContentWalk, function(kind, path, who, entry)
			if type(path) ~= "string" or path == "" or isStub(path) then return end
			path = clean(path)
			seen[entry] = true
			local had = entries[entry]
			if had == nil then
				entries[entry] = { kind = kind, path = path, who = who, by = file }
			elseif had.path ~= path then
				lost[#lost + 1] = { entry = entry, kind = had.kind, path = had.path, who = had.who, by = had.by, during = file, now = path }
				entries[entry] = { kind = kind, path = path, who = who, by = file }
			end
		end)
		if not ok then
			errors[#errors + 1] = { file = file, message = "the tables could not be read: " .. tostring(err) }
			return
		end
		for entry, had in pairs(entries) do
			if not seen[entry] then
				lost[#lost + 1] = { entry = entry, kind = had.kind, path = had.path, who = had.who, by = had.by, during = file }
				entries[entry] = nil
			end
		end
	end

	-- -------------------------------------------------------------------------------------
	-- the start of a game
	-- -------------------------------------------------------------------------------------
	-- Z-City's own appearance file was not handed in: the tables it makes, empty
	local function emptyTables()
		if files["homigrad/new_appearance/sh_shared.lua"] ~= nil then return end
		local hg = env.hg
		hg.Appearance = rawget(hg, "Appearance") or {}
		local AP = hg.Appearance
		AP.Clothes = AP.Clothes or { {}, {} }
		AP.ClothesDesc = AP.ClothesDesc or {}
		AP.PlayerModels = AP.PlayerModels or { {}, {} }
		AP.FacemapsSlots = AP.FacemapsSlots or {}
		AP.FacemapsModels = AP.FacemapsModels or {}
		AP.Bodygroups = AP.Bodygroups or {}
		hg.Accessories = rawget(hg, "Accessories") or {}
	end

	-- Z-City's lua/autorun/loader.lua, as far as the order of the files goes
	local function addFile(name, dir)
		local side = sideOf(name)
		if side == "sv" and not server then return end
		if side == "cl" and server then return end
		runFile(dir .. name)
	end
	local function includeDir(dir)
		local found, folders = findLua(dir .. "/*")
		for _, name in ipairs(found) do
			if string.sub(name, -4) == ".lua" then addFile(name, dir .. "/") end
		end
		for _, name in ipairs(folders) do includeDir(dir .. "/" .. name) end
	end
	local function loader()
		includeDir("homigrad")
		runHook("HomigradRun")
	end

	-- lua/autorun/*.lua, then autorun/server or autorun/client; Z-City's loader is one of them
	local LOADER = "autorun/loader.lua"
	local autorun = findLua("autorun/*.lua")
	local real = files[LOADER] ~= nil and not spec.port and not skip[LOADER]
	if files[LOADER] == nil then
		autorun[#autorun + 1] = "loader.lua"
		table.sort(autorun)
	end
	for _, name in ipairs(autorun) do
		if name == "loader.lua" then
			-- (the loader makes hg: `hg = hg or {}`. Here it gets one whose missing parts can
			-- be told from the outside.)
			if rawget(env, "hg") == nil then env.hg = newHg() end
			emptyTables()
			if real then
				runFile(LOADER)
			else
				ran[#ran + 1] = LOADER
				loader()
			end
		else
			runFile("autorun/" .. name)
		end
	end
	for _, name in ipairs((findLua("autorun/" .. (server and "server" or "client") .. "/*.lua"))) do
		runFile("autorun/" .. (server and "server" or "client") .. "/" .. name)
	end

	runHook("OnGamemodeLoaded")
	runHook("PostGamemodeLoaded")
	runHook("Initialize")
	if not real then includeDir("initpost") end     -- (the loader does that in its InitPostEntity hook)
	runHook("InitPostEntity")
	wait(60, 5000)

	-- the list of an earlier run, read the way the game reads it and checked by the addon itself
	local bound
	if spec.bound then
		local chunk, err = loadstring(spec.bound, "@sh_bound.lua")
		if not chunk then error("sh_bound.lua: " .. tostring(err)) end
		setfenv(chunk, room)
		chunk()
		local count, missing = addon.BoundMissing()
		bound = { count = count or -1, missing = missing or {} }
	end

	local stubs = {}
	for name in pairs(healed) do stubs[#stubs + 1] = name end
	for name in pairs(healedHg) do stubs[#stubs + 1] = "hg." .. name end
	table.sort(stubs)
	return { entries = entries, lost = lost, errors = errors, ran = ran, stubs = stubs, missing = missing, bound = bound }
end

-- runs until no file stumbles over a part of the game that is not there
return function(spec)
	local stubs, hgStubs = {}, {}
	local result
	for _ = 1, 400 do
		result = run({ files = spec.files, content = spec.content, realm = spec.realm, skip = spec.skip,
			port = spec.port, bare = spec.bare, bound = spec.bound, stubs = stubs, hgStubs = hgStubs })
		if not result.missing then break end
		if result.missing[1] == "hg" then hgStubs[result.missing[2]] = true else stubs[result.missing[2]] = true end
	end
	getmetatable("").__index = string   -- (the methods of strings were set for the run)
	return result
end
