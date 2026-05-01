---
id: TASK-3
title: Add MAX_DEADLINE constraint to BridgeHTLC.lock
status: Done
assignee: []
created_date: '2026-04-30 13:14'
labels:
  - security
  - bridge
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BridgeHTLC.lock currently hardcodes deadline to block.timestamp + 24 hours but does not enforce a maximum. If the contract is upgraded to accept a caller-specified deadline, an attacker could set a deadline beyond the 2D verifier's refund-check window (10,000 blocks ≈ 33 hours), refund after the window closes, and the verifier would miss it. Adding a protocol-level MAX_DEADLINE constant (e.g. 48 hours) and reverting on lock calls that exceed it closes this gap permanently, independent of verifier configuration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BridgeHTLC.lock reverts with DeadlineTooFar if deadline > block.timestamp + 24h
- [x] #2 MAX_DEADLINE_DURATION = 24 hours (safely below 33h verifier window)
- [x] #3 Two new tests: too-far revert + exactly-max boundary
- [x] #4 README updated with the new constraint
<!-- AC:END -->
