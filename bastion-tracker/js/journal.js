import { dateForTurn } from "./calendar.js";
import { EVENTS } from "./catalog.js";

const CORRECTIONS = new Set([
  "roster_save",
  "edit_person",
  "replace_person",
  "remove_person",
  "assign_person",
  "record_defenders",
  "edit_facility",
  "remove_facility",
  "replace_basic",
  "correct_special",
  "reserve_goods",
  "release_goods",
  "record_goods",
  "record_order",
  "set_order_start",
]);

function facilityName(state, id) {
  return state.facilities?.find((item) => item.id === id)?.name || "a facility";
}

function taskFor(state, order) {
  return (state.tasks || []).find((task) => task.id === order.taskId) || null;
}

function lotName(state, lotId) {
  const lot = (state.goods || []).find((item) => item.id === lotId);
  const name = lot?.name?.trim();
  return name || "goods";
}

function orderClause(state, order) {
  const place = facilityName(state, order.facilityId);
  const task = taskFor(state, order);
  if (order.suborder === "recruit" || order.auto === "barrack_recruit") {
    const count = order.result?.recruited;
    if (Number.isInteger(count) && count > 0) {
      return `the ${place} took on ${count} new defender${count === 1 ? "" : "s"}`;
    }
    return `the ${place} was ordered to recruit`;
  }
  if (order.suborder === "sell" || order.auto === "storehouse_sell") {
    const amount = task?.standardGp;
    const name = lotName(state, task?.lotId || order.lotId);
    if (Number.isInteger(amount)) return `the ${place} was set to sell ${amount} GP of ${name}`;
    return `the ${place} was set to sell ${name}`;
  }
  if (order.suborder === "buy" || order.auto === "storehouse_buy") {
    const amount = task?.standardGp;
    const name = task?.goodsName?.trim() || "goods";
    if (Number.isInteger(amount)) return `the ${place} was ordered to buy ${amount} GP of ${name}`;
    return `the ${place} was ordered to buy ${name}`;
  }
  if (order.result?.cost != null) return `the ${place} was stocked at a cost of ${order.result.cost} GP`;
  if (order.label) return `the ${place} was given the order ${order.label}`;
  return `the ${place} was given an order`;
}

function outcomeClause(state, task) {
  if (task.auto === "storehouse_sell" && task.settled) {
    return `the sale of ${lotName(state, task.lotId)} paid ${task.proceeds} GP`;
  }
  if (task.auto === "storehouse_buy" && task.settled) {
    const name = task.goodsName?.trim() || "goods";
    return `${name} arrived, listed at ${task.standardGp} GP`;
  }
  if (task.status === "ready" || task.status === "resolved") {
    const label = task.note?.trim() || task.auto || "an order";
    return `${label} came due`;
  }
  return "";
}

function eventClause(state, event) {
  if (!event || event.status === "pending" || !event.type) return "Maintain was kept, and the event is still open";
  const named = EVENTS.find((item) => item.id === event.type)?.name;
  return named ? `Maintain brought ${named}` : "Maintain was kept";
}

export function journalDateLabel(state, turn) {
  if (turn == null) return "date not set";
  const shown = dateForTurn(state.clock?.anchor, turn, state.clock || {});
  return shown?.text || "date not set";
}

function presenceClause(record) {
  if (record.presence === "present") return "the owner was here";
  if (record.presence === "absent_with_contact") {
    const how = String(record.contact || "").trim();
    return how ? `the owner was away and sent word by ${how}` : "the owner was away but able to send word";
  }
  if (record.presence === "absent") return "the owner was away, and no message arrived";
  return "";
}

function correctionLines(state, turn) {
  return (state.audit || [])
    .filter((entry) => entry.turn === turn && CORRECTIONS.has(entry.type) && entry.summary)
    .map((entry) => entry.summary.trim())
    .filter(Boolean);
}

function footnoteFor(state, turn, usedInBrief) {
  const notes = correctionLines(state, turn);
  if (!notes.length || usedInBrief) return "";
  const shown = notes.slice(0, 2).join(" ");
  const more = notes.length > 2 ? ` ${notes.length - 2} more correction${notes.length - 2 === 1 ? "" : "s"} kept in the backup.` : "";
  return `Also noted on the record: ${shown}${more}`;
}

function briefFor(state, turn) {
  const clauses = [];
  const noteLines = [];
  for (const record of state.turns || []) {
    if (record.turn !== turn) continue;
    const presence = presenceClause(record);
    if (presence) clauses.push(presence);
    if (record.notes) noteLines.push(record.notes);
    if (record.mode === "maintain") {
      const event = (state.events || []).find((item) => item.id === record.eventId);
      clauses.push(eventClause(state, event));
    } else if (record.mode === "no_orders") {
      clauses.push("no orders were issued");
    }
    for (const orderId of record.orderIds || []) {
      const order = (state.orders || []).find((item) => item.id === orderId);
      if (order) clauses.push(orderClause(state, order));
    }
  }
  for (const task of state.tasks || []) {
    if (task.dueTurn !== turn) continue;
    const line = outcomeClause(state, task);
    if (line) clauses.push(line);
  }
  const corrections = correctionLines(state, turn);
  const onlyCorrections = !clauses.length && corrections.length;
  if (onlyCorrections) clauses.push(`the record was set in order. ${corrections.join(" ")}`);
  if (!clauses.length) return { text: "In the turn just past, my lord, nothing new was entered on the record.", usedCorrections: false, notes: noteLines.join("\n") };
  return { text: `In the turn just past, my lord, ${clauses.join("; ")}.`, usedCorrections: onlyCorrections, notes: noteLines.join("\n") };
}

export function turnReports(state) {
  const numbers = new Set();
  for (const record of state.turns || []) {
    if (record.turn != null) numbers.add(record.turn);
  }
  for (const task of state.tasks || []) {
    if (task.dueTurn != null && (task.settled || task.status === "ready" || task.status === "resolved")) numbers.add(task.dueTurn);
  }
  for (const entry of state.audit || []) {
    if (entry.turn != null && CORRECTIONS.has(entry.type)) numbers.add(entry.turn);
  }
  return [...numbers].sort((left, right) => left - right).map((turn) => {
    const brief = briefFor(state, turn);
    return {
      turn,
      date: journalDateLabel(state, turn),
      brief: brief.text,
      notes: brief.notes,
      footnote: footnoteFor(state, turn, brief.usedCorrections),
    };
  });
}
