// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "solady/src/auth/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./IFeeCalculator.sol";

contract DynamicFeeCalculator is IFeeCalculator, Ownable {
    enum TokenType {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Discount {
        TokenType tokenType;
        address tokenAddress;
        uint256 tokenId;
        uint256 threshold;
        uint256 discount;
    }

    Discount[] public discounts;

    uint256 public baseFee = 0.005 ether;
    uint256 public linearFee = 0.01 ether;
    uint256 public penaltyFee = 0.01 ether;

    event AddedDiscounts(Discount[] discounts);
    event BaseFeeUpdated(uint256 baseFee);
    event ClearedDiscounts();
    event LinearFeeUpdated(uint256 linearFee);
    event PenaltyFeeUpdated(uint256 penaltyFee);

    constructor() {
        _initializeOwner(msg.sender);
    }

    function calculateFee(
        uint256 totalAuctionCount,
        address seller,
        uint24 auctionCount,
        uint24 soldCount,
        uint24 unclaimableCount,
        uint24 abandonedCount,
        bool checkForDiscounts
    ) public view returns (uint256) {
        uint256 fee = (baseFee * totalAuctionCount) +
            (linearFee * (auctionCount - soldCount - abandonedCount)) +
            (penaltyFee * unclaimableCount);

        if (checkForDiscounts) {
            uint256 discountsLength = discounts.length;
            
            for (uint256 i = 0; i < discountsLength; ++i) {
                Discount memory discount = discounts[i];

                if (_isEligibleForDiscount(discount, seller)) {
                    return fee * discount.discount / 100;
                }
            }
        }

        return fee;
    }

    function _isEligibleForDiscount(Discount memory discount, address seller) internal view returns (bool) {
        if (TokenType.ERC721 == discount.tokenType) {
            return IERC721(discount.tokenAddress).balanceOf(seller) > 0;
        }
        
        if (TokenType.ERC1155 == discount.tokenType) {
            return IERC1155(discount.tokenAddress).balanceOf(seller, discount.tokenId) > discount.threshold;
        }

        return IERC20(discount.tokenAddress).balanceOf(seller) > discount.threshold;
    }

    function addDiscounts(Discount[] calldata newDiscounts) external onlyOwner {
        for (uint256 i = 0; i < newDiscounts.length; i++) {
            discounts.push(newDiscounts[i]);
        }

        emit AddedDiscounts(newDiscounts);
    }

    function clearDiscounts() external onlyOwner {
        delete discounts;
        emit ClearedDiscounts();
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
