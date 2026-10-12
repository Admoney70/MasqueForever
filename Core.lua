--[[
	Guise - a lightweight, Masque-compatible button skinning engine for
	World of Warcraft: Forever.

	Core.lua: namespace, saved variables, event dispatch and the work queues
	(batched re-skins and the out-of-combat queue for protected buttons).
]]

local ADDON, ns = ...

local C_AddOns, C_Timer = C_AddOns, C_Timer
local pairs, next, pcall, print, type = pairs, next, pcall, print, type
local InCombatLockdown = InCombatLockdown

ns.name = ADDON
ns.title = "Guise"

----------------------------------------------------------------------
-- Masque coexistence
--
-- Guise registers itself under the LibStub name "Masque" so that add-ons
-- that support Masque (Bartender4, Dominos, ElvUI-style bar mods, aura
-- add-ons...) skin through Guise automatically. If the real Masque is
-- installed and enabled, Guise stands down completely.
----------------------------------------------------------------------

local function IsMasqueEnabled()
	if not C_AddOns or not C_AddOns.GetAddOnEnableState then return false end
	if C_AddOns.DoesAddOnExist and not C_AddOns.DoesAddOnExist("Masque") then return false end
	local ok, state = pcall(C_AddOns.GetAddOnEnableState, "Masque", UnitName and UnitName("player"))
	return ok and type(state) == "number" and state > 0
end

local MSQ
if IsMasqueEnabled() then
	ns.disabled = "Masque is enabled; Guise is standing down."
else
	MSQ = LibStub:NewLibrary("Masque", 1)
	if not MSQ then
		ns.disabled = "Another add-on already provides the Masque API; Guise is standing down."
	end
end

local events = CreateFrame("Frame")

-- Referenced by the TOC, so it must exist even when Guise stands down.
function _G.Guise_OnAddonCompartmentClick()
	if ns.OpenOptions then
		ns.OpenOptions()
	elseif ns.disabled then
		print("|cff33ff99Guise|r: " .. ns.disabled)
	end
end

if ns.disabled then
	events:RegisterEvent("PLAYER_LOGIN")
	events:SetScript("OnEvent", function()
		print("|cff33ff99Guise|r: " .. ns.disabled)
	end)
	return
end

ns.API = MSQ
_G.Guise = MSQ

----------------------------------------------------------------------
-- Utility
----------------------------------------------------------------------

function ns.Print(...)
	print("|cff33ff99Guise|r:", ...)
end

-- Run a function, reporting (instead of propagating) any error so that a bad
-- third-party skin can never break the caller's code path.
function ns.SafeCall(func, ...)
	local ok, err = pcall(func, ...)
	if not ok then
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) else ns.Print(err) end
	end
	return ok
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local handlers = {}

function ns.On(event, func)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		events:RegisterEvent(event)
	end
	list[#list + 1] = func
end

events:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			ns.SafeCall(list[i], event, ...)
		end
	end
end)

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------

ns.defaults = {
	SkinID = "Classic",
	Backdrop = true,
	Gloss = false,
	Shadow = false,
	Pulse = true,
	Disabled = false,
}

-- Group settings created before the saved variables are available are kept
-- here and merged in once ADDON_LOADED fires.
local pendingDB = {}

function ns.GetGroupDB(id)
	local db = ns.db
	local store = db and db.Groups or pendingDB
	local entry = store[id]
	if not entry then
		entry = {}
		store[id] = entry
	end
	return entry
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end

	local db = _G.GuiseDB
	if type(db) ~= "table" then db = {} end
	_G.GuiseDB = db
	db.Groups = db.Groups or {}
	if db.Blizzard == nil then db.Blizzard = true end
	ns.db = db

	-- Adopt groups that were registered before our saved variables loaded.
	for id, temp in pairs(pendingDB) do
		local saved = db.Groups[id]
		if saved then
			for k, v in pairs(temp) do
				if saved[k] == nil then saved[k] = v end
			end
		else
			db.Groups[id] = temp
		end
	end
	pendingDB = nil

	if ns.OnDatabaseReady then ns.OnDatabaseReady() end
end)

----------------------------------------------------------------------
-- Work queues
--
-- 1. Batched re-skins: option changes and repeated ReSkin() calls are
--    collapsed into a single pass on the next frame.
-- 2. Combat queue: protected (secure) buttons that need re-anchoring while
--    in combat are deferred until PLAYER_REGEN_ENABLED.
----------------------------------------------------------------------

local dirtyGroups, dirtyButtons = {}, {}
local flushScheduled = false
local combatQueue = {}

local function Flush()
	flushScheduled = false
	local groups, buttons = dirtyGroups, dirtyButtons
	dirtyGroups, dirtyButtons = {}, {}

	for group in pairs(groups) do
		for button in pairs(group.Buttons) do
			ns.SkinButton(button, buttons[button] or false)
			buttons[button] = nil
		end
	end
	for button, force in pairs(buttons) do
		ns.SkinButton(button, force)
	end
end

local function Schedule()
	if flushScheduled then return end
	flushScheduled = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0, Flush)
	else
		Flush()
	end
end

function ns.QueueGroup(group)
	dirtyGroups[group] = true
	Schedule()
end

function ns.QueueButton(button, force)
	dirtyButtons[button] = dirtyButtons[button] or force or false
	Schedule()
end

function ns.DeferUntilOutOfCombat(button)
	combatQueue[button] = true
end

function ns.CanModify(button)
	return not (InCombatLockdown() and button.IsProtected and button:IsProtected())
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if not next(combatQueue) then return end
	local queue = combatQueue
	combatQueue = {}
	for button in pairs(queue) do
		ns.SkinButton(button, true)
	end
end)
