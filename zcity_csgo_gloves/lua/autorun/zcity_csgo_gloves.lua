-- Z-City CS:GO Gloves
-- Adds 81 CS:GO gloves to the "Gloves" slot of the Z-City appearance editor.
-- https://github.com/yaumaDDD/hand

if SERVER then AddCSLuaFile() end

ZCGloves = ZCGloves or {}
ZCGloves.Version = "2.2.1"

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
shared("sh_core.lua")
shared("sh_materials.lua")
shared("sh_content.lua")
server("sv_core.lua")
client("cl_render.lua")
client("cl_editor.lua")
