-- Minimal test runner for the add-on's pure logic. Run: lua5.1 tests/run.lua (from the repo root)
local ns = {}
assert(loadfile("Model.lua"))("FashionJournal", ns)
local Model = ns.Model

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", msg or "value", tostring(expected), tostring(actual)), 2)
	end
end

local statuses = { [1] = "collected", [2] = "known", [3] = "missing", [4] = "none", [5] = nil }
local function getStatus(id) return statuses[id] end
local dungeons = {
	{ key = "a", mapID = 36, bosses = { { items = { 1, 2 } }, { items = { 3, 4, 5 } } } },
	{ key = "b", mapID = 33, bosses = { { items = { 6 } } } },
}

test("IsCollected", function()
	eq(Model.IsCollected("collected"), true)
	eq(Model.IsCollected("known"), true)
	eq(Model.IsCollected("missing"), false)
	eq(Model.IsCollected(nil), false)
end)

test("CountItems skips items without appearance", function()
	local c, t, k = Model.CountItems({ 1, 2, 3, 4, 5 }, getStatus)
	eq(c, 2, "collected"); eq(t, 4, "total"); eq(k, 3, "checked")
end)

test("DungeonProgress sums bosses", function()
	local c, t, k = Model.DungeonProgress(dungeons[1], getStatus)
	eq(c, 2, "collected"); eq(t, 4, "total"); eq(k, 3, "checked")
end)

test("FormatProgress", function()
	eq(Model.FormatProgress(0, 5, 0), "?/5")
	eq(Model.FormatProgress(2, 5, 3), "2/5")
	eq(Model.FormatProgress(0, 0, 0), "0/0")
end)

test("VisibleItems without filters hides only 'none'", function()
	local v = Model.VisibleItems({ 1, 2, 3, 4, 5 }, getStatus, function() return true end, {})
	eq(table.concat(v, ","), "1,2,3,5")
end)

test("VisibleItems missingOnly", function()
	local v = Model.VisibleItems({ 1, 2, 3, 4, 5 }, getStatus, function() return true end, { missingOnly = true })
	eq(table.concat(v, ","), "3,5")
end)

test("VisibleItems usableOnly hides false, keeps unknown", function()
	local usable = { [1] = false, [2] = true }
	local v = Model.VisibleItems({ 1, 2, 3 }, getStatus, function(id) return usable[id] end, { usableOnly = true })
	eq(table.concat(v, ","), "2,3")
end)

test("AllItems / DungeonItems", function()
	eq(table.concat(Model.AllItems(dungeons), ","), "1,2,3,4,5,6")
	eq(table.concat(Model.DungeonItems(dungeons[2]), ","), "6")
end)

test("FindByMapID", function()
	eq(Model.FindByMapID(dungeons, 33), dungeons[2])
	eq(Model.FindByMapID(dungeons, 999), nil)
end)

test("BuildItemIndex", function()
	local index = Model.BuildItemIndex(dungeons)
	eq(index[6].dungeon, dungeons[2])
	eq(index[4].boss, dungeons[1].bosses[2])
end)

test("generated data has the expected shape", function()
	local dataNs = {}
	assert(loadfile("Data/Dungeons.lua"))("FashionJournal", dataNs)
	local seen = {}
	for _, d in ipairs(dataNs.Dungeons) do
		assert(type(d.key) == "string" and type(d.mapID) == "number", "dungeon key/mapID")
		assert(#d.bosses > 0, d.key .. " has no bosses")
		for _, b in ipairs(d.bosses) do
			assert(type(b.encounterID) == "number", "encounterID")
			for _, id in ipairs(b.items) do
				assert(not seen[id], "duplicate item " .. id)
				seen[id] = true
			end
		end
	end
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
