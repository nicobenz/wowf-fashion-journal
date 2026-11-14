# WoW Forever Fashion Journal

An add-on for **World of Warcraft: Forever** that shows which dungeon appearances you
have collected and which are still missing. In Forever, every eligible player in the
group gets the appearance of a bind-on-pickup dungeon boss drop. Blizzard's own
Appearances tab only shows what you already have.

> Status: early development. The add-on currently contains only the **API probe**
> (`/fj probe`), which checks what the Forever client offers. The project plan is in
> [`docs/PLAN.md`](docs/PLAN.md).

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
- `/fj probe clear`: clear the event log.

The last report is also saved to
`WTF\Account\<ACCOUNT>\SavedVariables\FashionJournal.lua` on logout or `/reload`. You can
send that file instead of copying the text.

## Development

- Lint: `luacheck .` (config in `.luacheckrc`, also run in GitHub Actions).
- Release packaging: `.pkgmeta` for the BigWigs packager. Not set up for publishing yet.
- The Forever client's own UI source and API documentation are mirrored on the `forever`
  branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever).
  This is the best reference for what the client supports.
