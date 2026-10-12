-- Minimal World of Warcraft API mock: just enough to load Guise and observe
-- what it does to buttons. Not a general-purpose emulator.

local M = {}

strmatch = string.match
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

M.combat = false
SlashCmdList = {}
function ReloadUI() end
GameTooltip_Hide = function() end
function InCombatLockdown() return M.combat end
function UnitName() return "Tester" end
-- Secret values: an opaque object that errors like the real thing when used
-- as a number.
M.SECRET = setmetatable({}, {
	__lt = function() error("attempt to compare a secret value") end,
	__le = function() error("attempt to compare a secret value") end,
	__concat = function() error("attempt to concatenate a secret value") end,
})
function issecretvalue(v) return v == M.SECRET end
M.errors = {}
function geterrorhandler() return function(e) error(e, 0) end end

M.timers = {}
C_Timer = { After = function(_, f) M.timers[#M.timers + 1] = f end }
function M.RunTimers()
	while #M.timers > 0 do
		local list = M.timers
		M.timers = {}
		for _, f in ipairs(list) do f() end
	end
end

M.addons = {}
C_AddOns = {
	DoesAddOnExist = function(name) return M.addons[name] ~= nil end,
	GetAddOnEnableState = function(name) return M.addons[name] or 0 end,
}

function hooksecurefunc(tbl, name, hook)
	if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
	local orig = tbl[name]
	assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(name))
	tbl[name] = function(...)
		local a, b, c, d, e = orig(...)
		hook(...)
		return a, b, c, d, e
	end
end

----------------------------------------------------------------------
-- Regions
----------------------------------------------------------------------

local Region = {}
Region.__index = Region

local function NewRegion(kind, parent, layer, sub)
	local r = setmetatable({
		_type = kind, _parent = parent, _points = {}, _w = 0, _h = 0,
		_alpha = 1, _shown = true, _layer = layer or "ARTWORK", _sub = sub or 0,
		_coords = { 0, 0, 0, 1, 1, 0, 1, 1 }, _color = { 1, 1, 1, 1 },
		_blend = "BLEND", _masks = {}, _scripts = {},
		_justifyH = "CENTER", _justifyV = "MIDDLE",
	}, Region)
	return r
end
M.NewRegion = NewRegion

function Region:GetObjectType() return self._type end
function Region:GetParent() return self._parent end
function Region:GetName() return self._name end
function Region:SetPoint(p, rel, rp, x, y)
	if type(rel) == "number" then rel, rp, x, y = nil, p, rel, rp end
	self._points[#self._points + 1] = { p, rel or self._parent, rp or p, x or 0, y or 0 }
end
function Region:SetAllPoints(rel)
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
	self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end
function Region:ClearAllPoints() self._points = {} end
function Region:GetNumPoints() return #self._points end
function Region:GetPoint(i) return unpack(self._points[i]) end
function Region:SetSize(w, h) self._w, self._h = w, h; self:_SizeChanged() end
function Region:SetWidth(w) self._w = w; self:_SizeChanged() end
function Region:SetHeight(h) self._h = h; self:_SizeChanged() end
function Region:GetSize() return self._w, self._h end
function Region:GetWidth() return self._w end
function Region:GetHeight() return self._h end
function Region:_SizeChanged()
	local f = self._scripts.OnSizeChanged
	if f then f(self, self._w, self._h) end
end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetAlpha() return self._alpha end
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:IsShown() return self._shown end
function Region:SetShown(s) self._shown = not not s end
-- textures
function Region:SetTexture(t) self._texture = t; self._atlas = nil end
function Region:GetTexture() return self._texture end
function Region:SetAtlas(a) self._atlas = a; self._texture = "atlas:" .. tostring(a) end
function Region:GetAtlas() return self._atlas end
function Region:SetTexCoord(...)
	local n = select("#", ...)
	local a, b, c, d = ...
	if n == 4 then self._coords = { a, c, a, d, b, c, b, d } else self._coords = { ... } end
end
function Region:GetTexCoord() return unpack(self._coords) end
function Region:SetVertexColor(r, g, b, a) self._color = { r, g, b, a or 1 } end
function Region:GetVertexColor() return unpack(self._color) end
function Region:SetBlendMode(m) self._blend = m end
function Region:GetBlendMode() return self._blend end
function Region:SetDrawLayer(l, s) self._layer, self._sub = l, s or 0 end
function Region:GetDrawLayer() return self._layer, self._sub end
function Region:AddMaskTexture(m) self._masks[m] = true end
function Region:RemoveMaskTexture(m) self._masks[m] = nil end
-- font strings
function Region:SetJustifyH(j) self._justifyH = j end
function Region:GetJustifyH() return self._justifyH end
function Region:SetJustifyV(j) self._justifyV = j end
function Region:GetJustifyV() return self._justifyV end
function Region:SetText(t) self._text = t end
function Region:SetFontObject() end
function Region:SetWordWrap() end
-- cooldowns
function Region:SetSwipeColor(r, g, b, a) self._swipe = { r, g, b, a } end
function Region:SetSwipeTexture(t) self._swipeTex = t end
function Region:SetEdgeTexture() end
function Region:SetBlingTexture() end
function Region:SetDrawBling(v) self._bling = v end
-- frames
function Region:CreateTexture(name, layer, _, sub) return NewRegion("Texture", self, layer, sub) end
function Region:CreateMaskTexture() return NewRegion("MaskTexture", self) end
function Region:CreateFontString(name, layer) return NewRegion("FontString", self, layer) end
function Region:SetScript(s, f) self._scripts[s] = f end
function Region:HookScript(s, f)
	local old = self._scripts[s]
	self._scripts[s] = function(...) if old then old(...) end f(...) end
end
function Region:RegisterEvent(e) M.registered[e] = true end
function Region:IsProtected() return self._protected or false end
function Region:IsVisible() return self._shown end

-- options-panel widgets
function Region:SetScrollChild(c) self._child = c end
function Region:SetChecked(v) self._checked = v end
function Region:GetChecked() return self._checked end
function Region:Enable() self._enabled = true end
function Region:Disable() self._enabled = false end

Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		return { GetID = function() return name end }
	end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function(id) M.opened = id end,
}

M.registered = {}
M.frames = {}

function CreateFrame(kind, name, parent, template)
	local f = NewRegion(kind, parent)
	f._name = name
	if name then _G[name] = f end
	M.frames[#M.frames + 1] = f
	return f
end

-- An action button shaped like the modern ActionButtonTemplate.
function M.NewActionButton(name, size)
	local b = CreateFrame("CheckButton", name, nil)
	b._protected = true
	b:SetSize(size or 45, size or 45)
	b.icon = b:CreateTexture(nil, "BACKGROUND")
	b.icon:SetAllPoints(b)
	b.IconMask = b:CreateMaskTexture()
	b.icon:AddMaskTexture(b.IconMask)
	b.cooldown = NewRegion("Cooldown", b)
	b.cooldown:SetAllPoints(b)
	b.HotKey = b:CreateFontString(nil, "OVERLAY")
	b.HotKey:SetPoint("TOPRIGHT", b, "TOPRIGHT", -4, -4)
	b.Count = b:CreateFontString(nil, "OVERLAY")
	b.Name = b:CreateFontString(nil, "OVERLAY")
	b.Border = b:CreateTexture(nil, "OVERLAY")
	b.Flash = b:CreateTexture(nil, "ARTWORK")
	b.SlotBackground = b:CreateTexture(nil, "BACKGROUND")
	b.SlotArt = b:CreateTexture(nil, "BACKGROUND")

	local normal = b:CreateTexture(nil, "ARTWORK")
	normal:SetAtlas("UI-HUD-ActionBar-IconFrame")
	normal:SetSize(46, 45)
	normal:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	local pushed = b:CreateTexture(nil, "ARTWORK")
	local highlight = b:CreateTexture(nil, "HIGHLIGHT")
	local checked = b:CreateTexture(nil, "ARTWORK")
	function b:GetNormalTexture() return normal end
	function b:GetPushedTexture() return pushed end
	function b:GetHighlightTexture() return highlight end
	function b:GetCheckedTexture() return checked end
	function b:SetNormalAtlas(a) normal:SetAtlas(a) end
	function b:UpdateButtonArt() self:SetNormalAtlas("UI-HUD-ActionBar-IconFrame") end
	return b
end

return M
