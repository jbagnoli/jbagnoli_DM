# 0008. Loans on the home page and during a turn

- Status: Accepted
- Date: 2026-11-15

## Context

A loan was easy to forget because it lived only on the record screen.

## Decision

What is due on the home page lists each lender and the amount still owed. During a turn the DM can record a treasury payment and a personal-treasure payment. Only the treasury part leaves tracked cash. Personal treasure is not tracked as cash. The balance cannot go below zero.

## Consequences

The payment is journaled. An unknown or too-small treasury balance refuses the treasury part.
