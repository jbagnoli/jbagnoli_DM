# 0011. There is no separate session date

- Status: Accepted
- Date: 2026-11-15

## Context

The home page showed a session date as well as the turn’s in-game date. A stale session label could still say an old date, such as 30 Tarsakh, after the turn line had moved on. Settings also described that date as a real-world note and described later turns as seven days.

## Decision

The only date is the turn line: the Bastion turn and the in-game date derived from the anchor, the chosen turn length, and the festival setting. Any turn’s date can still be overridden. Each committed turn keeps the date recorded when it was committed. The session-date field is removed from Settings and from Home. The saved label is dropped so nothing still displays it. Turn length choices are labeled Tenday (FR) and 7 days (DMG). Skip festival days is one labeled line.

## Consequences

Home reads like “Turn 4 · 10 Mirtul 1495 DR”. Later changes to the anchor do not rewrite a date already stored on a committed turn. This replaces the session-label decision in 0006.
