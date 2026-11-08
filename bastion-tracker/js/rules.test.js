import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { saleProceeds, specialCap } from "./catalog.js";
import { practiceState } from "./demo.js";
import { configured, isSecretKey, serviceRoleRejected } from "./remote.js";
import { render } from "./render.js";
import { RuleError, apply, emptyEstate } from "./rules.js";

function party() {
  const state = emptyEstate({ name: "Practice Hall", cadenceDays: 7, level: 5 });
  return apply(state, { type: "set_clock", ordinal: 1, label: "Practice day 1" }).state;
}

function withCash(state, gp) {
  return apply(state, { type: "set_finance", cashGp: gp }).state;
}

function add(state, catalogId, unitId = "unit-party") {
  return apply(state, { type: "add_special", unitId, catalogId }).state;
}

test("level 6 cap is 2 and replacements follow levels gained", () => {
  assert.equal(specialCap(6), 2);
  assert.equal(specialCap(5), 2);
  assert.equal(specialCap(9), 4);
  assert.equal(specialCap(13), 5);
  assert.equal(specialCap(17), 6);
  let state = party();
  state = apply(state, { type: "raise_level", unitId: "unit-party", level: 6 }).state;
  assert.equal(state.units[0].replacementBank, 1);
  assert.throws(() => apply(state, { type: "replace_special", unitId: "unit-party", facilityId: "missing", catalogId: "library" }), (error) => error.code === "missing_facility" || error.code === "no_replacement" || error instanceof RuleError);
  state = add(state, "barrack");
  state = add(state, "storehouse");
  assert.throws(() => add(state, "library"), (error) => error.code === "cap");
  const replaced = apply(state, { type: "replace_special", unitId: "unit-party", facilityId: state.facilities.find((item) => item.catalogId === "barrack").id, catalogId: "library" }).state;
  assert.equal(replaced.units[0].replacementBank, 0);
  assert.equal(replaced.archive.length, 1);
  assert.throws(() => apply(replaced, {
    type: "replace_special",
    unitId: "unit-party",
    facilityId: replaced.facilities[0].id,
    catalogId: "garden",
  }), (error) => error.code === "no_replacement");
});

test("starting at level 6 does not grant retroactive swaps", () => {
  const state = emptyEstate({ level: 6 });
  assert.equal(state.units[0].replacementBank, 0);
  assert.equal(specialCap(6), 2);
});

test("duplicates and prerequisites", () => {
  let state = party();
  state = add(state, "storehouse");
  assert.throws(() => add(state, "storehouse"), (error) => error.code === "duplicate");
  state = party();
  state = add(state, "barrack");
  const second = add(state, "barrack");
  assert.equal(second.facilities.filter((item) => item.catalogId === "barrack").length, 2);
  assert.throws(() => add(party(), "arcane_study"), (error) => error.code === "prerequisite");
  const capable = apply(party(), { type: "set_capabilities", unitId: "unit-party", capabilities: ["arcane_or_tool"] }).state;
  assert.equal(add(capable, "arcane_study").facilities[0].catalogId, "arcane_study");
});

test("Maintain blocks the same unit only", () => {
  let state = party();
  state = add(state, "barrack");
  state = apply(state, { type: "split_unit", name: "Second hall", level: 5, acknowledgeNewCap: true }).state;
  const other = state.units[1].id;
  state = apply(state, { type: "add_special", unitId: other, catalogId: "library" }).state;
  const barrack = state.facilities.find((item) => item.catalogId === "barrack");
  assert.throws(() => apply(state, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "maintain",
    orders: [{ facilityId: barrack.id, suborder: "recruit", count: 1 }],
  }), (error) => error.code === "maintain_exclusive");
  state = apply(state, { type: "commit_turn", unitId: "unit-party", presence: "absent", mode: "orders" }).state;
  assert.equal(state.turns.at(-1).mode, "maintain");
  const library = state.facilities.find((item) => item.catalogId === "library");
  state = apply(state, {
    type: "commit_turn",
    unitId: other,
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: library.id, suborder: "research" }],
  }).state;
  assert.equal(state.turns.filter((item) => item.unitId === other).length, 1);
});

test("recruit adds four and stops at the housing cap", () => {
  let state = withCash(party(), 0);
  state = add(state, "barrack");
  const barrack = () => state.facilities.find((item) => item.catalogId === "barrack");
  state = apply(state, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: barrack().id, suborder: "recruit", count: 4 }],
  }).state;
  assert.equal(state.roster.filter((item) => item.status === "active").length, 4);
  state = apply(state, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: barrack().id, suborder: "recruit", count: 4 }],
  }).state;
  assert.equal(state.roster.filter((item) => item.category === "defender" && item.status === "active").length, 8);
  state = apply(state, { type: "commit_turn", unitId: "unit-party", presence: "present", mode: "orders", orders: [{ facilityId: barrack().id, suborder: "recruit", count: 4 }] }).state;
  assert.equal(state.roster.filter((item) => item.status === "active").length, 12);
  assert.throws(() => apply(state, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: barrack().id, suborder: "recruit", count: 1 }],
  }), (error) => error.code === "barrack_full");
});

test("500 GP of goods sell for 550 once after 7 days on a 10-day cadence", () => {
  let state = party();
  state = apply(state, { type: "set_settings", cadenceDays: 10 }).state;
  state = withCash(state, 0);
  state = add(state, "storehouse");
  state = apply(state, { type: "record_goods", name: "Wool", standardGp: 500 }).state;
  const store = state.facilities[0];
  const lot = state.goods[0];
  state = apply(state, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: store.id, suborder: "sell", lotId: lot.id, standardGp: 500 }],
  }).state;
  assert.equal(state.finance.cashGp, 0);
  assert.equal(state.tasks[0].dueOrdinal, 8);
  assert.equal(state.tasks[0].proceeds, 550);
  assert.equal(saleProceeds(500, 5), 550);
  state = apply(state, { type: "advance_days", days: 7, idempotencyKey: "week" }).state;
  assert.equal(state.clock.ordinal, 8);
  assert.equal(state.finance.cashGp, 550);
  const again = apply(state, { type: "advance_days", days: 7, idempotencyKey: "week" });
  assert.equal(again.replay, true);
  assert.equal(again.state.finance.cashGp, 550);
  assert.equal(again.state.clock.ordinal, 8);
});

test("construction cost, time, and free inherited rooms", () => {
  let state = withCash(party(), 500);
  const built = apply(state, { type: "add_basic", unitId: "unit-party", roomId: "parlor", space: "cramped" });
  assert.equal(built.state.finance.cashGp, 0);
  assert.equal(built.state.projects[0].days, 20);
  assert.equal(built.result.dueOrdinal, 21);
  state = built.state;
  state = apply(state, { type: "advance_days", days: 20 }).state;
  assert.equal(state.facilities.some((item) => item.name === "Parlor" && item.acquired === "built"), true);
  const free = apply(party(), { type: "add_basic", unitId: "unit-party", roomId: "bedroom", space: "cramped", inherited: true }).state;
  assert.equal(free.finance.cashKnown, false);
  assert.equal(free.facilities[0].acquired, "inherited");
  assert.throws(() => apply(party(), { type: "add_basic", unitId: "unit-party", roomId: "kitchen", space: "roomy" }), (error) => error.code === "finance_unknown");
});

test("attack, walls, armory, and next-turn shutdown", () => {
  let state = withCash(party(), 500);
  state = add(state, "barrack");
  state = add(state, "armory");
  const barrack = state.facilities.find((item) => item.catalogId === "barrack");
  state = apply(state, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: barrack.id, suborder: "recruit", count: 1 }],
  }).state;
  const armory = state.facilities.find((item) => item.catalogId === "armory");
  state = apply(state, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: armory.id, suborder: "stock" }],
  }).state;
  assert.equal(state.facilities.find((item) => item.catalogId === "armory").stocked, true);
  state = apply(state, { type: "mark_enclosure", complete: true, reason: "The DM walked the perimeter." }).state;
  state = apply(state, { type: "commit_turn", unitId: "unit-party", presence: "present", mode: "maintain" }).state;
  const eventId = state.events.at(-1).id;
  const resolved = apply(state, {
    type: "resolve_event",
    eventId,
    roll: 51,
    detail: { rolls: [1, 1, 1, 1] },
  }).state;
  assert.equal(resolved.facilities.find((item) => item.catalogId === "armory").stocked, false);
  assert.equal(resolved.roster.filter((item) => item.status === "active" && item.category === "defender").length, 0);
  const shut = resolved.facilities.find((item) => item.status === "shutdown");
  assert.ok(shut);
  assert.equal(shut.shutdownUntilTurnId, "next");
  const stillShut = apply(resolved, { type: "advance_days", days: 7 }).state;
  assert.equal(stillShut.facilities.find((item) => item.id === shut.id).status, "shutdown");
  assert.throws(() => apply(stillShut, {
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: barrack.id, suborder: "recruit", count: 1 }],
  }), (error) => error.code === "shutdown" || error.code === "barrack_full");
});

test("event roll is not repeated by resolving twice", () => {
  let state = add(party(), "barrack");
  state = apply(state, { type: "commit_turn", unitId: "unit-party", presence: "present", mode: "maintain" }).state;
  const eventId = state.events[0].id;
  state = apply(state, { type: "resolve_event", eventId, roll: 10, idempotencyKey: "evt-1", detail: { note: "Quiet" } }).state;
  const replay = apply(state, { type: "resolve_event", eventId, roll: 99, idempotencyKey: "evt-1" });
  assert.equal(replay.replay, true);
  assert.equal(replay.state.events[0].type, "all_is_well");
  assert.equal(replay.state.events[0].roll, 10);
});

test("unknown opening cash is preserved", () => {
  const state = party();
  assert.equal(state.finance.cashKnown, false);
  assert.equal(state.finance.cashGp, null);
  assert.throws(() => apply(state, { type: "add_wall_squares", squares: 1 }), (error) => error.code === "finance_unknown");
  assert.equal(state.finance.cashKnown, false);
});

test("readers cannot write and editors cannot raise level", () => {
  const state = party();
  assert.throws(() => apply(state, { type: "set_clock", actorRole: "reader", ordinal: 3 }), (error) => error.code === "forbidden");
  assert.throws(() => apply(state, { type: "raise_level", actorRole: "editor", unitId: "unit-party", level: 6 }), (error) => error.code === "forbidden");
});

test("stale revision is rejected", () => {
  const state = party();
  assert.throws(() => apply(state, { type: "set_settings", cadenceDays: 10, expectedRevision: 1 }), (error) => error.code === "revision_conflict");
});

test("review import does not finish historic turns or invent balances", () => {
  const state = party();
  assert.throws(() => apply(state, { type: "import_accept", item: { kind: "turn", status: "recorded; DM reconciliation pending", outcome: "" } }), (error) => error.code === "import_blocked");
  assert.throws(() => apply(state, { type: "import_accept", item: { kind: "finance" } }), (error) => error.code === "import_blocked");
  assert.throws(() => apply(state, { type: "import_accept", item: { kind: "date" } }), (error) => error.code === "import_blocked");
  const imported = apply(state, { type: "import_accept", item: { kind: "facility", facilityKind: "basic", roomId: "storage", space: "roomy" } }).state;
  assert.equal(imported.facilities[0].acquired, "inherited");
  assert.equal(imported.finance.cashKnown, false);
});

test("publishable keys are accepted and secret keys are refused", () => {
  const url = "https://example.supabase.co";
  const publishable = { supabaseUrl: url, supabaseAnonKey: "sb_publishable_example" };
  const secret = { supabaseUrl: url, supabaseAnonKey: "sb_secret_example" };
  const header = btoa(JSON.stringify({ alg: "none", typ: "JWT" }));
  const body = btoa(JSON.stringify({ role: "service" + "_role" }));
  const legacySecret = { supabaseUrl: url, supabaseAnonKey: `${header}.${body}.sig` };
  assert.equal(isSecretKey(publishable.supabaseAnonKey), false);
  assert.equal(configured(publishable), true);
  assert.equal(serviceRoleRejected(publishable), false);
  assert.equal(configured(secret), false);
  assert.equal(serviceRoleRejected(secret), true);
  assert.equal(configured(legacySecret), false);
  assert.equal(configured({ supabaseUrl: url, supabaseAnonKey: "" }), false);
});

test("practice sandbox renders and is labeled as not the group record", () => {
  const state = practiceState();
  assert.equal(state.practice, true);
  assert.equal(state.finance.cashGp, 800);
  const html = render({ mode: "sandbox", view: "dashboard", state, error: "", notice: "", configured: false, serviceRole: false });
  assert.match(html, /Practice sandbox/);
  assert.match(html, /Hearthwatch Hold/);
  assert.match(html, /Not the group record/);
  assert.match(html, /not synced/);
  const gate = render({ mode: "gate", configured: false, serviceRole: false, error: "", notice: "" });
  assert.match(gate, /Not connected/);
  assert.match(gate, /Setup is required/);
  assert.match(gate, /Sign-in stays off/);
  const ready = render({ mode: "gate", configured: true, serviceRole: false, error: "", notice: "" });
  assert.match(ready, /<label>Email/);
  assert.match(ready, /not a Microsoft/);
});

test("public tracker files do not carry private campaign material", async () => {
  const root = path.resolve(import.meta.dirname, "..");
  const banned = ["grim" + "wald", "duns" + "tan", "merrow" + "by", "tars" + "akh", "service" + "_role", "DMG_" + "Bastions", "an" + "vil", "notion" + ".so", "3c556933" + "c6ab"].map((word) => new RegExp(word, "i"));
  async function walk(dir) {
    const entries = await readdir(dir, { withFileTypes: true });
    const files = [];
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) files.push(...await walk(full));
      else files.push(full);
    }
    return files;
  }
  const files = await walk(root);
  for (const file of files) {
    if (file.endsWith(".pdf")) throw new Error(file);
    const text = await readFile(file, "utf8");
    for (const pattern of banned) {
      assert.equal(pattern.test(text), false, `${file} matches ${pattern}`);
    }
  }
});
