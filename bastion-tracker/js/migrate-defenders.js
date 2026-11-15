/** Fold generic defender entries into a Barrack count. Named people stay. */

const GENERIC = /^Defender \d+$/i;

export function isGenericDefender(person) {
  const name = String(person?.name || "").trim();
  return name === "" || GENERIC.test(name);
}

export function migrateDefenderCounts(doc) {
  const next = structuredClone(doc);
  if (next.defenderMigration === "009") return next;
  const roster = next.roster || [];
  const kept = [];
  const genericByFacility = {};
  for (const person of roster) {
    const active = !person.status || person.status === "active";
    if (active && person.category === "defender" && person.facilityId && isGenericDefender(person)) {
      genericByFacility[person.facilityId] = (genericByFacility[person.facilityId] || 0) + 1;
    } else {
      kept.push(person);
    }
  }
  for (const facility of next.facilities || []) {
    if (facility.catalogId !== "barrack" || facility.status === "archived") continue;
    const named = roster.filter((person) => person.facilityId === facility.id && person.category === "defender" && (!person.status || person.status === "active") && !isGenericDefender(person)).length;
    facility.defenderCount = (genericByFacility[facility.id] || 0) + named;
  }
  next.roster = kept;
  next.clock = next.clock || {};
  if (next.clock.turnDays == null) next.clock.turnDays = 10;
  if (next.clock.skipFestivals == null) next.clock.skipFestivals = true;
  next.defenderMigration = "009";
  return next;
}
