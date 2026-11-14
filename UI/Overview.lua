local _, ns = ...

-- List of all dungeons with collected/total progress, from the saved scan results.

local Overview = {}
ns.Overview = Overview

local ROW_HEIGHT = 30
local ROW_GAP = 4

local rows = {}

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, 0.04)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("LEFT", 8, 0)
	row.name:SetJustifyH("LEFT")

	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetSize(160, 16)
	row.bar:SetPoint("RIGHT", -8, 0)
	row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	row.bar:SetStatusBarColor(0.2, 0.7, 0.3)
	row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
	row.bar.bg:SetAllPoints()
	row.bar.bg:SetColorTexture(0, 0, 0, 0.5)
	row.bar.text = row.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.bar.text:SetPoint("CENTER")

	row.name:SetPoint("RIGHT", row.bar, "LEFT", -8, 0)
	row:SetScript("OnClick", function(self)
		ns.UI.ShowDungeon(self.dungeon)
	end)
	return row
end

function Overview.Render(content, width)
	local getStatus = ns.Collection.GetStatus
	local current = ns.GetCurrentDungeon()
	local y = 0
	for i, dungeon in ipairs(ns.Dungeons) do
		local row = rows[i] or CreateRow(content)
		rows[i] = row
		row:SetParent(content)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.dungeon = dungeon

		local collected, total, checked = ns.Model.DungeonProgress(dungeon, getStatus)
		local name = dungeon.name
		if dungeon == current then
			name = name .. "  |cff33ff99(you are here)|r"
		end
		row.name:SetText(name)
		row.bar:SetMinMaxValues(0, math.max(total, 1))
		row.bar:SetValue(collected)
		row.bar.text:SetText(ns.Model.FormatProgress(collected, total, checked))
		row:Show()
		y = y + ROW_HEIGHT + ROW_GAP
	end
	for i = #ns.Dungeons + 1, #rows do
		rows[i]:Hide()
	end
	return y
end

function Overview.Hide()
	for _, row in ipairs(rows) do
		row:Hide()
	end
end
