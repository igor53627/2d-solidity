---
id: TASK-1
title: 'claim() front-running: add per-lock receiver field'
status: Done
assignee: []
created_date: '2026-04-29 11:50'
updated_date: '2026-04-29 11:54'
labels:
  - security
dependencies: []
references:
  - src/BridgeHTLC.sol
  - test/BridgeHTLC.t.sol
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
claim() transfers tokens to msg.sender. In bridge-in, the user reveals preimage on 2D chain, and a front-runner monitoring 2D can race the operator's Ethereum claim TX and steal the locked USDC. Fix: add a per-lock receiver field set at lock time. claim() sends tokens to l.receiver instead of msg.sender. Bridge-in: user sets receiver=operator. Bridge-out: operator sets receiver=user. Front-running neutralized because tokens always go to the designated receiver regardless of who calls claim. An immutable claimant would break bridge-out (user can't claim). A proxy pattern reintroduces upgrade authority (the Wormhole/Nomad/Ronin class of attacks).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lock struct gains receiver field (address) set at lock time
- [ ] #2 lock() takes receiver as parameter, stores in Lock
- [ ] #3 claim() transfers to l.receiver instead of msg.sender
- [ ] #4 Locked event updated to include receiver parameter
- [ ] #5 Existing tests updated for new lock() signature
- [ ] #6 New test: front-runner calls claim but tokens go to designated receiver
- [ ] #7 New test: bridge-out flow works with operator as locker and user as receiver
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Already addressed in current code. Lock struct has claimer field (line 31), claim() checks msg.sender != l.claimer (line 117). Front-running is blocked. Task created from stale submodule read — the actual repo already had the fix.
<!-- SECTION:FINAL_SUMMARY:END -->
