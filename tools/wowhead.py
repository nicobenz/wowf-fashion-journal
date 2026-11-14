#!/usr/bin/env python3
"""Weekly refresh of the dungeon loot data from Wowhead.

Wowhead's drop data is collected by players and grows over time, so re-export every dungeon
now and then. Wowhead pages are opened and exported by you in your browser; this tool never
downloads anything from Wowhead itself.

  python3 tools/wowhead.py bookmarklet        print the export bookmarklet (save it once as a bookmark)
  python3 tools/wowhead.py open [--batch N]   open all dungeon pages in your browser, N tabs at a time
  python3 tools/wowhead.py open --missing     only dungeons without an export yet
  python3 tools/wowhead.py list               show every dungeon, its URL and when it was last exported
  python3 tools/wowhead.py import [DIR]       import fashionjournal-zone-*.json from DIR (default ~/Downloads),
                                              show what changed and rebuild Data/Dungeons.lua

Typical run: open -> click the bookmark on each page -> import.
"""

import argparse
import json
import re
import subprocess
import sys
import urllib.parse
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "tools" / "data"
EXPORTS = DATA / "wowhead"
DUNGEONS = DATA / "dungeons.json"
SNIPPET = ROOT / "tools" / "wowhead_export.js"

# Fields kept per row. Everything else Wowhead sends is dropped, so the stored files stay
# small and their git diffs show only changes that matter.
ITEM_FIELDS = ["id", "name", "quality", "classs", "subclass", "slot", "appearances", "sourcemore"]
SOURCE_FIELDS = ["n", "t", "ti", "z", "bd"]
NPC_FIELDS = ["id", "name", "classification", "boss", "tag"]


def load_dungeons():
    return json.loads(DUNGEONS.read_text(encoding="utf-8"))


def export_path(dungeon):
    return EXPORTS / f"{dungeon['key']}.json"


# bookmarklet ---------------------------------------------------------------------

def bookmarklet_source():
    """The snippet without comments, on one line (browsers may drop line breaks in bookmarks)."""
    lines = []
    for line in SNIPPET.read_text(encoding="utf-8").splitlines():
        line = re.sub(r"\s+// .*$", "", line).strip()
        if line and not line.startswith("//"):
            lines.append(line)
    return " ".join(lines)


def cmd_bookmarklet(_args):
    print("Create a new bookmark (e.g. named 'FJ export') and paste this as its URL/location:\n")
    print("javascript:" + urllib.parse.quote(bookmarklet_source(), safe=""))


# open / list ---------------------------------------------------------------------

def last_export(dungeon):
    path = export_path(dungeon)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8")).get("exportedAt", "?")[:10]


def cmd_list(_args):
    for d in load_dungeons():
        print(f"{d['level']:>2}  {d['name']:<28} {last_export(d) or 'never':<10}  {d['url']}")


def cmd_open(args):
    dungeons = load_dungeons()
    if args.missing:
        dungeons = [d for d in dungeons if not export_path(d).exists()]
    if not dungeons:
        print("nothing to open")
        return
    for start in range(0, len(dungeons), args.batch):
        batch = dungeons[start:start + args.batch]
        for d in batch:
            webbrowser.open_new_tab(d["url"])
        print(f"opened {start + 1}-{start + len(batch)} of {len(dungeons)}: " + ", ".join(d["name"] for d in batch))
        if start + args.batch < len(dungeons):
            input("Click the bookmark on each tab, then press Enter for the next batch...")
    print("Done. When all pages are exported, run: python3 tools/wowhead.py import")


# import --------------------------------------------------------------------------

def reduce_export(raw):
    """Keep only the drops and NPC tables and the fields the converter uses."""
    tables = []
    for t in raw.get("tables", []):
        if t.get("kind") == "item" and t.get("id") == "drops":
            rows = []
            for r in t.get("rows", []):
                row = {k: r[k] for k in ITEM_FIELDS if k in r}
                if "sourcemore" in row:
                    row["sourcemore"] = [{k: s[k] for k in SOURCE_FIELDS if k in s} for s in row["sourcemore"]]
                rows.append(row)
        elif t.get("kind") == "npc" and t.get("id") == "npcs":
            rows = [{k: r[k] for k in NPC_FIELDS if k in r} for r in t.get("rows", [])]
        else:
            continue
        rows.sort(key=lambda r: r["id"])
        tables.append({"id": t["id"], "name": t.get("name", ""), "kind": t["kind"], "rows": rows})
    return {"exportedAt": raw.get("exportedAt"), "url": raw.get("url"), "title": raw.get("title"), "tables": tables}


def dump(export):
    """JSON with one table row per line, so git diffs are readable."""
    lines = ["{" + ", ".join(f"{json.dumps(k)}: {json.dumps(export[k], ensure_ascii=False)}"
                             for k in ("exportedAt", "url", "title")) + ', "tables": [']
    for ti, t in enumerate(export["tables"]):
        lines.append("{" + ", ".join(f"{json.dumps(k)}: {json.dumps(t[k], ensure_ascii=False)}"
                                     for k in ("id", "name", "kind")) + ', "rows": [')
        for ri, r in enumerate(t["rows"]):
            lines.append(json.dumps(r, ensure_ascii=False) + ("," if ri < len(t["rows"]) - 1 else ""))
        lines.append("]}" + ("," if ti < len(export["tables"]) - 1 else ""))
    lines.append("]}")
    return "\n".join(lines) + "\n"


def drops(export):
    """item ID -> (name, sorted source NPC names) for the drops table."""
    result = {}
    for t in export.get("tables", []):
        if t.get("kind") == "item" and t.get("id") == "drops":
            for r in t["rows"]:
                sources = sorted({s.get("n", "?") for s in r.get("sourcemore") or []})
                result[r["id"]] = (r.get("name", "?"), sources)
    return result


def describe_changes(old, new):
    if old is None:
        return [f"   new export: {len(drops(new))} drops"]
    before, after = drops(old), drops(new)
    out = []
    for item_id in sorted(after.keys() - before.keys()):
        name, sources = after[item_id]
        out.append(f"   + {item_id} {name} ({', '.join(sources) or 'no source'})")
    for item_id in sorted(before.keys() - after.keys()):
        out.append(f"   - {item_id} {before[item_id][0]}")
    for item_id in sorted(before.keys() & after.keys()):
        if before[item_id][1] != after[item_id][1]:
            out.append(f"   ~ {item_id} {after[item_id][0]}: {', '.join(before[item_id][1]) or 'no source'}"
                       f" -> {', '.join(after[item_id][1]) or 'no source'}")
    return out or ["   no changes"]


def cmd_import(args):
    source_dir = Path(args.dir).expanduser()
    files = sorted(source_dir.glob("fashionjournal-zone-*.json"))
    if not files:
        print(f"no fashionjournal-zone-*.json files in {source_dir}")
        return 1
    by_zone = {d["wowheadZone"]: d for d in load_dungeons()}
    EXPORTS.mkdir(parents=True, exist_ok=True)
    imported, problems = [], []
    for f in files:
        raw = json.loads(f.read_text(encoding="utf-8"))
        zone = int(f.stem.rsplit("-", 1)[1])
        dungeon = by_zone.get(zone)
        if not dungeon:
            problems.append(f"{f.name}: zone {zone} is not in tools/data/dungeons.json")
            continue
        export = reduce_export(raw)
        if not drops(export):
            problems.append(f"{f.name}: no drops table (was the page fully loaded?)")
            continue
        target = export_path(dungeon)
        old = json.loads(target.read_text(encoding="utf-8")) if target.exists() else None
        target.write_text(dump(export), encoding="utf-8")
        imported.append(f)
        print(f"{dungeon['name']} ({target.relative_to(ROOT)})")
        print("\n".join(describe_changes(old, export)))
    for p in problems:
        print("problem: " + p)
    if imported and args.delete:
        for f in imported:
            f.unlink()
        print(f"deleted {len(imported)} imported files from {source_dir}")
    print("\nrebuilding Data/Dungeons.lua ...")
    result = subprocess.run([sys.executable, str(ROOT / "tools" / "build_data.py")], check=False)
    return 1 if problems or result.returncode else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("bookmarklet", help="print the export bookmarklet")
    sub.add_parser("list", help="list dungeons, URLs and last export date")
    p_open = sub.add_parser("open", help="open the dungeon pages in your browser")
    p_open.add_argument("--batch", type=int, default=7, help="tabs per batch (default 7)")
    p_open.add_argument("--missing", action="store_true", help="only dungeons without an export")
    p_import = sub.add_parser("import", help="import downloaded exports and rebuild the data")
    p_import.add_argument("dir", nargs="?", default="~/Downloads", help="folder with the downloads")
    p_import.add_argument("--delete", action="store_true", help="delete imported files from the folder")
    args = parser.parse_args()
    handler = {"bookmarklet": cmd_bookmarklet, "list": cmd_list, "open": cmd_open, "import": cmd_import}[args.command]
    return handler(args) or 0


if __name__ == "__main__":
    sys.exit(main())
