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
	local n = b:GetNormalTexture()
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
	eq(n:GetTexture(), [[Interface\Buttons\UI-Quickslot2]])
	eq(b.HotKey:GetJustifyH(), "RIGHT")

	ns.SetOption(g, "Inherit", false)
	ns.SetOption(g, "SkinID", "Blizzard")
	M.RunTimers()
	eq(n:GetAtlas(), origAtlas, "atlas restored")
	near(n._w, 46, "size restored")
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
	eq(b:GetNormalTexture():GetTexture(), [[Interface\Buttons\UI-Quickslot2]], "re-applied")
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
	ns.SetOption(ns.root, "SkinID", "Classic")
	M.RunTimers()
	eq(b:GetNormalTexture():GetAlpha(), 1, "normal visible again")
	eq(b:GetNormalTexture():GetTexture(), [[Interface\Buttons\UI-Quickslot2]])
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
	local n = b:GetNormalTexture()
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
	eq(b:GetNormalTexture():GetTexture(), [[Interface\Buttons\UI-Quickslot2]], "skinned after combat")
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
	eq(aura:GetNormalTexture():GetTexture(), "custom")
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
	near(b:GetNormalTexture()._w, 132, "rescaled")
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
	eq(b:GetNormalTexture():GetTexture(), [[Interface\Buttons\UI-Quickslot2]], "other layers still skinned")
	g:ReSkin(true)
	ns.SetOption(MSQ:Group("MiniAurasTest"), "Disabled", true)
	M.RunTimers()
	eq(st.active, false, "unskins cleanly")
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
