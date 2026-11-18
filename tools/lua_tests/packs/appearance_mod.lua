-- Make sure the Appearance Fix API exists no matter which addon loads first
if not (hg and hg.AppearanceFix and hg.AppearanceFix.AddModel) then
	include("autorun/sh_zcity_appearance_fix.lua")
end
local Fix = hg.AppearanceFix
local AppAddModel, AddFacemap, AppAddClothes, AppAddClothesDesc, AppAddBodygroup =
	Fix.AddModel, Fix.AddFacemap, Fix.AddClothes, Fix.AddClothesDesc, Fix.AddBodygroup

-- Content from z_city_appearance_mod
-- Add new models
AppAddModel( "Male 10", "models/zcity/m/male_10.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male Cohrt", "models/zcity/m/cohrt.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male Cheaple", "models/zcity/m/cheaple.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male Eli", "models/zcity/m/eli.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male Barney", "models/zcity/m/barney.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male Bill", "models/zcity/m/bill.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male Travis", "models/zcity/m/travis.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male JohnWick", "models/zcity/m/johnwick.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Male Leet", "models/zcity/m/leet.mdl", false, {
	main = "models/humans/male/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Female Mossman", "models/zcity/f/mossman.mdl", true, {
	main = "models/humans/female/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Female Zoey", "models/zcity/f/zoey.mdl", true, {
	main = "models/humans/female/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel( "Female BlackMesa", "models/zcity/f/scientist_female.mdl", true, {
	main = "models/humans/female/group01/players_sheet", 
	pants = "distac/gloves/pants", 
	boots = "distac/gloves/cross", 
	hands = "distac/gloves/hands"
})

AppAddModel("Female Rochelle", "models/zcity/f/rochelle.mdl", true, {
	main = "models/humans/female/group01/players_sheet",
	pants = "distac/gloves/pants",
	boots = "distac/gloves/cross",
	hands = "distac/gloves/hands"
})

-- Add new clothes
local maleClothes = {
	femboy = "models/humans/modern/male/sheet_29",
    yellowjacket = "models/humans/modern/male/sheet_01",
    obh = "models/humans/modern/male/sheet_02",
    bebra = "models/humans/modern/male/sheet_04",
    bloody = "models/humans/modern/male/sheet_05",
    coolskeleton = "models/humans/modern/male/sheet_08",
    ftptop = "models/humans/modern/male/sheet_10",
    brownjacket = "models/humans/modern/male/sheet_12",
    doralover = "models/humans/modern/male/sheet_13",
    gosling = "models/humans/modern/male/sheet_14",
    dawnofthedead = "models/humans/modern/male/sheet_16",
    corkers = "models/humans/modern/male/sheet_17",
    blackjacket = "models/humans/modern/male/sheet_18",
    adidas = "models/humans/modern/male/sheet_19",
    fur = "models/humans/modern/male/sheet_20",
    leatherjacket = "models/humans/modern/male/sheet_21",
    micah = "models/humans/modern/male/sheet_22",
    whitejacket = "models/humans/modern/male/sheet_23",
    furblack = "models/humans/modern/male/sheet_24",
    greenjacket = "models/humans/modern/male/sheet_25",
    nike = "models/humans/modern/male/sheet_26",
    jeansjacket = "models/humans/modern/male/sheet_27",
    puffer = "models/humans/modern/male/sheet_28",
    stripedjacket = "models/humans/modern/male/sheet_30",
    blackhoodie1 = "models/humans/modern/male/sheet_31",
    adidassheet = "models/humans/slav/adidas_sheet",
	stoneisland = "models/humans/slav/sheet_si",
	shirtmale = "models/humans/slav/shirtmale",
}
for k, v in pairs(maleClothes) do AppAddClothes(1, k, v) end

local femaleClothes = {
	shirt1fem = "models/humans/modern/female/sheet_01",
    shirt2fem = "models/humans/modern/female/sheet_02",
    shirt3fem = "models/humans/modern/female/sheet_03",
    pastelcolortopfem = "models/humans/modern/female/sheet_04",
    coloredtopfem = "models/humans/modern/female/sheet_05",
    streetwearfem = "models/humans/modern/female/sheet_06",
    policefem = "models/humans/modern/female/sheet_07",
    bluejacketfem = "models/humans/modern/female/sheet_08",
    greentopfem = "models/humans/modern/female/sheet_09",
    playeboyfem = "models/humans/modern/female/sheet_10",
    kittytopfem = "models/humans/modern/female/sheet_11",
    redtopfem = "models/humans/modern/female/sheet_12",
    purpletopfem = "models/humans/modern/female/sheet_13",
    coatfem = "models/humans/modern/female/sheet_14",
    leatherjacketfem = "models/humans/modern/female/sheet_15",
	turtleneckfem = "models/roscoe/dogge1",
	formalshirtfem = "models/roscoe/dogge2",
	halloween3 = "models/humans/slav/octo/halloween3_sheet_women",
	halloween7 = "models/humans/slav/octo/halloween7_sheet_women",
	halloween8 = "models/humans/slav/octo/halloween8_sheet_women",
	halloween11 = "models/humans/slav/octo/halloween11_sheet_women",
	halloween13 = "models/humans/slav/octo/halloween13_sheet_women",
	halloween14 = "models/humans/slav/octo/halloween14_sheet_women",
	halloween15 = "models/humans/slav/octo/halloween15_sheet_women",
	halloween16 = "models/humans/slav/octo/halloween16_sheet_women",
	halloween17 = "models/humans/slav/octo/halloween17_sheet_women",
	halloween18 = "models/humans/slav/octo/halloween18_sheet_women",
	winter2 = "models/humans/slav/octo/winter2_sheet_woman",
	winter4 = "models/humans/slav/octo/winter4_sheet_woman",
	winter5 = "models/humans/slav/octo/winter5_sheet_woman",
	winter6 = "models/humans/slav/octo/winter6_sheet_woman",
	winter7 = "models/humans/slav/octo/winter7_sheet_woman",
	winter8 = "models/humans/slav/octo/winter8_sheet_woman",
	winter9 = "models/humans/slav/octo/winter9_sheet_woman",
	winter10 = "models/humans/slav/octo/winter10_sheet_woman",
	winter12 = "models/humans/slav/octo/winter12_sheet_woman",
	winter13 = "models/humans/slav/octo/winter13_sheet_woman",
	winter15 = "models/humans/slav/octo/winter15_sheet_woman",
	winter16 = "models/humans/slav/octo/winter16_sheet_woman",
	winter17 = "models/humans/slav/octo/winter17_sheet_woman",
}
for k, v in pairs(femaleClothes) do AppAddClothes(2, k, v) end

-- Add descriptions
local clothesDesc = {
	femboy = { desc = "from zcity content." },
    yellowjacket = { desc = "from zcity content." },
    obh = { desc = "from zcity content." },
    bebra = { desc = "from zcity content." },
    bloody = { desc = "from zcity content." },
    coolskeleton = { desc = "from zcity content." },
    ftptop = { desc = "from zcity content." },
    brownjacket = { desc = "from zcity content." },
    doralover = { desc = "from zcity content." },
    gosling = { desc = "from zcity content." },
    dawnofthedead = { desc = "from zcity content." },
    corkers = { desc = "from zcity content." },
    blackjacket = { desc = "from zcity content." },
    adidas = { desc = "from zcity content." },
    fur = { desc = "from zcity content." },
    leatherjacket = { desc = "from zcity content." },
    micah = { desc = "from zcity content." },
    whitejacket = { desc = "from zcity content." },
    furblack = { desc = "from zcity content." },
    greenjacket = { desc = "from zcity content." },
    nike = { desc = "from zcity content." },
    jeansjacket = { desc = "from zcity content." },
    puffer = { desc = "from zcity content." },
    stripedjacket = { desc = "from zcity content." },
    blackhoodie1 = { desc = "from zcity content." },
    shirt1fem = { desc = "from zcity content." },
    shirt2fem = { desc = "from zcity content." },
    shirt3fem = { desc = "from zcity content." },
    pastelcolortopfem = { desc = "from zcity content." },
    coloredtopfem = { desc = "from zcity content." },
    streetwearfem = { desc = "from zcity content." },
    policefem = { desc = "from zcity content." },
    bluejacketfem = { desc = "from zcity content." },
    greentopfem = { desc = "from zcity content." },
    playeboyfem = { desc = "from zcity content." },
    kittytopfem = { desc = "from zcity content." },
    redtopfem = { desc = "from zcity content." },
    purpletopfem = { desc = "from zcity content." },
    coatfem = { desc = "from zcity content." },
    leatherjacketfem = { desc = "from zcity content." },
    adidassheet = { desc = "adidas clothes from workshop" },
	stoneisland = { desc = "stone island clothes from dobrograd content" },
	turtleneckfem = { desc = "turtleneck clothes from dobrograd content" },
	formalshirtfem = { desc = "formal shirt clothes from dobrograd content" },
	halloween3 = { desc = "halloween clothes from dobrograd content" },
	halloween7 = { desc = "halloween clothes from dobrograd content" },
	halloween8 = { desc = "halloween clothes from dobrograd content" },
	halloween11 = { desc = "halloween clothes from dobrograd content" },
	halloween13 = { desc = "halloween clothes from dobrograd content" },
	halloween14 = { desc = "halloween clothes from dobrograd content" },
	halloween15 = { desc = "halloween clothes from dobrograd content" },
	halloween16 = { desc = "halloween clothes from dobrograd content" },
	halloween17 = { desc = "halloween clothes from dobrograd content" },
	halloween18 = { desc = "halloween clothes from dobrograd content" },
	winter2 = { desc = "winter clothes from dobrograd content" },
	winter4 = { desc = "winter clothes from dobrograd content" },
	winter5 = { desc = "winter clothes from dobrograd content" },
	winter6 = { desc = "winter clothes from dobrograd content" },
	winter7 = { desc = "winter clothes from dobrograd content" },
	winter8 = { desc = "winter clothes from dobrograd content" },
	winter9 = { desc = "winter clothes from dobrograd content" },
	winter10 = { desc = "winter clothes from dobrograd content" },
	winter12 = { desc = "winter clothes from dobrograd content" },
	winter13 = { desc = "winter clothes from dobrograd content" },
	winter15 = { desc = "winter clothes from dobrograd content" },
	winter16 = { desc = "winter clothes from dobrograd content" },
	winter17 = { desc = "winter clothes from dobrograd content" },
	shirtmale = { desc = "by flada" },
}
for k, v in pairs(clothesDesc) do AppAddClothesDesc(k, v) end

-- Add facemaps
AddFacemap("models/humans/female/group01/lakeetra_facemap","Face 1","models/bloo_ltcom_zel/citizens/facemaps/lakeetra_facemap")
for i = 2, 5 do
    AddFacemap("models/humans/female/group01/lakeetra_facemap","Face " .. i,"models/bloo_ltcom_zel/citizens/facemaps/lakeetra_facemap" .. i) 
end

AddFacemap("models/humans/female/group01/naomi_facemap","Face 7","models/bloo_ltcom_zel/citizens/facemaps/naomi_facemap_new")

local mossmanfacemap = "models/mossman/mossman_face"
local mossmanhair = "models/mossman/mossman_hair"
AddFacemap(mossmanfacemap,"Face 1","models/humans/slav/mossman/mossman_face")
AddFacemap(mossmanhair,"Face 1","models/humans/slav/mossman/mossman_hair")
AddFacemap(mossmanfacemap,"Face 2","models/humans/slav/mossman/mossman_goth_face")
AddFacemap(mossmanhair,"Face 2","models/humans/slav/mossman/mossman_goth_hair")

local zoeyfacemap = "models/humans/slav/zoey/zoey_head"
local zoeyhair = "models/humans/slav/zoey/zoey_hair"
AddFacemap(zoeyfacemap,"Face 1","models/humans/slav/zoey/zoey_head_freckles")
AddFacemap(zoeyhair,"Face 1","models/humans/slav/zoey/zoey_hair")
AddFacemap(zoeyfacemap,"Face 2","models/humans/slav/zoey/zoey_head_goth")
AddFacemap(zoeyhair,"Face 2","models/humans/slav/zoey/zoey_hair_dark")
AddFacemap(zoeyfacemap,"Face 3","models/humans/slav/zoey/zoey_head_light")
AddFacemap(zoeyhair,"Face 3","models/humans/slav/zoey/zoey_hair_dark")
AddFacemap(zoeyfacemap,"Face 4","models/humans/slav/zoey/zoey_head_makeup")
AddFacemap(zoeyhair,"Face 4","models/humans/slav/zoey/zoey_hair")
AddFacemap(zoeyfacemap,"Face 5","models/humans/slav/zoey/zoey_head_eyes")
AddFacemap(zoeyhair,"Face 5","models/humans/slav/zoey/zoey_hair")

local femalebmsfacemap = "models/humans/slav/blackmesa/base_female/base_f_d"
local femalebmshair = "models/humans/slav/blackmesa/hair_trans_blonde"
AddFacemap(femalebmsfacemap, "Face 1", "models/humans/slav/blackmesa/base_female/base_f_02_d")
AddFacemap(femalebmshair, "Face 1", "models/humans/slav/blackmesa/hair_trans_grey")
AddFacemap(femalebmsfacemap, "Face 2", "models/humans/slav/blackmesa/base_female/base_f_03_d")
AddFacemap(femalebmshair, "Face 2", "models/humans/slav/blackmesa/hair_trans_brown")
AddFacemap(femalebmsfacemap, "Face 3", "models/humans/slav/blackmesa/base_female/base_f_04_d")
AddFacemap(femalebmshair, "Face 3", "models/humans/slav/blackmesa/hair_trans_blonde2")
AddFacemap(femalebmsfacemap, "Face 4", "models/humans/slav/blackmesa/base_female/base_f_05_d")
AddFacemap(femalebmshair, "Face 4", "models/humans/slav/blackmesa/hair_trans_black")
AddFacemap(femalebmsfacemap, "Face 5", "models/humans/slav/blackmesa/base_female/base_f_06_d")
AddFacemap(femalebmshair, "Face 5", "models/humans/slav/blackmesa/hair_trans")
AddFacemap(femalebmsfacemap, "Face 6", "models/humans/slav/blackmesa/base_female/base_f_07_d")
AddFacemap(femalebmshair, "Face 6", "models/humans/slav/blackmesa/hair_trans_black")
AddFacemap(femalebmsfacemap, "Face Mia", "models/humans/slav/blackmesa/base_female/base_f_mia_d")
AddFacemap(femalebmshair, "Face Mia", "models/humans/slav/blackmesa/hair_trans_black")
AddFacemap(femalebmsfacemap, "Face Wendy", "models/humans/slav/blackmesa/base_female/base_f_wendy_d")
AddFacemap(femalebmshair, "Face Wendy", "models/humans/slav/blackmesa/hair_trans_grey2")
AddFacemap(femalebmsfacemap, "Face Edith", "models/humans/slav/blackmesa/base_female/base_f_edith_d")
AddFacemap(femalebmshair, "Face Edith", "models/humans/slav/blackmesa/hair_trans_red")

local rochellefacemap = "models/humans/slav/rochelletrs/trs_rochelle_head"
AddFacemap(rochellefacemap, "Face 1", "models/humans/slav/rochelletrs/trs_rochelle_head_1")
AddFacemap(rochellefacemap, "Face 2", "models/humans/slav/rochelletrs/trs_rochelle_head_2")
AddFacemap(rochellefacemap, "Face 3", "models/humans/slav/rochelletrs/trs_rochelle_head_3")
AddFacemap(rochellefacemap, "Face 4", "models/humans/slav/rochelletrs/trs_rochelle_head_4")
AddFacemap(rochellefacemap, "Face 5", "models/humans/slav/rochelletrs/trs_rochelle_head_5")

AddFacemap("models/humans/male/group01/ted_facemap","Face 11 (New)","models/humans/modern/male/male_02/facemap_01")
AddFacemap("models/humans/male/group01/joe_facemap","Face 10 (New)","models/humans/modern/male/male_03/facemap_03")
AddFacemap("models/humans/male/group01/joe_facemap","Face 11 (New)","models/humans/modern/male/male_03/facemap_04")
AddFacemap("models/humans/male/group01/joe_facemap","Face 12 (New)","models/humans/modern/male/male_03/facemap_06")
AddFacemap("models/humans/male/group01/eric_facemap","Face 10 (New)","models/humans/modern/male/male_04/facemap_01")
AddFacemap("models/humans/male/group01/eric_facemap","Face 11 (New)","models/humans/modern/male/male_04/facemap_02")
AddFacemap("models/humans/male/group01/eric_facemap","Face 12 (New)","models/humans/modern/male/male_04/facemap_03")
AddFacemap("models/humans/male/group01/eric_facemap","Face 13 (New)","models/humans/modern/male/male_04/facemap_04")
AddFacemap("models/humans/male/group01/eric_facemap","Face 14 (New)","models/characters/citizen/male/facemaps/eric_facemap")
AddFacemap("models/humans/male/group01/art_facemap","Face 10 (New)","models/humans/modern/male/male_05/facemap_05")
AddFacemap("models/humans/male/group01/art_facemap","Face 11 (New)","models/humans/slav/art/art_facemap1")
AddFacemap("models/humans/male/group01/art_facemap","Face 12 (New)","models/humans/slav/art/art_facemap2")
AddFacemap("models/humans/male/group01/art_facemap","Face 13 (New)","models/humans/slav/art/art_facemap3")
AddFacemap("models/humans/male/group01/art_facemap","Face 14 (New)","models/humans/slav/art/art_facemap4")
AddFacemap("models/humans/male/group01/sandro_facemap","Face 11 (New)","models/humans/modern/male/male_06/facemap_02")
AddFacemap("models/humans/male/group01/sandro_facemap","Face 12 (New)","models/humans/modern/male/male_06/facemap_03")
AddFacemap("models/humans/male/group01/sandro_facemap","Face 13 (New)","models/humans/modern/male/male_06/facemap_04")
AddFacemap("models/humans/male/group01/sandro_facemap","Face 14 (New)","models/humans/modern/male/male_06/facemap_05")
AddFacemap("models/humans/male/group01/sandro_facemap","Face 15 (New)","models/characters/citizen/male/facemaps/sandro_facemap6")
AddFacemap("models/humans/male/group01/sandro_facemap","Face 16 (New)","models/humans/slav/tanned_facemap")
AddFacemap("models/humans/male/group01/mike_facemap","Face 9 (New)","models/humans/modern/male/male_07/facemap_01")
AddFacemap("models/humans/male/group01/vance_facemap","Face 10 (New)","models/humans/modern/male/male_08/facemap_02")
AddFacemap("models/humans/male/group01/vance_facemap","Face 11 (New)","models/characters/citizen/male/facemaps/vance_facemap")
AddFacemap("models/humans/male/group01/erdim_cylmap","Face 12 (New)","models/humans/modern/male/male_09/facemap_01")
AddFacemap("models/humans/male/group01/erdim_cylmap","Face 13 (New)","models/humans/modern/male/male_09/facemap_02")
AddFacemap("models/humans/male/group01/erdim_cylmap","Face 14 (New)","models/humans/modern/male/male_09/facemap_04")
AddFacemap("models/humans/male/group01/erdim_cylmap","Face 15 (New)","models/characters/citizen/male/facemaps/erdim_facemap")

local male10facemap = "models/humans/male/group01/cub_facemap"
AddFacemap(male10facemap,"Face 1","models/humans/male/group02/cub_facemap")
AddFacemap(male10facemap,"Face 2","models/humans/male/group03/cub_facemap")
AddFacemap(male10facemap,"Face 3","models/humans/male/group03m/cub_facemap")

local cohrtfacemap = "models/humans/slav/cohrt/cohrt"
AddFacemap(cohrtfacemap, "Face 1", "models/humans/slav/cohrt/cohrt")

local cheaplefacemap = "models/gregrogers/warren/gregrogers_warren_facemap"
AddFacemap(cheaplefacemap, "Face 1", "models/gregrogers/warren/gregrogers_warren_facemap_g02")
AddFacemap(cheaplefacemap, "Face 2", "models/gregrogers/warren/gregrogers_warren_facemap_g03")
AddFacemap(cheaplefacemap, "Face 3", "models/gregrogers/warren/gregrogers_warren_facemap_g03m")

local elifacemap = "models/eli/eli_tex4z"
AddFacemap(elifacemap, "Face 1", "models/gang_ballas_boss/gang_ballas_boss_face")
AddFacemap(elifacemap, "Face 2", "models/humans/slav/eli/eli_headz")

local barneyfacemap = "models/humans/slav/barney/barneyface"
AddFacemap(barneyfacemap, "Face 1", "models/humans/slav/barney/donaldface")

local billcig = "models/humans/slav/bill/bill_head"
local billhairs = "models/humans/slav/bill/bill_hairs"
local billhairs2 = "models/humans/slav/bill/bill_hairs2"
local billbeard = "models/humans/slav/bill/bill_hair"
local billface = "models/humans/slav/bill/bill_head_nohat"

AddFacemap(billcig, "No Cig", "null")
AddFacemap(billhairs, "No Cig", "models/humans/slav/bill/bill_hairs")
AddFacemap(billhairs2, "No Cig", "models/humans/slav/bill/bill_hairs2")
AddFacemap(billbeard, "No Cig", "models/humans/slav/bill/bill_hair")
AddFacemap(billface, "No Cig", "models/humans/slav/bill/bill_head_nohat")

AddFacemap(billcig, "Young", "models/humans/slav/bill/bill_head")
AddFacemap(billhairs, "Young", "models/humans/slav/bill/bill_hairs_young")
AddFacemap(billhairs2, "Young", "models/humans/slav/bill/bill_hairs_young2")
AddFacemap(billbeard, "Young", "models/humans/slav/bill/bill_hair_young")
AddFacemap(billface, "Young", "models/humans/slav/bill/bill_head_young_nohat")

AddFacemap(billcig, "Young No Beard", "models/humans/slav/bill/bill_head")
AddFacemap(billhairs, "Young No Beard", "models/humans/slav/bill/bill_hairs_young")
AddFacemap(billhairs2, "Young No Beard", "models/humans/slav/bill/bill_hairs_young2")
AddFacemap(billbeard, "Young No Beard", "null")
AddFacemap(billface, "Young No Beard", "models/humans/slav/bill/bill_head_young_nohat")

AddFacemap(billcig, "Young No Cig", "null")
AddFacemap(billhairs, "Young No Cig", "models/humans/slav/bill/bill_hairs_young")
AddFacemap(billhairs2, "Young No Cig", "models/humans/slav/bill/bill_hairs_young2")
AddFacemap(billbeard, "Young No Cig", "models/humans/slav/bill/bill_hair_young")
AddFacemap(billface, "Young No Cig", "models/humans/slav/bill/bill_head_young_nohat")

AddFacemap(billcig, "Young No Beard No Cig", "null")
AddFacemap(billhairs, "Young No Beard No Cig", "models/humans/slav/bill/bill_hairs_young")
AddFacemap(billhairs2, "Young No Beard No Cig", "models/humans/slav/bill/bill_hairs_young2")
AddFacemap(billbeard, "Young No Beard No Cig", "null")
AddFacemap(billface, "Young No Beard No Cig", "models/humans/slav/bill/bill_head_young_nohat")

local travisfacemap = "models/humans/slav/travis/trav_facemap"
AddFacemap(travisfacemap, "Face 1", "models/humans/slav/travis/trav_facemap1")
AddFacemap(travisfacemap, "Face 2", "models/humans/slav/travis/trav_facemap2")

local leetfacemap = "models/cstrike/t_leet"
AddFacemap(leetfacemap, "Default", "","models/zcity/m/leet.mdl")
