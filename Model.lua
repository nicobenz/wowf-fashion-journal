local _, ns = ...

-- Pure logic: no WoW API calls, so it can be unit-tested (tests/run.lua).
-- Item status values:
--   "collected"  this exact item's appearance source is collected
--   "known"      the appearance is collected through another item
--   "missing"    not collected
--   "none"       the item has no transmog appearance (not counted)
--   nil          not checked yet

local Model = {}
ns.Model = Model

function Model.IsCollected(status)
	return status == "collected" or status == "known"
end

-- Returns collected, total, checked for a list of item IDs.
function Model.CountItems(itemIDs, getStatus)
	local collected, total, checked = 0, 0, 0
	for _, itemID in ipairs(itemIDs) do
		local status = getStatus(itemID)
		if status ~= "none" then
			total = total + 1
			if status ~= nil then
				checked = checked + 1
			end
			if Model.IsCollected(status) then
				collected = collected + 1
			end
		end
	end
	return collected, total, checked
end

function Model.DungeonProgress(dungeon, getStatus)
	local collected, total, checked = 0, 0, 0
	for _, boss in ipairs(dungeon.bosses) do
		local c, t, k = Model.CountItems(boss.items, getStatus)
		collected, total, checked = collected + c, total + t, checked + k
	end
	return collected, total, checked
end

-- "12/24", or "?/24" if nothing has been checked yet.
function Model.FormatProgress(collected, total, checked)
	if checked == 0 and total > 0 then
		return string.format("?/%d", total)
	end
	return string.format("%d/%d", collected, total)
end

-- Items to display for a boss. Filters only hide items; they never change counts.
--   filters.missingOnly  hide collected and known items
--   filters.usableOnly   hide items isUsable() reports as false (nil = unknown, shown)
function Model.VisibleItems(itemIDs, getStatus, isUsable, filters)
	local visible = {}
	for _, itemID in ipairs(itemIDs) do
		local status = getStatus(itemID)
		local show = status ~= "none"
		if show and filters.missingOnly and Model.IsCollected(status) then
			show = false
		end
		if show and filters.usableOnly and isUsable(itemID) == false then
			show = false
		end
		if show then
			visible[#visible + 1] = itemID
		end
	end
	return visible
end

function Model.AllItems(dungeons)
	local items = {}
	for _, dungeon in ipairs(dungeons) do
		for _, boss in ipairs(dungeon.bosses) do
			for _, itemID in ipairs(boss.items) do
				items[#items + 1] = itemID
			end
		end
	end
	return items
end

function Model.DungeonItems(dungeon)
	return Model.AllItems({ dungeon })
end

function Model.FindByMapID(dungeons, mapID)
	for _, dungeon in ipairs(dungeons) do
		if dungeon.mapID == mapID then
			return dungeon
		end
	end
	return nil
end

-- itemID -> { dungeon = ..., boss = ... } for every item in the data.
function Model.BuildItemIndex(dungeons)
	local index = {}
	for _, dungeon in ipairs(dungeons) do
		for _, boss in ipairs(dungeon.bosses) do
			for _, itemID in ipairs(boss.items) do
				index[itemID] = { dungeon = dungeon, boss = boss }
			end
		end
	end
	return index
end
