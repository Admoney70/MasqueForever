--[[
	Blizzard.lua: skins the game's own action bars and bag buttons.

	Each bar is its own sub-group of "Blizzard", so bars can use different
	skins or be left alone. Missing bars (or ones a future client renames) are
	skipped silently.
]]

local _, ns = ...
if ns.disabled then return end

local _G = _G

local BARS = {
	{ "Action Bar 1", "ActionButton", 12 },
	{ "Action Bar 2", "MultiBarBottomLeftButton", 12 },
	{ "Action Bar 3", "MultiBarBottomRightButton", 12 },
	{ "Action Bar 4", "MultiBarRightButton", 12 },
	{ "Action Bar 5", "MultiBarLeftButton", 12 },
	{ "Action Bar 6", "MultiBar5Button", 12 },
	{ "Action Bar 7", "MultiBar6Button", 12 },
	{ "Action Bar 8", "MultiBar7Button", 12 },
	{ "Pet Bar", "PetActionButton", 10, "Pet" },
	{ "Stance Bar", "StanceButton", 10, "Stance" },
	{ "Possess Bar", "PossessButton", 2, "Possess" },
	{ "Extra Action", "ExtraActionButton", 1 },
}

local BAGS = {
	{ "MainMenuBarBackpackButton", "Backpack" },
	{ "CharacterBag0Slot", "BagSlot" },
	{ "CharacterBag1Slot", "BagSlot" },
	{ "CharacterBag2Slot", "BagSlot" },
	{ "CharacterBag3Slot", "BagSlot" },
	{ "CharacterReagentBag0Slot", "ReagentBag" },
}

local MSQ = ns.API
local done = false

local function SkinBlizzard()
	if done or not (ns.db and ns.db.Blizzard) then return end
	done = true

	local parent = MSQ:Group("Blizzard")
	parent:SetName("Blizzard UI")

	for _, bar in ipairs(BARS) do
		local name, prefix, count, btype = bar[1], bar[2], bar[3], bar[4] or "Action"
		local group
		for i = 1, count do
			local button = _G[prefix .. i]
			if button then
				group = group or MSQ:Group("Blizzard", name)
				group:AddButton(button, nil, btype)
			end
		end
	end

	local bags
	for _, entry in ipairs(BAGS) do
		local button = _G[entry[1]]
		if button then
			bags = bags or MSQ:Group("Blizzard", "Bags")
			bags:AddButton(button, nil, entry[2])
		end
	end
end

ns.SkinBlizzard = SkinBlizzard
ns.On("PLAYER_LOGIN", SkinBlizzard)

function ns.SetBlizzardEnabled(enabled)
	ns.db.Blizzard = enabled and true or false
	local group = ns.groups.Blizzard
	if enabled then
		if group then ns.SetOption(group, "Disabled", false) end
		SkinBlizzard()
	elseif group then
		ns.SetOption(group, "Disabled", true)
	end
end
