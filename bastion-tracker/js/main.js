import { BASTION_CONFIG } from "../config.js";
import { SPECIALS, specialById } from "./catalog.js";
import { practiceState } from "./demo.js";
import { apply, RuleError } from "./rules.js";
import { acceptInvite, applyCommand, configured, createEstate, listEstates, serviceRoleRejected, signIn } from "./remote.js";
import { render, renderReview } from "./render.js";

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
  formError: null,
  confirmGoodsId: "",
};

function paint() {
  const focusId = document.activeElement?.id;
  const start = document.activeElement?.selectionStart;
  app.innerHTML = render(model);
  if (focusId) {
    const next = document.getElementById(focusId);
    if (next) {
      next.focus();
      if (typeof start === "number" && next.setSelectionRange) next.setSelectionRange(start, start);
    }
  }
}

function fail(error) {
  model.error = error instanceof RuleError ? error.message : (error.message || "That was not saved.");
  model.notice = model.mode === "sandbox" ? "The practice session was not changed." : "The shared record was not changed.";
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
  model.notice = out.replay ? "That action was already saved in this practice session." : "Updated the practice session only.";
  paint();
}

async function remoteApply(command) {
  const key = command.idempotencyKey || (crypto.randomUUID ? crypto.randomUUID() : `key-${Date.now()}`);
  try {
    const result = await applyCommand(BASTION_CONFIG, model.token, model.estateId, model.state.revision, key, command);
    if (result?.document) model.state = result.document;
    model.error = "";
    model.formError = null;
    model.notice = result?.replay ? "The shared record already had this action." : "Saved to the shared record.";
    paint();
  } catch (error) {
    const code = String(error.message || "");
    if (code.includes("unsupported_on_server")) {
      fail(new Error("The shared database does not take that order yet. It was not saved here either. Use the practice sandbox to try it, or record a DM note."));
      return;
    }
    if (code.includes("revision_conflict") || error.status === 409) {
      fail(new Error("Someone else saved first. Reload the shared record before trying again."));
      return;
    }
    fail(error);
  }
}

function commit(command) {
  if (model.mode === "sandbox") localApply(command);
  else if (model.mode === "remote") return remoteApply(command);
  else fail(new Error("Not connected. Setup is required."));
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
    model.error = "";
    model.notice = "Practice data only.";
    paint();
  }
  if (action === "leave") {
    model.mode = "gate";
    model.state = null;
    model.token = "";
    model.notice = "Left the record. Practice data was dropped.";
    paint();
  }
  if (action === "nav") {
    model.view = button.dataset.view;
    model.error = "";
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
      await commit({ type: "remove_goods", lotId: button.dataset.id });
      if (!model.error) model.confirmGoodsId = "";
    } catch (error) {
      fail(error);
    }
  }
  if (action === "accept-review") {
    const item = model.review[Number(button.dataset.index)];
    if (!item || item.blocked) return;
    commit({ type: "import_accept", item: item.command });
  }
});

app.addEventListener("submit", async (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement)) return;
  event.preventDefault();
  const data = formData(form);
  try {
    if (form.id === "signin") return signInFrom(data);
    if (form.id === "accept") return acceptFrom(data);
    if (form.id === "add-special") {
      commit({ type: "add_special", unitId: model.state.units[0].id, catalogId: data.catalogId });
    } else if (form.id === "add-basic") {
      commit({ type: "add_basic", unitId: model.state.units[0].id, roomId: data.roomId, space: data.space, inherited: data.inherited === "on" });
    } else if (form.id === "person") {
      commit({ type: "roster_save", person: { name: data.name, category: data.category, role: data.role, summary: data.summary, link: data.link, unitId: model.state.units[0].id } });
    } else if (form.id === "turn") {
      commit(turnCommand(data));
    } else if (form.id === "event") {
      const rolls = String(data.dice || "").split(/[^\d]+/).filter(Boolean).map(Number);
      commit({ type: "resolve_event", eventId: data["event-id"] || document.getElementById("event-id")?.value, roll: data.roll ? Number(data.roll) : null, eventIdChoice: data.choice || null, detail: { note: data.note, rolls } });
    } else if (form.id === "finance") {
      commit({ type: "set_finance", cashGp: data.cashGp === "" ? null : Number(data.cashGp) });
    } else if (form.id === "goods") {
      const amount = Number(data.standardGp);
      if (!String(data.name || "").trim()) {
        rejectGoods("goods", "goods-name", "Goods need a name.");
      } else if (!positiveGoods(amount)) {
        rejectGoods("goods", "goods-gp", "Goods need a list price above zero, in whole GP.");
      } else {
        model.formError = null;
        commit({ type: "record_goods", name: data.name, standardGp: amount, unitId: model.state.units[0].id });
      }
    } else if (form.id === "settings") {
      const capabilities = [...form.querySelectorAll("input[name=cap]:checked")].map((input) => input.value);
      commit({
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
      commit({
        type: "record_defenders",
        facilityId: data.facilityId,
        count: Number(data.count),
        names: String(data.names || "").split(/[\n,]/).map((name) => name.trim()).filter(Boolean),
      });
    } else if (form.id === "record-loan") {
      commit({
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
        commit({
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
      commit({
        type: "record_order",
        facilityId,
        suborder,
        startedTurn: data.startedTurn === "" ? null : Number(data.startedTurn),
        note: data.note,
      });
    } else if (form.id === "advance") {
      commit({ type: "advance_days", days: Number(data.days) });
    } else if (form.id === "split") {
      commit({ type: "split_unit", name: data.name, level: Number(data.level), acknowledgeNewCap: data.acknowledge === "on" });
    } else if (form.id === "review") {
      model.review = parseReview(data.review);
      const list = document.getElementById("review-list");
      if (list) list.innerHTML = renderReview(model.review);
      model.notice = "Read on this device only. Blocked items were not saved.";
      const status = document.getElementById("status");
      if (status) status.textContent = model.notice;
    }
  } catch (error) {
    fail(error);
  }
});

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

function parseReview(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw new RuleError("bad_review", "That text is not JSON.");
  }
  const items = [];
  const rooms = { bedroom: "bedroom", "dining room": "dining", parlor: "parlor", courtyard: "courtyard", kitchen: "kitchen", storage: "storage" };
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
        command = { kind: "facility", facilityKind: "basic", roomId: rooms[roomName], space: String(row.value?.space || "cramped").toLowerCase() };
        if (!command.roomId) continue;
      } else if (!blocked && /special/i.test(key)) {
        const name = String(row.value?.name || "").toLowerCase();
        command = { kind: "facility", catalogId: specials[name] };
        if (!command.catalogId) continue;
      } else if (!blocked && /household|roster/i.test(key)) {
        command = { kind: "roster", person: { name: row.value?.name || row.value?.role || "Unnamed", category: "household", role: row.value?.role || "", summary: row.value?.summary || "", unitId: "unit-party" } };
      }
      items.push({ title, section: row.section || key, status, blocked: blocked || !command, command });
    }
  }
  return items;
}

function labelOf(value) {
  if (!value) return "";
  if (typeof value === "string") return value;
  return value.name || value.type || value.role || "";
}

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
    model.view = "dashboard";
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
    model.notice = "Invitation accepted.";
    paint();
  } catch (error) {
    fail(error);
  }
}

paint();
