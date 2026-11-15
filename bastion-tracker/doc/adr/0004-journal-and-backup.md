# 0004. Journal and Backup are separate

- Status: Accepted
- Date: 2026-11-14

## Context

The old journal was a plain list of every save. The table wanted a steward’s report of each turn, without losing the backup.

## Decision

Backup keeps the plain list and the JSON download. Journal is a separate read-only page. Each turn is a button showing the turn number and the in-game date, or “date not set.” The report uses only recorded facts.

## Consequences

Corrections stay in a short footnote unless that turn has no orders, in which case the setup itself is the card.
