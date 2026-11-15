# 0006. The session label follows the date

- Status: Accepted
- Date: 2026-11-15

## Context

The session label stayed on an old value after the turn moved.

## Decision

Advancing the turn, setting the anchor, or re-anchoring the current turn sets the session label to that turn’s in-game date.

## Consequences

The label is no longer a stale note once a date exists. If there is no anchor, no date is invented.
