# Bastion Tracker design requirements

This is the design of the Bastion Tracker as it stands after the work through migration 011. It is written for the DM. It describes behavior, not a recipe for changing the database. Decisions are also kept as short records in `doc/adr/`. A later design change adds another one of those records.

**Implemented** means the tracker already does this. **Planned** means John has agreed it, and it is not built yet.

The rules follow the 2024 bastions chapter. The tracker does not use the older bastion-point draft. It does not reprint that chapter. Numbers below are the ones the tracker uses.

## Core and platform

**Implemented.** One shared estate record, kept in the project database. A person sees it only after they sign in and belong to that estate. Anonymous visitors cannot read it or change it. Someone who is signed in but was not invited cannot see it either.

**Implemented.** Changes go through one saved command path. That path checks that the caller is signed in, then checks their role on that estate, and only then applies the change. Helper routines used inside that path are not available for a visitor or a signed-in user to call on their own. If two people save at once, the second save waits until they reload. Repeating the same save does not pay twice.

**Implemented.** Three roles:

- The DM sets the turn counter, money, level, replacements, and corrections, and can invite people.
- An editor can keep the roster, including adding someone with no name yet and filling the name in later. The saved rules also allow an editor to take a turn and issue orders. On the shared record, the Turn screen shows the advance and order controls to the DM.
- A reader can look, and can set or change the in-game date. A reader cannot take a turn, issue orders, or change rooms, people, money, or the turn counter.

**Implemented.** The practice sandbox is labeled as not the group record. Closing it drops the practice data. It is not synced, and it is not saved for anyone else. A failed save is shown as an error. It is not stored on the device and called a success.

**Implemented.** Unknown stays unknown. A blank opening cash is not zero. A blank Bastion turn is not turn 0. A blank in-game date is not invented.

**Implemented.** Ownership is set on purpose. Every way of changing a unit’s level uses the same check. That includes Settings and the older raise-level command. It does not add replacements and it does not record a reason. A level below 5 or above 20 is refused. The save is also refused, and nothing is written, when the special-facility cap or a facility’s own minimum level does not fit. The caps are 2, 4, 5, and 6 special facilities at levels 5, 9, 13, and 17. If the rooms still fit but an order already underway would be illegal at the new level, the save still happens and names that order. A new facility is added from the level cap. A replacement already recorded can still be spent. Splitting off another owner asks for a confirmation, adds a new cap, and copies no rooms. It is a new owner, not a level change of the current one.

**Implemented.** Screens use real buttons and labeled fields, and they work on a phone as well as a desk. The Journal turn list is a set of buttons that say whether they are open.

**Implemented.** The app sits on a fixed full-page backdrop of the estate art. A dark scrim keeps text readable. On a phone the art is biased toward the card fan at the lower right. The panels are dark charcoal with aged-brass headings, buttons, and focus rings, and bone-colored text. The Journal cards stay parchment with the handwriting font. Motion is not added to the backdrop.

**Implemented.** Every saved change is recorded with who made it. On the shared record that is the person’s role and email. Reasons for overrides are kept.

**Implemented.** Corrections stay with the DM. That includes editing, removing, or replacing a room, swapping a special facility without spending a level-up replacement, replacing or moving a person, cancelling unfinished work, reserving goods, releasing goods, and recording an order that is already underway. Removing a room archives it and does not move cash. The rules do not describe selling a room. Hirelings are kept on the roster or marked released. Defenders have to be counted down before a room that houses them can be removed. Unfinished work is cancelled only when the DM confirms it, and that does not pay a sale or refund a purchase.

## Turns and dates

**Implemented.** Bastion turns are the only game-time counter. Stored fields, the screen, order lengths, finish times, and the journal all use turns. The in-game date and the estate’s save number are different things. There is no separate session date. The save number only exists so two people do not overwrite each other.

**Implemented.** The in-game date is derived from an anchor, for example “turn 1 is 10 Tarsakh.” Each later turn adds the chosen turn length. The default is a ten-day tenday, and festival days are skipped so they do not use up one of those days. Settings can switch to the shorter chapter length, and can count festival days instead of skipping them. The calendar is the Calendar of Harptos: twelve months of thirty days, with the festivals that sit between months, including the Feast of the Moon, and Shieldmeet in a leap year. If the year is blank, Shieldmeet is not inserted, and the screen says so when a span crosses Midsummer. “Tarkesh” is accepted as Tarsakh. If no anchor is set, no date is shown. Changing the length does not move an anchor that is already saved.

**Implemented.** Any signed-in member of the estate can set the anchor or re-anchor the current turn, including a reader. Anonymous visitors cannot. A signed-in user who is not a member of that estate cannot. A re-anchor replaces the anchor at the current turn. Who did it, and why, stays on the Backup list. It does not create a second counter, and it does not move the turn number. A date already stored on a committed turn is left as it was.

**Implemented.** Loans appear on the home page under What is due, with the lender and the amount still owed.

**Implemented.** During a turn the DM can record a payment on each loan. One amount comes from the treasury and is deducted from tracked cash, refused if cash is unknown or too small. The other amount is personal treasure. It reduces the loan and is not tracked as cash. The loan cannot go below zero. The payment is on the Backup list.

**Implemented.** The turn form has a note of at most 600 characters. A longer note is refused on the page and in the saved command. Anyone who can take the turn can write it. The Journal shows it on that turn.

**Implemented.** Taking a turn is one sequence:

1. The turn counter moves forward by one.
2. The page shows what finished on the new turn, such as goods arriving or a sale paying out.
3. The page shows the in-game date for that turn. A member can keep it or set a different date if the party lost or gained time.
4. Orders are chosen for the special facilities.

**Implemented.** An order issued on turn N that takes one turn is due when the counter advances to N+1. A longer order is due on its own later turn. Work with no finish turn is skipped until someone marks it finished.

**Implemented.** Setup offers Tenday (FR) or 7 days (DMG), and a single line labeled Skip festival days. A new estate, and the first run of migration 009, use the tenday and skip festivals. The saved anchor is not moved.

**Implemented.** Home shows only the turn line, for example “Turn 4 · 10 Mirtul 1495 DR”. There is no session date beside it. Each committed turn stores the date it had when it was committed. Migration 010 drops the old session label so a stale note such as 30 Tarsakh cannot appear.

**Implemented.** Build times and wall times that are not a whole number of Bastion turns are paid for and left unscheduled. They are not rounded. A cramped, roomy, or vast basic room, an upgrade from one size to the next, and a wall square are in this group. Someone marks them finished when the work is done.

## Orders and facilities

**Implemented.** A level allows a set number of special facilities. Some can be kept only once. Barrack, Garden, Stable, and Training Area can repeat. Prerequisites are checked. A facility the unit is not ready for is refused.

**Implemented.** A Barrack recruits one to four defenders in a turn. A full Barrack refuses another recruit. A roomy Barrack holds twelve. A vast Barrack holds twenty-five.

**Implemented.** Storehouse Trade has two orders.

- Buy asks for a goods name and a list price. The price cannot pass the level’s limit: 500 GP before level 9, 2,000 GP from level 9, and 5,000 GP from level 13. The price is charged when the order is saved. It is refused if cash is still unknown or is too small. The goods arrive on the next turn.
- Sell asks for a lot and a list-price amount that is still free. The payout uses the level markup automatically, and that automation stays. The markup is 10 percent before level 9, 20 percent from level 9, 50 percent from level 13, and 100 percent from level 17. At level 5, 500 GP of goods pays 550 GP. The money arrives on the next turn. John wants this markup to remain automatic.

**Implemented.** “How many” appears only when Barrack Recruit is the chosen order. The Storehouse card shows the sell fields only for Sell, and the buy fields only for Buy. The level markup on a sale stays automatic.

**Implemented.** A Stable sale pays 20 percent over the list price from level 9 up. The tracker adds that. The money arrives on the next turn. A Stable purchase charges the list price when the order is saved. The Storehouse markup is unchanged.

**Implemented.** A Theater shows its performance die: d6, d8 from level 13, and d10 from level 17. A Teleportation Circle shows its spell level: 4th, or 8th from level 17. The tracker does not roll the die or cast the spell.

**Implemented.** Record existing state can enter defenders already housed, loans, goods already on hand, and an order already underway. Recording goods does not charge anyone. Marking goods committed only reserves them. It is not a completed sale and it does not pay anyone. A note that an order is already underway does not resolve that order when turns advance. The exception is a Storehouse sale already underway: it is tied to a chosen lot and pays once on the next turn, without paying at the moment it is recorded.

**Implemented.** The DM can release reserved goods. The screen asks for the amount. The change is journaled with who did it, and cash does not move. Release is refused while that amount is tied to an open Storehouse sale. The sale is not cancelled.

**Implemented.** The DM can mark a recorded order done, or cancel it. Neither action moves cash. Cancelling or marking done a linked Storehouse sale closes that sale so it will not pay later, and it releases the goods reservation so the lot is not stuck. The change is journaled.

## People

**Implemented.** Defenders are a count on each Barrack. Recruiting adds to that count. It does not create a named person. “Defenders already housed” sets the count. A generic name of the form Defender plus a number, or a blank name, is folded into that count by migration 009. A defender the DM named or edited by hand stays on the people list. The count still includes them, so the total does not change. Basic rooms keep the manual add-someone action, and that is also how a particular defender is named. The screen does not explain this rule.

**Implemented.** The People tab is one line per person: the name and tags on the left, the role or short description on the right, and the action buttons at the far right. On a phone the line stacks. The buttons stay real buttons.

## Journal and Backup

**Implemented.** The old combined page is now Backup. It is still the plain list of saved changes, with who made each one, and the same JSON download.

**Implemented.** Journal is a separate page. It does not change the estate. Any member, including a reader, can read it. It lists only committed turns. Setup, backup, corrections, renames, and roster edits are not cards. Those stay on Backup. Each turn is a button:

- Turn: N
- Date: the date recorded when that turn was committed, or “date not set”

Opening the button shows a short ledger: one line for each facility order, such as “Storehouse: sell 500 gp of herbs.”, then the turn note. Maintain and a turn with no orders are one short line each. It does not invent campaign facts.

**Implemented.** The newest turn card is open when the Journal is opened. The page is styled like readable parchment, with a self-hosted handwriting font and a plain fallback. An old audit number that is later than the saved Bastion turn is cleared by migration 010, so it is not shown as a later turn. Future cards come from committed turns only. When orders are saved, the backup line still names them.

## Out of scope / manual

These are not automated, on purpose. The DM or the player enters them, or leaves them alone.

- Crafting prices and times, magic items, poison prices, and mount prices. Those lists are outside the bastions chapter.
- Treasure names, research facts, rumors, charms, army upkeep, and theater results.
- A guild job whose rolled length is not a whole number of turns. The tracker does not round it. Type the turn count you are using.
- Whether a bastion has truly fallen. A long stretch without orders can warn. The fall is confirmed by the DM. It is not automatic.
- Old notes that do not say whether an order finished. They are not turned into completed turns.
- Private character histories. The roster here is a name, a role, a short line, and an optional link.

## Change log of decisions

**12 November 2026.** Bastion turns are the only game-time unit, everywhere. The in-game date is derived from a calendar anchor. Dates that are not a whole number of turns are not rounded into a schedule.

**14 November 2026.** Any signed-in member of the estate can set or change the in-game date, not only the DM. The DM can release goods that were reserved without an open sale. Journal and Backup are separate pages, and the journal is a steward’s report of recorded turns.

**15 November 2026.** Built: the tenday setting and festival-day choice; “How many” only on Barrack Recruit; Storehouse fields only for the chosen order; defenders as a count; loans on the home page and repayment during a turn; a turn note; the compact People tab. The same day, the session date was removed. Home shows only the turn line, and each committed turn keeps its recorded date. Saving a level is on the honor system, from 5 upward, and names an order that the new level would make illegal. A Stable sale adds 20 percent. The Theater die and the Teleportation Circle spell level are shown. The journal is a short ledger of committed turns only. The page uses the estate art as its backdrop, and every level change uses that same honor-system check. The decision records are in `doc/adr/`.
