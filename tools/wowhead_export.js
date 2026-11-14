// Wowhead export snippet for Fashion Journal.
//
// Usage: open a Wowhead Forever dungeon zone page (e.g. https://www.wowhead.com/forever/zone=1581/the-deadmines),
// open the browser's developer console (F12 -> Console), paste this whole file and press Enter.
// The page's item and NPC tables are copied to the clipboard as JSON.
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
  if (typeof copy === "function") {
    copy(json);
  }
  const summary = tables.map((t) => `${t.id} (${t.kind}): ${t.rows.length}`).join(", ");
  console.log(`Fashion Journal export: ${json.length} characters copied to clipboard. Tables: ${summary || "none found"}`);
  return summary;
})();
