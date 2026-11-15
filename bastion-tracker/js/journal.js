import { dateForTurn } from "./calendar.js";

function facilityName(state, id) {
  return state.facilities?.find((item) => item.id === id)?.name || "Facility";
}

function taskFor(state, order) {
  return (state.tasks || []).find((task) => task.id === order.taskId) || null;
}

function goodsName(state, lotId, fallback) {
  const lot = (state.goods || []).find((item) => item.id === lotId);
  const name = lot?.name?.trim();
  return name || fallback || "goods";
}

export function orderLedgerLine(state, order) {
  const place = facilityName(state, order.facilityId);
  const task = taskFor(state, order);
  if (order.suborder === "recruit" || order.auto === "barrack_recruit") {
    const count = order.result?.recruited;
    return Number.isInteger(count) ? `${place}: recruit ${count}.` : `${place}: recruit.`;
  }
  if (order.suborder === "sell" || order.auto === "storehouse_sell" || order.auto === "stable_sell") {
    const amount = task?.standardGp ?? order.preview?.standardGp;
    const name = goodsName(state, task?.lotId || order.lotId, task?.goodsName);
    return Number.isInteger(amount) ? `${place}: sell ${amount} gp of ${name}.` : `${place}: sell ${name}.`;
  }
  if (order.suborder === "buy" || order.auto === "storehouse_buy" || order.auto === "stable_buy") {
    const amount = task?.standardGp;
    const name = task?.goodsName?.trim() || "goods";
    return Number.isInteger(amount) ? `${place}: buy ${amount} gp of ${name}.` : `${place}: buy ${name}.`;
  }
  if (order.label) return `${place}: ${order.label}.`;
  return `${place}: an order.`;
}

export function journalDateLabel(state, turn) {
  if (turn == null) return "date not set";
  const shown = dateForTurn(state.clock?.anchor, turn, state.clock || {});
  return shown?.text || "date not set";
}

function recordedDate(state, records) {
  const stored = records.map((record) => record.date).find((value) => value);
  if (stored) return stored;
  const turn = records[0]?.turn;
  return journalDateLabel(state, turn);
}

export function turnReports(state) {
  const groups = new Map();
  for (const record of state.turns || []) {
    if (record.turn == null || !Number.isInteger(Number(record.turn))) continue;
    const turn = Number(record.turn);
    if (!groups.has(turn)) groups.set(turn, []);
    groups.get(turn).push(record);
  }
  return [...groups.keys()].sort((left, right) => left - right).map((turn) => {
    const records = groups.get(turn);
    const lines = [];
    const notes = [];
    for (const record of records) {
      if (record.notes) notes.push(record.notes);
      if (record.mode === "maintain") lines.push("Maintain.");
      else if (record.mode === "no_orders") lines.push("No orders.");
      for (const orderId of record.orderIds || []) {
        const order = (state.orders || []).find((item) => item.id === orderId);
        if (order) lines.push(orderLedgerLine(state, order));
      }
    }
    return {
      turn,
      date: recordedDate(state, records),
      lines,
      notes: notes.join("\n"),
    };
  });
}
