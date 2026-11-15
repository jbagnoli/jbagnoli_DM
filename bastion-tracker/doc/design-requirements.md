# Bastion Tracker design requirements

This is the design of the Bastion Tracker as it stands after the work through migration 008, plus the decisions that are agreed and not built yet. It is written for the DM. It describes behavior, not a recipe for changing the database.

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

**Implemented.** Ownership is set on purpose. Raising the recorded level does not grant a pile of facility swaps for levels already passed. One published replacement is added only for each level actually gained after tracking starts, and only when that box is checked. Splitting off another owner asks for a confirmation, adds a new cap, and copies no rooms.

**Implemented.** Screens use real buttons and labeled fields, and they work on a phone as well as a desk. The Journal turn list is a set of buttons that say whether they are open.

**Implemented.** Every saved change is recorded with who made it. On the shared record that is the person’s role and email. Reasons for overrides are kept.

**Implemented.** Corrections stay with the DM. That includes editing, removing, or replacing a room, swapping a special facility without spending a level-up replacement, replacing or moving a person, cancelling unfinished work, reserving goods, releasing goods, and recording an order that is already underway. Removing a room archives it and does not move cash. The rules do not describe selling a room. Hirelings are kept on the roster or marked released. Defenders have to be counted down before a room that houses them can be removed. Unfinished work is cancelled only when the DM confirms it, and that does not pay a sale or refund a purchase.

## Turns and dates

**Implemented.** Bastion turns are the only game-time counter. Stored fields, the screen, order lengths, finish times, and the journal all use turns. A real-world session note, the in-game date, and the estate’s save number are three different things. The save number only exists so two people do not overwrite each other.

**Implemented.** The in-game date is derived from an anchor, for example “turn 1 is 10 Tarsakh.” Turn N is that anchor plus seven days for each turn after the anchor turn. The calendar is the Calendar of Harptos: twelve months of thirty days, and the festivals that sit between months. A leap year can include Shieldmeet. If the year is blank, Shieldmeet is not inserted, and the screen says so when a span crosses Midsummer. “Tarkesh” is accepted as Tarsakh. If no anchor is set, no date is shown.

**Implemented.** Any signed-in member of the estate can set the anchor or re-anchor the current turn, including a reader. Anonymous visitors cannot. A signed-in user who is not a member of that estate cannot. A re-anchor replaces the anchor at the current turn and is written in the journal with who did it and why. It does not create a second counter, and it does not move the turn number.

**Implemented.** Taking a turn is one sequence:

1. The turn counter moves forward by one.
2. The page shows what finished on the new turn, such as goods arriving or a sale paying out.
3. The page shows the in-game date for that turn. A member can keep it or set a different date if the party lost or gained time.
4. Orders are chosen for the special facilities.

**Implemented.** An order issued on turn N that takes one turn is due when the counter advances to N+1. A longer order is due on its own later turn. Work with no finish turn is skipped until someone marks it finished.

**Planned.** Turn length should be chosen in setup. The default for this campaign is a ten-day tenday, the Faerûn rhythm. The seven-day length from the bastions chapter stays available as an option. Setup should also say whether festival days, such as Greengrass, are counted in that length or skipped. Today every turn is seven calendar days, and festival days are part of that count. There is no tenday setting and no switch for skipping festivals.

**Planned. Must fix.** Each time the turn moves forward, the session label should become that new turn’s in-game date. Today the session label is a separate note. Advancing the turn does not change it, so it can stay on an old value.

**Implemented.** Build times and wall times that are not a whole number of Bastion turns are paid for and left unscheduled. They are not rounded. A cramped, roomy, or vast basic room, an upgrade from one size to the next, and a wall square are in this group. Someone marks them finished when the work is done.

## Orders and facilities

**Implemented.** A level allows a set number of special facilities. Some can be kept only once. Barrack, Garden, Stable, and Training Area can repeat. Prerequisites are checked. A facility the unit is not ready for is refused.

**Implemented.** A Barrack recruits one to four defenders in a turn. A full Barrack refuses another recruit. A roomy Barrack holds twelve. A vast Barrack holds twenty-five.

**Implemented.** Storehouse Trade has two orders.

- Buy asks for a goods name and a list price. The price cannot pass the level’s limit: 500 GP before level 9, 2,000 GP from level 9, and 5,000 GP from level 13. The price is charged when the order is saved. It is refused if cash is still unknown or is too small. The goods arrive on the next turn.
- Sell asks for a lot and a list-price amount that is still free. The payout uses the level markup automatically, and that automation stays. The markup is 10 percent before level 9, 20 percent from level 9, 50 percent from level 13, and 100 percent from level 17. At level 5, 500 GP of goods pays 550 GP. The money arrives on the next turn. John wants this markup to remain automatic.

**Planned.** The “How many” field appears only on Barrack Recruit. It should not sit on every facility. The Storehouse card should show only the fields for the order that was chosen: the sell fields for Sell, and the buy fields for Buy. Today those extra fields are all visible together, and “How many” is on every order card.

**Implemented.** Record existing state can enter defenders already housed, loans, goods already on hand, and an order already underway. Recording goods does not charge anyone. Marking goods committed only reserves them. It is not a completed sale and it does not pay anyone. A note that an order is already underway does not resolve that order when turns advance. The exception is a Storehouse sale already underway: it is tied to a chosen lot and pays once on the next turn, without paying at the moment it is recorded.

**Implemented.** The DM can release reserved goods. The screen asks for the amount. The change is journaled with who did it, and cash does not move. Release is refused while that amount is tied to an open Storehouse sale. The sale is not cancelled.

**Planned.** An order recorded as already underway has no Mark done and no Cancel. That is a gap. A recorded Storehouse sale is the exception already built: it pays on the next turn. Other recorded orders just sit there.

## People

**Planned.** This is how the tracker should treat people. It is not built yet, and it does not need a paragraph of explanation on the screen.

Defenders are not given individual names or separate people entries by default. They are a count on each Barrack, so a large bastion does not create dozens of people. Only the hirelings of a special facility get people entries, and only as many as that facility’s description calls for. Basic rooms have no such rule, so they keep the existing way of adding someone by hand. If the DM wants to name one particular defender, that uses the same add-someone action. It is not automatic.

**Implemented today, and due to change when the rule above is built.** Recruiting and “defenders already housed” currently create one roster entry per defender, with a generated name if none was typed. Hirelings are also roster entries. The DM can add, rename, replace, or remove a person by hand, with the limits already described under corrections.

## Journal and Backup

**Implemented.** The old combined page is now Backup. It is still the plain list of saved changes, with who made each one, and the same JSON download.

**Implemented.** Journal is a separate page. It does not change the estate. Any member, including a reader, can read it. Each recorded turn is a button:

- Turn: N
- Date: the in-game date, or “date not set” when there is no anchor

Opening the button shows a short report in a steward’s voice. The report uses only what was recorded for that turn: orders, results, money, goods, and the people or rooms that changed with it. It does not invent campaign facts. Renames and other corrections are a short footnote, not the report itself.

**Planned.** The newest turn card should be open when the page is opened. Today every card starts closed.

**Planned.** The report should say whether the owner was present, and how orders were sent when the owner was away, including a message spell if that was how word arrived. Presence is already stored with the turn. The report does not say it yet.

**Planned.** A turn that only records setup or a correction should still get its own card. Today a card is created from a turn that was taken or from work that came due. A correction by itself does not open a new card. It can only appear as a footnote on a turn that already has one.

**Planned.** When orders are saved, the backup line should name those orders. Today it says that orders were committed, and the detail lives on the turn, not in that one line.

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

**15 November 2026.** Still to build: a turn-length setting, with a ten-day tenday as the default for this campaign and the seven-day chapter length as the other option, including whether festival days count; the session label updating to each new turn’s in-game date; the “How many” field only on Barrack Recruit, and Storehouse fields only for the chosen order; defenders as a count rather than a person each, with hireling entries limited to the facility description; Journal opening on the newest turn, naming presence and how orders were sent, giving setup-only turns a card, and naming the orders in the backup line.
