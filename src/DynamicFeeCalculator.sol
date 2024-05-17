// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "solady/src/auth/Ownable.sol";
import "./IFeeCalculator.sol";

contract DynamicFeeCalculator is IFeeCalculator, Ownable {
    uint256 public baseFee = 0.05 ether;
    uint256 public linearFee = 0.01 ether;
    uint256 public penaltyFee = 0.01 ether;

    event BaseFeeUpdated(uint256 baseFee);
    event LinearFeeUpdated(uint256 linearFee);
    event PenaltyFeeUpdated(uint256 penaltyFee);

    constructor() {
        _initializeOwner(msg.sender);
    }

    function calculateFee(
        uint24 totalAuctions,
        uint24 totalSold,
        uint24 totalUnclaimable,
        uint24 totalBidderAbandoned
    ) public view returns (uint256) {
        return (baseFee +
            (linearFee * (totalAuctions - totalSold - totalBidderAbandoned)) +
            (penaltyFee * totalUnclaimable));
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
