// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IFeeCalculator {
    function calculateFee(
        uint256 totalAuctionCount,
        address seller,
        uint24 auctionCount,
        uint24 soldCount,
        uint24 unclaimableCount,
        uint24 abandonedCount,
        bool checkForDiscounts
    ) external view returns (uint256);
}
