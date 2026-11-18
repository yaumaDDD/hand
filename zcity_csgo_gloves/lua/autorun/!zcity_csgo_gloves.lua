-- Z-City CS:GO Gloves - loaded first.
--
-- The "!" in the name is what makes the game read this file before the Lua of anything else:
-- lua/autorun is read in alphabetical order, and the clothing packs of Z-City lie there too
-- (sh_zcity_appearance_fix.lua, zc_balaclava.lua, zcity_drill_clothes.lua ...). A pack calls the
-- functions of the appearance by name - AppAddModel, AppAddClothes, AddFacemap, AppAddBodygroup -
-- and falls over when nothing provides them, so the API of this addon (zcity_csgo_gloves/
-- sh_register.lua) has to be there before the packs run, not after.
--
-- Everything else this addon does is loaded by lua/autorun/zcity_csgo_gloves.lua.

if SERVER then
	AddCSLuaFile()
	AddCSLuaFile("zcity_csgo_gloves/sh_register.lua")
end

ZCGloves = ZCGloves or {}

local ok, err = pcall(include, "zcity_csgo_gloves/sh_register.lua")
if not ok then
	ZCGloves.LoadErrors = ZCGloves.LoadErrors or {}
	ZCGloves.LoadErrors[#ZCGloves.LoadErrors + 1] = "sh_register.lua: " .. tostring(err)
	print("[CS:GO Gloves] sh_register.lua did not load: " .. tostring(err))
end
