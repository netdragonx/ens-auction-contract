// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "solady/src/auth/Ownable.sol";
import "./IFeeCalculator.sol";

contract DynamicFeeCalculator is IFeeCalculator, Ownable {
    uint256 public baseFee = 0.01 ether;
    uint256 public linearFee = 0.02 ether;
    uint256 public penaltyFee = 0.03 ether;

    event BaseFeeUpdated(uint256 baseFee);
    event LinearFeeUpdated(uint256 linearFee);
    event PenaltyFeeUpdated(uint256 penaltyFee);

    constructor() {
        _initializeOwner(msg.sender);
    }

    function calculateFee(
        uint256 totalActiveAuctions,
        uint24 sellerTotalAuctions,
        uint24 sellerTotalSold,
        uint24 sellerTotalUnclaimable,
        uint24 sellerTotalBidderAbandoned
    ) public view returns (uint256) {
        if (totalActiveAuctions == 0) return 0;

        return (baseFee * totalActiveAuctions) +
            (linearFee * (sellerTotalAuctions - sellerTotalSold - sellerTotalBidderAbandoned)) +
            (penaltyFee * sellerTotalUnclaimable);
    }

    function setBaseFee(uint256 baseFee_) external onlyOwner {
        baseFee = baseFee_;
        emit BaseFeeUpdated(baseFee_);
    }

    function setLinearFee(uint256 linearFee_) external onlyOwner {
        linearFee = linearFee_;
        emit LinearFeeUpdated(linearFee_);
    }

    function setPenaltyFee(uint256 penaltyFee_) external onlyOwner {
        penaltyFee = penaltyFee_;
        emit PenaltyFeeUpdated(penaltyFee_);
    }
}
