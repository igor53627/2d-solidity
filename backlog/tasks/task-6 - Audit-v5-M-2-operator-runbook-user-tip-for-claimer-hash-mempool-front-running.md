---
id: TASK-6
title: >-
  Audit v5 M-2: operator runbook + user tip for (claimer, hash) mempool
  front-running
status: To Do
assignee: []
created_date: '2026-05-02 08:55'
labels:
  - security
  - audit
  - docs
  - ops
dependencies: []
references:
  - src/BridgeHTLC.sol
  - README.md
  - ~/pse/2d/docs/
  - ~/Downloads/audit_agent_report_42_f53b2e14-608d-40e5-ae29-9ccfdf0fd72c.pdf
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Nethermind AuditAgent scan #42 (2026-05-02) re-flagged the mempool front-running tradeoff introduced by the audit v4 H-1 fix as Medium severity. The contract-side disclosure already exists in README Trust model (added in PR #7), but the operational mitigations are not yet documented.

## Why no contract fix

Preventing operator double-spend (H-1) requires global `(claimer, hash)` admission uniqueness. Any such global check is by construction front-runnable from the mempool. Commit-reveal moves the front-run to the commit phase without solving it. Sender-binding the hash breaks the cross-chain HTLC contract with the 2D side. So mitigations must live at the operational layer.

## Costs the front-running attack imposes

1. **Victim:** failed `lock()` tx (gas) + delay; recovers by retrying with a fresh preimage.
2. **Operator:** if they naively open a 2D HTLC for the squatter's `Locked` event, they sink 2D-side capital and gas into an escrow that will never settle (squatter does not know the preimage). The honest victim retries with a different hash, so the operator opens a *second* 2D HTLC for the legitimate flow.
3. **Squatter:** gas + USDC opportunity cost for ≤24h; recovers via `refund()`.

The operator-cost dimension is what makes this Medium, not Low — squatter can grief operator capital cheaply.

## Deliverables

### 1. Operator runbook in `~/pse/2d/` (or 2d-docs)
- **Off-chain (sender, hash) pre-registration:** users submit an authenticated intent `(sender, hash, claimer, receiverOn2D, amount)` to the operator API/bot *before* calling `lock()`. Operator stores it. On `Locked` event, operator only opens the 2D HTLC if `(event.sender, event.hash, event.claimer, event.receiverOn2D, event.amount)` matches a pending intent.
- A squatter can copy the `hash` and `claimer` but not the victim's `sender` — squatter's lock arrives with `sender = squatter`, no matching intent → operator ignores the event, no 2D HTLC opened. Squatter eats the cost alone.
- Define intent expiry (e.g. 1 hour after registration; longer than typical inclusion latency, shorter than the lock deadline).
- Optional: require an EIP-712 signature on the intent so the operator can prove it received a specific user's request, in case of disputes.

### 2. README tip in `2d-solidity` (this repo)
Add to README — likely a new "Operational notes for users" section near Trust model:
- "If your `lock()` reverts with `HashAlreadyUsed`, regenerate the preimage and retry. The hash is now public."
- "For sensitive locks, submit the `lock()` tx via a private mempool (Flashbots Protect, MEV-Share, or similar) so the `(claimer, hash)` pair is not visible until inclusion."
- Cross-link to operator-side intent registration once that endpoint exists.

### 3. Update audit memory
After both deliverables land, mark M-2 as fully closed in `project_audit_status.md`.

## Out of scope

- Contract changes. Confirmed in PR #7 and re-confirmed during scan #42 review.
- A cross-chain ordering protocol (overengineered for this risk level).
- Forced private-mempool submission (cannot be enforced; remains user choice).

## Acceptance criteria

- [ ] Operator runbook in 2d repo describes the intent registration flow with an explicit "ignore unmatched (sender, hash, claimer, ...) Locked events" rule
- [ ] README in 2d-solidity has user-facing notes on retry-on-HashAlreadyUsed and private-mempool submission
- [ ] Once operator endpoint exists, README cross-links to it
- [ ] `project_audit_status.md` updated to reflect M-2 closed
<!-- SECTION:DESCRIPTION:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 forge test passes for the change
- [ ] #2 Regression tests cover public API behavior affected by the change
- [ ] #3 NatSpec and README reviewed for staleness against changed code
- [ ] #4 Final summary added before marking Done
<!-- DOD:END -->
