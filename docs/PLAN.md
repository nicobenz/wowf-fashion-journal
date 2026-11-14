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

### Probe results, run 1 (outside, level 18 priest, 14 Nov 2026)
- Interface `16001`, `WOW_PROJECT_ID = 18 = WOW_PROJECT_CAMELOT` (mainline is 1).
  The plain `FashionJournal.toc` loads, so no suffix is needed.
- All 39 probed functions and 8 events exist.
- **The Encounter Journal has no data**: `EncounterJournalDisabled` is active and
  `EJ_GetNumTiers()` returns 0. The **game data has no journal tables either**:
  wago.tools has build `wowf 1.60.1.70938`, but `JournalInstance`, `JournalEncounter` and
  `JournalEncounterItem` are absent. **The loot table must come from outside the client.**
- Collection lookups work for every item, including uncollected items and items the class
  can't use. Results for the three Deadmines items:
  - Cape of the Brotherhood (5193): collected, and the three checks agree:
    `GetSourceInfo().isCollected`, `PlayerHasTransmogItemModifiedAppearance(sourceID)` and
    `PlayerHasTransmog(itemID)`.
  - Cruel Barb (5191): a sword on a priest. `isCollected=false`, `isValidSourceForPlayer=false`,
    `useError="This appearance can't be used by your class."`
  - Corsair's Overshirt (5202): not collected.
- Not reliable:
  - `PlayerCanCollectSource`/`AccountCanCollectSource` and `sourceInfo.playerCanCollect`
    return `false` even for the cape, which this character did collect.
  - `GetAppearanceInfoBySource` returned nothing for 5202.
  - `sourceType` is WorldDrop/Vendor, not "journal encounter", for these boss drops.
- `GetAllAppearanceSources(appearanceID)` lists 2–3 sources per appearance. The other
  sources are other items, possibly not obtainable in Forever, but they still count for
  "appearance known".
- `TRANSMOG_COLLECTION_UPDATED` fires at login with no payload, so refreshes on this
  event must be debounced.

### Forever instance map IDs (from game data `Map`, build 1.60.1.70938)
These are the `instanceID` values `GetInstanceInfo()` returns, so they are what we use
to recognise the dungeon you're in. The client data also contains entries that aren't
live (test maps, "<unused>", Season of Discovery leftovers), so this is a candidate
list to compare against the live dungeon list.
- **Classic dungeons:** 33 Shadowfang Keep, 34 Stormwind Stockade, 36 Deadmines,
  43 Wailing Caverns, 47 Razorfen Kraul, 48 Blackfathom Deeps, 70 Uldaman,
  90 Gnomeregan, 109 Sunken Temple, 129 Razorfen Downs, 189 Scarlet Monastery,
  209 Zul'Farrak, 229 Blackrock Spire, 230 Blackrock Depths, 289 Scholomance,
  329 Stratholme, 349 Maraudon, 389 Ragefire Chasm, 429 Dire Maul.
- **Newer dungeon maps:** 2720 The Searing Basin, 2784 Demon Fall Canyon,
  2806 Shadow Hold, 2807 Burning of Andorhal, 2817 Starfall Barrow Den,
  2853 Deadwind Pass, 2875 Karazhan Crypts, 2902 The Scarab Dais, 2921 Naxxramas,
  2959 City of Dalaran, 2970 The Drowned City, 2974 Blackmaw Hold, 2994 Alcaz Prison,
  2998 Excavation Site: Wetlands, 2999 Ruins of Lordaeron, 3001 The Shaper's Terrace,
  3039 Krol'dok Stronghold, 3065 The Hall of Thanes, 3109 Manor Mistmantle.

### Still to check in game
1. The `GetInstanceInfo()` instanceID inside a Forever dungeon matches the map IDs above.
2. Live event flow during a run: does `TRANSMOG_COLLECTION_SOURCE_ADDED` fire for
   **each** shared appearance when a boss item is looted by someone else?
3. Are class-restricted items (a sword for a priest) collected through the shared loot
   rule? The API marks them `isValidSourceForPlayer=false`; on retail such
   appearances can't be learned by that class.

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
Neither the journal API nor the client's game data has loot tables (see the probe
results), so we **ship our own dungeon → boss → item table**. Options:

1. **Wowhead Forever** dungeon loot lists. Wowhead blocks automated access, so this
   needs a manual copy-paste or export from a person, which a script then turns into
   `Data/Dungeons.lua`.
2. **Learn in game**: log `ENCOUNTER_LOOT_RECEIVED` (encounterID, itemID) during runs
   and merge the logs. This is reliable but slow, and works best as a supplement.
3. **Hand-curated**, dungeon by dungeon, as a last resort.

Map IDs for detecting the current dungeon come from the game data (list above).

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
   Don't use `PlayerCanCollectSource`, `playerCanCollect` or `sourceType`: probe run 1
   showed them to be unreliable on Forever.
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
