// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console2} from "forge-std/Script.sol";
import {EnsAuctionDrops} from "../../src/EnsAuctionDrops.sol";

contract AirdropScript is Script {
    EnsAuctionDrops ensAuctionDrops;

    function run() public {
        vm.startBroadcast();

        ensAuctionDrops = EnsAuctionDrops(vm.envAddress("ADDRESS_ENS_AUCTION_DROPS"));
        
        ensAuctionDrops.setURI(
            vm.envUint("AIRDROP_TOKEN_ID"),
            vm.envString("AIRDROP_TOKEN_URI")
        );
        
        ensAuctionDrops.airdrop(
            vm.envUint("AIRDROP_TOKEN_ID"),
            vm.envAddress("AIRDROP_RECIPIENTS", ",")
        );

        vm.stopBroadcast();
    }
}
