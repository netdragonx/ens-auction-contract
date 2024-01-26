// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/auth/Ownable.sol";

enum Status {
    Active,
    Claimed,
    Abandoned
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
    IERC721 public constant ENS = IERC721(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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
    uint256 public feeIncrement = 5;
    uint256 public withdrawalAddress;

    mapping(uint256 => EnsAuction) public auctions;
    mapping(uint256 => bool) public auctionTokens;
    mapping(address => uint256) public userFees;

    error AuctionAbandoned();
    error AuctionActive();
    error AuctionClaimed();
    error AuctionEnded();
    error AuctionIsApproved();
    error AuctionNotActive();
    error AuctionNotStarted();
    error AuctionNotClaimed();
    error AuctionNotEnded();
    error AuctionWithdrawn();
    error BidTooLow();
    error BuyNowUnavailable();
    error InsufficientWethAllowance();
    error InvalidFee();
    error InvalidLengthOfAmounts();
    error InvalidLengthOfTokenIds();
    error MaxTokensPerTxReached();
    error NotEnoughTokensInSupply();
    error NotHighestBidder();
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

    constructor(address owner) {
        _initializeOwner(owner);
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

        uint256 auctionFee = calculateFee(msg.sender, tokenIds.length);

        if (msg.value != auctionFee) {
            revert InvalidFee();
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

        userFees[msg.sender] += auctionFee;

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

        if (bidAmount < auction.highestBid + minBidIncrement) {
            revert BidTooLow();
        }

        if (block.timestamp >= auction.endTime - antiSnipeDuration) {
            auction.endTime += uint64(antiSnipeDuration);
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

        if (WETH.allowance(msg.sender, address(this)) < auction.highestBid) {
            revert InsufficientWethAllowance();
        }

        if (block.timestamp < auction.endTime) {
            revert AuctionNotEnded();
        }

        if (msg.sender != auction.highestBidder) {
            revert NotHighestBidder();
        }

        if (auction.status != Status.Active) {
            if (auction.status == Status.Claimed) {
                revert AuctionClaimed();
            } else if (auction.status == Status.Abandoned) {
                revert AuctionAbandoned();
            }
        }

        auction.status = Status.Claimed;

        WETH.transferFrom(msg.sender, auction.seller, auction.highestBid);
        _transferTokens(auction);

        emit Claimed(auctionId, auction.highestBidder);
    }

    /**
     *
     * abandon - Mark unclaimed auctions as abandoned after the settlement period
     *
     * @param auctionId - The id of the auction to abandon
     *
     */
    function abandon(uint256 auctionId) external {
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
        
        _resetTokens(auction);

        emit Abandoned(auctionId);
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
     * calculateFee - Calculates the auction fee based on previous unsold auctions.
     *
     * @param tokenCount - Number of ENS tokens in the auction
     */
     //TODO: convert this to a bonding curve based on number of active auctions?
    function calculateFee(address user, uint256 tokenCount) public view returns (uint256) {
        uint256 fee = baseFee * tokenCount;
        uint256 userFee = userFees[user];

        if (userFee > 0) {
            fee = fee + ((userFee * feeIncrement) / 100);
        }

        return fee;
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

    function setMinStartingBid(uint256 minStartingPrice_) external onlyOwner {
        minStartingPrice = minStartingPrice_;
    }

    function setMinBidIncrement(uint256 minBidIncrement_) external onlyOwner {
        minBidIncrement = minBidIncrement_;
    }

    function setAuctionDuration(uint256 auctionDuration_) external onlyOwner {
        auctionDuration = auctionDuration_;
    }

    function setSettlementDuration(uint256 settlementDuration_) external onlyOwner {
        settlementDuration = settlementDuration_;
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
        uint256 tokenCount = auction.tokenCount;
        address highestBidder = auction.highestBidder;

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenCount; ) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;
            ENS.transferFrom(msg.sender, highestBidder, tokenId);

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
