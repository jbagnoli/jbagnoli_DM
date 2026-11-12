/** One-time document conversion. The live database runs the same rules in SQL. */

export function migrateTurns(doc) {
  const next = structuredClone(doc);
  if (next.turnsMigration === "007") return next;
  const clock = next.clock || {};
  const previous = Object.prototype.hasOwnProperty.call(clock, "ordinal") ? clock.ordinal : (clock.turn ?? null);
  clock.keptCounter = previous ?? null;
  clock.keptCadence = clock.cadenceDays ?? null;
  clock.turn = previous ?? null;
  clock.turnNeedsCheck = clock.turn !== 3;
  clock.anchor = clock.anchor || null;
  delete clock.ordinal;
  delete clock.cadenceDays;
  next.clock = clock;
  for (const order of next.orders || []) {
    if (Object.prototype.hasOwnProperty.call(order, "startedDay")) {
      if (order.startedDay != null && order.startedDay !== "") {
        order.previousStartNumber = order.startedDay;
        order.startedTurn = null;
        order.startNeedsCheck = true;
      }
      delete order.startedDay;
    } else if (order.startedTurn != null && order.startedTurn !== "" && order.startNeedsCheck == null) {
      order.previousStartNumber = order.startedTurn;
      order.startedTurn = null;
      order.startNeedsCheck = true;
    }
  }
  const flagTimer = (item) => {
    if (!item || item.dueOrdinal == null) return;
    item.previousDue = item.dueOrdinal;
    item.dueTurn = null;
    item.timerNeedsCheck = true;
    delete item.dueOrdinal;
    delete item.startOrdinal;
    delete item.days;
  };
  for (const task of next.tasks || []) flagTimer(task);
  for (const project of next.projects || []) flagTimer(project);
  for (const square of next.walls?.squares || []) flagTimer(square);
  for (const entry of [...(next.ledger || []), ...(next.audit || []), ...(next.turns || [])]) {
    if (entry && entry.turn == null && entry.day != null) entry.turn = entry.day;
    if (entry) delete entry.day;
    if (entry) delete entry.cadenceDays;
  }
  for (const event of next.events || []) {
    const detail = event?.detail;
    if (!detail || !Object.prototype.hasOwnProperty.call(detail, "dueInDays")) continue;
    const days = detail.dueInDays;
    if (typeof days === "number" && days % 7 === 0) detail.dueInTurns = days / 7;
    else {
      detail.previousDurationDays = days;
      detail.dueInTurns = null;
      detail.durationNeedsCheck = true;
    }
    delete detail.dueInDays;
  }
  next.turnsMigration = "007";
  return next;
}
