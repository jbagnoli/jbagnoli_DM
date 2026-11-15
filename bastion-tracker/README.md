# Bastion tracker

A shared record for bastion rooms, people, money, and turns. The chronicle at `../eternal-concord/` is unchanged.

The shared database is already created. The site uses its publishable key. You are not in the group record until you sign in. The practice sandbox stays on **Not connected** and is labeled as not synced. A failed save is shown as an error. It is not written onto this device and called a success.

Notion is left as it is. This app does not write to Notion. Full NPC histories stay there. The roster here is a name, a role, a short line, and an optional link.

The github.io host may still show Chrome's "Dangerous site" warning until Google finishes its review. Do not ask players to bypass that warning, and do not treat the address as ready to share until the warning is gone.

## What is already set up

- The Supabase project exists. `config.js` has its URL and publishable key. That key is safe to publish. Do not put a secret key in the site.
- `supabase/migrations/001_bastion.sql` has been applied.
- Public signup is off. Email and password sign-in is on. The DM account was created by hand in the Supabase dashboard.
- Anonymous visitors cannot read the tables or create an estate. That was checked against the live project.

The publishable key is not a JWT. The tracker sends it as the `apikey` header. Before sign-in it is also sent as `Authorization: Bearer`. This project accepts that and treats the caller as anonymous. After sign-in, `Authorization` is the user's access token and `apikey` stays the publishable key.

## What you still do

1. After this change is merged, run `supabase/migrations/007_bastion_turns.sql` once in the Supabase SQL editor. Do not run `001` through `006` again. `007` does not change cash. It switches the saved record onto Bastion turns, leaves a start turn unknown when the old number cannot be trusted, and lets any signed-in member of the estate set the in-game date.
2. Open the tracker and sign in with the DM account. The first sign-in creates your estate and makes you its DM. Until you sign in, the page stays **Not connected**.
3. Add other people in the Supabase dashboard (Authentication → Users). Use the same email they will type here. Public signup will not create accounts.
4. Sign in as the DM and create an invite code for that email and role. Give them the code yourself. They sign in, then accept the code.
5. Set the Bastion turn and opening cash only when you know them. Unknown stays unknown, including a blank turn. It is not treated as turn 0, and cash is not treated as zero. The DM sets the turn counter. Any signed-in member of the estate can set the calendar anchor, or re-anchor the current turn when the party lost or gained time. The date shown next to a turn is derived from that anchor. A session date is only a real-world note.
6. Defenders already housed, outstanding loans, goods already committed to an order, and an order that is already running are entered from More → Record existing state. That screen does not run a turn or move cash.
7. Keep the old Notion page until you decide the tracker is the record you want. This app does not switch that for you.

Publishing the site is the existing Pages workflow. A deploy log shows the files are on the web. The github.io host may still show Chrome's "Dangerous site" warning. Do not ask anyone to bypass it, and do not treat the address as ready to share until that warning is gone.

Roles:

- **DM** changes level, money, replacements, invites, and overrides.
- **Editor** can run turns, add rooms, and keep the roster. That includes adding someone with no name yet and filling the name in later. An editor cannot remove or replace a person, move someone to another room, or edit, remove, or replace a room.
- **DM** can also remove a roster name entered by mistake, when that person is not a defender, not assigned to a facility, not set to protect the bastion, and not tied to an unfinished order. The DM can replace that person instead, which keeps the post and leaves the old name marked replaced.
- **DM** can edit a room's recorded type, size, or note, remove a room, or replace a basic room. Those are corrections. Removing a room archives it and does not move cash. The chapter does not describe selling a room.
- **DM** can swap a special facility in two different ways. A level-up replacement spends one replacement granted when the level goes up. A DM correction swap can fix a wrong choice or change the facility before the next level, and it does not spend that replacement. Hirelings must be kept on the roster or marked released. Defenders have to be counted down first. Unfinished work is cancelled only when the DM confirms it, and that does not pay a sale or refund a purchase.
- **Reader** can look, and can set or change the in-game date. A reader cannot take a turn, issue orders, or change rooms, people, money, or the turn counter.
- Someone who is signed in but not invited cannot see the estate or change its date. Anonymous visitors cannot read it or change a date.

If two people save at once, the second save is refused until they reload. Selling the same goods twice with the same save key does not pay twice.

## Practice sandbox

Use **Open practice sandbox** to learn the screens. The sample hall is called Hearthwatch Hold. It is not your estate.

## What is worked out, and what you still enter

Worked out from the bastions chapter, without reprinting it:

- How many special facilities a level allows, which ones can repeat, and prerequisites.
- One published replacement each time the level goes up after you start tracking. The current level alone does not grant a pile of swaps. A mid-level swap is a separate DM correction.
- Basic room price. Rooms you mark as already owned are free. Published build and wall times that are not a whole number of Bastion turns are not scheduled.
- Barrack recruiting, Storehouse buy and sell (each finishes on the next Bastion turn), and Armory stock.
- Maintain for the whole owner, one event, and a shutdown that lasts the next Bastion turn.

You still enter crafting prices and times, magic items, poison and mount prices, treasure names, research, rumors, and whether a bastion has fallen. Old notes that do not say an order finished are not turned into completed turns.

## Checks

From the repository root:

```bash
node --test bastion-tracker/js/rules.test.js
bash bastion-tracker/supabase/test_rls.sh
python3 scripts/verify_site.py
```

The database check needs PostgreSQL. It creates a temporary local database and does not touch a hosted project.
