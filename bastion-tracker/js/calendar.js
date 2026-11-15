/** Calendar of Harptos. Turns stay the counter. A date is derived for display. */

export const MONTHS = [
  ["hammer", "Hammer"],
  ["alturiak", "Alturiak"],
  ["ches", "Ches"],
  ["tarsakh", "Tarsakh"],
  ["mirtul", "Mirtul"],
  ["kythorn", "Kythorn"],
  ["flamerule", "Flamerule"],
  ["eleasis", "Eleasis"],
  ["eleint", "Eleint"],
  ["marpenoth", "Marpenoth"],
  ["uktar", "Uktar"],
  ["nightal", "Nightal"],
];

export const FESTIVALS = [
  ["midwinter", "Midwinter"],
  ["greengrass", "Greengrass"],
  ["midsummer", "Midsummer"],
  ["shieldmeet", "Shieldmeet"],
  ["highharvestide", "Highharvestide"],
  ["feast_of_the_moon", "Feast of the Moon"],
];

const MONTH_IDS = new Set(MONTHS.map(([id]) => id));
const FESTIVAL_IDS = new Set(FESTIVALS.map(([id]) => id));
const ALIASES = { tarkesh: "tarsakh" };

export function normalizeName(value) {
  const key = String(value || "").trim().toLowerCase();
  return ALIASES[key] || key;
}

function segments(leap) {
  const list = [];
  for (const [id, name] of MONTHS) {
    list.push({ kind: "month", id, name, length: 30 });
    if (id === "hammer") list.push({ kind: "festival", id: "midwinter", name: "Midwinter", length: 1 });
    if (id === "tarsakh") list.push({ kind: "festival", id: "greengrass", name: "Greengrass", length: 1 });
    if (id === "flamerule") {
      list.push({ kind: "festival", id: "midsummer", name: "Midsummer", length: 1 });
      if (leap) list.push({ kind: "festival", id: "shieldmeet", name: "Shieldmeet", length: 1 });
    }
    if (id === "eleint") list.push({ kind: "festival", id: "highharvestide", name: "Highharvestide", length: 1 });
    if (id === "uktar") list.push({ kind: "festival", id: "feast_of_the_moon", name: "Feast of the Moon", length: 1 });
  }
  return list;
}

export function isLeapYear(year) {
  return year % 4 === 0;
}

export function yearLength(year) {
  return isLeapYear(year) ? 366 : 365;
}

function locate(date, leap) {
  let index = 0;
  for (const segment of segments(leap)) {
    if (segment.kind === "month" && date.month === segment.id) {
      if (!Number.isInteger(date.day) || date.day < 1 || date.day > 30) return null;
      return index + date.day;
    }
    if (segment.kind === "festival" && date.festival === segment.id) return index + 1;
    index += segment.length;
  }
  return null;
}

function fromIndex(index, leap, year) {
  let cursor = index;
  for (const segment of segments(leap)) {
    if (cursor <= segment.length) {
      if (segment.kind === "festival") {
        return { festival: segment.id, festivalName: segment.name, month: null, day: null, monthName: null, year };
      }
      return { festival: null, festivalName: null, month: segment.id, day: cursor, monthName: segment.name, year };
    }
    cursor -= segment.length;
  }
  return null;
}

function absolute(date) {
  let total = 0;
  for (let year = 1; year < date.year; year += 1) total += yearLength(year);
  const index = locate(date, isLeapYear(date.year));
  if (index == null) return null;
  return total + index;
}

function fromAbsolute(total) {
  let year = 1;
  let left = total;
  while (left > yearLength(year)) {
    left -= yearLength(year);
    year += 1;
    if (year > 100000) return null;
  }
  return fromIndex(left, isLeapYear(year), year);
}

function midsummerIndex(leap) {
  return locate({ festival: "midsummer" }, leap);
}

export function calendarOptions(clock = {}) {
  return {
    turnDays: Number(clock.turnDays) === 7 ? 7 : 10,
    skipFestivals: clock.skipFestivals !== false,
  };
}

function stepOneDay(date, direction) {
  const next = addCalendarDays(date, direction);
  if (!next) return null;
  return {
    festival: next.festival,
    month: next.month,
    day: next.day,
    year: next.year ?? null,
    festivalName: next.festivalName,
    monthName: next.monthName,
    shieldmeetUncertain: next.shieldmeetUncertain,
  };
}

export function addTurnDays(date, amount, skipFestivals) {
  if (!skipFestivals || amount === 0) return addCalendarDays(date, amount);
  if (!date || !Number.isInteger(amount)) return null;
  const direction = amount < 0 ? -1 : 1;
  let cursor = {
    festival: date.festival || null,
    month: date.month || null,
    day: date.day ?? null,
    year: date.year ?? null,
  };
  let uncertain = false;
  for (let left = Math.abs(amount); left > 0; left -= 1) {
    let next = stepOneDay(cursor, direction);
    if (!next) return null;
    uncertain = uncertain || next.shieldmeetUncertain;
    while (next.festival) {
      const hopped = stepOneDay(next, direction);
      if (!hopped) return null;
      uncertain = uncertain || hopped.shieldmeetUncertain;
      next = hopped;
    }
    cursor = next;
  }
  return { ...cursor, shieldmeetUncertain: uncertain };
}

export function addCalendarDays(date, amount) {
  if (!date || !Number.isInteger(amount)) return null;
  if (date.year != null) {
    const start = absolute(date);
    if (start == null) return null;
    const next = fromAbsolute(start + amount);
    if (!next) return null;
    return { ...next, shieldmeetUncertain: false };
  }
  const start = locate(date, false);
  if (start == null) return null;
  const length = 365;
  let shifted = start + amount;
  let wrapped = 0;
  while (shifted > length) {
    shifted -= length;
    wrapped += 1;
  }
  while (shifted < 1) {
    shifted += length;
    wrapped -= 1;
  }
  const next = fromIndex(shifted, false, null);
  const shield = midsummerIndex(false);
  const crossed = wrapped !== 0 || (amount > 0 && start <= shield && shifted > shield) || (amount < 0 && start > shield && shifted <= shield);
  return { ...next, shieldmeetUncertain: crossed };
}

export function normalizeAnchor(input) {
  const turn = Number(input?.turn);
  if (!Number.isInteger(turn) || turn < 1) return { error: "The anchor names a Bastion turn, starting at 1." };
  const yearRaw = input?.year;
  let year = null;
  if (yearRaw != null && yearRaw !== "") {
    year = Number(yearRaw);
    if (!Number.isInteger(year) || year < 1 || year > 100000) return { error: "The year is a whole number, or left blank." };
  }
  const festival = normalizeName(input?.festival);
  const month = normalizeName(input?.month);
  if (festival && FESTIVAL_IDS.has(festival)) {
    if (!year && festival === "shieldmeet") return { error: "Shieldmeet needs a year, because it falls only when that year has one." };
    return { anchor: { turn, festival, month: null, day: null, year } };
  }
  if (!MONTH_IDS.has(month)) return { error: "Choose a Harptos month or festival." };
  const day = Number(input?.day);
  if (!Number.isInteger(day) || day < 1 || day > 30) return { error: "A month date is a whole number from 1 to 30." };
  return { anchor: { turn, festival: null, month, day, year } };
}

export function formatCalendarDate(date) {
  if (!date) return "";
  const core = date.festival ? date.festivalName : `${date.day} ${date.monthName}`;
  return date.year == null ? core : `${core}, ${date.year} DR`;
}

export function dateForTurn(anchor, turn, clock = {}) {
  if (!anchor || turn == null || turn === "") return null;
  const current = Number(turn);
  const origin = Number(anchor.turn);
  if (!Number.isInteger(current) || !Number.isInteger(origin)) return null;
  const { turnDays, skipFestivals } = calendarOptions(clock);
  const described = anchor.festival
    ? { festival: anchor.festival, month: null, day: null, year: anchor.year ?? null }
    : { festival: null, month: anchor.month, day: anchor.day, year: anchor.year ?? null };
  const shifted = addTurnDays(described, turnDays * (current - origin), skipFestivals);
  if (!shifted) return null;
  return { ...shifted, text: formatCalendarDate(shifted) };
}
