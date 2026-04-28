// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(BridgeHTLC.initialize, (address(usdc), owner))
        );
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

        assertTrue(htlc.isActive(hash));
        assertEq(usdc.balanceOf(address(htlc)), amount);
        assertEq(usdc.balanceOf(alice), 10_000e6 - amount);
    }

    function test_lock_emits_event_with_receiverOn2D() public {
        vm.expectEmit(true, true, true, true);
        emit BridgeHTLC.Locked(hash, alice, aliceOn2D, amount, deadline);

        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);
    }

    function test_lock_duplicate_hash_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectRevert(BridgeHTLC.AlreadyLocked.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);
    }

    function test_lock_below_minimum_reverts() public {
        vm.expectRevert(BridgeHTLC.AmountTooSmall.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, 999_999, deadline); // < 1 USDC
    }

    function test_lock_zero_receiver_reverts() public {
        vm.expectRevert(BridgeHTLC.ZeroAddress.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, address(0), amount, deadline);
    }

    function test_lock_deadline_too_soon_reverts() public {
        vm.expectRevert(BridgeHTLC.DeadlineTooSoon.selector);
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, block.timestamp + 30 minutes);
    }

    function test_lock_deadline_exactly_min_succeeds() public {
        uint256 exactMin = block.timestamp + 1 hours + 1;
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, exactMin);
        assertTrue(htlc.isActive(hash));
    }

    // ── claim ───────────────────────────────────────────────

    function test_claim_happy_path() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(operator);
        htlc.claim(hash, preimage);

        assertFalse(htlc.isActive(hash));
        assertEq(usdc.balanceOf(operator), amount);
    }

    function test_claim_emits_event() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectEmit(true, false, false, true);
        emit BridgeHTLC.Claimed(hash, preimage);

        vm.prank(operator);
        htlc.claim(hash, preimage);
    }

    function test_claim_frontrun_by_third_party_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        address frontrunner = makeAddr("frontrunner");
        vm.expectRevert(BridgeHTLC.NotClaimer.selector);
        vm.prank(frontrunner);
        htlc.claim(hash, preimage);

        // operator can still claim
        vm.prank(operator);
        htlc.claim(hash, preimage);
        assertEq(usdc.balanceOf(operator), amount);
    }

    function test_claim_wrong_preimage_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectRevert(BridgeHTLC.InvalidPreimage.selector);
        vm.prank(operator);
        htlc.claim(hash, bytes32(uint256(999)));
    }

    function test_claim_after_deadline_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        vm.expectRevert(BridgeHTLC.DeadlinePassed.selector);
        vm.prank(operator);
        htlc.claim(hash, preimage);
    }

    function test_claim_inactive_reverts() public {
        vm.expectRevert(BridgeHTLC.NotActive.selector);
        vm.prank(operator);
        htlc.claim(hash, preimage);
    }

    // ── refund ──────────────────────────────────────────────

    function test_refund_after_deadline() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        htlc.refund(hash);

        assertFalse(htlc.isActive(hash));
        assertEq(usdc.balanceOf(alice), 10_000e6);
    }

    function test_refund_before_deadline_reverts() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.expectRevert(BridgeHTLC.DeadlineNotPassed.selector);
        htlc.refund(hash);
    }

    function test_refund_emits_event() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        vm.expectEmit(true, false, false, false);
        emit BridgeHTLC.Refunded(hash);
        htlc.refund(hash);
    }

    // ── isActive ────────────────────────────────────────────

    function test_isActive_false_for_unknown_hash() public view {
        assertFalse(htlc.isActive(bytes32(uint256(123))));
    }

    function test_isActive_false_after_claim() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(operator);
        htlc.claim(hash, preimage);

        assertFalse(htlc.isActive(hash));
    }

    function test_isActive_false_after_refund() public {
        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.warp(deadline);
        htlc.refund(hash);

        assertFalse(htlc.isActive(hash));
    }

    // ── balance conservation ────────────────────────────────

    function test_full_cycle_conserves_total_supply() public {
        uint256 totalBefore = usdc.balanceOf(alice) + usdc.balanceOf(operator);

        vm.prank(alice);
        htlc.lock(hash, operator, aliceOn2D, amount, deadline);

        vm.prank(operator);
        htlc.claim(hash, preimage);

        uint256 totalAfter = usdc.balanceOf(alice) + usdc.balanceOf(operator);
        assertEq(totalBefore, totalAfter);
    }

    // ── upgradeability ──────────────────────────────────────

    function test_non_owner_cannot_upgrade() public {
        BridgeHTLC newImpl = new BridgeHTLC();
        vm.expectRevert();
        vm.prank(alice);
        htlc.upgradeToAndCall(address(newImpl), "");
    }

    function test_owner_can_upgrade() public {
        BridgeHTLC newImpl = new BridgeHTLC();
        vm.prank(owner);
        htlc.upgradeToAndCall(address(newImpl), "");
        // still works after upgrade
        assertTrue(address(htlc.token()) == address(usdc));
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
}
