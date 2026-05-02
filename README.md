# 2d-solidity

Ethereum-side contracts for the [2D bridge](https://github.com/igor53627/2d). Currently one contract: `BridgeHTLC`.

## BridgeHTLC

USDC-based HTLC that settles cross-chain swaps between Ethereum and 2D via preimage reveal. UUPS-upgradeable (owner should be a TimelockController). No validator federation, no multisig unlock, no wrapped tokens.

### How it works

```
Ethereum                              2D chain
────────                              ────────
Alice ──lock(H, claimer, receiver, amt, dl)──▸ HTLC
                                       │
                    Operator sees Locked event at finality
                                       │
                                       ▾
                              Operator mints + locks
                              USD-stable for Alice on 2D
                                       │
                    Alice claims on 2D with preimage P
                                       │
                                       ▾
        HTLC ◂──claim(sender, H, P)── Operator (preimage now public)
```

**Bridge-in** (Ethereum → 2D):

1. Alice calls `lock(hash, claimer, receiverOn2D, amount, deadline)` -- USDC goes into escrow, only `claimer` (the operator) can claim
2. Operator waits for Ethereum finality (~12-15 min)
3. Operator mints USD-stable on 2D and locks it in the 2D HTLC for Alice
4. Alice claims on 2D by revealing the preimage
5. Operator uses the revealed preimage to `claim` the original USDC on Ethereum

If the operator never locks on 2D, anyone can call `refund(sender, hash)` after the deadline — USDC returns to the original sender.

### Key design choices

**`claimer` (anti-front-running).** Each lock binds claim rights to a specific address (the operator). Third parties who discover the preimage cannot front-run the claim. The `claimer` is the third indexed topic in the `Locked` event.

**`receiverOn2D`.** The `Locked` event includes the intended 2D recipient address (non-indexed). The 2D verifier cross-checks that the operator's lock on the 2D side routes funds to the correct person.

```solidity
event Locked(
    bytes32 indexed hash,
    address indexed sender,
    address indexed claimer,
    address receiverOn2D,
    uint256 amount,
    uint256 deadline
);
```

### `isActive` view

```solidity
function isActive(address sender, bytes32 hash) external view returns (bool);
```

Returns whether a lock is still active and claimable — i.e. not yet claimed, not yet refunded, not past its deadline, and the claimer has not already used this hash on another lock. The 2D verifier queries this to confirm that a `refill_mint` references a lock that is still settleable.

### Functions

| Function | Who calls | What it does |
|---|---|---|
| `lock(hash, claimer, receiverOn2D, amount, deadline)` | User | Escrows USDC under hash H; binds claim right to `claimer` |
| `claim(sender, hash, preimage)` | Claimer only | Reveals preimage, receives USDC (preimage single-use per claimer) |
| `refund(sender, hash)` | Anyone | Returns USDC to sender after deadline |
| `isActive(sender, hash)` | Verifier | View: is the lock still claimable? |
| `setMinLockAmount(amount)` | Owner | Update minimum lock amount |
| `setMinDeadlineDuration(duration)` | Owner | Update minimum deadline duration (must be < max) |
| `setMaxDeadlineDuration(duration)` | Owner | Update maximum deadline duration (must be > min, capped at `MAX_DEADLINE_DURATION_CAP` = 365 days) |

### Protections

- **UUPS proxy** -- upgradeable, owner should be a TimelockController
- **Sender-namespaced locks** -- storage key is `keccak256(sender, hash)`, prevents hash-squatting against the victim's own slot
- **`(claimer, hash)` uniqueness** -- only one active lock may exist per `(claimer, hash)` pair, and a hash consumed by a claim can never be reused for that claimer; prevents an attacker from cloning a victim's hash under the same operator and farming the preimage on the destination chain
- **Anti-griefing** -- governance-configurable: `minLockAmount` (default 1 USDC), `minDeadlineDuration` (default 1 hour), `maxDeadlineDuration` (default 24 hours, hard-capped at 365 days). Owner can adjust via setters
- **Anti-frontrunning** -- `claimer` bound at lock time; `claim()` enforces `msg.sender == claimer`
- **Single-use preimages** -- each claimer can use a preimage only once; prevents operator from sweeping multiple locks that share a preimage
- **ReentrancyGuardTransient** + **SafeERC20** -- defense-in-depth

### Trust model

- **No unlock authority.** Funds leave the contract only via `claim(preimage)` (correct preimage + authorized claimer required) or `refund` (deadline must have passed).
- **Operator key compromise:** cannot steal locked USDC (no `unlock` function, and claim is bound to the designated claimer). Can refuse to complete swaps (DoS). Users refund after deadline.
- **Preimage is the only key.** The first valid claim consumes the preimage for that claimer. The 2D chain publishes the preimage when Alice claims there, so the operator picks it up from on-chain data.
- **Mempool griefing.** A mempool observer can copy a victim's pending `(claimer, hash)` and submit a minimum-amount lock first, causing the victim's `lock()` to revert with `HashAlreadyUsed`. The griefer's funds are escrowed (claimable only with the victim's unrevealed preimage) and recovered via `refund()` after the deadline. To recover, the victim picks a fresh preimage and retries — this cannot permanently block bridging, only delay it.

### Operational notes for users

- **`HashAlreadyUsed` after a pending tx:** generate a fresh preimage and retry. The old hash is now public and can never be reused under the same operator (see "(claimer, hash) uniqueness").
- **Sensitive flows: submit `lock()` privately.** Use a private-mempool relay (Flashbots Protect, MEV-Share, or your operator's intent endpoint) so the `(claimer, hash)` pair is not visible until inclusion. This eliminates the front-run window without changing contract behavior.
- **Pre-registering an intent with the operator** (when available): the bridge operator may expose an EIP-712 intent endpoint where you sign and pre-register `(sender, hash, claimer, receiverOn2D, amount, deadline)` *before* broadcasting `lock()`. The operator only opens the destination-side HTLC for events that match a registered intent, so a squatter who copies `hash` and `claimer` from your pending tx (but not your `sender`) is ignored. See the operator runbook in the [2D chain repository](https://github.com/igor53627/2d) for the current intent schema and endpoint.

## Build and test

Requires [Foundry](https://book.getfoundry.sh/).

```bash
forge build
forge test -vv
```

Comprehensive tests covering lock, claim, refund, isActive, all revert cases, event emission, balance conservation, and upgrade persistence.

### Deploy

Deploys TimelockController + BridgeHTLC (implementation + proxy). The proposer is both proposer and executor on the timelock.

```bash
# Testnet (EOA as proposer, 1 min delay)
USDC_ADDRESS=0x... \
PROPOSER_ADDRESS=0x<your-eoa> \
TIMELOCK_DELAY=60 \
forge script script/DeployBridgeHTLC.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Mainnet (Safe multisig as proposer, 48h delay)
USDC_ADDRESS=0x... \
PROPOSER_ADDRESS=0x<safe-multisig> \
TIMELOCK_DELAY=172800 \
forge script script/DeployBridgeHTLC.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Post-deploy checks run automatically: owner == timelock, token == USDC, governance params initialized.

**Production deploys must use the multisig as proposer from genesis.** The timelock is constructed with `admin=address(0)`, so DEFAULT_ADMIN_ROLE is held only by the timelock itself — any role change must go through `schedule()` → delay → `execute()` on the timelock. Worse, an EOA proposer can `cancel()` its own pending removal between schedule and execute, so post-hoc EOA→multisig migration is not a security boundary.

## Security

- [Formal invariants](audit/INVARIANTS.md) -- 17 properties the contract must preserve

## Related

- [2D chain](https://github.com/igor53627/2d) -- the L1 that this contract bridges to
- [2D docs](https://igor53627.github.io/2d-docs/architecture/bridge/) -- bridge architecture article

## License

MIT
