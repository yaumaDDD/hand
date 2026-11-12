-- Z-City CS:GO gloves - appearance editor integration.
--
-- The editor (vgui "HG_AppearanceMenu") knows nothing about this addon, so two things are added
-- from the outside once its PostInit has built the window:
--   1. the model in the middle (a DModelPanel) also shows the selected CS:GO glove;
--   2. the "Gloves" button keeps its menu with the stock gloves and gets one more entry that
--      opens a picker with an icon for every CS:GO glove (hover = try it on, click = take it).
--
-- Everything is optional: if the editor changes in a future Z-City version and something cannot
-- be found, the gloves are still listed by name in the stock "Gloves" menu, because they are
-- regular entries of hg.Appearance.Bodygroups.HANDS.
--
-- Other addons change the editor as well. "Z-City Appearance Mod" (and its LEGACY version) puts
-- a window with a tile per glove behind the "Gloves" button and a window with a slider per body
-- group behind "BODYGROUPS"; section 3 makes both work with the CS:GO gloves.

local ZCG = ZCGloves
local Config = ZCG.Config

local IsValid = IsValid

local function report(what, err)
	ErrorNoHalt("[CS:GO Gloves] " .. what .. ": " .. tostring(err) .. "\n")
end

-- ---------------------------------------------------------------------------------------------
-- which glove does the editor show right now?
-- ---------------------------------------------------------------------------------------------
local function selectedName(main)
	local appearance = main.AppearanceTable
	local groups = istable(appearance) and appearance.ABodygroups
	if not istable(groups) then return nil end
	return groups.HANDS
end

local function selectedVariant(main)
	local name = selectedName(main)
	if name == nil then return nil end
	return ZCG.ByName[name]
end

local function editorVariant(main)
	-- a tile of another addon's glove menu was hovered when that menu went away
	local tile = main.zcg_hoverTile
	if tile ~= nil and not IsValid(tile) then
		main.zcg_hoverTile = nil
		main.zcg_preview = nil
	end
	return main.zcg_preview or selectedVariant(main) -- zcg_preview: hovered in the picker
end

local function choose(main, name)
	local appearance = main.AppearanceTable
	if not istable(appearance) then return end
	appearance.ABodygroups = appearance.ABodygroups or {}
	appearance.ABodygroups.HANDS = name
	surface.PlaySound("player/weapon_draw_0" .. math.random(2, 5) .. ".wav")
end

-- ---------------------------------------------------------------------------------------------
-- 1. the preview model
-- ---------------------------------------------------------------------------------------------
-- runs after the editor's own LayoutEntity, which resets every sub-material in every frame
local function editorLayout(main, ent)
	if not IsValid(ent) then return end
	local variant = editorVariant(main)
	if not variant or not ZCG.HasModel(variant.model) then return end
	-- only while a glove really is drawn over the hands; it is drawn after the model, so the
	-- hands go one frame after the glove came
	local state = ZCG.States[ent]
	if not state or not state.drawn then return end
	local slot = ZCG.Wearing(ent, variant)
	if slot then ent:SetSubMaterial(slot, ZCG.HideMaterial()) end
end

-- runs after the editor's own PostDrawModel (which draws the accessories and ends with
-- Entity:SetupBones(), so the bones the glove is put on are those of this frame)
local function editorDraw(main, ent)
	if not IsValid(ent) then return end
	local variant = editorVariant(main)
	if variant then
		local _, fingers = ZCG.Wearing(ent, variant)
		ZCG.DrawGlove(ent, variant, fingers)
	else
		ZCG.ClearGlove(ent)
	end
end

-- the DModelPanel of the editor (it is the only child with these three functions)
local function isViewer(panel)
	return isfunction(panel.LayoutEntity) and isfunction(panel.PostDrawModel) and isfunction(panel.SetModel)
end

local function wrapViewer(main, viewer)
	local layout, postDraw = viewer.LayoutEntity, viewer.PostDrawModel
	local broken = false

	local function guard(func, ent)
		if broken then return end
		local ok, err = pcall(func, main, ent)
		if not ok then
			broken = true
			report("appearance editor preview switched off", err)
		end
	end

	viewer.LayoutEntity = function(self, ent, ...)
		local result = layout(self, ent, ...)
		guard(editorLayout, ent)
		return result
	end

	viewer.PostDrawModel = function(self, ent, ...)
		local result = postDraw(self, ent, ...)
		guard(editorDraw, ent)
		return result
	end
end

-- ---------------------------------------------------------------------------------------------
-- 2. the picker
-- ---------------------------------------------------------------------------------------------
local clrWindow = Color(15, 15, 20, 250)
local clrBorder = Color(100, 100, 120, 200)
local clrHeader = Color(25, 25, 35, 255)
local clrTile = Color(30, 30, 40, 255)
local clrTileHover = Color(50, 50, 65, 255)
local clrSelected = Color(255, 200, 50, 255)
local clrText = Color(255, 255, 255, 255)
local clrDim = Color(170, 170, 185, 255)
local clrGrip = Color(70, 70, 90, 255)
local clrGripHover = Color(100, 100, 130, 255)
local clrBar = Color(20, 20, 30, 200)

-- same font face as the rest of the Z-City menus
local fontKey
local function setupFonts()
	local face = "Bahnschrift"
	local cv = GetConVar("hg_font")
	if cv and cv:GetString() ~= "" then face = cv:GetString() end

	local size = math.max(11, math.floor(ScreenScale(6)))
	local key = face .. size
	if fontKey == key then return end
	fontKey = key
	surface.CreateFont("ZCG_Title", { font = face, size = math.floor(size * 1.35), weight = 500, extended = true })
	surface.CreateFont("ZCG_Label", { font = face, size = size, weight = 400, extended = true })
end

local function textWidth(font, text)
	surface.SetFont(font)
	local w = surface.GetTextSize(text)
	return w or 0
end

local icons = {}
local function iconOf(variant)
	local icon = icons[variant.id]
	if icon == nil then
		local mat = Material("zcity_csgo_gloves/icons/" .. variant.id .. ".png", "smooth mips")
		icon = (mat and not mat:IsError()) and mat or false
		icons[variant.id] = icon
	end
	return icon or nil
end

local function isInside(panel, root)
	while IsValid(panel) do
		if panel == root then return true end
		panel = panel:GetParent()
	end
	return false
end

-- one group per glove family; families with only a few gloves share a group at the end
local function pickerGroups()
	local me = LocalPlayer()
	local groups, rest = {}, {}
	for _, family in ipairs(ZCG.Families) do
		local list = {}
		for _, variant in ipairs(family.variants) do
			-- return false from this hook to leave a glove out of the picker
			if hook.Run("ZCityCSGOGloves_CanSelect", me, variant) ~= false then list[#list + 1] = variant end
		end
		if #family.variants >= 4 then
			if #list > 0 then groups[#groups + 1] = { title = family.title, variants = list } end
		else
			for _, variant in ipairs(list) do rest[#rest + 1] = variant end
		end
	end
	if #rest > 0 then groups[#groups + 1] = { title = "Other", variants = rest } end
	return groups
end

local function shortName(variant)
	local name = string.gsub(variant.name, "^CS:GO ", "")
	return name
end

local function describe(variant)
	if variant.label and variant.label ~= "" then return shortName(variant) .. " - " .. variant.label end
	return shortName(variant)
end

-- The camera zooms on the hands while main.modelPosID is "Hands" (that is what the stock menu
-- does); it goes back to the full view when neither our menu nor the picker is open any more.
local function releaseCamera(main)
	if not IsValid(main) then return end
	if IsValid(main.zcg_picker) or IsValid(main.zcg_menu) then return end
	if main.modelPosID == "Hands" then main.modelPosID = "All" end
end

local function closePicker(main)
	local picker = main.zcg_picker
	main.zcg_picker = nil
	main.zcg_preview = nil
	if IsValid(picker) then picker:Remove() end
end

-- sizes and position of the picker inside the editor window
local function pickerMetrics(main, groups)
	local w, h = main:GetWide(), main:GetTall()
	local m = {}
	m.gap = math.max(2, math.floor(ScreenScale(2)))
	m.pad = math.max(4, math.floor(ScreenScale(3)))
	m.bar = math.max(6, math.floor(ScreenScale(4)))
	m.header = math.floor(ScreenScale(13))
	m.caption = math.floor(ScreenScale(9))

	local margin = math.floor(ScreenScale(8))
	local top = math.floor(ScreenScale(20)) -- below the model selector at the top
	local bottom = math.floor(ScreenScale(62)) -- above the name / preset / apply controls

	-- With the camera on the hands they stay within about 0.45 * height around the middle of the
	-- window; the picker takes the room to the right of that, so both hands remain visible.
	local room = w / 2 - 0.45 * h - margin
	local function cellFor(columns)
		local chrome = m.pad * 2 + (columns - 1) * m.gap + m.gap + m.bar
		return math.floor((room - chrome) / columns)
	end

	local biggest = math.min(math.floor(ScreenScale(26)), 132) -- the icons are 128 px
	m.columns = 6
	m.cell = cellFor(6)
	if m.cell < math.floor(ScreenScale(20)) then
		m.columns = 5
		m.cell = math.max(cellFor(5), math.floor(ScreenScale(18)))
	end
	m.cell = math.min(m.cell, biggest)

	m.inner = m.columns * m.cell + (m.columns - 1) * m.gap
	m.width = m.pad * 2 + m.inner + m.gap + m.bar

	local content = 0
	for _, group in ipairs(groups) do
		local rows = math.ceil(#group.variants / m.columns)
		content = content + m.caption + rows * (m.cell + m.gap) + m.gap
	end
	m.content = content

	local available = math.max(h - top - bottom, m.header + m.cell * 2)
	m.height = math.min(available, m.header + m.pad * 2 + content)
	m.x = math.Clamp(w - m.width - margin, 0, math.max(w - m.width, 0))
	m.y = math.Clamp(top + math.floor((available - m.height) / 2), 0, math.max(h - m.height, 0))
	return m
end

local function openPicker(main)
	closePicker(main)
	setupFonts()

	local groups = pickerGroups()
	local m = pickerMetrics(main, groups)

	local picker = vgui.Create("DPanel", main)
	main.zcg_picker = picker
	main.modelPosID = "Hands"

	picker:SetSize(m.width, m.height)
	picker:SetPos(m.x, m.y)
	picker:SetZPos(32000)
	picker:MoveToFront()

	local title = Config.PickerTitle or "CS:GO gloves"

	function picker:Paint(w, h)
		draw.RoundedBox(8, 0, 0, w, h, clrWindow)
		draw.RoundedBoxEx(8, 0, 0, w, m.header, clrHeader, true, true, false, false)
		surface.SetDrawColor(clrBorder)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		surface.DrawLine(0, m.header, w, m.header)

		-- title on the left, the hovered (or selected) glove on the right; only the glove when
		-- there is no room for both
		local shown = main.zcg_preview or selectedVariant(main)
		local name = shown and describe(shown) or nil
		local room = w - m.pad * 2 - 4
		if name and textWidth("ZCG_Title", title) + textWidth("ZCG_Label", name) + m.pad * 2 > room then
			if textWidth("ZCG_Label", name) > room then name = shortName(shown) end
			draw.SimpleText(name, "ZCG_Label", m.pad + 2, m.header / 2, clrText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return
		end
		draw.SimpleText(title, "ZCG_Title", m.pad + 2, m.header / 2, clrText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if name then
			draw.SimpleText(name, "ZCG_Label", w - m.pad - 2, m.header / 2, clrDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	function picker:Think()
		if not IsValid(main) or main.zcg_picker ~= self then return end

		-- hovering a glove tries it on
		local hovered = vgui.GetHoveredPanel()
		main.zcg_preview = IsValid(hovered) and hovered.zcg_variant or nil

		-- a click anywhere else closes the picker (the click that opened it does not count)
		local down = input.IsMouseDown(MOUSE_LEFT) or input.IsMouseDown(MOUSE_RIGHT)
		if not down then
			self.zcg_armed = true
			self.zcg_down = false
		elseif self.zcg_armed and not self.zcg_down then
			self.zcg_down = true
			if not isInside(hovered, self) then closePicker(main) end
		end
	end

	function picker:OnRemove()
		if not IsValid(main) then return end
		if main.zcg_picker == self then
			main.zcg_picker = nil
			main.zcg_preview = nil
		end
		releaseCamera(main)
	end

	local scroll = vgui.Create("DScrollPanel", picker)
	scroll:SetPos(m.pad, m.header + m.pad)
	scroll:SetSize(m.width - m.pad * 2, m.height - m.header - m.pad * 2)

	local vbar = scroll:GetVBar()
	if IsValid(vbar) then
		vbar:SetWide(m.bar)
		vbar:SetHideButtons(true)
		function vbar:Paint(w, h)
			draw.RoundedBox(4, 0, 0, w, h, clrBar)
		end
		if IsValid(vbar.btnGrip) then
			function vbar.btnGrip:Paint(w, h)
				draw.RoundedBox(4, 1, 1, w - 2, h - 2, self:IsHovered() and clrGripHover or clrGrip)
			end
		end
	end

	local y = 0
	for _, group in ipairs(groups) do
		local label = vgui.Create("DLabel", scroll)
		label:SetFont("ZCG_Label")
		label:SetTextColor(clrDim)
		label:SetText(group.title)
		label:SetPos(2, y)
		label:SetSize(m.inner - 2, m.caption)
		y = y + m.caption

		for i, variant in ipairs(group.variants) do
			local column = (i - 1) % m.columns
			if i > 1 and column == 0 then y = y + m.cell + m.gap end

			local tile = vgui.Create("DButton", scroll)
			tile:SetText("")
			tile:SetPos(column * (m.cell + m.gap), y)
			tile:SetSize(m.cell, m.cell)
			tile.zcg_variant = variant

			function tile:Paint(w, h)
				draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and clrTileHover or clrTile)
				local icon = iconOf(variant)
				if icon then
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(icon)
					surface.DrawTexturedRect(2, 2, w - 4, h - 4)
				else
					-- no icon file: family and number instead
					draw.SimpleText(variant.family.title, "ZCG_Label", w / 2, h / 2, clrText, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
					draw.SimpleText(tostring(variant.index), "ZCG_Label", w / 2, h / 2, clrDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end
				if selectedName(main) == variant.name then
					surface.SetDrawColor(clrSelected)
					surface.DrawOutlinedRect(0, 0, w, h, 2)
				end
			end

			function tile:DoClick()
				choose(main, variant.name)
				closePicker(main)
			end
		end
		y = y + m.cell + m.gap * 2
	end

	return picker
end

-- the "Gloves" button: stock gloves as before, CS:GO gloves behind one extra entry
local function openGlovesMenu(main)
	closePicker(main)

	local appearance = main.AppearanceTable
	local entry = ZCG.AppearanceModel(appearance.AModel)
	local sex = (entry and entry.sex) and 2 or 1
	local me = LocalPlayer()
	local accessToAll = hg.Appearance.GetAccessToAll

	local menu = DermaMenu()
	for name, data in SortedPairs(hg.Appearance.Bodygroups.HANDS[sex]) do
		if istable(data) and not data.ZCG then
			-- same rule as the original menu: pointshop gloves only when owned
			local locked = data[2] and not me:PS_HasItem(data.ID) and not (accessToAll and accessToAll(me))
			if not locked then
				menu:AddOption(name, function() choose(main, name) end)
			end
		end
	end

	menu:AddSpacer()
	local text = Config.MenuText or "CS:GO gloves..."
	local current = selectedVariant(main)
	if current then text = text .. "  [" .. shortName(current) .. "]" end
	menu:AddOption(text, function()
		local ok, err = pcall(openPicker, main)
		if not ok then
			report("glove picker failed", err)
			closePicker(main)
		end
	end)

	main.zcg_menu = menu
	main.modelPosID = "Hands"
	menu:Open()

	function menu:OnRemove()
		if not IsValid(main) then return end
		if main.zcg_menu == self then main.zcg_menu = nil end
		releaseCamera(main)
	end
end

local function findGlovesButton(viewer)
	for _, child in ipairs(viewer:GetChildren()) do
		if isfunction(child.DoClick) and isfunction(child.GetText) and child:GetText() == "Gloves" then
			return child
		end
	end
	return nil
end

local function wrapGlovesButton(main, viewer)
	local button = findGlovesButton(viewer)
	if not button then return false end

	local stock = button.DoClick
	local function click(self, ...)
		local ok, err = pcall(openGlovesMenu, main)
		if not ok then
			-- back to the original menu for good; it lists the CS:GO gloves by name
			report("glove menu switched off", err)
			button.DoClick = stock
			button.zcg_click = stock
			return stock(self, ...)
		end
	end
	button.DoClick = click
	-- section 3 looks at these to notice another addon taking the button over
	button.zcg_click = click
	viewer.zcg_button = button
	return true
end

-- ---------------------------------------------------------------------------------------------
-- 3. other addons in the editor
-- ---------------------------------------------------------------------------------------------
-- top-level windows: what a menu of another addon is, if it does not hand it to us
local function worldPanels()
	local out = {}
	local world = vgui.GetWorldPanel and vgui.GetWorldPanel()
	if not world or not world.GetChildren then return out end
	for _, child in ipairs(world:GetChildren()) do out[child] = true end
	return out
end

local function newWorldPanels(before)
	local out = {}
	for panel in pairs(worldPanels()) do
		if not before[panel] and IsValid(panel) then out[#out + 1] = panel end
	end
	return out
end

-- a glove by the text another menu shows for it
local byLabel
local function variantByLabel(text)
	if not isstring(text) or text == "" then return nil end
	if not byLabel then
		byLabel = {}
		for _, variant in ipairs(ZCG.Variants) do
			byLabel[variant.name] = variant
			if isfunction(string.NiceName) then byLabel[string.NiceName(variant.name)] = variant end
		end
	end
	return byLabel[text]
end

-- 3a. The glove window of Z-City Appearance Mod: a button per entry of the HANDS list with a
-- model panel (the player model with that entry's body group) and a label inside. For a CS:GO
-- glove the model would show bare hands, 81 times. Such a tile gets the icon instead, and the
-- glove under the cursor is tried on the model of the editor, as in the picker.
local function decorateTile(main, tile)
	if tile.zcg_tile or not isfunction(tile.DoClick) or not isfunction(tile.GetChildren) then return false end

	local label, model, variant
	for _, child in ipairs(tile:GetChildren()) do
		if isfunction(child.LayoutEntity) and isfunction(child.SetModel) then
			model = child
		elseif isfunction(child.GetText) then
			local found = variantByLabel(child:GetText())
			if found then label, variant = child, found end
		end
	end
	if not variant or not model then return false end
	tile.zcg_tile = true

	local icon = iconOf(variant)
	if not icon then return true end -- the content is not installed: the tile stays as it is

	if isfunction(model.SetVisible) then model:SetVisible(false) end -- clicks now reach the tile itself
	label:SetText(shortName(variant))
	if isfunction(tile.SetTooltip) then tile:SetTooltip(describe(variant)) end

	local paint = tile.Paint
	tile.Paint = function(self, w, h)
		local result
		if paint then result = paint(self, w, h) end
		local room = h
		if IsValid(label) then
			local _, y = label:GetPos()
			if y and y > 0 then room = y end
		end
		local size = math.max(math.min(w - 4, room - 4), 0)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(icon)
		surface.DrawTexturedRect(math.floor((w - size) / 2), 2, size, size)
		return result
	end

	local think = tile.Think
	tile.Think = function(self, ...)
		if think then think(self, ...) end
		if not IsValid(main) then return end
		if vgui.GetHoveredPanel() == self then
			main.zcg_preview = variant
			main.zcg_hoverTile = self
		elseif main.zcg_hoverTile == self then
			main.zcg_preview = nil
			main.zcg_hoverTile = nil
		end
	end
	return true
end

local function decorateMenu(main, panel, depth)
	if not IsValid(panel) or not isfunction(panel.GetChildren) then return 0 end
	if decorateTile(main, panel) then return 1 end
	if depth >= 12 then return 0 end
	local count = 0
	for _, child in ipairs(panel:GetChildren()) do
		count = count + decorateMenu(main, child, depth + 1)
	end
	return count
end

-- Another addon wrapped the "Gloves" button after us (Appearance Mod does that a moment after
-- the window is built and calls our menu only when it cannot open its own). Wrap it once more:
-- its menu opens as it wants, then the CS:GO tiles in it are dressed up.
local function watchGlovesButton(main, viewer)
	local button = viewer.zcg_button
	if not IsValid(button) or button.DoClick == button.zcg_click or not isfunction(button.DoClick) then return end

	local inner = button.DoClick
	local broken = false
	local function click(self, ...)
		if broken then return inner(self, ...) end
		local before = worldPanels()
		local function after(...)
			local opened = {}
			for i = 1, select("#", ...) do
				local value = select(i, ...)
				if ispanel(value) then opened[#opened + 1] = value end
			end
			if #opened == 0 then opened = newWorldPanels(before) end
			local ok, err = pcall(function()
				for _, panel in ipairs(opened) do decorateMenu(main, panel, 0) end
			end)
			if not ok then
				broken = true
				report("glove menu of another addon left as it is", err)
			end
			return ...
		end
		return after(inner(self, ...))
	end
	button.DoClick = click
	button.zcg_click = click
end

-- 3b. The "Bodygroups" window of Z-City Appearance Mod has a slider per body group. For the
-- value a slider is moved to it takes the first entry of the list that has this submodel - and
-- every CS:GO glove shares the bare-hands submodel with "None", so moving the hands slider to
-- "bare" would hand out some CS:GO glove. While such a window is open, a CS:GO glove that
-- appears in the appearance is therefore turned into "None": the sliders have no other way to
-- select bare hands, and the gloves are picked in the glove menu.
local sliderWatches = {}

local function handsKeys(groups)
	local out = {}
	for key in pairs(groups) do
		if isstring(key) and string.upper(key) == "HANDS" then out[#out + 1] = key end
	end
	return out
end

-- name of Z-City's entry for bare hands; without one the selection is simply dropped
local function bareHands()
	local AP = hg and hg.Appearance
	local hands = istable(AP) and istable(AP.Bodygroups) and AP.Bodygroups.HANDS
	if not istable(hands) then return nil end
	for sex = 1, 2 do
		if istable(hands[sex]) and hands[sex]["None"] ~= nil then return "None" end
	end
	return nil
end

local function checkSliders()
	for index = #sliderWatches, 1, -1 do
		local watch = sliderWatches[index]
		local open = false
		for _, frame in ipairs(watch.frames) do
			if IsValid(frame) then open = true break end
		end
		local groups = watch.appearance.ABodygroups
		if not open or not istable(groups) then
			table.remove(sliderWatches, index)
		else
			for _, key in ipairs(handsKeys(groups)) do
				local value = groups[key]
				if value ~= watch.last[key] then
					if ZCG.ByName[value] then
						value = bareHands()
						groups[key] = value
					end
					watch.last[key] = value
				end
			end
		end
	end
	if #sliderWatches == 0 then hook.Remove("Think", "zcg_sliders") end
end

local function watchSliders(appearance, frames)
	if not istable(appearance) or #frames == 0 then return end
	appearance.ABodygroups = appearance.ABodygroups or {}
	local last = {}
	for _, key in ipairs(handsKeys(appearance.ABodygroups)) do last[key] = appearance.ABodygroups[key] end
	sliderWatches[#sliderWatches + 1] = { appearance = appearance, frames = frames, last = last }
	hook.Add("Think", "zcg_sliders", checkSliders)
end

local sliderWrappers = setmetatable({}, { __mode = "k" })

local function hookSliderWindow()
	local AP = hg and hg.Appearance
	local open = istable(AP) and AP.OpenBodygroupsShowcaseMenu
	if not isfunction(open) or sliderWrappers[open] then return end

	local function wrapped(appearance, ...)
		local before = worldPanels()
		local function after(...)
			local ok, err = pcall(watchSliders, appearance or AP.CurrentEditTable, newWorldPanels(before))
			if not ok then report("body group sliders", err) end
			return ...
		end
		return after(open(appearance, ...))
	end
	sliderWrappers[wrapped] = true
	AP.OpenBodygroupsShowcaseMenu = wrapped
end

-- ---------------------------------------------------------------------------------------------
-- attaching to the editor
-- ---------------------------------------------------------------------------------------------
-- Hooks into every model panel of the editor window that is not hooked yet (PostInit may run
-- more than once and builds a new one each time). Returns true if the window has one.
function ZCG.AttachEditor(main)
	if not IsValid(main) then return false end

	local found = false
	for _, child in ipairs(main:GetChildren()) do
		if isViewer(child) then
			found = true
			if not child.zcg_wrapped then
				child.zcg_wrapped = true

				local ok, err = pcall(wrapViewer, main, child)
				if not ok then report("appearance editor preview", err) end

				ok, err = pcall(wrapGlovesButton, main, child)
				if not ok then report("appearance editor menu", err) end
			end

			local ok, err = pcall(watchGlovesButton, main, child)
			if not ok then report("appearance editor menu of another addon", err) end
		end
	end
	return found
end

-- PANEL.PostInit builds the window: run right after it
local wrappers = setmetatable({}, { __mode = "k" })

local function hookEditorClass()
	local class = vgui.GetControlTable("HG_AppearanceMenu")
	if not istable(class) or not isfunction(class.PostInit) or wrappers[class.PostInit] then return end

	local postInit = class.PostInit
	local function wrapped(self, ...)
		postInit(self, ...)
		local ok, err = pcall(ZCG.AttachEditor, self)
		if not ok then report("appearance editor", err) end
	end
	wrappers[wrapped] = true
	class.PostInit = wrapped
end

hookEditorClass()
hookSliderWindow()
hook.Add("InitPostEntity", "zcg_editor", function()
	hookEditorClass()
	hookSliderWindow()
end)

-- Z-City Appearance Mod runs this when it has put its own menus on the buttons of the editor
hook.Add("HG_AppearanceMenuReady", "zcg_editor", function(panel)
	if not ispanel(panel) then return end
	local ok, err = pcall(ZCG.AttachEditor, panel)
	if not ok then report("appearance editor", err) end
end)

-- Safety net: the editor class is registered late (and again on a Lua refresh), and a window may
-- already be open; "zpan" is the global Z-City keeps the open editor in.
timer.Create("zcg_editor", 0.5, 0, function()
	hookEditorClass()
	hookSliderWindow()
	local open = rawget(_G, "zpan")
	if ispanel(open) and IsValid(open) then
		local ok, err = pcall(ZCG.AttachEditor, open)
		if not ok then report("appearance editor", err) end
	end
end)
