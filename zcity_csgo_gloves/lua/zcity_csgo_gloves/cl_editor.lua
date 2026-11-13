-- Z-City CS:GO gloves - appearance editor integration.
--
-- The editor (vgui "HG_AppearanceMenu") knows nothing about this addon, so two things are added
-- from the outside once its PostInit has built the window:
--   1. the model in the middle (a DModelPanel) also shows the selected CS:GO glove;
--   2. the "Gloves" button keeps its menu with the stock gloves and gets one more entry that
--      opens a picker with an icon for every CS:GO glove (hover = try it on, click = take it);
--   3. with the "Z-City Appearance Mod" installed the "Gloves" button opens that addon's window
--      of previews instead: the window gets one more tile, which opens the same picker.
--
-- Everything is optional: if the editor changes in a future Z-City version and something cannot
-- be found, the gloves are still listed by name in the stock "Gloves" menu, because they are
-- regular entries of hg.Appearance.Bodygroups.HANDS.

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
-- The hands of the model go only while a glove really is drawn over them; the glove is drawn
-- after the model, so they go one frame after the glove came.
local function gloveOn(main, ent)
	if not IsValid(ent) then return nil end
	local variant = editorVariant(main)
	if not variant or not ZCG.HasModel(variant.model) then
		-- (a glove of Z-City or none: whatever this addon hid on the model is given back)
		ZCG.GiveBack(ent)
		return nil
	end
	local state = ZCG.States[ent]
	if not state or not state.drawn then return nil end
	return variant, state
end

-- runs after the editor's own LayoutEntity, which resets every sub-material in every frame
local function editorLayout(main, ent)
	local variant = gloveOn(main, ent)
	if not variant then return end
	local slot, _, _, more = ZCG.Wearing(ent, variant)
	if slot then
		ent:SetSubMaterial(slot, ZCG.HideMaterial())
		ZCG.NoteHidden(ent, slot)
	end
	-- (every other material that lies on the hands alone; the editor resets them all each frame)
	for _, other in ipairs(more or {}) do
		ent:SetSubMaterial(other, ZCG.HideMaterial())
		ZCG.NoteHidden(ent, other)
	end
end

-- runs right before the model is drawn: it gets the bones of this frame with the hands shrunk
-- into the wrists (every model, or what zcg_hide_bones says: see cl_render.lua)
local function editorBefore(main, ent)
	local variant, state = gloveOn(main, ent)
	if not variant then return end
	local _, _, bones = ZCG.Wearing(ent, variant)
	if not bones then return end
	ent:SetupBones()
	state.shrunk = ZCG.ShrinkHands(ent, state)
end

-- runs before the editor's own PostDrawModel: the accessories it draws find whole hands
local function editorAfter(main, ent)
	local state = IsValid(ent) and ZCG.States[ent]
	if state then ZCG.GrowHands(ent, state) end
end

-- runs after the editor's own PostDrawModel (which draws the accessories and ends with
-- Entity:SetupBones(), so the bones the glove is put on are those of this frame)
local function editorDraw(main, ent)
	if not IsValid(ent) then return end
	local variant = editorVariant(main)
	if variant then
		local _, fingers = ZCG.Wearing(ent, variant)
		local state = ZCG.States[ent]
		if state then state.shrunk = false end
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
	local layout, preDraw, postDraw = viewer.LayoutEntity, viewer.PreDrawModel, viewer.PostDrawModel
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
		-- (the bodies chosen in the menu on a model that names them differently: sh_core.lua)
		if not broken and IsValid(ent) and istable(main.AppearanceTable) then
			pcall(ZCG.FixBodygroups, ent, main.AppearanceTable)
		end
		guard(editorLayout, ent)
		return result
	end

	viewer.PreDrawModel = function(self, ent, ...)
		local result
		if isfunction(preDraw) then result = preDraw(self, ent, ...) end
		if result ~= false then guard(editorBefore, ent) end -- (false: the model is not drawn)
		return result
	end

	viewer.PostDrawModel = function(self, ent, ...)
		guard(editorAfter, ent)
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

	-- The Appearance Mod (section 3) wraps the same button. If it was quicker, the handler to
	-- replace is the one its wrapper keeps and falls back to.
	local slot = "DoClick"
	if button.__AppearanceModWrapped and isfunction(button.__AppearanceOriginalDoClick) then
		slot = "__AppearanceOriginalDoClick"
	end

	local stock = button[slot]
	local function wrapped(self, ...)
		local ok, err = pcall(openGlovesMenu, main)
		if not ok then
			-- back to the original menu for good; it lists the CS:GO gloves by name
			report("glove menu switched off", err)
			main.zcg_plain = true
			if button.DoClick == wrapped then button.DoClick = stock end
			if button.__AppearanceOriginalDoClick == wrapped then button.__AppearanceOriginalDoClick = stock end
			return stock(self, ...)
		end
	end
	button[slot] = wrapped
	return true
end

-- ---------------------------------------------------------------------------------------------
-- 3. the Z-City Appearance Mod
-- ---------------------------------------------------------------------------------------------
-- That addon replaces the drop-down menus of the editor with windows of 3D previews. It wraps
-- the "Gloves" button a moment after the editor is built; a click then opens "Select Gloves"
-- with one preview - a whole player model - per entry of hg.Appearance.Bodygroups.HANDS, three
-- in a row. That is no place for 81 gloves which all look like bare hands there, so the button
-- is wrapped once more, on top of the mod:
--   * while the mod builds its window the CS:GO gloves are out of the list;
--   * the window gets one more tile, the first one, which opens the picker.
-- Whatever goes wrong ends in the "plain" mode (main.zcg_plain): the mod lists the gloves by
-- name like any other entry, and they can still be chosen.

-- shown on the tile while no CS:GO glove is selected
local MOD_TILE_ICONS = { "moto_2", "sport_5", "specialist_10", "handwrap_12" }

-- calls fn(...) while the CS:GO gloves are not in the list of hand bodygroups;
-- returns true and the first result of fn, or false and the error
local function withoutGloves(fn, ...)
	local groups = istable(hg) and istable(hg.Appearance) and hg.Appearance.Bodygroups
	local hands = istable(groups) and groups.HANDS
	local taken = {}
	for sex = 1, 2 do
		local list = istable(hands) and hands[sex]
		if istable(list) then
			for name, data in pairs(list) do
				if istable(data) and data.ZCG then taken[#taken + 1] = { list, name, data } end
			end
		end
	end
	for _, entry in ipairs(taken) do entry[1][entry[2]] = nil end

	local count, args = select("#", ...), { ... }
	local ok, result = xpcall(function() return fn(unpack(args, 1, count)) end, debug.traceback)

	for _, entry in ipairs(taken) do
		if entry[1][entry[2]] == nil then entry[1][entry[2]] = entry[3] end
	end
	return ok, result
end

-- the grid of tiles in a window of the mod (a DGrid on the canvas of a scroll panel)
local function findGrid(panel, depth)
	for _, child in ipairs(panel:GetChildren()) do
		if isfunction(child.AddItem) and isfunction(child.GetItems) and isfunction(child.SetCols) then
			return child
		end
		if depth < 5 then
			local grid = findGrid(child, depth + 1)
			if grid then return grid end
		end
	end
	return nil
end

local function closeModWindow(frame)
	if not IsValid(frame) then return end
	-- DFrame:Close() also runs the mod's OnClose, which puts the camera back
	if isfunction(frame.Close) then frame:Close() else frame:Remove() end
end

-- returns true when the window has the tile
local function addModTile(main, frame)
	if IsValid(frame.zcg_tile) then return true end
	local grid = findGrid(frame, 0)
	if not grid then return false end
	setupFonts()

	-- as large as the tiles of the mod
	local w, h = math.floor(ScreenScale(66)), math.floor(ScreenScale(62))
	local items = grid:GetItems()
	local first = istable(items) and items[1]
	if ispanel(first) and IsValid(first) and first:GetWide() > 0 and first:GetTall() > 0 then
		w, h = first:GetWide(), first:GetTall()
	end

	local title = Config.MenuText or "CS:GO gloves..."
	local tile = vgui.Create("DButton")
	tile:SetText("")
	tile:SetSize(w, h)

	function tile:Paint(tw, th)
		local current = selectedVariant(main)
		draw.RoundedBox(4, 0, 0, tw, th, self:IsHovered() and clrTileHover or clrTile)

		local line = math.max(11, math.floor(ScreenScale(7)))
		local lines = current and 2 or 1
		local size = math.max(8, math.min(tw - 8, th - line * lines - 8))
		local x, y = math.floor((tw - size) / 2), 4

		surface.SetDrawColor(255, 255, 255, 255)
		if current then
			-- the glove that is selected
			local icon = iconOf(current)
			if icon then
				surface.SetMaterial(icon)
				surface.DrawTexturedRect(x, y, size, size)
			end
		else
			-- four gloves out of the collection
			local half = math.floor(size / 2)
			for i, id in ipairs(MOD_TILE_ICONS) do
				local variant = ZCG.ByID[id]
				local icon = variant and iconOf(variant)
				if icon then
					surface.SetMaterial(icon)
					surface.DrawTexturedRect(x + ((i - 1) % 2) * half, y + math.floor((i - 1) / 2) * half, half, half)
				end
			end
		end

		local ty = th - line * lines - 2
		draw.SimpleText(title, "ZCG_Label", tw / 2, ty, clrText, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		if current then
			draw.SimpleText(shortName(current), "ZCG_Label", tw / 2, ty + line, clrDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			surface.SetDrawColor(clrSelected)
			surface.DrawOutlinedRect(0, 0, tw, th, 2)
		end
	end

	function tile:DoClick()
		-- the window of the mod goes, the picker comes
		closeModWindow(frame)
		local ok, err = pcall(openPicker, main)
		if not ok then
			report("glove picker failed", err)
			closePicker(main)
			main.zcg_plain = true
		end
	end

	grid:AddItem(tile)
	-- the first tile: the window shows fewer than three rows without scrolling
	items = grid:GetItems()
	if istable(items) and #items > 1 and items[#items] == tile then
		table.remove(items)
		table.insert(items, 1, tile)
		grid:InvalidateLayout()
	end

	frame.zcg_tile = tile
	return true
end

local function wrapModButton(main, button)
	local inner = button.DoClick -- the wrapper of the mod

	local function wrapped(self, ...)
		if main.zcg_plain then return inner(self, ...) end
		closePicker(main)

		local ok, menu = withoutGloves(inner, self, ...)
		if not ok then
			report("gloves window of the Appearance Mod", menu)
			return nil
		end
		-- no window: the mod fell back to the menu below it (openGlovesMenu)
		if not (ispanel(menu) and IsValid(menu)) then return menu end

		local done, added = pcall(addModTile, main, menu)
		if done and added then return menu end

		-- no tile: the window once more, this time with every glove listed by name
		if not done then
			report("tile in the gloves window of the Appearance Mod", added)
		else
			ZCG.Print("the gloves window of the Appearance Mod is not the one this addon knows - "
				.. "the CS:GO gloves are listed there by name.")
		end
		main.zcg_plain = true
		pcall(closeModWindow, menu)
		return inner(self, ...)
	end

	button.zcg_mod = wrapped
	button.DoClick = wrapped
end

-- gets on top of the mod's wrapper as soon as there is one
local function attachMod(main, viewer)
	local button = findGlovesButton(viewer)
	if not button or not button.__AppearanceModWrapped then return end
	if button.zcg_mod ~= nil and button.DoClick == button.zcg_mod then return end
	wrapModButton(main, button)
end

-- ---------------------------------------------------------------------------------------------
-- 4. the older body groups (Torso, Legs/Boots) inside the windows of the Appearance Mod
-- ---------------------------------------------------------------------------------------------
-- ZCITY Clothing+ puts two buttons into the editor, "Torso" and "Legs/Boots", with plain lists of
-- its body groups (TORSO, LEGS). The Appearance Mod has windows with previews for its own groups
-- (the cog buttons next to Jacket / Pants / Boots). Here the two buttons are taken away and
-- their choices are shown inside those windows, as a part of their own under the heading LEGACY,
-- below the choices of the Appearance Mod (heading NEW).
local OLD_BUTTONS = { ["Torso"] = true, ["Legs/Boots"] = true }
local WINDOWS = { ["Select Jacket Bodygroup"] = "main", ["Select Pants Bodygroup"] = "pants", ["Select Boots Bodygroup"] = "boots" }
local CAMERAS = {
	main = { Vector(70, 0, 45), Vector(0, 0, 46), 25 },
	pants = { Vector(70, 0, 25), Vector(0, 0, 15), 30 },
	boots = { Vector(40, -50, 30), Vector(7, 0, 0), 14 },
}
local clrPart = Color(26, 26, 38, 255)
local clrPartOn = Color(10, 130, 10, 255)
local clrPartBorder = Color(100, 100, 120, 200)

local function hideOldButtons(viewer)
	for _, child in ipairs(viewer:GetChildren()) do
		if not child.zcg_old and isfunction(child.GetText) and OLD_BUTTONS[child:GetText() or ""] then
			child.zcg_old = true
			child:SetVisible(false)
			child.Think = function(self) if self:IsVisible() then self:SetVisible(false) end end
		end
	end
end

local function heading(parent, text, z)
	local label = vgui.Create("DLabel", parent)
	label:SetFont("ZCG_Label")
	label:SetText(text)
	label:SetTextColor(clrDim)
	label:Dock(TOP)
	label:DockMargin(4, 4, 0, 2)
	label:SetTall(math.floor(ScreenScale(9)))
	label:SetZPos(z)
	return label
end

-- the preview of one part: the model of the editor as it is dressed now, with this part on
local function partTile(main, frame, part, item)
	local source = main.zcg_viewer
	local tile = vgui.Create("DButton")
	tile:SetText("")
	tile:SetSize(ScreenScale(66), ScreenScale(62))

	local mdl = vgui.Create("DModelPanel", tile)
	mdl:Dock(FILL)
	mdl:DockMargin(2, 2, 2, 10)
	local from = IsValid(source) and source.Entity
	if IsValid(from) then mdl:SetModel(from:GetModel()) end
	mdl:SetAnimated(false)
	function mdl:RunAnimation() end
	local camera = CAMERAS[part]
	mdl:SetCamPos(camera[1])
	mdl:SetLookAt(camera[2])
	mdl:SetFOV(camera[3])
	function mdl:LayoutEntity(ent)
		if not IsValid(ent) then return end
		ent:SetAngles(Angle(0, 0, 0))
		local now = IsValid(source) and source.Entity
		if IsValid(now) and now ~= ent then
			for slot = 0, 31 do
				local name = now:GetSubMaterial(slot) or ""
				if name == ZCG.HideMaterial() then name = "" end -- (hands hidden under a glove)
				ent:SetSubMaterial(slot, name ~= "" and name or nil)
			end
			for _, group in ipairs(now:GetBodyGroups() or {}) do
				ent:SetBodygroup(group.id, now:GetBodygroup(group.id) or 0)
			end
			if now.GetPlayerColor then
				local colour = now:GetPlayerColor()
				ent.GetPlayerColor = function() return colour end
			end
		end
		ent:SetBodygroup(item.group, item.index)
	end

	local label = vgui.Create("DLabel", tile)
	label:SetPos(0, ScreenScale(50))
	label:SetSize(ScreenScale(66), ScreenScale(10))
	label:SetFont("ZCity_Tiny")
	label:SetText(item.name)
	label:SetTextColor(clrText)
	label:SetContentAlignment(8)
	label:SetMouseInputEnabled(false)

	local function selected()
		local groups = istable(main.AppearanceTable) and main.AppearanceTable.ABodygroups
		return istable(groups) and groups[item.key] == item.name
	end
	function tile:Paint(w, h)
		draw.RoundedBox(4, 0, 0, w, h, selected() and clrPartOn or clrPart)
		local hovered = vgui.GetHoveredPanel()
		if hovered == self or hovered == mdl then
			surface.SetDrawColor(clrText)
		else
			surface.SetDrawColor(clrPartBorder)
		end
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	function tile:DoClick()
		local appearance = main.AppearanceTable
		if istable(appearance) then
			appearance.ABodygroups = appearance.ABodygroups or {}
			appearance.ABodygroups[item.key] = item.name
		end
		surface.PlaySound("player/weapon_draw_0" .. math.random(2, 5) .. ".wav")
		if IsValid(frame) then frame:Close() end
	end
	function mdl:DoClick() tile:DoClick() end
	return tile
end

local function extendWindow(main, frame, part)
	local source = main.zcg_viewer
	local ent = IsValid(source) and source.Entity
	if not IsValid(ent) or not istable(main.AppearanceTable) then return end
	local items, has = ZCG.LegacyParts(part, ent, main.AppearanceTable)

	local scroll
	for _, child in ipairs(frame:GetChildren()) do
		if isfunction(child.GetCanvas) then scroll = child break end
	end
	if not scroll then return end
	local cols = 3
	for _, child in ipairs(scroll:GetCanvas():GetChildren()) do
		if isfunction(child.GetCols) then
			cols = child:GetCols() or cols
			child:SetZPos(1)
		end
	end

	setupFonts()
	scroll:AddItem(heading(scroll, "NEW", 0))
	scroll:AddItem(heading(scroll, "LEGACY", 2))
	if #items == 0 then
		scroll:AddItem(heading(scroll, has and "No parts for this model." or "This model has no LEGACY parts.", 3))
		return
	end
	local grid = vgui.Create("DGrid", scroll)
	grid:Dock(TOP)
	grid:SetZPos(3)
	grid:SetCols(cols)
	grid:SetColWide(ScreenScale(68))
	grid:SetRowHeight(ScreenScale(66))
	for _, item in ipairs(items) do grid:AddItem(partTile(main, frame, part, item)) end
	scroll:AddItem(grid)
end

local function titleOf(panel)
	if not isfunction(panel.GetTitle) then return nil end
	local ok, title = pcall(panel.GetTitle, panel)
	return ok and isstring(title) and title or nil
end

-- looks for a window of the Appearance Mod that has just been opened
local function watchWindows(main)
	if not (vgui.GetWorldPanel and IsValid(vgui.GetWorldPanel())) then return end
	for _, frame in ipairs(vgui.GetWorldPanel():GetChildren()) do
		if not frame.zcg_parts then
			local title = titleOf(frame)
			if title then
				for prefix, part in pairs(WINDOWS) do
					if string.sub(title, 1, #prefix) == prefix then
						frame.zcg_parts = true
						local ok, err = pcall(extendWindow, main, frame, part)
						if not ok then report("appearance editor, LEGACY parts", err) end
						break
					end
				end
			end
		end
	end
end

hook.Add("Think", "zcg_legacy_parts", function()
	local open = rawget(_G, "zpan")
	if not (ispanel(open) and IsValid(open)) or not IsValid(open.zcg_viewer) then return end
	watchWindows(open)
end)

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

			main.zcg_viewer = child
			-- (only next to the windows of the Appearance Mod, where their choices go: without
			-- it the two buttons are the only way to them)
			local AP = hg and hg.Appearance
			if AP and (AP.OpenClothesMenu or AP.OpenFacemapMenu) then pcall(hideOldButtons, child) end

			-- the Appearance Mod wraps the button later than this addon does
			if not child.zcg_mod_failed then
				local ok, err = pcall(attachMod, main, child)
				if not ok then
					child.zcg_mod_failed = true
					report("appearance editor, Appearance Mod", err)
				end
			end
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
hook.Add("InitPostEntity", "zcg_editor", hookEditorClass)

-- the Appearance Mod runs this hook right after it has wrapped the buttons of a window
hook.Add("HG_AppearanceMenuReady", "zcg_editor", function(panel)
	if not (ispanel(panel) and IsValid(panel)) then return end
	local ok, err = pcall(ZCG.AttachEditor, panel)
	if not ok then report("appearance editor", err) end
end)

-- Safety net: the editor class is registered late (and again on a Lua refresh), and a window may
-- already be open; "zpan" is the global Z-City keeps the open editor in.
timer.Create("zcg_editor", 0.5, 0, function()
	hookEditorClass()
	local open = rawget(_G, "zpan")
	if ispanel(open) and IsValid(open) then
		local ok, err = pcall(ZCG.AttachEditor, open)
		if not ok then report("appearance editor", err) end
	end
end)
