local _, ns = ...

-- Collection state per item. Results are saved account-wide in FashionJournalDB.items,
-- like the transmog collection itself. "Usable by this character" is per character and
-- kept in memory only.

local Collection = {}
ns.Collection = Collection

local bySource = {}      -- sourceID -> itemID
local byAppearance = {}  -- appearanceID -> { [itemID] = true }
local usable = {}        -- itemID -> bool (current character)
local dataItems = {}     -- itemID -> { dungeon, boss } for every item in Data/Dungeons.lua

local TC = C_TransmogCollection

local function Index(itemID, entry)
	if entry.source then
		bySource[entry.source] = itemID
	end
	if entry.appearance then
		byAppearance[entry.appearance] = byAppearance[entry.appearance] or {}
		byAppearance[entry.appearance][itemID] = true
	end
end

function Collection.Init()
	dataItems = ns.Model.BuildItemIndex(ns.Dungeons)
	for itemID, entry in pairs(ns.db.items) do
		if dataItems[itemID] then
			Index(itemID, entry)
		else
			ns.db.items[itemID] = nil -- item no longer in the data
		end
	end
end

function Collection.GetStatus(itemID)
	local entry = ns.db.items[itemID]
	return entry and entry.status
end

function Collection.IsUsable(itemID)
	return usable[itemID]
end

function Collection.GetEntry(itemID)
	return ns.db.items[itemID]
end

local function AnySourceCollected(appearanceID)
	local sources = TC.GetAllAppearanceSources(appearanceID)
	for _, sourceID in ipairs(sources or {}) do
		if TC.PlayerHasTransmogItemModifiedAppearance(sourceID) then
			return true
		end
	end
	return false
end

-- Checks one item against the collection and saves the result.
-- The item's data should be loaded (see Scanner); otherwise the stored source is used.
-- Returns the new status, or nil if the item could not be checked.
function Collection.Check(itemID)
	local old = ns.db.items[itemID]
	local appearanceID, sourceID = TC.GetItemInfo(itemID)
	if not sourceID and old and old.source then
		appearanceID, sourceID = old.appearance, old.source
	end

	local entry
	if sourceID then
		local status
		if TC.PlayerHasTransmogItemModifiedAppearance(sourceID) then
			status = "collected"
		elseif appearanceID and AnySourceCollected(appearanceID) then
			status = "known"
		else
			status = "missing"
		end
		local info = TC.GetSourceInfo(sourceID)
		if info then
			usable[itemID] = info.isValidSourceForPlayer and true or false
		end
		entry = { source = sourceID, appearance = appearanceID, status = status }
	elseif C_Item.IsItemDataCachedByID(itemID) then
		entry = { status = "none" } -- loaded, but no appearance
	else
		return nil -- not loaded yet; keep the old result
	end

	entry.checked = time()
	ns.db.items[itemID] = entry
	Index(itemID, entry)
	ns.Fire("ITEM_UPDATED", itemID, old and old.status, entry.status)
	return entry.status
end

-- An appearance source was added to or removed from the collection.
-- Re-checks only our items that use this source or appearance; no rescan.
local function OnSourceChanged(_, sourceID)
	local affected = {}
	if bySource[sourceID] then
		affected[bySource[sourceID]] = true
	end
	local info = TC.GetSourceInfo(sourceID)
	if info then
		if info.itemID and dataItems[info.itemID] then
			affected[info.itemID] = true
		end
		local appearanceID = info.visualID
		for itemID in pairs(appearanceID and byAppearance[appearanceID] or {}) do
			affected[itemID] = true
		end
	end
	for itemID in pairs(affected) do
		Collection.Check(itemID)
	end
end

ns.On("INITIALIZE", Collection.Init)
ns.RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED", OnSourceChanged)
ns.RegisterEvent("TRANSMOG_COLLECTION_SOURCE_REMOVED", OnSourceChanged)
