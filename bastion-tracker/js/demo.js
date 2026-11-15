import { apply, emptyEstate } from "./rules.js";

/** Fictional practice data. This is not a campaign record. */
export function practiceState() {
  let state = emptyEstate({
    practice: true,
    name: "Hearthwatch Hold",
    level: 5,
    unitName: "Shared hall",
    owner: "The company, until someone claims a wing",
  });
  const go = (command) => {
    state = apply(state, command).state;
  };
  go({ type: "set_clock", turn: 2, label: "Practice session" });
  go({ type: "set_calendar_anchor", turn: 1, month: "tarsakh", day: 10, year: null });
  go({ type: "set_finance", cashGp: 1300 });
  go({ type: "set_loan", creditor: "North mill", amountGp: 300, note: "Practice debt" });
  go({ type: "add_basic", unitId: "unit-party", roomId: "bedroom", space: "cramped", starter: true });
  go({ type: "add_basic", unitId: "unit-party", roomId: "kitchen", space: "roomy", starter: true });
  go({ type: "add_special", unitId: "unit-party", catalogId: "barrack" });
  go({ type: "add_special", unitId: "unit-party", catalogId: "storehouse" });
  const barrack = state.facilities.find((item) => item.catalogId === "barrack");
  go({ type: "record_defenders", facilityId: barrack.id, count: 2 });
  go({
    type: "roster_save",
    person: { name: "Pell Ash", category: "hireling", role: "Yard watch", summary: "Watches the yard gate.", facilityId: barrack.id, unitId: "unit-party" },
  });
  go({
    type: "roster_save",
    person: { name: "Sarn Wick", category: "hireling", role: "Armorer", summary: "Mends spears and tells bad jokes.", facilityId: barrack.id, unitId: "unit-party" },
  });
  go({
    type: "roster_save",
    person: {
      name: "Bram Holt",
      category: "household",
      role: "Steward",
      summary: "Keeps the practice hall's keys.",
      unitId: "unit-party",
    },
  });
  go({ type: "record_goods", name: "Wool bolts", standardGp: 200, unitId: "unit-party" });
  go({ type: "add_basic", unitId: "unit-party", roomId: "parlor", space: "cramped" });
  return state;
}
