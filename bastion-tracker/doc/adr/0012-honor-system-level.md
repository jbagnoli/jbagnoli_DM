# 0012. Level is on the honor system

- Status: Accepted
- Date: 2026-11-15

## Context

Saving a level asked whether it was a level-up and could add replacements and a reason. A level below 5 could also be saved when the unit had no special facilities. Bastions start at level 5.

## Decision

Saving a level does not add replacements and does not record a reason. The level-up checkbox is gone. A level below 5 is refused, even with no special facilities. The save is also refused when the special-facility cap or a facility’s minimum level does not fit, and nothing is saved in that case. If the rooms still fit but an order already underway would be illegal at the new level, the save still happens and the screen names that order. That covers magic-item crafting, which needs level 9, and a Storehouse purchase over the new level’s buy limit.

## Consequences

The published replacement action is unchanged: it still spends a replacement that was granted when the level was raised on purpose. A settings save does not grant one.
