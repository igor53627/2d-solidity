// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @title BridgeHTLC — HTLC for the 2D bridge (Ethereum side)
/// @notice Users lock USDC under a hash+deadline. The operator claims with
///         the preimage after the 2D side settles. If unclaimed, the user
///         refunds after the deadline.
///
///         The Locked event includes `receiverOn2D` so the 2D verifier can
///         cross-check that the operator's 2D-side HTLC lock routes funds
///         to the correct recipient (Plan B: combined refill+lock).
contract BridgeHTLC {
    IERC20 public immutable token;

    struct Lock {
        address sender;
        address receiverOn2D;
        uint256 amount;
        uint256 deadline;
        bool active;
    }

    mapping(bytes32 => Lock) public locks;

    event Locked(
        bytes32 indexed hash,
        address indexed sender,
        address indexed receiverOn2D,
        uint256 amount,
        uint256 deadline
    );

    event Claimed(bytes32 indexed hash, bytes32 preimage);
    event Refunded(bytes32 indexed hash);

    error AlreadyLocked();
    error NotActive();
    error DeadlineNotPassed();
    error DeadlinePassed();
    error InvalidPreimage();
    error ZeroAmount();
    error ZeroAddress();

    constructor(address _token) {
        token = IERC20(_token);
    }

    /// @notice Lock `amount` USDC under `hash` for bridge-in to 2D.
    /// @param hash         sha256(preimage) — the hashlock
    /// @param receiverOn2D The intended recipient address on the 2D chain
    /// @param amount       USDC amount (6 decimals)
    /// @param deadline     Unix timestamp after which sender can refund
    function lock(
        bytes32 hash,
        address receiverOn2D,
        uint256 amount,
        uint256 deadline
    ) external {
        if (locks[hash].active) revert AlreadyLocked();
        if (amount == 0) revert ZeroAmount();
        if (receiverOn2D == address(0)) revert ZeroAddress();

        locks[hash] = Lock({
            sender: msg.sender,
            receiverOn2D: receiverOn2D,
            amount: amount,
            deadline: deadline,
            active: true
        });

        token.transferFrom(msg.sender, address(this), amount);

        emit Locked(hash, msg.sender, receiverOn2D, amount, deadline);
    }

    /// @notice Operator claims locked USDC by revealing the preimage.
    /// @param hash     The hashlock
    /// @param preimage The preimage such that sha256(preimage) == hash
    function claim(bytes32 hash, bytes32 preimage) external {
        Lock storage l = locks[hash];
        if (!l.active) revert NotActive();
        if (block.timestamp >= l.deadline) revert DeadlinePassed();
        if (sha256(abi.encodePacked(preimage)) != hash) revert InvalidPreimage();

        l.active = false;
        token.transfer(msg.sender, l.amount);

        emit Claimed(hash, preimage);
    }

    /// @notice Sender refunds after deadline passes without a claim.
    /// @param hash The hashlock
    function refund(bytes32 hash) external {
        Lock storage l = locks[hash];
        if (!l.active) revert NotActive();
        if (block.timestamp < l.deadline) revert DeadlineNotPassed();

        l.active = false;
        token.transfer(l.sender, l.amount);

        emit Refunded(hash);
    }

    /// @notice View: is the lock still active and claimable?
    /// @param hash The hashlock
    function isActive(bytes32 hash) external view returns (bool) {
        return locks[hash].active;
    }
}
