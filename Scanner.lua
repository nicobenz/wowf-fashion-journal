local _, ns = ...

-- Checks a list of items in small batches, spread over frames, so a full scan never
-- stalls the game. Item data is loaded asynchronously before each check.
--
-- Fires: "SCAN_STARTED"(label, total), "SCAN_PROGRESS"(label, done, total),
--        "SCAN_FINISHED"(label, isFullScan)

local Scanner = {}
ns.Scanner = Scanner

local BATCH_SIZE = 8
local BATCH_TIMEOUT = 5 -- seconds; items that never load (bad IDs) don't block the scan

local job

function Scanner.IsRunning()
	return job ~= nil
end

function Scanner.GetProgress()
	if job then
		return job.label, job.done, job.total
	end
end

local function Finish(current)
	if job ~= current then
		return
	end
	job = nil
	if current.isFull then
		ns.db.lastFullScan = time()
	end
	ns.Fire("SCAN_FINISHED", current.label, current.isFull)
end

local function Step(current)
	if job ~= current then
		return
	end
	if current.index >= current.total then
		Finish(current)
		return
	end

	local first, last = current.index + 1, math.min(current.index + BATCH_SIZE, current.total)
	current.index = last
	local pending, batchDone = last - first + 1, false

	local function NextBatch()
		if not batchDone then
			batchDone = true
			C_Timer.After(0, function()
				Step(current)
			end)
		end
	end

	local function OnChecked()
		current.done = current.done + 1
		ns.Fire("SCAN_PROGRESS", current.label, current.done, current.total)
		pending = pending - 1
		if pending == 0 then
			NextBatch()
		end
	end

	for i = first, last do
		local itemID = current.items[i]
		local item = Item:CreateFromItemID(itemID)
		if item:IsItemEmpty() then
			OnChecked()
		else
			item:ContinueOnItemLoad(function()
				if job == current and not batchDone then
					ns.Collection.Check(itemID)
					OnChecked()
				end
			end)
		end
	end

	C_Timer.After(BATCH_TIMEOUT, function()
		if job == current and not batchDone then
			current.done = current.done + pending
			NextBatch()
		end
	end)
end

-- Starts a scan. A running scan is replaced, except that a single-dungeon scan never
-- interrupts a full scan (the full scan covers that dungeon anyway).
function Scanner.Start(items, label, isFull)
	if job and job.isFull and not isFull then
		return false
	end
	job = { items = items, label = label, isFull = isFull, index = 0, done = 0, total = #items }
	ns.Fire("SCAN_STARTED", label, job.total)
	Step(job)
	return true
end

function Scanner.ScanDungeon(dungeon)
	return Scanner.Start(ns.Model.DungeonItems(dungeon), dungeon.name, false)
end

function Scanner.ScanAll()
	return Scanner.Start(ns.Model.AllItems(ns.Dungeons), "all dungeons", true)
end
