# 0014. The journal is a short ledger

- Status: Accepted
- Date: 2026-11-15

## Context

The journal included setup, backup, corrections, renames, and roster edits. An old setup note had stored the number 30. That number was read as Bastion turn 30 and produced a card dated like 30 Hammer 1496 DR. The report was also written as a paragraph.

## Decision

The journal lists only committed turns. Each card is the turn number, the date recorded for that turn, one short line for each facility order, and the turn note. Setup, backup, audit, corrections, renames, and roster edits stay on the Backup page only. An audit number later than the saved Bastion turn is cleared once, so the old 30 is not a turn. Future journal cards come from committed turns, not from those audit numbers.

## Consequences

A roster edit no longer opens a journal card. A turn committed before a date existed keeps “date not set” even after an anchor is added later. The journal is styled as a readable parchment page, with a self-hosted handwriting font and a plain fallback.
