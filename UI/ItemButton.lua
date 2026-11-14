local _, ns = ...

-- One item icon in the dungeon view: quality border, collected check, tooltip,
-- Ctrl-click for the dressing room and Shift-click to link (via HandleModifiedItemClick).

local ItemButton = {}
ns.ItemButton = ItemButton

ItemButton.SIZE = 40

local QUESTION_MARK_ICON = 134400
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"

local STATUS_TEXT = {
	collected = { "Collected", 0.2, 1, 0.2 },
	known = { "Appearance collected from another item", 0.4, 0.75, 1 },
	missing = { "Not collected", 1, 0.3, 0.3 },
}

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(self.itemID)
	local status = ns.Collection.GetStatus(self.itemID)
	local line = STATUS_TEXT[status]
	GameTooltip:AddLine(" ")
	if line then
		GameTooltip:AddLine("Fashion Journal: " .. line[1], line[2], line[3], line[4])
	else
		GameTooltip:AddLine("Fashion Journal: not checked yet", 0.6, 0.6, 0.6)
	end
	if ns.Collection.IsUsable(self.itemID) == false then
		GameTooltip:AddLine("Your current character can't use this item.", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function OnLeave()
	GameTooltip:Hide()
end

local function OnClick(self)
	local _, link = C_Item.GetItemInfo(self.itemID)
	if link then
		HandleModifiedItemClick(link)
	end
end

local function SetItem(self, itemID)
	self.itemID = itemID
	self.icon:SetTexture(C_Item.GetItemIconByID(itemID) or QUESTION_MARK_ICON)

	local quality = C_Item.GetItemQualityByID(itemID)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		self.border:SetVertexColor(color.r, color.g, color.b)
		self.border:Show()
	else
		self.border:Hide()
	end

	local status = ns.Collection.GetStatus(itemID)
	local collected = ns.Model.IsCollected(status)
	self.icon:SetDesaturated(not collected)
	self.icon:SetAlpha(collected and 1 or 0.5)
	self.check:SetShown(collected)
	if status == "known" then
		self.check:SetVertexColor(0.4, 0.75, 1)
	else
		self.check:SetVertexColor(1, 1, 1)
	end
	self.unknown:SetShown(status == nil)

	if GameTooltip:IsOwned(self) then
		OnEnter(self)
	end
end

function ItemButton.Create(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(ItemButton.SIZE, ItemButton.SIZE)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()

	b.border = b:CreateTexture(nil, "OVERLAY")
	b.border:SetTexture("Interface\\Common\\WhiteIconFrame")
	b.border:SetAllPoints()

	b.check = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.check:SetTexture(CHECK_TEXTURE)
	b.check:SetSize(18, 18)
	b.check:SetPoint("BOTTOMRIGHT", 4, -4)

	b.unknown = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	b.unknown:SetPoint("CENTER")
	b.unknown:SetText("?")

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnEnter", OnEnter)
	b:SetScript("OnLeave", OnLeave)
	b:SetScript("OnClick", OnClick)

	b.SetItem = SetItem
	return b
end
