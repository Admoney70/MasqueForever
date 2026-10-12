std = "lua51"
max_line_length = false
exclude_files = { "Libs/", "tests/" }
ignore = { "212/self", "212/_.*" }
globals = { "GuiseDB", "Guise", "Guise_OnAddonCompartmentClick", "SLASH_GUISE1", "SlashCmdList" }
read_globals = {
	"LibStub", "CreateFrame", "C_AddOns", "C_Timer", "UnitName", "InCombatLockdown",
	"hooksecurefunc", "geterrorhandler", "issecretvalue", "wipe", "strmatch", "GameTooltip", "GameTooltip_Hide",
	"Settings", "ColorPickerFrame", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory", "ReloadUI",
}
