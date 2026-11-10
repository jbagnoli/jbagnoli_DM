import { SPECIALS } from "./catalog.js";
import { RuleError } from "./rules.js";

const ROOMS = {
  bedroom: "bedroom",
  "dining room": "dining",
  parlor: "parlor",
  courtyard: "courtyard",
  kitchen: "kitchen",
  storage: "storage",
};

export function parseReview(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch (error) {
    if (error instanceof RuleError) throw error;
    throw new RuleError("bad_review", "That text is not JSON.");
  }
  const items = [];
  const specials = Object.fromEntries(SPECIALS.map((spec) => [spec.name.toLowerCase(), spec.id]));
  specials.barracks = "barrack";
  for (const [key, value] of Object.entries(data || {})) {
    const rows = Array.isArray(value) ? value : [value];
    for (const row of rows) {
      if (!row || typeof row !== "object" || !("value" in row || "status" in row)) continue;
      const status = String(row.status || "");
      const blocked = /turn|finance|date|goods|loan|defender|steward/i.test(key) || (/pending/i.test(status) && !/special|basic|household/i.test(key));
      const title = labelOf(row.value) || key;
      let command = null;
      if (!blocked && /basic/i.test(key)) {
        const roomName = String(row.value?.type || "").toLowerCase();
        command = { kind: "facility", facilityKind: "basic", roomId: ROOMS[roomName], space: String(row.value?.space || "cramped").toLowerCase() };
        if (!command.roomId) continue;
      } else if (!blocked && /special/i.test(key)) {
        const name = String(row.value?.name || "").toLowerCase();
        command = { kind: "facility", catalogId: specials[name] };
        if (!command.catalogId) continue;
      } else if (!blocked && /household|roster/i.test(key)) {
        command = {
          kind: "roster",
          person: {
            name: row.value?.name || row.value?.role || "Unnamed",
            category: "household",
            role: row.value?.role || "",
            summary: row.value?.summary || "",
            unitId: "unit-party",
          },
        };
      }
      items.push({ title, section: row.section || key, status, blocked: blocked || !command, command, accepted: false, present: false });
    }
  }
  return items;
}

function labelOf(value) {
  if (!value) return "";
  if (typeof value === "string") return value;
  return value.name || value.type || value.role || "";
}

export function reviewKey(item) {
  const command = item?.command;
  if (!command) return "";
  if (command.kind === "facility" && command.facilityKind === "basic") {
    return `basic:${command.roomId}:${command.space}`;
  }
  if (command.kind === "facility" && command.catalogId) {
    return `special:${command.catalogId}`;
  }
  if (command.kind === "roster") {
    const person = command.person || {};
    return `roster:${String(person.name || "").trim().toLowerCase()}:${String(person.role || "").trim().toLowerCase()}`;
  }
  return "";
}

function tally(map, key) {
  if (!key) return;
  map.set(key, (map.get(key) || 0) + 1);
}

export function markAgainstRecord(items, state) {
  const have = new Map();
  for (const facility of state?.facilities || []) {
    if (facility.status === "archived") continue;
    if (facility.kind === "basic") tally(have, `basic:${facility.catalogId}:${facility.space}`);
    if (facility.kind === "special") tally(have, `special:${facility.catalogId}`);
  }
  for (const person of state?.roster || []) {
    if (person.status && person.status !== "active") continue;
    if (person.category && person.category !== "household") continue;
    tally(have, `roster:${String(person.name || "").trim().toLowerCase()}:${String(person.role || "").trim().toLowerCase()}`);
  }
  const used = new Map();
  for (const item of items) {
    item.accepted = false;
    item.present = false;
    const key = reviewKey(item);
    if (!key || item.blocked) continue;
    const seen = used.get(key) || 0;
    if (seen < (have.get(key) || 0)) {
      item.present = true;
      used.set(key, seen + 1);
    }
  }
  return items;
}

export function canAccept(item) {
  return Boolean(item && item.command && !item.blocked && !item.accepted && !item.present && !item.pending);
}
