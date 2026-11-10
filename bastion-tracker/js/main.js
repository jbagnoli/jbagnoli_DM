import { BASTION_CONFIG } from "../config.js";
import { specialById } from "./catalog.js";
import { practiceState } from "./demo.js";
import { apply, RuleError } from "./rules.js";
import { acceptInvite, applyCommand, configured, createEstate, listEstates, memberRole, serviceRoleRejected, signIn } from "./remote.js";
import { canAccept, markAgainstRecord, parseReview } from "./review.js";
import { render } from "./render.js";
import { beginSave, failSave, succeedSave } from "./save-feedback.js";

const app = document.querySelector("#app");
const model = {
  mode: "gate",
  view: "dashboard",
  state: null,
  error: "",
  notice: "",
  configured: configured(BASTION_CONFIG),
  serviceRole: serviceRoleRejected(BASTION_CONFIG),
  email: "",
  token: "",
  estateId: "",
  review: [],
  reviewText: "",
  formError: null,
  confirmGoodsId: "",
  confirmPersonId: "",
  editPersonId: "",
  replacePersonId: "",
  roomAction: null,
  projectId: "",
  role: "",
};

function paint() {
  const failure = model.save?.status === "failure";
  const focusId = failure ? "save-feedback" : document.activeElement?.id;
  const start = failure ? undefined : document.activeElement?.selectionStart;
  app.innerHTML = render(model);
  if (focusId) {
    const next = document.getElementById(focusId);
    if (next) {
      next.focus();
      if (typeof start === "number" && next.setSelectionRange) next.setSelectionRange(start, start);
    }
  }
}

function fail(error, source) {
  const message = error instanceof RuleError ? error.message : (error.message || "That was not saved.");
  model.error = message;
  model.notice = model.mode === "sandbox" ? "The practice session was not changed." : "The shared record was not changed.";
  model.save = failSave(message, source || model.save?.source || "");
  paint();
}

function rejectGoods(form, fieldId, message) {
  model.formError = { form, message };
  fail(new RuleError(fieldId.includes("name") ? "name_required" : "bad_amount", message));
  document.getElementById(fieldId)?.focus();
}

function positiveGoods(amount) {
  return Number.isInteger(amount) && amount >= 1;
}

function localApply(command) {
  const out = apply(model.state, { ...command, expectedRevision: model.state.revision, actorRole: "dm" });
  model.state = out.state;
  model.error = "";
  model.formError = null;
  return out;
}

async function remoteApply(command) {
  const key = command.idempotencyKey || (crypto.randomUUID ? crypto.randomUUID() : `key-${Date.now()}`);
  try {
    const result = await applyCommand(BASTION_CONFIG, model.token, model.estateId, model.state.revision, key, command);
    if (result?.document) model.state = result.document;
    model.error = "";
    model.formError = null;
    return result;
  } catch (error) {
    const code = String(error.message || "");
    if (code.includes("unsupported_on_server")) {
      throw new Error("The shared database does not take that order yet. It was not saved here either. Use the practice sandbox to try it, or record a DM note.");
    }
    if (code.includes("revision_conflict") || error.status === 409) {
      throw new Error("Someone else saved first. Reload the shared record before trying again.");
    }
    throw error;
  }
}

async function commit(command, source) {
  if (model.save?.status === "pending") return false;
  model.save = beginSave(source || "");
  model.error = "";
  model.formError = null;
  paint();
  await new Promise((resolve) => setTimeout(resolve, 0));
  try {
    let replay = false;
    if (model.mode === "sandbox") {
      replay = Boolean(localApply(command).replay);
    } else if (model.mode === "remote") {
      replay = Boolean((await remoteApply(command))?.replay);
    } else {
      throw new Error("Not connected. Setup is required.");
    }
    const summary = model.state?.audit?.at(-1)?.summary || "";
    model.save = succeedSave({ practice: model.mode === "sandbox", summary, replay });
    model.notice = "";
    model.error = "";
    paint();
    return true;
  } catch (error) {
    const message = error instanceof RuleError ? error.message : (error.message || "That was not saved.");
    model.error = message;
    model.notice = model.mode === "sandbox" ? "The practice session was not changed." : "The shared record was not changed.";
    model.formError = source ? { form: source, message } : model.formError;
    model.save = failSave(message, source || "");
    paint();
    return false;
  }
}

function formData(form) {
  return Object.fromEntries(new FormData(form).entries());
}

app.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const action = button.dataset.action;
  if (action === "sandbox") {
    model.mode = "sandbox";
    model.view = "dashboard";
    model.state = practiceState();
    model.role = "dm";
    model.error = "";
    model.save = null;
    model.notice = "Practice data only.";
    paint();
  }
  if (action === "leave") {
    model.mode = "gate";
    model.state = null;
    model.token = "";
    model.role = "";
    model.review = [];
    model.reviewText = "";
    model.save = null;
    model.roomAction = null;
    model.projectId = "";
    model.editPersonId = "";
    model.replacePersonId = "";
    model.notice = "Left the record. Practice data was dropped.";
    paint();
  }
  if (action === "nav") {
    model.view = button.dataset.view;
    model.error = "";
    model.save = null;
    model.roomAction = null;
    model.projectId = "";
    paint();
  }
  if (action === "export" && model.state) {
    const blob = new Blob([JSON.stringify({ format: "bastion-tracker-export-1", practice: model.mode === "sandbox", state: model.state }, null, 2)], { type: "application/json" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = model.mode === "sandbox" ? "practice-bastion.json" : "bastion-backup.json";
    link.click();
    URL.revokeObjectURL(link.href);
  }
  if (action === "confirm-remove-goods") {
    model.confirmGoodsId = button.dataset.id;
    model.error = "";
    paint();
  }
  if (action === "cancel-remove-goods") {
    model.confirmGoodsId = "";
    paint();
  }
  if (action === "remove-goods") {
    try {
      await commit({ type: "remove_goods", lotId: button.dataset.id }, `remove-goods:${button.dataset.id}`);
      if (!model.error) model.confirmGoodsId = "";
    } catch (error) {
      fail(error);
    }
  }
  if (action === "confirm-remove-person") {
    model.confirmPersonId = button.dataset.id;
    model.error = "";
    paint();
  }
  if (action === "cancel-remove-person") {
    model.confirmPersonId = "";
    paint();
  }
  if (action === "remove-person") {
    try {
      await commit({ type: "remove_person", personId: button.dataset.id }, `remove-person:${button.dataset.id}`);
      if (!model.error) {
        model.confirmPersonId = "";
        if (model.editPersonId === button.dataset.id) model.editPersonId = "";
      }
    } catch (error) {
      fail(error);
    }
  }
  if (action === "edit-person") {
    model.editPersonId = button.dataset.id;
    model.replacePersonId = "";
    model.confirmPersonId = "";
    model.error = "";
    paint();
    document.getElementById("person-name")?.focus();
  }
  if (action === "cancel-edit-person") {
    model.editPersonId = "";
    paint();
  }
  if (action === "replace-person") {
    model.replacePersonId = button.dataset.id;
    model.editPersonId = "";
    model.confirmPersonId = "";
    model.error = "";
    paint();
    document.getElementById("replace-person-name")?.focus();
  }
  if (action === "cancel-replace-person") {
    model.replacePersonId = "";
    paint();
  }
  if (action === "room-action") {
    model.roomAction = { id: button.dataset.id, mode: button.dataset.mode };
    model.projectId = "";
    model.error = "";
    paint();
    const focusId = { edit: "room-note", remove: "remove-reason", correct: "correct-catalog", level: "level-catalog", "replace-basic": "replace-room" }[button.dataset.mode];
    document.getElementById(focusId)?.focus();
  }
  if (action === "cancel-room-action") {
    model.roomAction = null;
    paint();
  }
  if (action === "cancel-project") {
    model.projectId = button.dataset.id;
    model.roomAction = null;
    model.error = "";
    paint();
    document.getElementById("project-reason")?.focus();
  }
  if (action === "cancel-project-close") {
    model.projectId = "";
    paint();
  }
  if (action === "accept-review") {
    await acceptReviewItem(Number(button.dataset.index));
  }
  if (action === "accept-remaining") {
    await acceptRemaining();
  }
});

async function acceptReviewItem(index) {
  const item = model.review?.[index];
  if (!canAccept(item)) return false;
  item.pending = true;
  try {
    await commit({ type: "import_accept", item: item.command }, `accept-review:${index}`);
  } catch (error) {
    item.pending = false;
    fail(error);
    return false;
  }
  if (model.error) {
    item.pending = false;
    return false;
  }
  item.accepted = true;
  item.pending = false;
  paint();
  return true;
}

async function acceptRemaining() {
  let added = 0;
  for (let index = 0; index < (model.review || []).length; index += 1) {
    if (!canAccept(model.review[index])) continue;
    const ok = await acceptReviewItem(index);
    if (!ok) {
      const error = model.error;
      model.notice = added ? `Added ${added}. The next item was not saved.` : "Nothing was added.";
      model.error = error;
      paint();
      return;
    }
    added += 1;
  }
  model.error = "";
  model.notice = added ? `Added ${added}.` : "Nothing left to add.";
  paint();
}

app.addEventListener("submit", async (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement)) return;
  event.preventDefault();
  const data = formData(form);
  const save = (command) => commit(command, form.id);
  try {
    if (form.id === "signin") return signInFrom(data);
    if (form.id === "accept") return acceptFrom(data);
    if (form.id === "add-special") {
      save({ type: "add_special", unitId: model.state.units[0].id, catalogId: data.catalogId });
    } else if (form.id === "add-basic") {
      save({ type: "add_basic", unitId: model.state.units[0].id, roomId: data.roomId, space: data.space, inherited: data.inherited === "on" });
    } else if (form.id === "person") {
      if (data.personId) {
        const person = model.state.roster.find((item) => item.id === data.personId);
        const nextFacility = Object.prototype.hasOwnProperty.call(data, "facilityId") ? (data.facilityId || null) : undefined;
        const assignmentChanged = nextFacility !== undefined && nextFacility !== (person?.facilityId || null);
        const ok = assignmentChanged
          ? await save({ type: "assign_person", personId: data.personId, name: data.name, category: data.category, role: data.role, summary: data.summary, link: data.link, facilityId: nextFacility, reason: data.reason })
          : await save({ type: "edit_person", personId: data.personId, name: data.name, category: data.category, role: data.role, summary: data.summary, link: data.link });
        if (ok) {
          model.editPersonId = "";
          paint();
        }
      } else {
        save({ type: "roster_save", person: { name: data.name, category: data.category, role: data.role, summary: data.summary, link: data.link, unitId: model.state.units[0].id } });
      }
    } else if (form.id === "replace-person") {
      const ok = await save({
        type: "replace_person",
        personId: data.personId,
        name: data.name,
        category: data.category,
        role: data.role,
        summary: data.summary,
        link: data.link,
        reason: data.reason,
      });
      if (ok) {
        model.replacePersonId = "";
        paint();
      }
    } else if (form.id === "edit-room") {
      const ok = await save({
        type: "edit_facility",
        facilityId: data.facilityId,
        roomId: data.roomId,
        space: data.space,
        note: data.note,
        reason: data.reason,
      });
      if (ok) {
        model.roomAction = null;
        paint();
      }
    } else if (form.id === "remove-room") {
      const ok = await save(closeRoomCommand("remove_facility", data));
      if (ok) {
        model.roomAction = null;
        paint();
      }
    } else if (form.id === "level-replace") {
      const ok = await save({
        ...closeRoomCommand("replace_special", data),
        unitId: model.state.units[0].id,
        catalogId: data.catalogId,
      });
      if (ok) {
        model.roomAction = null;
        paint();
      }
    } else if (form.id === "correct-special") {
      const ok = await save({
        ...closeRoomCommand("correct_special", data),
        unitId: model.state.units[0].id,
        catalogId: data.catalogId,
        reason: data.reason,
      });
      if (ok) {
        model.roomAction = null;
        paint();
      }
    } else if (form.id === "replace-basic") {
      const ok = await save({
        ...closeRoomCommand("replace_basic", data),
        roomId: data.roomId,
        space: data.space,
        reason: data.reason,
      });
      if (ok) {
        model.roomAction = null;
        paint();
      }
    } else if (form.id === "cancel-project") {
      const ok = await save({ type: "cancel_project", projectId: data.projectId, reason: data.reason });
      if (ok) {
        model.projectId = "";
        paint();
      }
    } else if (form.id === "turn") {
      save(turnCommand(data));
    } else if (form.id === "event") {
      const rolls = String(data.dice || "").split(/[^\d]+/).filter(Boolean).map(Number);
      save({ type: "resolve_event", eventId: data["event-id"] || document.getElementById("event-id")?.value, roll: data.roll ? Number(data.roll) : null, eventIdChoice: data.choice || null, detail: { note: data.note, rolls } });
    } else if (form.id === "finance") {
      save({ type: "set_finance", cashGp: data.cashGp === "" ? null : Number(data.cashGp) });
    } else if (form.id === "goods") {
      const amount = Number(data.standardGp);
      if (!String(data.name || "").trim()) {
        rejectGoods("goods", "goods-name", "Goods need a name.");
      } else if (!positiveGoods(amount)) {
        rejectGoods("goods", "goods-gp", "Goods need a list price above zero, in whole GP.");
      } else {
        model.formError = null;
        save({ type: "record_goods", name: data.name, standardGp: amount, unitId: model.state.units[0].id });
      }
    } else if (form.id === "settings") {
      const capabilities = [...form.querySelectorAll("input[name=cap]:checked")].map((input) => input.value);
      save({
        type: "save_settings",
        name: data.name,
        owner: data.owner,
        unitId: model.state.units[0].id,
        cadenceDays: Number(data.cadenceDays),
        label: data.label,
        ordinal: data.ordinal === "" ? null : Number(data.ordinal),
        level: Number(data.level),
        grantReplacements: data.grantReplacements === "on",
        capabilities,
      });
    } else if (form.id === "record-defenders") {
      save({
        type: "record_defenders",
        facilityId: data.facilityId,
        count: Number(data.count),
        names: String(data.names || "").split(/[\n,]/).map((name) => name.trim()).filter(Boolean),
      });
    } else if (form.id === "record-loan") {
      save({
        type: "set_loan",
        loanId: data.loanId || null,
        creditor: data.creditor,
        amountGp: data.amountGp === "" ? null : Number(data.amountGp),
        note: data.note,
        remove: data.remove === "on",
      });
    } else if (form.id === "record-goods") {
      const amount = Number(data.standardGp);
      const creating = !data.lotId;
      if (creating && !String(data.name || "").trim()) {
        rejectGoods("record-goods", "commit-name", "Goods need a name.");
      } else if (!positiveGoods(amount)) {
        rejectGoods("record-goods", "commit-gp", "Goods need a list price above zero, in whole GP.");
      } else {
        model.formError = null;
        save({
          type: "reserve_goods",
          lotId: data.lotId || null,
          name: data.name,
          standardGp: amount,
          note: data.note,
          unitId: model.state.units[0].id,
        });
      }
    } else if (form.id === "record-order") {
      const [facilityId, suborder] = String(data.orderKey || "").split("|");
      save({
        type: "record_order",
        facilityId,
        suborder,
        startedDay: data.startedDay === "" ? null : Number(data.startedDay),
        note: data.note,
      });
    } else if (form.id === "advance") {
      save({ type: "advance_days", days: Number(data.days) });
    } else if (form.id === "split") {
      save({ type: "split_unit", name: data.name, level: Number(data.level), acknowledgeNewCap: data.acknowledge === "on" });
    } else if (form.id === "review") {
      model.reviewText = data.review;
      model.review = markAgainstRecord(parseReview(data.review), model.state);
      model.error = "";
      model.notice = "Read on this device only. Blocked items were not saved.";
      paint();
    }
  } catch (error) {
    fail(error);
  }
});

async function readRole() {
  try {
    return await memberRole(BASTION_CONFIG, model.token, model.estateId);
  } catch {
    return "";
  }
}

function closeRoomCommand(type, data) {
  return {
    type,
    facilityId: data.facilityId,
    reason: data.reason,
    hirelings: data.hirelings || undefined,
    cancelWork: data.cancelWork === "on",
  };
}

function turnCommand(data) {
  const orders = [];
  for (const facility of model.state.facilities.filter((item) => item.kind === "special")) {
    const suborder = data[`order-${facility.id}`];
    if (!suborder) continue;
    const spec = specialById(facility.catalogId);
    const sub = spec?.subs.find((item) => item.id === suborder);
    const count = data[`count-${facility.id}`];
    orders.push({ facilityId: facility.id, suborder, count: count ? Number(count) : undefined, standardGp: sub?.auto === "storehouse_sell" ? undefined : undefined });
  }
  if (data.mode === "orders") {
    const sell = orders.find((order) => order.suborder === "sell");
    if (sell) {
      const lot = model.state.goods.find((item) => item.status === "on_hand" && (item.standardGp - (item.reservedGp || 0)) > 0);
      if (!lot) throw new RuleError("missing_goods", "Record goods before selling.");
      sell.lotId = lot.id;
      sell.standardGp = lot.standardGp - (lot.reservedGp || 0);
    }
  }
  return { type: "commit_turn", unitId: data.unitId, presence: data.presence, contact: data.contact, mode: data.mode, orders };
}

app.addEventListener("input", (event) => {
  if (event.target?.id === "review-text") model.reviewText = event.target.value;
});

async function signInFrom(data) {
  try {
    const session = await signIn(BASTION_CONFIG, data.email, data.password);
    model.token = session.accessToken;
    model.email = session.email;
    const estates = await listEstates(BASTION_CONFIG, model.token);
    if (!estates?.length) {
      model.estateId = await createEstate(BASTION_CONFIG, model.token, "Shared bastion");
      const again = await listEstates(BASTION_CONFIG, model.token);
      model.state = again[0].document;
      model.estateId = again[0].id;
    } else {
      model.estateId = estates[0].id;
      model.state = estates[0].document;
    }
    model.mode = "remote";
    model.role = await readRole();
    model.view = "dashboard";
    model.review = [];
    model.reviewText = "";
    model.error = "";
    model.notice = "Connected. This is the shared record.";
    paint();
  } catch (error) {
    fail(error);
  }
}

async function acceptFrom(data) {
  if (!model.token) {
    fail(new Error("Sign in before accepting an invitation."));
    return;
  }
  try {
    await acceptInvite(BASTION_CONFIG, model.token, data.invite);
    const estates = await listEstates(BASTION_CONFIG, model.token);
    model.estateId = estates[0].id;
    model.state = estates[0].document;
    model.mode = "remote";
    model.role = await readRole();
    model.review = [];
    model.reviewText = "";
    model.notice = "Invitation accepted.";
    paint();
  } catch (error) {
    fail(error);
  }
}

paint();
