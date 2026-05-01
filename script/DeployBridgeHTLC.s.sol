// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {BridgeHTLC} from "../src/BridgeHTLC.sol";

/// @notice Deploys TimelockController + BridgeHTLC (impl + proxy).
///
/// Testnet:  PROPOSER_ADDRESS=<EOA> TIMELOCK_DELAY=60 (1 min)
/// Mainnet:  PROPOSER_ADDRESS=<Safe multisig> TIMELOCK_DELAY=172800 (48h)
///
/// To migrate proposer/executor from EOA to multisig later, grant
/// PROPOSER_ROLE and EXECUTOR_ROLE to the multisig on the timelock,
/// then revoke from the EOA.
contract DeployBridgeHTLC is Script {
    function run() external {
        address token = vm.envAddress("USDC_ADDRESS");
        address proposer = vm.envAddress("PROPOSER_ADDRESS");
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(60));

        require(token != address(0), "USDC_ADDRESS is zero");
        require(proposer != address(0), "PROPOSER_ADDRESS is zero");

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = proposer;

        vm.startBroadcast();

        TimelockController timelock = new TimelockController(timelockDelay, proposers, executors, address(0));

        BridgeHTLC impl = new BridgeHTLC();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(impl), abi.encodeCall(BridgeHTLC.initialize, (token, address(timelock))));

        vm.stopBroadcast();

        BridgeHTLC htlc = BridgeHTLC(address(proxy));
        require(htlc.owner() == address(timelock), "owner != timelock");
        require(address(htlc.token()) == token, "token mismatch");
        require(htlc.minLockAmount() == 1e6, "minLockAmount not set");
        require(htlc.minDeadlineDuration() == 1 hours, "minDeadlineDuration not set");
        require(htlc.maxDeadlineDuration() == 24 hours, "maxDeadlineDuration not set");

        console.log("TimelockController:", address(timelock));
        console.log("  delay:", timelockDelay);
        console.log("  proposer/executor:", proposer);
        console.log("Implementation:", address(impl));
        console.log("Proxy:", address(proxy));
        console.log("  owner:", htlc.owner());
        console.log("  token:", address(htlc.token()));
    }
}
