# 2d-solidity

Ethereum-side contracts for the [2D bridge](https://github.com/igor53627/2d). Currently one contract: `BridgeHTLC`.

## BridgeHTLC

USDC-based HTLC that settles cross-chain swaps between Ethereum and 2D via preimage reveal. No validator federation, no multisig unlock, no wrapped tokens.

### How it works

```
Ethereum                              2D chain
────────                              ────────
Alice ──lock(H, receiver, amt, dl)──▸ HTLC
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
        HTLC ◂──claim(H, P)── Operator (preimage now public)
```

**Bridge-in** (Ethereum → 2D):

1. Alice calls `lock(hash, receiverOn2D, amount, deadline)` -- USDC goes into escrow
2. Operator waits for Ethereum finality (~12-15 min)
3. Operator mints USD-stable on 2D and locks it in the 2D HTLC for Alice
4. Alice claims on 2D by revealing the preimage
5. Operator uses the revealed preimage to `claim` the original USDC on Ethereum

If the operator never locks on 2D, Alice calls `refund(hash)` after the deadline and gets her USDC back.

### Key design choice: `receiverOn2D`

The `Locked` event includes the intended 2D recipient address:

```solidity
event Locked(
    bytes32 indexed hash,
    address indexed sender,
    address indexed receiverOn2D,
    uint256 amount,
    uint256 deadline
);
```

This lets the 2D verifier cross-check that the operator's lock on the 2D side actually routes funds to the right person. Without this field, a compromised operator could lock to an attacker-controlled address instead.

### `isActive` view

```solidity
function isActive(bytes32 hash) external view returns (bool);
```

Returns whether a lock is still active (not yet claimed or refunded). The 2D verifier queries this to confirm that a `refill_mint` references a lock that hasn't already been settled.

### Functions

| Function | Who calls | What it does |
|---|---|---|
| `lock(hash, claimer, receiverOn2D, amount, deadline)` | User | Escrows USDC under hash H; binds claim right to `claimer` |
| `claim(hash, preimage)` | Claimer only | Reveals preimage, receives USDC |
| `refund(hash)` | Anyone | Returns USDC to sender after deadline |
| `isActive(hash)` | Verifier | View: is the lock still live? |

### Protections (see [PR #1](https://github.com/igor53627/2d-solidity/pull/1))

- **UUPS proxy** -- upgradeable, owner should be a TimelockController
- **Anti-griefing** -- `MIN_LOCK_AMOUNT = 1 USDC`, `MIN_DEADLINE_DURATION = 1 hour`
- **Anti-frontrunning** -- `claimer` bound at lock time; `claim()` enforces `msg.sender == claimer`
- **ReentrancyGuard** + **SafeERC20** -- defense-in-depth

### Trust model

- **No unlock authority.** Funds leave the contract only via `claim(preimage)` (correct preimage + authorized claimer required) or `refund` (deadline must have passed).
- **Operator key compromise:** cannot steal locked USDC (no `unlock` function, and claim is bound to the designated claimer). Can refuse to complete swaps (DoS). Users refund after deadline.
- **Preimage is the only key.** Whoever knows the preimage can claim. The 2D chain publishes the preimage when Alice claims there, so the operator picks it up from on-chain data.

## Build and test

Requires [Foundry](https://book.getfoundry.sh/).

```bash
forge build
forge test -vv
```

17 tests: lock, claim, refund, isActive, all revert cases, event emission, balance conservation.

## Related

- [2D chain](https://github.com/igor53627/2d) -- the L1 that this contract bridges to
- [2D docs](https://igor53627.github.io/2d-docs/architecture/bridge/) -- bridge architecture article

## License

MIT
