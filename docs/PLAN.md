# Fashion Journal: Project Plan

An add-on for **World of Warcraft: Forever** that shows, per dungeon and per boss,
which bind-on-pickup appearances you have already collected and which are still missing.

## 1. What we know about WoW Forever (as of Nov 2026)

| Topic | Finding | Confidence |
|---|---|---|
| Release | Launched 4 Nov 2026. A separate, permanent level 1–60 branch, included with a WoW subscription. Nine new dungeons and three raids. Raids unlock 9 Dec 2026. | High (several sources) |
| Client / API | Forever runs on the **modern (retail-style) API**, not the Classic Era API. Classic Era add-ons (Interface 11509) do not load. | Medium (community guides) |
| Interface number | `## Interface: 16001` (client version 1.60.x). Check in game with `/dump select(4, GetBuildInfo())`. | Medium (community guides + Warcraft Wiki multi-flavor example) |
| Collections UI | The account-wide **Collections → Appearances** tab exists (Shift+P), even when transmog is switched off. | Medium |
| Shared dungeon appearances | BoP **Uncommon/Rare** dungeon boss drops give their appearance to **every eligible looter**, even if they lose the roll. | High (several sources) |
| Raid epics | Appearance goes only to the player who gets the item. Out of scope for v1. | High |
| Poor/Common items | Appearance is granted when looted (no binding needed). | Medium |
| Level lock | Higher-tier dungeon/raid appearances stay locked until level 60. | Medium (single source) |
| Hardcore | Collection may not be account-wide on Hardcore realms. Sources disagree. | Low |
| Built-in dungeon journal | **No Adventure Guide / Encounter Journal UI** in Forever. Community add-ons fill the gap. | Medium |

### Unverified: needs an in-game check (Phase 0)

1. Whether `C_TransmogCollection` exists in Forever and which functions it has:
   `GetItemInfo`, `GetSourceInfo`, `GetAppearanceSources`/`GetAllAppearanceSources`,
   `PlayerHasTransmog`, `PlayerHasTransmogItemModifiedAppearance`,
   `PlayerKnowsSource`. (The Warcraft Wiki lists `PlayerHasTransmog` as present on
   Classic Era too, which is a good sign.)
2. Whether the Encounter Journal **API** (`EJ_*`, `C_EncounterJournal`) exists and
   has data, even though there is no journal UI. If it does, we can skip shipping our
   own loot tables. Assume it does not.
3. Events: `TRANSMOG_COLLECTION_SOURCE_ADDED`, `TRANSMOG_COLLECTION_SOURCE_REMOVED`,
   `TRANSMOG_COLLECTION_UPDATED`.
4. Whether Forever supports a flavor-specific TOC suffix (e.g. `_Forever.toc`), or
   whether we only use the plain `.toc` with `16001`.
5. Whether uncollectable items (wrong armor type for the class, level-locked) return
   valid source info, and whether `isCollected` reports correctly for them.
6. How the new Rare dungeon items look in the data (bonus IDs or item modifiers that
   change the `itemModifiedAppearanceID`).

## 2. Scope

### v1 (MVP)
- Covers every Forever dungeon: the nine new ones plus any reworked classic dungeons that are live.
- Lists each dungeon's bosses and their BoP Uncommon/Rare drops.
- Shows each item as collected / appearance known from another item / missing.
- Progress per dungeon and per boss (e.g. `Deadmines 14/22`).
- Filters: missing only, by armor type or slot, usable by current class.
- Item tooltip on hover. Ctrl-click previews the item in the dressing room. Shift-click links it in chat.
- Open with `/fj` (`/fashionjournal`) and an optional minimap button.

### Later
- Raids (personal-loot rules differ), world drops, quest rewards.
- A note in the item tooltip: "Fashion Journal: missing, drops from X in Y".
- A notice when entering a dungeon: "You are missing N appearances here".
- An optional tab inside the Collections window instead of a separate frame.

## 3. Architecture

```
FashionJournal/
  FashionJournal.toc        ## Interface: 16001, SavedVariables: FashionJournalDB
  Core.lua                  init, events, slash command, saved variables
  Data/Dungeons.lua         static: dungeons -> bosses -> itemIDs (generated)
  Collection.lua            wraps the transmog API: per-item status, cache
  Model.lua                 pure logic: progress counts, filtering, sorting
  UI/MainFrame.lua          window: dungeon list (left), boss/item grid (right)
  UI/ItemButton.lua         icon, collected overlay, tooltip, click handlers
  Libs/                     LibStub, LibDataBroker, LibDBIcon (minimap only)
tools/
  generate_data.py          builds Data/Dungeons.lua from a data source
tests/
  *_spec.lua                busted tests with a stubbed WoW API
```

### Item data (the main open question)
There is no in-game journal, so we will probably have to **ship our own loot table**.
Ways to get it, in order of preference:

1. **The Encounter Journal API at runtime**, if Phase 0 shows it exists and has data. No upkeep needed.
2. **Game data tables for the Forever build** (for example `JournalInstance`,
   `JournalEncounter`, `JournalEncounterItem`, via wago.tools or a similar db2
   export). The tables may exist even without the UI. A script turns them into
   `Data/Dungeons.lua`.
3. **Wowhead Forever** pages for each dungeon ("drops from"). Pull them by script or
   by hand, then check them by hand.
4. **Hand-curated** list as a last resort, starting with the nine new dungeons.

The data format stores only IDs; names and icons come from the client at runtime:
```lua
{ id = "deadmines", name = "The Deadmines", minLevel = 17,
  bosses = { { name = "Edwin VanCleef", items = { 5193, 5191, 5202 } }, ... } }
```

### Collection status logic
For each itemID:
1. Load the item asynchronously (`Item:CreateFromItemID():ContinueOnItemLoad`, or
   `C_Item.RequestLoadItemDataByID` plus `ITEM_DATA_LOAD_RESULT`).
2. Call `C_TransmogCollection.GetItemInfo(itemID)` to get `appearanceID, sourceID`.
3. Look up this exact source with `C_TransmogCollection.GetSourceInfo(sourceID).isCollected`,
   falling back to `PlayerHasTransmogItemModifiedAppearance(sourceID)`.
4. If this source is not collected, check whether **any** source of `appearanceID` is
   collected (`GetAllAppearanceSources`). If one is, show "appearance known, from another item".
5. Fallback if the API is limited: `PlayerHasTransmog(itemID)`.
6. Cache results in memory. Clear the cache entry for that source on
   `TRANSMOG_COLLECTION_SOURCE_ADDED/REMOVED`, and refresh the open view.

The collection is account-wide and the client already stores it, so the saved
variables only hold UI settings (window position, filters, minimap). No collection
data is copied into them.

## 4. Phases

**Phase 0: API spike (about 1 evening, needs a Forever client)**
A throwaway `FJProbe` add-on that, on `/fjprobe`, prints which namespaces and
functions exist, runs the steps in §3 on a few known dungeon items (collected and
uncollected, cloth and plate, below and above the level lock), and checks
`EJ_GetNumTier`/`EJ_SelectInstance`. Its output answers every point in §1
"Unverified". **Everything after this depends on the result.**

**Phase 1: Skeleton and tooling**
TOC, core, slash command, saved variables. Add luacheck config (WoW globals),
busted plus API stubs, and a GitHub Action for linting, tests and packaging
(BigWigs packager → CurseForge/Wago).

**Phase 2: Data**
Build the dungeon→boss→item table from the best source found in Phase 0, starting
with one dungeon end to end, then all of them. Add a test that checks the data
(no duplicates, every boss has items, IDs are numbers).

**Phase 3: Collection module and model**
Status logic, cache and events. Unit-test the model (counts, filters) with stubbed
API answers.

**Phase 4: UI**
A plain frame using Blizzard templates (`ButtonFrameTemplate` / `PortraitFrameTemplate`),
a scrolling dungeon list (`ScrollBox`/`DataProvider` if present, otherwise
`FauxScrollFrame`), and a boss section with an item icon grid that greys out and
desaturates missing items. Add tooltips, dressing-room preview and chat links.

**Phase 5: Polish and release**
Filters, minimap button, localization scaffold (enUS first), README, screenshots,
release v0.1.0.

## 5. Risks

- **API gaps in Forever**: covered by Phase 0. If source-level lookups are missing,
  fall back to `PlayerHasTransmog(itemID)` and accept less detail.
- **Data accuracy and upkeep**: Forever is new and loot tables may change with
  patches. Keep the data generated by script and covered by tests.
- **Item cache misses**: item info may not be loaded yet, so all lookups must be
  asynchronous. Never assume `GetItemInfo` returns data straight away.
- **Rules ambiguity**: the level-60 lock and Hardcore behaviour may make items
  "uncollectable right now". Show this as its own state, not as "missing".
- **Interface number bumps**: update `## Interface` with each Forever patch.

## Sources
- https://en.wikipedia.org/wiki/World_of_Warcraft:_Forever
- https://www.pcgamer.com/games/world-of-warcraft/forever-release-date-launch-times/
- https://www.icy-veins.com/wow-forever/roadmap
- https://www.warcrafttavern.com/forever/news/transmog-in-world-of-warcraft-forever/
- https://www.icy-veins.com/wow-forever/transmog-system
- https://wowforeverguides.com/transmog
- https://wowforeverguides.com/addons/developers
- https://bindonforever.com/articles/do-classic-era-addons-work-in-wow-forever
- https://warcraft.wiki.gg/wiki/TOC_format
- https://warcraft.wiki.gg/wiki/API_C_TransmogCollection.PlayerHasTransmog
- https://www.warcrafttavern.com/forever/guides/transmog/
- https://wowhead.com/forever/wardrobe
