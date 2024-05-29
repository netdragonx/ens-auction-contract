// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IFeeCalculator {
    function calculateFee(
        uint256 totalActiveAuctions,
        uint24 sellerTotalAuctions,
        uint24 sellerTotalSold,
        uint24 sellerTotalUnclaimable,
        uint24 sellerTotalBidderAbandoned
    ) external view returns (uint256);
}
