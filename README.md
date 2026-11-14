# WoW Forever Fashion Journal

An add-on for **World of Warcraft: Forever** that shows which dungeon appearances you
have collected and which are still missing. In Forever, every eligible player in the
group gets the appearance of a bind-on-pickup dungeon boss drop. Blizzard's own
Appearances tab only shows what you already have.

> Status: early development. Only **The Deadmines** is included so far. The project
> plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Usage

- `/fj` opens the journal. **Outside** a dungeon it shows the overview: every dungeon
  with its collected/total progress. **Inside** a dungeon it opens that dungeon
  directly and re-checks its items.
- Click a dungeon to see its bosses and their appearances:
  - full color with a green check: collected
  - blue check: the appearance is collected through another item
  - grey: missing
  - `?`: not checked yet
- **Missing only** and **Usable by this character** filter the view. They never
  change the counts, because collection is account-wide: a priest collects sword
  appearances too.
- **Scan all** (or `/fj scan` outside a dungeon) checks every dungeon against your
  collection after asking for confirmation. Inside a dungeon, **Rescan** and
  `/fj scan` only check that dungeon.
- When you collect an appearance from a dungeon boss, the entry updates right away
  and a chat line announces it. No rescan is needed.
- Hover an icon for its tooltip. Ctrl-click opens it in the dressing room,
  Shift-click links it in chat.

## Install (from git)

The add-on folder must be called **`FashionJournal`**, because WoW requires the folder
name to match the `.toc` file. Clone the repository straight into the Forever client's
AddOns folder under that name.

**Windows (PowerShell or Git Bash):**
```sh
cd "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
git clone https://github.com/nicobenz/wowf-fashion-journal.git FashionJournal
```

**macOS:**
```sh
cd "/Applications/World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/nicobenz/wowf-fashion-journal.git FashionJournal
```

If you can't find the folder, open the Battle.net launcher, select WoW Forever, click
the gear icon, then **Show in Explorer/Finder**. The `Interface\AddOns` folder is inside
the folder that opens; create it if it doesn't exist.

To update, run `git pull` inside the `FashionJournal` folder, then `/reload` in game.

During development, use the branch you are testing:
```sh
git -C FashionJournal checkout <branch-name>
```

## Running the probe

1. Log in to a Forever character. Make sure *Fashion Journal* is enabled in the AddOns
   list on the character select screen. If it shows as "out of date", the interface
   number in the `.toc` doesn't match: run `/dump select(4, GetBuildInfo())` and report
   the number.
2. Type `/fj probe`. A window opens with the report and the text already selected.
   Press **Ctrl+C** to copy it.
3. Run it at least twice:
   - **outside** any instance, and
   - **inside a dungeon**. This also checks the current dungeon's loot, if the
     Encounter Journal data works.
4. Optional: leave the add-on enabled during a dungeon run in which you collect new
   appearances, then run `/fj probe` afterwards. The report ends with a log of
   appearance-collected and boss-kill events, which we need for live updates.

Other commands:
- `/fj probe item 5193 5191`: check specific item IDs only.
- `/fj probe data`: check every item in the add-on's dungeon data.
- `/fj probe clear`: clear the event log.

The last report is also saved to
`WTF\Account\<ACCOUNT>\SavedVariables\FashionJournal.lua` on logout or `/reload`. You can
send that file instead of copying the text.

## Development

### Branches and releases
- **`main`** holds released versions only. **`develop`** is the integration branch.
- New work happens on a **feature branch off `develop`** and goes back into `develop`
  through a pull request, merged as a **squash merge** once the feature works. CI
  (lint, unit tests, data check) must pass. The feature branch is **deleted after the
  merge**; the next feature starts from a fresh branch off the updated `develop`.
- Suggested GitHub settings to enforce this:
  - Settings → General → Pull Requests: allow only **squash merging**, and enable
    **"Automatically delete head branches"**.
  - Settings → Rules → Rulesets for `develop` and `main`: **require a pull request**
    before merging and **require status checks** (the Lint workflow's jobs) to pass;
    block force pushes and deletion.
- **Releasing:** open a pull request from `develop` to `main`. After it is merged,
  create a version **tag** on `main` (`git tag v0.1.0 && git push origin v0.1.0`, or
  "Create release" on GitHub). Releases are triggered by tags only, never by merges
  or pushes, so the version number is always chosen deliberately and an accidental
  merge publishes nothing.
- **Version tags** follow `vMAJOR.MINOR.PATCH`. The tag decides the release type:

  | Tag | Release type | Typical use |
  |---|---|---|
  | `v0.2.0` | release | tagged on `main` |
  | `v0.2.0-beta1` | beta | may be tagged on `develop` for testers |
  | `v0.2.0-alpha1` | alpha | early test builds |

- **Publishing (planned):** a GitHub Actions workflow runs the
  [BigWigs packager](https://github.com/BigWigsMods/packager) on `v*` tags. It builds
  the add-on zip from `.pkgmeta`, substitutes `@project-version@` with the tag, and
  uploads it to CurseForge as a Forever file (Interface 16001 → game version 1.60.1).
  Release builds leave out the development probe (`Probe/`, plus `#@debug@` markers
  in the TOC), `docs/`, `tools/` and `tests/`.
- **Still to set up before the first release:**
  - [ ] CurseForge project created; its ID goes into the TOC as `## X-Curse-Project-ID`
  - [ ] CurseForge API token stored as the GitHub secret `CF_API_KEY`
  - [ ] Optional: Wago project (`## X-Wago-ID`) and secret `WAGO_API_TOKEN`
  - [ ] Release workflow (`.github/workflows/release.yml`) and probe exclusion

### Dungeon data
`Data/Dungeons.lua` is generated, so don't edit it by hand. Wowhead's drop data is
collected by players and fills in over time, so refresh it every week or so.

**One-time setup:** run `python3 tools/wowhead.py bookmarklet` and save the printed
`javascript:` URL as a browser bookmark (e.g. "FJ export").

**Weekly refresh:**
1. `python3 tools/wowhead.py open` opens the 28 dungeon pages on Wowhead, 7 tabs at a
   time. On each tab, click the bookmark: it downloads `fashionjournal-zone-<id>.json`.
2. `python3 tools/wowhead.py import --delete` reads those files from `~/Downloads`
   (or pass another folder), stores them in `tools/data/wowhead/<dungeon>.json`, shows
   per dungeon which drops were added, removed or got a new source, and rebuilds
   `Data/Dungeons.lua`.
3. In game: `/reload`, then `/fj probe data` to check the new items (binding, quality,
   appearance).
4. Commit `tools/data/wowhead/` and `Data/Dungeons.lua`.

`python3 tools/wowhead.py list` shows every dungeon with its Wowhead URL and last
export date, and `open --missing` opens only dungeons that have no export yet.

**Data files** in `tools/data/`:
- `dungeons.json`: the 28 live dungeons with map ID, level and Wowhead URL. It is
  generated from the client's game data by `tools/make_dungeon_list.py`; re-run that
  only when Blizzard adds dungeons.
- `npc_aliases.json`: adds whose loot belongs to a boss with a different name
  (e.g. Sneed's Shredder → Sneed).
- `excluded_items.json`: items to leave out, with the in-game evidence.
- `gamedata/`: tables from the Forever client (via wago.tools), see `SOURCE.txt`.

- Tests: `lua5.1 tests/run.lua` (also run in GitHub Actions).
- Lint: `luacheck .` (config in `.luacheckrc`, also run in GitHub Actions).
- Release packaging: `.pkgmeta` for the BigWigs packager (see *Branches and releases*).
- The Forever client's own UI source and API documentation are mirrored on the `forever`
  branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever).
  This is the best reference for what the client supports.
