--[[
	Skinner.lua: discovers a button's regions and applies / removes skins.

	Design notes:
	* Per-button state lives in a weak-keyed table owned by Guise. Nothing is
	  written onto the button objects themselves, which keeps Blizzard's secure
	  action buttons free of foreign keys (no taint) and lets buttons that are
	  thrown away be garbage collected.
	* Every region's original state is captured the first time Guise changes
	  it and restored exactly when the skin is removed or set to "Blizzard".
	* A signature (options epoch + button size) lets repeated ReSkin() calls
	  that change nothing return immediately.
	* Re-anchoring protected buttons is deferred until combat ends.
]]

local _, ns = ...
if ns.disabled then return end

local pairs, ipairs, type, unpack, pcall, tostring, select = pairs, ipairs, type, unpack, pcall, tostring, select
local hooksecurefunc = hooksecurefunc

-- Midnight-era clients (including Forever) return "secret values" from some
-- regions, notably Blizzard's aura container buttons. Secrets cannot be
-- compared, used in arithmetic or as loop bounds, so anything that returns
-- one is treated as off limits.
local issecretvalue = issecretvalue or function() return false end

local function AnySecret(...)
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

-- Errors are reported once per message, not once per button.
local reported = {}
local function Report(err)
	err = tostring(err)
	if reported[err] then return end
	reported[err] = true
	local handler = geterrorhandler and geterrorhandler()
	if handler then handler(err) end
end

local BASE = 36
local FULL_COORDS = { 0, 1, 0, 1 }

local state = setmetatable({}, { __mode = "k" })
ns.state = state

----------------------------------------------------------------------
-- Layer tables
----------------------------------------------------------------------

-- Texture regions Guise may restyle.
local TEXTURE_LAYERS = {
	"Normal", "Pushed", "Highlight", "Checked", "Disabled", "Border", "Flash",
	"AutoCastable", "NewAction", "SpellHighlight", "IconBorder", "IconOverlay",
	"IconOverlay2", "QuestBorder", "NewItem", "SearchOverlay", "ContextOverlay",
	"SlotHighlight", "JunkIcon", "UpgradeIcon",
}

local TEXT_LAYERS = { "Name", "Count", "HotKey", "Duration" }

local FRAME_LAYERS = { "Cooldown", "ChargeCooldown", "AutoCastShine", "AutoCastOverlay" }

-- Textures Guise creates itself; the key doubles as the group option name.
local CREATED = {
	Shadow = { "BACKGROUND", -2 },
	Backdrop = { "BACKGROUND", -1 },
	Gloss = { "OVERLAY", 7 },
}
local CREATED_ORDER = { "Shadow", "Backdrop", "Gloss" }

-- Blizzard art that is hidden while a skin is active.
local HIDE_WHEN_SKINNED = { "SlotBackground", "SlotArt" }

-- Layers whose colour carries game state (equipped item, debuff type, item
-- quality...). Their colour is left alone unless a skin sets UseColor.
local KEEP_COLOR = {
	Border = true, IconBorder = true, QuestBorder = true, NewItem = true,
	SlotHighlight = true, IconOverlay = true, IconOverlay2 = true,
}

-- Button methods that replace a state texture, mapped to the layer.
local STATE_SETTERS = {
	SetNormalTexture = "Normal", SetNormalAtlas = "Normal",
	SetPushedTexture = "Pushed", SetPushedAtlas = "Pushed",
	SetHighlightTexture = "Highlight", SetHighlightAtlas = "Highlight",
	SetCheckedTexture = "Checked", SetCheckedAtlas = "Checked",
	SetDisabledTexture = "Disabled", SetDisabledAtlas = "Disabled",
}

local STATE_GETTERS = {
	Normal = "GetNormalTexture", Pushed = "GetPushedTexture",
	Highlight = "GetHighlightTexture", Checked = "GetCheckedTexture",
	Disabled = "GetDisabledTexture",
}

-- Where to look for each region: keys on the button, then global name
-- suffixes ("ActionButton1Icon").
local REGION_KEYS = {
	Icon = { "icon", "Icon", "IconTexture", sfx = { "Icon", "IconTexture" } },
	Cooldown = { "cooldown", "Cooldown", sfx = { "Cooldown" } },
	ChargeCooldown = { "chargeCooldown", "ChargeCooldown" },
	Count = { "Count", "count", sfx = { "Count" } },
	HotKey = { "HotKey", "hotKey", sfx = { "HotKey" } },
	Name = { "Name", "actionName", sfx = { "Name" } },
	Duration = { "Duration", "duration", sfx = { "Duration" } },
	Border = { "Border", "border", sfx = { "Border" } },
	Flash = { "Flash", sfx = { "Flash" } },
	AutoCastable = { "AutoCastable", sfx = { "AutoCastable" } },
	AutoCastShine = { "AutoCastShine", sfx = { "Shine", "AutoCast" } },
	AutoCastOverlay = { "AutoCastOverlay" },
	NewAction = { "NewActionTexture" },
	SpellHighlight = { "SpellHighlightTexture" },
	IconBorder = { "IconBorder" },
	IconOverlay = { "IconOverlay" },
	IconOverlay2 = { "IconOverlay2" },
	QuestBorder = { "IconQuestTexture", sfx = { "IconQuestTexture" } },
	NewItem = { "NewItemTexture" },
	SearchOverlay = { "searchOverlay", "SearchOverlay", sfx = { "SearchOverlay" } },
	ContextOverlay = { "ItemContextOverlay" },
	SlotHighlight = { "SlotHighlightTexture" },
	JunkIcon = { "JunkIcon" },
	UpgradeIcon = { "UpgradeIcon" },
	SlotBackground = { "SlotBackground" },
	SlotArt = { "SlotArt" },
	IconMask = { "IconMask" },
}

-- Region names older Masque add-ons pass in their region tables.
local REGION_ALIAS = { AutoCast = "AutoCastShine", Shine = "AutoCastShine" }

----------------------------------------------------------------------
-- Region discovery
----------------------------------------------------------------------

local function IsRegion(v)
	return type(v) == "table" and type(v.GetObjectType) == "function"
end

local function Lookup(button, layer, name)
	local keys = REGION_KEYS[layer]
	if not keys then return nil end
	for i = 1, #keys do
		local v = button[keys[i]]
		if IsRegion(v) then return v end
	end
	if name and keys.sfx then
		for i = 1, #keys.sfx do
			local v = _G[name .. keys.sfx[i]]
			if IsRegion(v) then return v end
		end
	end
end

function ns.CollectRegions(button, given, strict)
	local regions = {}

	if type(given) == "table" then
		for k, v in pairs(given) do
			if IsRegion(v) then regions[REGION_ALIAS[k] or k] = v end
		end
	end

	if strict then return regions end

	local name = button.GetName and button:GetName()
	for layer in pairs(REGION_KEYS) do
		if regions[layer] == nil and not (type(given) == "table" and given[layer] == false) then
			regions[layer] = Lookup(button, layer, name)
		end
	end
	for layer, getter in pairs(STATE_GETTERS) do
		if regions[layer] == nil and button[getter] then
			regions[layer] = button[getter](button)
		end
	end
	return regions
end

function ns.GuessType(button)
	if button.IconBorder then return "Item" end
	if button.auraInstanceID or button.Duration or button.duration then return "Aura" end
	return "Action"
end

----------------------------------------------------------------------
-- Snapshot / restore
----------------------------------------------------------------------

-- Records a region's original state. Returns nil (and the layer is left
-- alone) if the region is restricted or reports secret values, since such a
-- region could neither be restyled safely nor restored.
local Inspect -- forward

local function Snapshot(st, layer, region, kind)
	local o = st.orig[layer]
	if o and o.region == region then return o end

	o = Inspect(region, kind)
	if not o then
		st.broken[layer] = true
		return nil
	end
	st.orig[layer] = o
	return o
end

function Inspect(region, kind)
	if region.IsAnchoringRestricted and region:IsAnchoringRestricted() then return nil end

	local alpha = region:GetAlpha()
	local numPoints = region:GetNumPoints()
	local w, h = region:GetSize()
	if AnySecret(alpha, numPoints, w, h) then return nil end

	local o = { region = region, kind = kind, alpha = alpha, w = w, h = h }
	local points = {}
	for i = 1, numPoints do
		local p = { region:GetPoint(i) }
		if AnySecret(unpack(p, 1, 5)) then return nil end
		points[i] = p
	end
	o.points = points

	if kind == "texture" or kind == "icon" then
		o.atlas = region.GetAtlas and region:GetAtlas() or nil
		o.texture = region:GetTexture()
		o.coords = { region:GetTexCoord() }
		o.color = { region:GetVertexColor() }
		o.blend = region:GetBlendMode()
		o.layer, o.sublevel = region:GetDrawLayer()
		if AnySecret(o.atlas, o.texture, o.blend, o.layer, o.sublevel)
			or AnySecret(unpack(o.coords, 1, 8)) or AnySecret(unpack(o.color, 1, 4)) then
			return nil
		end
	elseif kind == "text" then
		o.justifyH = region:GetJustifyH()
		o.justifyV = region:GetJustifyV()
		if AnySecret(o.justifyH, o.justifyV) then return nil end
	end

	return o
end

local function RestorePoints(region, o)
	region:ClearAllPoints()
	local parent = region:GetParent()
	for i = 1, #o.points do
		local p = o.points[i]
		region:SetPoint(p[1], p[2] or parent, p[3], p[4], p[5])
	end
	if o.w and o.w > 0 and o.h and o.h > 0 then
		region:SetSize(o.w, o.h)
	end
end

local function Restore(st, layer)
	local o = st.orig[layer]
	if not o then return end
	st.orig[layer] = nil

	local region, kind = o.region, o.kind
	if kind == "texture" then
		if o.atlas then
			region:SetAtlas(o.atlas)
		else
			region:SetTexture(o.texture)
		end
	end
	if kind == "texture" or kind == "icon" then
		region:SetTexCoord(unpack(o.coords))
		if kind == "texture" and not KEEP_COLOR[layer] then
			region:SetVertexColor(unpack(o.color))
		end
		if o.blend then region:SetBlendMode(o.blend) end
		if o.layer then region:SetDrawLayer(o.layer, o.sublevel or 0) end
	elseif kind == "text" then
		if o.justifyH then region:SetJustifyH(o.justifyH) end
		if o.justifyV then region:SetJustifyV(o.justifyV) end
	elseif kind == "cooldown" and st.swipeColored then
		region:SetSwipeColor(0, 0, 0, 0.8)
		st.swipeColored = nil
	end

	region:SetAlpha(o.alpha)
	RestorePoints(region, o)
end

----------------------------------------------------------------------
-- Appliers
----------------------------------------------------------------------

local function Place(region, spec, button, xs, ys, sized)
	region:ClearAllPoints()
	if spec.SetAllPoints then
		region:SetAllPoints(button)
		return
	end
	if sized then
		if not spec.UseAtlasSize then
			region:SetSize((spec.Width or BASE) * xs, (spec.Height or BASE) * ys)
		end
	else
		if spec.Width then region:SetWidth(spec.Width * xs) end
		if spec.Height then region:SetHeight(spec.Height * ys) end
	end
	local point = spec.Point or "CENTER"
	region:SetPoint(point, button, spec.RelPoint or point, (spec.OffsetX or 0) * xs, (spec.OffsetY or 0) * ys)
end

local function SetHidden(st, layer, region, hidden)
	if hidden then
		if not st.hidden[layer] then
			local alpha = region:GetAlpha()
			if issecretvalue(alpha) then return end
			st.hidden[layer] = alpha
			region:SetAlpha(0)
		end
	elseif st.hidden[layer] then
		region:SetAlpha(st.hidden[layer])
		st.hidden[layer] = nil
	end
end

local function ApplyTexture(st, layer, region, spec, button, xs, ys, color)
	if not Snapshot(st, layer, region, "texture") then return end

	if spec.Hide then
		SetHidden(st, layer, region, true)
		return
	end
	SetHidden(st, layer, region, false)

	local texture, atlas = spec.Texture, spec.Atlas
	if atlas then
		region:SetAtlas(atlas, spec.UseAtlasSize)
	elseif texture then
		region:SetTexture(texture)
	end

	if texture or atlas then
		if spec.TexCoords then
			region:SetTexCoord(unpack(spec.TexCoords))
		elseif texture then
			region:SetTexCoord(0, 1, 0, 1)
		end
		region:SetBlendMode(spec.BlendMode or "BLEND")
		if not KEEP_COLOR[layer] or spec.UseColor then
			local c = color or spec.Color
			if c then
				region:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
			else
				region:SetVertexColor(1, 1, 1, 1)
			end
		end
	end

	if spec.DrawLayer then
		region:SetDrawLayer(spec.DrawLayer, spec.DrawLevel or 0)
	end

	Place(region, spec, button, xs, ys, true)

	local o = st.orig[layer]
	local nowAtlas, nowTexture = region.GetAtlas and region:GetAtlas() or nil, region:GetTexture()
	if AnySecret(nowAtlas, nowTexture) then nowAtlas, nowTexture = nil, nil end
	o.skinAtlas, o.skinTexture = nowAtlas, nowTexture
end

local function ApplyIcon(st, region, spec, skin, button, xs, ys)
	if not Snapshot(st, "Icon", region, "icon") then return end

	-- Modern action buttons round their icons with a mask; skins expect the
	-- raw square icon.
	local blizzMask = st.regions.IconMask
	if blizzMask and not st.blizzMaskRemoved and region.RemoveMaskTexture then
		region:RemoveMaskTexture(blizzMask)
		st.blizzMaskRemoved = true
	end

	region:SetTexCoord(unpack(spec.TexCoords or FULL_COORDS))
	if spec.DrawLayer then
		region:SetDrawLayer(spec.DrawLayer, spec.DrawLevel or 0)
	end
	Place(region, spec, button, xs, ys, true)

	-- Skin-provided icon mask (round skins etc.).
	local mask = spec.Mask or skin.Mask
	if type(mask) == "table" then mask = mask.Texture end
	if mask and region.AddMaskTexture and button.CreateMaskTexture then
		local m = st.mask
		if not m then
			m = button:CreateMaskTexture()
			st.mask = m
		end
		m:SetTexture(mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		m:ClearAllPoints()
		m:SetAllPoints(region)
		if not st.maskApplied then
			region:AddMaskTexture(m)
			st.maskApplied = true
		end
	elseif st.maskApplied then
		region:RemoveMaskTexture(st.mask)
		st.maskApplied = nil
	end
end

local function ApplyText(st, layer, region, spec, button, xs, ys)
	if not Snapshot(st, layer, region, "text") then return end
	if spec.JustifyH then region:SetJustifyH(spec.JustifyH) end
	if spec.JustifyV then region:SetJustifyV(spec.JustifyV) end
	Place(region, spec, button, xs, ys, false)
end

local function ApplyFrame(st, layer, region, spec, button, xs, ys, color)
	local isCooldown = region:GetObjectType() == "Cooldown"
	if not Snapshot(st, layer, region, isCooldown and "cooldown" or "frame") then return end
	Place(region, spec, button, xs, ys, true)

	if isCooldown then
		if spec.Texture and region.SetSwipeTexture then region:SetSwipeTexture(spec.Texture) end
		if spec.EdgeTexture and region.SetEdgeTexture then region:SetEdgeTexture(spec.EdgeTexture) end
		if spec.PulseTexture and region.SetBlingTexture then region:SetBlingTexture(spec.PulseTexture) end
		local c = color or spec.Color
		if c and region.SetSwipeColor then
			region:SetSwipeColor(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0.8)
			st.swipeColored = true
		end
	end
end

----------------------------------------------------------------------
-- Hooks: keep the skin when the game swaps button art
----------------------------------------------------------------------

local applying = false
local ApplyLayer -- forward

local function Reapply(button, layer, refetch)
	if applying then return end
	local st = state[button]
	if not st or not st.active or st.broken[layer] then return end

	if refetch then
		local getter = STATE_GETTERS[layer]
		local region = getter and button[getter](button)
		if region and region ~= st.regions[layer] then
			st.regions[layer] = region
			st.orig[layer] = nil
		end
	end

	-- Remember the art the game just set so that removing the skin later
	-- restores the current art rather than a stale one.
	-- (Several hooks can fire for one change; only record art that is not
	-- the skin's own.)
	local o = st.orig[layer]
	if o and o.kind == "texture" then
		local region = o.region
		local atlas = region.GetAtlas and region:GetAtlas() or nil
		local texture = region:GetTexture()
		if not AnySecret(atlas, texture) and (atlas ~= o.skinAtlas or texture ~= o.skinTexture) then
			o.atlas, o.texture = atlas, texture
		end
	end

	applying = true
	local ok, err = pcall(ApplyLayer, button, st, layer)
	applying = false
	if not ok then
		st.broken[layer] = true
		Report(err)
	end
end

local function HookRegion(button, st, layer, region)
	st.hookedRegions = st.hookedRegions or {}
	if st.hookedRegions[region] then return end
	st.hookedRegions[region] = true
	local function hook() Reapply(button, layer) end
	if region.SetTexture then hooksecurefunc(region, "SetTexture", hook) end
	if region.SetAtlas then hooksecurefunc(region, "SetAtlas", hook) end
end

local function InstallButtonHooks(button, st)
	if st.buttonHooked then return end
	st.buttonHooked = true

	for method, layer in pairs(STATE_SETTERS) do
		if type(button[method]) == "function" then
			hooksecurefunc(button, method, function() Reapply(button, layer, true) end)
		end
	end

	-- Modern action buttons rebuild their art here (bar art toggles, Edit Mode).
	if type(button.UpdateButtonArt) == "function" then
		hooksecurefunc(button, "UpdateButtonArt", function()
			local s = state[button]
			if s and s.active then ns.QueueButton(button, true) end
		end)
	end

	if button.HookScript then
		button:HookScript("OnSizeChanged", function()
			local s = state[button]
			if s and s.active then ns.QueueButton(button) end
		end)
	end
end

local function HookCooldownPulse(st, cooldown)
	if st.pulseHooked or not cooldown.SetDrawBling then return end
	st.pulseHooked = true
	hooksecurefunc(cooldown, "SetDrawBling", function(self, enabled)
		if enabled and st.active and st.noPulse then
			self:SetDrawBling(false)
		end
	end)
end

----------------------------------------------------------------------
-- Skinning
----------------------------------------------------------------------

local IS_TEXTURE, IS_TEXT, IS_FRAME = {}, {}, {}
for _, l in ipairs(TEXTURE_LAYERS) do IS_TEXTURE[l] = true end
for _, l in ipairs(TEXT_LAYERS) do IS_TEXT[l] = true end
for _, l in ipairs(FRAME_LAYERS) do IS_FRAME[l] = true end

local function LayerColor(st, layer)
	local colors = ns.GetOption(st.group, "Colors")
	return colors and colors[layer]
end

-- Applies (or, if the skin has no spec for it, restores) a single layer.
function ApplyLayer(button, st, layer)
	local skin, skinID = st.skin, st.skinID
	local spec = ns.ResolveLayer(skinID, skin, layer, st.type)
	local xs, ys = st.xs, st.ys

	if layer == "Icon" then
		local region = st.regions.Icon
		if region then
			if spec then
				ApplyIcon(st, region, spec, skin, button, xs, ys)
			else
				Restore(st, "Icon")
			end
		end
		return
	end

	local opt = CREATED[layer]
	if opt then
		local tex = st.created[layer]
		if spec and not spec.Hide and ns.GetOption(st.group, layer) then
			if not tex then
				tex = button:CreateTexture(nil, opt[1], nil, opt[2])
				st.created[layer] = tex
			end
			ApplyTexture(st, layer, tex, spec, button, xs, ys, LayerColor(st, layer))
			if not spec.DrawLayer then tex:SetDrawLayer(opt[1], opt[2]) end
			tex:Show()
		elseif tex then
			tex:Hide()
		end
		return
	end

	local region = st.regions[layer]

	if IS_TEXTURE[layer] then
		if not region and layer == "Normal" and spec and not spec.Hide then
			-- The button has no normal texture; give it one we own.
			region = st.created.Normal
			if not region then
				region = button:CreateTexture(nil, "ARTWORK", nil, 1)
				st.created.Normal = region
			end
			region:Show()
		end
		if not region then return end
		if spec then
			ApplyTexture(st, layer, region, spec, button, xs, ys, LayerColor(st, layer))
			if region ~= st.created.Normal then HookRegion(button, st, layer, region) end
		else
			if st.hidden[layer] then SetHidden(st, layer, region, false) end
			Restore(st, layer)
		end
	elseif IS_TEXT[layer] then
		if not region then return end
		if spec then ApplyText(st, layer, region, spec, button, xs, ys) else Restore(st, layer) end
	elseif IS_FRAME[layer] then
		if not region then return end
		if spec then
			ApplyFrame(st, layer, region, spec, button, xs, ys, LayerColor(st, layer))
			if region:GetObjectType() == "Cooldown" then HookCooldownPulse(st, region) end
		else
			Restore(st, layer)
		end
	end
end

local ALL_LAYERS = { "Icon" }
for _, l in ipairs(CREATED_ORDER) do ALL_LAYERS[#ALL_LAYERS + 1] = l end
for _, l in ipairs(TEXTURE_LAYERS) do ALL_LAYERS[#ALL_LAYERS + 1] = l end
for _, l in ipairs(TEXT_LAYERS) do ALL_LAYERS[#ALL_LAYERS + 1] = l end
for _, l in ipairs(FRAME_LAYERS) do ALL_LAYERS[#ALL_LAYERS + 1] = l end

local function Unskin(st)
	if not st.active then return end
	st.active = false
	st.sig = nil

	applying = true
	for layer in pairs(st.orig) do
		local ok, err = pcall(Restore, st, layer)
		if not ok then
			st.orig[layer] = nil
			Report(err)
		end
	end
	for layer, alpha in pairs(st.hidden) do
		local region = st.regions[layer]
		if region then region:SetAlpha(alpha) end
		st.hidden[layer] = nil
	end
	for _, tex in pairs(st.created) do
		tex:Hide()
	end
	local icon = st.regions.Icon
	if icon then
		if st.maskApplied then
			icon:RemoveMaskTexture(st.mask)
			st.maskApplied = nil
		end
		if st.blizzMaskRemoved then
			icon:AddMaskTexture(st.regions.IconMask)
			st.blizzMaskRemoved = nil
		end
	end
	applying = false
end

-- Skins (or un-skins) one button according to its group's settings.
-- force = true bypasses the "nothing changed" signature check.
function ns.SkinButton(button, force)
	local st = state[button]
	if not st then return end

	if not ns.CanModify(button) then
		ns.DeferUntilOutOfCombat(button)
		return
	end

	local group = st.group
	local skinID, skin = ns.EffectiveSkin(group)
	if not skin then
		Unskin(st)
		return
	end

	local w, h = button:GetSize()
	if AnySecret(w, h) then w, h = BASE, BASE end
	local sig = ns.epoch .. ":" .. skinID .. ":" .. tostring(w) .. "x" .. tostring(h)
	if not force and st.sig == sig then return end

	if st.skinID ~= skinID and st.active then
		-- Different skin: start from the game's art so layers the new skin
		-- leaves undefined are not stuck with the old skin's look.
		Unskin(st)
	end

	st.sig = sig
	st.skin, st.skinID = skin, skinID
	st.xs = (w and w > 0 and w or BASE) / BASE
	st.ys = (h and h > 0 and h or BASE) / BASE
	st.noPulse = ns.GetOption(group, "Pulse") == false
	st.active = true

	-- Each layer is isolated: a region the game refuses to let us touch is
	-- skipped from then on without affecting the rest of the button.
	applying = true
	local broken = st.broken
	for i = 1, #ALL_LAYERS do
		local layer = ALL_LAYERS[i]
		if not broken[layer] then
			local ok, err = pcall(ApplyLayer, button, st, layer)
			if not ok then
				broken[layer] = true
				Report(err)
			end
		end
	end
	for i = 1, #HIDE_WHEN_SKINNED do
		local layer = HIDE_WHEN_SKINNED[i]
		local region = st.regions[layer]
		if region and not broken[layer] then
			local ok, err = pcall(SetHidden, st, layer, region, true)
			if not ok then
				broken[layer] = true
				Report(err)
			end
		end
	end
	applying = false

	InstallButtonHooks(button, st)
end

function ns.AttachButton(button, group, regions, btype, strict)
	local st = state[button]
	if st then
		if st.group and st.group ~= group then
			st.group.Buttons[button] = nil
		end
		-- Re-adding: discard old state cleanly before re-collecting regions.
		Unskin(st)
	else
		st = { orig = {}, hidden = {}, created = {}, broken = {} }
		state[button] = st
	end

	st.group = group
	st.type = btype or ns.GuessType(button)
	st.regions = ns.CollectRegions(button, regions, strict)
	st.broken = {}
	st.sig = nil
	group.Buttons[button] = st.type
	ns.SkinButton(button, true)
end

function ns.DetachButton(button)
	local st = state[button]
	if not st then return end
	Unskin(st)
	if st.group then st.group.Buttons[button] = nil end
	st.group = nil
	-- Hooks cannot be removed; with st.active false they are inert.
end

function ns.GetButtonRegion(button, layer)
	local st = state[button]
	if not st then return nil end
	layer = REGION_ALIAS[layer] or layer
	return st.created[layer] or st.regions[layer]
end
