local _, ns = ...

-- The journal window: header (back button, title, filters, scan button), a scrolling
-- content area that shows either the overview or one dungeon, and a status line.

local UI = {}
ns.UI = UI

local FRAME_NAME = "FashionJournalFrame"
local POPUP_FULL_SCAN = "FASHIONJOURNAL_FULL_SCAN"

local frame
local view = "overview" -- or "dungeon"
local shownDungeon
local refreshQueued = false

-- Full scan confirmation ----------------------------------------------------------

StaticPopupDialogs[POPUP_FULL_SCAN] = {
	text = "Fashion Journal: check all %s dungeons (%s items) against your collection?\nThis takes a few seconds.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		ns.Scanner.ScanAll()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function UI.ConfirmFullScan()
	StaticPopup_Show(POPUP_FULL_SCAN, tostring(#ns.Dungeons), tostring(#ns.Model.AllItems(ns.Dungeons)))
end

-- Layout --------------------------------------------------------------------------

local function SavePosition(f)
	local point, _, relativePoint, x, y = f:GetPoint()
	ns.db.ui.point = { point, relativePoint, x, y }
end

local function CreateCheck(parent, label, filterKey)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check.Text:SetText(label)
	check:SetScript("OnClick", function(self)
		ns.db.ui.filters[filterKey] = self:GetChecked() and true or false
		UI.Refresh()
	end)
	check.filterKey = filterKey
	return check
end

local function CreateMainFrame()
	local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(560, 560)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)
	local point = ns.db.ui.point
	if point then
		f:SetPoint(point[1], UIParent, point[2], point[3], point[4])
	else
		f:SetPoint("CENTER")
	end
	f.TitleText:SetText("Fashion Journal")
	table.insert(UISpecialFrames, FRAME_NAME)

	f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.back:SetSize(90, 22)
	f.back:SetPoint("TOPLEFT", 12, -30)
	f.back:SetText("< Dungeons")
	f.back:SetScript("OnClick", function()
		UI.ShowOverview()
	end)

	f.scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.scan:SetSize(100, 22)
	f.scan:SetPoint("TOPRIGHT", -12, -30)
	f.scan:SetScript("OnClick", function()
		if view == "dungeon" and shownDungeon then
			ns.Scanner.ScanDungeon(shownDungeon)
		else
			UI.ConfirmFullScan()
		end
	end)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 110, -34)
	f.title:SetPoint("RIGHT", f.scan, "LEFT", -8, 0)
	f.title:SetJustifyH("LEFT")

	f.missingOnly = CreateCheck(f, "Missing only", "missingOnly")
	f.missingOnly:SetPoint("TOPLEFT", 12, -56)
	f.usableOnly = CreateCheck(f, "Usable by this character", "usableOnly")
	f.usableOnly:SetPoint("LEFT", f.missingOnly.Text, "RIGHT", 16, 0)

	f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.scroll:SetPoint("TOPLEFT", 14, -86)
	f.scroll:SetPoint("BOTTOMRIGHT", -32, 30)
	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(500, 1)
	f.scroll:SetScrollChild(f.content)

	f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", 14, 10)
	f.status:SetPoint("BOTTOMRIGHT", -14, 10)
	f.status:SetJustifyH("LEFT")

	f:SetScript("OnShow", function()
		UI.Refresh()
	end)
	return f
end

-- Rendering -----------------------------------------------------------------------

local function StatusText()
	if ns.Scanner.IsRunning() then
		local label, done, total = ns.Scanner.GetProgress()
		return string.format("Checking %s: %d/%d", label, done, total)
	end
	if view == "dungeon" then
		return "Collected appearances are account-wide. Ctrl-click: dressing room, Shift-click: link."
	end
	if ns.db.lastFullScan then
		return "Last full scan: " .. date("%Y-%m-%d %H:%M", ns.db.lastFullScan)
	end
	return "Not scanned yet: press \"Scan all\" to check your collection."
end

function UI.Refresh()
	refreshQueued = false
	if not frame or not frame:IsShown() then
		return
	end
	local filters = ns.db.ui.filters
	frame.missingOnly:SetChecked(filters.missingOnly)
	frame.usableOnly:SetChecked(filters.usableOnly)
	frame.scan:SetEnabled(not ns.Scanner.IsRunning())

	local width = frame.scroll:GetWidth()
	if width <= 0 then
		width = 500
	end
	frame.content:SetWidth(width)

	local height
	if view == "dungeon" and shownDungeon then
		ns.Overview.Hide()
		local collected, total, checked = ns.Model.DungeonProgress(shownDungeon, ns.Collection.GetStatus)
		frame.title:SetText(string.format("%s  |cffffffff%s|r", shownDungeon.name,
			ns.Model.FormatProgress(collected, total, checked)))
		frame.back:Show()
		frame.scan:SetText("Rescan")
		frame.missingOnly:Show()
		frame.usableOnly:Show()
		height = ns.DungeonView.Render(frame.content, width, shownDungeon, filters)
	else
		ns.DungeonView.Hide()
		frame.title:SetText("Dungeons")
		frame.back:Hide()
		frame.scan:SetText("Scan all")
		frame.missingOnly:Hide()
		frame.usableOnly:Hide()
		height = ns.Overview.Render(frame.content, width)
	end
	frame.content:SetHeight(math.max(height, 1))
	frame.status:SetText(StatusText())
end

-- Coalesces bursts of updates (e.g. during a scan) into one redraw.
function UI.QueueRefresh()
	if refreshQueued or not (frame and frame:IsShown()) then
		return
	end
	refreshQueued = true
	C_Timer.After(0.1, UI.Refresh)
end

-- Navigation ------------------------------------------------------------------------

local function EnsureFrame()
	frame = frame or CreateMainFrame()
	return frame
end

function UI.ShowOverview()
	EnsureFrame()
	view, shownDungeon = "overview", nil
	frame.scroll:SetVerticalScroll(0)
	frame:Show()
	UI.Refresh()
end

-- Shows one dungeon and re-checks its items (a few dozen, so no confirmation needed).
function UI.ShowDungeon(dungeon)
	EnsureFrame()
	view, shownDungeon = "dungeon", dungeon
	frame.scroll:SetVerticalScroll(0)
	frame:Show()
	UI.Refresh()
	ns.Scanner.ScanDungeon(dungeon)
end

-- /fj: inside a known dungeon open that dungeon, otherwise the overview.
function UI.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
		return
	end
	local current = ns.GetCurrentDungeon()
	if current then
		UI.ShowDungeon(current)
	else
		UI.ShowOverview()
	end
end

-- /fj scan: the current dungeon, or everything after confirmation.
ns.RegisterCommand("scan", function()
	local current = ns.GetCurrentDungeon()
	if current then
		ns.Scanner.ScanDungeon(current)
		ns.Print("checking %s...", current.name)
	else
		UI.ConfirmFullScan()
	end
end)

ns.On("ITEM_UPDATED", UI.QueueRefresh)
ns.On("SCAN_STARTED", UI.QueueRefresh)
ns.On("SCAN_PROGRESS", UI.QueueRefresh)
ns.On("SCAN_FINISHED", function(_, isFull)
	UI.QueueRefresh()
	if isFull then
		local collected, total = ns.Model.CountItems(ns.Model.AllItems(ns.Dungeons), ns.Collection.GetStatus)
		ns.Print("scan finished: %d of %d dungeon appearances collected.", collected, total)
	end
end)

-- Announce dungeon appearances collected live (e.g. during a run), not scan catch-ups.
ns.On("ITEM_UPDATED", function(itemID, oldStatus, newStatus)
	if not ns.Scanner.IsRunning() and oldStatus and not ns.Model.IsCollected(oldStatus) and ns.Model.IsCollected(newStatus) then
		local _, link = C_Item.GetItemInfo(itemID)
		ns.Print("new appearance: %s", link or ("item " .. itemID))
	end
end)
