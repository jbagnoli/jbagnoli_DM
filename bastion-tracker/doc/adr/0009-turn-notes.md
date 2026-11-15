# 0009. Turn notes

- Status: Accepted
- Date: 2026-11-15

## Context

A turn needed a place for a short remark that is not an order.

## Decision

The turn form has a note of at most 600 characters. The limit is enforced when the turn is saved. Anyone who can take the turn can write it. The Journal shows the note on that turn.

## Consequences

A longer note is refused. It is not cut down in secret.
