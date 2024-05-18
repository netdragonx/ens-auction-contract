// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctions} from "../src/EnsAuctions.sol";
import {MockRegistrar} from "../test/lib/MockRegistrar.sol";
import {MockNameWrapper} from "../test/lib/MockNameWrapper.sol";
import {DynamicFeeCalculator} from "../src/DynamicFeeCalculator.sol";
import {IFeeCalculator} from "../src/IFeeCalculator.sol";

contract DeployAnvilScript is Script {
    EnsAuctions ensAuctions;
    MockRegistrar mockRegistrar;
    MockNameWrapper mockNameWrapper;

    function run() public {
        vm.startBroadcast();

        address user = vm.envAddress("ADDRESS_USER_1");

        mockRegistrar = new MockRegistrar();
        mockRegistrar.mint(user, 20);

        mockNameWrapper = new MockNameWrapper();
        mockNameWrapper.mint(user, 20);

        IFeeCalculator feeCalculator = new DynamicFeeCalculator();

        ensAuctions = new EnsAuctions(
            address(mockRegistrar),
            address(mockNameWrapper),
            address(feeCalculator),
            address(this)
        );

        vm.stopBroadcast();
    }
}
