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
	db.probe = db.probe or {}
	db.probe.events = db.probe.events or {}
	ns.db = db
end

-- Events --------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Registers a handler for an event. Several modules can listen to the same event.
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
	local list = handlers[event]
	if not list then
		return
	end
	for _, handler in ipairs(list) do
		handler(event, ...)
	end
end)

ns.RegisterEvent("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= ADDON_NAME then
		return
	end
	InitDB()
	if ns.OnInitialize then
		ns.OnInitialize()
	end
end)

-- Slash commands ----------------------------------------------------------

local function PrintHelp()
	ns.Print("version %s", ns.version)
	print("  /fj probe            - run the API probe and show a copyable report")
	print("  /fj probe item <ids> - probe only the given item IDs (space separated)")
	print("  /fj probe clear      - clear the probe's event log")
end

local commands = {}

function ns.RegisterCommand(name, handler)
	commands[name] = handler
end

SLASH_FASHIONJOURNAL1 = "/fj"
SLASH_FASHIONJOURNAL2 = "/fashionjournal"
SlashCmdList.FASHIONJOURNAL = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()

	local handler = commands[cmd]
	if handler then
		handler(rest)
	elseif cmd == "" then
		-- The journal window does not exist yet (see docs/PLAN.md, phase 4).
		PrintHelp()
	else
		PrintHelp()
	end
end
