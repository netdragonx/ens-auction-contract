// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {EnsAuctions} from "../src/EnsAuctions.sol";

contract EnsAuctionsTest is Test {
    EnsAuctions public ensAuctions;

    function setUp() public {
        ensAuctions = new EnsAuctions();
    }
}
