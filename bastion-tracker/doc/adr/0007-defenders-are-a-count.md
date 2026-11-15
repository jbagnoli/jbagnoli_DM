# 0007. Defenders are a count

- Status: Accepted
- Date: 2026-11-15

## Context

Naming every defender created a long list of people the table did not want.

## Decision

Each Barrack stores a defender count. Recruiting and “already housed” change that count and do not create people. A person entry is for someone added by hand, including a named defender, and for hirelings of a special facility. Migration 009 folds a blank name or a generic “Defender” plus a number into the count and keeps any other name. The count stays the full number.

## Consequences

A large bastion does not grow a person entry per defender. The screen does not explain this rule.
