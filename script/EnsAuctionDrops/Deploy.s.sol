// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctionDrops} from "../../src/EnsAuctionDrops.sol";

contract DeployEnsAuctionDropsScript is Script {
    EnsAuctionDrops ensAuctionDrops;

    function run() public {
        vm.startBroadcast();

        ensAuctionDrops = new EnsAuctionDrops();
        ensAuctionDrops.setContractURI(vm.envString("AIRDROP_CONTRACT_META"));
        
        console2.log("EnsAuctionDrops contract: ", address(ensAuctionDrops));

        vm.stopBroadcast();
    }
}
