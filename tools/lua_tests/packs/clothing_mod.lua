-- Make sure the Appearance Fix API exists no matter which addon loads first
if not (hg and hg.AppearanceFix and hg.AppearanceFix.AddModel) then
	include("autorun/sh_zcity_appearance_fix.lua")
end
local Fix = hg.AppearanceFix
local AppAddModel, AddFacemap, AppAddClothes, AppAddClothesDesc, AppAddBodygroup =
	Fix.AddModel, Fix.AddFacemap, Fix.AddClothes, Fix.AddClothesDesc, Fix.AddBodygroup

-- Content from zcity_clothing addon
-- Add new models from zcity_clothing addon
AppAddModel("Adodser Male 01", "models/zcityadodser/m/male_01.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 02", "models/zcityadodser/m/male_02.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 03", "models/zcityadodser/m/male_03.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 04", "models/zcityadodser/m/male_04.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 05", "models/zcityadodser/m/male_05.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 06", "models/zcityadodser/m/male_06.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 07", "models/zcityadodser/m/male_07.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 08", "models/zcityadodser/m/male_08.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Male 09", "models/zcityadodser/m/male_09.mdl", false, {
    main = "models/humans/male/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})

AppAddModel("Adodser Female 01", "models/zcityadodser/f/female_01.mdl", true, {
    main = "models/humans/female/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Female 02", "models/zcityadodser/f/female_02.mdl", true, {
    main = "models/humans/female/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Female 03", "models/zcityadodser/f/female_03.mdl", true, {
    main = "models/humans/female/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Female 04", "models/zcityadodser/f/female_04.mdl", true, {
    main = "models/humans/female/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Female 05", "models/zcityadodser/f/female_07.mdl", true, {
    main = "models/humans/female/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})
AppAddModel("Adodser Female 06", "models/zcityadodser/f/female_06.mdl", true, {
    main = "models/humans/female/group01/players_sheet",
    pants = "distac/gloves/pants",
    boots = "distac/gloves/cross",
    hands = "distac/gloves/hands"
})

-- Add new clothes from zcity_clothing
local maleClothes = {
    bomber_jacket1  = "models/humans/male/group01/bomberjacket1",
    camo_variant1   = "models/humans/male/group01/camo1",
    camo_variant2   = "models/humans/male/group01/camo2",
    pilot_jacket    = "models/humans/male/group01/pilotjacket",
    tactical_outfit = "models/humans/male/group01/tacticalgop",     
    hussar_jacket   = "models/humans/male/group01/hussar",
    Tshirt3  = "models/humans/male/group01/bersk",           
    leather_jacket  = "models/humans/male/group01/jacket",
    Tshirt1   = "models/humans/male/group01/promised",        
    Tshirt2    = "models/humans/male/group01/simon",
    alpha_bomber    = "models/humans/male/group01/alphaindustry",
    alpha_hoodie    = "models/humans/male/group01/alphahoodie",
    lonsdale_hoodie = "models/humans/male/group01/LondsdaleHoodie", 
    golden_adidas   = "models/humans/male/group01/goldenadidas",
    wagner_group    = "models/humans/male/group01/wagner",
    russian_army    = "models/humans/male/group01/russianarmy",
	Hello_Kitty    = "models/humans/male/group01/hello_kitty",
	Office_Worker    = "models/humans/male/group01/OfficeWorker",
	Security_Officer    = "models/humans/male/group01/Security_Officer",
	Zcity_Hoodie    = "models/humans/male/group01/zcityhoodie",
}
for k, v in pairs(maleClothes) do AppAddClothes(1, k, v) end

local femaleClothes = {
	adidas_tracksuit = "models/humans/female/group01/adidas",
	Tshirt1_f = "models/humans/female/group01/flowers",
}
for k, v in pairs(femaleClothes) do AppAddClothes(2, k, v) end

-- Male Facemaps for Adodser
local m01f = "models/humans/male/group01/van_facemap"
for i = 1, 8 do AddFacemap(m01f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/van_facemap" .. (i == 1 and "" or i)) end

local m02f = "models/humans/male/group01/ted_facemap"
for i = 1, 10 do AddFacemap(m02f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/ted_facemap" .. (i == 1 and "" or i)) end

local m03f = "models/humans/male/group01/joe_facemap"
for i = 1, 9 do AddFacemap(m03f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/joe_facemap" .. (i == 1 and "" or i)) end

local m04f = "models/humans/male/group01/eric_facemap"
for i = 1, 9 do AddFacemap(m04f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/eric_facemap" .. (i == 1 and "" or i)) end

local m05f = "models/humans/male/group01/art_facemap"
for i = 1, 9 do AddFacemap(m05f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/art_facemap" .. (i == 1 and "" or i)) end

local m06f = "models/humans/male/group01/sandro_facemap"
for i = 1, 10 do AddFacemap(m06f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/sandro_facemap" .. (i == 1 and "" or i)) end

local m07f = "models/humans/male/group01/mike_facemap"
for i = 1, 8 do AddFacemap(m07f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/mike_facemap" .. (i == 1 and "" or i)) end

local m08f = "models/humans/male/group01/vance_facemap"
for i = 1, 9 do AddFacemap(m08f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/vance_facemap" .. (i == 1 and "" or i)) end

local m09f = "models/humans/male/group01/erdim_cylmap"
for i = 1, 11 do AddFacemap(m09f, "Face " .. i, "models/bloo_ltcom_zel/citizens/facemaps/erdim_facemap" .. (i == 1 and "" or i)) end

-- Add Bodygroups from zcity_clothing
AppAddBodygroup("TORSO", "Standard Top", "male_standart_top.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "Wide Top", "male_standart_top_wide.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "Wide More Top", "male_standart_top_wide_more.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "T-Shirt", "male_standart_tshirt.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "Closed Collar", "male_standart_closed_collar.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("HANDS", "T-Shirt Hands", "handsfortshirt", false, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "Odessa Jacket", "male_odessa_jacket.smd", false, false, false, 0, nil, 0)

AppAddBodygroup("LEGS", "Standard Bottom", "male_reference_bottom.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("LEGS", "Wide Bottom", "male_reference_wide_bottom.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("LEGS", "Boots", "male_reference_boots.smd", false, false, false, 0, nil, 0)
AppAddBodygroup("LEGS", "Shorts", "male_reference_bottom_shorts.smd", false, false, false, 0, nil, 0)

AppAddBodygroup("TORSO", "Standard Top", "female_standart_top.smd", true, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "Wide Top", "female_standart_top_wide.smd", true, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "Wide More Top", "female_standart_top_wide_more.smd", true, false, false, 0, nil, 0)
AppAddBodygroup("TORSO", "Mossman Jacket", "female_mossman_jacket.smd", true, false, false, 0, nil, 0)

AppAddBodygroup("LEGS", "Standard Bottom", "female_reference_bottom.smd", true, false, false, 0, nil, 0)
AppAddBodygroup("LEGS", "Wide Bottom", "female_reference_wide_bottom.smd", true, false, false, 0, nil, 0)
AppAddBodygroup("LEGS", "Boots", "female_reference_boots.smd", true, false, false, 0, nil, 0)
