// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @title BridgeHTLC — HTLC for the 2D bridge (Ethereum side)
/// @notice Users lock USDC under a hash+deadline. The operator claims with
///         the preimage after the 2D side settles. If unclaimed, the user
///         refunds after the deadline.
///
///         UUPS-upgradeable. Owner should be a TimelockController.
contract BridgeHTLC is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 public constant MIN_LOCK_AMOUNT = 1e6; // 1 USDC (6 decimals)
    uint256 public constant MIN_DEADLINE_DURATION = 1 hours;

    struct Lock {
        address sender;
        address receiverOn2D;
        uint256 amount;
        uint256 deadline;
        bool active;
        address claimer;
    }

    mapping(bytes32 => Lock) public locks;

    event Locked(
        bytes32 indexed hash,
        address indexed sender,
        address indexed claimer,
        address receiverOn2D,
        uint256 amount,
        uint256 deadline
    );

    event Claimed(bytes32 indexed hash, address indexed sender, bytes32 preimage);
    event Refunded(bytes32 indexed hash, address indexed sender);

    error AlreadyLocked();
    error NotActive();
    error DeadlineNotPassed();
    error DeadlinePassed();
    error InvalidPreimage();
    error AmountTooSmall();
    error ZeroClaimerAddress();
    error ZeroReceiverAddress();
    error ZeroTokenAddress();
    error DeadlineTooSoon();
    error NotClaimer();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token, address _owner) external initializer {
        if (_token == address(0)) revert ZeroTokenAddress();
        __Ownable_init(_owner);
        token = IERC20(_token);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _lockId(address sender, bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender, hash));
    }

    /// @notice Lock `amount` USDC under `hash` for bridge-in to 2D.
    /// @param hash         sha256(preimage) — the hashlock
    /// @param claimer      The only address allowed to claim (typically the bridge operator)
    /// @param receiverOn2D The intended recipient address on the 2D chain
    /// @param amount       USDC amount (6 decimals)
    /// @param deadline     Unix timestamp after which sender can refund
    function lock(bytes32 hash, address claimer, address receiverOn2D, uint256 amount, uint256 deadline)
        external
        nonReentrant
    {
        bytes32 id = _lockId(msg.sender, hash);
        if (locks[id].active) revert AlreadyLocked();
        if (amount < MIN_LOCK_AMOUNT) revert AmountTooSmall();
        if (claimer == address(0)) revert ZeroClaimerAddress();
        if (receiverOn2D == address(0)) revert ZeroReceiverAddress();
        if (deadline < block.timestamp + MIN_DEADLINE_DURATION) revert DeadlineTooSoon();

        locks[id] = Lock({
            sender: msg.sender,
            claimer: claimer,
            receiverOn2D: receiverOn2D,
            amount: amount,
            deadline: deadline,
            active: true
        });

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(hash, msg.sender, claimer, receiverOn2D, amount, deadline);
    }

    /// @notice Authorized claimer reveals preimage and receives USDC.
    /// @param sender The address that created the lock
    /// @param hash   The hashlock
    /// @param preimage The preimage such that sha256(preimage) == hash
    function claim(address sender, bytes32 hash, bytes32 preimage) external nonReentrant {
        bytes32 id = _lockId(sender, hash);
        Lock storage l = locks[id];
        if (!l.active) revert NotActive();
        if (msg.sender != l.claimer) revert NotClaimer();
        if (block.timestamp >= l.deadline) revert DeadlinePassed();
        if (sha256(abi.encodePacked(preimage)) != hash) revert InvalidPreimage();

        l.active = false;
        token.safeTransfer(msg.sender, l.amount);

        emit Claimed(hash, sender, preimage);
    }

    /// @notice Anyone can refund after deadline passes without a claim.
    /// @param sender The address that created the lock
    /// @param hash   The hashlock
    function refund(address sender, bytes32 hash) external nonReentrant {
        bytes32 id = _lockId(sender, hash);
        Lock storage l = locks[id];
        if (!l.active) revert NotActive();
        if (block.timestamp < l.deadline) revert DeadlineNotPassed();

        l.active = false;
        token.safeTransfer(l.sender, l.amount);

        emit Refunded(hash, sender);
    }

    /// @notice View: is the lock still active and claimable?
    /// @param sender The address that created the lock
    /// @param hash   The hashlock
    function isActive(address sender, bytes32 hash) external view returns (bool) {
        return locks[_lockId(sender, hash)].active;
    }

    uint256[48] private __gap;
}
