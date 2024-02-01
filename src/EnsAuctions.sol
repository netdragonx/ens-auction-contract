// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/auth/Ownable.sol";

enum Status {
    Active,
    Claimed,
    Unclaimable,
    Abandoned
}

struct Bidder {
    address bidder;
    uint16 totalBids;
    uint16 totalOutbids;
    uint16 totalClaimed;
    uint16 totalAbandoned;
}

struct Seller {
    address seller;
    uint16 totalAuctions;
    uint16 totalClaimed;
    uint16 totalUnclaimable;
}

struct EnsAuction {
    uint64 endTime;
    uint64 buyNowEndTime;
    uint8 tokenCount;
    Status status;
    address seller;
    address highestBidder;
    uint256 highestBid;
    uint256 startingPrice;
    uint256 buyNowPrice;
    mapping(uint256 => uint256) tokenIds;
}

contract EnsAuctions is Ownable {
    IERC721 public immutable ENS;
    IERC20 public immutable WETH;

    uint256 public maxTokens = 10;
    uint256 public nextAuctionId = 1;
    uint256 public minStartingPrice = 0.01 ether;
    uint256 public minBuyNowPrice = 0.01 ether;
    uint256 public minBidIncrement = 0.01 ether;
    uint256 public auctionDuration = 7 days;
    uint256 public buyNowDuration = 4 hours;
    uint256 public settlementDuration = 7 days;
    uint256 public antiSnipeDuration = 15 minutes;
    uint256 public baseFee = 0.05 ether;
    uint256 public linearFee = 0.01 ether;
    uint256 public penaltyFee = 0.01 ether;

    mapping(uint256 => EnsAuction) public auctions;
    mapping(uint256 => bool) public auctionTokens;
    mapping(address => Seller) public sellers;
    mapping(address => Bidder) public bidders;
    
    error AuctionAbandoned();
    error AuctionActive();
    error AuctionClaimed();
    error AuctionEnded();
    error AuctionNotActive();
    error AuctionNotStarted();
    error AuctionNotClaimed();
    error AuctionNotEnded();
    error AuctionWithdrawn();
    error BidTooLow();
    error BuyNowTooLow();
    error BuyNowUnavailable();
    error InsufficientWethAllowance();
    error InvalidFee();
    error InvalidLengthOfAmounts();
    error InvalidLengthOfTokenIds();
    error MaxTokensPerTxReached();
    error NotApproved();
    error NotEnoughTokensInSupply();
    error NotHighestBidder();
    error SellerCannotBid();
    error SettlementPeriodNotExpired();
    error SettlementPeriodEnded();
    error StartPriceTooLow();
    error TokenAlreadyInAuction();
    error TokenNotOwned();
    error TransferFailed();

    event Abandoned(uint256 indexed auctionId);
    event AuctionStarted(address indexed bidder, uint256[] indexed tokenIds, uint256 indexed buyNowPrice);
    event BuyNow(uint256 indexed auctionId, address indexed buyer, uint256 indexed value);
    event Claimed(uint256 indexed auctionId, address indexed winner);
    event NewBid(uint256 indexed auctionId, address indexed bidder, uint256 indexed value);

    constructor(address owner, address ensAddress, address wethAddress) {
        _initializeOwner(owner);
        ENS = IERC721(ensAddress);
        WETH = IERC20(wethAddress);
    }

    /**
     *
     * startAuction - Starts an auction for one or more ENS tokens
     *
     * @param tokenIds - The token ids to auction
     *
     */
    function startAuction(uint256[] calldata tokenIds, uint256 startingPrice, uint256 buyNowPrice) external payable {
        _validateAuctionTokens(tokenIds);

        uint256 auctionFee = calculateFee(msg.sender);

        if (msg.value != auctionFee) {
            revert InvalidFee();
        }

        if (startingPrice < minStartingPrice) {
            revert StartPriceTooLow();
        }

        if (buyNowPrice < minBuyNowPrice) {
            revert BuyNowTooLow();
        }

        if (buyNowPrice > 0 && buyNowPrice <= startingPrice) {
            revert BuyNowTooLow();
        }

        EnsAuction storage auction = auctions[nextAuctionId];

        auction.seller = msg.sender;
        auction.startingPrice = startingPrice;
        auction.buyNowPrice = buyNowPrice;
        auction.endTime = uint64(block.timestamp + auctionDuration);
        auction.buyNowEndTime = uint64(block.timestamp + buyNowDuration);
        auction.tokenCount = uint8(tokenIds.length);

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenIds.length; ) {
            tokenMap[i] = tokenIds[i];

            unchecked {
                ++i;
            }
        }

        unchecked {
            ++nextAuctionId;
        }

        ++sellers[msg.sender].totalAuctions;

        (bool success,) = owner().call{value: msg.value}("");
        if (!success) revert TransferFailed();

        emit AuctionStarted(msg.sender, tokenIds, buyNowPrice);
    }

    /**
     *
     * bid - Places a bid on an auction
     *
     * @param auctionId - The id of the auction to bid on
     *
     */
    function bid(uint256 auctionId, uint256 bidAmount) external {
        EnsAuction storage auction = auctions[auctionId];

        if (block.timestamp < auction.buyNowEndTime && auction.buyNowPrice > 0) {
            revert AuctionNotStarted();
        }

        if (block.timestamp > auction.endTime) {
            revert AuctionEnded();
        }

        if (auction.highestBid == 0) {
            if (bidAmount < auction.startingPrice) {
                revert BidTooLow();
            }
        } else if (bidAmount < auction.highestBid + minBidIncrement) {
            revert BidTooLow();
        }

        if (msg.sender == auction.seller) {
            revert SellerCannotBid();
        }

        if (block.timestamp >= auction.endTime - antiSnipeDuration) {
            auction.endTime += uint64(antiSnipeDuration);
        }

        ++bidders[msg.sender].totalBids;

        if (auction.highestBidder != address(0)) {
            ++bidders[auction.highestBidder].totalOutbids;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = bidAmount;

        emit NewBid(auctionId, msg.sender, bidAmount);
    }

    /**
     *
     * buyNow - Buy an auction immediately *before* auction begins
     *
     * @param auctionId - The id of the auction to buy
     *
     */
    function buyNow(uint256 auctionId) external {
        EnsAuction storage auction = auctions[auctionId];

        if (auction.status != Status.Active) {
            revert AuctionNotActive();
        }

        if (auction.buyNowPrice == 0 || block.timestamp > auction.buyNowEndTime) {
            revert BuyNowUnavailable();
        }

        if (WETH.allowance(msg.sender, address(this)) < auction.buyNowPrice) {
            revert InsufficientWethAllowance();
        }

        auction.status = Status.Claimed;
        auction.highestBidder = msg.sender;
        auction.highestBid = auction.buyNowPrice;
        auction.endTime = uint64(block.timestamp);
        auction.buyNowEndTime = uint64(block.timestamp);
    
        ++sellers[auction.seller].totalClaimed;
        ++bidders[msg.sender].totalClaimed;

        WETH.transferFrom(msg.sender, auction.seller, auction.buyNowPrice);
        _transferTokens(auction);

        emit BuyNow(auctionId, msg.sender, auction.buyNowPrice);
    }

    /**
     *
     * claim - Claims the tokens from an auction
     *
     * @param auctionId - The id of the auction to claim
     *
     */
    function claim(uint256 auctionId) external {
        EnsAuction storage auction = auctions[auctionId];

        if (auction.status != Status.Active) {
            if (auction.status == Status.Claimed) {
                revert AuctionClaimed();
            } else if (auction.status == Status.Abandoned) {
                revert AuctionAbandoned();
            }
        }

        if (msg.sender != auction.highestBidder) {
            revert NotHighestBidder();
        }

        if (block.timestamp < auction.endTime) {
            revert AuctionNotEnded();
        }

        if (WETH.allowance(msg.sender, address(this)) < auction.highestBid) {
            revert InsufficientWethAllowance();
        }

        auction.status = Status.Claimed;

        ++sellers[auction.seller].totalClaimed;
        ++bidders[msg.sender].totalClaimed;

        WETH.transferFrom(msg.sender, auction.seller, auction.highestBid);
        _transferTokens(auction);

        emit Claimed(auctionId, auction.highestBidder);
    }

    /**
     *
     * abandon - Seller can mark unclaimed auctions as abandoned after the settlement period
     *
     * @param auctionId - The id of the auction to abandon
     *
     */
    function markAbandoned(uint256 auctionId) external {
        EnsAuction storage auction = auctions[auctionId];
        
       if (auction.status != Status.Active) {
            if (auction.status == Status.Abandoned) {
                revert AuctionAbandoned();
            } else if (auction.status == Status.Claimed) {
                revert AuctionClaimed();
            }
        }

        if (block.timestamp < auction.endTime + settlementDuration) {
            revert SettlementPeriodNotExpired();
        }

        auction.status = Status.Abandoned;

        ++bidders[auction.highestBidder].totalAbandoned;

        _resetTokens(auction);

        emit Abandoned(auctionId);
    }

    /**
     *
     * abandon - Buyer can mark auction unclaimable during the settlement period
     *
     * @param auctionId - The id of the auction to abandon
     *
     */
    function markUnclaimable(uint256 auctionId) external {
        EnsAuction storage auction = auctions[auctionId];
        
       if (auction.status != Status.Active) {
            if (auction.status == Status.Abandoned) {
                revert AuctionAbandoned();
            } else if (auction.status == Status.Claimed) {
                revert AuctionClaimed();
            }
        }

        if (block.timestamp > auction.endTime + settlementDuration) {
            revert SettlementPeriodEnded();
        }

        if (msg.sender != auction.highestBidder) {
            revert NotHighestBidder();
        }

        for (uint256 i; i < auction.tokenCount; ) {
            uint256 tokenId = auction.tokenIds[i];

            if (ENS.ownerOf(tokenId) != auction.seller) {
                revert TokenNotOwned();
            }
            
            if (ENS.getApproved(tokenId) != address(this)) {
                revert NotApproved();
            }

            unchecked {
                ++i;
            }
        }

        auction.status = Status.Abandoned;

        ++sellers[auction.seller].totalUnclaimable;

        _resetTokens(auction);

        emit Abandoned(auctionId);
    }

    /**
     *
     * calculateFee - Calculates the auction fee based on previous unsold auctions.
     *
     * @param sellerAddress - Address of seller
     */
     
    function calculateFee(address sellerAddress) public view returns (uint256) {
        Seller storage seller = sellers[sellerAddress];

        return (
            baseFee
            + linearFee * (seller.totalAuctions - seller.totalClaimed)
            + (seller.totalUnclaimable * penaltyFee)
        );
    }

    /**
     *
     * withdraw - Withdraws the contract balance to the owner
     *
     */
    function withdraw() external onlyOwner {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }
    
    /**
     *
     * Getters & Setters
     *
     */

    function getAuctionTokens(uint256 auctionId) external view returns (uint256[] memory) {
        EnsAuction storage auction = auctions[auctionId];

        uint256[] memory tokenIds = new uint256[](auction.tokenCount);

        uint256 tokenCount = auction.tokenCount;

        for (uint256 i; i < tokenCount; ) {
            tokenIds[i] = auction.tokenIds[i];

            unchecked {
                ++i;
            }
        }

        return tokenIds;
    }

    function setMaxTokens(uint256 maxTokens_) external onlyOwner {
        maxTokens = maxTokens_;
    }

    function setMinBuyNowPrice(uint256 minBuyNowPrice_) external onlyOwner {
        minBuyNowPrice = minBuyNowPrice_;
    }

    function setMinStartingBid(uint256 minStartingPrice_) external onlyOwner {
        minStartingPrice = minStartingPrice_;
    }

    function setMinBidIncrement(uint256 minBidIncrement_) external onlyOwner {
        minBidIncrement = minBidIncrement_;
    }

    function setAuctionDuration(uint256 auctionDuration_) external onlyOwner {
        auctionDuration = auctionDuration_;
    }

    function setBuyNowDuration(uint256 buyNowDuration_) external onlyOwner {
        buyNowDuration = buyNowDuration_;
    }

    function setSettlementDuration(uint256 settlementDuration_) external onlyOwner {
        settlementDuration = settlementDuration_;
    }

    function setAntiSnipeDuration(uint256 antiSnipeDuration_) external onlyOwner {
        antiSnipeDuration = antiSnipeDuration_;
    }

    function setBaseFee(uint256 baseFee_) external onlyOwner {
        baseFee = baseFee_;
    }

    function setLinearFee(uint256 linearFee_) external onlyOwner {
        linearFee = linearFee_;
    }

    function setPenaltyFee(uint256 penaltyFee_) external onlyOwner {
        penaltyFee = penaltyFee_;
    }

    /**
     *
     * Internal Functions
     *
     */

    /**
     * _validateAuctionTokens - Validates that the tokens are owned by the sender and not already in an auction
     *
     * @param tokenIds - The token ids to validate
     *
     */
    function _validateAuctionTokens(uint256[] calldata tokenIds) internal {
        if (tokenIds.length == 0) {
            revert InvalidLengthOfTokenIds();
        }

        if (tokenIds.length > maxTokens) {
            revert MaxTokensPerTxReached();
        }

        for (uint256 i; i < tokenIds.length; ) {
            uint256 tokenId = tokenIds[i];

            if (auctionTokens[tokenId]) {
                revert TokenAlreadyInAuction();
            }

            auctionTokens[tokenId] = true;

            if (ENS.ownerOf(tokenId) != msg.sender) {
                revert TokenNotOwned();
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * _transferTokens - Transfer auction tokens to the highest bidder
     *
     * @param auction - The auction to transfer tokens from
     *
     */
    function _transferTokens(EnsAuction storage auction) internal {
        address seller = auction.seller;
        address highestBidder = auction.highestBidder;
        uint256 tokenCount = auction.tokenCount;
        
        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenCount; ) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;
            ENS.transferFrom(seller, highestBidder, tokenId);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * _resetTokens - Reset auction tokens so they can be auctioned again if needed
     *
     * @param auction - The auction to reset
     *
     */
    function _resetTokens(EnsAuction storage auction) internal {
        uint256 tokenCount = auction.tokenCount;

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenCount; ) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;

            unchecked {
                ++i;
            }
        }
    }

    receive() external payable {}

    fallback() external payable {}
}
