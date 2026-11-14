#!/usr/bin/env python3
"""Generate tools/data/dungeons.json: every live WoW Forever dungeon with its map ID,
level and Wowhead zone URL, from the client's game data in tools/data/gamedata/.

Run this only when Blizzard adds or changes dungeons (after updating the game data
tables from wago.tools). The weekly refresh does not need it.
"""

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "tools" / "data"
GAMEDATA = DATA / "gamedata"
OUTPUT = DATA / "dungeons.json"
WOWHEAD_ZONE_URL = "https://www.wowhead.com/forever/zone={}"


def norm(name):
    name = re.sub(r"^the\s+", "", name.strip().lower())
    return re.sub(r"[^a-z0-9]+", "", name)


def slug(name):
    name = re.sub(r"^the\s+", "", name.strip(), flags=re.I)
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def read(name):
    with open(GAMEDATA / name, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main():
    maps = {r["ID"]: r for r in read("Map.csv")}
    tuning = {r["ID"]: int(r["MinLevelSquish"]) for r in read("ContentTuning.csv")}
    aliases = {k: str(v) for k, v in json.loads((DATA / "lfg_map_aliases.json").read_text(encoding="utf-8")).items()
               if not k.startswith("_")}
    map_by_name = {norm(m["MapName_lang"]): map_id for map_id, m in maps.items()}
    areas = read("AreaTable.csv")

    dungeons = {}
    for row in read("LFGDungeons.csv"):
        name = row["Name_lang"]
        map_id = aliases.get(name) or map_by_name.get(norm(name))
        if not map_id:
            raise SystemExit(f"dungeon finder entry '{name}' matches no map; add it to lfg_map_aliases.json")
        if maps[map_id]["InstanceType"] != "1":
            continue  # raid
        level = tuning.get(row["ContentTuningID"], 0)
        d = dungeons.setdefault(map_id, {"level": level, "finderNames": []})
        d["level"] = min(d["level"], level) if d["level"] else level
        d["finderNames"].append(name)

    out = []
    for map_id, d in dungeons.items():
        map_name = maps[map_id]["MapName_lang"]
        candidates = [a for a in areas if a["ContinentID"] == map_id]
        area = next((a for a in candidates if norm(a["AreaName_lang"]) == norm(map_name)), None) \
            or next((a for a in candidates if norm(a["AreaName_lang"]) in {norm(n) for n in d["finderNames"]}), None) \
            or (candidates[0] if len(candidates) == 1 else None)
        if not area:
            raise SystemExit(f"no Wowhead zone found for map {map_id} {map_name}")
        name = area["AreaName_lang"]
        out.append({
            "key": slug(name),
            "name": name,
            "mapID": int(map_id),
            "level": d["level"],
            "wowheadZone": int(area["ID"]),
            "url": WOWHEAD_ZONE_URL.format(area["ID"]),
        })
    out.sort(key=lambda d: (d["level"], d["name"].lower()))
    OUTPUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for d in out:
        print(f"{d['level']:>2}  {d['name']:<28} map {d['mapID']:<5} {d['url']}")
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {len(out)} dungeons")


if __name__ == "__main__":
    main()
