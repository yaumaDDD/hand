-- Z-City CS:GO Gloves
-- Adds 81 CS:GO gloves to the "Gloves" slot of the Z-City appearance editor.
-- https://github.com/yaumaDDD/hand

if SERVER then AddCSLuaFile() end

ZCGloves = ZCGloves or {}
ZCGloves.Version = "2.17.0"

local DIR = "zcity_csgo_gloves/"

local function shared(name)
	if SERVER then AddCSLuaFile(DIR .. name) end
	include(DIR .. name)
end

local function client(name)
	if SERVER then
		AddCSLuaFile(DIR .. name)
	else
		include(DIR .. name)
	end
end

local function server(name)
	if SERVER then include(DIR .. name) end
end

shared("sh_config.lua")
shared("sh_data.lua")
-- (the build writes this one when the addon carries the Lua of clothing packs: see sh_content.lua)
if file.Exists(DIR .. "sh_bound.lua", "LUA") then shared("sh_bound.lua") end
shared("sh_core.lua")
shared("sh_materials.lua")
shared("sh_content.lua")
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
server("sv_core.lua")
client("cl_render.lua")
client("cl_editor.lua")
