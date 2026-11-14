local _, ns = ...

-- A simple window with a read-only, copyable multi-line text box.

local FRAME_NAME = "FashionJournalReportFrame"
local frame

local function CreateReportFrame()
	local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(780, 540)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if f.TitleText then
		f.TitleText:SetText("Fashion Journal - probe report")
	end

	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 40)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(730)
	edit:SetMaxLetters(0)
	edit:SetScript("OnEscapePressed", function()
		f:Hide()
	end)
	-- Read-only: undo any typing by restoring the report text.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(self.reportText or "")
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	f.editBox = edit

	local selectAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	selectAll:SetSize(110, 22)
	selectAll:SetPoint("BOTTOMRIGHT", -12, 10)
	selectAll:SetText("Select all")
	selectAll:SetScript("OnClick", function()
		edit:SetFocus()
		edit:HighlightText()
	end)

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 14, 15)
	hint:SetPoint("RIGHT", selectAll, "LEFT", -8, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Select all, then Ctrl+C to copy. The report is also written to WTF\\...\\SavedVariables\\FashionJournal.lua on logout or /reload.")

	table.insert(UISpecialFrames, FRAME_NAME)
	return f
end

function ns.ShowReport(text)
	frame = frame or CreateReportFrame()
	frame.editBox.reportText = text
	frame.editBox:SetText(text)
	frame:Show()
	frame.editBox:SetFocus()
	frame.editBox:HighlightText()
end
