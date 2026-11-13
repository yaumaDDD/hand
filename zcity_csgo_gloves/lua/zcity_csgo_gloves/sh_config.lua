-- Z-City CS:GO gloves - settings for the server owner.
-- Console variables (zcg_any_model, zcg_hide_hands, zcg_fingers, zcg_enable) are described in the README.

ZCGloves.Config = {
	-- Steam Workshop ID (as a string) of the built addon if you uploaded it to the Workshop:
	-- joining players then download the models and textures automatically.
	-- Leave it nil when players install the addon by hand or get it through FastDL.
	WorkshopID = nil,

	-- true: send every model / material / icon of the addon through FastDL (resource.AddSingleFile).
	-- The content is about 270 MB - prefer the Workshop.
	FastDL = false,

	-- true: the server precaches the 12 glove models, so clients load them while joining
	-- instead of freezing for a moment when a glove is seen for the first time.
	PrecacheModels = true,

	-- how often (seconds) the server checks which glove every player wears
	PollInterval = 0.3,

	-- A glove hides the hands of the player model. Under a full-finger glove (moto, hardknuckle,
	-- leather, driver, specialist, sport) the skin would poke through; a fingerless glove brings fingers of its own: they
	-- are part of the glove models and fit them exactly, which the fingers of a player model
	-- do not.
	-- Set a family to false to keep the wearer's own hands under it (a fingerless glove is then
	-- drawn without its fingers, as up to version 1.0.1):
	--   HideHands = { handwrap = false }
	-- Families: bloodhound, brokenfang, hydra, handwrap, fingerless, moto, hardknuckle, leather,
	-- driver, specialist, sport.
	-- (zcg_hide_hands 0 does this for every glove, zcg_fingers 0 for all fingerless ones.)
	HideHands = {},

	-- skin of the fingers inside the fingerless glove models (a material name; false = the
	-- same as zcg_fingers 0)
	FingerMaterial = "zcity_csgo_gloves/skin/fingers",

	-- Colour that skin is multiplied with, to bring it closer to the skin of your player models:
	-- Vector(1, 1, 1) changes nothing, Vector(0.8, 0.8, 0.8) is darker, Vector(1.15, 1.05, 1) is
	-- lighter and warmer. Find the numbers in game with the console command
	-- "zcg_finger_tint 1.15 1.05 1" (it only changes your own screen) and write them down here.
	FingerTint = nil,

	-- material used to hide things (the wearer's own hands under a glove and what is left of the
	-- bare arm inside the glove models). nil = "null" if the game has it, otherwise the material
	-- shipped with this addon.
	HideMaterial = nil,

	-- The game leaves materials whose files are missing out of Entity:GetMaterials(), and Z-City
	-- finds the place of the jacket, the trousers, the boots and the hands by counting in that
	-- list: one material of a player model that is not installed, and all the clothes sit on the
	-- wrong parts. true: the list is completed from the model file, so the clothes stay where they
	-- belong (the part whose material is missing is still purple and black). false: the list of
	-- the game as it is.
	CompleteMaterialList = true,

	-- The cuff of a CS:GO glove under the sleeve of a jacket, jacket by jacket. The key is the name
	-- of the jacket part the model shows (body group "sheet" / "TORSO"), as the console command
	-- "zcg_cuff" prints it; the numbers are { thickness, length, shift }:
	--   thickness  around the forearm, 1 = as the glove was made, 0.8 = thinner
	--   length     of the cuff from the wrist up the arm, 1 = as made, 0.7 = shorter
	--   shift      of the cuff along the arm in units, + towards the elbow, - towards the fingers
	-- A jacket that is not listed leaves the glove as it is. Found in game with
	-- "zcg_cuff 0.8 1 0" (for the jacket you wear; your own screen only) and written down here.
	Cuffs = {
		["sheet_m"] = { 0.7, 1, 0 },
		["sheet_hood_m"] = { 0.5, 1, 0 },
		["sheet_closed_m"] = { 0.6, 1, 0 },
		["sheet_wide_m"] = { 0.8, 1, 0 },
		["sheet_tshirt_m"] = { 0.8, 1, 0 },
	},

	-- text of the extra entry in the "Gloves" menu of the appearance editor
	MenuText = "CS:GO gloves...",
	-- title of the picker window
	PickerTitle = "CS:GO gloves",
}
