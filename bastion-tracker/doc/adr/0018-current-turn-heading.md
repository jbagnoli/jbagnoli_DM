# 0018. The home section is titled Current Turn

- Status: Accepted
- Date: 2026-11-21

## Context

The home page listed loans and open timers under “What is due”, and repeated the turn and date on a small line under the estate name.

## Decision

That section’s heading is the live turn and its in-game date, for example “Current Turn 4 · 10 Mirtul, 1495 DR”. The date is the one derived for the current turn, or the date set by an override, the same source the Turn page uses. If no date is set, the heading is “Current Turn” and the number. The line under the estate name is removed, so the turn and date are not shown twice. The list is unchanged: loans still show the lender and the amount still owed, and open timers still show when they finish. Paying a loan during a turn is unchanged.

## Consequences

Nothing is stored differently. No migration is required.
