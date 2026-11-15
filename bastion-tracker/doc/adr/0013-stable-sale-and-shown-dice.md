# 0013. Stable sales, the Theater die, and the circle spell

- Status: Accepted
- Date: 2026-11-15

## Context

A Stable sale did not add the sale bonus, even though the room text said it would. The Theater die and the Teleportation Circle spell level were left for the table to remember.

## Decision

A Stable sale pays 20 percent over the list price from level 9 up. The tracker adds that, the same way it adds the Storehouse markup. The Storehouse markup stays on its own scale. The room shows the Theater die: d6, d8 from level 13, and d10 from level 17. The room shows the Teleportation Circle spell level: 4th, or 8th from level 17.

## Consequences

A Stable purchase still charges the list price when the order is saved. A Stable sale pays on the next turn. The die and the spell level are shown. They are not rolled or cast by the tracker.
