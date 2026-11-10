import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { saleProceeds, specialCap } from "./catalog.js";
import { practiceState } from "./demo.js";
import { configured, isSecretKey, serviceRoleRejected } from "./remote.js";
import { canAccept, markAgainstRecord, parseReview } from "./review.js";
import { beginSave, failSave, markSavingButtons, succeedSave } from "./save-feedback.js";
import { render } from "./render.js";
import { RuleError, apply, emptyEstate, orderStartedDay } from "./rules.js";

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
  assert.throws(() => apply(state, { type: "import_accept", item: { kind: "loan" } }), (error) => error.code === "import_blocked");
  assert.throws(() => apply(state, { type: "import_accept", item: { kind: "goods" } }), (error) => error.code === "import_blocked");
  assert.throws(() => apply(state, { type: "import_accept", item: { kind: "defender" } }), (error) => error.code === "import_blocked");
  const imported = apply(state, { type: "import_accept", item: { kind: "facility", facilityKind: "basic", roomId: "storage", space: "roomy" } }).state;
  assert.equal(imported.facilities[0].acquired, "inherited");
  assert.equal(imported.finance.cashKnown, false);
  const withSpecial = apply(imported, { type: "import_accept", item: { kind: "facility", catalogId: "library" } }).state;
  assert.equal(withSpecial.facilities.at(-1).acquired, "inherited");
  assert.equal(withSpecial.facilities.at(-1).name, "Library");
  const withRoster = apply(withSpecial, {
    type: "import_accept",
    item: { kind: "roster", person: { name: "Bram Holt", category: "household", role: "Steward", unitId: "unit-party" } },
  }).state;
  assert.equal(withRoster.roster.at(-1).name, "Bram Holt");
  assert.equal(withRoster.revision, state.revision + 3);
});

test("a fresh estate uses a 10-day turn", () => {
  const state = emptyEstate({ name: "Unnamed bastion" });
  assert.equal(state.clock.cadenceDays, 10);
  assert.equal(state.clock.ordinal, null);
  const html = render({ mode: "sandbox", view: "dashboard", state, error: "", notice: "", configured: false, serviceRole: false });
  assert.match(html, /In-game day unknown · turn every 10 in-game days/);
});

test("setting a level directly does not grant replacements", () => {
  let state = party();
  state = add(state, "barrack");
  state = add(state, "storehouse");
  state = apply(state, { type: "raise_level", unitId: "unit-party", level: 6 }).state;
  assert.equal(state.units[0].replacementBank, 1);
  const direct = apply(state, { type: "set_level", unitId: "unit-party", level: 9 }).state;
  assert.equal(direct.units[0].level, 9);
  assert.equal(direct.units[0].replacementBank, 1);
  const granted = apply(state, { type: "set_level", unitId: "unit-party", level: 9, grantReplacements: true }).state;
  assert.equal(granted.units[0].replacementBank, 4);
  assert.throws(() => apply(direct, { type: "set_level", unitId: "unit-party", level: 4 }), (error) => error.code === "cap");
  let high = apply(direct, { type: "set_level", unitId: "unit-party", level: 13 }).state;
  high = add(high, "archive");
  assert.throws(() => apply(high, { type: "set_level", unitId: "unit-party", level: 9 }), (error) => error.code === "level_gate");
});

test("settings save is one change and keeps the previous record when refused", () => {
  const state = add(party(), "library");
  const saved = apply(state, {
    type: "save_settings",
    name: "Practice Hall",
    owner: "The company",
    unitId: "unit-party",
    cadenceDays: 10,
    label: "A spring day",
    ordinal: 4,
    level: 8,
    grantReplacements: false,
    capabilities: ["arcane_or_tool"],
  }).state;
  assert.equal(saved.revision, state.revision + 1);
  assert.equal(saved.name, "Practice Hall");
  assert.equal(saved.units[0].owner, "The company");
  assert.equal(saved.units[0].level, 8);
  assert.equal(saved.units[0].replacementBank, 0);
  assert.equal(saved.clock.cadenceDays, 10);
  assert.equal(saved.clock.ordinal, 4);
  assert.deepEqual(saved.units[0].capabilities, ["arcane_or_tool"]);
  assert.throws(() => apply(saved, {
    type: "save_settings",
    name: "Renamed Hall",
    unitId: "unit-party",
    level: 1,
    cadenceDays: 12,
  }), (error) => error.code === "cap");
  assert.equal(saved.name, "Practice Hall");
  assert.equal(saved.units[0].level, 8);
  assert.equal(saved.clock.cadenceDays, 10);
});

test("DM can record defenders, loans, committed goods, and an order already running", () => {
  let state = add(party(), "barrack");
  state = add(state, "storehouse");
  const barrack = state.facilities.find((item) => item.catalogId === "barrack");
  const store = state.facilities.find((item) => item.catalogId === "storehouse");
  const turns = state.turns.length;
  state = apply(state, { type: "record_defenders", facilityId: barrack.id, count: 2, names: ["Pell Ash", "Sarn Wick"] }).state;
  assert.equal(state.turns.length, turns);
  assert.deepEqual(
    state.roster.filter((person) => person.status === "active").map((person) => person.name),
    ["Pell Ash", "Sarn Wick"],
  );
  assert.throws(() => apply(state, { type: "record_defenders", actorRole: "editor", facilityId: barrack.id, count: 1 }), (error) => error.code === "forbidden");
  const cash = state.finance.cashGp;
  state = apply(state, { type: "set_loan", creditor: "Mill at Northbridge", amountGp: 250, note: "Seed money" }).state;
  assert.equal(state.finance.loans[0].amountGp, 250);
  assert.equal(state.finance.cashGp, cash);
  state = apply(state, { type: "set_loan", loanId: state.finance.loans[0].id, creditor: "Mill at Northbridge", amountGp: 200, note: "Seed money" }).state;
  assert.equal(state.finance.loans[0].amountGp, 200);
  state = apply(state, { type: "reserve_goods", name: "Wool", standardGp: 500, note: "Trade sell already underway" }).state;
  assert.equal(state.goods[0].reservedGp, 500);
  assert.equal(state.finance.cashGp, cash);
  assert.equal(state.tasks.length, 0);
  state = apply(state, { type: "record_order", facilityId: store.id, suborder: "sell", startedDay: 1, note: "Already listed" }).state;
  assert.equal(state.orders[0].status, "in_progress");
  assert.equal(state.orders[0].startedDay, 1);
  assert.equal(state.orders[0].startedTurn, undefined);
  const fromOld = apply(state, { type: "record_order", facilityId: store.id, suborder: "sell", startedTurn: 1, note: "Old backup" }).state;
  assert.equal(orderStartedDay(fromOld.orders.at(-1)), 1);
  assert.equal(fromOld.orders.at(-1).startedTurn, undefined);
  assert.throws(() => apply(state, { type: "record_order", facilityId: store.id, suborder: "sell", startedDay: 9 }), (error) => error.code === "bad_day");
  const listed = render({ mode: "sandbox", view: "record", state, error: "", notice: "", configured: false, serviceRole: false });
  assert.match(listed, /In-game day it started/);
  assert.match(listed, /value="1"/);
  assert.match(listed, /started day 1/);
  assert.doesNotMatch(listed, /Turn it started/);
  assert.equal(state.tasks.length, 0);
  assert.equal(state.finance.cashKnown, false);
});

test("blank or zero goods are refused and the DM can remove a free lot", () => {
  const state = party();
  const cash = state.finance.cashGp;
  assert.throws(() => apply(state, { type: "record_goods", name: "   ", standardGp: 10 }), (error) => error.code === "name_required");
  assert.throws(() => apply(state, { type: "record_goods", name: "Wool", standardGp: 0 }), (error) => error.code === "bad_amount");
  assert.throws(() => apply(state, { type: "reserve_goods", name: "", standardGp: 500 }), (error) => error.code === "name_required");
  assert.equal(state.goods.length, 0);
  assert.equal(state.finance.cashGp, cash);
  let saved = apply(state, { type: "record_goods", name: " Wool bolts ", standardGp: 200 }).state;
  assert.equal(saved.goods[0].name, "Wool bolts");
  assert.equal(saved.finance.cashGp, cash);
  const removed = apply(saved, { type: "remove_goods", lotId: saved.goods[0].id }).state;
  assert.equal(removed.goods.length, 0);
  assert.equal(removed.finance.cashGp, cash);
  assert.equal(removed.finance.cashKnown, false);
  assert.equal(removed.audit.at(-1).type, "remove_goods");
  saved = apply(saved, { type: "reserve_goods", lotId: saved.goods[0].id, standardGp: 50 }).state;
  assert.throws(() => apply(saved, { type: "remove_goods", lotId: saved.goods[0].id }), (error) => error.code === "goods_committed");
  assert.equal(saved.goods.length, 1);
  assert.throws(() => apply(saved, { type: "remove_goods", actorRole: "editor", lotId: saved.goods[0].id }), (error) => error.code === "forbidden");
});

test("settings and the DM record screen are reachable", () => {
  const state = emptyEstate({ name: "Unnamed bastion" });
  const settings = render({ mode: "sandbox", view: "settings", state, error: "", notice: "", configured: true, serviceRole: false });
  assert.match(settings, /<select id="level"/);
  assert.doesNotMatch(settings, /<input id="level"/);
  for (let level = 1; level <= 20; level += 1) assert.match(settings, new RegExp(`value="${level}"`));
  assert.match(settings, /none of them change/);
  assert.match(settings, /for="date-label">Date </);
  assert.match(settings, /placeholder="Leave blank if the date is unknown"/);
  assert.doesNotMatch(settings, /Calendar label/);
  const record = render({ mode: "sandbox", view: "record", state, error: "", notice: "", configured: true, serviceRole: false });
  assert.match(record, /Defenders already housed/);
  assert.match(record, /Outstanding loan/);
  assert.match(record, /Goods already committed/);
  assert.match(record, /Order already underway/);
  assert.match(record, /runs a Recruit turn/);
});

function reviewModel(state, items, text) {
  return { mode: "sandbox", view: "import", state, review: items, reviewText: text, error: "", notice: "", configured: false, serviceRole: false };
}

test("a review list stays on screen after one item is accepted", () => {
  const text = JSON.stringify({
    specials: [
      { value: { name: "Barrack" }, status: "recorded", section: "Special" },
      { value: { name: "Library" }, status: "recorded", section: "Special" },
    ],
  });
  let state = emptyEstate({ name: "Practice Hall", level: 5 });
  const items = markAgainstRecord(parseReview(text), state);
  state = apply(state, { type: "import_accept", item: items[0].command }).state;
  items[0].accepted = true;
  const html = render(reviewModel(state, items, text));
  assert.match(html, /Barrack/);
  assert.match(html, /Library/);
  assert.match(html, /&quot;specials&quot;/);
  assert.match(html, /disabled>Added</);
  assert.match(html, /data-action="accept-review" data-index="1"/);
  assert.equal(canAccept(items[0]), false);
  assert.equal(canAccept(items[1]), true);
  const again = render(reviewModel(state, items, text));
  assert.match(again, /disabled>Added</);
  assert.match(again, /Accept this item/);
});

test("reading a review again marks a Barrack that is already kept", () => {
  const text = JSON.stringify({
    specials: [{ value: { name: "Barrack" }, status: "recorded", section: "Special" }],
  });
  let state = emptyEstate({ name: "Practice Hall", level: 5 });
  state = apply(state, { type: "import_accept", item: { kind: "facility", catalogId: "barrack" } }).state;
  const items = markAgainstRecord(parseReview(text), state);
  assert.equal(items[0].present, true);
  assert.equal(canAccept(items[0]), false);
  const html = render(reviewModel(state, items, text));
  assert.match(html, /Already in the record/);
  assert.doesNotMatch(html, /Accept this item/);
});

test("one existing bedroom covers one of four identical review rooms", () => {
  const text = JSON.stringify({
    basics: Array.from({ length: 4 }, () => ({ value: { type: "Bedroom", space: "cramped" }, status: "recorded", section: "Basic" })),
  });
  let state = emptyEstate({ name: "Practice Hall", level: 5 });
  state = apply(state, { type: "add_basic", unitId: "unit-party", roomId: "bedroom", space: "cramped", inherited: true }).state;
  const items = markAgainstRecord(parseReview(text), state);
  assert.equal(items.length, 4);
  assert.equal(items.filter((item) => item.present).length, 1);
  assert.equal(items.filter((item) => canAccept(item)).length, 3);
});

test("the DM can remove a mistaken roster name and not someone the rules still count", () => {
  let state = emptyEstate({ name: "Practice Hall" });
  state = apply(state, {
    type: "roster_save",
    person: { name: "Ada Moss", category: "household", role: "Steward", unitId: "unit-party" },
  }).state;
  const duplicate = apply(state, {
    type: "roster_save",
    person: { name: "Ada Moss", category: "household", role: "Steward", unitId: "unit-party" },
  }).state;
  assert.equal(duplicate.roster.length, 2);
  const cash = duplicate.finance.cashGp;
  const removed = apply(duplicate, { type: "remove_person", personId: duplicate.roster[1].id }).state;
  assert.equal(removed.roster.length, 1);
  assert.equal(removed.roster[0].id, duplicate.roster[0].id);
  assert.equal(removed.finance.cashGp, cash);
  assert.equal(removed.audit.at(-1).type, "remove_person");
  assert.throws(() => apply(duplicate, { type: "remove_person", actorRole: "editor", personId: duplicate.roster[0].id }), (error) => error.code === "forbidden");
  const keeper = apply(removed, {
    type: "roster_save",
    person: { name: "Yard hand", category: "hireling", role: "Yard", facilityId: "fac-1", unitId: "unit-party" },
  }).state;
  keeper.facilities.push({ id: "fac-1", kind: "special", catalogId: "garden", status: "active", unitId: "unit-party" });
  const hired = keeper.roster.find((person) => person.name === "Yard hand");
  assert.throws(() => apply(keeper, { type: "remove_person", personId: hired.id }), (error) => error.code === "person_held");
  const guard = apply(removed, {
    type: "roster_save",
    person: { name: "Pell Ash", category: "defender", role: "Defender", facilityId: "fac-2", unitId: "unit-party" },
  }).state;
  const defender = guard.roster.find((person) => person.category === "defender");
  assert.throws(() => apply(guard, { type: "remove_person", personId: defender.id }), (error) => error.code === "person_held");
  const guest = apply(removed, {
    type: "roster_save",
    person: { name: "One-night guest", category: "guest", role: "Guest", protectsOnce: true, unitId: "unit-party" },
  }).state;
  const protector = guest.roster.find((person) => person.protectsOnce);
  assert.throws(() => apply(guest, { type: "remove_person", personId: protector.id }), (error) => error.code === "person_held");
});

test("an editor can name an unnamed hireling without changing the id or assignment", () => {
  let state = emptyEstate({ name: "Practice Hall" });
  state.facilities.push({ id: "fac-9", unitId: "unit-party", kind: "special", catalogId: "smithy", name: "Smithy", status: "active" });
  state = apply(state, {
    type: "roster_save",
    person: { name: "  ", category: "hireling", role: "Smith", facilityId: "fac-9", unitId: "unit-party" },
  }).state;
  const placeholder = state.roster.at(-1);
  assert.equal(placeholder.name, "");
  const html = render({ mode: "sandbox", view: "people", state, error: "", notice: "", configured: false, serviceRole: false });
  assert.match(html, /Unnamed \(Smith\)/);
  assert.match(html, />Unnamed</);
  const edited = apply(state, {
    type: "edit_person",
    actorRole: "editor",
    personId: placeholder.id,
    name: "Ada Moss",
    role: "Smith",
    category: "hireling",
    summary: "Works the forge",
    link: "",
  }).state;
  assert.equal(edited.roster.at(-1).id, placeholder.id);
  assert.equal(edited.roster.at(-1).name, "Ada Moss");
  assert.equal(edited.roster.at(-1).facilityId, "fac-9");
  assert.match(edited.audit.at(-1).summary, /"" → "Ada Moss"/);
  assert.throws(() => apply(edited, {
    type: "edit_person",
    actorRole: "editor",
    personId: placeholder.id,
    name: "Ada Moss",
    category: "household",
  }), (error) => error.code === "category_locked");
  assert.throws(() => apply(state, { type: "edit_person", actorRole: "reader", personId: placeholder.id, name: "Ada Moss" }), (error) => error.code === "forbidden");
});

test("save feedback names a practice save differently from a shared save", () => {
  assert.equal(beginSave("settings").status, "pending");
  assert.equal(beginSave("settings").message, "Saving…");
  const shared = succeedSave({ practice: false, summary: "Recorded 8 defenders at Barrack." });
  assert.match(shared.message, /^Saved: Recorded 8 defenders at Barrack\./);
  const practice = succeedSave({ practice: true, summary: "Recorded 8 defenders at Barrack." });
  assert.match(practice.message, /^Saved on this device \(practice\): Recorded 8 defenders at Barrack\./);
  assert.doesNotMatch(practice.message, /^Saved:/);
  const failed = failSave("Level 1 allows 0 special facilities, and this unit already has 2.");
  assert.equal(failed.status, "failure");
  const pending = render({
    mode: "sandbox",
    view: "settings",
    state: emptyEstate({ name: "Practice Hall" }),
    save: beginSave("settings"),
    error: "",
    notice: "",
    configured: false,
    serviceRole: false,
  });
  assert.match(pending, /id="save-feedback"/);
  assert.match(pending, /Saving…/);
  assert.match(pending, /<button class="primary" type="submit" disabled>Saving…<\/button>/);
  const success = render({
    mode: "sandbox",
    view: "settings",
    state: emptyEstate({ name: "Practice Hall" }),
    save: practice,
    error: "",
    notice: "",
    configured: false,
    serviceRole: false,
  });
  assert.match(success, /role="status"/);
  assert.match(success, /aria-live="polite"/);
  assert.match(success, /Saved on this device \(practice\)/);
  const failure = render({
    mode: "remote",
    view: "settings",
    state: emptyEstate({ name: "Practice Hall" }),
    save: failed,
    error: failed.message,
    notice: "",
    configured: true,
    serviceRole: false,
  });
  assert.match(failure, /role="alert"/);
  assert.match(failure, /Level 1 allows 0 special facilities/);
  assert.doesNotMatch(failure, /disabled>Saving…/);
  const buttons = markSavingButtons(`<form id="goods"><button class="primary" type="submit">Record goods without charging</button></form>`, "goods");
  assert.match(buttons, /disabled>Saving…/);
});

test("the server handles every command the client can send", async () => {
  const root = path.resolve(import.meta.dirname, "..");
  const rules = await readFile(path.join(root, "js/rules.js"), "utf8");
  const migration = await readFile(path.join(root, "supabase/migrations/005_remove_person.sql"), "utf8");
  const cases = [...rules.matchAll(/case "([a-z_]+)":/g)].map((match) => match[1]);
  assert.equal(new Set(cases).size, cases.length);
  const block = migration.match(/function public\.handled_command_types\(\)[\s\S]*?array\[([\s\S]*?)\]::text\[\]/);
  assert.ok(block, "handled_command_types is missing");
  const server = [...block[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  assert.deepEqual([...server].sort(), [...cases].sort());
  const dmBlock = migration.match(/dm_only text\[\] := array\[([\s\S]*?)\];/);
  const dmClient = rules.match(/const DM_ONLY = new Set\(\[([\s\S]*?)\]\);/)[1];
  const dmServer = [...dmBlock[1].matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  const dmRules = [...dmClient.matchAll(/"([a-z_]+)"/g)].map((match) => match[1]);
  assert.deepEqual([...dmServer].sort(), [...dmRules].sort());
  const sent = [];
  for (const name of ["main.js", "demo.js", "render.js", "remote.js"]) {
    const source = await readFile(path.join(root, "js", name), "utf8");
    sent.push(...[...source.matchAll(/type:\s*"([a-z_]+)"/g)].map((match) => match[1]));
  }
  for (const type of sent) assert.ok(server.includes(type), type);
  const updates = migration.match(/update\s+public\.estates/gi) || [];
  assert.deepEqual(updates, ["update public.estates", "update public.estates"]);
  assert.match(migration, /update public\.estates set document = doc, revision = rev where id = eid/);
  assert.match(migration, /update public\.estates\s+set document = public\._bastion_move_started_turn\(document\)\s+where document::text like '%startedTurn%'/);
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
