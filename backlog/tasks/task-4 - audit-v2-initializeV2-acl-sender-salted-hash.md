---
id: TASK-4
title: 'Audit v2 fixes: initializeV2 ACL + sender-salted hash'
status: Done
assignee: []
created_date: '2026-05-01 12:00'
labels:
  - security
  - audit
dependencies: []
references:
  - src/BridgeHTLC.sol
  - test/BridgeHTLC.t.sol
  - ~/Downloads/audit_agent_report_39_50fc10b7-8b5e-4752-bc86-d4a8208d1818.pdf
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nethermind AuditAgent scan #39 (2026-04-30) reported 2 Medium findings:

**M-1 — initializeV2() has no access control.**
Anyone can call it to reset governance params to defaults and consume the reinitializer(2) slot, bricking the planned upgrade path. Fix: add `onlyOwner`.

**M-2 — Hash reuse across senders lets claimer drain unrelated escrows.**
Different senders can lock with the same hash. Revealing the preimage on 2D for one lock makes it valid for all. Fix: `usedPreimages` mapping — each preimage can only be used once across all locks. Operator can claim at most one lock per preimage; other senders can refund after deadline.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 initializeV2() has onlyOwner modifier
- [x] #2 claim() rejects already-used preimages via usedPreimages mapping
- [x] #3 New test: non-owner calling initializeV2 reverts
- [x] #4 New test: operator cannot sweep second lock with same preimage, victim refunds
- [x] #5 All 54 tests pass
<!-- AC:END -->
