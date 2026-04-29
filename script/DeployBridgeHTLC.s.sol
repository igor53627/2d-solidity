// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BridgeHTLC} from "../src/BridgeHTLC.sol";

contract DeployBridgeHTLC is Script {
    function run() external {
        address token = vm.envAddress("USDC_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        require(token != address(0), "USDC_ADDRESS is zero");
        require(owner != address(0), "OWNER_ADDRESS is zero");

        vm.startBroadcast();

        BridgeHTLC impl = new BridgeHTLC();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(BridgeHTLC.initialize, (token, owner)));

        vm.stopBroadcast();

        console.log("Implementation:", address(impl));
        console.log("Proxy:", address(proxy));
    }
}
