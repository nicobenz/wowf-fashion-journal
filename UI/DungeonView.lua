local _, ns = ...

-- One dungeon: each boss with its progress and a grid of item icons.

local DungeonView = {}
ns.DungeonView = DungeonView

local HEADER_HEIGHT = 22
local GAP = 6
local SECTION_GAP = 10

local headers, buttons = {}, {}

local function GetHeader(index, parent)
	local header = headers[index]
	if not header then
		header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header:SetJustifyH("LEFT")
		headers[index] = header
	end
	return header
end

local function GetButton(index, parent)
	local button = buttons[index]
	if not button then
		button = ns.ItemButton.Create(parent)
		buttons[index] = button
	end
	return button
end

function DungeonView.Render(content, width, dungeon, filters)
	local Model, Collection = ns.Model, ns.Collection
	local size = ns.ItemButton.SIZE
	local perRow = math.max(1, math.floor((width + GAP) / (size + GAP)))
	local y, buttonCount = 0, 0

	for bossIndex, boss in ipairs(dungeon.bosses) do
		local collected, total, checked = Model.CountItems(boss.items, Collection.GetStatus)
		local visible = Model.VisibleItems(boss.items, Collection.GetStatus, Collection.IsUsable, filters)

		local header = GetHeader(bossIndex, content)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 2, -y)
		local text = string.format("%s  |cffffffff%s|r", boss.name, Model.FormatProgress(collected, total, checked))
		if #visible == 0 then
			text = text .. "  |cff808080" .. (collected == total and "all collected" or "nothing to show") .. "|r"
		end
		header:SetText(text)
		header:Show()
		y = y + HEADER_HEIGHT

		for i, itemID in ipairs(visible) do
			buttonCount = buttonCount + 1
			local button = GetButton(buttonCount, content)
			local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", col * (size + GAP), -(y + row * (size + GAP)))
			button:SetItem(itemID)
			button:Show()
		end
		if #visible > 0 then
			y = y + math.ceil(#visible / perRow) * (size + GAP)
		end
		y = y + SECTION_GAP
	end

	for i = #dungeon.bosses + 1, #headers do
		headers[i]:Hide()
	end
	for i = buttonCount + 1, #buttons do
		buttons[i]:Hide()
	end
	return y
end

function DungeonView.Hide()
	for _, header in ipairs(headers) do
		header:Hide()
	end
	for _, button in ipairs(buttons) do
		button:Hide()
	end
end
