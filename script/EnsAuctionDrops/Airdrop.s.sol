// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctionDrops} from "../../src/EnsAuctionDrops.sol";

contract AirdropEnsAuctionDropsScript is Script {
    EnsAuctionDrops ensAuctionDrops;

    function run() public {
        vm.startBroadcast();

        ensAuctionDrops = EnsAuctionDrops(vm.envAddress("ADDRESS_ENS_AUCTION_DROPS"));
        
        ensAuctionDrops.airdrop(
            vm.envUint("AIRDROP_TOKEN_ID"),
            vm.envAddress("AIRDROP_RECIPIENTS", ",")
        );

        vm.stopBroadcast();
    }
}
