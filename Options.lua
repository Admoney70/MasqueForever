--[[
	Options.lua: Settings panel (Esc > Options > AddOns > Guise) and the
	/guise slash command.
]]

local _, ns = ...
if ns.disabled then return end

local pairs, ipairs, sort, format, wipe = pairs, ipairs, table.sort, string.format, wipe

local ROW_HEIGHT = 30
local INDENT = 18

local panel, category, scrollChild
local rows = {}

----------------------------------------------------------------------
-- Group ordering: depth-first, alphabetical within each level
----------------------------------------------------------------------

local function SortedChildren(group)
	local list = {}
	for _, child in pairs(group.SubList) do list[#list + 1] = child end
	sort(list, function(a, b) return (a.Name or a.ID) < (b.Name or b.ID) end)
	return list
end

local function Flatten(group, depth, out)
	out[#out + 1] = { group = group, depth = depth }
	for _, child in ipairs(SortedChildren(group)) do
		Flatten(child, depth + 1, out)
	end
	return out
end

----------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------

local function CreateCheck(parent, label, tooltip, onClick)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", cb, "RIGHT", 0, 1)
	text:SetText(label)
	cb.label = text
	cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	if tooltip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", GameTooltip_Hide)
	end
	return cb
end

local function SetCheckEnabled(cb, enabled)
	if enabled then cb:Enable() else cb:Disable() end
	cb.label:SetFontObject(enabled and "GameFontHighlightSmall" or "GameFontDisableSmall")
end

-- Modern dropdown (11.0+ menu API), with a click-to-cycle fallback.
local function CreateSkinPicker(parent, row)
	local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dd and dd.SetupMenu then
		dd:SetWidth(140)
		dd:SetupMenu(function(_, root)
			for _, id in ipairs(ns.SkinList()) do
				root:CreateRadio(id,
					function() return row.group ~= nil and ns.GetOption(row.group, "SkinID") == id end,
					function()
						if not row.group then return end
						ns.SetOption(row.group, "SkinID", id)
						ns.RefreshOptions()
					end)
			end
		end)
		function dd:Refresh() self:GenerateMenu() end
		return dd
	end

	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(140, 22)
	btn:SetScript("OnClick", function()
		if not row.group then return end
		local list = ns.SkinList()
		local current = ns.GetOption(row.group, "SkinID")
		local nextID = list[1]
		for i, id in ipairs(list) do
			if id == current then nextID = list[i % #list + 1] break end
		end
		ns.SetOption(row.group, "SkinID", nextID)
		ns.RefreshOptions()
	end)
	function btn:Refresh() self:SetText(row.group and ns.GetOption(row.group, "SkinID") or "") end
	return btn
end

local function CreateRow(index)
	local row = CreateFrame("Frame", nil, scrollChild)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", scrollChild, "RIGHT")

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.label:SetPoint("LEFT", 4, 0)
	row.label:SetWidth(160)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.skin = CreateSkinPicker(row, row)
	row.skin:SetPoint("LEFT", 168, 0)

	local function toggle(key)
		return function(value)
			if not row.group then return end
			ns.SetOption(row.group, key, value)
			ns.RefreshOptions()
		end
	end

	row.inherit = CreateCheck(row, "Inherit", "Use the parent group's settings.", toggle("Inherit"))
	row.inherit:SetPoint("LEFT", row.skin, "RIGHT", 6, 0)

	row.backdrop = CreateCheck(row, "Backdrop", "Show the skin's backdrop behind empty slots.", toggle("Backdrop"))
	row.backdrop:SetPoint("LEFT", row.inherit, "RIGHT", 44, 0)

	row.gloss = CreateCheck(row, "Gloss", "Show the skin's gloss overlay (if it has one).", toggle("Gloss"))
	row.gloss:SetPoint("LEFT", row.backdrop, "RIGHT", 56, 0)

	row.shadow = CreateCheck(row, "Shadow", "Show the skin's shadow (if it has one).", toggle("Shadow"))
	row.shadow:SetPoint("LEFT", row.gloss, "RIGHT", 38, 0)

	row.disabled = CreateCheck(row, "Off", "Leave these buttons unskinned.", function(value)
		if not row.group then return end
		ns.SetOption(row.group, "Disabled", value)
		ns.RefreshOptions()
	end)
	row.disabled:SetPoint("LEFT", row.shadow, "RIGHT", 46, 0)

	row.colors = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.colors:SetSize(60, 22)
	row.colors:SetText("Colors")
	row.colors:SetPoint("LEFT", row.disabled, "RIGHT", 28, 0)
	row.colors:SetScript("OnClick", function()
		if row.group then ns.ShowColors(row.group) end
	end)

	rows[index] = row
	return row
end

local function UpdateRow(row, entry)
	local group = entry.group
	row.group = group
	row.label:SetPoint("LEFT", 4 + entry.depth * INDENT, 0)
	row.label:SetWidth(160 - entry.depth * INDENT)

	local count = 0
	for _ in pairs(group.Buttons) do count = count + 1 end
	local name = group.Name or group.ID
	row.label:SetText(count > 0 and format("%s |cff808080(%d)|r", name, count) or name)

	local isRoot = group.Parent == nil
	local inherits = not isRoot and group.db.Inherit ~= false
	local parentOff = group.Parent and ns.IsGroupDisabled(group.Parent)

	row.inherit:SetShown(not isRoot)
	row.inherit:SetChecked(inherits)

	row.skin:Refresh()
	if inherits or parentOff then row.skin:Disable() else row.skin:Enable() end

	row.backdrop:SetChecked(ns.GetOption(group, "Backdrop"))
	row.gloss:SetChecked(ns.GetOption(group, "Gloss"))
	row.shadow:SetChecked(ns.GetOption(group, "Shadow"))
	local editable = not inherits and not parentOff
	SetCheckEnabled(row.backdrop, editable)
	SetCheckEnabled(row.gloss, editable)
	SetCheckEnabled(row.shadow, editable)

	row.disabled:SetChecked(group.db.Disabled and true or false)
	SetCheckEnabled(row.disabled, not parentOff)

	if editable then row.colors:Enable() else row.colors:Disable() end

	row:Show()
end

local function Refresh()
	if not panel or not panel:IsVisible() then return end
	local list = Flatten(ns.root, 0, {})
	for i, entry in ipairs(list) do
		UpdateRow(rows[i] or CreateRow(i), entry)
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	scrollChild:SetHeight(#list * ROW_HEIGHT)
end

-- Coalesced: add-ons can create dozens of groups in one frame.
local refreshQueued = false
function ns.RefreshOptions()
	if refreshQueued or not panel or not panel:IsVisible() then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		Refresh()
	end)
end

----------------------------------------------------------------------
-- Colours
----------------------------------------------------------------------

-- Layers worth colouring, in display order. "Normal" is the frame drawn
-- around each icon (the visible border in skins such as Caith).
local COLOR_LAYERS = {
	{ "Normal", "Frame / border" },
	{ "Backdrop", "Backdrop" },
	{ "Highlight", "Mouseover highlight" },
	{ "Checked", "Active (checked)" },
	{ "Pushed", "Pressed" },
	{ "Border", "Equipped / item border" },
	{ "Flash", "Attack flash" },
	{ "Gloss", "Gloss" },
	{ "Shadow", "Shadow" },
	{ "Cooldown", "Cooldown swipe" },
}

local colorPopup

local function HasOverride(group, layer)
	local colors = ns.GetOption(group, "Colors")
	return colors and colors[layer] ~= nil
end

local function OpenColorPicker(r, g, b, a, onChange, onCancel)
	if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
		ns.Print("The colour picker is not available.")
		return
	end
	local function changed()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		local na = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or a
		onChange(nr, ng, nb, na)
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b, opacity = a, hasOpacity = true,
		swatchFunc = changed,
		opacityFunc = changed,
		cancelFunc = onCancel,
	})
end

local function UpdateColorPopup()
	local popup = colorPopup
	local group = popup.group
	popup.title:SetText("Colors: " .. (group.Name or group.ID))
	for _, line in ipairs(popup.lines) do
		local r, g, b, a = group:GetColor(line.layer)
		line.swatch.color:SetColorTexture(r, g, b, a)
		local custom = HasOverride(group, line.layer)
		line.label:SetFontObject(custom and "GameFontHighlight" or "GameFontDisable")
		if custom then line.reset:Enable() else line.reset:Disable() end
	end
end

local function CreateColorPopup()
	local ok, popup = pcall(CreateFrame, "Frame", "GuiseColorPopup", panel, "BasicFrameTemplateWithInset")
	if not ok then
		popup = CreateFrame("Frame", "GuiseColorPopup", panel)
		local bg = popup:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
		local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT")
	end
	popup:SetSize(270, 66 + #COLOR_LAYERS * 24)
	popup:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -40)
	popup:SetFrameStrata("DIALOG")
	popup:EnableMouse(true)
	popup:Hide()

	popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	popup.title:SetPoint("TOP", 0, -5)

	local hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOM", 0, 10)
	hint:SetText("Greyed-out layers use the skin's own colour.")

	popup.lines = {}
	for i, entry in ipairs(COLOR_LAYERS) do
		local layer = entry[1]
		local line = { layer = layer }

		local swatch = CreateFrame("Button", nil, popup)
		swatch:SetSize(18, 18)
		swatch:SetPoint("TOPLEFT", 16, -30 - (i - 1) * 24)
		local edge = swatch:CreateTexture(nil, "BACKGROUND")
		edge:SetAllPoints()
		edge:SetColorTexture(0.6, 0.6, 0.6, 1)
		swatch.color = swatch:CreateTexture(nil, "ARTWORK")
		swatch.color:SetPoint("TOPLEFT", 1, -1)
		swatch.color:SetPoint("BOTTOMRIGHT", -1, 1)
		swatch:SetScript("OnClick", function()
			local group = popup.group
			local hadOverride = HasOverride(group, layer)
			local r, g, b, a = group:GetColor(layer)
			OpenColorPicker(r, g, b, a,
				function(nr, ng, nb, na)
					group:SetColor(layer, nr, ng, nb, na)
					UpdateColorPopup()
				end,
				function()
					if hadOverride then group:SetColor(layer, r, g, b, a) else group:SetColor(layer, nil) end
					UpdateColorPopup()
				end)
		end)
		line.swatch = swatch

		line.label = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line.label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
		line.label:SetText(entry[2])

		line.reset = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		line.reset:SetSize(56, 20)
		line.reset:SetText("Reset")
		line.reset:SetPoint("TOPRIGHT", -14, -29 - (i - 1) * 24)
		line.reset:SetScript("OnClick", function()
			popup.group:SetColor(layer, nil)
			UpdateColorPopup()
		end)

		popup.lines[i] = line
	end

	return popup
end

function ns.ShowColors(group)
	colorPopup = colorPopup or CreateColorPopup()
	colorPopup.group = group
	UpdateColorPopup()
	colorPopup:Show()
end

----------------------------------------------------------------------
-- Panel
----------------------------------------------------------------------

local function BuildPanel()
	panel = CreateFrame("Frame")
	panel.name = ns.title

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ns.title)

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetPoint("RIGHT", -16, 0)
	sub:SetJustifyH("LEFT")
	sub:SetText("Pick a skin for every group at once with Global, or untick Inherit on a group to style it separately. Skinning changes to bars are applied after combat.")

	local blizz = CreateCheck(panel, "Skin the Blizzard action bars and bag buttons",
		"Turn off if another add-on replaces the default bars.", function(value)
			ns.SetBlizzardEnabled(value)
			ns.RefreshOptions()
		end)
	blizz:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -8)
	panel.blizz = blizz

	local scrollTemplate = "ScrollFrameTemplate"
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, panel, scrollTemplate)
	if not ok then
		scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	end
	scroll:SetPoint("TOPLEFT", blizz, "BOTTOMLEFT", 2, -10)
	scroll:SetPoint("BOTTOMRIGHT", -30, 12)

	scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(640, 1)
	scroll:SetScrollChild(scrollChild)
	scroll:SetScript("OnSizeChanged", function(self, w) scrollChild:SetWidth(w) end)

	panel:SetScript("OnHide", function()
		if colorPopup then colorPopup:Hide() end
	end)

	panel:SetScript("OnShow", function()
		blizz:SetChecked(ns.db and ns.db.Blizzard)
		Refresh()
	end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, ns.title)
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function ns.OpenOptions()
	if InCombatLockdown() then
		ns.Print("Options can't be opened in combat.")
		return
	end
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

ns.On("PLAYER_LOGIN", BuildPanel)

----------------------------------------------------------------------
-- Slash command
----------------------------------------------------------------------

local function FindSkin(input)
	input = input:lower()
	for _, id in ipairs(ns.SkinList()) do
		if id:lower() == input then return id end
	end
end

local HELP = {
	"/guise - open the options panel",
	"/guise skins - list installed skins",
	"/guise skin <name> - use a skin everywhere",
	"/guise blizzard on|off - skin the default action bars",
	"/guise reset - forget all settings (reloads the UI)",
}

SLASH_GUISE1 = "/guise"
SlashCmdList.GUISE = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()

	if cmd == "" then
		ns.OpenOptions()
	elseif cmd == "skins" or cmd == "list" then
		ns.Print("Skins: " .. table.concat(ns.SkinList(), ", "))
	elseif cmd == "skin" then
		local id = FindSkin(rest)
		if not id then
			ns.Print(format("Unknown skin %q. Try /guise skins", rest))
			return
		end
		ns.SetOption(ns.root, "SkinID", id)
		ns.RefreshOptions()
		ns.Print("Global skin set to " .. id .. ".")
	elseif cmd == "blizzard" then
		local on = rest:lower() ~= "off"
		ns.SetBlizzardEnabled(on)
		ns.Print("Blizzard bar skinning " .. (on and "enabled." or "disabled."))
	elseif cmd == "reset" then
		wipe(ns.db.Groups)
		ns.db.Blizzard = true
		ReloadUI()
	else
		for _, line in ipairs(HELP) do ns.Print(line) end
	end
end
