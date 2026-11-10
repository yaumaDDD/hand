-- Z-City CS:GO gloves - settings for the server owner.
-- Console variables (zcg_any_model, zcg_hide_hands, zcg_enable) are described in the README.

ZCGloves.Config = {
	-- Steam Workshop ID (as a string) of the built addon if you uploaded it to the Workshop:
	-- joining players then download the models and textures automatically.
	-- Leave it nil when players install the addon by hand or get it through FastDL.
	WorkshopID = nil,

	-- true: send every model / material / icon of the addon through FastDL (resource.AddSingleFile).
	-- The content is about 200 MB - prefer the Workshop.
	FastDL = false,

	-- true: the server precaches the 10 glove models, so clients load them while joining
	-- instead of freezing for a moment when a glove is seen for the first time.
	PrecacheModels = true,

	-- how often (seconds) the server checks which glove every player wears
	PollInterval = 0.3,

	-- Full-finger gloves (moto, hardknuckle, leather) hide the hands of the player model, because
	-- the skin would poke through; fingerless gloves keep them, because the fingers are needed.
	-- Override per glove family here if a family looks wrong on your player models:
	--   HideHands = { leather = false }   -- keep the hands under the "Leather" glove
	-- Families: bloodhound, brokenfang, hydra, handwrap, fingerless, moto, hardknuckle, leather.
	-- (zcg_hide_hands 0 switches the hiding off for every glove.)
	HideHands = {},

	-- material used to hide things (the wearer's own hands under full-finger gloves and the
	-- bare arm inside the glove models). nil = "null" if the game has it, otherwise the
	-- material shipped with this addon.
	HideMaterial = nil,

	-- text of the extra entry in the "Gloves" menu of the appearance editor
	MenuText = "CS:GO gloves...",
	-- title of the picker window
	PickerTitle = "CS:GO gloves",
}
