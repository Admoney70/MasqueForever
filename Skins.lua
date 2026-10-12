--[[
	Skins.lua: the skin registry.

	Skins use the Masque skin format, so existing Masque skin definitions can
	be passed to AddSkin() unchanged. Optimizations over a naive registry:

	* Templates are flattened once, when a skin is first used, not on every
	  button.
	* Per-layer, per-button-type lookups are memoized, so skinning a button is
	  a series of table hits rather than repeated fallback chains.
]]

local _, ns = ...
if ns.disabled then return end

local pairs, type, sort = pairs, type, table.sort

local skins = {}      -- SkinID -> raw skin data (as registered)
local compiled = {}   -- SkinID -> flattened skin data
local cache = {}      -- SkinID -> { ["Layer:Type"] = spec or false }
local order = {}      -- sorted list of selectable SkinIDs (rebuilt lazily)
local orderDirty = true

ns.skins = skins

-- Masque button types that fall back to a broader type when a skin does not
-- define a type-specific variant of a layer.
local TYPE_PARENT = {
	Buff = "Aura", Debuff = "Aura", Enchant = "Aura",
	Backpack = "Item", BagSlot = "Item", ReagentBag = "Item",
	Pet = "Action", Possess = "Action", Stance = "Action", Legacy = "Action",
}
ns.TYPE_PARENT = TYPE_PARENT

-- Template names used by Masque skins, mapped to the closest Guise skin.
local TEMPLATE_ALIAS = {
	["Default"] = "Classic",
	["Blizzard Classic"] = "Classic",
	["Blizzard Modern"] = "Classic",
	["Dream"] = "Clean",
}

local function Compile(id, seen)
	local done = compiled[id]
	if done then return done end

	local raw = skins[id] or skins[TEMPLATE_ALIAS[id] or ""]
	if not raw then return nil end

	local template = raw.Template
	if type(template) == "string" and template ~= id then
		seen = seen or {}
		if not seen[id] then
			seen[id] = true
			local base = Compile(template, seen)
			if base then
				local merged = {}
				for k, v in pairs(base) do merged[k] = v end
				for k, v in pairs(raw) do merged[k] = v end
				merged.Template = nil
				compiled[id] = merged
				return merged
			end
		end
	end

	compiled[id] = raw
	return raw
end

local function Invalidate()
	for k in pairs(compiled) do compiled[k] = nil end
	for k in pairs(cache) do cache[k] = nil end
	orderDirty = true
end

-- Type-specific layer names used by current Masque skins.
local TYPE_LAYER = {
	Border = { Debuff = "DebuffBorder", Enchant = "EnchantBorder" },
}

-- Masque's built-in text anchors; skins often give only offsets.
local TEXT_DEFAULTS = {
	HotKey = { Width = 36, JustifyH = "RIGHT", Point = "TOPRIGHT", RelPoint = "TOPRIGHT" },
	Count = { Width = 36, JustifyH = "RIGHT", Point = "BOTTOMRIGHT", RelPoint = "BOTTOMRIGHT" },
	Name = { Width = 36, JustifyH = "CENTER", Point = "BOTTOM", RelPoint = "BOTTOM" },
	Duration = { Width = 36, JustifyH = "CENTER", Point = "TOP", RelPoint = "BOTTOM" },
}

-- A layer may be a table, or a string naming another layer
-- (e.g. SlotHighlight = "Checked").
local function LayerTable(skin, layer)
	local spec = skin[layer]
	for _ = 1, 5 do
		if type(spec) ~= "string" then break end
		spec = skin[spec]
	end
	return type(spec) == "table" and spec or nil
end

-- Returns the spec table for a layer of a skin, honouring Masque's
-- type-specific variants (Border.Debuff, DebuffBorder, Backdrop.Item...)
-- and the type fallbacks.
function ns.ResolveLayer(skinID, skin, layer, btype)
	local c = cache[skinID]
	if not c then
		c = {}
		cache[skinID] = c
	end

	local key = layer .. ":" .. (btype or "")
	local spec = c[key]
	if spec ~= nil then return spec or nil end

	local alt = TYPE_LAYER[layer] and btype and TYPE_LAYER[layer][btype]
	spec = alt and LayerTable(skin, alt) or LayerTable(skin, layer)
	if spec then
		local t = btype
		while t do
			local sub = spec[t]
			if type(sub) == "table" then
				spec = sub
				break
			end
			t = TYPE_PARENT[t]
		end

		local defaults = TEXT_DEFAULTS[layer]
		if defaults then
			local merged = {}
			for k, v in pairs(defaults) do merged[k] = v end
			for k, v in pairs(spec) do merged[k] = v end
			-- An explicit Point without RelPoint means "same as Point".
			if spec.Point and not spec.RelPoint then merged.RelPoint = nil end
			spec = merged
		end
	end

	c[key] = spec or false
	return spec
end

-- Masque skins reference textures that ship inside Masque itself. Map them
-- to equivalents so those skins work without it.
local MASQUE_TEXTURES = "^[Ii]nterface[\\/][Aa]dd[Oo]ns[\\/][Mm]asque[\\/][Tt]extures[\\/](.+)$"
local OWN_TEXTURES = [[Interface\AddOns\]] .. ns.name .. [[\Textures\]]
local WHITE = [[Interface\Buttons\WHITE8x8]]
local texCache = {}

function ns.Texture(path)
	if type(path) ~= "string" then return path end
	local mapped = texCache[path]
	if mapped ~= nil then return mapped or nil end

	local rest = path:match(MASQUE_TEXTURES)
	if not rest then
		mapped = path
	else
		rest = rest:lower():gsub("/", "\\")
		local shape, file = rest:match("^(.-)\\([^\\]+)$")
		file = file or rest
		if shape == "backdrop" then
			mapped = OWN_TEXTURES .. "Backdrop"
		elseif file == "mask" or file == "autocast-mask" then
			mapped = shape == "circle" and [[Interface\CharacterFrame\TempPortraitAlphaMask]] or WHITE
		elseif file == "edge" then
			mapped = [[Interface\Cooldown\edge]]
		else
			mapped = false -- unknown: leave the game's art in place
		end
	end

	texCache[path] = mapped
	return mapped or nil
end

function ns.AddSkin(id, data, replace)
	if type(id) ~= "string" or type(data) ~= "table" then return end
	if skins[id] and not replace then return end
	skins[id] = data
	Invalidate()
	if ns.OnSkinsChanged then ns.OnSkinsChanged(id) end
	return true
end

function ns.GetSkin(id)
	if id == nil then return nil end
	return Compile(id)
end

function ns.HasSkin(id)
	return id ~= nil and (skins[id] ~= nil or (TEMPLATE_ALIAS[id] and skins[TEMPLATE_ALIAS[id]] ~= nil)) or false
end

-- Sorted list of skins a user may pick, with "Blizzard" (unskinned) first.
function ns.SkinList()
	if orderDirty then
		for i = #order, 1, -1 do order[i] = nil end
		for id, data in pairs(skins) do
			if id ~= "Blizzard" and not data.Disable and not data.Hidden then
				order[#order + 1] = id
			end
		end
		sort(order)
		if skins.Blizzard then
			table.insert(order, 1, "Blizzard")
		end
		orderDirty = false
	end
	return order
end
