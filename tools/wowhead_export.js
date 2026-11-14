// Wowhead export snippet for Fashion Journal.
//
// Usage: open a Wowhead Forever dungeon page (e.g. https://www.wowhead.com/forever/zone=...),
// open the browser's developer console (F12 -> Console), paste this whole file and press Enter.
// The page's item and NPC tables are copied to the clipboard as JSON.
// Paste the result into tools/data/wowhead/<dungeon>.json (or send it to the project chat).
//
// It only reads data the page has already loaded; it makes no requests.
(() => {
  const pick = (obj, keys) => {
    const out = {};
    for (const k of keys) if (obj[k] !== undefined) out[k] = obj[k];
    return out;
  };
  const ITEM_KEYS = ["id", "name", "quality", "level", "reqlevel", "slot", "classs", "subclass",
    "source", "sourcemore", "count", "outof", "percent", "modes"];
  const NPC_KEYS = ["id", "name", "classification", "boss", "minlevel", "maxlevel", "location",
    "react", "type"];

  const views = window.g_listviews || {};
  const tables = [];
  for (const [key, lv] of Object.entries(views)) {
    const rows = Array.isArray(lv.data) ? lv.data : [];
    const template = lv.template || (lv.config && lv.config.template) || "";
    const keys = template === "item" ? ITEM_KEYS : template === "npc" ? NPC_KEYS : null;
    tables.push({
      id: key,
      name: lv.name || (lv.config && lv.config.name) || "",
      template,
      rows: rows.map((r) => (keys ? pick(r, keys) : pick(r, ["id", "name"]))),
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
  const summary = tables.map((t) => `${t.id} (${t.template}): ${t.rows.length}`).join(", ");
  console.log(`Fashion Journal export: ${json.length} characters copied to clipboard. Tables: ${summary || "none found"}`);
  return summary;
})();
