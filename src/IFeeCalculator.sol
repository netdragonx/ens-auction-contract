// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IFeeCalculator {
    function calculateFee(
        uint24 totalAuctions,
        uint24 totalSold,
        uint24 totalUnclaimable,
        uint24 totalBidderAbandoned
    ) external view returns (uint256);
}
