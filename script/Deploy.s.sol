// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctions} from "../src/EnsAuctions.sol";

contract DeployScript is Script {

    EnsAuctions ensAuctions;

    function run() public {
        vm.startBroadcast();

        address feeRecipient = vm.envAddress("ADDRESS_FEE_RECIPIENT");
        address ensAddress = 0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85;

        ensAuctions = new EnsAuctions(ensAddress, feeRecipient);
        
        console2.log("EnsAuctions contract: ", address(ensAuctions));

        vm.stopBroadcast();
    }
}
