#!/usr/bin/env python3
"""Build Data/Dungeons.lua from Wowhead exports and the client's encounter table.

Inputs (all in tools/data/):
  wowhead/*.json             exports made with tools/wowhead_export.js on a dungeon zone page
  gamedata/DungeonEncounter.csv  boss encounters per instance map (from the game client)
  gamedata/Map.csv           instance maps (from the game client)
  npc_aliases.json           NPC name -> encounter name, for adds whose loot belongs to a boss

An item is kept if it
  - has a transmog appearance,
  - is Uncommon (2) or better,
  - drops from an NPC that matches a boss encounter of the dungeon (directly or via alias).
Binding (bind-on-pickup) is not in the Wowhead data; check it in game with /fj probe data.

Usage: python3 tools/build_data.py            # writes Data/Dungeons.lua, prints a summary
       python3 tools/build_data.py --check    # exits 1 if Data/Dungeons.lua is out of date
"""

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "tools" / "data"
OUTPUT = ROOT / "Data" / "Dungeons.lua"
MIN_QUALITY = 2  # Uncommon


def load_encounters():
    by_map = defaultdict(list)
    with open(DATA / "gamedata" / "DungeonEncounter.csv", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            by_map[int(row["MapID"])].append({
                "id": int(row["ID"]),
                "name": row["Name_lang"],
                "order": int(row["OrderIndex"]),
                "difficulty": int(row["DifficultyID"]),
            })
    return by_map


def load_maps():
    with open(DATA / "gamedata" / "Map.csv", encoding="utf-8") as f:
        return {int(r["ID"]): r for r in csv.DictReader(f)}


def load_aliases():
    path = DATA / "npc_aliases.json"
    if not path.exists():
        return {}
    return {k: v for k, v in json.loads(path.read_text(encoding="utf-8")).items() if not k.startswith("_")}


def table(export, kind, table_id=None):
    for t in export.get("tables", []):
        if t.get("kind") == kind and (table_id is None or t.get("id") == table_id):
            return t.get("rows", [])
    return []


def slug(name):
    name = re.sub(r"^the\s+", "", name.strip(), flags=re.I)
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def dungeon_name(export):
    return re.sub(r"\s+-\s+Zone\s+-\s+WoW Forever\s*$", "", export.get("title", "")).strip()


def wowhead_zone(export):
    m = re.search(r"/zone=(\d+)", export.get("url", ""))
    return int(m.group(1)) if m else None


def find_map(export, encounters_by_map, aliases):
    """The instance map whose boss encounters best match the NPCs on the Wowhead page."""
    npc_names = {r.get("name") for r in table(export, "npc")}
    npc_names |= {aliases.get(n) for n in npc_names if n in aliases}
    best, best_score = None, 0
    for map_id, encounters in encounters_by_map.items():
        score = sum(1 for e in encounters if e["name"] in npc_names)
        if score > best_score:
            best, best_score = map_id, score
    return best, best_score


def build_dungeon(path, encounters_by_map, maps, aliases, log):
    export = json.loads(path.read_text(encoding="utf-8"))
    name = dungeon_name(export) or path.stem
    map_id, score = find_map(export, encounters_by_map, aliases)
    if not map_id:
        raise SystemExit(f"{path.name}: no instance map matches the NPCs on this page")
    encounters = sorted(encounters_by_map[map_id], key=lambda e: e["order"])
    log.append(f"{path.name}: {name} -> map {map_id} ({maps.get(map_id, {}).get('MapName_lang', '?')}), "
               f"{score}/{len(encounters)} encounters matched")

    by_name = {e["name"]: e for e in encounters}
    bosses = {e["id"]: {"encounter": e, "items": []} for e in encounters}
    excluded = []
    for item in table(export, "item", "drops"):
        label = f"{item['id']} {item.get('name')}"
        if not item.get("appearances"):
            excluded.append(f"{label}: no appearance")
            continue
        if (item.get("quality") or 0) < MIN_QUALITY:
            excluded.append(f"{label}: quality {item.get('quality')}")
            continue
        boss = None
        for src in item.get("sourcemore") or []:
            npc = src.get("n")
            enc = by_name.get(npc) or by_name.get(aliases.get(npc))
            if enc:
                boss = enc
                break
        if not boss:
            sources = ", ".join(s.get("n", "?") for s in item.get("sourcemore") or []) or "unknown source"
            excluded.append(f"{label}: not a boss drop ({sources})")
            continue
        bosses[boss["id"]]["items"].append(item["id"])

    for line in excluded:
        log.append("   excluded " + line)
    for e in encounters:
        if not bosses[e["id"]]["items"]:
            log.append(f"   warning: boss {e['name']} ({e['id']}) has no items")

    return {
        "key": slug(name),
        "name": name,
        "mapID": map_id,
        "wowheadZone": wowhead_zone(export),
        "bosses": [
            {"name": e["name"], "encounterID": e["id"], "items": sorted(bosses[e["id"]]["items"])}
            for e in encounters
        ],
    }


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(dungeons):
    out = [
        "-- Generated by tools/build_data.py. Do not edit by hand; edit tools/data/ and re-run.",
        "local _, ns = ...",
        "",
        "ns.Dungeons = {",
    ]
    for d in dungeons:
        out.append("\t{")
        out.append(f"\t\tkey = {lua_string(d['key'])},")
        out.append(f"\t\tname = {lua_string(d['name'])},")
        out.append(f"\t\tmapID = {d['mapID']},")
        if d["wowheadZone"]:
            out.append(f"\t\twowheadZone = {d['wowheadZone']},")
        out.append("\t\tbosses = {")
        for b in d["bosses"]:
            items = ", ".join(str(i) for i in b["items"])
            out.append(f"\t\t\t{{ name = {lua_string(b['name'])}, encounterID = {b['encounterID']}, items = {{ {items} }} }},")
        out.append("\t\t},")
        out.append("\t},")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if Data/Dungeons.lua is out of date")
    args = parser.parse_args()

    encounters_by_map = load_encounters()
    maps = load_maps()
    aliases = load_aliases()
    log = []
    dungeons = [build_dungeon(p, encounters_by_map, maps, aliases, log)
                for p in sorted((DATA / "wowhead").glob("*.json"))]
    dungeons.sort(key=lambda d: d["name"].lower())

    keys = [d["key"] for d in dungeons]
    if len(keys) != len(set(keys)):
        raise SystemExit("duplicate dungeon keys: " + ", ".join(keys))

    text = render(dungeons)
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != text:
            print("Data/Dungeons.lua is out of date: run python3 tools/build_data.py", file=sys.stderr)
            return 1
        print("Data/Dungeons.lua is up to date")
        return 0

    OUTPUT.write_text(text, encoding="utf-8")
    print("\n".join(log))
    total = sum(len(b["items"]) for d in dungeons for b in d["bosses"])
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {len(dungeons)} dungeons, {total} items")
    return 0


if __name__ == "__main__":
    sys.exit(main())
