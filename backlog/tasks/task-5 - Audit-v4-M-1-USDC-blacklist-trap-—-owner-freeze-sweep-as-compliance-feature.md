---
id: TASK-5
title: 'Audit v4 M-1: USDC blacklist trap — owner freeze/sweep as compliance feature'
status: To Do
assignee: []
created_date: '2026-05-02 06:42'
labels:
  - security
  - audit
  - compliance
dependencies: []
references:
  - src/BridgeHTLC.sol
  - test/BridgeHTLC.t.sol
  - ~/Downloads/audit_agent_report_41_651273d2-eb81-4585-9ebd-3634bb517a8e.pdf
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nethermind AuditAgent scan #41 (2026-05-01) reported a Medium-severity finding: USDC blacklist permanently traps locked funds.

## Problem

USDC (Circle's FiatTokenV2) implements a `blacklist` mapping that Circle/OFAC can apply to any address. If a lock's `sender` is added to the blacklist **after** locking, the funds become permanently irrecoverable:

- `refund()` calls `token.safeTransfer(l.sender, l.amount)` — USDC reverts on transfer to a blacklisted recipient. The whole tx reverts, rolling back `l.active = false`. The lock stays perpetually active.
- `claim()` is gated by `block.timestamp < l.deadline` — once the deadline passes without a claim, the claim window is permanently closed. So even if the operator wanted to rescue, they cannot.
- There is no `sweep`, `recoverTokens`, or admin recovery path. Funds are stranded forever.

This applies to any user whose Ethereum address is sanctioned, blacklisted by Circle's discretion, or otherwise added to the USDC blacklist between `lock()` and `refund()`.

## Decision: treat as compliance feature, not just bugfix

Instead of a passive emergency rescue, we want a **deliberate compliance freeze**:

- An owner-only (timelock-gated) `freeze(address sender, bytes32 hash)` that marks a specific lock as frozen — neither claimable nor refundable through normal paths.
- An owner-only `sweepFrozen(address sender, bytes32 hash, address destination)` that transfers the locked USDC to a designated compliance address (e.g., Circle's recovery address, or a multisig holding cell awaiting OFAC determination).
- Frozen state is publicly visible (event + view) so the 2D verifier can refuse to settle frozen locks.

This gives the protocol a defensible posture: locks can be frozen only by timelock action, and the destination is constrained or transparent.

## Open design questions for auditors

1. **Should `sweepFrozen` allow arbitrary `destination`, or only a pre-set `complianceAddress` configurable by timelock?** Arbitrary destination = more flexible but bigger trust surface. Fixed destination = harder to abuse but requires governance turn for each new compliance scenario. Lean: configurable `complianceAddress` setter + sweep always sends there.
2. **Should `freeze` work pre-deadline as well, or only post-deadline (when refund would otherwise be the only path)?** Pre-deadline freeze gives faster compliance response but lets owner steal an honest user's funds before they have time to claim/refund. Post-deadline only is safer but slower. Lean: post-deadline only, OR pre-deadline with a freeze-delay window during which user can still claim.
3. **Should `freeze` be reversible (`unfreeze`)?** If a user is removed from the blacklist before sweep, can the lock be restored? Lean: yes, `unfreeze` allowed before `sweepFrozen` is called.
4. **2D verifier interaction.** If a lock is frozen on Ethereum after the operator already opened the corresponding 2D HTLC, the operator must also be able to refund/cancel on 2D. Need to specify this off-chain workflow.
5. **Storage layout.** New fields will need to fit in `__gap` (currently 43 slots after audit v4 H-1). Plan: `mapping(bytes32 => bool) frozen`, `address complianceAddress`. Two slots — `__gap` 43 → 41.
6. **Events.** `Frozen(hash, sender)`, `Unfrozen(hash, sender)`, `SweptFrozen(hash, sender, destination, amount)`, `ComplianceAddressUpdated(old, new)`.
7. **NatSpec / user-facing docs.** Users must be told upfront that owner (timelock) can freeze and sweep their lock under compliance circumstances. This is a trust-model change vs the current "no unlock authority" guarantee in README.md:86.

## Out of scope for this task

- Changes to `claim()` / `refund()` aside from the frozen-state guard.
- Cross-chain coordination with the 2D verifier (separate task in `2d` repo).

## Audit v4 — other findings (already handled)

- H-1 (claimer/hash uniqueness): fixed on branch `fix/audit-v4-h1-claimer-hash-uniqueness`, PR pending.
- I-1 (`__gap` "unused"): false positive, standard OZ upgradeable storage pattern. No action.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner-only (timelock) freeze(sender, hash) marks a specific lock frozen, with event
- [ ] #2 Owner-only sweepFrozen(sender, hash) transfers the locked USDC to a compliance destination, with event
- [ ] #3 claim() and refund() revert when the lock is frozen
- [ ] #4 Frozen state is queryable (view) so the 2D verifier can refuse to settle frozen locks
- [ ] #5 isActive() returns false when frozen
- [ ] #6 Storage layout: new fields placed before __gap; __gap reduced accordingly
- [ ] #7 Trust-model section in README.md updated to disclose freeze authority
- [ ] #8 NatSpec on freeze/sweep functions explains compliance use case
- [ ] #9 Tests cover: freeze blocks claim, freeze blocks refund, sweep moves funds, only owner can freeze/sweep, frozen lock cannot be re-locked under same (claimer, hash)
- [ ] #10 All existing tests still pass
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 forge test passes for the change
- [ ] #2 Regression tests cover public API behavior affected by the change
- [ ] #3 NatSpec and README reviewed for staleness against changed code
- [ ] #4 Final summary added before marking Done
<!-- DOD:END -->
