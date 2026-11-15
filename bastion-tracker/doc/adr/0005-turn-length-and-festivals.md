# 0005. Turn length and festival days

- Status: Accepted
- Date: 2026-11-15

## Context

This campaign keeps time in ten-day tendays. The bastions chapter uses a shorter turn. Festival days may or may not count inside that length.

## Decision

Settings offer a tenday or the shorter chapter length, and whether festival days are counted or skipped. The default, including the first run of migration 009, is a tenday with festival days skipped. The saved anchor is not moved.

## Consequences

Later turns are dated from the anchor with that length. Switching the setting changes later dates. It does not rewrite the anchor.
