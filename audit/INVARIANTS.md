# Invariants

## src/BridgeHTLC.sol

### 1. Lock IDs are sender-namespaced and deterministic (prevents hash-squatting across senders).

**Function:** `Contract-wide`

```solidity
For all sender,hash: lockId == keccak256(abi.encode(sender, hash)) and all state transitions for a lock only ever read/write locks[keccak256(abi.encode(sender,hash))].
```

### 2. A lock ID can be created at most once (ever-used sentinel).

**Function:** `lock()`

```solidity
If locks[id].sender != address(0) then lock(id) must always revert; once locks[id].sender is set nonzero it is never reset to zero across all future calls/upgrades.
```

### 3. Active lock state is coherent: any active lock must have fully-initialized, nonzero critical fields and a positive amount.

**Function:** `Contract-wide`

```solidity
If locks[id].active == true then locks[id].sender != address(0) AND locks[id].claimer != address(0) AND locks[id].receiverOn2D != address(0) AND locks[id].amount > 0 AND locks[id].deadline > 0.
```

### 4. Governance parameters remain internally consistent.

**Function:** `Contract-wide`

```solidity
minLockAmount > 0 AND minDeadlineDuration > 0 AND maxDeadlineDuration > 0 AND minDeadlineDuration < maxDeadlineDuration always holds after initialization and after any setter call. Note: initializeV2() enforces this by construction (hardcoded 1e6/1h/24h), not via a runtime guard.
```

### 5. Only owner can change governance parameters, authorize upgrades, and reinitialize; non-owners can never change them.

**Function:** `setMinLockAmount()/setMinDeadlineDuration()/setMaxDeadlineDuration()/_authorizeUpgrade()/initializeV2()`

```solidity
If msg.sender != owner() then these calls must revert; if they succeed then msg.sender == owner().
```

### 6. Single-settlement property: each lock can be settled at most once, and settlement always deactivates it.

**Function:** `claim()/refund()`

```solidity
For any id: locks[id].active can transition true -> false at most once; after a successful claim or refund, locks[id].active == false forever and subsequent claim/refund on same id must revert with NotActive.
```

### 7. Claim access control: only the designated claimer can claim a lock.

**Function:** `claim()`

```solidity
If msg.sender != locks[id].claimer then claim must revert with NotClaimer. No other address can trigger settlement via claim, regardless of preimage knowledge.
```

### 8. Preimage correctness: claim requires a valid preimage matching the hash.

**Function:** `claim()`

```solidity
If sha256(abi.encodePacked(preimage)) != hash then claim must revert with InvalidPreimage. The hash is the commitment; the preimage is the only key.
```

### 9. Temporal separation: claim and refund have non-overlapping time windows.

**Function:** `claim()/refund()`

```solidity
claim() succeeds only when block.timestamp < deadline; refund() succeeds only when block.timestamp >= deadline. At any given timestamp, at most one of the two settlement paths is available.
```

### 10. Single-use-per-claimer-per-hash: a claimer cannot claim two locks that share the same hash (even across different senders).

**Function:** `claim()`

```solidity
If claimerUsedHash[claimer][hash] == true then any subsequent claim by that claimer for that hash must revert; if claim succeeds then claimerUsedHash[msg.sender][hash] becomes true and never returns to false.
```

### 11. isActive is consistent with claimability: returns true if and only if the lock could be claimed.

**Function:** `isActive()`

```solidity
isActive(sender, hash) == true iff locks[id].active == true AND block.timestamp < locks[id].deadline AND !claimerUsedHash[locks[id].claimer][hash]. Note: isActive does not check the caller — it reports whether the lock is claimable by its designated claimer, not by any arbitrary address.
```

### 12. Conservation of escrowed tokens per lock: settlement transfers exactly the locked amount to the correct recipient and does not change lock.amount.

**Function:** `claim()/refund()`

```solidity
On successful claim: token balance of msg.sender increases by exactly locks[id].amount and contract balance decreases by same; on successful refund: token balance of locks[id].sender increases by exactly locks[id].amount and contract balance decreases by same; locks[id].amount is not modified by claim/refund.
```

### 13. No administrative drain path: owner actions must not directly transfer locked user funds (only claim/refund can move escrow).

**Function:** `Contract-wide`

```solidity
Across all externally callable functions, the only token outflows from the contract are in claim() to locks[id].claimer and refund() to locks[id].sender, each for locks[id].amount, and only when locks[id].active was true.
```

### 14. Initialization safety for upgradeable deployment: token address is nonzero and initialization cannot be replayed to change token.

**Function:** `initialize()/initializeV2()/constructor`

```solidity
initialize can be executed at most once (initializer); initializeV2 can be executed at most once (reinitializer(2)) and only by owner. After successful initialize, token != address(0) forever (no function changes token; initializeV2 only resets governance params). Constructor disables initializers on the implementation contract.
```

### 15. Refund is permissionless: anyone can trigger a refund after deadline, but funds always go to the original sender.

**Function:** `refund()`

```solidity
refund(sender, hash) has no msg.sender restriction. On success, tokens are always transferred to locks[id].sender, never to msg.sender. This is by design — allows relayers or third parties to trigger refunds on behalf of users.
```

### 16. Reentrancy protection: all state-mutating entry points are guarded.

**Function:** `lock()/claim()/refund()`

```solidity
All three functions carry nonReentrant (ReentrancyGuardTransient, EIP-1153 transient storage). State changes (locks[id].active = false, claimerUsedHash write) occur before external calls (safeTransfer/safeTransferFrom), following checks-effects-interactions.
```

### 17. (claimer, hash) lock-time uniqueness: at most one active lock per (claimer, hash); a claimed (claimer, hash) is permanently retired.

**Function:** `lock()/claim()/refund()`

```solidity
Lock-time precondition: lock(hash, claimer, ...) reverts with HashAlreadyUsed when claimerHashLocked[claimer][hash] == true OR claimerUsedHash[claimer][hash] == true.

Lifecycle of claimerHashLocked[claimer][hash]: false -> true on a successful lock() with that (claimer, hash); true -> false on a successful claim() or refund() of that lock; otherwise unchanged. claimerUsedHash, in contrast, is monotonic (see #10).

Together with #10, this ensures that for any (claimer, hash) at most one lock can ever reach claim(): concurrent admission is blocked at lock-time, and post-claim re-admission is blocked permanently by claimerUsedHash.
```
