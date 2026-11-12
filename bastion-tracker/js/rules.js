import { dateForTurn, normalizeAnchor } from "./calendar.js";
import {
  BASIC_BUILD,
  BASIC_UPGRADE,
  EVENTS,
  SPACE_SQUARES,
  SPECIALS,
  WALL_SQUARE,
  buyLimitGp,
  eventFromRoll,
  saleProceeds,
  specialById,
  specialCap,
} from "./catalog.js";

export class RuleError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
    this.name = "RuleError";
  }
}

const MEMBERS = new Set(["dm", "editor", "reader"]);
const DATE_COMMANDS = new Set(["set_calendar_anchor", "reanchor_calendar"]);
const WRITERS = new Set(["dm", "editor"]);
const DM_ONLY = new Set([
  "set_settings",
  "set_clock",
  "set_finance",
  "raise_level",
  "split_unit",
  "replace_special",
  "dm_override",
  "confirm_fall",
  "import_accept",
  "set_capabilities",
  "mark_enclosure",
  "save_settings",
  "set_level",
  "record_defenders",
  "set_loan",
  "reserve_goods",
  "record_order",
  "remove_goods",
  "remove_person",
  "remove_facility",
  "edit_facility",
  "replace_basic",
  "correct_special",
  "replace_person",
  "assign_person",
  "cancel_project",
  "set_order_start",
]);

export function emptyEstate(options = {}) {
  return {
    revision: 1,
    seq: 0,
    practice: Boolean(options.practice),
    name: options.name || "Unnamed bastion",
    clock: {
      label: options.sessionLabel || options.dateLabel || "",
      turn: options.turn ?? null,
      turnNeedsCheck: false,
      anchor: null,
    },
    finance: {
      cashKnown: false,
      cashGp: null,
      loans: [],
    },
    units: [
      {
        id: "unit-party",
        name: options.unitName || "Party",
        level: options.level || 5,
        owner: options.owner || "Shared, or assign later",
        replacementBank: 0,
        capabilities: [],
        neglectStreak: 0,
        fallen: false,
      },
    ],
    facilities: [],
    archive: [],
    projects: [],
    walls: { enclosureComplete: false, squares: [] },
    roster: [],
    goods: [],
    tasks: [],
    turns: [],
    events: [],
    ledger: [],
    orders: [],
    audit: [],
    idempotency: {},
    warnings: [],
  };
}

function clone(state) {
  return structuredClone(state);
}

function nid(state, prefix) {
  state.seq += 1;
  return `${prefix}-${state.seq}`;
}

function roleOf(command) {
  return command.actorRole || "dm";
}

function assertWriter(command) {
  const role = roleOf(command);
  if (DATE_COMMANDS.has(command.type)) {
    if (!MEMBERS.has(role)) throw new RuleError("forbidden", "Sign in as a member of this estate to set the in-game date.");
    return;
  }
  if (!WRITERS.has(role)) {
    throw new RuleError("forbidden", "A reader can look, but cannot change the record.");
  }
  if (DM_ONLY.has(command.type) && role !== "dm") {
    throw new RuleError("forbidden", "Only the DM can change that part of the record.");
  }
}

function unitById(state, id) {
  const unit = state.units.find((item) => item.id === id);
  if (!unit) throw new RuleError("missing_unit", "That ownership unit is not on this estate.");
  return unit;
}

function facilityById(state, id) {
  const facility = state.facilities.find((item) => item.id === id && item.status !== "archived");
  if (!facility) throw new RuleError("missing_facility", "That facility is not active.");
  return facility;
}

function requireTurn(state) {
  if (state.clock.turn == null) {
    throw new RuleError("calendar_unknown", "Set the Bastion turn before starting something that takes turns. The session date can stay blank.");
  }
}

function requireCash(state) {
  if (!state.finance.cashKnown || state.finance.cashGp == null) {
    throw new RuleError("finance_unknown", "Cash is still unknown. Set an opening balance before any GP is spent or received. Unknown is not zero.");
  }
}

function spend(state, gp, reason, command) {
  requireCash(state);
  if (gp < 0) throw new RuleError("bad_amount", "A payment cannot be negative.");
  if (state.finance.cashGp < gp) {
    throw new RuleError("insufficient_cash", `That costs ${gp} GP and the recorded cash is ${state.finance.cashGp} GP.`);
  }
  state.finance.cashGp -= gp;
  state.ledger.push({ id: nid(state, "led"), gp: -gp, reason, turn: state.clock.turn, key: command.idempotencyKey || null });
}

function receive(state, gp, reason, command) {
  requireCash(state);
  state.finance.cashGp += gp;
  state.ledger.push({ id: nid(state, "led"), gp, reason, turn: state.clock.turn, key: command.idempotencyKey || null });
}

function activeSpecials(state, unitId) {
  return state.facilities.filter((item) => item.unitId === unitId && item.kind === "special" && item.status === "active");
}

function defendersOf(state, facilityId) {
  return state.roster.filter((person) => person.category === "defender" && person.status === "active" && person.facilityId === facilityId);
}

function housedLieutenants(state, unitId) {
  return state.roster.filter((person) => person.category === "lieutenant" && person.status === "active" && person.unitId === unitId && person.housed).length;
}

function barrackCap(facility) {
  return facility.space === "vast" ? 25 : 12;
}

function assertEligible(state, unit, spec) {
  if (unit.level < spec.level) {
    throw new RuleError("level_gate", `${spec.name} requires level ${spec.level}. This unit is level ${unit.level}.`);
  }
  if (spec.prereq && !unit.capabilities.includes(spec.prereq)) {
    throw new RuleError("prerequisite", `${spec.name} needs a capability this unit does not have yet. Add it in settings if the character qualifies.`);
  }
  if (spec.unique && activeSpecials(state, unit.id).some((item) => item.catalogId === spec.id)) {
    throw new RuleError("duplicate", `${spec.name} can be kept only once. Barrack, Garden, Stable, and Training Area are the repeats.`);
  }
  if (activeSpecials(state, unit.id).length >= specialCap(unit.level)) {
    throw new RuleError("cap", `Level ${unit.level} allows ${specialCap(unit.level)} special facilities. Replace one, or raise the level, before adding another.`);
  }
}

function pushAudit(state, command, summary) {
  state.audit.push({
    id: nid(state, "aud"),
    revision: state.revision + 1,
    type: command.type,
    summary,
    reason: command.reason || "",
    actorRole: roleOf(command),
    turn: state.clock.turn,
    actorEmail: command.actorEmail || "",
  });
}

function finish(state, command, result, summary) {
  pushAudit(state, command, summary);
  state.revision += 1;
  if (command.idempotencyKey) state.idempotency[command.idempotencyKey] = result;
  return { state, result, replay: false };
}

function addSpecial(state, command) {
  const unit = unitById(state, command.unitId);
  const spec = specialById(command.catalogId);
  if (!spec) throw new RuleError("unknown_facility", "That facility is not in the bastion list.");
  assertEligible(state, unit, spec);
  const facility = {
    id: nid(state, "fac"),
    unitId: unit.id,
    kind: "special",
    catalogId: spec.id,
    name: spec.name,
    space: spec.space,
    hirelings: spec.hirelings,
    status: "active",
    acquired: command.acquired || "level",
    stocked: false,
    shutdownUntilTurnId: null,
    blockedOnTurnId: null,
    plots: 1,
    vastCapacityLarge: spec.id === "stable" ? 3 : null,
  };
  state.facilities.push(facility);
  return facility;
}

function openTask(state, fields) {
  const task = {
    id: nid(state, "task"),
    status: "open",
    settled: false,
    ...fields,
  };
  state.tasks.push(task);
  return task;
}

function dueAfter(state, turns) {
  requireTurn(state);
  return state.clock.turn + turns;
}

export function apply(input, command) {
  if (!command || !command.type) throw new RuleError("bad_command", "Missing command.");
  if (command.idempotencyKey && input.idempotency[command.idempotencyKey]) {
    return { state: input, result: input.idempotency[command.idempotencyKey], replay: true };
  }
  if (command.expectedRevision != null && command.expectedRevision !== input.revision) {
    throw new RuleError("revision_conflict", "The shared record changed. Reload it, then try again. This attempt was not saved.");
  }
  assertWriter(command);
  const state = clone(input);
  switch (command.type) {
    case "set_settings":
      return setSettings(state, command);
    case "set_clock":
      return setClock(state, command);
    case "set_finance":
      return setFinance(state, command);
    case "set_capabilities":
      return setCapabilities(state, command);
    case "raise_level":
      return raiseLevel(state, command);
    case "split_unit":
      return splitUnit(state, command);
    case "add_special":
      return addSpecialCommand(state, command);
    case "replace_special":
    case "correct_special":
      return replaceSpecial(state, command);
    case "enlarge_special":
      return enlargeSpecial(state, command);
    case "add_basic":
      return addBasic(state, command);
    case "upgrade_basic":
      return upgradeBasic(state, command);
    case "remove_facility":
      return removeFacility(state, command);
    case "edit_facility":
      return editFacility(state, command);
    case "replace_basic":
      return replaceBasic(state, command);
    case "cancel_project":
      return cancelProject(state, command);
    case "add_wall_squares":
      return addWalls(state, command);
    case "mark_enclosure":
      return markEnclosure(state, command);
    case "take_turn":
      return takeTurn(state, command);
    case "set_calendar_anchor":
      return setCalendarAnchor(state, command);
    case "reanchor_calendar":
      return reanchorCalendar(state, command);
    case "set_order_start":
      return setOrderStart(state, command);
    case "finish_project":
      return finishProject(state, command);
    case "set_due_turn":
      return setDueTurn(state, command);
    case "roster_save":
      return rosterSave(state, command);
    case "roster_remove":
      return rosterRemove(state, command);
    case "record_goods":
      return recordGoods(state, command);
    case "commit_turn":
      return commitTurn(state, command);
    case "resolve_event":
      return resolveEvent(state, command);
    case "dm_override":
      return dmOverride(state, command);
    case "confirm_fall":
      return confirmFall(state, command);
    case "import_accept":
      return importAccept(state, command);
    case "save_settings":
      return saveSettings(state, command);
    case "set_level":
      return setLevel(state, command);
    case "record_defenders":
      return recordDefenders(state, command);
    case "set_loan":
      return setLoan(state, command);
    case "reserve_goods":
      return reserveGoods(state, command);
    case "record_order":
      return recordOrder(state, command);
    case "remove_goods":
      return removeGoods(state, command);
    case "remove_person":
      return removePerson(state, command);
    case "edit_person":
      return editPerson(state, command);
    case "replace_person":
      return replacePerson(state, command);
    case "assign_person":
      return assignPerson(state, command);
    default:
      throw new RuleError("unsupported", "That action is not available.");
  }
}

function readTurn(value, allowBlank) {
  if (value == null || value === "") {
    if (allowBlank) return null;
    throw new RuleError("bad_turn", "A Bastion turn is a whole number, starting at 1, or left unknown.");
  }
  const turn = Number(value);
  if (!Number.isInteger(turn) || turn < 1) throw new RuleError("bad_turn", "A Bastion turn is a whole number, starting at 1, or left unknown.");
  return turn;
}

function setSettings(state, command) {
  if (command.name) state.name = String(command.name).slice(0, 80);
  if (command.unitName || command.owner) {
    const unit = unitById(state, command.unitId || state.units[0].id);
    if (command.unitName) unit.name = String(command.unitName).slice(0, 80);
    if (command.owner) unit.owner = String(command.owner).slice(0, 120);
  }
  return finish(state, command, { turn: state.clock.turn }, "Updated estate settings.");
}

function setClock(state, command) {
  if (command.label != null) state.clock.label = String(command.label).slice(0, 120);
  if (Object.prototype.hasOwnProperty.call(command, "turn")) {
    state.clock.turn = readTurn(command.turn, true);
    state.clock.turnNeedsCheck = false;
  }
  return finish(state, command, { clock: { turn: state.clock.turn, label: state.clock.label } }, "Updated the Bastion turn and the session date.");
}

function setFinance(state, command) {
  if (command.cashGp == null || command.cashGp === "") {
    state.finance.cashKnown = false;
    state.finance.cashGp = null;
    return finish(state, command, { cashKnown: false }, "Cleared the cash balance back to unknown.");
  }
  const cash = Number(command.cashGp);
  if (!Number.isInteger(cash) || cash < 0) throw new RuleError("bad_amount", "Opening cash is a whole number of GP, or left unknown.");
  state.finance.cashKnown = true;
  state.finance.cashGp = cash;
  state.ledger.push({ id: nid(state, "led"), gp: 0, reason: `Opening cash set to ${cash} GP`, turn: state.clock.turn, key: command.idempotencyKey || null });
  return finish(state, command, { cashGp: cash }, `Set opening cash to ${cash} GP.`);
}

function setCapabilities(state, command) {
  const unit = unitById(state, command.unitId);
  const allowed = new Set(["arcane_or_tool", "holy_or_druid", "spellcasting_focus", "expertise", "fighting_or_unarmored"]);
  unit.capabilities = (command.capabilities || []).filter((item) => allowed.has(item));
  return finish(state, command, { capabilities: unit.capabilities }, "Updated facility prerequisites for this owner.");
}

function raiseLevel(state, command) {
  const unit = unitById(state, command.unitId);
  const level = Number(command.level);
  if (!Number.isInteger(level) || level < unit.level || level > 20) {
    throw new RuleError("bad_level", "The new level has to be the same or higher, up to 20.");
  }
  const gained = level - unit.level;
  unit.level = level;
  unit.replacementBank += gained;
  return finish(state, command, { level, gainedReplacements: gained, bank: unit.replacementBank }, gained ? `Level ${level}. One replacement was added for each level gained (${gained}).` : "Level unchanged.");
}

function occupiedSpecials(state, unitId) {
  return state.facilities.filter((item) => item.unitId === unitId && item.kind === "special" && item.status !== "archived");
}

function applyDirectLevel(state, unit, level, grant) {
  const next = Number(level);
  if (!Number.isInteger(next) || next < 1 || next > 20) {
    throw new RuleError("bad_level", "Choose a level from 1 to 20.");
  }
  const specials = occupiedSpecials(state, unit.id);
  const cap = specialCap(next);
  if (specials.length > cap) {
    throw new RuleError("cap", `Level ${next} allows ${cap} special facilities, and this unit already has ${specials.length}. Shut facilities still count.`);
  }
  for (const facility of specials) {
    const spec = specialById(facility.catalogId);
    if (spec && next < spec.level) {
      throw new RuleError("level_gate", `${spec.name} requires level ${spec.level}. Level ${next} is below what this unit's facilities require.`);
    }
  }
  const gained = next - unit.level;
  unit.level = next;
  const granted = grant && gained > 0 ? gained : 0;
  if (granted) unit.replacementBank += granted;
  return { gained, granted };
}

function setLevel(state, command) {
  const unit = unitById(state, command.unitId || state.units[0].id);
  const outcome = applyDirectLevel(state, unit, command.level, command.grantReplacements === true);
  const summary = outcome.granted
    ? `Level ${unit.level}. One replacement was added for each level gained (${outcome.granted}).`
    : `Level set to ${unit.level}. No replacement was added.`;
  return finish(state, command, { level: unit.level, bank: unit.replacementBank, granted: outcome.granted }, summary);
}

function saveSettings(state, command) {
  if (command.name) state.name = String(command.name).slice(0, 80);
  const unit = unitById(state, command.unitId || state.units[0].id);
  if (command.unitName) unit.name = String(command.unitName).slice(0, 80);
  if (command.owner) unit.owner = String(command.owner).slice(0, 120);
  if (command.label != null) state.clock.label = String(command.label).slice(0, 120);
  if (Object.prototype.hasOwnProperty.call(command, "turn")) {
    state.clock.turn = readTurn(command.turn, true);
    state.clock.turnNeedsCheck = false;
  }
  let levelNote = "Level unchanged. No replacement was added.";
  if (command.level != null && command.level !== "") {
    const outcome = applyDirectLevel(state, unit, command.level, command.grantReplacements === true);
    levelNote = outcome.granted
      ? `Level ${unit.level}. One replacement was added for each level gained (${outcome.granted}).`
      : `Level set to ${unit.level}. No replacement was added.`;
  }
  if (Array.isArray(command.capabilities)) {
    const allowed = new Set(["arcane_or_tool", "holy_or_druid", "spellcasting_focus", "expertise", "fighting_or_unarmored"]);
    unit.capabilities = command.capabilities.filter((item) => allowed.has(item));
  }
  return finish(
    state,
    command,
    { turn: state.clock.turn, level: unit.level, bank: unit.replacementBank },
    `Saved settings. ${levelNote}`,
  );
}

function splitUnit(state, command) {
  if (!command.acknowledgeNewCap) {
    throw new RuleError("confirm_split", "Splitting adds a new owner's own facility cap. Confirm that you mean to do that. Rooms are not copied.");
  }
  const level = Number(command.level);
  if (!Number.isInteger(level) || level < 5 || level > 20) throw new RuleError("bad_level", "A new owner unit needs a level from 5 to 20.");
  const unit = {
    id: nid(state, "unit"),
    name: String(command.name || "Character bastion").slice(0, 80),
    level,
    owner: String(command.owner || "Unassigned").slice(0, 120),
    replacementBank: 0,
    capabilities: [],
    neglectStreak: 0,
    fallen: false,
  };
  state.units.push(unit);
  return finish(state, command, { unitId: unit.id, cap: specialCap(level) }, `Opened a separate unit at level ${level} with its own cap of ${specialCap(level)}. No rooms were copied.`);
}

function addSpecialCommand(state, command) {
  const facility = addSpecial(state, command);
  return finish(state, command, { facilityId: facility.id }, `Added ${facility.name}. No build cost, because specials come from level.`);
}

function requireReason(command) {
  const reason = String(command.reason || "").trim().slice(0, 400);
  if (!reason) throw new RuleError("reason_required", "Write why this correction is being made. Cash was not changed.");
  command.reason = reason;
  return reason;
}

function assertCanTakeSpecial(state, unit, spec, ignoreId) {
  if (!spec) throw new RuleError("unknown_facility", "That replacement is not in the bastion list.");
  if (unit.level < spec.level) throw new RuleError("level_gate", `${spec.name} requires level ${spec.level}.`);
  if (spec.prereq && !unit.capabilities.includes(spec.prereq)) throw new RuleError("prerequisite", `${spec.name} needs a capability this unit does not have.`);
  if (spec.unique && activeSpecials(state, unit.id).some((item) => item.catalogId === spec.id && item.id !== ignoreId)) {
    throw new RuleError("duplicate", `${spec.name} is already kept.`);
  }
}

function activeAt(state, facilityId) {
  return state.roster.filter((person) => person.facilityId === facilityId && (!person.status || person.status === "active"));
}

function taskPending(task) {
  return Boolean(task) && !task.settled && !["resolved", "cancelled"].includes(task.status);
}

function linkedTasks(state, order) {
  return (state.tasks || []).filter((task) => task.orderId === order.id || (order.taskId && task.id === order.taskId));
}

function orderUnfinished(state, order) {
  if (!order || ["resolved", "cancelled"].includes(order.status)) return false;
  const tasks = linkedTasks(state, order);
  if (!tasks.length) return true;
  return tasks.some((task) => taskPending(task));
}

function facilityWork(state, facilityId) {
  const orders = (state.orders || []).filter((order) => order.facilityId === facilityId && orderUnfinished(state, order));
  const orderIds = new Set(orders.map((order) => order.id));
  const tasks = (state.tasks || []).filter((task) => taskPending(task) && (orderIds.has(task.orderId) || orders.some((order) => order.taskId === task.id)));
  const projects = (state.projects || []).filter((project) => project.status === "building" && project.facilityId === facilityId);
  const events = (state.events || []).filter((event) => event.status === "pending" && (
    event.facilityId === facilityId
    || event.detail?.facilityId === facilityId
    || event.detail?.shutdown === facilityId
  ));
  return { orders, tasks, projects, events };
}

function prepareFacilityClosure(state, facility, command) {
  const people = activeAt(state, facility.id);
  const defenders = people.filter((person) => person.category === "defender");
  const lieutenants = people.filter((person) => person.category === "lieutenant");
  const hirelings = people.filter((person) => person.category === "hireling");
  const others = people.filter((person) => !["defender", "lieutenant", "hireling"].includes(person.category));
  if (defenders.length) {
    const word = defenders.length === 1 ? "defender" : "defenders";
    throw new RuleError("facility_held", `${facility.name} still houses ${defenders.length} ${word}. Change the defender count before removing or replacing this room. Nobody was deleted, and cash was not changed.`);
  }
  if (lieutenants.length) {
    const word = lieutenants.length === 1 ? "lieutenant" : "lieutenants";
    throw new RuleError("facility_held", `${facility.name} still has ${lieutenants.length} ${word} assigned. Replace or release them before removing or replacing this room. Nobody was deleted, and cash was not changed.`);
  }
  const work = facilityWork(state, facility.id);
  if (work.events.length) {
    throw new RuleError("work_unresolved", `A record still waiting on a decision names ${facility.name}. Resolve that before removing or replacing the room. Cash was not changed.`);
  }
  if ((work.orders.length || work.tasks.length || work.projects.length) && command.cancelWork !== true) {
    throw new RuleError("work_unresolved", `${facility.name} has unfinished work. Confirm that you want it cancelled. Cancelling does not pay a sale, deliver a purchase, or refund money already spent.`);
  }
  let choice = "";
  if (hirelings.length) {
    choice = command.hirelings;
    if (choice !== "release" && choice !== "archive") {
      const word = hirelings.length === 1 ? "hireling" : "hirelings";
      throw new RuleError("hirelings_unresolved", `${facility.name} still has ${hirelings.length} ${word}. Choose whether they stay on the roster unassigned, or are marked released. They are not deleted either way.`);
    }
  }
  let purchaseKept = false;
  let cancelled = 0;
  if (command.cancelWork === true) {
    for (const task of work.tasks) {
      if (task.auto === "storehouse_sell" && !task.settled) {
        const lot = state.goods.find((item) => item.id === task.lotId);
        if (lot) lot.reservedGp = Math.max(0, (lot.reservedGp || 0) - (task.standardGp || 0));
      }
      if (task.auto === "storehouse_buy" && !task.settled) purchaseKept = true;
      task.status = "cancelled";
      task.settled = false;
    }
    for (const order of work.orders) {
      order.status = "cancelled";
      order.cancelledReason = "DM closed the facility before this work finished. It was not resolved and it was not paid.";
      cancelled += 1;
    }
    for (const project of work.projects) project.status = "cancelled";
  }
  let released = 0;
  let archived = 0;
  for (const person of hirelings) {
    person.facilityId = null;
    if (choice === "archive") {
      person.status = "released";
      const extra = `Released when ${facility.name} was closed.`;
      person.summary = [person.summary, extra].filter(Boolean).join(" ").slice(0, 160);
      archived += 1;
    } else {
      released += 1;
    }
  }
  for (const person of others) person.facilityId = null;
  facility.currentOrderId = null;
  const notes = [];
  if (others.length) notes.push(`${others.length} other assigned ${others.length === 1 ? "person was" : "people were"} kept on the roster and unassigned.`);
  if (released) notes.push(`${released} hireling${released === 1 ? "" : "s"} stayed on the roster, unassigned.`);
  if (archived) notes.push(`${archived} hireling${archived === 1 ? "" : "s"} ${archived === 1 ? "was" : "were"} marked released and ${archived === 1 ? "was" : "were"} not deleted.`);
  if (cancelled) notes.push(`${cancelled} unfinished order${cancelled === 1 ? "" : "s"} ${cancelled === 1 ? "was" : "were"} cancelled, not paid.`);
  if (purchaseKept) notes.push("Money already spent on a purchase was not refunded, and the goods were not delivered.");
  return { note: notes.length ? ` ${notes.join(" ")}` : "" };
}

function archiveFacility(state, facility, archivedReason) {
  facility.status = "archived";
  facility.archivedReason = archivedReason;
  state.archive.push(structuredClone(facility));
  state.facilities = state.facilities.filter((item) => item.id !== facility.id);
}

function specialSpaceAllowed(spec, space) {
  if (!["cramped", "roomy", "vast"].includes(space)) return false;
  if (spec.enlargeGp) return space === spec.space || space === "vast";
  return space === spec.space;
}

function applySpecialSpace(state, facility, space) {
  const spec = specialById(facility.catalogId);
  if (!spec || !specialSpaceAllowed(spec, space)) {
    throw new RuleError("bad_space", `${facility.name} is not recorded at that size. Enlargement, when the chapter has a price, stays on its own action.`);
  }
  if (facility.catalogId === "barrack") {
    const housed = defendersOf(state, facility.id).length;
    const cap = space === "vast" ? 25 : 12;
    if (housed > cap) {
      throw new RuleError("barrack_cap", `This barrack houses ${housed}, and the ${space} size holds ${cap}. The defender count was not changed.`);
    }
  }
  facility.space = space;
  facility.hirelings = spec.hirelings + (space === "vast" ? (spec.enlargeHirelings || 0) : 0);
  if (spec.id === "garden") facility.plots = space === "vast" ? 2 : 1;
  if (spec.id === "stable") facility.vastCapacityLarge = space === "vast" ? 6 : 3;
}

function replaceSpecial(state, command) {
  const unit = unitById(state, command.unitId);
  const current = facilityById(state, command.facilityId);
  if (current.kind !== "special") throw new RuleError("not_special", "That room is not a special facility.");
  if (current.unitId !== unit.id) throw new RuleError("wrong_unit", "That facility belongs to another owner.");
  const spec = specialById(command.catalogId);
  assertCanTakeSpecial(state, unit, spec, current.id);
  if (spec.id === current.catalogId) throw new RuleError("no_change", "Choose a different facility. Edit the note if this room is already the right one.");
  const correction = command.type === "correct_special" || command.dmOverride === true;
  if (correction && roleOf(command) !== "dm") throw new RuleError("forbidden", "Only the DM can correct a special facility.");
  if (correction) requireReason(command);
  if (!correction && unit.replacementBank < 1) {
    throw new RuleError("no_replacement", "This level has no unused replacement. Gaining a level grants one. The current level by itself does not grant a stack of swaps.");
  }
  const closure = prepareFacilityClosure(state, current, command);
  const archivedReason = command.type === "correct_special"
    ? `DM correction: ${command.reason}`
    : (command.dmOverride === true ? `DM override: ${command.reason}` : "Replaced");
  archiveFacility(state, current, archivedReason);
  if (!correction) unit.replacementBank -= 1;
  const acquired = command.type === "correct_special" ? "dm_correction" : (command.dmOverride === true ? "dm_override" : "replacement");
  const facility = {
    id: nid(state, "fac"),
    unitId: unit.id,
    kind: "special",
    catalogId: spec.id,
    name: spec.name,
    space: spec.space,
    hirelings: spec.hirelings,
    status: "active",
    acquired,
    stocked: false,
    shutdownUntilTurnId: null,
    blockedOnTurnId: null,
    plots: 1,
    vastCapacityLarge: spec.id === "stable" ? 3 : null,
  };
  state.facilities.push(facility);
  const lead = command.type === "correct_special"
    ? `DM correction: swapped ${current.name} for ${spec.name}. This did not spend a level-up replacement, and it is not the published once-per-level swap. The old room is archived. Cash was not changed.`
    : (command.dmOverride === true
      ? `DM override: replaced ${current.name} with ${spec.name} without using a level-up replacement. The old one stays in the archive. Cash was not changed.`
      : `Replaced ${current.name} with ${spec.name}. The old one stays in the archive.`);
  return finish(state, command, { facilityId: facility.id, bank: unit.replacementBank, acquired }, `${lead}${closure.note}`);
}

function removeFacility(state, command) {
  const reason = requireReason(command);
  const current = facilityById(state, command.facilityId);
  const closure = prepareFacilityClosure(state, current, command);
  const kind = current.kind;
  const name = current.name;
  archiveFacility(state, current, `DM correction: ${reason}`);
  const lead = kind === "basic"
    ? `DM correction: archived ${name}. This is not a sale. The bastion chapter does not give a price for removing a basic room, so cash was not changed.`
    : `DM correction: archived ${name}. Special facilities are not sold. Cash was not changed. The old room is in the archive.`;
  return finish(state, command, { facilityId: current.id, removed: true }, `${lead}${closure.note}`);
}

function editFacility(state, command) {
  requireReason(command);
  const facility = facilityById(state, command.facilityId);
  if (facility.status === "building" || state.projects.some((project) => project.status === "building" && project.facilityId === facility.id)) {
    throw new RuleError("work_unresolved", `${facility.name} is in the middle of an enlargement. Cancel that project or let it finish before editing the room. Cash was not changed.`);
  }
  const before = { name: facility.name, space: facility.space, note: facility.note || "", catalogId: facility.catalogId };
  if (command.note != null) facility.note = String(command.note).slice(0, 160);
  if (facility.kind === "basic") {
    if (command.roomId && command.roomId !== facility.catalogId) {
      const room = BASIC_ROOMS_SAFE(command.roomId);
      facility.catalogId = room.id;
      facility.name = room.name;
    }
    if (command.space && command.space !== facility.space) {
      if (!SPACE_SQUARES[command.space]) throw new RuleError("bad_space", "Choose cramped, roomy, or vast.");
      facility.space = command.space;
      facility.squares = SPACE_SQUARES[command.space];
    }
  } else if (facility.kind === "special") {
    if (command.roomId && command.roomId !== facility.catalogId) {
      throw new RuleError("not_basic", "A special facility is swapped from its own action. Edit can change the note or a wrongly recorded size.");
    }
    if (command.space && command.space !== facility.space) applySpecialSpace(state, facility, command.space);
  } else {
    throw new RuleError("missing_facility", "That room cannot be edited.");
  }
  const after = { name: facility.name, space: facility.space, note: facility.note || "", catalogId: facility.catalogId };
  if (before.name === after.name && before.space === after.space && before.note === after.note && before.catalogId === after.catalogId) {
    throw new RuleError("no_change", "Nothing on that room changed.");
  }
  return finish(
    state,
    command,
    { facilityId: facility.id, before, after },
    `DM correction: edited ${before.name}. Room: "${before.name}" → "${after.name}". Size: "${before.space}" → "${after.space}". Note: "${before.note}" → "${after.note}". Cash was not changed. This did not start a build and it is not a level-up replacement.`,
  );
}

function replaceBasic(state, command) {
  const reason = requireReason(command);
  const current = facilityById(state, command.facilityId);
  if (current.kind !== "basic") throw new RuleError("not_basic", "Use the special-facility swap for a special facility.");
  const room = BASIC_ROOMS_SAFE(command.roomId);
  if (!BASIC_BUILD[command.space]) throw new RuleError("bad_space", "Choose cramped, roomy, or vast.");
  if (current.catalogId === room.id && current.space === command.space) {
    throw new RuleError("no_change", "That is already the recorded room. Edit the note, or choose a different room.");
  }
  const closure = prepareFacilityClosure(state, current, command);
  const oldName = current.name;
  archiveFacility(state, current, `DM correction: ${reason}`);
  const facility = {
    id: nid(state, "fac"),
    unitId: current.unitId,
    kind: "basic",
    catalogId: room.id,
    name: room.name,
    space: command.space,
    status: "active",
    acquired: "dm_correction",
    squares: SPACE_SQUARES[command.space],
    note: "",
  };
  state.facilities.push(facility);
  return finish(
    state,
    command,
    { facilityId: facility.id, replacedId: current.id },
    `DM correction: replaced ${oldName} with ${room.name}. The old room is archived. No build was started and no money moved. This is not the published way to add a basic room.${closure.note}`,
  );
}

function cancelProject(state, command) {
  const reason = requireReason(command);
  const project = (state.projects || []).find((item) => item.id === command.projectId);
  if (!project || project.status !== "building") throw new RuleError("missing_project", "That build is not still in progress.");
  project.status = "cancelled";
  project.cancelledReason = reason;
  if (project.kind === "upgrade" && project.facilityId) {
    const facility = state.facilities.find((item) => item.id === project.facilityId);
    if (facility && facility.status === "building") facility.status = "active";
  }
  return finish(
    state,
    command,
    { projectId: project.id, cancelled: true },
    `DM correction: cancelled the unfinished work on ${project.name}. The build will not finish. Money already spent was not refunded.`,
  );
}

function enlargeSpecial(state, command) {
  const facility = facilityById(state, command.facilityId);
  const spec = specialById(facility.catalogId);
  if (!spec.enlargeGp) throw new RuleError("no_enlarge", "This facility has no enlargement price in the bastion rules.");
  if (facility.space === "vast") throw new RuleError("already_vast", "This facility is already vast.");
  spend(state, spec.enlargeGp, `Enlarged ${facility.name}`, command);
  facility.space = "vast";
  facility.hirelings += spec.enlargeHirelings || 0;
  if (spec.id === "garden") facility.plots = 2;
  if (spec.id === "stable") facility.vastCapacityLarge = 6;
  return finish(state, command, { facilityId: facility.id }, `Enlarged ${facility.name} for ${spec.enlargeGp} GP. No extra turns were added, because the chapter does not give a build time.`);
}

function addBasic(state, command) {
  const unit = unitById(state, command.unitId);
  const space = command.space;
  const build = BASIC_BUILD[space];
  if (!build) throw new RuleError("bad_space", "Choose cramped, roomy, or vast.");
  const room = BASIC_ROOMS_SAFE(command.roomId);
  if (command.inherited || command.starter) {
    const facility = {
      id: nid(state, "fac"),
      unitId: unit.id,
      kind: "basic",
      catalogId: room.id,
      name: room.name,
      space,
      status: "active",
      acquired: command.inherited ? "inherited" : "starter",
      squares: SPACE_SQUARES[space],
    };
    state.facilities.push(facility);
    return finish(state, command, { facilityId: facility.id, charged: 0 }, `Added ${room.name} with no charge.`);
  }
  spend(state, build.gp, `Build ${room.name}`, command);
  const project = {
    id: nid(state, "proj"),
    unitId: unit.id,
    kind: "basic",
    roomId: room.id,
    name: room.name,
    space,
    gp: build.gp,
    unscheduled: true,
    dueTurn: null,
    startedTurn: state.clock.turn,
    status: "building",
  };
  state.projects.push(project);
  return finish(state, command, { projectId: project.id, dueTurn: null, charged: build.gp }, `${room.name} costs ${build.gp} GP. The published build time is not a whole number of Bastion turns, so no finish turn was scheduled.`);
}

function BASIC_ROOMS_SAFE(roomId) {
  const rooms = {
    bedroom: "Bedroom",
    dining: "Dining room",
    parlor: "Parlor",
    courtyard: "Courtyard",
    kitchen: "Kitchen",
    storage: "Storage",
  };
  if (!rooms[roomId]) throw new RuleError("bad_room", "Choose a basic room from the list.");
  return { id: roomId, name: rooms[roomId] };
}

function upgradeBasic(state, command) {
  const facility = facilityById(state, command.facilityId);
  if (facility.kind !== "basic") throw new RuleError("not_basic", "Only basic rooms use this enlargement.");
  const step = BASIC_UPGRADE[facility.space];
  if (!step) throw new RuleError("already_vast", "This room is already vast.");
  spend(state, step.gp, `Enlarge ${facility.name}`, command);
  const project = {
    id: nid(state, "proj"),
    unitId: facility.unitId,
    kind: "upgrade",
    facilityId: facility.id,
    name: facility.name,
    from: facility.space,
    space: step.to,
    gp: step.gp,
    unscheduled: true,
    dueTurn: null,
    startedTurn: state.clock.turn,
    status: "building",
  };
  facility.status = "building";
  state.projects.push(project);
  return finish(state, command, { projectId: project.id, dueTurn: null }, `${facility.name} is enlarging. The published time is not a whole number of Bastion turns, so no finish turn was scheduled.`);
}

function addWalls(state, command) {
  const count = Number(command.squares);
  if (!Number.isInteger(count) || count < 1 || count > 200) throw new RuleError("bad_amount", "Enter how many 5-foot squares to start.");
  const gp = WALL_SQUARE.gp * count;
  spend(state, gp, `Wall squares ×${count}`, command);
  const ids = [];
  for (let i = 0; i < count; i += 1) {
    const square = {
      id: nid(state, "wall"),
      status: "building",
      unscheduled: true,
      dueTurn: null,
      startedTurn: state.clock.turn,
      gp: WALL_SQUARE.gp,
    };
    state.walls.squares.push(square);
    ids.push(square.id);
  }
  return finish(state, command, { ids, dueTurn: null, charged: gp }, `${count} wall squares are paid for. The published time is not a whole number of Bastion turns, so no finish turn was scheduled. The enclosure is still not marked complete.`);
}

function markEnclosure(state, command) {
  if (!String(command.reason || "").trim()) throw new RuleError("reason_required", "Say why the walls now form a complete enclosure. Square count does not decide it.");
  state.walls.enclosureComplete = Boolean(command.complete);
  return finish(state, command, { complete: state.walls.enclosureComplete }, state.walls.enclosureComplete ? "Marked the walls as a complete enclosure." : "Cleared the complete-enclosure mark.");
}

function takeTurn(state, command) {
  requireTurn(state);
  state.clock.turn += 1;
  const settled = settleDue(state, command);
  const shown = dateForTurn(state.clock.anchor, state.clock.turn);
  const dateText = shown?.text || "";
  const summary = dateText
    ? `Advanced to Bastion turn ${state.clock.turn}. The in-game date is ${dateText}.`
    : `Advanced to Bastion turn ${state.clock.turn}. No in-game date is set.`;
  return finish(state, command, { turn: state.clock.turn, date: dateText, shieldmeetUncertain: Boolean(shown?.shieldmeetUncertain), settled }, summary);
}

function applyAnchor(state, command, summary) {
  const parsed = normalizeAnchor(command);
  if (parsed.error) throw new RuleError("bad_date", parsed.error);
  state.clock.anchor = parsed.anchor;
  const shown = dateForTurn(parsed.anchor, parsed.anchor.turn);
  return finish(state, command, { anchor: parsed.anchor, text: shown?.text || "" }, summary(parsed.anchor.turn, shown?.text || ""));
}

function setCalendarAnchor(state, command) {
  return applyAnchor(state, command, (turn, text) => `Set the calendar anchor: turn ${turn} is ${text}. Later turns follow it. The turn counter was not changed.`);
}

function reanchorCalendar(state, command) {
  requireTurn(state);
  if (Number(command.turn) !== state.clock.turn) {
    throw new RuleError("bad_turn", "A date override re-anchors the current Bastion turn. It does not create a second counter.");
  }
  const reason = String(command.reason || "").trim();
  if (!reason) throw new RuleError("reason_required", "Say why this turn's date differs from the one derived so far.");
  command.reason = reason.slice(0, 400);
  return applyAnchor(state, command, (turn, text) => `Re-anchored turn ${turn} to ${text}. Later turns follow this date. ${reason}`);
}

function setOrderStart(state, command) {
  const order = (state.orders || []).find((item) => item.id === command.orderId);
  if (!order) throw new RuleError("missing_order", "That order is not on the record.");
  if (command.unknown === true) {
    order.startedTurn = null;
    order.startNeedsCheck = false;
    return finish(state, command, { orderId: order.id, startedTurn: null }, `Left the start of ${order.label || order.id} unknown. The old stored number was not used.`);
  }
  const started = readTurn(command.startedTurn, false);
  if (state.clock.turn != null && started > state.clock.turn) {
    throw new RuleError("bad_turn", "That Bastion turn is later than the current turn.");
  }
  order.startedTurn = started;
  order.startNeedsCheck = false;
  return finish(state, command, { orderId: order.id, startedTurn: started }, `Set the start of ${order.label || order.id} to Bastion turn ${started}.`);
}

function finishProject(state, command) {
  const project = (state.projects || []).find((item) => item.id === command.projectId && item.status === "building");
  if (!project) throw new RuleError("missing_project", "That build is not still in progress.");
  completeProject(state, project);
  return finish(state, command, { projectId: project.id, finished: true }, `Marked ${project.name} finished. No book duration was turned into a Bastion turn.`);
}

function setDueTurn(state, command) {
  const due = readTurn(command.dueTurn, false);
  const task = (state.tasks || []).find((item) => item.id === command.taskId);
  if (!task) throw new RuleError("missing_task", "That timer is not on the record.");
  task.dueTurn = due;
  task.timerNeedsCheck = false;
  return finish(state, command, { taskId: task.id, dueTurn: due }, `Set that work to finish on Bastion turn ${due}.`);
}

function settleDue(state, command) {
  const settled = [];
  const turn = state.clock.turn;
  for (const task of state.tasks) {
    if (task.status !== "open" || task.dueTurn == null || task.dueTurn > turn) continue;
    if (task.auto === "storehouse_sell") settled.push(settleSale(state, task, command));
    else if (task.auto === "storehouse_buy") settled.push(settlePurchase(state, task, command));
    else {
      task.status = "ready";
      settled.push({ taskId: task.id, status: "ready", label: task.note || "Order ready" });
    }
  }
  for (const project of state.projects) {
    if (project.status === "building" && project.dueTurn != null && project.dueTurn <= turn) {
      completeProject(state, project);
      settled.push({ projectId: project.id, name: project.name, status: "done" });
    }
  }
  for (const square of state.walls.squares) {
    if (square.status === "building" && square.dueTurn != null && square.dueTurn <= turn) {
      square.status = "built";
      settled.push({ wallId: square.id, status: "built" });
    }
  }
  return settled;
}

function completeProject(state, project) {
  project.status = "done";
  if (project.kind === "basic") {
    state.facilities.push({
      id: nid(state, "fac"),
      unitId: project.unitId,
      kind: "basic",
      catalogId: project.roomId,
      name: project.name,
      space: project.space,
      status: "active",
      acquired: "built",
      squares: SPACE_SQUARES[project.space],
    });
  }
  if (project.kind === "upgrade") {
    const facility = state.facilities.find((item) => item.id === project.facilityId);
    if (facility) {
      facility.space = project.space;
      facility.status = "active";
      facility.squares = SPACE_SQUARES[project.space];
    }
  }
}

function settleSale(state, task, command) {
  if (task.settled) return { taskId: task.id, replay: true, proceeds: task.proceeds };
  receive(state, task.proceeds, `Sold ${task.standardGp} GP of goods`, command);
  task.settled = true;
  task.status = "resolved";
  const lot = state.goods.find((item) => item.id === task.lotId);
  if (lot) {
    lot.standardGp -= task.standardGp;
    lot.reservedGp = Math.max(0, (lot.reservedGp || 0) - task.standardGp);
    if (lot.standardGp <= 0) lot.status = "sold";
  }
  return { taskId: task.id, proceeds: task.proceeds };
}

function settlePurchase(state, task, command) {
  if (task.settled) return { taskId: task.id, replay: true };
  const boughtName = goodsLabel(task.goodsName);
  goodsPrice(task.standardGp);
  state.goods.push({
    id: nid(state, "good"),
    name: boughtName,
    standardGp: task.standardGp,
    reservedGp: 0,
    status: "on_hand",
    unitId: task.unitId,
  });
  task.settled = true;
  task.status = "resolved";
  return { taskId: task.id, standardGp: task.standardGp };
}

const PERSON_CATEGORIES = new Set(["household", "hireling", "defender", "guest", "lieutenant", "creature"]);

function cleanPersonName(name) {
  return String(name || "").trim().slice(0, 80);
}

function categoryLocked(state, person) {
  const active = !person.status || person.status === "active";
  if (!active) return false;
  if (person.category === "defender" || person.protectsOnce) return true;
  return Boolean(person.facilityId && state.facilities.some((item) => item.id === person.facilityId && item.status !== "archived"));
}

function rosterSave(state, command) {
  const person = command.person || {};
  const name = cleanPersonName(person.name);
  if (!PERSON_CATEGORIES.has(person.category)) throw new RuleError("bad_category", "Choose a roster category.");
  const record = {
    id: person.id || nid(state, "npc"),
    name: name.slice(0, 80),
    category: person.category,
    summary: String(person.summary || "").slice(0, 160),
    role: String(person.role || "").slice(0, 80),
    link: String(person.link || "").slice(0, 300),
    unitId: person.unitId || state.units[0].id,
    facilityId: person.facilityId || null,
    status: person.status || "active",
    housed: Boolean(person.housed),
    protectsOnce: Boolean(person.protectsOnce),
  };
  if (record.link && !/^https?:\/\//.test(record.link)) throw new RuleError("bad_link", "A link should start with http:// or https://, or be left blank.");
  const index = state.roster.findIndex((item) => item.id === record.id);
  if (index >= 0) state.roster[index] = record;
  else state.roster.push(record);
  return finish(state, command, { personId: record.id }, `Saved ${record.name || "an unnamed person"}.`);
}

function rosterRemove(state, command) {
  const person = state.roster.find((item) => item.id === command.personId);
  if (!person) throw new RuleError("missing_person", "That person is not on the roster.");
  person.status = "gone";
  return finish(state, command, { personId: person.id }, `Marked ${person.name} as gone. The name stays in the log.`);
}

function mentionsId(value, id) {
  if (value === id) return true;
  if (Array.isArray(value)) return value.some((item) => mentionsId(item, id));
  if (value && typeof value === "object") return Object.values(value).some((item) => mentionsId(item, id));
  return false;
}

function personHoldReason(state, person) {
  const active = !person.status || person.status === "active";
  if (active && person.category === "defender") {
    return "That defender is still active and counted. Change the defender count instead of deleting the name. Cash was not changed.";
  }
  if (active && person.facilityId) {
    const facility = state.facilities.find((item) => item.id === person.facilityId && item.status !== "archived");
    if (facility) return "That person is still assigned to a facility. Clear that assignment before removing them. Cash was not changed.";
  }
  if (active && person.protectsOnce) {
    return "That person is still set to protect the bastion once. Cash was not changed.";
  }
  const openOrder = (state.orders || []).some((order) => !["resolved", "cancelled"].includes(order.status) && mentionsId(order, person.id));
  const openTask = (state.tasks || []).some((task) => task.status === "open" && mentionsId(task, person.id));
  const pendingEvent = (state.events || []).some((event) => event.status === "pending" && mentionsId(event, person.id));
  if (openOrder || openTask || pendingEvent) {
    return "That person is tied to an order that has not finished. Release that link before removing them. Cash was not changed.";
  }
  return "";
}

function removePerson(state, command) {
  const person = state.roster.find((item) => item.id === command.personId);
  if (!person) throw new RuleError("missing_person", "That person is not on the roster.");
  const reason = personHoldReason(state, person);
  if (reason) throw new RuleError("person_held", reason);
  const cashGp = state.finance.cashGp;
  const cashKnown = state.finance.cashKnown;
  state.roster = state.roster.filter((item) => item.id !== person.id);
  state.finance.cashGp = cashGp;
  state.finance.cashKnown = cashKnown;
  return finish(state, command, { personId: person.id, removed: true }, `Removed ${person.name || "unnamed person"}. Cash was not changed.`);
}

function editPerson(state, command) {
  const person = state.roster.find((item) => item.id === command.personId);
  if (!person) throw new RuleError("missing_person", "That person is not on the roster.");
  const name = cleanPersonName(command.name);
  const role = String(command.role || "").slice(0, 80);
  const summary = String(command.summary || "").slice(0, 160);
  const link = String(command.link || "").slice(0, 300);
  if (link && !/^https?:\/\//.test(link)) throw new RuleError("bad_link", "A link should start with http:// or https://, or be left blank.");
  const category = command.category || person.category;
  if (!PERSON_CATEGORIES.has(category)) throw new RuleError("bad_category", "Choose a roster category.");
  if (category !== person.category && categoryLocked(state, person)) {
    throw new RuleError("category_locked", "That person's category stays put while they are a defender, assigned to a facility, or set to protect the bastion.");
  }
  const oldValues = { name: person.name, role: person.role, summary: person.summary, link: person.link, category: person.category };
  const newValues = { name, role, summary, link, category };
  person.name = name;
  person.role = role;
  person.summary = summary;
  person.link = link;
  person.category = category;
  const summaryText = `Edited roster ${person.id}. Name: "${oldValues.name}" → "${newValues.name}". Role: "${oldValues.role}" → "${newValues.role}". Category: "${oldValues.category}" → "${newValues.category}". Summary: "${oldValues.summary}" → "${newValues.summary}". Link: "${oldValues.link}" → "${newValues.link}".`;
  return finish(state, command, { personId: person.id, old: oldValues, new: newValues }, summaryText);
}

function applyPersonEdits(state, person, command) {
  const name = command.name == null ? person.name : cleanPersonName(command.name);
  const role = command.role == null ? person.role : String(command.role).slice(0, 80);
  const summary = command.summary == null ? person.summary : String(command.summary).slice(0, 160);
  const link = command.link == null ? person.link : String(command.link).slice(0, 300);
  if (link && !/^https?:\/\//.test(link)) throw new RuleError("bad_link", "A link should start with http:// or https://, or be left blank.");
  const category = command.category || person.category;
  if (!PERSON_CATEGORIES.has(category)) throw new RuleError("bad_category", "Choose a roster category.");
  if (category !== person.category && categoryLocked(state, person)) {
    throw new RuleError("category_locked", "That person's category stays put while they are a defender, assigned to a facility, or set to protect the bastion.");
  }
  return { name, role, summary, link, category };
}

function replacePerson(state, command) {
  requireReason(command);
  const person = state.roster.find((item) => item.id === command.personId);
  if (!person) throw new RuleError("missing_person", "That person is not on the roster.");
  const fields = applyPersonEdits(state, person, command);
  const openOrder = (state.orders || []).some((order) => orderUnfinished(state, order) && mentionsId(order, person.id));
  const openTask = (state.tasks || []).some((task) => taskPending(task) && mentionsId(task, person.id));
  const pendingEvent = (state.events || []).some((event) => event.status === "pending" && mentionsId(event, person.id));
  if (openOrder || openTask || pendingEvent) {
    throw new RuleError("person_held", "That person is tied to work that has not finished. Release that link before replacing them. Cash was not changed.");
  }
  const facilityId = person.facilityId || null;
  const housed = Boolean(person.housed);
  const protectsOnce = Boolean(person.protectsOnce);
  const unitId = person.unitId;
  const oldName = person.name;
  person.status = "replaced";
  person.facilityId = null;
  person.housed = false;
  person.protectsOnce = false;
  const record = {
    id: nid(state, "npc"),
    name: fields.name,
    category: fields.category,
    summary: fields.summary,
    role: fields.role,
    link: fields.link,
    unitId,
    facilityId,
    status: "active",
    housed,
    protectsOnce,
  };
  state.roster.push(record);
  const label = record.name || "an unnamed person";
  return finish(
    state,
    command,
    { personId: record.id, replacedId: person.id },
    `Replaced roster ${person.id} ("${oldName}") with ${record.id} ("${label}"). The old name stays on the roster as replaced. Cash was not changed.`,
  );
}

function assignPerson(state, command) {
  requireReason(command);
  const person = state.roster.find((item) => item.id === command.personId);
  if (!person) throw new RuleError("missing_person", "That person is not on the roster.");
  const fields = applyPersonEdits(state, person, command);
  let facilityId = command.facilityId;
  if (facilityId === "" || facilityId == null) facilityId = null;
  if (facilityId) {
    const facility = facilityById(state, facilityId);
    if (fields.category === "defender" && facility.catalogId === "barrack") {
      const housed = defendersOf(state, facility.id).filter((item) => item.id !== person.id).length;
      if (housed + 1 > barrackCap(facility)) {
        throw new RuleError("barrack_cap", `This barrack houses ${barrackCap(facility)}, not ${housed + 1}.`);
      }
    }
  } else if (fields.category === "defender" && (!person.status || person.status === "active")) {
    throw new RuleError("facility_held", "A defender stays housed until you change the defender count. The assignment was not cleared.");
  }
  const oldFacility = person.facilityId || null;
  person.name = fields.name;
  person.role = fields.role;
  person.summary = fields.summary;
  person.link = fields.link;
  person.category = fields.category;
  person.facilityId = facilityId;
  return finish(
    state,
    command,
    { personId: person.id, facilityId },
    `DM correction: assigned roster ${person.id} ("${person.name || "an unnamed person"}") from "${oldFacility || ""}" to "${facilityId || ""}". Cash was not changed.`,
  );
}

function recordDefenders(state, command) {
  const facility = facilityById(state, command.facilityId);
  const count = Number(command.count);
  if (!Number.isInteger(count) || count < 0 || count > 25) {
    throw new RuleError("bad_amount", "Defender count is a whole number from 0 to 25.");
  }
  if (facility.catalogId === "barrack" && count > barrackCap(facility)) {
    throw new RuleError("barrack_cap", `This barrack houses ${barrackCap(facility)}, not ${count}.`);
  }
  const names = (Array.isArray(command.names) ? command.names : [])
    .map((name) => String(name || "").trim())
    .filter(Boolean)
    .map((name) => name.slice(0, 80));
  if (names.length > count) throw new RuleError("bad_amount", "There are more names than the defender count.");
  const existing = state.roster.filter((person) => person.category === "defender" && person.status === "active" && person.facilityId === facility.id);
  for (let index = count; index < existing.length; index += 1) existing[index].status = "gone";
  const kept = existing.slice(0, count);
  while (kept.length < count) {
    const person = {
      id: nid(state, "npc"),
      name: `Defender ${state.roster.length + 1}`,
      category: "defender",
      summary: "Recorded as already housed. This was not a Recruit order.",
      role: "Defender",
      link: "",
      unitId: facility.unitId,
      facilityId: facility.id,
      status: "active",
      housed: true,
      protectsOnce: false,
    };
    state.roster.push(person);
    kept.push(person);
  }
  names.forEach((name, index) => {
    kept[index].name = name;
  });
  return finish(state, command, { facilityId: facility.id, count }, `Recorded ${count} defenders at ${facility.name}. No Recruit turn was run.`);
}

function setLoan(state, command) {
  if (!state.finance.loans) state.finance.loans = [];
  if (command.remove === true) {
    const index = state.finance.loans.findIndex((loan) => loan.id === command.loanId);
    if (index < 0) throw new RuleError("missing_loan", "That loan is not on the record.");
    const [removed] = state.finance.loans.splice(index, 1);
    return finish(state, command, { loanId: removed.id, removed: true }, `Removed the loan from ${removed.creditor}. Cash was not changed.`);
  }
  const creditor = String(command.creditor || "").trim();
  if (!creditor) throw new RuleError("name_required", "A loan needs a creditor label.");
  const amount = Number(command.amountGp);
  if (!Number.isInteger(amount) || amount < 0) throw new RuleError("bad_amount", "Loan amount is a whole number of GP, or zero.");
  const note = String(command.note || "").slice(0, 240);
  if (command.loanId) {
    const loan = state.finance.loans.find((item) => item.id === command.loanId);
    if (!loan) throw new RuleError("missing_loan", "That loan is not on the record.");
    loan.creditor = creditor.slice(0, 80);
    loan.amountGp = amount;
    loan.note = note;
    return finish(state, command, { loanId: loan.id }, `Updated the loan from ${loan.creditor}. Cash was not changed.`);
  }
  const loan = { id: nid(state, "loan"), creditor: creditor.slice(0, 80), amountGp: amount, note };
  state.finance.loans.push(loan);
  return finish(state, command, { loanId: loan.id }, `Recorded a loan of ${amount} GP from ${loan.creditor}. Cash was not changed.`);
}

function goodsPrice(amount) {
  const value = Number(amount);
  if (!Number.isInteger(value) || value < 1) {
    throw new RuleError("bad_amount", "Goods need a list price above zero, in whole GP.");
  }
  return value;
}

function goodsLabel(name) {
  const cleaned = String(name ?? "").trim();
  if (!cleaned) throw new RuleError("name_required", "Goods need a name.");
  return cleaned.slice(0, 80);
}

function reserveGoods(state, command) {
  const amount = goodsPrice(command.standardGp);
  const note = String(command.note || "Committed to an order already underway. This did not charge or pay anyone.").slice(0, 240);
  if (command.lotId) {
    const lot = state.goods.find((item) => item.id === command.lotId && item.status === "on_hand");
    if (!lot) throw new RuleError("missing_goods", "Those goods are not on hand.");
    const available = lot.standardGp - (lot.reservedGp || 0);
    if (amount > available) throw new RuleError("bad_amount", "That commits more than the goods still free.");
    lot.reservedGp = (lot.reservedGp || 0) + amount;
    lot.commitment = note;
    return finish(state, command, { lotId: lot.id, reservedGp: lot.reservedGp }, `Marked ${amount} GP of ${lot.name} as already committed. Cash was not changed.`);
  }
  const name = goodsLabel(command.name);
  const lot = {
    id: nid(state, "good"),
    name,
    standardGp: amount,
    reservedGp: amount,
    status: "on_hand",
    unitId: command.unitId || state.units[0].id,
    note,
    commitment: note,
  };
  state.goods.push(lot);
  return finish(state, command, { lotId: lot.id, reservedGp: amount }, `Recorded ${amount} GP of ${lot.name} as already committed. Cash was not changed.`);
}

function goodsHeld(state, lot) {
  if ((lot.reservedGp || 0) > 0) return true;
  const openOrder = (state.orders || []).some((order) => order.lotId === lot.id && !["resolved", "cancelled"].includes(order.status));
  const openTask = (state.tasks || []).some((task) => task.lotId === lot.id && task.status === "open");
  return openOrder || openTask;
}

function removeGoods(state, command) {
  const lot = state.goods.find((item) => item.id === command.lotId);
  if (!lot) throw new RuleError("missing_goods", "Those goods are not on the record.");
  if (goodsHeld(state, lot)) {
    throw new RuleError("goods_committed", "Those goods are still reserved or tied to an order that has not finished. Release that link before removing them. Cash was not changed.");
  }
  const cashGp = state.finance.cashGp;
  const cashKnown = state.finance.cashKnown;
  state.goods = state.goods.filter((item) => item.id !== lot.id);
  state.finance.cashGp = cashGp;
  state.finance.cashKnown = cashKnown;
  return finish(state, command, { lotId: lot.id, removed: true }, `Removed ${lot.name || "unnamed goods"}. Cash was not changed.`);
}

export function orderStartedTurn(order) {
  if (!order || order.startNeedsCheck) return null;
  if (order.startedTurn == null || order.startedTurn === "") return null;
  return Number(order.startedTurn);
}

function recordOrder(state, command) {
  const facility = facilityById(state, command.facilityId);
  if (facility.kind !== "special") throw new RuleError("not_special", "Basic rooms do not take orders.");
  const spec = specialById(facility.catalogId);
  const sub = spec?.subs.find((item) => item.id === command.suborder);
  if (!sub) throw new RuleError("bad_order", `${facility.name} cannot take that order.`);
  const started = readTurn(command.startedTurn, true);
  if (started != null && state.clock.turn != null && started > state.clock.turn) {
    throw new RuleError("bad_turn", "That Bastion turn is later than the current turn.");
  }
  const note = String(command.note || "").slice(0, 240);
  if (!state.orders) state.orders = [];
  let order = state.orders.find((item) => item.facilityId === facility.id && item.status === "in_progress" && item.recorded);
  if (!order) {
    order = { id: nid(state, "ord"), facilityId: facility.id, unitId: facility.unitId, recorded: true };
    state.orders.push(order);
  }
  order.suborder = sub.id;
  order.label = sub.label;
  order.status = "in_progress";
  order.startedTurn = started;
  order.startNeedsCheck = false;
  order.note = note;
  order.auto = null;
  order.recorded = true;
  facility.currentOrderId = order.id;
  return finish(state, command, { orderId: order.id, startedTurn: started }, `Marked ${facility.name} as already running ${sub.label}. No turn was resolved and no money moved.`);
}

function recordGoods(state, command) {
  const standardGp = goodsPrice(command.standardGp);
  const name = goodsLabel(command.name);
  const lot = {
    id: nid(state, "good"),
    name,
    standardGp,
    reservedGp: 0,
    status: "on_hand",
    unitId: command.unitId || state.units[0].id,
    note: "Recorded as already on hand. This did not charge or pay anyone.",
  };
  state.goods.push(lot);
  return finish(state, command, { lotId: lot.id }, `Recorded ${lot.standardGp} GP of ${lot.name} without a sale or purchase.`);
}

function commitTurn(state, command) {
  const unit = unitById(state, command.unitId);
  if (unit.fallen) throw new RuleError("fallen", "This bastion has fallen. Start a new one instead of issuing orders.");
  if (state.events.some((event) => event.unitId === unit.id && event.status === "pending")) {
    throw new RuleError("event_pending", "Resolve the pending Maintain event before the next turn.");
  }
  const presence = command.presence;
  if (!["present", "absent", "absent_with_contact"].includes(presence)) {
    throw new RuleError("presence", "Say whether the owner is here, away, or away but able to send word.");
  }
  let mode = command.mode;
  if (presence === "absent" && mode !== "no_orders") mode = "maintain";
  if (!["maintain", "orders", "no_orders"].includes(mode)) throw new RuleError("bad_mode", "Choose Maintain, orders, or no orders.");
  const turn = {
    id: nid(state, "turn"),
    unitId: unit.id,
    presence,
    contact: String(command.contact || "").slice(0, 160),
    mode,
    status: "committed",
    turn: state.clock.turn,
    orderIds: [],
  };
  state.turns.push(turn);
  for (const facility of state.facilities.filter((item) => item.unitId === unit.id)) {
    if (facility.shutdownUntilTurnId === "next") {
      facility.blockedOnTurnId = turn.id;
      facility.shutdownUntilTurnId = null;
      facility.status = "shutdown";
    } else if (facility.blockedOnTurnId && facility.blockedOnTurnId !== turn.id) {
      facility.blockedOnTurnId = null;
      if (facility.status === "shutdown") facility.status = "active";
    }
  }
  if (mode === "maintain") {
    if ((command.orders || []).length) throw new RuleError("maintain_exclusive", "Maintain covers the whole ownership unit. It cannot share a turn with other orders.");
    unit.neglectStreak = 0;
    const event = {
      id: nid(state, "event"),
      unitId: unit.id,
      turnId: turn.id,
      status: "pending",
      roll: null,
      type: null,
      detail: {},
    };
    state.events.push(event);
    turn.eventId = event.id;
    return finish(state, command, { turnId: turn.id, eventId: event.id }, "Maintain is in effect for this whole unit. Roll or choose the event before the next turn.");
  }
  if (mode === "no_orders") {
    unit.neglectStreak += 1;
    const warning = unit.neglectStreak >= unit.level ? `No orders have been issued for ${unit.neglectStreak} turns, which matches this owner's level. The DM can confirm a fall. It is not automatic.` : "";
    return finish(state, command, { turnId: turn.id, neglectStreak: unit.neglectStreak, warning }, warning || "Recorded a turn with no orders. This is not the same as Maintain.");
  }
  unit.neglectStreak = 0;
  const orders = command.orders || [];
  if (!orders.length) throw new RuleError("no_orders", "Choose at least one order, or switch this turn to Maintain or no orders.");
  for (const request of orders) {
    const facility = facilityById(state, request.facilityId);
    if (facility.unitId !== unit.id) throw new RuleError("wrong_unit", "An order can only go to this owner's facility.");
    if (facility.kind !== "special") throw new RuleError("not_special", "Basic rooms do not take orders.");
    if (facility.blockedOnTurnId === turn.id || facility.status === "shutdown") {
      throw new RuleError("shutdown", `${facility.name} is shut for this turn.`);
    }
    const spec = specialById(facility.catalogId);
    const sub = spec.subs.find((item) => item.id === request.suborder);
    if (!sub) throw new RuleError("bad_order", `${facility.name} cannot take that order.`);
    if (sub.id === "craft_magic" && unit.level < 9) throw new RuleError("level_gate", "Magic-item crafting from this facility waits until level 9.");
    const order = placeOrder(state, command, unit, facility, spec, sub, request, turn);
    turn.orderIds.push(order.id);
  }
  return finish(state, command, { turnId: turn.id, orderIds: turn.orderIds }, "Orders committed.");
}

function placeOrder(state, command, unit, facility, spec, sub, request, turn) {
  const order = {
    id: nid(state, "ord"),
    turnId: turn.id,
    unitId: unit.id,
    facilityId: facility.id,
    suborder: sub.id,
    label: sub.label,
    status: "committed",
    auto: sub.auto,
  };
  if (sub.auto === "barrack_recruit") {
    const count = Number(request.count);
    const housed = defendersOf(state, facility.id).length;
    const room = barrackCap(facility) - housed;
    if (room <= 0) throw new RuleError("barrack_full", "This barrack is full, so it cannot recruit.");
    if (!Number.isInteger(count) || count < 1 || count > 4) throw new RuleError("bad_amount", "Recruit 1 to 4 defenders.");
    if (count > room) throw new RuleError("barrack_cap", `This barrack has room for ${room} more, not ${count}.`);
    const ids = [];
    for (let i = 0; i < count; i += 1) {
      const person = {
        id: nid(state, "npc"),
        name: `Defender ${state.roster.length + 1}`,
        category: "defender",
        summary: "",
        role: "Defender",
        link: "",
        unitId: unit.id,
        facilityId: facility.id,
        status: "active",
        housed: true,
        protectsOnce: false,
      };
      state.roster.push(person);
      ids.push(person.id);
    }
    order.status = "resolved";
    order.result = { recruited: count, defenderIds: ids, housed: housed + count, cap: barrackCap(facility) };
  } else if (sub.auto === "storehouse_buy") {
    const standardGp = Number(request.standardGp);
    const limit = buyLimitGp(unit.level);
    if (!Number.isInteger(standardGp) || standardGp < 1 || standardGp > limit) {
      throw new RuleError("buy_limit", `This level can buy up to ${limit} GP of goods in one order.`);
    }
    spend(state, standardGp, `Storehouse purchase of ${standardGp} GP`, command);
    const task = openTask(state, {
      auto: "storehouse_buy",
      unitId: unit.id,
      orderId: order.id,
      goodsName: request.goodsName == null ? "Goods" : goodsLabel(request.goodsName),
      standardGp,
      dueTurn: dueAfter(state, 1),
    });
    order.taskId = task.id;
    order.dueTurn = task.dueTurn;
  } else if (sub.auto === "storehouse_sell") {
    const lot = state.goods.find((item) => item.id === request.lotId && item.status === "on_hand");
    if (!lot) throw new RuleError("missing_goods", "Choose goods that are still on hand.");
    const standardGp = Number(request.standardGp ?? lot.standardGp - (lot.reservedGp || 0));
    const available = lot.standardGp - (lot.reservedGp || 0);
    if (!Number.isInteger(standardGp) || standardGp < 1 || standardGp > available) {
      throw new RuleError("bad_amount", "Sell a list-price amount that is still free.");
    }
    const proceeds = saleProceeds(standardGp, unit.level);
    lot.reservedGp = (lot.reservedGp || 0) + standardGp;
    const task = openTask(state, {
      auto: "storehouse_sell",
      unitId: unit.id,
      orderId: order.id,
      lotId: lot.id,
      standardGp,
      proceeds,
      dueTurn: dueAfter(state, 1),
    });
    order.taskId = task.id;
    order.dueTurn = task.dueTurn;
    order.preview = { standardGp, proceeds, turns: 1 };
  } else if (sub.auto === "armory_stock") {
    const defenders = state.roster.filter((person) => person.unitId === unit.id && person.category === "defender" && person.status === "active").length;
    const hasSmithy = activeSpecials(state, unit.id).some((item) => item.catalogId === "smithy");
    let cost = 100 + 100 * defenders;
    if (hasSmithy) cost = Math.floor(cost / 2);
    spend(state, cost, "Stocked the armory", command);
    facility.stocked = true;
    order.status = "resolved";
    order.result = { cost, defenders, halved: hasSmithy };
  } else if (sub.auto === "war_lieutenant") {
    const count = state.roster.filter((person) => person.unitId === unit.id && person.category === "lieutenant" && person.status === "active").length;
    if (count >= 10) throw new RuleError("lieutenant_cap", "This war room already has 10 lieutenants.");
    state.roster.push({
      id: nid(state, "npc"),
      name: String(request.name || `Lieutenant ${count + 1}`).slice(0, 80),
      category: "lieutenant",
      summary: "",
      role: "Lieutenant",
      link: "",
      unitId: unit.id,
      facilityId: facility.id,
      status: "active",
      housed: true,
      protectsOnce: false,
    });
    order.status = "resolved";
  } else {
    const turns = request.turns != null && request.turns !== "" ? Number(request.turns) : sub.turns;
    if (request.gp != null) {
      const gp = Number(request.gp);
      if (!Number.isInteger(gp) || gp < 0) throw new RuleError("bad_amount", "Enter a whole GP cost, or leave the order unpriced.");
      if (gp > 0) spend(state, gp, sub.label, command);
    }
    if (turns == null) {
      order.status = "awaiting_dm";
      order.note = sub.note || "Enter a duration and any price from the rules outside this chapter.";
    } else {
      if (!Number.isInteger(turns) || turns < 0) throw new RuleError("bad_turn", "Duration has to be a whole number of Bastion turns.");
      const task = openTask(state, {
        auto: "manual",
        unitId: unit.id,
        orderId: order.id,
        note: String(request.note || sub.note || "").slice(0, 240),
        dueTurn: turns === 0 ? state.clock.turn : dueAfter(state, turns),
      });
      order.taskId = task.id;
      order.dueTurn = task.dueTurn;
    }
  }
  state.tasks;
  if (!state.orders) state.orders = [];
  state.orders.push(order);
  return order;
}

function resolveEvent(state, command) {
  const event = state.events.find((item) => item.id === command.eventId);
  if (!event) throw new RuleError("missing_event", "That event is not open.");
  if (event.status === "resolved") {
    throw new RuleError("already_resolved", "This event is already in the log. It will not be rolled again.");
  }
  const unit = unitById(state, event.unitId);
  let type = command.eventIdChoice || null;
  let roll = command.roll == null ? null : Number(command.roll);
  if (roll != null) {
    if (!Number.isInteger(roll) || roll < 1 || roll > 100) throw new RuleError("bad_roll", "Enter a d100 result from 1 to 100, or choose the event yourself.");
    type = eventFromRoll(roll).id;
    if (type === "opportunity" && command.opportunityReroll) {
      throw new RuleError("bad_roll", "Resolve the opportunity choice before rolling a replacement event.");
    }
  }
  if (!type) throw new RuleError("event_choice", "Roll a d100 or choose the event. Refreshing the page will not roll again.");
  const known = EVENTS.find((item) => item.id === type);
  if (!known) throw new RuleError("event_choice", "That is not a bastion event.");
  event.roll = roll;
  event.type = type;
  event.status = "resolved";
  event.detail = {};
  const result = resolveEventBody(state, command, unit, event);
  event.result = result;
  return finish(state, command, result, `${known.name} resolved.`);
}

function resolveEventBody(state, command, unit, event) {
  const detail = command.detail || {};
  if (event.type === "all_is_well") {
    event.detail = { note: String(detail.note || "").slice(0, 240) };
    return { type: event.type, deltas: [] };
  }
  if (event.type === "attack") {
    return resolveAttack(state, command, unit, event);
  }
  if (event.type === "criminal") {
    const bribeRoll = Number(detail.bribeRoll);
    if (!Number.isInteger(bribeRoll) || bribeRoll < 1 || bribeRoll > 6) throw new RuleError("bad_roll", "Enter the bribe die, from 1 to 6.");
    const gp = bribeRoll * 100;
    if (detail.choice === "pay") {
      spend(state, gp, "Bribe to keep a hireling", command);
      event.detail = { choice: "pay", gp };
      return { type: event.type, gp };
    }
    if (detail.choice !== "arrest") throw new RuleError("event_choice", "Pay the bribe or let the hireling be arrested.");
    const person = state.roster.find((item) => item.id === detail.personId && item.status === "active");
    if (!person) throw new RuleError("missing_person", "Name the hireling who is arrested.");
    person.status = "arrested";
    const facility = person.facilityId ? state.facilities.find((item) => item.id === person.facilityId) : null;
    const staffLeft = state.roster.filter((item) => item.facilityId === person.facilityId && item.status === "active" && item.category === "hireling").length;
    if (facility && staffLeft < 1 && person.category === "hireling") {
      facility.status = "shutdown";
      facility.shutdownUntilTurnId = "next";
    }
    event.detail = { choice: "arrest", personId: person.id };
    return { type: event.type, arrested: person.name };
  }
  if (event.type === "opportunity") {
    if (detail.choice === "decline") {
      event.detail = { choice: "decline" };
      return { type: event.type, choice: "decline" };
    }
    if (detail.choice !== "pay") throw new RuleError("event_choice", "Pay 500 GP for another event, or decline.");
    spend(state, 500, "Extraordinary opportunity", command);
    const next = Number(detail.nextRoll);
    if (!Number.isInteger(next) || next < 1 || next > 100) throw new RuleError("bad_roll", "Enter the new d100. If it is 59–63, roll again and enter the later result.");
    let mapped = eventFromRoll(next);
    if (mapped.id === "opportunity") throw new RuleError("bad_roll", "That result is the opportunity again. Roll once more and enter the new result.");
    event.type = mapped.id;
    event.detail = { paid: 500, replacedRoll: next };
    return resolveEventBody(state, { ...command, detail: detail.follow || {} }, unit, event);
  }
  if (event.type === "visitors") {
    const die = Number(detail.die);
    if (!Number.isInteger(die) || die < 1 || die > 6) throw new RuleError("bad_roll", "Enter 1d6 for the visitors' payment.");
    receive(state, die * 100, "Friendly visitors", command);
    event.detail = { gp: die * 100 };
    return { type: event.type, gp: die * 100 };
  }
  if (event.type === "guest") {
    const kind = Number(detail.kind);
    if (![1, 2, 3, 4].includes(kind)) throw new RuleError("event_choice", "Choose the guest result from 1 to 4.");
    event.detail = { kind };
    if (kind === 2) {
      const die = Number(detail.die);
      if (!Number.isInteger(die) || die < 1 || die > 6) throw new RuleError("bad_roll", "Enter 1d6 for the gift.");
      event.detail.gp = die * 100;
      event.detail.dueInTurns = 1;
      return { type: event.type, kind, gpLater: die * 100, note: "The gift is due after 1 Bastion turn. Record it then; it is not cash today." };
    }
    if (kind === 3) {
      state.roster.push({
        id: nid(state, "npc"),
        name: String(detail.name || "Mercenary guest").slice(0, 80),
        category: "defender",
        summary: "Staying guest. Does not need a barrack bed.",
        role: "Guest defender",
        link: "",
        unitId: unit.id,
        facilityId: null,
        status: "active",
        housed: false,
        protectsOnce: false,
      });
      return { type: event.type, kind, defender: true };
    }
    if (kind === 4) {
      state.roster.push({
        id: nid(state, "npc"),
        name: String(detail.name || "Friendly monster").slice(0, 80),
        category: "guest",
        summary: "Will protect the bastion once, then leave.",
        role: "Guest",
        link: "",
        unitId: unit.id,
        facilityId: null,
        status: "active",
        housed: false,
        protectsOnce: true,
      });
      return { type: event.type, kind };
    }
    return { type: event.type, kind, note: "Renowned guest stays 1 Bastion turn. Record the letter yourself." };
  }
  if (event.type === "lost_hirelings") {
    const facility = facilityById(state, detail.facilityId);
    if (facility.unitId !== unit.id || facility.kind !== "special") throw new RuleError("missing_facility", "Choose one of this owner's special facilities.");
    for (const person of state.roster) {
      if (person.facilityId === facility.id && person.category === "hireling" && person.status === "active") person.status = "gone";
    }
    facility.status = "shutdown";
    facility.shutdownUntilTurnId = "next";
    event.detail = { facilityId: facility.id };
    return { type: event.type, facility: facility.name };
  }
  if (event.type === "magic") {
    const item = String(detail.item || "").trim();
    if (!item) throw new RuleError("manual_required", "Name the uncommon potion or scroll. The item tables are not in the bastion chapter.");
    event.detail = { item: item.slice(0, 120) };
    return { type: event.type, item };
  }
  if (event.type === "refugees") {
    const count = Number(detail.count);
    const die = Number(detail.die);
    if (!Number.isInteger(count) || count < 2 || count > 8) throw new RuleError("bad_roll", "Enter the 2d4 result, from 2 to 8.");
    if (!Number.isInteger(die) || die < 1 || die > 6) throw new RuleError("bad_roll", "Enter 1d6 for the refugees' payment.");
    if (detail.housed !== true && detail.housed !== false) throw new RuleError("manual_required", "Say whether a basic room can house them. There is no squares-per-person formula.");
    receive(state, die * 100, "Refugee payment", command);
    event.detail = { count, housed: detail.housed, gp: die * 100 };
    return { type: event.type, count, gp: die * 100, housed: detail.housed };
  }
  if (event.type === "aid") {
    const sent = Number(detail.sent);
    const rolls = detail.rolls || [];
    if (!Number.isInteger(sent) || sent < 1) throw new RuleError("bad_amount", "Send at least one defender, or do not take the request.");
    if (rolls.length !== sent || rolls.some((roll) => !Number.isInteger(Number(roll)) || roll < 1 || roll > 6)) {
      throw new RuleError("bad_roll", "Enter one d6 for each defender sent. Armory stock is not applied to this total.");
    }
    const total = rolls.reduce((sum, roll) => sum + Number(roll), 0);
    const rewardRoll = Number(detail.rewardRoll);
    if (!Number.isInteger(rewardRoll) || rewardRoll < 1 || rewardRoll > 6) throw new RuleError("bad_roll", "Enter the reward d6.");
    let gp = rewardRoll * 100;
    let casualty = null;
    if (total < 10) {
      gp = Math.floor(gp / 2);
      const person = state.roster.find((item) => item.id === detail.casualtyId && item.category === "defender" && item.status === "active");
      if (!person) throw new RuleError("missing_person", "Name the defender who is lost when the total is under 10.");
      person.status = "dead";
      casualty = person.name;
    }
    receive(state, gp, "Request for aid", command);
    event.detail = { sent, total, gp, casualty };
    return { type: event.type, total, gp, casualty };
  }
  if (event.type === "treasure") {
    const band = Number(detail.band);
    if (!Number.isInteger(band) || band < 1 || band > 100) throw new RuleError("bad_roll", "Enter the treasure d100.");
    const item = String(detail.item || "").trim();
    if (!item) throw new RuleError("manual_required", "The treasure tables are in another chapter. Enter the object you rolled there.");
    event.detail = { band, item: item.slice(0, 160), claimed: Boolean(detail.ownerPresent) };
    return { type: event.type, item, claimed: Boolean(detail.ownerPresent), note: detail.ownerPresent ? "Claimed now." : "Stored until the owner can claim it. Not converted to cash." };
  }
  throw new RuleError("event_choice", "That event still needs a choice.");
}

function resolveAttack(state, command, unit, event) {
  const detail = command.detail || {};
  let dice = 6;
  if (state.walls.enclosureComplete) dice -= 2;
  dice -= housedLieutenants(state, unit.id);
  let needsDmConfirm = false;
  if (dice < 0) {
    dice = 0;
    needsDmConfirm = true;
    if (!detail.confirmZeroDice) throw new RuleError("dm_confirm", "Reductions would drop the attack below zero dice. The DM should confirm zero before continuing.");
  }
  const stocked = state.facilities.some((item) => item.unitId === unit.id && item.catalogId === "armory" && item.stocked && item.status === "active");
  const sides = stocked ? 8 : 6;
  const rolls = detail.rolls || [];
  if (rolls.length !== dice || rolls.some((roll) => !Number.isInteger(Number(roll)) || roll < 1 || roll > sides)) {
    throw new RuleError("bad_roll", `Enter ${dice} dice with ${sides} sides. They stay saved with the event.`);
  }
  const monster = state.roster.find((person) => person.unitId === unit.id && person.protectsOnce && person.status === "active");
  let kills = rolls.filter((roll) => Number(roll) === 1).length;
  if (monster) {
    kills = 0;
    monster.status = "gone";
    monster.protectsOnce = false;
  }
  const defenders = state.roster.filter((person) => person.unitId === (detail.lossUnitId || unit.id) && person.category === "defender" && person.status === "active");
  const lost = [];
  for (let i = 0; i < kills && i < defenders.length; i += 1) {
    const person = detail.lossIds ? defenders.find((item) => item.id === detail.lossIds[i]) : defenders[i];
    if (!person) continue;
    person.status = "dead";
    lost.push(person.id);
  }
  if (stocked) {
    for (const facility of state.facilities) {
      if (facility.unitId === unit.id && facility.catalogId === "armory" && facility.stocked) facility.stocked = false;
    }
  }
  let shutdown = null;
  const remaining = state.roster.filter((person) => person.unitId === unit.id && person.category === "defender" && person.status === "active").length;
  if (remaining === 0) {
    const specials = activeSpecials(state, unit.id);
    if (specials.length) {
      const index = detail.shutdownIndex == null ? 0 : Number(detail.shutdownIndex);
      const facility = specials[index] || specials[0];
      facility.status = "shutdown";
      facility.shutdownUntilTurnId = "next";
      shutdown = facility.id;
    }
  }
  event.detail = { dice, sides, rolls, lost, shutdown, monster: monster?.name || null, needsDmConfirm };
  return { type: "attack", dice, sides, lost: lost.length, shutdown, armorySpent: stocked };
}

function dmOverride(state, command) {
  if (!String(command.reason || "").trim()) throw new RuleError("reason_required", "A DM override needs a written reason.");
  state.audit.push({
    id: nid(state, "aud"),
    revision: state.revision + 1,
    type: "dm_override",
    summary: String(command.summary || "DM override").slice(0, 200),
    reason: String(command.reason).slice(0, 400),
    actorRole: "dm",
    turn: state.clock.turn,
    actorEmail: "",
  });
  if (command.patch && command.patch.facilityId) {
    const facility = state.facilities.find((item) => item.id === command.patch.facilityId) || state.archive.find((item) => item.id === command.patch.facilityId);
    if (!facility) throw new RuleError("missing_facility", "That facility is not in the record.");
    if (command.patch.status) facility.status = command.patch.status;
  }
  state.revision += 1;
  return { state, result: { ok: true }, replay: false };
}

function confirmFall(state, command) {
  const unit = unitById(state, command.unitId);
  if (!String(command.reason || "").trim()) throw new RuleError("reason_required", "Say whether this is neglect, giving the bastion up, or ruin.");
  unit.fallen = true;
  for (const facility of state.facilities.filter((item) => item.unitId === unit.id)) {
    facility.status = "archived";
    state.archive.push(facility);
  }
  state.facilities = state.facilities.filter((item) => item.unitId !== unit.id);
  return finish(state, command, { fallen: true }, `Marked ${unit.name} as fallen. A new bastion is a separate step and is not created automatically.`);
}

function importAccept(state, command) {
  const item = command.item || {};
  const status = String(item.status || "");
  if (["turn", "finance", "date", "goods", "loan", "defender", "defenders"].includes(item.kind)) {
    throw new RuleError("import_blocked", "Turns, dates, loans, goods, and defenders from a review file are not applied. Enter those yourself.");
  }
  if (status.toLowerCase().includes("pending") && item.kind !== "facility" && item.kind !== "roster") {
    throw new RuleError("import_blocked", "This note is still awaiting a decision. It was not written into the record.");
  }
  if (item.kind === "facility") {
    if (item.facilityKind === "basic") {
      return addBasic(state, {
        ...command,
        type: "add_basic",
        unitId: item.unitId || state.units[0].id,
        roomId: item.roomId,
        space: item.space,
        inherited: true,
      });
    }
    return addSpecialCommand(state, {
      ...command,
      type: "add_special",
      unitId: item.unitId || state.units[0].id,
      catalogId: item.catalogId,
      acquired: "inherited",
    });
  }
  if (item.kind === "roster") {
    return rosterSave(state, { ...command, type: "roster_save", person: item.person });
  }
  throw new RuleError("import_blocked", "That review item cannot be applied automatically.");
}

export function facilityClosureFacts(state, facilityId) {
  const people = activeAt(state, facilityId);
  const work = facilityWork(state, facilityId);
  return {
    defenders: people.filter((person) => person.category === "defender").length,
    lieutenants: people.filter((person) => person.category === "lieutenant").length,
    hirelings: people.filter((person) => person.category === "hireling").length,
    orders: work.orders.length,
    tasks: work.tasks.length,
    projects: work.projects.length,
    events: work.events.length,
  };
}

export function previewSpecials(unit) {
  return SPECIALS.map((spec) => {
    const reasons = [];
    if (unit.level < spec.level) reasons.push(`Level ${spec.level}`);
    if (spec.prereq && !unit.capabilities.includes(spec.prereq)) reasons.push("Missing prerequisite");
    if (spec.unique && false) reasons.push("Already kept");
    return { ...spec, locked: reasons.length > 0, reasons };
  });
}

export function listEvents() {
  return EVENTS;
}

export { specialCap, saleProceeds, buyLimitGp, SPACE_SQUARES };
