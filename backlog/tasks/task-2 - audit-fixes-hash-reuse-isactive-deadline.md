---
id: TASK-2
title: 'Audit fixes: hash reuse (H-1) + isActive deadline (M-1)'
status: Done
assignee: []
created_date: '2026-04-29 16:00'
labels:
  - security
  - audit
dependencies: []
references:
  - src/BridgeHTLC.sol
  - test/BridgeHTLC.t.sol
  - ~/Downloads/audit_agent_report_38_86658394-1709-41e5-8ce9-a7f7566badab.pdf
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nethermind AuditAgent (scan #38, 2026-04-29) reported 1 High + 3 Medium findings. Two require code fixes:

**H-1 — Hash reuse allows event replay and double-minting on 2D.**
After claim/refund sets `active = false`, the same sender can `lock()` again with the same hash, overwriting the Lock struct. An attacker can lock 1M, refund, re-lock 1 USDC with the same hash, then replay the old high-value Locked event to the 2D verifier (which only calls `isActive`). Fix: prevent lock ID reuse — check `locks[id].sender != address(0)` instead of `locks[id].active`.

**M-1 — `isActive()` reports expired locks as live.**
After deadline passes but before `refund()` is called, `isActive()` returns true even though `claim()` would revert. The 2D verifier could be misled. Fix: add `block.timestamp < l.deadline` to `isActive()`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 lock() reverts on reused hash (even after claim/refund), new error HashAlreadyUsed
- [x] #2 isActive() returns false when block.timestamp >= deadline
- [x] #3 Existing tests updated for new revert behavior
- [x] #4 New test: lock after refund with same hash reverts
- [x] #5 New test: lock after claim with same hash reverts
- [x] #6 New test: isActive returns false after deadline passes (without refund call)
- [x] #7 All 33 tests pass
<!-- AC:END -->
