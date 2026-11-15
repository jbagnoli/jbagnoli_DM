# 0003. Release goods and Storehouse order fields

- Status: Accepted
- Date: 2026-11-14

## Context

Goods reserved with no open sale could not be freed. Storehouse buy and sell did not ask for the goods they needed. The level markup on a sale was already automatic and had to stay that way.

## Decision

The DM can release all or part of a reservation that is not tied to an open sale. Release never moves cash. A sell asks for a lot and an amount. A buy asks for a name and a price, capped at the level limit and refused if cash is short. The payout markup stays automatic.

## Consequences

Marking goods committed is still only a reservation, not a completed sale. A recorded Storehouse sale links a lot and pays once on the next turn.
