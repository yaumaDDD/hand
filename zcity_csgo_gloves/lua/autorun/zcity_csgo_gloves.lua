-- Z-City CS:GO Gloves
-- Adds 81 CS:GO gloves to the "Gloves" slot of the Z-City appearance editor.
-- https://github.com/yaumaDDD/hand

if SERVER then AddCSLuaFile() end

ZCGloves = ZCGloves or {}
ZCGloves.Version = "2.24.6"

local DIR = "zcity_csgo_gloves/"

-- One broken file must not take the rest of the addon down with it: what fell over is named in
-- ZCGloves.LoadErrors, in the console, and in the report the client sends to the server
-- (zcg_clients), so a client that lacks half of the addon says why by itself.
local function load(name, realm)
	if realm == "server" then
		if SERVER then
			local ok, err = pcall(include, DIR .. name)
			if not ok then
				ZCGloves.LoadErrors = ZCGloves.LoadErrors or {}
				ZCGloves.LoadErrors[#ZCGloves.LoadErrors + 1] = name .. ": " .. tostring(err)
				print("[CS:GO Gloves] " .. name .. " did not load: " .. tostring(err))
			end
		end
		return
	end
	if SERVER then AddCSLuaFile(DIR .. name) end
	if realm == "client" and SERVER then return end
	local ok, err = pcall(include, DIR .. name)
	if not ok then
		ZCGloves.LoadErrors = ZCGloves.LoadErrors or {}
		ZCGloves.LoadErrors[#ZCGloves.LoadErrors + 1] = name .. ": " .. tostring(err)
		print("[CS:GO Gloves] " .. name .. " did not load: " .. tostring(err))
	end
end

local function shared(name) load(name, "shared") end
local function client(name) load(name, "client") end
local function server(name) load(name, "server") end

-- (lua/autorun/!zcity_csgo_gloves.lua loads this one first, before the Lua of the clothing packs:
-- it is the API they call by name. Here it is loaded again for a build that has no "!" file - the
-- file itself can be run as often as anything likes.)
shared("sh_register.lua")
shared("sh_config.lua")
shared("sh_data.lua")
-- (the build writes this one when the addon carries the Lua of clothing packs: see sh_content.lua)
if file.Exists(DIR .. "sh_bound.lua", "LUA") then shared("sh_bound.lua") end
-- (sort_content.bat writes this one: the lines of the menu as data, which the addon puts into the
-- tables itself whatever order the Lua of the packs loads in - see sh_content.lua)
if file.Exists(DIR .. "sh_baked.lua", "LUA") then shared("sh_baked.lua") end
shared("sh_core.lua")
shared("sh_materials.lua")
shared("sh_content.lua")
-- (the faces of the two systems Z-City has, in every table the menus read: sh_faces.lua)
shared("sh_faces.lua")
-- (sort_content.bat writes this one when materials lie in the addon that no Lua names: see sh_auto.lua)
if file.Exists(DIR .. "sh_found.lua", "LUA") then shared("sh_found.lua") end
shared("sh_auto.lua")
-- (the build writes this one when the addon carries the table file of the other version of a pack: see sh_merge.lua)
if file.Exists(DIR .. "sh_merged.lua", "LUA") then
	shared("sh_merged.lua")
	if SERVER then
		for _, one in ipairs(ZCGloves.Merged or {}) do AddCSLuaFile(DIR .. one.file) end
	end
end
shared("sh_merge.lua")

-- Our own appearance system (own rails). The catalog is everything the addon has of the appearance
-- of Z-City - models, clothes, faces, bodygroups, accessories - written down as data of this addon
-- while it was built (tools/catalog.py). The code that follows dresses a player, keeps his look on
-- the server, draws his accessories and opens a menu of its own. None of it needs the Appearance
-- Mod: what the gamemode of Z-City calls by name is defined by this addon as well.
if file.Exists(DIR .. "own/sh_catalog.lua", "LUA") then shared("own/sh_catalog.lua") end
shared("own/sh_own.lua")
-- (the content of the addon no Lua names, found by walking its own materials/ and models/: a model
-- or a material somebody threw into the addon is offered by the menu of this addon as well)
shared("own/sh_scan.lua")

server("sv_core.lua")
server("own/sv_own.lua")
client("cl_render.lua")
client("cl_editor.lua")
client("own/cl_own_render.lua")
client("own/cl_own_files.lua")
client("own/cl_own_menu.lua")
