// Wowhead export for Fashion Journal.
//
// Use it as a bookmarklet (recommended): run `python3 tools/wowhead.py bookmarklet` and save
// the printed javascript: URL as a bookmark. On a Wowhead Forever dungeon zone page, click the
// bookmark: the page's loot and NPC tables are downloaded as fashionjournal-zone-<id>.json.
// Then run `python3 tools/wowhead.py import` to bring the downloads into the project.
//
// It also works when pasted into the browser console (F12), where it additionally copies
// the JSON to the clipboard.
//
// It only reads data the page has already loaded; it makes no requests.
(() => {
  // Wowhead listview entity types.
  const ENTITY = { 1: "npc", 2: "object", 3: "item", 5: "quest" };
  const FULL_ROWS = new Set(["npc", "item"]); // export these rows in full
  const SKIP_KEYS = new Set(["tooltip", "tooltip_enus", "completed", "noteworthy"]);

  // Copies plain data only: no functions, DOM nodes or cycles, limited depth.
  const clean = (value, depth = 0, seen = new WeakSet()) => {
    if (value === null || typeof value !== "object") {
      return typeof value === "function" ? undefined : value;
    }
    if (depth > 4 || seen.has(value) || value instanceof Node) return undefined;
    seen.add(value);
    if (Array.isArray(value)) {
      return value.map((v) => clean(v, depth + 1, seen)).filter((v) => v !== undefined);
    }
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (SKIP_KEYS.has(k) || k.startsWith("__")) continue;
      const c = clean(v, depth + 1, seen);
      if (c !== undefined) out[k] = c;
    }
    return out;
  };

  const zone = (location.href.match(/\/zone=(\d+)/) || [])[1];
  if (!zone) {
    alert("Fashion Journal: this is not a Wowhead zone page.");
    return;
  }

  const views = window.g_listviews || {};
  const tables = [];
  for (const [key, lv] of Object.entries(views)) {
    const template = lv.template || {};
    const entityType = typeof template === "object" ? template.entityType : undefined;
    const kind = ENTITY[entityType] || (typeof template === "string" ? template : "other");
    if (kind === "other") continue; // comments, screenshots, news, guides...
    const rows = Array.isArray(lv.data) ? lv.data : [];
    tables.push({
      id: key,
      name: lv.name || "",
      kind,
      rows: rows.map((r) => (FULL_ROWS.has(kind) ? clean(r) : { id: r.id, name: r.name })),
    });
  }

  const result = {
    exportedAt: new Date().toISOString(),
    url: location.href,
    title: document.title,
    tables,
  };
  const json = JSON.stringify(result);
  const summary = tables.map((t) => `${t.id} (${t.kind}): ${t.rows.length}`).join(", ") || "none found";

  // Download as a file.
  const link = document.createElement("a");
  link.href = URL.createObjectURL(new Blob([json], { type: "application/json" }));
  link.download = `fashionjournal-zone-${zone}.json`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);

  // In the console, also copy to the clipboard.
  if (typeof copy === "function") {
    copy(json);
  }
  console.log(`Fashion Journal export: zone ${zone}, ${json.length} characters. Tables: ${summary}`);
})();
