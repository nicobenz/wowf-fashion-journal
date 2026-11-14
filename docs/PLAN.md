# Fashion Journal: Project Plan

An add-on for **World of Warcraft: Forever** that shows, per dungeon and per boss,
which bind-on-pickup appearances you have already collected and which are still missing.

## 1. What we know about WoW Forever

### From the Forever client's own UI source (primary source)
Blizzard's interface code for each client is mirrored at
[Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source). It has a
**`forever` branch** (build `1.60.1.70938`, 13 Nov 2026) that includes Blizzard's
generated API documentation (`Blizzard_APIDocumentationGenerated`). The table below
was checked against that branch.

| Topic | Finding |
|---|---|
| Client family | Forever is the **modern client**. Its internal codename is **Camelot**. The code sets `WOW_PROJECT_CAMELOT = 18` and `WOW_PROJECT_ID = WOW_PROJECT_CAMELOT`. Most UI is shared with retail ("mainline"), with Camelot-specific override files. |
| Transmog API | **`C_TransmogCollection` exists with every function we need**: `GetItemInfo(itemInfo) → itemAppearanceID, itemModifiedAppearanceID`, `GetSourceInfo`, `GetAppearanceSources`, `GetAllAppearanceSources`, `GetAppearanceInfoBySource`, `PlayerHasTransmog(itemID[, modID])`, `PlayerHasTransmogItemModifiedAppearance`, `PlayerKnowsSource`, `PlayerCanCollectSource`, `AccountCanCollectSource`, `GetSourceItemID`. |
| Events | `TRANSMOG_COLLECTION_SOURCE_ADDED(itemModifiedAppearanceID)`, `TRANSMOG_COLLECTION_SOURCE_REMOVED(itemModifiedAppearanceID)`, `TRANSMOG_COLLECTION_UPDATED`, `TRANSMOG_COLLECTION_ITEM_UPDATE`. The *added* event tells us exactly which source was learned, so we can update one entry without a rescan. |
| Collections UI | The Appearances tab exists, but Forever's override **hides uncollected appearances and the progress bar** (`Blizzard_Collections/Camelot/Blizzard_Wardrobe.lua`: *"In Camelot we dont want to show uncollected appearances"*). In other words, Blizzard's own UI deliberately doesn't show what you're missing. That is the gap this add-on fills. |
| Encounter Journal | The `C_EncounterJournal` namespace exists (`Environment = "All"`), and the journal add-on is in the client. In Forever, it is switched on or off by the server game rule `Enum.GameRule.EncounterJournalDisabled` (`GameRulesUtil.EJIsDisabled()`). Community sources say there's no journal in Forever, so the rule is probably active, and its loot data may or may not be usable. **We need an in-game check.** |
| Interface number | Version 1.60.1 → `## Interface: 16001` (major·10000 + minor·100 + patch). This matches what community guides say. |

### From community sources (rules of the game)
- BoP **Uncommon/Rare** dungeon boss drops give their appearance to **every eligible
  looter**, even if they lose the roll. This is the core mechanic the add-on tracks.
- Collection is **account-wide**. Appearances are collected even when transmog is switched off.
- Raid epics only give their appearance to the player who gets the item (out of scope for v1).
- Level-locks and similar *usage* restrictions are **ignored by design**. This add-on is
  about whether you have collected an appearance, not whether you can use it.

### Still to check in game (Phase 0)
1. Does the `EJ_*` / `C_EncounterJournal` loot data return Forever dungeons and drops
   (`EJ_SelectInstance`, `EJ_GetNumLoot`, `C_EncounterJournal.GetLootInfoByIndex`)
   while the game rule hides the journal?
2. Does `C_TransmogCollection.GetItemInfo` return data for the new Rare dungeon items,
   and are any of them modified variants (bonus IDs)?
3. Does `GetSourceInfo(sourceID).isCollected` / `PlayerHasTransmogItemModifiedAppearance`
   work for items the current character can't wear (e.g. plate on a mage)?
4. Is a flavor-suffixed TOC recognised (`_Forever.toc`, `_Camelot.toc`), or do we ship a plain `.toc`?
5. What `GetInstanceInfo()` returns inside a Forever dungeon (its `instanceID`/map ID is how
   we recognise which dungeon you're in).

## 2. Scope (v1)

- Covers every Forever dungeon, with each dungeon's bosses and their BoP Uncommon/Rare drops.
- Each item has one of three states:
  - **Collected**: this exact item (source) is known.
  - **Appearance known**: the look is already collected through a different item that shares it. Shown as collected, with a subtle marker.
  - **Missing**.
- Progress per dungeon and per boss (e.g. `Deadmines 14/22`).
- Filter to show only missing items. Item tooltip on hover. Ctrl-click opens the dressing room, Shift-click links the item in chat.

### Behaviour
| Situation | Behaviour |
|---|---|
| `/fj` **outside** an instance | Opens the **overview**: all dungeons with their collected/total progress, taken from the last saved scan. Click a dungeon to see its bosses and items. |
| `/fj` **inside** a known dungeon | Opens straight into **that dungeon's view**. That one dungeon is re-checked quickly when it opens (a few dozen items). |
| Appearance collected **during a run** | On `TRANSMOG_COLLECTION_SOURCE_ADDED(sourceID)`, look up the source in a reverse index (sourceID → dungeon/boss/item). Update only that entry, save it, and refresh the view if it's open. **No rescan.** |
| **Full scan** | Started from a "Scan all" button or `/fj scan`. Outside a dungeon it first asks for confirmation (`StaticPopup`: "Scan all N dungeons (M items)? This may take a few seconds."). It works through items in batches across frames so the game doesn't stall, and shows progress. Inside a dungeon, the scan button only re-checks that dungeon. |
| First login / no saved data | The overview says "not scanned yet" and offers the full scan (still with confirmation). |

### Later
- Raids, world drops, quest rewards.
- An item tooltip note ("Fashion Journal: missing, drops from X in Y").
- On entering a dungeon, a chat line: "You are missing N appearances here."

## 3. Architecture

```
FashionJournal/
  FashionJournal.toc        ## Interface: 16001, SavedVariables: FashionJournalDB
  Core.lua                  init, events, slash command, instance detection
  Data/Dungeons.lua         static: dungeons -> bosses -> itemIDs (+ instance map ID)
  Collection.lua            transmog API wrapper: status per item, reverse index
  Scanner.lua               async, batched scanning (one dungeon or all)
  Model.lua                 pure logic: progress counts, filtering, sorting
  UI/MainFrame.lua          window shell, switching between overview and dungeon view
  UI/Overview.lua           dungeon list with progress bars
  UI/DungeonView.lua        bosses, item icon grid
  UI/ItemButton.lua         icon, state overlay, tooltip, click handlers
tests/
  *_spec.lua                busted tests with a stubbed WoW API
tools/
  generate_data.*           builds Data/Dungeons.lua from the chosen data source
```

### Saved data (`FashionJournalDB`, account-wide like the collection itself)
```lua
FashionJournalDB = {
  version = 1,
  lastFullScan = 1731600000,       -- time() of the last full scan
  items = {                        -- itemID -> scan result
    [5193] = { source = 1234, appearance = 567, state = "collected" },
  },
  ui = { point = {...}, missingOnly = false, minimap = {} },
}
```
The client is still the source of truth. The saved results only let the overview
show progress straight away without a full rescan. Results are refreshed whenever a
dungeon is opened, when a single source is added, and when a full scan runs.

### Item data source
The Encounter Journal can't be relied on (the game rule above), so the plan is to
**ship our own dungeon → boss → item table**, ideally generated by script.

1. **The journal API at runtime**, if Phase 0 shows it returns Forever data. No upkeep needed.
2. **Game data tables for build 1.60.x** (`JournalInstance`, `JournalEncounter`,
   `JournalEncounterItem`, `Map`) from a db2 export, turned into `Data/Dungeons.lua`
   by `tools/generate_data`.
3. Wowhead Forever "drops from" pages, checked by hand.

The table stores only IDs. Names and icons come from the client at runtime.
```lua
{ key = "deadmines", mapID = 36, name = "The Deadmines",
  bosses = { { name = "Edwin VanCleef", items = { 5193, 5191, 5202 } } } }
```

### Status check for one item
1. Make sure the item data is loaded (`Item:CreateFromItemID(id):ContinueOnItemLoad`).
2. Get `appearanceID, sourceID` from `C_TransmogCollection.GetItemInfo(itemID)`.
3. If `PlayerHasTransmogItemModifiedAppearance(sourceID)` (or `GetSourceInfo(sourceID).isCollected`), the state is **collected**.
4. Otherwise, if any source in `GetAllAppearanceSources(appearanceID)` is collected, the state is **appearance known**.
5. Otherwise the state is **missing**.
6. Fallback if step 2 returns nothing: `PlayerHasTransmog(itemID)`.
7. Store the result and put `sourceID → item` in the reverse index.

## 4. Phases

**Phase 0: probe in game (needs someone with a Forever client)**
A throwaway `FJProbe` add-on. Running `/fjprobe` prints the client version and
interface number, `GetInstanceInfo()`, whether the journal data works, and the full
status check for a handful of known dungeon item IDs. This answers the
"Still to check in game" list above.

**Phase 1: skeleton and tooling**
TOC, core, slash command, saved variables. Add a luacheck config with WoW globals,
busted plus API stubs, and a GitHub Action for linting, tests and packaging
(BigWigs packager → CurseForge/Wago).

**Phase 2: data**
Build the dungeon table, one dungeon end to end first, then all of them. Add a test
that checks the data: no duplicates, every boss has items, every dungeon has a map ID.

**Phase 3: collection, scanner and model**
Status check, reverse index, batched async scanner, incremental updates from
`SOURCE_ADDED`/`REMOVED`, and the confirmation popup before a full scan. Unit tests
for the model and scanner against a stubbed API.

**Phase 4: UI**
Overview and dungeon view built from Blizzard templates (`ButtonFrameTemplate`,
`ScrollBox`/`DataProvider`, which are available because this is the modern client).
Instance-aware `/fj`, tooltips, dressing-room preview, chat links, missing-only filter.

**Phase 5: polish and release**
Minimap/compartment button, localization scaffold (enUS), README with screenshots, release v0.1.0.

## 5. Risks
- **Loot data upkeep**: Forever is new and loot tables may change with patches. Keep the data generated by script and covered by tests.
- **Item cache misses**: item info may not be loaded yet, so all lookups must be asynchronous. A full scan has to run in batches.
- **Blizzard hides uncollected appearances on purpose** in Forever's own UI. If a later patch also restricts the API for uncollected sources, the "missing" view would break. The Phase 0 probe and a quick re-check after each patch will catch this.
- **Interface number** goes up with each Forever patch. Update `## Interface` each time.

## Sources
- Forever client UI source: https://github.com/Gethe/wow-ui-source/tree/forever
- https://en.wikipedia.org/wiki/World_of_Warcraft:_Forever
- https://www.icy-veins.com/wow-forever/roadmap
- https://www.warcrafttavern.com/forever/news/transmog-in-world-of-warcraft-forever/
- https://www.icy-veins.com/wow-forever/transmog-system
- https://wowforeverguides.com/addons/developers
- https://warcraft.wiki.gg/wiki/TOC_format
