// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctions} from "../src/EnsAuctions.sol";

contract DeployScript is Script {

    EnsAuctions ensAuctions;

    function run() public {
        vm.startBroadcast();

        address owner = vm.envAddress("ADDRESS_DEPLOYER");
        address ensAddress = 0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85;
        address apeAddress = 0x4d224452801ACEd8B2F0aebE155379bb5D594381;

        ensAuctions = new EnsAuctions(owner, ensAddress, apeAddress);
        
        vm.stopBroadcast();
    }
}
