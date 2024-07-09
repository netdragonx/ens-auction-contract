// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {DynamicFeeCalculator} from "../../src/DynamicFeeCalculator.sol";
import {IFeeCalculator} from "../../src/IFeeCalculator.sol";

contract DeployDynamicFeeCalculatorScript is Script {
    IFeeCalculator feeCalculator;

    function run() public {
        vm.startBroadcast();

        feeCalculator = new DynamicFeeCalculator();

        vm.stopBroadcast();
    }
}
