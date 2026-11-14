std = "lua51"
max_line_length = false
codes = true

exclude_files = {
	".release/",
	"Libs/",
}

ignore = {
	"212/self", -- unused argument self
}

-- Globals the add-on writes.
globals = {
	"FashionJournalDB",
	"SlashCmdList",
	"SLASH_FASHIONJOURNAL1",
	"SLASH_FASHIONJOURNAL2",
	"StaticPopupDialogs",
}

-- WoW API and FrameXML globals the add-on reads.
read_globals = {
	"C_AddOns",
	"C_EncounterJournal",
	"C_EventUtils",
	"C_GameRules",
	"C_Item",
	"C_Map",
	"C_Timer",
	"C_TransmogCollection",
	"ChatFontNormal",
	"CreateFrame",
	"Enum",
	"GetBuildInfo",
	"GetInstanceInfo",
	"GetLocale",
	"Item",
	"UIParent",
	"GameTooltip",
	"HandleModifiedItemClick",
	"ITEM_QUALITY_COLORS",
	"NO",
	"StaticPopup_Show",
	"YES",
	"UISpecialFrames",
	"UnitClass",
	"UnitLevel",
	"UnitRace",
	"WOW_PROJECT_ID",
	"date",
	"strtrim",
	"time",
	"wipe",
}
