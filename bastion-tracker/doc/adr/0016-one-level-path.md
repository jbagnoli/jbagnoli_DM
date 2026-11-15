# 0016. Every level change uses the same checks

- Status: Accepted
- Date: 2026-11-15

## Context

Saving a level from Settings already refused a level below 5, refused a level the rooms do not fit, and named an order that a lower level would make illegal. It did not add replacements. The older raise-level command still only moved upward and added one replacement for each level gained, and it skipped those room checks. There is no separate raise-level control on the page. Settings is where the level is chosen.

## Decision

Raising the level calls the same save used by Settings. It can move up or down. It refuses a level below 5 or above 20. It refuses, and writes nothing, when the special-facility count or a facility’s own minimum level does not fit. If the rooms fit and an order already underway would be illegal, it still saves and names that order. It does not add replacements and does not ask for a reason. A facility gained with a level is added through the normal add-facility action, which already checks the cap. A replacement already stored on the record can still be spent. Splitting off another owner is a new unit, not a level change of the current one.

## Consequences

The raise-level command stays so an older caller cannot skip the checks, and it does the same thing as saving the level. The page does not grow a second level control.
