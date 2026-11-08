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
  go({ type: "set_clock", ordinal: 12, label: "A spring day on the practice calendar" });
  go({ type: "set_finance", cashGp: 1300 });
  go({ type: "add_basic", unitId: "unit-party", roomId: "bedroom", space: "cramped", starter: true });
  go({ type: "add_basic", unitId: "unit-party", roomId: "kitchen", space: "roomy", starter: true });
  go({ type: "add_special", unitId: "unit-party", catalogId: "barrack" });
  go({ type: "add_special", unitId: "unit-party", catalogId: "storehouse" });
  const barrack = state.facilities.find((item) => item.catalogId === "barrack");
  go({
    type: "commit_turn",
    unitId: "unit-party",
    presence: "present",
    mode: "orders",
    orders: [{ facilityId: barrack.id, suborder: "recruit", count: 2 }],
  });
  const defenders = state.roster.filter((item) => item.category === "defender");
  go({
    type: "roster_save",
    person: { ...defenders[0], name: "Pell Ash", summary: "Watches the yard gate." },
  });
  go({
    type: "roster_save",
    person: { ...defenders[1], name: "Sarn Wick", summary: "Mends spears and tells bad jokes." },
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
