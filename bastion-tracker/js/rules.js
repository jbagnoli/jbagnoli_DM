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
]);

export function emptyEstate(options = {}) {
  return {
    revision: 1,
    seq: 0,
    practice: Boolean(options.practice),
    name: options.name || "Unnamed bastion",
    clock: {
      label: options.dateLabel || "",
      ordinal: options.dayOrdinal ?? null,
      cadenceDays: options.cadenceDays ?? 10,
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

function requireClock(state) {
  if (state.clock.ordinal == null) {
    throw new RuleError("calendar_unknown", "Set an in-game day before starting something that takes days. The date can stay blank until you know it.");
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
  state.ledger.push({ id: nid(state, "led"), gp: -gp, reason, day: state.clock.ordinal, key: command.idempotencyKey || null });
}

function receive(state, gp, reason, command) {
  requireCash(state);
  state.finance.cashGp += gp;
  state.ledger.push({ id: nid(state, "led"), gp, reason, day: state.clock.ordinal, key: command.idempotencyKey || null });
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
    day: state.clock.ordinal,
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

function dueDay(state, days) {
  requireClock(state);
  return state.clock.ordinal + days;
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
      return replaceSpecial(state, command);
    case "enlarge_special":
      return enlargeSpecial(state, command);
    case "add_basic":
      return addBasic(state, command);
    case "upgrade_basic":
      return upgradeBasic(state, command);
    case "add_wall_squares":
      return addWalls(state, command);
    case "mark_enclosure":
      return markEnclosure(state, command);
    case "advance_days":
      return advanceDays(state, command);
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
    default:
      throw new RuleError("unsupported", "That action is not available.");
  }
}

function setSettings(state, command) {
  if (command.name) state.name = String(command.name).slice(0, 80);
  if (command.cadenceDays != null) {
    const days = Number(command.cadenceDays);
    if (!Number.isInteger(days) || days < 1 || days > 365) {
      throw new RuleError("bad_cadence", "Cadence is a whole number of in-game days, at least 1.");
    }
    state.clock.cadenceDays = days;
  }
  if (command.unitName || command.owner) {
    const unit = unitById(state, command.unitId || state.units[0].id);
    if (command.unitName) unit.name = String(command.unitName).slice(0, 80);
    if (command.owner) unit.owner = String(command.owner).slice(0, 120);
  }
  return finish(state, command, { cadenceDays: state.clock.cadenceDays }, "Updated estate settings.");
}

function setClock(state, command) {
  if (command.label != null) state.clock.label = String(command.label).slice(0, 120);
  if (command.ordinal === null) {
    state.clock.ordinal = null;
  } else if (command.ordinal != null) {
    const ordinal = Number(command.ordinal);
    if (!Number.isInteger(ordinal) || ordinal < 0) throw new RuleError("bad_day", "The day count has to be a whole number, or stay unknown.");
    state.clock.ordinal = ordinal;
  }
  return finish(state, command, { clock: state.clock }, "Updated the in-game clock.");
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
  state.ledger.push({ id: nid(state, "led"), gp: 0, reason: `Opening cash set to ${cash} GP`, day: state.clock.ordinal, key: command.idempotencyKey || null });
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
  if (command.cadenceDays != null && command.cadenceDays !== "") {
    const days = Number(command.cadenceDays);
    if (!Number.isInteger(days) || days < 1 || days > 365) {
      throw new RuleError("bad_cadence", "Cadence is a whole number of in-game days, at least 1.");
    }
    state.clock.cadenceDays = days;
  }
  const unit = unitById(state, command.unitId || state.units[0].id);
  if (command.unitName) unit.name = String(command.unitName).slice(0, 80);
  if (command.owner) unit.owner = String(command.owner).slice(0, 120);
  if (command.label != null) state.clock.label = String(command.label).slice(0, 120);
  if (command.ordinal === null || command.ordinal === "") {
    state.clock.ordinal = null;
  } else if (command.ordinal != null) {
    const ordinal = Number(command.ordinal);
    if (!Number.isInteger(ordinal) || ordinal < 0) throw new RuleError("bad_day", "The day count has to be a whole number, or stay unknown.");
    state.clock.ordinal = ordinal;
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
    { cadenceDays: state.clock.cadenceDays, level: unit.level, bank: unit.replacementBank },
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

function replaceSpecial(state, command) {
  const unit = unitById(state, command.unitId);
  const current = facilityById(state, command.facilityId);
  if (current.unitId !== unit.id) throw new RuleError("wrong_unit", "That facility belongs to another owner.");
  const spec = specialById(command.catalogId);
  if (!spec) throw new RuleError("unknown_facility", "That replacement is not in the bastion list.");
  if (unit.level < spec.level) throw new RuleError("level_gate", `${spec.name} requires level ${spec.level}.`);
  if (spec.prereq && !unit.capabilities.includes(spec.prereq)) throw new RuleError("prerequisite", `${spec.name} needs a capability this unit does not have.`);
  if (spec.unique && activeSpecials(state, unit.id).some((item) => item.catalogId === spec.id && item.id !== current.id)) {
    throw new RuleError("duplicate", `${spec.name} is already kept.`);
  }
  const override = command.dmOverride === true;
  if (override && roleOf(command) !== "dm") throw new RuleError("forbidden", "Only the DM can override a replacement.");
  if (override && !String(command.reason || "").trim()) throw new RuleError("reason_required", "Write why this replacement skips the normal limit.");
  if (!override && unit.replacementBank < 1) {
    throw new RuleError("no_replacement", "This level has no unused replacement. Gaining a level grants one. The current level by itself does not grant a stack of swaps.");
  }
  current.status = "archived";
  state.archive.push({ ...current, archivedReason: override ? `DM override: ${command.reason}` : "Replaced" });
  state.facilities = state.facilities.filter((item) => item.id !== current.id);
  if (!override) unit.replacementBank -= 1;
  const facility = {
    id: nid(state, "fac"),
    unitId: unit.id,
    kind: "special",
    catalogId: spec.id,
    name: spec.name,
    space: spec.space,
    hirelings: spec.hirelings,
    status: "active",
    acquired: "replacement",
    stocked: false,
    shutdownUntilTurnId: null,
    blockedOnTurnId: null,
    plots: 1,
    vastCapacityLarge: spec.id === "stable" ? 3 : null,
  };
  state.facilities.push(facility);
  return finish(state, command, { facilityId: facility.id, bank: unit.replacementBank }, `Replaced ${current.name} with ${spec.name}. The old one stays in the archive.`);
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
  return finish(state, command, { facilityId: facility.id }, `Enlarged ${facility.name} for ${spec.enlargeGp} GP. No extra days were added, because the chapter does not give a build time.`);
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
    days: build.days,
    startOrdinal: state.clock.ordinal,
    dueOrdinal: dueDay(state, build.days),
    status: "building",
  };
  requireClock(state);
  state.projects.push(project);
  return finish(state, command, { projectId: project.id, dueOrdinal: project.dueOrdinal, charged: build.gp }, `${room.name} costs ${build.gp} GP and is ready on day ${project.dueOrdinal}.`);
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
    days: step.days,
    startOrdinal: state.clock.ordinal,
    dueOrdinal: dueDay(state, step.days),
    status: "building",
  };
  facility.status = "building";
  state.projects.push(project);
  return finish(state, command, { projectId: project.id, dueOrdinal: project.dueOrdinal }, `${facility.name} enlarges on day ${project.dueOrdinal}.`);
}

function addWalls(state, command) {
  const count = Number(command.squares);
  if (!Number.isInteger(count) || count < 1 || count > 200) throw new RuleError("bad_amount", "Enter how many 5-foot squares to start.");
  const gp = WALL_SQUARE.gp * count;
  spend(state, gp, `Wall squares ×${count}`, command);
  const start = state.clock.ordinal;
  requireClock(state);
  const ids = [];
  for (let i = 0; i < count; i += 1) {
    const square = {
      id: nid(state, "wall"),
      status: "building",
      startOrdinal: start,
      dueOrdinal: start + WALL_SQUARE.days,
      gp: WALL_SQUARE.gp,
    };
    state.walls.squares.push(square);
    ids.push(square.id);
  }
  return finish(state, command, { ids, dueOrdinal: start + WALL_SQUARE.days, charged: gp }, `${count} wall squares finish on day ${start + WALL_SQUARE.days}. They run together, so the days are not stacked. The enclosure is still not marked complete.`);
}

function markEnclosure(state, command) {
  if (!String(command.reason || "").trim()) throw new RuleError("reason_required", "Say why the walls now form a complete enclosure. Square count does not decide it.");
  state.walls.enclosureComplete = Boolean(command.complete);
  return finish(state, command, { complete: state.walls.enclosureComplete }, state.walls.enclosureComplete ? "Marked the walls as a complete enclosure." : "Cleared the complete-enclosure mark.");
}

function advanceDays(state, command) {
  const days = Number(command.days);
  if (!Number.isInteger(days) || days < 1 || days > 3650) throw new RuleError("bad_day", "Advance a whole number of in-game days.");
  requireClock(state);
  state.clock.ordinal += days;
  if (command.label) state.clock.label = String(command.label).slice(0, 120);
  const settled = settleDue(state, command);
  return finish(state, command, { ordinal: state.clock.ordinal, settled }, `Advanced to day ${state.clock.ordinal}.`);
}

function settleDue(state, command) {
  const settled = [];
  for (const task of state.tasks) {
    if (task.status !== "open" || task.dueOrdinal == null || task.dueOrdinal > state.clock.ordinal) continue;
    if (task.auto === "storehouse_sell") settled.push(settleSale(state, task, command));
    else if (task.auto === "storehouse_buy") settled.push(settlePurchase(state, task, command));
    else {
      task.status = "ready";
      settled.push({ taskId: task.id, status: "ready" });
    }
  }
  for (const project of state.projects) {
    if (project.status === "building" && project.dueOrdinal <= state.clock.ordinal) completeProject(state, project);
  }
  for (const square of state.walls.squares) {
    if (square.status === "building" && square.dueOrdinal <= state.clock.ordinal) square.status = "built";
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

function rosterSave(state, command) {
  const person = command.person || {};
  const name = String(person.name || "").trim();
  if (!name) throw new RuleError("name_required", "A person needs a name.");
  const categories = new Set(["household", "hireling", "defender", "guest", "lieutenant", "creature"]);
  if (!categories.has(person.category)) throw new RuleError("bad_category", "Choose a roster category.");
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
  return finish(state, command, { personId: record.id }, `Saved ${record.name}.`);
}

function rosterRemove(state, command) {
  const person = state.roster.find((item) => item.id === command.personId);
  if (!person) throw new RuleError("missing_person", "That person is not on the roster.");
  person.status = "gone";
  return finish(state, command, { personId: person.id }, `Marked ${person.name} as gone. The name stays in the log.`);
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

function recordOrder(state, command) {
  const facility = facilityById(state, command.facilityId);
  if (facility.kind !== "special") throw new RuleError("not_special", "Basic rooms do not take orders.");
  const spec = specialById(facility.catalogId);
  const sub = spec?.subs.find((item) => item.id === command.suborder);
  if (!sub) throw new RuleError("bad_order", `${facility.name} cannot take that order.`);
  let started = null;
  if (command.startedTurn != null && command.startedTurn !== "") {
    started = Number(command.startedTurn);
    if (!Number.isInteger(started) || started < 0) throw new RuleError("bad_day", "The turn it started has to be a whole number, or left blank.");
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
  order.note = note;
  order.auto = null;
  order.recorded = true;
  facility.currentOrderId = order.id;
  return finish(state, command, { orderId: order.id }, `Marked ${facility.name} as already running ${sub.label}. No turn was resolved and no money moved.`);
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
    day: state.clock.ordinal,
    cadenceDays: state.clock.cadenceDays,
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
      dueOrdinal: dueDay(state, 7),
    });
    order.taskId = task.id;
    order.dueOrdinal = task.dueOrdinal;
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
      dueOrdinal: dueDay(state, 7),
    });
    order.taskId = task.id;
    order.dueOrdinal = task.dueOrdinal;
    order.preview = { standardGp, proceeds, days: 7 };
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
    const days = request.days != null ? Number(request.days) : sub.days;
    if (request.gp != null) {
      const gp = Number(request.gp);
      if (!Number.isInteger(gp) || gp < 0) throw new RuleError("bad_amount", "Enter a whole GP cost, or leave the order unpriced.");
      if (gp > 0) spend(state, gp, sub.label, command);
    }
    if (days == null) {
      order.status = "awaiting_dm";
      order.note = sub.note || "Enter a duration and any price from the rules outside this chapter.";
    } else {
      if (!Number.isInteger(days) || days < 0) throw new RuleError("bad_day", "Duration has to be a whole number of days from the facility, not from the turn length.");
      const task = openTask(state, {
        auto: "manual",
        unitId: unit.id,
        orderId: order.id,
        note: String(request.note || sub.note || "").slice(0, 240),
        dueOrdinal: days === 0 ? state.clock.ordinal : dueDay(state, days),
      });
      order.taskId = task.id;
      order.dueOrdinal = task.dueOrdinal;
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
      event.detail.dueInDays = 7;
      return { type: event.type, kind, gpLater: die * 100, note: "The gift is due after 7 days. Record it then; it is not cash today." };
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
    return { type: event.type, kind, note: "Renowned guest stays 7 days. Record the letter yourself." };
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
    day: state.clock.ordinal,
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
