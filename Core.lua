local ADDON_NAME, ns = ...

ns.name = ADDON_NAME

local function GetVersion()
	local version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
	if not version or version:find("^@") then
		return "dev"
	end
	return version
end

ns.version = GetVersion()

function ns.Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	print("|cff33ff99Fashion Journal|r: " .. msg)
end

-- Saved variables ---------------------------------------------------------

local DB_VERSION = 1

local function InitDB()
	local db = FashionJournalDB
	if type(db) ~= "table" then
		db = {}
		FashionJournalDB = db
	end
	db.version = db.version or DB_VERSION
	db.items = db.items or {}
	db.ui = db.ui or {}
	db.ui.filters = db.ui.filters or { missingOnly = false, usableOnly = false }
	db.probe = db.probe or {}
	db.probe.events = db.probe.events or {}
	ns.db = db
end

-- Internal callbacks (module -> module) --------------------------------------

local callbacks = {}

function ns.On(name, handler)
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], handler)
end

function ns.Fire(name, ...)
	for _, handler in ipairs(callbacks[name] or {}) do
		handler(...)
	end
end

-- Game events -------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Registers a handler for a game event. Several modules can listen to the same event.
-- Returns false if the client does not know the event.
function ns.RegisterEvent(event, handler)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		return false
	end
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], handler)
	return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, handler in ipairs(handlers[event] or {}) do
		handler(event, ...)
	end
end)

ns.RegisterEvent("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= ADDON_NAME then
		return
	end
	InitDB()
	ns.Fire("INITIALIZE")
end)

-- Helpers -----------------------------------------------------------------------

-- The dungeon from Data/Dungeons.lua the player is currently in, or nil.
function ns.GetCurrentDungeon()
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if instanceType ~= "party" and instanceType ~= "raid" then
		return nil
	end
	return ns.Model.FindByMapID(ns.Dungeons, instanceID)
end

-- Slash commands ----------------------------------------------------------

local function PrintHelp()
	ns.Print("version %s", ns.version)
	print("  /fj                  - open or close the journal")
	print("  /fj scan             - scan the current dungeon, or all dungeons (asks first)")
	print("  /fj probe            - run the API probe and show a copyable report")
	print("  /fj probe item <ids> - probe only the given item IDs (space separated)")
	print("  /fj probe data       - check every item in the add-on's dungeon data")
	print("  /fj probe clear      - clear the probe's event log")
end

local commands = {
	help = PrintHelp,
}

function ns.RegisterCommand(name, handler)
	commands[name] = handler
end

SLASH_FASHIONJOURNAL1 = "/fj"
SLASH_FASHIONJOURNAL2 = "/fashionjournal"
SlashCmdList.FASHIONJOURNAL = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		ns.UI.Toggle()
		return
	end
	local handler = commands[cmd]
	if handler then
		handler(rest)
	else
		PrintHelp()
	end
end
