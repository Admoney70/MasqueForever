--[[
	Built-in skins. All artwork is stock Blizzard art shipped with the game
	client, so no texture files are bundled.

	Sizes are for a 36x36 button; Guise scales every value to the actual
	button size.
]]

local _, ns = ...
if ns.disabled then return end

local WHITE = [[Interface\Buttons\WHITE8x8]]
local FULL = { 0, 1, 0, 1 }
local TRIM = { 0.07, 0.93, 0.07, 0.93 }

local TEXT = {
	HotKey = { Width = 36, JustifyH = "RIGHT", Point = "TOPRIGHT", OffsetX = -2, OffsetY = -3 },
	Count = { Width = 36, JustifyH = "RIGHT", Point = "BOTTOMRIGHT", OffsetX = -2, OffsetY = 2 },
	Name = { Width = 36, JustifyH = "CENTER", Point = "BOTTOM", OffsetY = 2 },
	Duration = { Width = 36, Point = "TOP", RelPoint = "BOTTOM", OffsetY = -2 },
}

local FRAME36 = { Width = 36, Height = 36 }

-- Debuff / temp-enchant borders shared by all skins.
local AURA_BORDERS = {
	Debuff = {
		Texture = [[Interface\Buttons\UI-Debuff-Overlays]],
		TexCoords = { 0.296875, 0.5703125, 0, 0.515625 },
		Width = 38, Height = 38,
	},
	Enchant = {
		Texture = [[Interface\Buttons\UI-TempEnchant-Border]],
		Width = 38, Height = 38,
	},
	Buff = { Hide = true },
}

local function Border(base)
	local t = {}
	for k, v in pairs(base) do t[k] = v end
	for k, v in pairs(AURA_BORDERS) do t[k] = v end
	return t
end

-- "Blizzard" is a pseudo-skin: selecting it leaves buttons exactly as the
-- game draws them.
ns.AddSkin("Blizzard", {
	Blizzard = true,
	Description = "The game's own button art (unskinned).",
})

-- The original 2004-era action button look, a natural fit for Forever.
ns.AddSkin("Classic", {
	Shape = "Square",
	Description = "The original Classic action button art.",
	Icon = { Width = 36, Height = 36, TexCoords = FULL },
	Backdrop = {
		Texture = [[Interface\Buttons\UI-Quickslot]],
		Width = 66, Height = 66, OffsetY = -1,
	},
	Normal = {
		Texture = [[Interface\Buttons\UI-Quickslot2]],
		Width = 66, Height = 66, OffsetY = -1,
	},
	Pushed = { Texture = [[Interface\Buttons\UI-Quickslot-Depress]] },
	Highlight = { Texture = [[Interface\Buttons\ButtonHilight-Square]], BlendMode = "ADD" },
	Checked = { Texture = [[Interface\Buttons\CheckButtonHilight]], BlendMode = "ADD" },
	SpellHighlight = { Texture = [[Interface\Buttons\CheckButtonHilight]], BlendMode = "ADD" },
	Disabled = { Hide = true },
	Flash = { Texture = [[Interface\Buttons\UI-QuickslotRed]] },
	Border = Border({
		Texture = [[Interface\Buttons\UI-ActionButton-Border]],
		BlendMode = "ADD", Width = 62, Height = 62,
	}),
	Cooldown = FRAME36,
	ChargeCooldown = FRAME36,
	AutoCastShine = FRAME36,
	AutoCastOverlay = FRAME36,
	HotKey = TEXT.HotKey,
	Count = TEXT.Count,
	Name = TEXT.Name,
	Duration = TEXT.Duration,
})

-- Thin dark outline with lightly trimmed icons.
ns.AddSkin("Clean", {
	Shape = "Square",
	Description = "A thin dark outline around trimmed icons.",
	Icon = { Width = 34, Height = 34, TexCoords = TRIM },
	Backdrop = { Texture = WHITE, Color = { 0, 0, 0, 0.5 }, Width = 36, Height = 36 },
	Normal = {
		Texture = [[Interface\Common\WhiteIconFrame]],
		Color = { 0.05, 0.05, 0.05, 1 }, Width = 36, Height = 36,
	},
	Pushed = { Texture = WHITE, Color = { 0, 0, 0, 0.45 }, Width = 34, Height = 34 },
	Highlight = { Texture = WHITE, Color = { 1, 1, 1, 0.18 }, BlendMode = "ADD", Width = 34, Height = 34 },
	Checked = {
		Texture = [[Interface\Common\WhiteIconFrame]],
		Color = { 1, 0.82, 0, 1 }, BlendMode = "ADD", Width = 36, Height = 36,
	},
	SpellHighlight = { Texture = WHITE, Color = { 1, 1, 0.6, 0.25 }, BlendMode = "ADD", Width = 34, Height = 34 },
	Disabled = { Hide = true },
	Flash = { Texture = WHITE, Color = { 1, 0, 0, 0.3 }, Width = 34, Height = 34 },
	Border = Border({
		Texture = [[Interface\Common\WhiteIconFrame]],
		BlendMode = "BLEND", Width = 36, Height = 36,
	}),
	Cooldown = { Width = 34, Height = 34 },
	ChargeCooldown = { Width = 34, Height = 34 },
	AutoCastShine = { Width = 34, Height = 34 },
	AutoCastOverlay = { Width = 34, Height = 34 },
	HotKey = TEXT.HotKey,
	Count = TEXT.Count,
	Name = TEXT.Name,
	Duration = TEXT.Duration,
})

-- Edge-to-edge icons with no frame at all.
ns.AddSkin("Zoomed", {
	Shape = "Square",
	Description = "Edge-to-edge icons with no frame.",
	Icon = { Width = 36, Height = 36, TexCoords = TRIM },
	Backdrop = { Texture = WHITE, Color = { 0, 0, 0, 0.4 }, Width = 36, Height = 36 },
	Normal = { Hide = true },
	Pushed = { Texture = WHITE, Color = { 0, 0, 0, 0.5 } },
	Highlight = { Texture = WHITE, Color = { 1, 1, 1, 0.2 }, BlendMode = "ADD" },
	Checked = { Texture = WHITE, Color = { 1, 0.82, 0, 0.25 }, BlendMode = "ADD" },
	SpellHighlight = { Texture = WHITE, Color = { 1, 1, 0.6, 0.25 }, BlendMode = "ADD" },
	Disabled = { Hide = true },
	Flash = { Texture = WHITE, Color = { 1, 0, 0, 0.3 } },
	Border = Border({
		Texture = [[Interface\Buttons\UI-ActionButton-Border]],
		BlendMode = "ADD", Width = 62, Height = 62,
	}),
	Cooldown = FRAME36,
	ChargeCooldown = FRAME36,
	AutoCastShine = FRAME36,
	AutoCastOverlay = FRAME36,
	HotKey = TEXT.HotKey,
	Count = TEXT.Count,
	Name = TEXT.Name,
	Duration = TEXT.Duration,
})
