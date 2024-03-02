// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctions} from "../src/EnsAuctions.sol";

contract EnsAuctionsScript is Script {

    EnsAuctions ensAuctions;

    function run() public {
        vm.startBroadcast();

        address owner = vm.envAddress("ADDRESS_DEPLOYER");
        address ensAddress = 0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85;

        ensAuctions = new EnsAuctions(owner, ensAddress);
        
        vm.stopBroadcast();
    }
}
