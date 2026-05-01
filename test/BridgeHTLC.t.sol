// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BridgeHTLC} from "../src/BridgeHTLC.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract BridgeHTLCTest is Test {
    BridgeHTLC htlc;
    MockERC20 usdc;

    address alice = makeAddr("alice");
    address operator = makeAddr("operator");
    address aliceOn2D = makeAddr("aliceOn2D");
    address owner = makeAddr("owner");

    bytes32 preimage = bytes32(uint256(42));
    bytes32 hash = sha256(abi.encodePacked(preimage));

    uint256 amount = 1000e6; // 1000 USDC
    uint256 deadline;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);

        BridgeHTLC impl = new BridgeHTLC();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(BridgeHTLC.initialize, (address(usdc), owner)));
        htlc = BridgeHTLC(address(proxy));

        deadline = block.timestamp + 2 hours;

        usdc.mint(alice, 10_000e6);
        vm.prank(alice);
        usdc.approve(address(htlc), type(uint256).max);
    }

    // ── lock ────────────────────────────────────────────────

    function test_lock_happy_path() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        assertTrue(htlc.isActive(alice, hash));
        assertEq(usdc.balanceOf(address(htlc)), amount);
        assertEq(usdc.balanceOf(alice), 10_000e6 - amount);
    }

    function test_lock_emits_event_with_claimer_and_receiverOn2D() public {
        vm.expectEmit(true, true, true, true);
        emit BridgeHTLC.Locked(hash, alice, operator, aliceOn2D, amount, deadline);

        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);
    }

    function test_lock_duplicate_hash_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectRevert(BridgeHTLC.HashAlreadyUsed.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);
    }

    function test_lock_same_hash_different_sender_succeeds() public {
        address bob = makeAddr("bob");
        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(htlc), type(uint256).max);

        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(bob);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        assertTrue(htlc.isActive(alice, hash));
        assertTrue(htlc.isActive(bob, hash));
    }

    function test_lock_below_minimum_reverts() public {
        vm.expectRevert(BridgeHTLC.AmountTooSmall.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, 999_999, deadline); // < 1 USDC
    }

    function test_lock_zero_claimer_reverts() public {
        vm.expectRevert(BridgeHTLC.ZeroClaimerAddress.selector);
        vm.prank(alice);
        htlc.lock(hash, address(0), aliceOn2D, amount, deadline);
    }

    function test_lock_zero_receiver_reverts() public {
        vm.expectRevert(BridgeHTLC.ZeroReceiverAddress.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, address(0), amount, deadline);
    }

    function test_lock_deadline_too_soon_reverts() public {
        vm.expectRevert(BridgeHTLC.DeadlineTooSoon.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, block.timestamp + 30 minutes);
    }

    function test_lock_deadline_exactly_min_succeeds() public {
        uint256 exactMin = block.timestamp + 1 hours;
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, exactMin);
        assertTrue(htlc.isActive(alice, hash));
    }

    function test_lock_deadline_too_far_reverts() public {
        vm.expectRevert(BridgeHTLC.DeadlineTooFar.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, block.timestamp + 25 hours);
    }

    function test_lock_deadline_exactly_max_succeeds() public {
        uint256 exactMax = block.timestamp + 24 hours;
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, exactMax);
        assertTrue(htlc.isActive(alice, hash));
    }

    // ── anti-griefing ──────────────────────────────────────

    function test_hash_squatting_does_not_block_victim() public {
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 10e6);
        vm.prank(attacker);
        usdc.approve(address(htlc), type(uint256).max);

        // attacker front-runs with same hash
        vm.prank(attacker);
        htlc.lock(hash, attacker, attacker, 1e6, deadline);

        // alice's lock still succeeds — different sender namespace
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        assertTrue(htlc.isActive(alice, hash));
        assertTrue(htlc.isActive(attacker, hash));

        // alice's operator can still claim
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
        assertEq(usdc.balanceOf(operator), amount);
    }

    // ── claim ───────────────────────────────────────────────

    function test_claim_happy_path() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(operator);
        htlc.claim(alice, hash, preimage);

        assertFalse(htlc.isActive(alice, hash));
        assertEq(usdc.balanceOf(operator), amount);
    }

    function test_claim_emits_event() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectEmit(true, true, false, true);
        emit BridgeHTLC.Claimed(hash, alice, preimage);

        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
    }

    function test_claim_frontrun_by_third_party_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        address frontrunner = makeAddr("frontrunner");
        vm.expectRevert(BridgeHTLC.NotClaimer.selector);
        vm.prank(frontrunner);
        htlc.claim(alice, hash, preimage);

        // operator can still claim
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
        assertEq(usdc.balanceOf(operator), amount);
    }

    function test_claim_wrong_preimage_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectRevert(BridgeHTLC.InvalidPreimage.selector);
        vm.prank(operator);
        htlc.claim(alice, hash, bytes32(uint256(999)));
    }

    function test_claim_after_deadline_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        vm.expectRevert(BridgeHTLC.DeadlinePassed.selector);
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
    }

    function test_claim_inactive_reverts() public {
        vm.expectRevert(BridgeHTLC.NotActive.selector);
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
    }

    // ── refund ──────────────────────────────────────────────

    function test_refund_after_deadline() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        htlc.refund(alice, hash);

        assertFalse(htlc.isActive(alice, hash));
        assertEq(usdc.balanceOf(alice), 10_000e6);
    }

    function test_refund_before_deadline_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectRevert(BridgeHTLC.DeadlineNotPassed.selector);
        htlc.refund(alice, hash);
    }

    function test_refund_by_third_party_succeeds() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        address anyone = makeAddr("anyone");
        vm.prank(anyone);
        htlc.refund(alice, hash);

        assertFalse(htlc.isActive(alice, hash));
        assertEq(usdc.balanceOf(alice), 10_000e6);
    }

    function test_refund_emits_event() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        vm.expectEmit(true, true, false, false);
        emit BridgeHTLC.Refunded(hash, alice);
        htlc.refund(alice, hash);
    }

    // ── isActive ────────────────────────────────────────────

    function test_isActive_false_for_unknown_hash() public view {
        assertFalse(htlc.isActive(alice, bytes32(uint256(123))));
    }

    function test_isActive_false_after_claim() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(operator);
        htlc.claim(alice, hash, preimage);

        assertFalse(htlc.isActive(alice, hash));
    }

    function test_isActive_false_after_refund() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        htlc.refund(alice, hash);

        assertFalse(htlc.isActive(alice, hash));
    }

    function test_lock_after_refund_same_hash_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        htlc.refund(alice, hash);

        vm.expectRevert(BridgeHTLC.HashAlreadyUsed.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, block.timestamp + 2 hours);
    }

    function test_lock_after_claim_same_hash_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(operator);
        htlc.claim(alice, hash, preimage);

        vm.expectRevert(BridgeHTLC.HashAlreadyUsed.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, block.timestamp + 2 hours);
    }

    function test_isActive_false_after_deadline_without_refund() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        assertTrue(htlc.isActive(alice, hash));

        vm.warp(deadline - 1);
        assertTrue(htlc.isActive(alice, hash));

        vm.warp(deadline);
        assertFalse(htlc.isActive(alice, hash));
    }

    function test_isActive_false_after_claimer_used_hash() public {
        address bob = makeAddr("bob");
        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(htlc), type(uint256).max);

        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(bob);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        // operator claims alice's lock
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);

        // bob's lock is still active in storage but isActive returns false
        assertFalse(htlc.isActive(bob, hash));
    }

    // ── governance setters ───────────────────────────────────

    function test_initialize_sets_defaults() public view {
        assertEq(htlc.minLockAmount(), 1e6);
        assertEq(htlc.minDeadlineDuration(), 1 hours);
        assertEq(htlc.maxDeadlineDuration(), 24 hours);
    }

    function test_setMinLockAmount() public {
        vm.prank(owner);
        htlc.setMinLockAmount(5e6);
        assertEq(htlc.minLockAmount(), 5e6);
    }

    function test_setMinLockAmount_zero_reverts() public {
        vm.expectRevert(BridgeHTLC.InvalidParameter.selector);
        vm.prank(owner);
        htlc.setMinLockAmount(0);
    }

    function test_setMinLockAmount_non_owner_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        htlc.setMinLockAmount(5e6);
    }

    function test_setMinDeadlineDuration() public {
        vm.prank(owner);
        htlc.setMinDeadlineDuration(2 hours);
        assertEq(htlc.minDeadlineDuration(), 2 hours);
    }

    function test_setMinDeadlineDuration_gte_max_reverts() public {
        vm.expectRevert(BridgeHTLC.InvalidParameter.selector);
        vm.prank(owner);
        htlc.setMinDeadlineDuration(24 hours);
    }

    function test_setMaxDeadlineDuration() public {
        vm.prank(owner);
        htlc.setMaxDeadlineDuration(48 hours);
        assertEq(htlc.maxDeadlineDuration(), 48 hours);
    }

    function test_setMaxDeadlineDuration_lte_min_reverts() public {
        vm.expectRevert(BridgeHTLC.InvalidParameter.selector);
        vm.prank(owner);
        htlc.setMaxDeadlineDuration(1 hours);
    }

    function test_setMinLockAmount_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit BridgeHTLC.MinLockAmountUpdated(1e6, 5e6);
        vm.prank(owner);
        htlc.setMinLockAmount(5e6);
    }

    function test_setMinDeadlineDuration_non_owner_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        htlc.setMinDeadlineDuration(2 hours);
    }

    function test_setMaxDeadlineDuration_non_owner_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        htlc.setMaxDeadlineDuration(48 hours);
    }

    function test_setMinDeadlineDuration_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit BridgeHTLC.MinDeadlineDurationUpdated(1 hours, 2 hours);
        vm.prank(owner);
        htlc.setMinDeadlineDuration(2 hours);
    }

    function test_setMaxDeadlineDuration_emits_event() public {
        vm.expectEmit(false, false, false, true);
        emit BridgeHTLC.MaxDeadlineDurationUpdated(24 hours, 48 hours);
        vm.prank(owner);
        htlc.setMaxDeadlineDuration(48 hours);
    }

    function test_updated_minLockAmount_affects_lock() public {
        vm.prank(owner);
        htlc.setMinLockAmount(500e6);

        vm.expectRevert(BridgeHTLC.AmountTooSmall.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, 100e6, deadline);
    }

    function test_updated_minDeadlineDuration_affects_lock() public {
        vm.prank(owner);
        htlc.setMinDeadlineDuration(3 hours);

        vm.expectRevert(BridgeHTLC.DeadlineTooSoon.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, block.timestamp + 2 hours);
    }

    function test_updated_maxDeadlineDuration_affects_lock() public {
        vm.prank(owner);
        htlc.setMaxDeadlineDuration(4 hours);

        vm.expectRevert(BridgeHTLC.DeadlineTooFar.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, block.timestamp + 5 hours);
    }

    function test_initializeV2_non_owner_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        htlc.initializeV2();
    }

    function test_claim_same_preimage_twice_by_same_claimer_reverts() public {
        address bob = makeAddr("bob");
        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(htlc), type(uint256).max);

        // alice and bob lock with same hash, same claimer (operator)
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(bob);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        // operator claims alice's lock
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
        assertEq(usdc.balanceOf(operator), amount);

        // operator tries to sweep bob's lock with same preimage — blocked
        vm.expectRevert(BridgeHTLC.PreimageAlreadyUsed.selector);
        vm.prank(operator);
        htlc.claim(bob, hash, preimage);

        // bob can still refund after deadline
        vm.warp(deadline);
        htlc.refund(bob, hash);
        assertEq(usdc.balanceOf(bob), 10_000e6);
    }

    function test_self_claim_does_not_poison_operator() public {
        address attacker = makeAddr("attacker");
        usdc.mint(attacker, 10e6);
        vm.prank(attacker);
        usdc.approve(address(htlc), type(uint256).max);

        // alice locks legitimately
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        // attacker self-locks with same hash and self-claims
        vm.prank(attacker);
        htlc.lock(hash, attacker, attacker, 1e6, deadline);
        vm.prank(attacker);
        htlc.claim(attacker, hash, preimage);

        // operator can still claim alice's lock — attacker's marker is scoped to attacker
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
        assertEq(usdc.balanceOf(operator), amount);
    }

    // ── balance conservation ────────────────────────────────

    function test_full_cycle_conserves_total_supply() public {
        uint256 totalBefore = usdc.balanceOf(alice) + usdc.balanceOf(operator);

        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(operator);
        htlc.claim(alice, hash, preimage);

        uint256 totalAfter = usdc.balanceOf(alice) + usdc.balanceOf(operator);
        assertEq(totalBefore, totalAfter);
    }

    // ── upgradeability ──────────────────────────────────────

    function test_non_owner_cannot_upgrade() public {
        BridgeHTLC newImpl = new BridgeHTLC();
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        htlc.upgradeToAndCall(address(newImpl), "");
    }

    function test_owner_can_upgrade() public {
        BridgeHTLC newImpl = new BridgeHTLC();
        vm.prank(owner);
        htlc.upgradeToAndCall(address(newImpl), "");
        assertTrue(address(htlc.token()) == address(usdc));
    }

    function test_lock_persists_after_upgrade() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        BridgeHTLC newImpl = new BridgeHTLC();
        vm.prank(owner);
        htlc.upgradeToAndCall(address(newImpl), "");

        assertTrue(htlc.isActive(alice, hash));
        vm.prank(operator);
        htlc.claim(alice, hash, preimage);
        assertEq(usdc.balanceOf(operator), amount);
    }

    function test_upgradeToAndCall_initializeV2_sets_params() public {
        BridgeHTLC newImpl = new BridgeHTLC();
        vm.prank(owner);
        htlc.upgradeToAndCall(address(newImpl), abi.encodeCall(BridgeHTLC.initializeV2, ()));

        assertEq(htlc.minLockAmount(), 1e6);
        assertEq(htlc.minDeadlineDuration(), 1 hours);
        assertEq(htlc.maxDeadlineDuration(), 24 hours);

        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);
        assertTrue(htlc.isActive(alice, hash));
    }

    function test_cannot_initialize_twice() public {
        vm.expectRevert();
        htlc.initialize(address(usdc), owner);
    }

    function test_cannot_initialize_implementation_directly() public {
        BridgeHTLC impl = new BridgeHTLC();
        vm.expectRevert();
        impl.initialize(address(usdc), owner);
    }

    function test_initialize_zero_token_reverts() public {
        BridgeHTLC impl = new BridgeHTLC();
        vm.expectRevert(BridgeHTLC.ZeroTokenAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(BridgeHTLC.initialize, (address(0), owner)));
    }
}
