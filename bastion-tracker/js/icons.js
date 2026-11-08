/** Small original marks. Decorative only; the visible words carry the meaning. */

const SHAPES = {
  star: '<path d="M8 1.6 9.3 6.2 14 6.3 10.4 9.1 11.6 13.8 8 11.2 4.4 13.8 5.6 9.1 2 6.3 6.7 6.2Z"/>',
  crescent: '<path d="M10.2 2.1a6 6 0 1 0 0 11.8 4.7 4.7 0 1 1 0-11.8Z"/>',
  gem: '<path d="M8 1.7 13.2 8 8 14.3 2.8 8Z"/>',
  coin: '<circle cx="8" cy="8" r="5.2"/><path d="M8 5.1v5.8M5.4 8h5.2"/>',
  leaf: '<path d="M8 13.6S3.2 10 3.2 6.4C3.2 3.6 5.6 2.2 8 2.2s4.8 1.4 4.8 4.2c0 3.6-4.8 7.2-4.8 7.2Z"/><path d="M8 13.4V3.2"/>',
  crest: '<path d="M8 1.8 12.8 4v4.1c0 3.2-4.8 6.1-4.8 6.1S3.2 11.3 3.2 8.1V4Z"/>',
  card: '<rect x="3.2" y="2.2" width="9.6" height="11.6" rx="1.2"/><path d="M6 5.2h4M6 8h4"/>',
  keep: '<path d="M2.4 6.4 8 2.2l5.6 4.2V14H10V9.6H6V14H2.4Z"/>',
  pair: '<circle cx="5.4" cy="5.2" r="1.7"/><circle cx="10.6" cy="5.2" r="1.7"/><path d="M2.6 13.2c.4-2.2 1.8-3.3 2.8-3.3s2.4 1.1 2.8 3.3M8 13.2c.4-2.2 1.8-3.3 2.8-3.3s2.4 1.1 2.8 3.3"/>',
  cycle: '<path d="M12.6 4.4A5.4 5.4 0 1 0 13.4 8"/><path d="M12.6 4.4 10.2 3.6M12.6 4.4 12.4 6.9"/>',
  pips: '<circle cx="3.4" cy="8" r="1.1"/><circle cx="8" cy="8" r="1.1"/><circle cx="12.6" cy="8" r="1.1"/>',
  key: '<circle cx="5.4" cy="6.2" r="2.6"/><path d="M7.6 7.6 13.4 13.2M11 10.8l1.8 1.8"/>',
  thread: '<path d="M1.4 8c2.2-2.4 3.6-2.4 5.2 0s3 2.4 5.2 0 3-2.4 4.8 0"/>',
  seal: '<circle cx="8" cy="8" r="4.6"/><path d="M1.6 8h12.8"/>',
  door: '<path d="M4.2 13.6V3.2h7.6v10.4"/><path d="M9.4 8.2h.2"/>',
};

export function mark(name) {
  const shape = SHAPES[name] || SHAPES.star;
  return `<svg class="mark" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true" focusable="false">${shape}</svg>`;
}

const FAMILY = {
  Craft: "gem",
  Recruit: "crest",
  Trade: "coin",
  Harvest: "leaf",
  Research: "star",
  Empower: "crescent",
};

export function facilityMark(spec) {
  if (!spec) return mark("door");
  return mark(FAMILY[spec.family] || "card");
}

export const SECTION_MARK = {
  dashboard: "keep",
  rooms: "card",
  people: "pair",
  turn: "cycle",
  more: "pips",
  money: "coin",
  journal: "thread",
  settings: "key",
  import: "card",
  help: "star",
};
