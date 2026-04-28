// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BridgeHTLC — HTLC for the 2D bridge (Ethereum side)
/// @notice Users lock USDC under a hash+deadline. The operator claims with
///         the preimage after the 2D side settles. If unclaimed, the user
///         refunds after the deadline.
///
///         UUPS-upgradeable. Owner should be a TimelockController.
contract BridgeHTLC is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 public constant MIN_LOCK_AMOUNT = 1e6; // 1 USDC (6 decimals)
    uint256 public constant MIN_DEADLINE_DURATION = 1 hours;

    struct Lock {
        address sender;
        address claimer;
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
    error AmountTooSmall();
    error ZeroAddress();
    error DeadlineTooSoon();
    error NotClaimer();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token, address _owner) external initializer {
        __Ownable_init(_owner);
        token = IERC20(_token);
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Lock `amount` USDC under `hash` for bridge-in to 2D.
    /// @param claimer The only address allowed to claim (typically the bridge operator)
    function lock(
        bytes32 hash,
        address claimer,
        address receiverOn2D,
        uint256 amount,
        uint256 deadline
    ) external nonReentrant {
        if (locks[hash].active) revert AlreadyLocked();
        if (amount < MIN_LOCK_AMOUNT) revert AmountTooSmall();
        if (claimer == address(0)) revert ZeroAddress();
        if (receiverOn2D == address(0)) revert ZeroAddress();
        if (deadline < block.timestamp + MIN_DEADLINE_DURATION) revert DeadlineTooSoon();

        locks[hash] = Lock({
            sender: msg.sender,
            claimer: claimer,
            receiverOn2D: receiverOn2D,
            amount: amount,
            deadline: deadline,
            active: true
        });

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(hash, msg.sender, receiverOn2D, amount, deadline);
    }

    /// @notice Authorized claimer reveals preimage and receives USDC.
    function claim(bytes32 hash, bytes32 preimage) external nonReentrant {
        Lock storage l = locks[hash];
        if (!l.active) revert NotActive();
        if (msg.sender != l.claimer) revert NotClaimer();
        if (block.timestamp >= l.deadline) revert DeadlinePassed();
        if (sha256(abi.encodePacked(preimage)) != hash) revert InvalidPreimage();

        l.active = false;
        token.safeTransfer(l.claimer, l.amount);

        emit Claimed(hash, preimage);
    }

    /// @notice Sender refunds after deadline passes without a claim.
    function refund(bytes32 hash) external nonReentrant {
        Lock storage l = locks[hash];
        if (!l.active) revert NotActive();
        if (block.timestamp < l.deadline) revert DeadlineNotPassed();

        l.active = false;
        token.safeTransfer(l.sender, l.amount);

        emit Refunded(hash);
    }

    /// @notice View: is the lock still active and claimable?
    function isActive(bytes32 hash) external view returns (bool) {
        return locks[hash].active;
    }
}
