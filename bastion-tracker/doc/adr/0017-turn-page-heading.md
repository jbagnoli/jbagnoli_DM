# 0017. The Turn page heading is the turn number

- Status: Accepted
- Date: 2026-11-15

## Context

The Turn page heading said only “Turn”, and the next sentence repeated the turn number and the date before the instructions.

## Decision

The heading is the turn number, such as “Turn 4”. The date is the line directly under it. That date is the one derived for the current turn, or the date set by an override. If there is no turn, the heading says “Turn unknown”. If there is no date, the line says “date not set”. The instructions no longer repeat either one.

## Consequences

No data changes. The same date is still used when the turn is checked and when orders are chosen. No migration is required.
