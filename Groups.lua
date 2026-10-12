--[[
	Groups.lua: skin groups and the public, Masque-compatible API.

	Groups form a tree:  Global  ->  Add-on  ->  Sub-group
	A group that "inherits" (the default) uses its parent's settings, so
	picking a skin for "Global" restyles everything at once.
]]

local _, ns = ...
if ns.disabled then return end

local MSQ = ns.API
local pairs, type = pairs, type
local defaults = ns.defaults

-- Bumped whenever anything that affects how buttons look changes.
ns.epoch = 1
local function Bump() ns.epoch = ns.epoch + 1 end

local groups = {}  -- ID -> group
ns.groups = groups

local Group = {}
local GroupMeta = { __index = Group }

----------------------------------------------------------------------
-- Settings resolution
----------------------------------------------------------------------

local function Inherits(group)
	return group.Parent ~= nil and group.db.Inherit ~= false
end

function ns.GetOption(group, key)
	while Inherits(group) do
		group = group.Parent
	end
	local v = group.db[key]
	if v == nil then v = defaults[key] end
	return v
end

function ns.IsGroupDisabled(group)
	while group do
		if group.db.Disabled then return true end
		group = group.Parent
	end
	return false
end

-- Returns skinID, compiled skin; or nil when the group should be unskinned.
function ns.EffectiveSkin(group)
	if ns.IsGroupDisabled(group) then return nil end
	local id = ns.GetOption(group, "SkinID")
	if not ns.HasSkin(id) then id = defaults.SkinID end
	local skin = ns.GetSkin(id)
	if not skin or skin.Blizzard then return nil end
	return id, skin
end

----------------------------------------------------------------------
-- Change propagation
----------------------------------------------------------------------

local function FireCallbacks(group, option, value)
	local cbs = group.callbacks
	if cbs then
		for i = 1, #cbs do
			local cb = cbs[i]
			if cb.arg ~= nil then
				ns.SafeCall(cb.func, cb.arg, group, option, value)
			else
				ns.SafeCall(cb.func, group, option, value)
			end
		end
	end

	-- Legacy MSQ:Register() callbacks (one per add-on).
	local legacy = ns.legacyCallbacks and ns.legacyCallbacks[group.Addon]
	if legacy and group.Addon then
		ns.SafeCall(legacy.func, legacy.arg, ns.GetOption(group, "SkinID"),
			ns.GetOption(group, "Gloss"), ns.GetOption(group, "Backdrop"),
			group.Group, nil, ns.GetOption(group, "Colors"))
	end
end

-- Re-skins a group and every descendant that inherits from it.
local function Propagate(group, option, inheritedOnly)
	ns.QueueGroup(group)
	if option then FireCallbacks(group, option, ns.GetOption(group, option)) end
	for _, child in pairs(group.SubList) do
		if not inheritedOnly or Inherits(child) or option == "Disabled" then
			Propagate(child, option, inheritedOnly)
		end
	end
end

function ns.SetOption(group, key, value)
	local db = group.db
	if key == "Inherit" and value == false and db.Inherit ~= false then
		-- Stop inheriting: start from what the group currently looks like.
		for k in pairs(defaults) do
			if k ~= "Disabled" then db[k] = ns.GetOption(group, k) end
		end
		if not db.Colors then
			local colors = {}
			for layer, c in pairs(ns.GetOption(group, "Colors") or {}) do
				colors[layer] = { c[1], c[2], c[3], c[4] }
			end
			db.Colors = colors
		end
	end
	db[key] = value
	Bump()
	Propagate(group, key, true)
end

function ns.OnSkinsChanged(id)
	Bump()
	for _, group in pairs(groups) do
		if not group.Parent or ns.GetOption(group, "SkinID") == id then
			ns.QueueGroup(group)
		end
	end
	if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.OnDatabaseReady()
	for id, group in pairs(groups) do
		group.db = ns.GetGroupDB(id)
	end
	Bump()
	for _, group in pairs(groups) do ns.QueueGroup(group) end
end

----------------------------------------------------------------------
-- Group construction
----------------------------------------------------------------------

local function NewGroup(id, addon, name, parent)
	local group = setmetatable({
		ID = id,
		Addon = addon,
		Group = name,
		Name = name or addon,
		Parent = parent,
		Buttons = {},
		SubList = {},
		db = ns.GetGroupDB(id),
	}, GroupMeta)
	groups[id] = group
	if parent then parent.SubList[id] = group end
	if ns.RefreshOptions then ns.RefreshOptions() end
	return group
end

local ROOT_ID = "Guise"
ns.root = NewGroup(ROOT_ID, nil, nil, nil)
ns.root.Name = "Global"

local function GetGroup(addon, name, staticID)
	if type(addon) ~= "string" or addon == "" then return ns.root end

	local parent = groups[addon]
	if not parent then
		parent = NewGroup(addon, addon, nil, ns.root)
	end
	if type(name) ~= "string" or name == "" then
		return parent
	end

	local id = staticID or (addon .. "_" .. name)
	local group = groups[id]
	if not group then
		group = NewGroup(id, addon, name, parent)
	end
	return group
end

----------------------------------------------------------------------
-- Group methods (Masque API)
----------------------------------------------------------------------

function Group:AddButton(button, regions, btype, strict)
	if type(button) ~= "table" then return end
	if type(regions) == "string" then
		-- Group:AddButton(button, type) form.
		regions, btype, strict = nil, regions, btype
	end
	ns.AttachButton(button, self, regions, btype, strict)
end

function Group:RemoveButton(button)
	if button and self.Buttons[button] then
		ns.DetachButton(button)
	end
end

-- ReSkin()        -> re-skin buttons whose appearance is out of date (cheap)
-- ReSkin(button)  -> force one button
-- ReSkin(true)    -> force the whole group
function Group:ReSkin(button)
	if type(button) == "table" then
		if self.Buttons[button] then ns.SkinButton(button, true) end
		return
	end
	local force = button == true
	for b in pairs(self.Buttons) do
		ns.SkinButton(b, force)
	end
end

function Group:GetLayer(button, layer)
	if button and layer then
		return ns.GetButtonRegion(button, layer)
	end
end

function Group:GetColor(layer)
	local colors = ns.GetOption(self, "Colors")
	local c = colors and colors[layer]
	if not c then
		local id, skin = ns.EffectiveSkin(self)
		local spec = skin and ns.ResolveLayer(id, skin, layer, nil)
		c = spec and spec.Color
	end
	if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
	return 1, 1, 1, 1
end

function Group:SetColor(layer, r, g, b, a)
	local colors = self.db.Colors or {}
	self.db.Colors = colors
	colors[layer] = r and { r, g, b, a } or nil
	Bump()
	Propagate(self, "Colors", true)
end

function Group:GetSkin()
	local id, skin = ns.EffectiveSkin(self)
	return id, skin
end

function Group:SetName(name)
	if type(name) == "string" then
		self.Name = name
		if ns.RefreshOptions then ns.RefreshOptions() end
	end
end

function Group:GetName()
	return self.Name
end

function Group:RegisterCallback(func, arg)
	if type(func) ~= "function" then return end
	self.callbacks = self.callbacks or {}
	self.callbacks[#self.callbacks + 1] = { func = func, arg = arg }
end
Group.SetCallback = Group.RegisterCallback

function Group:Delete()
	for _, child in pairs(self.SubList) do
		child:Delete()
	end
	for button in pairs(self.Buttons) do
		ns.DetachButton(button)
	end
	if self.Parent then self.Parent.SubList[self.ID] = nil end
	groups[self.ID] = nil
	if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Convenience toggles used by the options panel.
function Group:__Enable() ns.SetOption(self, "Disabled", false) end
function Group:__Disable() ns.SetOption(self, "Disabled", true) end

----------------------------------------------------------------------
-- Library methods (Masque API)
----------------------------------------------------------------------

function MSQ:Group(addon, name, staticID)
	return GetGroup(addon, name, staticID)
end

function MSQ:AddSkin(id, data, replace)
	return ns.AddSkin(id, data, replace)
end

function MSQ:GetSkin(id)
	return ns.GetSkin(id)
end

function MSQ:GetSkins()
	return ns.skins
end

function MSQ:GetDefaultSkin()
	return defaults.SkinID, ns.GetSkin(defaults.SkinID)
end

-- Pre-Masque-4 style add-on callback.
function MSQ:Register(addon, func, arg)
	if type(addon) ~= "string" or type(func) ~= "function" then return end
	ns.legacyCallbacks = ns.legacyCallbacks or {}
	ns.legacyCallbacks[addon] = { func = func, arg = arg }
end

-- Spell-alert styles: stored for API compatibility; the game's own proc
-- glow is used.
local spellAlerts = {}
function MSQ:AddSpellAlert(name, data)
	if type(name) == "string" and type(data) == "table" then
		spellAlerts[name] = data
	end
end
function MSQ:GetSpellAlert(name) return spellAlerts[name] end
function MSQ:UpdateSpellAlert() end

