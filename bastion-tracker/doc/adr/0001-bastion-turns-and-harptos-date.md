# 0001. Bastion turns and an anchored Harptos date

- Status: Accepted
- Date: 2026-11-12

## Context

The tracker had mixed day counts and turn counts. The table needed one counter, plus a readable in-game date.

## Decision

Bastion turns are the only game-time counter. The in-game date is derived from an anchor on the Calendar of Harptos. A build time that is not a whole number of turns is paid and left unscheduled.

## Consequences

Orders, finish times, and the journal speak in turns. The save number and any real-world note stay separate from the turn. The anchor is not a second counter.
