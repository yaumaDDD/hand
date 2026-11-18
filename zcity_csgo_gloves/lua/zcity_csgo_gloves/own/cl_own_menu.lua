-- Our own appearance system: the menu. Nothing of the Appearance Mod is used for it - the list of
-- what can be worn comes out of the catalog of this addon (own/sh_catalog.lua), the look is put on
-- the player by our own server code (own/sv_own.lua), and what a player chooses is kept on the
-- server and in data/zco/ of his own client.
--
-- Opens: the chat commands /внешность, /внешка, /appearance, /menu, the console command zco_menu
-- (bind it to a key: bind MOUSE_MIDDLE zco_menu), and ZCO.OpenMenu() from any other Lua.

ZCO = ZCO or {}

ZCO.Menu = ZCO.Menu or {}

surface.CreateFont("ZCOTitle", { font = "Roboto", size = 22, weight = 700 })
surface.CreateFont("ZCOCategory", { font = "Roboto", size = 17, weight = 500 })
surface.CreateFont("ZCOItem", { font = "Roboto", size = 15, weight = 400 })
surface.CreateFont("ZCOSmall", { font = "Roboto", size = 13, weight = 400 })

-- the categories of the menu, in the order they are shown
ZCO.Categories = {
	{ id = "model", title = "Модель" },
	{ id = "main", title = "Одежда" },
	{ id = "pants", title = "Штаны" },
	{ id = "boots", title = "Обувь" },
	{ id = "HANDS", title = "Перчатки" },
	{ id = "groups", title = "Телосложение" },
	{ id = "face", title = "Лицо" },
	{ id = "attach", title = "Аксессуары" },
	{ id = "name", title = "Имя" },
	{ id = "color", title = "Цвет" },
	{ id = "sets", title = "Наборы" },
}

--- the sex the menu shows the things of: the one of the model that is chosen
function ZCO.Menu.SexOf(appearance)
	local _name, entry, sex = ZCO.ModelByName(appearance and appearance.AModel or nil)
	return sex or (entry and entry.sex and ZCO.FEMALE or ZCO.MALE)
end

--- what a category offers: { { title, value, material, hint } }
function ZCO.Menu.Items(category, appearance)
	local sex = ZCO.Menu.SexOf(appearance)
	local got = {}
	if category == "model" then
		local names = {}
		for name, entry in pairs(ZCO.Models(sex)) do
			if type(entry) == "table" and entry.mdl then names[#names + 1] = name end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			got[#got + 1] = { title = name, value = name, hint = ZCO.Models(sex)[name].mdl }
		end
	elseif category == "main" or category == "pants" or category == "boots" or category == "hands" then
		local slot = category == "hands" and "hands" or category
		local names = {}
		for name, material in pairs(ZCO.Clothes(sex)) do
			names[#names + 1] = { name, material }
		end
		local other = ZCO.Clothes(sex == ZCO.FEMALE and ZCO.MALE or ZCO.FEMALE)
		for name, material in pairs(other) do
			if not ZCO.Clothes(sex)[name] then names[#names + 1] = { name, material } end
		end
		table.sort(names, function(a, b) return a[1] < b[1] end)
		for _, pair in ipairs(names) do
			local description = (ZCO.Catalog.ClothesDesc or {})[pair[1]]
			got[#got + 1] = { title = pair[1], value = pair[1], material = pair[2], slot = slot,
				hint = description and description.desc or nil }
		end
	elseif category == "face" then
		local _name, entry = ZCO.ModelByName(appearance.AModel)
		local model = (entry and entry.mdl) or (type(appearance.AModel) == "string" and appearance.AModel) or ""
		local names = {}
		for name, material in pairs(ZCO.Faces(model, sex)) do names[#names + 1] = { name, material } end
		table.sort(names, function(a, b) return a[1] < b[1] end)
		for _, pair in ipairs(names) do
			got[#got + 1] = { title = pair[1], value = pair[1], material = pair[2] }
		end
	else
		local group = nil
		for _, known in ipairs(ZCO.GROUPS) do
			if known == category then group = known end
		end
		if group then
			local names = {}
			local by_sex = ZCO.Bodygroups(group, sex)
			for name in pairs(by_sex) do names[#names + 1] = name end
			if group == "HANDS" and not by_sex["None"] then names[#names + 1] = "None" end
			table.sort(names)
			for _, name in ipairs(names) do
				local entry = by_sex[name]
				got[#got + 1] = { title = name, value = name, group = group,
					hint = entry and entry.submodel or "свои руки" }
			end
		elseif category == "groups" then
			for _, known in ipairs(ZCO.GROUPS) do
				if known ~= "HANDS" and next(ZCO.Bodygroups(known, sex)) then
					local names = {}
					for name in pairs(ZCO.Bodygroups(known, sex)) do names[#names + 1] = name end
					table.sort(names)
					for _, name in ipairs(names) do
						got[#got + 1] = { title = known .. ": " .. name, value = name, group = known,
							hint = ZCO.Bodygroups(known, sex)[name].submodel }
					end
				end
			end
		elseif category == "attach" then
			-- the places in the order of ZCO.PLACEMENTS, a place nobody knows of after them
			local have, places = ZCO.Placements(), {}
			for _, place in ipairs(ZCO.PLACEMENTS) do
				if have[place] then places[#places + 1] = place end
			end
			local rest = {}
			for place in pairs(have) do
				local known = false
				for _, one in ipairs(ZCO.PLACEMENTS) do if one == place then known = true end end
				if not known then rest[#rest + 1] = place end
			end
			table.sort(rest)
			for _, place in ipairs(rest) do places[#places + 1] = place end
			for _, place in ipairs(places) do
				local names = {}
				for name, data in pairs(ZCO.AccessoriesByPlacement(place)) do
					if not data.disallow then names[#names + 1] = name end
				end
				table.sort(names)
				for _, name in ipairs(names) do
					local data = ZCO.AccessoriesByPlacement(place)[name]
					got[#got + 1] = { title = (data.name or name) .. "  (" .. place .. ")", value = name,
						placement = place, hint = data.model }
				end
			end
		end
	end
	return got
end

--- what is chosen right now in a category (so that the button of it is lit)
function ZCO.Menu.Chosen(category, appearance)
	if category == "model" then return appearance.AModel end
	if category == "main" or category == "pants" or category == "boots" or category == "hands" then
		return appearance.AClothes and appearance.AClothes[category == "hands" and "hands" or category]
	end
	if category == "face" then return appearance.AFacemap end
	if category == "attach" then return appearance.AAttachments end
	for _, known in ipairs(ZCO.GROUPS) do
		if known == category then return appearance.ABodygroups and appearance.ABodygroups[category] end
	end
	return nil
end

-- --------------------------------------------------------------------------------------
-- the look in the middle of the menu
-- --------------------------------------------------------------------------------------

--- the preview panel: the model, the clothes in its slots, the face, the bodygroups
function ZCO.Menu.Preview(panel, appearance)
	if not panel then return end
	local name, entry = ZCO.ModelByName(appearance.AModel)
	local model = (entry and entry.mdl) or (type(appearance.AModel) == "string" and appearance.AModel) or nil
	if not model or model == "" then return end
	if panel.zcoModel ~= model then
		panel:SetModel(model)
		panel.zcoModel = model
		panel:SetCamPos(Vector(-70, 0, 58))
		panel:SetLookAt(Vector(0, 0, 42))
		panel:SetFOV(28)
	end
	local ent = panel.Entity
	if not IsValid(ent) then return end
	local sex = (entry and entry.sex and ZCO.FEMALE) or (name and ZCO.Menu.SexOf(appearance)) or ZCO.MALE
	local clothes = ZCO.Clothes(sex)
	local slots = entry and entry.submatSlots or {}
	ent:SetSubMaterial()
	for _, slot in ipairs(ZCO.SLOTS) do
		local index = ZCO.SlotOf(ent, slots[slot])
		local worn = appearance.AClothes and appearance.AClothes[slot]
		local material = worn and (clothes[worn] or ZCO.Clothes(ZCO.MALE)[worn] or ZCO.Clothes(ZCO.FEMALE)[worn])
		if index and material and material ~= "" then ent:SetSubMaterial(index, material) end
	end
	local materials = ent:GetMaterials() or {}
	for index = 1, #materials do
		local by_name = (ZCO.Catalog.Facemaps or {})[materials[index]]
		local face = appearance.AFacemap or "Default"
		if type(by_name) == "table" and by_name[face] then ent:SetSubMaterial(index - 1, by_name[face]) end
		local multi = (ZCO.Catalog.MultiFacemaps or {})[model]
		if type(multi) == "table" and type(multi[face]) == "table" and multi[face][materials[index]] then
			ent:SetSubMaterial(index - 1, multi[face][materials[index]])
		end
	end
	local groups = ent:GetBodyGroups() or {}
	for index = 1, #groups do
		local group = groups[index]
		local worn = group and group.name and appearance.ABodygroups and appearance.ABodygroups[group.name]
		local known = group and group.name and ZCO.Bodygroups(group.name, sex)[worn or ""]
		if group and group.submodels and known and known.submodel then
			for sub = 0, #group.submodels do
				if group.submodels[sub] == known.submodel then
					ent:SetBodygroup(index - 1, sub)
					break
				end
			end
		end
	end
	if ent.SetColor and type(appearance.AColor) == "table" and appearance.AColor.r then
		ent:SetColor(Color(appearance.AColor.r, appearance.AColor.g, appearance.AColor.b, 255))
	end
end

-- --------------------------------------------------------------------------------------
-- the frame
-- --------------------------------------------------------------------------------------

local function itemButton(parent, item, chosen, category, appearance, frame)
	local button = vgui.Create("DButton", parent)
	button:SetTall(46)
	button:SetText("")
	button.zcoTitle = item.title
	button.zcoHint = item.hint
	button.zcoChosen = chosen
	if item.material and item.material ~= "" then
		button.zcoMaterial = Material(item.material)
	end
	button.Paint = function(self, wide, tall)
		local back = self.zcoChosen and Color(64, 122, 190, 235) or (self:IsHovered() and Color(58, 64, 76, 235)
			or Color(38, 42, 50, 225))
		draw.RoundedBox(4, 0, 0, wide, tall, back)
		local left = 8
		if self.zcoMaterial then
			surface.SetMaterial(self.zcoMaterial)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRect(6, 5, tall - 10, tall - 10)
			left = tall + 4
		end
		draw.SimpleText(self.zcoTitle, "ZCOItem", left, tall / 2, Color(235, 238, 242), TEXT_ALIGN_LEFT,
			TEXT_ALIGN_CENTER)
		if self.zcoChosen then
			draw.SimpleText("выбрано", "ZCOSmall", wide - 8, tall / 2, Color(210, 230, 255), TEXT_ALIGN_RIGHT,
				TEXT_ALIGN_CENTER)
		end
	end
	button.DoClick = function()
		ZCO.Menu.Choose(frame, category, item, appearance)
	end
	if item.hint then button:SetTooltip(tostring(item.hint)) end
	return button
end

--- a click on an item: the look changes, the preview and the list are drawn again
function ZCO.Menu.Choose(frame, category, item, appearance)
	if category == "model" then
		appearance.AModel = item.value
		-- another model: the clothes and the face of the old one may not be there in the new one
		local sex = ZCO.Menu.SexOf(appearance)
		local clothes = ZCO.Clothes(sex)
		for _, slot in ipairs(ZCO.SLOTS) do
			local worn = appearance.AClothes[slot]
			if worn and not clothes[worn] and not ZCO.Clothes(ZCO.MALE)[worn]
				and not ZCO.Clothes(ZCO.FEMALE)[worn] then
				appearance.AClothes[slot] = clothes["normal"] and "normal" or nil
			end
		end
	elseif category == "main" or category == "pants" or category == "boots" or category == "hands" then
		appearance.AClothes[category == "hands" and "hands" or category] = item.value
	elseif category == "face" then
		appearance.AFacemap = item.value
	elseif category == "attach" then
		local list = appearance.AAttachments or {}
		local kept = {}
		for index = 1, #list do
			local worn = list[index]
			local data = (ZCO.Catalog.Accessories or {})[worn]
			if worn ~= item.value and (not data or data.placement ~= item.placement) then kept[#kept + 1] = worn end
		end
		-- the same accessory once more takes it off
		local had = false
		for index = 1, #list do
			if list[index] == item.value then had = true end
		end
		if not had and #kept < ZCO.MAX_ATTACHMENTS then kept[#kept + 1] = item.value end
		appearance.AAttachments = kept
	elseif item.group then
		local worn = appearance.ABodygroups[item.group]
		if worn == item.value then
			appearance.ABodygroups[item.group] = nil      -- the same one once more takes it off
		else
			appearance.ABodygroups[item.group] = item.value
		end
	end
	ZCO.MenuState = appearance
	frame:zcoRefresh()
end

--- the frame of the menu (made once, shown again with what the player wears)
function ZCO.Menu.Build(appearance)
	local frame = vgui.Create("DFrame")
	frame:SetSize(1020, 660)
	frame:Center()
	frame:SetTitle("Внешность — " .. ZCO.Name .. " " .. ZCO.Version)
	frame:SetDraggable(true)
	frame:ShowCloseButton(true)
	frame:MakePopup()
	frame.zcoAppearance = ZCO.Copy(appearance)
	frame.zcoCategory = "model"

	local background = vgui.Create("DPanel", frame)
	background:SetPos(0, 0)
	background:SetSize(1020, 660)
	background.Paint = function(_self, wide, tall)
		draw.RoundedBox(0, 0, 0, wide, tall, Color(24, 26, 31, 250))
	end

	-- the categories
	local categories = vgui.Create("DScrollPanel", frame)
	categories:SetPos(10, 34)
	categories:SetSize(190, 616)
	frame.zcoCategories = categories

	-- the things of a category
	local items = vgui.Create("DScrollPanel", frame)
	items:SetPos(210, 34)
	items:SetSize(480, 616)
	frame.zcoItems = items

	-- the look, the name and the color
	local preview = vgui.Create("DModelPanel", frame)
	preview:SetPos(700, 34)
	preview:SetSize(310, 380)
	preview:SetModel("models/error.mdl")
	preview.PaintOver = function(_self, wide, tall)
		draw.SimpleText("так это выглядит", "ZCOSmall", wide / 2, tall - 10, Color(200, 205, 215),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	frame.zcoPreview = preview

	local name_label = vgui.Create("DLabel", frame)
	name_label:SetPos(700, 420)
	name_label:SetSize(310, 18)
	name_label:SetText("Имя персонажа")
	name_label:SetFont("ZCOSmall")

	local name_entry = vgui.Create("DTextEntry", frame)
	name_entry:SetPos(700, 440)
	name_entry:SetSize(310, 26)
	name_entry:SetValue(frame.zcoAppearance.AName or "")
	name_entry:SetPlaceholderText("2-25 букв, русский или английский")
	name_entry.OnChange = function(self)
		frame.zcoAppearance.AName = self:GetValue()
	end
	frame.zcoName = name_entry

	local color = vgui.Create("DColorMixer", frame)
	color:SetPos(700, 474)
	color:SetSize(310, 120)
	color:SetAlphaBar(false)
	color:SetWangs(true)
	color:SetPalette(true)
	if type(frame.zcoAppearance.AColor) == "table" and frame.zcoAppearance.AColor.r then
		color:SetColor(Color(frame.zcoAppearance.AColor.r, frame.zcoAppearance.AColor.g,
			frame.zcoAppearance.AColor.b, 255))
	end
	color.ValueChanged = function(_self, value)
		frame.zcoAppearance.AColor = value
		frame:zcoRefresh(true)
	end
	frame.zcoColor = color

	-- the buttons
	local function action(title, x, wide, click)
		local button = vgui.Create("DButton", frame)
		button:SetPos(x, 602)
		button:SetSize(wide, 46)
		button:SetText(title)
		button:SetFont("ZCOItem")
		button.DoClick = click
		return button
	end

	action("Применить", 700, 150, function()
		local clean = ZCO.Clean(frame.zcoAppearance)
		local ok, why = ZCO.Validate(clean)
		if not ok then
			chat.AddText(Color(255, 140, 140), "[Внешность] ", Color(230, 230, 230),
				"Так нельзя: " .. tostring(why or "не из списка") .. ".")
			return
		end
		frame.zcoAppearance = clean
		ZCO.Send(clean)
		ZCO.SavePreset(ZCO.Selected:GetString(), clean)
		ZCO.WriteOld(ZCO.Selected:GetString(), clean)
		chat.AddText(Color(140, 220, 150), "[Внешность] ", Color(230, 230, 230), "Внешность отправлена серверу.")
		frame:zcoRefresh()
	end)

	action("Случайно", 860, 150, function()
		frame.zcoAppearance = ZCO.Random(ZCO.Menu.SexOf(frame.zcoAppearance))
		frame.zcoName:SetValue(frame.zcoAppearance.AName or "")
		if frame.zcoColor.SetColor and type(frame.zcoAppearance.AColor) == "table" then
			frame.zcoColor:SetColor(Color(frame.zcoAppearance.AColor.r, frame.zcoAppearance.AColor.g,
				frame.zcoAppearance.AColor.b, 255))
		end
		frame:zcoRefresh()
	end)

	-- the sets of this client
	local sets = vgui.Create("DComboBox", frame)
	sets:SetPos(700, 654)
	sets:SetSize(0, 0)
	sets:Remove()

	frame.zcoSets = vgui.Create("DListView", frame)
	frame.zcoSets:SetPos(10, 654)
	frame.zcoSets:SetSize(0, 0)
	frame.zcoSets:Remove()

	-- what the categories and the things are drawn by
	function frame:zcoCategory(category)
		self.zcoCategory = category
		self:zcoRefresh()
	end

	function frame:zcoRefresh(onlyPreview)
		local appearance = self.zcoAppearance
		if IsValid(self.zcoPreview) then ZCO.Menu.Preview(self.zcoPreview, appearance) end
		if onlyPreview then return end
		-- the categories
		if IsValid(self.zcoCategories) then
			self.zcoCategories:Clear()
			local chosen = self.zcoCategory
			for _, category in ipairs(ZCO.Categories) do
				local button = vgui.Create("DButton", self.zcoCategories)
				button:DockMargin(0, 0, 0, 4)
				button:SetTall(38)
				button:SetText("")
				button.zcoTitle = category.title
				button.zcoChosen = category.id == chosen
				button.Paint = function(panel, wide, tall)
					draw.RoundedBox(4, 0, 0, wide, tall, panel.zcoChosen and Color(64, 122, 190, 235)
						or (panel:IsHovered() and Color(52, 57, 68, 235) or Color(34, 37, 44, 225)))
					draw.SimpleText(panel.zcoTitle, "ZCOCategory", 12, tall / 2, Color(232, 236, 242),
						TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				button.DoClick = function()
					self:zcoCategory(category.id)
				end
				local how_many = 0
				if category.id ~= "name" and category.id ~= "color" and category.id ~= "sets" then
					how_many = #ZCO.Menu.Items(category.id, appearance)
				end
				if how_many > 0 then
					local count = vgui.Create("DLabel", button)
					count:SetText(tostring(how_many))
					count:SetFont("ZCOSmall")
					count:SetSize(40, 18)
					count:SetPos(140, 10)
				end
			end
		end
		-- the things of the category
		if IsValid(self.zcoItems) then
			self.zcoItems:Clear()
			local category = self.zcoCategory
			if category == "name" then
				local label = vgui.Create("DLabel", self.zcoItems)
				label:SetPos(4, 4)
				label:SetSize(460, 200)
				label:SetText("Имя вписывается справа. Буквы русского и английского алфавита и пробел,\n"
					.. "от 2 до 25 букв. Сервер не принимает другое имя.")
				label:SetFont("ZCOItem")
			elseif category == "color" then
				local label = vgui.Create("DLabel", self.zcoItems)
				label:SetPos(4, 4)
				label:SetSize(460, 200)
				label:SetText("Цвет выбирается справа: он красит то, что красится цветом игрока\n"
					.. "(рубашки, повязки, некоторые аксессуары).")
				label:SetFont("ZCOItem")
			elseif category == "sets" then
				local list = vgui.Create("DListView", self.zcoItems)
				list:SetPos(4, 4)
				list:SetSize(470, 400)
				list:SetMultiSelect(false)
				list:AddColumn("Набор (data/zco/)")
				for _, name in ipairs(ZCO.PresetList()) do
					local line = list:AddLine(name)
					line.zcoName = name
				end
				list.OnRowSelected = function(_panel, _index, line)
					local got = ZCO.LoadPreset(line.zcoName)
					if got then
						self.zcoAppearance = got
						self.zcoName:SetValue(got.AName or "")
						if self.zcoColor.SetColor and type(got.AColor) == "table" and got.AColor.r then
							self.zcoColor:SetColor(Color(got.AColor.r, got.AColor.g, got.AColor.b, 255))
						end
						self:zcoRefresh()
					end
				end
				local save = vgui.Create("DButton", self.zcoItems)
				save:SetPos(4, 412)
				save:SetSize(150, 34)
				save:SetText("Сохранить как main")
				save.DoClick = function()
					ZCO.SavePreset(ZCO.Selected:GetString(), self.zcoAppearance)
					chat.AddText(Color(140, 220, 150), "[Внешность] ", Color(230, 230, 230),
						("Набор «%s» записан в data/zco/."):format(ZCO.Selected:GetString()))
				end
				local take = vgui.Create("DButton", self.zcoItems)
				take:SetPos(162, 412)
				take:SetSize(150, 34)
				take:SetText("Серверный")
				take:SetTooltip("То, что сервер хранит для этого персонажа")
				take.DoClick = function()
					if ZCO.Saved then
						self.zcoAppearance = ZCO.Copy(ZCO.Saved)
						self.zcoName:SetValue(self.zcoAppearance.AName or "")
						self:zcoRefresh()
					end
				end
				local old = vgui.Create("DButton", self.zcoItems)
				old:SetPos(320, 412)
				old:SetSize(154, 34)
				old:SetText("Из прежнего мода")
				old:SetTooltip("Прочитать наборы из data/zcity/appearances/")
				old.DoClick = function()
					local taken = 0
					for _, name in ipairs(ZCO.OldList()) do
						if ZCO.ImportOld(name) then taken = taken + 1 end
					end
					chat.AddText(Color(140, 220, 150), "[Внешность] ", Color(230, 230, 230),
						("Перенесено наборов: %d."):format(taken))
					self:zcoRefresh()
				end
			else
				local chosen = ZCO.Menu.Chosen(category, appearance)
				local column, wide = 0, 470
				for index, item in ipairs(ZCO.Menu.Items(category, appearance)) do
					local button = itemButton(self.zcoItems, item,
						(type(chosen) == "table" and table.HasValue(chosen, item.value)) or chosen == item.value,
						category, appearance, self)
					button:SetPos(4 + column * (wide / 2), 4 + math.floor((index - 1) / 2) * 50)
					button:SetSize(wide / 2 - 8, 46)
					column = column == 0 and 1 or 0
				end
			end
		end
	end

	frame:zcoRefresh()
	frame.OnClose = function()
		ZCO.MenuFrame = nil
	end
	return frame
end

--- open the menu (or bring the one that is open to the front) with what the player wears now
function ZCO.OpenMenu()
	if not LocalPlayer or not IsValid(LocalPlayer()) then return end
	ZCO.Install()
	if IsValid(ZCO.MenuFrame) then
		ZCO.MenuFrame:MoveToFront()
		return ZCO.MenuFrame
	end
	local appearance = ZCO.Saved and ZCO.Copy(ZCO.Saved) or ZCO.Read(LocalPlayer())
	if not ZCO.Validate(appearance) then appearance = ZCO.Clean(appearance) end
	ZCO.MenuState = appearance
	ZCO.MenuFrame = ZCO.Menu.Build(appearance)
	return ZCO.MenuFrame
end

concommand.Add("zco_menu", function() ZCO.OpenMenu() end, nil, "The menu of the appearance of this addon")

-- The buttons of Z-City open the appearance by the command hg_appearance_menu. With our own rails
-- that command opens our menu; where our menu does not open (something missing on this computer),
-- the editor that was there is called instead, so that nobody is left without an appearance.
-- zco_take_menu 0 leaves the command to whoever had it - the editor of the gamemode or of the mod.
ZCO.TakeMenu = CreateClientConVar("zco_take_menu", "1", true, false,
	"1: hg_appearance_menu opens the menu of this addon, 0: the editor that was there")

local had_menu = nil            -- the function that had the command before us
local ours_menu = nil           -- ... and the one of ours, so that it is not remembered as theirs

function ZCO.TakeAppearanceCommand()
	local commands = concommand.GetTable and concommand.GetTable() or nil
	local now = commands and commands["hg_appearance_menu"]
	if type(now) == "function" and now ~= ours_menu then had_menu = now end
	if ZCO.TakeMenu:GetBool() then
		ours_menu = function()
			local ok, err = pcall(ZCO.OpenMenu)
			if ok then return end
			print("[Внешность] своё меню не открылось: " .. tostring(err))
			if type(had_menu) == "function" then had_menu() end
		end
		concommand.Add("hg_appearance_menu", ours_menu, nil, "The menu of the appearance of this addon")
	elseif type(had_menu) == "function" then
		concommand.Add("hg_appearance_menu", had_menu, nil, "The appearance editor of Z-City")
	end
end

ZCO.TakeAppearanceCommand()

-- the game tells a convar that changed to cvars, not to the hooks (cvars.OnConVarChanged)
cvars.AddChangeCallback("zco_take_menu", function(_name, _old, _new)
	ZCO.TakeAppearanceCommand()
end, "zco_take_menu")

local COMMANDS = { "/внешность", "/внешка", "/appearance", "/menu", "/меню", "!внешность", "!appearance" }
hook.Add("OnPlayerChat", "zco_menu", function(ply, text)
	if ply ~= LocalPlayer() then return end
	for _, command in ipairs(COMMANDS) do
		if text:lower() == command then
			ZCO.OpenMenu()
			return true
		end
	end
	return nil
end)

-- the server hands the saved appearance over when the player joins: the menu opens with it
hook.Add("ZCOSaved", "zco_menu", function()
	if IsValid(ZCO.MenuFrame) then ZCO.MenuFrame:zcoRefresh() end
end)

-- a line in the chat the first time, so that the menu is found without a manual
hook.Add("InitPostEntity", "zco_menu", function()
	timer.Simple(12, function()
		if not LocalPlayer or not IsValid(LocalPlayer()) then return end
		if ZCO.Told then return end
		ZCO.Told = true
		local got = ZCO.Counts()
		chat.AddText(Color(120, 200, 255), "[Внешность] ", Color(230, 230, 230),
			("свои рельсы %s: моделей %d, одежды %d, лиц %d, аксессуаров %d. Меню: /внешность или zco_menu.")
				:format(ZCO.Version, got.models, got.clothes, got.faces, got.accessories))
	end)
end)
