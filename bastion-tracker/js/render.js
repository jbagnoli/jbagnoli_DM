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
  if (model.view === "record") return renderRecord(model);
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
  const specials = state.facilities.filter((item) => item.unitId === unit.id && item.kind === "special" && item.status !== "archived");
  const highest = specials.reduce((max, item) => Math.max(max, specialById(item.catalogId)?.level || 0), 0);
  const levels = Array.from({ length: 20 }, (_, index) => index + 1);
  return `<h2 class="with-mark">${mark("key")} Settings</h2>
    <p class="muted">Only the DM can save settings. Name, owner, level, turn length, date, and prerequisites are saved together. If one of them is refused, none of them change.</p>
    <form id="settings" class="panel stack">
      <label>Estate name <input id="estate-name" name="name" value="${esc(state.name)}" maxlength="80"></label>
      <label>Owner label <input id="owner" name="owner" value="${esc(unit.owner)}" maxlength="120"></label>
      <label for="level">Level
        <select id="level" name="level">${levels.map((level) => `<option value="${level}" ${level === unit.level ? "selected" : ""}>${level}</option>`).join("")}</select>
      </label>
      <p id="level-fit" class="muted">This unit has ${specials.length} special ${specials.length === 1 ? "facility" : "facilities"}. Level ${unit.level} allows ${specialCap(unit.level)}. ${highest ? `The highest requirement among them is level ${highest}.` : "No facility requirement yet."} A shut facility still counts. Saving a level that is too low for these rooms is refused.</p>
      <label><input id="grant-replacements" name="grantReplacements" type="checkbox"> This is a level-up. Add one replacement for each level gained.</label>
      <label>Turn length in in-game days <input id="cadence" name="cadenceDays" inputmode="numeric" value="${state.clock.cadenceDays}"></label>
      <label>Calendar label <input id="date-label" name="label" value="${esc(state.clock.label)}" placeholder="Leave blank if the date is unknown"></label>
      <label>Day number <input id="ordinal" name="ordinal" inputmode="numeric" value="${state.clock.ordinal ?? ""}" placeholder="Unknown"></label>
      <fieldset><legend>Prerequisites this owner meets</legend>
        ${Object.entries(PREREQ_LABELS).map(([id, label]) => `<label><input type="checkbox" name="cap" value="${id}" ${unit.capabilities.includes(id) ? "checked" : ""}> ${esc(label)}</label>`).join("")}
      </fieldset>
      <button class="primary" type="submit">Save settings</button>
      <p class="muted">Choosing a level here does not add replacements unless the level-up box is checked, and only for levels actually gained. It does not look backward, and it does not add facilities. The turn length stays editable. A new record starts at 10 in-game days.</p>
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
    </form>
    <p style="margin-top:14px"><button type="button" data-action="nav" data-view="record">Record defenders, loans, and orders already underway</button></p>`;
}

function renderRecord(model) {
  const state = model.state;
  const specials = state.facilities.filter((item) => item.kind === "special" && item.status !== "archived");
  const loans = state.finance.loans || [];
  const orders = (state.orders || []).filter((item) => item.recorded && item.status === "in_progress");
  const facilityOptions = specials.map((facility) => `<option value="${esc(facility.id)}">${esc(facility.name)}</option>`).join("");
  const orderOptions = specials.flatMap((facility) => {
    const spec = specialById(facility.catalogId);
    return (spec?.subs || []).map((sub) => `<option value="${esc(facility.id)}|${esc(sub.id)}">${esc(facility.name)}: ${esc(sub.label)}</option>`);
  }).join("");
  return `<h2 class="with-mark">${mark("seal")} Record existing state</h2>
    <p class="muted">DM only. Use this when the estate already has people, debts, or work in progress. Nothing here runs a Recruit turn, spends cash, or pays a sale.</p>
    <form id="record-defenders" class="panel stack">
      <h3>Defenders already housed</h3>
      ${specials.length ? `<label>Facility <select id="defender-facility" name="facilityId">${facilityOptions}</select></label>
        <label>How many <input id="defender-count" name="count" inputmode="numeric" value="0"></label>
        <label>Names, if you know them <textarea id="defender-names" name="names" placeholder="One name per line. Leave blank to record a count only."></textarea></label>
        <button class="primary" type="submit">Save defender count</button>
        <p class="muted">This sets the count at that facility. A roomy barrack still holds 12, and a vast barrack holds 25. Extra names are refused.</p>` : `<p class="muted">Add a special facility before recording defenders.</p>`}
    </form>
    <form id="record-loan" class="panel stack" style="margin-top:14px">
      <h3>Outstanding loan</h3>
      ${loans.length ? `<ul>${loans.map((loan) => `<li>${esc(loan.creditor)} · ${loan.amountGp} GP${loan.note ? ` · ${esc(loan.note)}` : ""}</li>`).join("")}</ul>` : `<p class="muted">No loans recorded. Unknown cash stays unknown.</p>`}
      <label>Which loan <select id="loan-id" name="loanId"><option value="">New loan</option>${loans.map((loan) => `<option value="${esc(loan.id)}">${esc(loan.creditor)} · ${loan.amountGp} GP</option>`).join("")}</select></label>
      <label>Creditor <input id="loan-creditor" name="creditor" maxlength="80" placeholder="A lender's name"></label>
      <label>Amount in GP <input id="loan-amount" name="amountGp" inputmode="numeric"></label>
      <label>Note <input id="loan-note" name="note" maxlength="240"></label>
      <label><input id="loan-remove" name="remove" type="checkbox"> Remove the selected loan</label>
      <button class="primary" type="submit">Save loan</button>
      <p class="muted">Saving a loan does not change the cash balance.</p>
    </form>
    <form id="record-goods" class="panel stack" style="margin-top:14px">
      <h3>Goods already committed</h3>
      <label>Existing lot, or a new one <select id="commit-lot" name="lotId"><option value="">New goods</option>${state.goods.filter((lot) => lot.status === "on_hand").map((lot) => `<option value="${esc(lot.id)}">${esc(lot.name)} · ${lot.standardGp} GP list${lot.reservedGp ? `, ${lot.reservedGp} reserved` : ""}</option>`).join("")}</select></label>
      <label>Name, for new goods <input id="commit-name" name="name" maxlength="80" placeholder="Wool bolts"></label>
      <label>List price committed, in GP <input id="commit-gp" name="standardGp" inputmode="numeric" placeholder="500"></label>
      <label>What the goods are tied up in <input id="commit-note" name="note" maxlength="240" placeholder="Trade sell already underway"></label>
      <button class="primary" type="submit">Mark goods committed</button>
      <p class="muted">Example: 500 GP of goods already in a sell order. This reserves them. It does not pay the sale.</p>
    </form>
    <form id="record-order" class="panel stack" style="margin-top:14px">
      <h3>Order already underway</h3>
      ${specials.length ? `<label>Facility and order <select id="record-order-key" name="orderKey">${orderOptions}</select></label>
        <label>Turn it started <input id="order-started" name="startedTurn" inputmode="numeric" placeholder="Leave blank if you do not know"></label>
        <label>Note <input id="order-note" name="note" maxlength="240"></label>
        <button class="primary" type="submit">Mark order in progress</button>
        <p class="muted">This records the current order. It does not recruit, spend, or finish the work.</p>` : `<p class="muted">Add a special facility before recording an order.</p>`}
      ${orders.length ? `<ul>${orders.map((order) => `<li>${esc(order.label || order.suborder)} · turn ${order.startedTurn ?? "unknown"}${order.note ? ` · ${esc(order.note)}` : ""}</li>`).join("")}</ul>` : ""}
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
      <li>Defenders, loans, goods already committed, and an order that is already running. Enter those on Record existing state. That screen does not run a turn or move cash.</li>
    </ul><p class="muted">Source for the mechanics: the bastions chapter of the Dungeon Master's Guide. This screen does not reprint that chapter.</p></div>`;
}

function renderMore() {
  return `<h2 class="with-mark">${mark("pips")} More</h2><div class="stack">
    <button type="button" data-action="nav" data-view="money">${mark("coin")}<span>Treasury</span></button>
    <button type="button" data-action="nav" data-view="journal">${mark("thread")}<span>Journal and backup</span></button>
    <button type="button" data-action="nav" data-view="settings">${mark("key")}<span>Settings</span></button>
    <button type="button" data-action="nav" data-view="record">${mark("seal")}<span>Record existing state</span></button>
    <button type="button" data-action="nav" data-view="import">${mark("card")}<span>Review import</span></button>
    <button type="button" data-action="nav" data-view="help">${mark("star")}<span>What is automatic</span></button>
    <button type="button" data-action="export">${mark("seal")}<span>Download JSON backup</span></button>
  </div>`;
}

export function renderReview(items) {
  if (!items.length) return `<p class="muted">Nothing to review.</p>`;
  return `<div class="list">${items.map((item, index) => `<article class="card"><h3>${esc(item.title)}</h3><p class="muted">${esc(item.section)} · ${esc(item.status || "no status")}</p><p>${item.blocked ? "Not applied. Enter this yourself if you still want it." : "You can add this as an inherited, uncharged record."}</p>${item.blocked ? "" : `<button type="button" data-action="accept-review" data-index="${index}">Accept this item</button>`}</article>`).join("")}</div>`;
}
