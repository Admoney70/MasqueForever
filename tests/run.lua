-- Usage: lua5.1 tests/run.lua   (from the repository root)
package.path = "./tests/?.lua;" .. package.path
local M = require("wowmock")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function near(a, b, msg)
	if math.abs(a - b) > 1e-6 then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

-- Load the add-on in TOC order.
local ns = {}
local ADDON = "!Guise"
for line in io.lines("!Guise.toc") do
	if line ~= "" and not line:match("^#") then
		local path = line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk(ADDON, ns)
	end
end

local function fire(event, ...)
	for _, f in ipairs(M.frames) do
		local h = f._scripts.OnEvent
		if h then h(f, event, ...) end
	end
end

fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
M.RunTimers()

local MSQ = LibStub("Masque")

test("library registered", function()
	assert(MSQ, "Masque API missing")
	assert(MSQ.Group and MSQ.AddSkin and MSQ.GetSkin, "API methods missing")
	eq(_G.Guise, MSQ)
end)

test("database created", function()
	assert(GuiseDB and GuiseDB.Groups, "no db")
	eq(GuiseDB.Blizzard, true)
end)

test("built-in skins", function()
	local list = ns.SkinList()
	eq(list[1], "Blizzard")
	for _, id in ipairs({ "Classic", "Clean", "Zoomed" }) do assert(MSQ:GetSkin(id), id) end
	local id = MSQ:GetDefaultSkin()
	eq(id, "Classic")
end)

-- The skin's frame is drawn on a texture Guise owns (the game's is hidden).
local function N(b) return ns.GetButtonRegion(b, "Normal") end

test("blizzard bars skinned at login", function()
	-- ActionButton1 didn't exist at login in this run; create and re-run.
	local b = M.NewActionButton("ActionButton1", 45)
	ns.SkinBlizzard() -- no-op: already done
	local g = MSQ:Group("Blizzard", "Action Bar 1")
	g:AddButton(b, nil, "Action")
	local st = ns.state[b]
	assert(st and st.active, "not active")
	eq(st.skinID, "Classic")
	-- Classic Normal: 66x66 scaled by 45/36
	local n = N(b)
	assert(n ~= b:GetNormalTexture(), "own normal texture")
	eq(b:GetNormalTexture():GetAlpha(), 0, "game normal hidden")
	eq(n:GetTexture(), [[Interface\Buttons\UI-Quickslot2]])
	near(n._w, 66 * 45 / 36, "normal width")
	-- Blizzard mask removed, slot art hidden
	assert(not b.icon._masks[b.IconMask], "icon still masked")
	eq(b.SlotBackground:GetAlpha(), 0)
	-- backdrop created
	local bd = g:GetLayer(b, "Backdrop")
	assert(bd and bd:IsShown(), "backdrop missing")
end)

test("button skinned and restored", function()
	local b = M.NewActionButton("TestButton", 36)
	local n = b:GetNormalTexture()
	local origAtlas = n:GetAtlas()
	local g = MSQ:Group("TestAddon", "Bar")
	g:AddButton(b)
	eq(N(b):GetTexture(), [[Interface\Buttons\UI-Quickslot2]])
	eq(b.HotKey:GetJustifyH(), "RIGHT")

	ns.SetOption(g, "Inherit", false)
	ns.SetOption(g, "SkinID", "Blizzard")
	M.RunTimers()
	eq(n:GetAtlas(), origAtlas, "atlas restored")
	near(n._w, 46, "size restored")
	eq(n:GetAlpha(), 1, "game normal visible again")
	eq(N(b), n, "own normal texture retired")
	eq(b.HotKey:GetJustifyH(), "CENTER", "justify restored")
	assert(b.icon._masks[b.IconMask], "mask restored")
	eq(b.SlotBackground:GetAlpha(), 1, "slot bg restored")
	eq(g:GetLayer(b, "Backdrop"):IsShown(), false, "backdrop hidden")
end)

test("hooks keep skin when game swaps art", function()
	local b = M.NewActionButton("HookButton", 36)
	local g = MSQ:Group("TestAddon", "Hooks")
	g:AddButton(b)
	b:SetNormalAtlas("UI-HUD-ActionBar-IconFrame-AddRow")
	eq(N(b):GetTexture(), [[Interface\Buttons\UI-Quickslot2]], "re-applied")
	eq(b:GetNormalTexture():GetAlpha(), 0, "game art kept hidden")
	-- remove skin: restores the art the game set most recently
	g:RemoveButton(b)
	eq(b:GetNormalTexture():GetAtlas(), "UI-HUD-ActionBar-IconFrame-AddRow")
	-- after removal hooks are inert
	b:SetNormalAtlas("Other")
	eq(b:GetNormalTexture():GetAtlas(), "Other")
end)

test("inheritance from global", function()
	local b = M.NewActionButton("InheritButton", 36)
	local g = MSQ:Group("Another", "Bar")
	g:AddButton(b)
	ns.SetOption(ns.root, "SkinID", "Zoomed")
	M.RunTimers()
	eq(ns.state[b].skinID, "Zoomed")
	near(b.icon._coords[1], 0.07, "zoomed coords")
	eq(b:GetNormalTexture():GetAlpha(), 0, "normal hidden in Zoomed")
	eq(ns.state[b].created.Normal:IsShown(), false, "own normal hidden in Zoomed")
	ns.SetOption(ns.root, "SkinID", "Classic")
	M.RunTimers()
	eq(N(b):IsShown(), true, "normal visible again")
	eq(N(b):GetTexture(), [[Interface\Buttons\UI-Quickslot2]])
end)

test("callbacks fire", function()
	local g = MSQ:Group("CB", "Bar")
	local got
	g:RegisterCallback(function(arg, group, option, value) got = { arg, option, value } end, "ARG")
	ns.SetOption(ns.root, "Gloss", true)
	eq(got and got[1], "ARG")
	eq(got[2], "Gloss")
	eq(got[3], true)
	ns.SetOption(ns.root, "Gloss", false)
end)

test("signature skips redundant ReSkin", function()
	local b = M.NewActionButton("SigButton", 36)
	local g = MSQ:Group("Sig", "Bar")
	g:AddButton(b)
	local n = N(b)
	local calls = 0
	local orig = n.SetSize
	n.SetSize = function(...) calls = calls + 1 return orig(...) end
	for _ = 1, 100 do g:ReSkin() end
	eq(calls, 0, "no work for unchanged buttons")
	g:ReSkin(true)
	assert(calls > 0, "forced reskin did work")
end)

test("combat deferral for protected buttons", function()
	local b = M.NewActionButton("CombatButton", 36)
	M.combat = true
	local g = MSQ:Group("Combat", "Bar")
	g:AddButton(b)
	eq(b:GetNormalTexture():GetAtlas(), "UI-HUD-ActionBar-IconFrame", "untouched in combat")
	M.combat = false
	fire("PLAYER_REGEN_ENABLED")
	eq(N(b):GetTexture(), [[Interface\Buttons\UI-Quickslot2]], "skinned after combat")
end)

test("third-party skin with template and type variants", function()
	MSQ:AddSkin("Test Skin", {
		Template = "Classic",
		Normal = { Texture = "custom", Width = 40, Height = 40 },
		Border = { Texture = "border", Debuff = { Texture = "debuff" } },
	})
	local aura = M.NewActionButton("AuraButton", 36)
	local g = MSQ:Group("Auras", "Debuffs")
	ns.SetOption(g, "Inherit", false)
	ns.SetOption(g, "SkinID", "Test Skin")
	g:AddButton(aura, nil, "Debuff")
	M.RunTimers()
	eq(N(aura):GetTexture(), "custom")
	eq(aura.Border:GetTexture(), "debuff")
	eq(aura:GetPushedTexture():GetTexture(), [[Interface\Buttons\UI-Quickslot-Depress]], "from template")
end)

test("border keeps game colour", function()
	local b = M.NewActionButton("BorderButton", 36)
	b.Border:SetVertexColor(0, 1, 0, 0.35)
	MSQ:Group("Border", "Bar"):AddButton(b)
	local r, g = b.Border:GetVertexColor()
	eq(r, 0); eq(g, 1)
end)

test("unknown skin falls back to default", function()
	local b = M.NewActionButton("FallbackButton", 36)
	local g = MSQ:Group("Fallback", "Bar")
	ns.SetOption(g, "Inherit", false)
	ns.SetOption(g, "SkinID", "Not Installed")
	g:AddButton(b)
	eq(ns.state[b].skinID, "Classic")
end)

test("disable parent unskins children", function()
	local b = M.NewActionButton("DisableButton", 36)
	local g = MSQ:Group("Dis", "Bar")
	g:AddButton(b)
	ns.SetOption(MSQ:Group("Dis"), "Disabled", true)
	M.RunTimers()
	eq(ns.state[b].active, false)
	ns.SetOption(MSQ:Group("Dis"), "Disabled", false)
	M.RunTimers()
	eq(ns.state[b].active, true)
end)

test("resize triggers rescale", function()
	local b = M.NewActionButton("ResizeButton", 36)
	MSQ:Group("Resize", "Bar"):AddButton(b)
	b:SetSize(72, 72)
	M.RunTimers()
	near(N(b)._w, 132, "rescaled")
end)

test("slash commands", function()
	SlashCmdList.GUISE("skin zoomed")
	eq(ns.GetOption(ns.root, "SkinID"), "Zoomed")
	SlashCmdList.GUISE("skin classic")
	SlashCmdList.GUISE("skins")
end)

test("un-inheriting copies colours", function()
	local parent = MSQ:Group("Col")
	ns.SetOption(parent, "Inherit", false)
	parent:SetColor("Normal", 1, 0, 0, 1)
	local child = MSQ:Group("Col", "Bar")
	ns.SetOption(child, "Inherit", false)
	child:SetColor("Normal", 0, 1, 0, 1)
	local r = parent:GetColor("Normal")
	eq(r, 1, "parent colour untouched")
end)

test("aura buttons with secret layout values", function()
	-- Mirrors Blizzard aura container buttons in Midnight-era clients: some
	-- regions report secret anchors and the button size is secret.
	local b = M.NewActionButton(nil, 20)
	b.cooldown.GetNumPoints = function() return M.SECRET end
	b.Count:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.Count.GetPoint = function() return "CENTER", M.SECRET, "CENTER", 0, 0 end
	b.GetSize = function() return M.SECRET, M.SECRET end
	local g = MSQ:Group("MiniAurasTest", "Important Auras")
	g:AddButton(b, nil, "Aura")
	local st = ns.state[b]
	assert(st.active, "skinned")
	assert(st.broken.Cooldown and st.broken.Count, "restricted layers skipped")
	eq(N(b):GetTexture(), [[Interface\Buttons\UI-Quickslot2]], "other layers still skinned")
	g:ReSkin(true)
	ns.SetOption(MSQ:Group("MiniAurasTest"), "Disabled", true)
	M.RunTimers()
	eq(st.active, false, "unskins cleanly")
end)

test("new groups while the options panel is open", function()
	local panel
	for _, f in ipairs(M.frames) do if f.name == "Guise" then panel = f end end
	assert(panel, "panel built")
	panel:Show()
	panel._scripts.OnShow(panel)
	for i = 1, 5 do MSQ:Group("PanelTest", "Group " .. i) end
	M.RunTimers()
	panel:Hide()
end)

test("Masque-format skin pack features", function()
	-- Structure modelled on current Masque skin packs.
	MSQ:AddSkin("Pack", {
		Shape = "Square",
		Backdrop = { Texture = [[Interface\AddOns\Masque\Textures\Backdrop\Action]] },
		Icon = { Backpack = [[Interface\Icons\INV_Misc_Bag_08]], TexCoords = { 0.02, 0.98, 0.02, 0.98 } },
		Normal = { Texture = "pack-normal", Width = 42, Height = 42 },
		Pushed = { Color = { 0, 0, 0, 0.5 }, UseColor = true },
		Checked = { Texture = "pack-border", Width = 42, Height = 42 },
		SlotHighlight = "Checked",
		Border = { Texture = "pack-border", Width = 42, Height = 42 },
		DebuffBorder = { Texture = "pack-debuff" },
		IconBorder = "Border",
		HotKey = { OffsetX = -2, OffsetY = -2 },
		Cooldown = {
			Texture = [[Interface\AddOns\Masque\Textures\Square\Mask]],
			EdgeTexture = [[Interface\AddOns\Masque\Textures\Square\Edge]],
			Color = { 0, 0, 0, 0.7 },
		},
	})
	local g = MSQ:Group("PackTest", "Bar")
	ns.SetOption(g, "Inherit", false)
	ns.SetOption(g, "SkinID", "Pack")

	local b = M.NewActionButton("PackButton", 36)
	g:AddButton(b, nil, "Action")
	eq(b:GetPushedTexture():GetTexture(), "color", "solid colour fill")
	eq(b:GetPushedTexture()._fill[4], 0.5)
	eq(b:GetPushedTexture()._color[4], 1, "no double tint")
	local hk = b.HotKey
	local p, _, rp, x = hk:GetPoint(1)
	eq(p, "TOPRIGHT", "default text anchor"); eq(rp, "TOPRIGHT"); eq(x, -2)
	eq(hk:GetJustifyH(), "RIGHT")
	eq(b.cooldown._swipeTex, [[Interface\Buttons\WHITE8x8]], "Masque texture remapped")
	eq(g:GetLayer(b, "Backdrop"):GetTexture(), [[Interface\AddOns\!Guise\Textures\Backdrop]])

	local d = M.NewActionButton("PackDebuff", 36)
	g:AddButton(d, nil, "Debuff")
	eq(d.Border:GetTexture(), "pack-debuff", "DebuffBorder layer")

	local item = M.NewActionButton("PackItem", 36)
	item.IconBorder = item:CreateTexture()
	item.SlotHighlightTexture = item:CreateTexture()
	g:AddButton(item, nil, "Item")
	eq(item.IconBorder:GetTexture(), "pack-border", "string alias")
	eq(item.SlotHighlightTexture:GetTexture(), "pack-border", "string alias to Checked")
end)

test("custom frame colour (Caith-style Normal layer)", function()
	MSQ:AddSkin("Framed", {
		Normal = { Texture = "framed-normal", Color = { 0.3, 0.3, 0.3, 1 }, Width = 42, Height = 42 },
		Border = { Texture = "framed-border", Width = 42, Height = 42 },
	})
	local g = MSQ:Group("ColorTest", "Bar")
	ns.SetOption(g, "Inherit", false)
	ns.SetOption(g, "SkinID", "Framed")
	local b = M.NewActionButton("ColorButton", 36)
	b.Border:SetVertexColor(0, 1, 0, 0.35) -- game's "equipped" green
	g:AddButton(b)
	local n = N(b)
	eq(n._color[1], 0.3, "skin colour by default")
	-- The game recolours its normal texture on usable/mana changes; that
	-- must not touch the skin's frame.
	b:GetNormalTexture():SetVertexColor(0.5, 0.5, 1, 1)
	eq(n._color[1], 0.3, "game recolour does not leak")
	local r = g:GetColor("Normal")
	eq(r, 0.3, "GetColor reports skin colour")

	g:SetColor("Normal", 1, 0, 0, 1)
	M.RunTimers()
	eq(n._color[1], 1, "custom colour applied"); eq(n._color[2], 0)

	g:SetColor("Border", 0, 0, 1, 1)
	M.RunTimers()
	eq(b.Border._color[3], 1, "override beats game colour")
	g:SetColor("Border", nil)
	M.RunTimers()
	eq(b.Border._color[2], 1, "game colour restored after reset")

	g:SetColor("Normal", nil)
	M.RunTimers()
	eq(n._color[1], 0.3, "reset to skin colour")
end)

test("colour popup and picker", function()
	local panel
	for _, f in ipairs(M.frames) do if f.name == "Guise" then panel = f end end
	panel:Show()
	panel._scripts.OnShow(panel)
	local g = MSQ:Group("ColorTest", "Bar")
	ns.ShowColors(g)
	local popup = _G.GuiseColorPopup
	assert(popup and popup:IsShown(), "popup shown")
	local line = popup.lines[1]
	eq(line.layer, "Normal")
	eq(line.reset:IsEnabled(), false, "reset disabled without override")
	line.swatch._scripts.OnClick(line.swatch)
	ColorPickerFrame:Pick(0, 0.5, 1, 1)
	local r, gg, bb = g:GetColor("Normal")
	eq(r, 0); eq(gg, 0.5); eq(bb, 1)
	eq(line.reset:IsEnabled(), true, "reset enabled")
	ColorPickerFrame:Cancel()
	eq(g:GetColor("Normal"), 0.3, "cancel restores skin colour")
	line.swatch._scripts.OnClick(line.swatch)
	ColorPickerFrame:Pick(1, 1, 0, 1)
	line.reset._scripts.OnClick(line.reset)
	eq(g:GetColor("Normal"), 0.3, "reset button")
	panel._scripts.OnHide(panel)
	eq(popup:IsShown(), false, "popup closes with panel")
	panel:Hide()
end)

local function LoadCoreWith(setup)
	M.addons.Masque = 2
	setup()
	local other = {}
	LibStub.minors.Masque = nil
	assert(loadfile("Core.lua"))("!Guise", other)
	M.addons.Masque, M.metadata = nil, {}
	M.deps, M.titles = {}, {}
	return other
end

test("stub recognised by its dependency on Guise", function()
	-- Metadata unavailable for unloaded add-ons: must still be recognised.
	local other = LoadCoreWith(function() M.deps.Masque = { "!Guise" } end)
	assert(not other.disabled, other.disabled)
end)

test("stub recognised by its title", function()
	local other = LoadCoreWith(function() M.titles.Masque = "Guise: Masque skin loader" end)
	assert(not other.disabled, other.disabled)
end)

test("stub recognised by its metadata", function()
	local other = LoadCoreWith(function() M.metadata["Masque:X-Guise-Shim"] = "1" end)
	assert(not other.disabled, other.disabled)
end)

test("standing down is announced and /guise explains", function()
	local other = LoadCoreWith(function() M.titles.Masque = "Masque" end)
	assert(other.disabled, "real Masque should win")
	SlashCmdList.GUISE("")
end)

test("stands down when Masque is enabled", function()
	M.addons.Masque = 2
	local other = {}
	local oldLib = LibStub.libs.Masque
	local chunk = assert(loadfile("Core.lua"))
	chunk("!Guise", other)
	assert(other.disabled, "should stand down")
	eq(LibStub.libs.Masque, oldLib)
	M.addons.Masque = nil
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
