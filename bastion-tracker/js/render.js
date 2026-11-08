import { BASIC_ROOMS, PREREQ_LABELS, SPECIALS, specialById, specialCap } from "./catalog.js";
import { SECTION_MARK, facilityMark, mark } from "./icons.js";

export function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  }[char]));
}

function money(state) {
  if (!state.finance.cashKnown) return "Unknown";
  return `${state.finance.cashGp} GP`;
}

function dayLine(state) {
  if (state.clock.ordinal == null) return "In-game day unknown";
  return state.clock.label ? `${state.clock.label} · day ${state.clock.ordinal}` : `Day ${state.clock.ordinal}`;
}

export function render(model) {
  if (model.mode === "gate") return renderGate(model);
  return `${shellStart(model)}${view(model)}${shellEnd(model)}`;
}

function coverArt(strip) {
  return `<figure class="hero${strip ? " hero-strip" : ""}">
    <picture>
      <source media="(max-width: 700px)" srcset="assets/deck-of-many-things-cover-phone.webp">
      <img src="assets/deck-of-many-things-cover.webp" width="1400" height="807" alt="A goblin dealing ornate cards onto a red cloth.">
    </picture>
  </figure>`;
}

function fanNotice() {
  return `<footer class="fan-notice">Bastion Tracker is unofficial Fan Content permitted under the Fan Content Policy. Not approved/endorsed by Wizards. Portions of the materials used are property of Wizards of the Coast. ©Wizards of the Coast LLC.</footer>`;
}

function renderGate(model) {
  return `<div class="topline"></div><main class="wrap gate">
    ${coverArt(false)}
    <p class="eyebrow">${mark("card")} Bastion tracker</p>
    <h1>Not connected</h1>
    <hr class="thread">
    <p class="muted">${model.configured
      ? "The shared database is set up. Sign in to open the group record. The practice sandbox is a different, fictional hall and is never called synced."
      : "Setup is required before this page can be the group's record. Nothing typed here is shared with the table until a database is configured and you save to it."}</p>
    <div class="banner warn"><strong>This is not the group record yet.</strong> ${model.configured
      ? "You are not signed in. Opening the practice sandbox does not read or write the shared estate."
      : "A practice sandbox stays in this browser tab. If a save fails later, it is not quietly kept on this device."}</div>
    <div class="banner"><strong>Browser warning.</strong> This github.io address may still be flagged by Chrome until Google finishes a review. Do not ask anyone to click through that warning.</div>
    ${model.serviceRole ? `<p class="status" data-tone="error" role="alert">A secret key was refused. Use the publishable key only.</p>` : ""}
    <div class="actions">
      <button class="${model.configured ? "quiet" : "primary"}" type="button" data-action="sandbox">Open practice sandbox</button>
      <a class="linkish" href="../index.html">DM projects</a>
    </div>
    <section class="panel stack" style="margin-top:16px">
      <h2>Shared sign-in</h2>
      <p class="muted">This is the bastion record's own sign-in. It is not a Microsoft, Google, or D&amp;D Beyond login.</p>
      ${model.configured ? `<form id="signin" class="stack">
        <label>Email <input id="email" name="email" type="email" autocomplete="username" required></label>
        <label>Password <input id="password" name="password" type="password" autocomplete="current-password" required></label>
        <button class="primary" type="submit">Sign in to the shared record</button>
      </form>
      <form id="accept" class="stack">
        <label>Invitation code <input id="invite" name="invite" autocomplete="one-time-code"></label>
        <button type="submit">Accept invitation</button>
      </form>` : `<p>Sign-in stays off until the owner adds the project URL and anon public key. See the setup notes in the repository.</p>`}
      <p id="status" class="status" role="status" data-tone="${model.error ? "error" : ""}">${esc(model.error || model.notice || "")}</p>
    </section>
    ${fanNotice()}
  </main>`;
}

function shellStart(model) {
  const practice = model.mode === "sandbox";
  const buttons = [
    ["dashboard", "Home"],
    ["rooms", "Rooms"],
    ["people", "People"],
    ["turn", "Turn"],
    ["more", "More"],
  ];
  return `<div class="topline"></div><div class="wrap">
    <div class="banner ${practice ? "warn" : "ok"}"><strong>${practice ? "Practice sandbox. Not the group record." : "Connected to the shared record."}</strong>
    ${practice ? "Closing this tab drops the practice data. It is fictional, it is not synced, and it is not saved for anyone else." : `Signed in as ${esc(model.email || "a member")}. Changes here are the shared group record. A failed save is shown as an error and is not stored on this device.`}</div>
    <div class="layout">
      <nav class="side stack" aria-label="Sections">${buttons.map(([id, label]) => navButton(id, label, model.view === id)).join("")}
        <button type="button" data-action="leave">Leave this record</button>
        <a href="../index.html">DM projects</a>
      </nav>
      <div>`;
}

function shellEnd(model) {
  const buttons = [["dashboard", "Home"], ["rooms", "Rooms"], ["people", "People"], ["turn", "Turn"], ["more", "More"]];
  return `</div></div>
    <p id="status" class="status" role="status" data-tone="${model.error ? "error" : ""}">${esc(model.error || model.notice || "")}</p>
    ${fanNotice()}
    <nav class="bottom-nav" aria-label="Mobile sections">${buttons.map(([id, label]) => navButton(id, label, model.view === id)).join("")}</nav>
  </div>`;
}

function navButton(id, label, current) {
  return `<button type="button" data-action="nav" data-view="${id}" ${current ? 'aria-current="page"' : ""}>${mark(SECTION_MARK[id] || "star")}<span>${label}</span></button>`;
}

function view(model) {
  if (model.view === "rooms") return renderRooms(model);
  if (model.view === "people") return renderPeople(model);
  if (model.view === "turn") return renderTurn(model);
  if (model.view === "money") return renderMoney(model);
  if (model.view === "journal") return renderJournal(model);
  if (model.view === "settings") return renderSettings(model);
  if (model.view === "import") return renderImport(model);
  if (model.view === "help") return renderHelp();
  if (model.view === "more") return renderMore();
  return renderDashboard(model);
}

function renderDashboard(model) {
  const state = model.state;
  const unit = state.units[0];
  const specials = state.facilities.filter((item) => item.kind === "special" && item.status !== "archived");
  const defenders = state.roster.filter((item) => item.category === "defender" && item.status === "active");
  const projects = [...state.projects.filter((item) => item.status === "building"), ...state.walls.squares.filter((item) => item.status === "building")];
  const pending = state.events.filter((item) => item.status === "pending");
  return `${coverArt(true)}<header><p class="eyebrow">${mark("keep")} Estate</p><h1>${esc(state.name)}</h1><hr class="thread"><p class="muted">${esc(dayLine(state))} · turn every ${state.clock.cadenceDays} in-game days</p></header>
    <div class="stats">
      <div class="stat"><span>Cash</span><strong>${esc(money(state))}</strong></div>
      <div class="stat"><span>Specials</span><strong>${specials.length}/${specialCap(unit.level)}</strong></div>
      <div class="stat"><span>Defenders</span><strong>${defenders.length}</strong></div>
      <div class="stat"><span>Open timers</span><strong>${projects.length + state.tasks.filter((item) => item.status === "open").length}</strong></div>
    </div>
    ${state.finance.cashKnown ? "" : `<p class="banner warn">Cash, loans, and goods on hand are unknown until you enter them. Spending and payouts stay blocked.</p>`}
    ${state.clock.ordinal == null ? `<p class="banner warn">The in-game day is unknown, so timers cannot finish.</p>` : ""}
    ${pending.length ? `<p class="banner warn">A Maintain event is waiting. Resolve it before the next turn.</p>` : ""}
    <div class="actions" style="margin-top:14px">
      <button class="primary" type="button" data-action="nav" data-view="turn">Record a turn</button>
      <button type="button" data-action="nav" data-view="rooms">Rooms</button>
      <button type="button" data-action="nav" data-view="people">People</button>
    </div>
    <section class="panel" style="margin-top:14px"><h2>What is due</h2>
      ${projects.length || state.tasks.some((item) => item.status === "open") ? `<ul>${projects.map((item) => `<li>${esc(item.name || "Wall square")} ready on day ${item.dueOrdinal}</li>`).join("")}${state.tasks.filter((item) => item.status === "open").map((item) => `<li>${esc(item.auto)} ready on day ${item.dueOrdinal}</li>`).join("")}</ul>` : `<p class="muted">No open timers.</p>`}
    </section>`;
}

function renderRooms(model) {
  const state = model.state;
  const unit = state.units[0];
  const options = SPECIALS.map((spec) => {
    const reasons = [];
    if (unit.level < spec.level) reasons.push(`needs level ${spec.level}`);
    if (spec.prereq && !unit.capabilities.includes(spec.prereq)) reasons.push("missing prerequisite");
    if (spec.unique && state.facilities.some((item) => item.catalogId === spec.id && item.status === "active")) reasons.push("already kept");
    const full = state.facilities.filter((item) => item.kind === "special" && item.unitId === unit.id && item.status === "active").length >= specialCap(unit.level);
    if (full) reasons.push("cap is full");
    return { spec, reasons };
  });
  return `<h2 class="with-mark">${mark("card")} Rooms</h2>
    <div class="list">${state.facilities.map((item) => `<article class="facility card"><h3 class="with-mark">${facilityMark(specialById(item.catalogId))}<span>${esc(item.name)}</span></h3><p class="muted">${esc(item.kind)} · ${esc(item.space)} · ${esc(item.status)} · ${esc(item.acquired || "")}</p><p>${esc(specialById(item.catalogId)?.hint || "Basic room. No orders.")}</p></article>`).join("") || `<p class="muted">No rooms yet.</p>`}</div>
    <section class="panel stack" style="margin-top:14px"><h3>Add a special facility</h3>
      <form id="add-special" class="stack">
        <label>Facility <select id="catalogId" name="catalogId">${options.map(({ spec, reasons }) => `<option value="${spec.id}" ${reasons.length ? "disabled" : ""}>${esc(spec.name)} · level ${spec.level}${reasons.length ? ` (${esc(reasons.join(", "))})` : ""}</option>`).join("")}</select></label>
        <button class="primary" type="submit">Add without a build cost</button>
        <p class="muted">The level cap is ${specialCap(unit.level)}. Replacements are granted only when the level goes up, not from the current level alone. Unused replacements: ${unit.replacementBank}.</p>
      </form>
    </section>
    <section class="panel stack" style="margin-top:14px"><h3>Basic room</h3>
      <form id="add-basic" class="stack">
        <label>Room <select id="roomId" name="roomId">${BASIC_ROOMS.map((room) => `<option value="${room.id}">${esc(room.name)}</option>`).join("")}</select></label>
        <label>Size <select id="space" name="space"><option value="cramped">Cramped · 500 GP · 20 days</option><option value="roomy">Roomy · 1,000 GP · 45 days</option><option value="vast">Vast · 3,000 GP · 125 days</option></select></label>
        <label><input id="inherited" name="inherited" type="checkbox"> Already part of the estate. Do not charge.</label>
        <button class="primary" type="submit">Add basic room</button>
      </form>
    </section>
    <section class="panel"><h3>Projects</h3>${state.projects.length ? `<ul>${state.projects.map((item) => `<li>${esc(item.name)} · ${esc(item.status)} · due day ${item.dueOrdinal ?? "unknown"} · ${item.gp || 0} GP</li>`).join("")}</ul>` : `<p class="muted">No building projects.</p>`}</section>`;
}

function renderPeople(model) {
  const people = model.state.roster;
  return `<h2 class="with-mark">${mark("pair")} People</h2><p class="muted">Names, a short public line, and an optional link. Full biographies stay in Notion. This page does not write to Notion.</p>
    <div class="list">${people.map((person) => `<article class="person card"><h3>${esc(person.name)}</h3><p><span class="tag">${esc(person.category)}</span> <span class="tag">${esc(person.status)}</span></p>${person.summary ? `<p>${esc(person.summary)}</p>` : `<p>${esc(person.role)}</p>`}${person.link ? `<p><a href="${esc(person.link)}">External note</a></p>` : ""}</article>`).join("") || `<p class="muted">No one is named yet.</p>`}</div>
    <form id="person" class="panel stack" style="margin-top:14px">
      <h3>Add someone</h3>
      <label>Name <input id="person-name" name="name" required maxlength="80"></label>
      <label>Category <select id="person-category" name="category"><option>household</option><option>hireling</option><option>defender</option><option>guest</option><option>lieutenant</option><option>creature</option></select></label>
      <label>Role <input id="person-role" name="role" maxlength="80"></label>
      <label>Short summary <input id="person-summary" name="summary" maxlength="160"></label>
      <label>Optional link <input id="person-link" name="link" type="url" placeholder="https://"></label>
      <button class="primary" type="submit">Save person</button>
    </form>`;
}

function renderTurn(model) {
  const state = model.state;
  const specials = state.facilities.filter((item) => item.kind === "special" && item.status !== "archived");
  const pending = state.events.find((item) => item.status === "pending");
  return `<h2 class="with-mark">${mark("cycle")} Turn</h2>
    <form id="turn" class="panel stack">
      <label>Owner unit <select id="turn-unit" name="unitId">${state.units.map((unit) => `<option value="${unit.id}">${esc(unit.name)} · level ${unit.level}</option>`).join("")}</select></label>
      <label>Where is the owner? <select id="presence" name="presence"><option value="present">Here</option><option value="absent_with_contact">Away, but can send word</option><option value="absent">Away, no message</option></select></label>
      <label>How they sent word, if they did <input id="contact" name="contact" maxlength="160"></label>
      <label>This turn <select id="mode" name="mode"><option value="orders">Issue orders</option><option value="maintain">Maintain the whole unit</option><option value="no_orders">No orders, owner unable</option></select></label>
      <p class="muted">Maintain cannot share the turn with other orders. Being away without a message forces Maintain. Task lengths stay the facility's own days, not the turn length.</p>
      ${specials.map((facility) => {
        const spec = specialById(facility.catalogId);
        return `<fieldset><legend>${facilityMark(spec)}<span>${esc(facility.name)}${facility.status === "shutdown" ? " (shut this turn)" : ""}</span></legend>
          <label>Order <select name="order-${facility.id}"><option value="">No order</option>${(spec?.subs || []).map((sub) => `<option value="${sub.id}">${esc(sub.label)}${sub.days == null ? "" : ` · ${sub.days} days`}</option>`).join("")}</select></label>
          <label>How many, if the order asks <input name="count-${facility.id}" inputmode="numeric" placeholder="1 to 4 for defenders"></label>
        </fieldset>`;
      }).join("")}
      <button class="primary" type="submit">Commit turn</button>
    </form>
    ${pending ? `<form id="event" class="panel stack" style="margin-top:14px"><h3>Maintain event</h3>
      <p class="muted">Enter the dice you rolled, or choose the event. Opening this page again will not roll for you.</p>
      <label>d100, optional <input id="event-roll" name="roll" inputmode="numeric"></label>
      <label>Or choose <select id="event-choice" name="choice"><option value="">Use the roll</option><option value="all_is_well">All is well</option><option value="attack">Attack</option><option value="visitors">Friendly visitors</option><option value="magic">Magical discovery</option></select></label>
      <label>Attack dice, if needed <input id="event-dice" name="dice" placeholder="Example: 1, 4, 2, 6"></label>
      <label>Note <input id="event-note" name="note" maxlength="240"></label>
      <input type="hidden" id="event-id" value="${esc(pending.id)}">
      <button class="primary" type="submit">Resolve event</button>
    </form>` : ""}
    <section class="panel" style="margin-top:14px"><h3>Recent turns</h3><ul>${state.turns.slice(-6).reverse().map((turn) => `<li>${esc(turn.mode)} · ${esc(turn.presence)} · day ${turn.day ?? "unknown"}</li>`).join("") || "<li>None yet.</li>"}</ul></section>`;
}

function renderMoney(model) {
  const state = model.state;
  return `<h2 class="with-mark">${mark("coin")} Treasury</h2>
    <p class="stat"><span>Cash</span><strong>${esc(money(state))}</strong></p>
    <form id="finance" class="panel stack"><label>Opening or corrected cash, in GP <input id="cash" name="cashGp" inputmode="numeric" placeholder="Leave blank to keep unknown"></label><button class="primary" type="submit">Set cash</button><p class="muted">Unknown stays unknown. It is not treated as zero, and nothing is spent until you set it.</p></form>
    <h3>Goods</h3>
    <ul>${state.goods.map((lot) => `<li>${esc(lot.name)} · list ${lot.standardGp} GP · ${esc(lot.status)}${lot.reservedGp ? ` · reserved ${lot.reservedGp}` : ""}</li>`).join("") || "<li>No goods recorded.</li>"}</ul>
    <form id="goods" class="stack"><label>Goods already on hand <input id="goods-name" name="name"></label><label>List price GP <input id="goods-gp" name="standardGp" inputmode="numeric"></label><button type="submit">Record goods without charging</button></form>
    <h3>Ledger</h3>
    <ul>${state.ledger.slice(-8).reverse().map((entry) => `<li>${entry.gp} GP · ${esc(entry.reason)}</li>`).join("") || "<li>No payments yet.</li>"}</ul>`;
}

function renderJournal(model) {
  const lines = model.state.audit.slice().reverse().slice(0, 40);
  return `<h2 class="with-mark">${mark("thread")} Journal</h2><p class="muted">Each saved change is listed. Overrides keep their reason.</p>
    <ol>${lines.map((entry) => `<li><strong>${esc(entry.summary)}</strong><br><span class="muted">${esc(entry.actorRole || "")} ${entry.reason ? `· ${esc(entry.reason)}` : ""}</span></li>`).join("") || "<li>No entries yet.</li>"}</ol>
    <button type="button" data-action="export">Download JSON backup</button>`;
}

function renderSettings(model) {
  const state = model.state;
  const unit = state.units[0];
  return `<h2 class="with-mark">${mark("key")} Settings</h2>
    <form id="settings" class="panel stack">
      <label>Estate name <input id="estate-name" name="name" value="${esc(state.name)}" maxlength="80"></label>
      <label>Owner label <input id="owner" name="owner" value="${esc(unit.owner)}" maxlength="120"></label>
      <label>Level <input id="level" name="level" inputmode="numeric" value="${unit.level}"></label>
      <label>Turn length in in-game days <input id="cadence" name="cadenceDays" inputmode="numeric" value="${state.clock.cadenceDays}"></label>
      <label>Calendar label <input id="date-label" name="label" value="${esc(state.clock.label)}" placeholder="Leave blank if the date is unknown"></label>
      <label>Day number <input id="ordinal" name="ordinal" inputmode="numeric" value="${state.clock.ordinal ?? ""}" placeholder="Unknown"></label>
      <fieldset><legend>Prerequisites this owner meets</legend>
        ${Object.entries(PREREQ_LABELS).map(([id, label]) => `<label><input type="checkbox" name="cap" value="${id}" ${unit.capabilities.includes(id) ? "checked" : ""}> ${esc(label)}</label>`).join("")}
      </fieldset>
      <button class="primary" type="submit">Save settings</button>
      <p class="muted">Raising the level adds one replacement per level gained. It does not add free specials by itself, and it does not look backward.</p>
    </form>
    <form id="advance" class="panel stack" style="margin-top:14px">
      <label>Advance in-game days <input id="advance-days" name="days" inputmode="numeric" value="1"></label>
      <button type="submit">Advance the calendar</button>
    </form>
    <form id="split" class="panel stack">
      <h3>Separate owner</h3>
      <label>Name <input id="split-name" name="name" value="Character bastion"></label>
      <label>Level <input id="split-level" name="level" inputmode="numeric" value="5"></label>
      <label><input id="split-ok" name="acknowledge" type="checkbox"> I understand this adds a new cap and copies no rooms.</label>
      <button type="submit">Split off a unit</button>
    </form>`;
}

function renderImport() {
  return `<h2 class="with-mark">${mark("card")} Review a private file</h2>
    <p class="muted">Paste a review file on this device. Turns, dates, loans, and goods are refused. Facilities and named people can be accepted one at a time, and only into the record you have open. Nothing in the file is bundled with the site.</p>
    <form id="review" class="stack">
      <label>Review JSON <textarea id="review-text" name="review"></textarea></label>
      <button type="submit">Read the file locally</button>
    </form>
    <div id="review-list"></div>`;
}

function renderHelp() {
  return `<h2 class="with-mark">${mark("star")} What the tracker does</h2>
    <div class="panel"><h3>Worked out for you</h3><ul>
      <li>Special facility cap, prerequisites, and the facilities that can repeat.</li>
      <li>One replacement each time a level is gained after tracking starts.</li>
      <li>Basic room price and time, with no charge for rooms you mark as already owned.</li>
      <li>Barrack recruiting, up to 4, inside the 12 or 25 bed limit.</li>
      <li>Storehouse buying and selling, including the 7-day wait. 500 GP of goods sells for 550 GP at level 5.</li>
      <li>Armory stock price, tougher defense dice, then the stock is used up.</li>
      <li>Wall squares, and fewer attack dice only after the enclosure is marked complete.</li>
      <li>Maintain for the whole owner, one event, and a shutdown that lasts the next turn.</li>
    </ul></div>
    <div class="panel"><h3>You still decide</h3><ul>
      <li>Crafting time and price, magic items, poisons, mounts, and treasure names.</li>
      <li>Research facts, rumors, charms, armies, and theater results.</li>
      <li>Whether a bastion has truly fallen.</li>
      <li>Old notes that do not say whether an order finished.</li>
    </ul><p class="muted">Source for the mechanics: the bastions chapter of the Dungeon Master's Guide. This screen does not reprint that chapter.</p></div>`;
}

function renderMore() {
  return `<h2 class="with-mark">${mark("pips")} More</h2><div class="stack">
    <button type="button" data-action="nav" data-view="money">${mark("coin")}<span>Treasury</span></button>
    <button type="button" data-action="nav" data-view="journal">${mark("thread")}<span>Journal and backup</span></button>
    <button type="button" data-action="nav" data-view="settings">${mark("key")}<span>Settings</span></button>
    <button type="button" data-action="nav" data-view="import">${mark("card")}<span>Review import</span></button>
    <button type="button" data-action="nav" data-view="help">${mark("star")}<span>What is automatic</span></button>
    <button type="button" data-action="export">${mark("seal")}<span>Download JSON backup</span></button>
  </div>`;
}

export function renderReview(items) {
  if (!items.length) return `<p class="muted">Nothing to review.</p>`;
  return `<div class="list">${items.map((item, index) => `<article class="card"><h3>${esc(item.title)}</h3><p class="muted">${esc(item.section)} · ${esc(item.status || "no status")}</p><p>${item.blocked ? "Not applied. Enter this yourself if you still want it." : "You can add this as an inherited, uncharged record."}</p>${item.blocked ? "" : `<button type="button" data-action="accept-review" data-index="${index}">Accept this item</button>`}</article>`).join("")}</div>`;
}
