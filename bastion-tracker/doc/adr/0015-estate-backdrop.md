# 0015. The estate art is the page background

- Status: Accepted
- Date: 2026-11-15

## Context

The tracker used a light parchment page and a repeating line pattern. John supplied a dark umber illustration, with aged-brass line art and a fan of cards at the lower right, and asked for it as the background with a matching color scheme.

## Decision

The illustration is a fixed full-viewport background, covered to the screen. A dark scrim sits over it so text keeps a readable contrast. On a narrow screen the picture is positioned toward the card fan. The panels are semi-opaque charcoal. Headings, buttons, focus rings, and the active tab use aged brass. Body text is bone. The Journal cards stay parchment, with the same handwriting font. The backdrop does not scroll separately and does not move. A compressed WebP is used, with a JPEG fallback. The large original is not stored in the repository.

## Consequences

Every screen shares one set of color variables. The Journal remains a light card on the dark page so the ledger stays easy to read.
