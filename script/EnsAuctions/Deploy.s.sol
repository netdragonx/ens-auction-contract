// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctions} from "../../src/EnsAuctions.sol";

contract DeployEnsAuctionsScript is Script {
    EnsAuctions ensAuctions;

    function run() public {
        vm.startBroadcast();

        address feeRecipient = vm.envAddress("ADDRESS_FEE_RECIPIENT");
        address registrar = vm.envAddress("ADDRESS_ENS_BASE_REGISTRAR");
        address nameWrapper = vm.envAddress("ADDRESS_ENS_NAME_WRAPPER");
        address feeCalculator = vm.envAddress("ADDRESS_FEE_CALCULATOR");

        ensAuctions = new EnsAuctions(
            registrar,
            nameWrapper,
            feeCalculator,
            feeRecipient
        );

        console2.log("EnsAuctions contract: ", address(ensAuctions));
        console2.log("FeeCalculator contract: ", feeCalculator);
        console2.log("FeeRecipient: ", feeRecipient);
        console2.log("Registrar: ", registrar);
        console2.log("NameWrapper: ", nameWrapper);

        vm.stopBroadcast();
    }
}
