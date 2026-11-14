local ADDON_NAME, ns = ...

-- Development probe: reports what the WoW Forever client offers for this add-on.
-- Run /fj probe and paste the report back into the project discussion.
-- Every call is wrapped in pcall, so a missing or failing function is reported, not raised.

local Probe = {}
ns.Probe = Probe

-- Deadmines drops from the original game. Used only if no other items are available.
local SAMPLE_ITEMS = { 5193, 5191, 5202 }
local MAX_INSTANCES = 60          -- cap for the Encounter Journal dump
local MAX_ITEM_CHECKS = 40        -- cap for the detailed transmog checks
local ITEM_LOAD_TIMEOUT = 8       -- seconds to wait for item data
local MAX_LOG_ENTRIES = 300

local API_PATHS = {
	-- transmog collection
	"C_TransmogCollection.GetItemInfo",
	"C_TransmogCollection.GetSourceInfo",
	"C_TransmogCollection.GetAppearanceInfoBySource",
	"C_TransmogCollection.GetAppearanceSources",
	"C_TransmogCollection.GetAllAppearanceSources",
	"C_TransmogCollection.GetSourceItemID",
	"C_TransmogCollection.PlayerHasTransmog",
	"C_TransmogCollection.PlayerHasTransmogByItemInfo",
	"C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance",
	"C_TransmogCollection.PlayerKnowsSource",
	"C_TransmogCollection.PlayerCanCollectSource",
	"C_TransmogCollection.AccountCanCollectSource",
	-- encounter journal
	"C_EncounterJournal.GetInstanceForGameMap",
	"C_EncounterJournal.GetLootInfoByIndex",
	"C_EncounterJournal.ResetSlotFilter",
	"C_EncounterJournal.InstanceHasLoot",
	"EJ_GetNumTiers",
	"EJ_GetTierInfo",
	"EJ_GetCurrentTier",
	"EJ_SelectTier",
	"EJ_GetInstanceByIndex",
	"EJ_GetInstanceInfo",
	"EJ_GetInstanceForMap",
	"EJ_SelectInstance",
	"EJ_GetEncounterInfoByIndex",
	"EJ_GetNumLoot",
	"EJ_SetLootFilter",
	"EJ_GetDifficulty",
	"EJ_SetDifficulty",
	-- items, maps, misc
	"C_Item.GetItemInfo",
	"C_Item.RequestLoadItemDataByID",
	"C_Item.IsDressableItemByID",
	"Item.CreateFromItemID",
	"C_Map.GetBestMapForUnit",
	"C_GameRules.IsGameRuleActive",
	"C_EventUtils.IsEventValid",
	"GetInstanceInfo",
	"DressUpItemLink",
	"C_Timer.After",
}

local EVENTS = {
	"TRANSMOG_COLLECTION_SOURCE_ADDED",
	"TRANSMOG_COLLECTION_SOURCE_REMOVED",
	"TRANSMOG_COLLECTION_UPDATED",
	"TRANSMOG_COLLECTION_ITEM_UPDATE",
	"ENCOUNTER_END",
	"ENCOUNTER_LOOT_RECEIVED",
	"EJ_LOOT_DATA_RECIEVED",
	"PLAYER_ENTERING_WORLD",
}

-- Helpers -------------------------------------------------------------------

local function pack(...)
	return { n = select("#", ...), ... }
end

local function resolve(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[part]
	end
	return value
end

local function fmt(value, depth)
	depth = depth or 0
	local t = type(value)
	if t == "string" then
		return '"' .. (value:gsub("\n", "\\n")) .. '"'
	elseif t == "table" then
		if depth >= 2 then
			return "{...}"
		end
		local keys = {}
		for k in pairs(value) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, k in ipairs(keys) do
			parts[#parts + 1] = tostring(k) .. "=" .. fmt(value[k], depth + 1)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function safeFmt(value)
	local ok, text = pcall(fmt, value)
	return ok and text or "<unprintable>"
end

-- Calls a function by its global path. Returns a packed result:
-- r.missing (function not found), r.ok, r.err, and r[1..r.n] for the return values.
local function call(path, ...)
	local fn = resolve(path)
	if type(fn) ~= "function" then
		return { missing = true, n = 0 }
	end
	local r = pack(pcall(fn, ...))
	local result = { ok = r[1], n = r.n - 1 }
	if not r[1] then
		result.err = r[2]
		result.n = 0
		return result
	end
	for i = 2, r.n do
		result[i - 1] = r[i]
	end
	return result
end

local function describe(r)
	if r.missing then
		return "MISSING"
	elseif not r.ok then
		return "ERROR: " .. tostring(r.err)
	elseif r.n == 0 then
		return "(no return values)"
	end
	local parts = {}
	for i = 1, r.n do
		parts[i] = safeFmt(r[i])
	end
	return table.concat(parts, ", ")
end

-- Report ----------------------------------------------------------------------

local Report = {}
Report.__index = Report

function Report.new()
	return setmetatable({ lines = {} }, Report)
end

function Report:Add(text, ...)
	if select("#", ...) > 0 then
		text = text:format(...)
	end
	self.lines[#self.lines + 1] = text
end

function Report:Section(title)
	self:Add("")
	self:Add("== %s ==", title)
end

function Report:Call(label, path, ...)
	local r = call(path, ...)
	self:Add("%s -> %s", label or path, describe(r))
	return r
end

function Report:Text()
	return table.concat(self.lines, "\n")
end

-- Sections --------------------------------------------------------------------

function Probe:Client(rep)
	rep:Section("Client")
	local version, build, buildDate, interface = GetBuildInfo()
	rep:Add("build: %s (%s, %s), interface %s", tostring(version), tostring(build), tostring(buildDate), tostring(interface))
	rep:Add("WOW_PROJECT_ID=%s  WOW_PROJECT_CAMELOT=%s  WOW_PROJECT_MAINLINE=%s",
		tostring(WOW_PROJECT_ID), tostring(_G.WOW_PROJECT_CAMELOT), tostring(_G.WOW_PROJECT_MAINLINE))
	rep:Add("locale: %s", tostring(GetLocale()))
	local _, class = UnitClass("player")
	local _, race = UnitRace("player")
	rep:Add("player: level %s %s %s", tostring(UnitLevel("player")), tostring(race), tostring(class))
	rep:Add("addon: %s %s", ADDON_NAME, ns.version)

	-- Game rules: report the journal rule and every rule that is active.
	if Enum and Enum.GameRule and C_GameRules and C_GameRules.IsGameRuleActive then
		local ejRule = Enum.GameRule.EncounterJournalDisabled
		if ejRule then
			rep:Call("GameRule EncounterJournalDisabled", "C_GameRules.IsGameRuleActive", ejRule)
		else
			rep:Add("GameRule EncounterJournalDisabled -> enum value MISSING")
		end
		local active = {}
		for name, id in pairs(Enum.GameRule) do
			local ok, isActive = pcall(C_GameRules.IsGameRuleActive, id)
			if ok and isActive then
				active[#active + 1] = name
			end
		end
		table.sort(active)
		rep:Add("active game rules (%d): %s", #active, table.concat(active, ", "))
	else
		rep:Add("game rules: Enum.GameRule or C_GameRules MISSING")
	end
end

function Probe:Apis(rep)
	rep:Section("API presence")
	local missing = {}
	for _, path in ipairs(API_PATHS) do
		if type(resolve(path)) ~= "function" then
			missing[#missing + 1] = path
		end
	end
	rep:Add("checked %d functions, %d missing", #API_PATHS, #missing)
	for _, path in ipairs(missing) do
		rep:Add("  MISSING: %s", path)
	end

	if C_EventUtils and C_EventUtils.IsEventValid then
		local invalid = {}
		for _, event in ipairs(EVENTS) do
			local ok, valid = pcall(C_EventUtils.IsEventValid, event)
			if not (ok and valid) then
				invalid[#invalid + 1] = event
			end
		end
		rep:Add("checked %d events, %d unknown%s", #EVENTS, #invalid,
			#invalid > 0 and (": " .. table.concat(invalid, ", ")) or "")
	end
end

function Probe:Location(rep, ctx)
	rep:Section("Location")
	rep:Call("IsInInstance", "IsInInstance")
	rep:Add("GetInstanceInfo returns: name, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, lfgDungeonID")
	rep:Call("GetInstanceInfo", "GetInstanceInfo")
	local uiMap = call("C_Map.GetBestMapForUnit", "player")
	rep:Add("C_Map.GetBestMapForUnit(player) -> %s", describe(uiMap))
	local uiMapID = uiMap.ok and uiMap[1] or nil
	if uiMapID then
		local r = rep:Call("C_EncounterJournal.GetInstanceForGameMap", "C_EncounterJournal.GetInstanceForGameMap", uiMapID)
		local legacy = rep:Call("EJ_GetInstanceForMap", "EJ_GetInstanceForMap", uiMapID)
		local journalInstanceID = (r.ok and r[1]) or (legacy.ok and legacy[1]) or nil
		if journalInstanceID and journalInstanceID ~= 0 then
			ctx.currentJournalInstance = journalInstanceID
		end
	end
end

local function CollectInstances(rep, numTiers)
	local instances, seen = {}, {}
	for tier = 1, numTiers do
		call("EJ_SelectTier", tier)
		for _, isRaid in ipairs({ false, true }) do
			for index = 1, 500 do
				local r = call("EJ_GetInstanceByIndex", index, isRaid)
				-- returns: instanceID, name, description, bgImage, buttonImage1, loreImage,
				--          buttonImage2, dungeonAreaMapID, link, shouldDisplayDifficulty, mapID
				if not r.ok or not r[1] then
					if not r.ok and not r.missing then
						rep:Add("EJ_GetInstanceByIndex(%d, %s) -> %s", index, tostring(isRaid), describe(r))
					end
					break
				end
				if not seen[r[1]] then
					seen[r[1]] = true
					instances[#instances + 1] = {
						id = r[1], name = r[2], isRaid = isRaid, tier = tier,
						areaMapID = r[8], mapID = r[11],
					}
				end
			end
		end
	end
	return instances
end

local function DumpInstanceLoot(rep, inst, ctx)
	call("EJ_SelectTier", inst.tier)
	call("EJ_SelectInstance", inst.id)
	call("EJ_SetLootFilter", 0, 0)
	call("C_EncounterJournal.ResetSlotFilter")

	local bosses, bossByEncounter = {}, {}
	for index = 1, 50 do
		-- returns: name, description, journalEncounterID, rootSectionID, link,
		--          journalInstanceID, dungeonEncounterID, instanceID
		local r = call("EJ_GetEncounterInfoByIndex", index, inst.id)
		if not r.ok or not r[1] then
			break
		end
		local boss = { name = r[1], journalEncounterID = r[3], dungeonEncounterID = r[7], items = {} }
		bosses[#bosses + 1] = boss
		if boss.journalEncounterID then
			bossByEncounter[boss.journalEncounterID] = boss
		end
	end

	local numLoot = call("EJ_GetNumLoot")
	local lootCount = numLoot.ok and numLoot[1] or 0
	local unassigned = { name = "(no boss)", items = {} }
	local itemIDs = {}
	for index = 1, lootCount do
		local r = call("C_EncounterJournal.GetLootInfoByIndex", index)
		local info = r.ok and r[1]
		if type(info) == "table" and info.itemID then
			local boss = bossByEncounter[info.encounterID] or unassigned
			boss.items[#boss.items + 1] = info
			itemIDs[#itemIDs + 1] = info.itemID
		end
	end

	rep:Add("[%s] %s  journalInstanceID=%s mapID=%s areaMapID=%s tier=%s  bosses=%d loot=%d",
		inst.isRaid and "R" or "D", tostring(inst.name), tostring(inst.id), tostring(inst.mapID),
		tostring(inst.areaMapID), tostring(inst.tier), #bosses, lootCount)

	if #unassigned.items > 0 then
		bosses[#bosses + 1] = unassigned
	end
	for _, boss in ipairs(bosses) do
		local parts = {}
		for _, info in ipairs(boss.items) do
			parts[#parts + 1] = string.format("%d %s/%s/%s", info.itemID, tostring(info.name),
				tostring(info.slot), tostring(info.armorType))
		end
		rep:Add("   %s (journal=%s, encounter=%s): %s", tostring(boss.name), tostring(boss.journalEncounterID),
			tostring(boss.dungeonEncounterID), #parts > 0 and table.concat(parts, "; ") or "-")
	end

	if ctx.currentJournalInstance == inst.id then
		ctx.instanceItems = itemIDs
	end
	return lootCount
end

function Probe:EncounterJournal(rep, ctx)
	rep:Section("Encounter Journal data")
	local tiers = call("EJ_GetNumTiers")
	if not tiers.ok or not tiers[1] then
		rep:Add("EJ_GetNumTiers -> %s (journal data not available)", describe(tiers))
		return
	end
	local numTiers = tiers[1]
	local tierNames = {}
	for tier = 1, numTiers do
		local r = call("EJ_GetTierInfo", tier)
		tierNames[#tierNames + 1] = string.format("%d=%s", tier, tostring(r.ok and r[1]))
	end
	rep:Add("tiers (%d): %s", numTiers, table.concat(tierNames, ", "))
	rep:Call("EJ_GetCurrentTier", "EJ_GetCurrentTier")
	rep:Call("EJ_GetDifficulty", "EJ_GetDifficulty")

	local instances = CollectInstances(rep, numTiers)
	rep:Add("instances found: %d (showing up to %d)", #instances, MAX_INSTANCES)

	local totalLoot = 0
	for i = 1, math.min(#instances, MAX_INSTANCES) do
		totalLoot = totalLoot + DumpInstanceLoot(rep, instances[i], ctx)
	end
	rep:Add("total loot entries: %d%s", totalLoot,
		totalLoot == 0 and #instances > 0 and " (loot may still be loading: run /fj probe again in a few seconds)" or "")
end

function Probe:DescribeItem(rep, itemID)
	rep:Add("")
	rep:Add("- item %d", itemID)
	local info = call("C_Item.GetItemInfo", itemID)
	if info.ok and info[1] then
		-- returns: name, link, quality, itemLevel, minLevel, type, subType, stackCount,
		--          equipLoc, texture, sellPrice, classID, subclassID, bindType
		rep:Add("  %s  quality=%s minLevel=%s equipLoc=%s class=%s/%s bindType=%s",
			tostring(info[1]), tostring(info[3]), tostring(info[5]), tostring(info[9]),
			tostring(info[12]), tostring(info[13]), tostring(info[14]))
	else
		rep:Add("  C_Item.GetItemInfo -> %s (item data not loaded or invalid item)", describe(info))
	end
	rep:Call("  C_Item.IsDressableItemByID", "C_Item.IsDressableItemByID", itemID)

	local r = rep:Call("  TC.GetItemInfo -> appearanceID, sourceID", "C_TransmogCollection.GetItemInfo", itemID)
	local appearanceID = r.ok and r[1] or nil
	local sourceID = r.ok and r[2] or nil
	rep:Call("  TC.PlayerHasTransmog(itemID)", "C_TransmogCollection.PlayerHasTransmog", itemID)

	if sourceID then
		rep:Call("  TC.GetSourceInfo", "C_TransmogCollection.GetSourceInfo", sourceID)
		rep:Call("  TC.PlayerHasTransmogItemModifiedAppearance", "C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance", sourceID)
		rep:Call("  TC.PlayerKnowsSource", "C_TransmogCollection.PlayerKnowsSource", sourceID)
		rep:Call("  TC.PlayerCanCollectSource -> hasItemData, canCollect", "C_TransmogCollection.PlayerCanCollectSource", sourceID)
		rep:Call("  TC.AccountCanCollectSource -> hasItemData, canCollect", "C_TransmogCollection.AccountCanCollectSource", sourceID)
		rep:Call("  TC.GetAppearanceInfoBySource", "C_TransmogCollection.GetAppearanceInfoBySource", sourceID)
	end

	if appearanceID then
		local all = call("C_TransmogCollection.GetAllAppearanceSources", appearanceID)
		if all.ok and type(all[1]) == "table" then
			local parts, collected = {}, 0
			for _, id in ipairs(all[1]) do
				local has = call("C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance", id)
				local isCollected = has.ok and has[1]
				if isCollected then
					collected = collected + 1
				end
				parts[#parts + 1] = tostring(id) .. (isCollected and "*" or "")
			end
			rep:Add("  TC.GetAllAppearanceSources -> %d sources, %d collected (*): %s",
				#all[1], collected, table.concat(parts, " "))
		else
			rep:Add("  TC.GetAllAppearanceSources -> %s", describe(all))
		end
	end
end

-- Loads item data for all items, then calls done(). Gives up after a timeout,
-- so unknown item IDs cannot stall the probe.
local function LoadItems(itemIDs, done)
	local pending, finished = #itemIDs, false
	local function finish()
		if not finished then
			finished = true
			done()
		end
	end
	if pending == 0 or not (Item and Item.CreateFromItemID) then
		finish()
		return
	end
	for _, itemID in ipairs(itemIDs) do
		local ok = pcall(function()
			local item = Item:CreateFromItemID(itemID)
			item:ContinueOnItemLoad(function()
				pending = pending - 1
				if pending == 0 then
					finish()
				end
			end)
		end)
		if not ok then
			pending = pending - 1
		end
	end
	if pending <= 0 then
		finish()
	else
		C_Timer.After(ITEM_LOAD_TIMEOUT, finish)
	end
end

function Probe:EventLog(rep)
	rep:Section("Event log (since last /fj probe clear)")
	local events = ns.db.probe.events
	if #events == 0 then
		rep:Add("(empty: collect an appearance in a dungeon, then run /fj probe again)")
	end
	for _, line in ipairs(events) do
		rep:Add(line)
	end
end

-- Data check: verifies every item in Data/Dungeons.lua in the client.
local BIND_NAMES = { [0] = "none", [1] = "BoP", [2] = "BoE", [3] = "BoU", [4] = "quest" }

function Probe:CheckData(rep, done)
	rep:Section("Data check (Data/Dungeons.lua)")
	local itemIDs = {}
	for _, dungeon in ipairs(ns.Dungeons or {}) do
		for _, boss in ipairs(dungeon.bosses) do
			for _, itemID in ipairs(boss.items) do
				itemIDs[#itemIDs + 1] = itemID
			end
		end
	end
	rep:Add("%d dungeons, %d items. Flags: !BIND = not bind-on-pickup, !QUALITY = below Uncommon, !APPEARANCE = no transmog source, !LOAD = no item data",
		#(ns.Dungeons or {}), #itemIDs)

	LoadItems(itemIDs, function()
		local problems, collected = 0, 0
		for _, dungeon in ipairs(ns.Dungeons or {}) do
			rep:Add("")
			rep:Add("[%s] %s (mapID %d)", dungeon.key, dungeon.name, dungeon.mapID)
			for _, boss in ipairs(dungeon.bosses) do
				rep:Add("  %s (encounter %d)", boss.name, boss.encounterID)
				for _, itemID in ipairs(boss.items) do
					local info = call("C_Item.GetItemInfo", itemID)
					local name, quality, bindType = info[1], info[3], info[14]
					local tc = call("C_TransmogCollection.GetItemInfo", itemID)
					local appearanceID, sourceID = tc.ok and tc[1], tc.ok and tc[2]
					local has = sourceID and call("C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance", sourceID)
					local isCollected = has and has.ok and has[1]
					if isCollected then
						collected = collected + 1
					end

					local flags = {}
					if not (info.ok and name) then
						flags[#flags + 1] = "!LOAD"
					else
						if bindType ~= 1 then flags[#flags + 1] = "!BIND" end
						if (quality or 0) < 2 then flags[#flags + 1] = "!QUALITY" end
					end
					if not sourceID then
						flags[#flags + 1] = "!APPEARANCE"
					end
					if #flags > 0 then
						problems = problems + 1
					end
					rep:Add("    %d %s  q=%s bind=%s appearance=%s source=%s %s %s", itemID, tostring(name),
						tostring(quality), BIND_NAMES[bindType] or tostring(bindType), tostring(appearanceID),
						tostring(sourceID), isCollected and "COLLECTED" or "missing", table.concat(flags, " "))
				end
			end
		end
		rep:Add("")
		rep:Add("summary: %d items, %d collected, %d with problems", #itemIDs, collected, problems)
		done()
	end)
end

-- Entry point -----------------------------------------------------------------

local function ParseItemIDs(text)
	local ids = {}
	for id in text:gmatch("%d+") do
		ids[#ids + 1] = tonumber(id)
	end
	return ids
end

local function Finish(rep)
	local text = rep:Text()
	ns.db.probe.lastReport = text
	ns.db.probe.lastReportAt = time()
	ns.ShowReport(text)
end

function Probe:Run(args)
	args = strtrim(args or "")
	local sub, rest = args:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()

	if sub == "clear" then
		wipe(ns.db.probe.events)
		ns.Print("probe event log cleared.")
		return
	end

	local rep, ctx = Report.new(), {}
	rep:Add("Fashion Journal probe report, %s", date("%Y-%m-%d %H:%M:%S"))

	if sub == "data" then
		local version, build = GetBuildInfo()
		rep:Add("build: %s (%s)", tostring(version), tostring(build))
		ns.Print("checking item data...")
		self:CheckData(rep, function()
			Finish(rep)
		end)
		return
	end

	self:Client(rep)
	self:Apis(rep)

	local itemIDs, itemSource
	if sub == "item" then
		itemIDs, itemSource = ParseItemIDs(rest), "given on the command line"
	else
		self:Location(rep, ctx)
		self:EncounterJournal(rep, ctx)
		if ctx.instanceItems and #ctx.instanceItems > 0 then
			itemIDs, itemSource = ctx.instanceItems, "journal loot of the current instance"
		else
			itemIDs, itemSource = SAMPLE_ITEMS, "built-in samples (Deadmines)"
		end
	end

	local limited = {}
	for i = 1, math.min(#itemIDs, MAX_ITEM_CHECKS) do
		limited[i] = itemIDs[i]
	end
	rep:Section(string.format("Transmog checks: %d of %d items, %s", #limited, #itemIDs, itemSource))

	ns.Print("loading item data for %d items...", #limited)
	LoadItems(limited, function()
		for _, itemID in ipairs(limited) do
			self:DescribeItem(rep, itemID)
		end
		self:EventLog(rep)
		Finish(rep)
	end)
end

-- Event logger ------------------------------------------------------------------

local function Log(text, ...)
	if not ns.db then
		return
	end
	local events = ns.db.probe.events
	events[#events + 1] = date("%Y-%m-%d %H:%M:%S ") .. text:format(...)
	while #events > MAX_LOG_ENTRIES do
		table.remove(events, 1)
	end
end

local function InstanceTag()
	local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
	return string.format("[%s %s id=%s diff=%s]", tostring(name), tostring(instanceType), tostring(instanceID), tostring(difficultyID))
end

local function SourceTag(sourceID)
	local r = call("C_TransmogCollection.GetSourceInfo", sourceID)
	local info = r.ok and r[1]
	if type(info) == "table" then
		return string.format("item=%s %s visual=%s", tostring(info.itemID), tostring(info.name), tostring(info.visualID))
	end
	return "source info " .. describe(r)
end

local function OnLogEvent(event, ...)
	if event == "TRANSMOG_COLLECTION_SOURCE_ADDED" or event == "TRANSMOG_COLLECTION_SOURCE_REMOVED" then
		local sourceID = ...
		Log("%s source=%s %s %s", event, tostring(sourceID), SourceTag(sourceID), InstanceTag())
	elseif event == "TRANSMOG_COLLECTION_UPDATED" then
		Log("%s %s", event, safeFmt({ ... }))
	elseif event == "ENCOUNTER_END" then
		local encounterID, encounterName, difficultyID, groupSize, success = ...
		Log("%s encounter=%s %s diff=%s size=%s success=%s %s", event, tostring(encounterID), tostring(encounterName),
			tostring(difficultyID), tostring(groupSize), tostring(success), InstanceTag())
	elseif event == "ENCOUNTER_LOOT_RECEIVED" then
		local encounterID, itemID, itemLink = ...
		Log("%s encounter=%s item=%s %s", event, tostring(encounterID), tostring(itemID), tostring(itemLink))
	elseif event == "PLAYER_ENTERING_WORLD" then
		Log("%s %s", event, InstanceTag())
	end
end

for _, event in ipairs(EVENTS) do
	if event ~= "EJ_LOOT_DATA_RECIEVED" and event ~= "TRANSMOG_COLLECTION_ITEM_UPDATE" then
		ns.RegisterEvent(event, OnLogEvent)
	end
end

ns.RegisterCommand("probe", function(rest)
	Probe:Run(rest)
end)
