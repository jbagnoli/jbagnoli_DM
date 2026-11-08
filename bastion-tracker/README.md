# Bastion tracker

A shared record for bastion rooms, people, money, and turns. The chronicle at `../eternal-concord/` is unchanged.

The page is not the group's record until you connect a database. Until then it says **Not connected** and offers a practice sandbox. The sandbox is fictional, stays in the browser tab, and is dropped when you leave. A failed save is shown as an error. It is not written onto this device and called a success.

Notion is left as it is. This app does not write to Notion. Full NPC histories stay there. The roster here is a name, a role, a short line, and an optional link.

The github.io host may still show Chrome's "Dangerous site" warning until Google finishes its review. Do not ask players to bypass that warning, and do not treat the address as ready to share until the warning is gone.

## What you do once

These steps are yours. This repository does not create the database or turn Pages on.

1. Create a Supabase project on the free plan. Do not add a paid add-on.
2. In the SQL editor, run `supabase/migrations/001_bastion.sql`.
3. Under Authentication, turn on email and password. Create the DM user there. Leave public signup off unless you want strangers to be able to create their own empty estates. They still cannot see yours.
4. Copy the project URL and the **anon public** key into `config.js`. Do not put the secret service key in that file or anywhere in the site. The anon key is meant to be public. The database rules, not the key, decide who can read.
5. Merge the pull request when you are ready. The existing Pages workflow publishes this folder with the chronicle. A successful deploy log is the only proof the files are on the web. That still does not mean the database is connected, and it does not clear a browser warning.
6. Open the tracker, sign in, and create the estate. You are the DM for that estate.
7. Invite a player from the database with `create_invite`, or add a small invite form later. Give them the one-time code out of band. They sign in with the same email and accept the code.
8. Set the in-game day, turn length, and opening cash only when you know them. Leave them blank while they are unknown. Unknown cash is not zero.
9. Keep the old Notion page until you decide the tracker is the record you want. This app does not switch that for you.

Roles:

- **DM** changes level, money, replacements, invites, and overrides.
- **Editor** can run turns, rooms, and the roster.
- **Reader** can look and cannot change anything.
- Someone who is signed in but not invited cannot see the estate. Anonymous visitors cannot read it.

If two people save at once, the second save is refused until they reload. Selling the same goods twice with the same save key does not pay twice.

## Practice sandbox

Use **Open practice sandbox** to learn the screens. The sample hall is called Hearthwatch Hold. It is not your estate.

## What is worked out, and what you still enter

Worked out from the bastions chapter, without reprinting it:

- How many special facilities a level allows, which ones can repeat, and prerequisites.
- One replacement each time the level goes up after you start tracking. The current level alone does not grant a pile of swaps.
- Basic room price and days. Rooms you mark as already owned are free.
- Barrack recruiting, Storehouse buy and sell (7 days even on a longer turn), Armory stock, and wall squares.
- Maintain for the whole owner, one event, and a shutdown that lasts the next turn rather than a number of days.

You still enter crafting prices and times, magic items, poison and mount prices, treasure names, research, rumors, and whether a bastion has fallen. Old notes that do not say an order finished are not turned into completed turns.

## Checks

From the repository root:

```bash
node --test bastion-tracker/js/rules.test.js
bash bastion-tracker/supabase/test_rls.sh
python3 scripts/verify_site.py
```

The database check needs PostgreSQL. It creates a temporary local database and does not touch a hosted project.
