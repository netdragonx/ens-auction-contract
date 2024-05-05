// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

//                     ░▒▓████████▓▒░▒▓███████▓▒░ ░▒▓███████▓▒░
//                     ░▒▓█▓▒░      ░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒░       
//                     ░▒▓█▓▒░      ░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒░       
//                     ░▒▓██████▓▒░ ░▒▓█▓▒  ▒▓█▓▒  ▒▓██████▓▒░ 
//                     ░▒▓█▓▒░      ░▒▓█▓▒  ▒▓█▓▒░      ░▒▓█▓▒░
//                     ░▒▓█▓▒░      ░▒▓█▓▒  ▒▓█▓▒░      ░▒▓█▓▒░
//                     ░▒▓████████▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓███████▓▒  
//
//                        ___________
//                        \         /
//                         )_______(
//                         |"""""""|_.-._,.---------.,_.-._
//                         |       | | |               | | ''-.
//                         |       |_| |_             _| |_..-'
//                         |_______| '-' `'---------'` '-'
//                         )"""""""(
//                        /_________\
//                        `'-------'`
//                      .-------------.
//                     /_______________\
//    
//   ░▒▓██████▓▒  ▒▓█▓▒  ▒▓█▓▒  ▒▓██████▓▒░▒▓████████▓▒░▒▓█▓▒  ▒▓██████▓▒  ▒▓███████▓▒░  
//  ░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░ ░▒▓█▓▒░   ░▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░ 
//  ░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒░        ░▒▓█▓▒░   ░▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░ 
//  ░▒▓████████▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒░        ░▒▓█▓▒░   ░▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░ 
//  ░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒░        ░▒▓█▓▒░   ░▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░ 
//  ░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░ ░▒▓█▓▒░   ░▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░▒▓█▓▒  ▒▓█▓▒░ 
//  ░▒▓█▓▒  ▒▓█▓▒  ▒▓██████▓▒░ ░▒▓██████▓▒░  ░▒▓█▓▒░   ░▒▓█▓▒  ▒▓██████▓▒  ▒▓█▓▒  ▒▓█▓▒░ 
//                                                                   https://ens.auction

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/auth/Ownable.sol";
import "./IEnsAuctions.sol";

contract EnsAuctions is IEnsAuctions, Ownable {
    enum Status {
        Active,
        BuyNow,
        Claimed,
        Unclaimable,
        Abandoned
    }

    struct Bidder {
        uint16 totalBids;
        uint16 totalOutbids;
        uint16 totalClaimed;
        uint16 totalBuyNow;
        uint16 totalAbandoned;
        uint256 balance;
    }

    struct Seller {
        uint16 totalAuctions;
        uint16 totalSold;
        uint16 totalUnclaimable;
        uint16 totalBidderAbandoned;
    }

    struct Auction {
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

    IERC721 public immutable ENS;
    address public feeRecipient;
    uint256 public maxTokens = 10;
    uint256 public nextAuctionId = 1;
    uint256 public minStartingPrice = 0.01 ether;
    uint256 public minBuyNowPrice = 0.05 ether;
    uint256 public minBidIncrement = 0.01 ether;
    uint256 public auctionDuration = 3 days;
    uint256 public buyNowDuration = 4 hours;
    uint256 public settlementDuration = 7 days;
    uint256 public antiSnipeDuration = 10 minutes;
    uint256 public baseFee = 0.05 ether;
    uint256 public linearFee = 0.01 ether;
    uint256 public penaltyFee = 0.01 ether;

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => bool) public auctionTokens;
    mapping(address => Seller) public sellers;
    mapping(address => Bidder) public bidders;

    constructor(address ensAddress, address feeRecipient_) {
        _initializeOwner(msg.sender);
        ENS = IERC721(ensAddress);
        feeRecipient = feeRecipient_;
    }

    /**
     *
     * startAuction - Starts an auction for one or more ENS tokens
     *
     * @param tokenIds - The token ids to auction
     *
     */
    function startAuction(
        uint256[] calldata tokenIds,
        uint256 startingPrice,
        uint256 buyNowPrice
    ) external payable {
        uint256 auctionFee = calculateFee(msg.sender);

        _validateAuctionTokens(tokenIds);

        if (msg.value != auctionFee) {
            revert InvalidFee();
        }

        if (startingPrice < minStartingPrice) {
            revert StartPriceTooLow();
        }

        if (buyNowPrice < minBuyNowPrice) {
            revert BuyNowTooLow();
        }

        if (buyNowPrice <= startingPrice) {
            revert BuyNowTooLow();
        }

        Auction storage auction = auctions[nextAuctionId];

        auction.seller = msg.sender;
        auction.startingPrice = startingPrice;
        auction.buyNowPrice = buyNowPrice;
        auction.endTime = uint64(block.timestamp + auctionDuration);
        auction.buyNowEndTime = uint64(block.timestamp + buyNowDuration);
        auction.tokenCount = uint8(tokenIds.length);

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenIds.length; ++i) {
            tokenMap[i] = tokenIds[i];
        }

        unchecked {
            ++nextAuctionId;
        }

        ++sellers[msg.sender].totalAuctions;

        (bool success, ) = payable(feeRecipient).call{value: msg.value}("");
        if (!success) revert TransferFailed();

        emit Started(
            nextAuctionId - 1,
            msg.sender,
            startingPrice,
            buyNowPrice,
            auction.endTime,
            auction.buyNowEndTime,
            auction.tokenCount,
            tokenIds
        );
    }

    /**
     *
     * bid - Places a bid on an auction
     *
     * @param auctionId - The id of the auction to bid on
     *
     */
    function bid(uint256 auctionId, uint256 bidAmount) external payable {
        Auction storage auction = auctions[auctionId];
        Bidder storage bidder = bidders[msg.sender];

        if (auction.status != Status.Active) {
            revert InvalidStatus();
        }

        if (block.timestamp < auction.buyNowEndTime) {
            revert AuctionBuyNowPeriod();
        }

        if (block.timestamp > auction.endTime) {
            revert AuctionEnded();
        }

        if (msg.sender == auction.seller) {
            revert SellerCannotBid();
        }

        if (block.timestamp >= auction.endTime - antiSnipeDuration) {
            auction.endTime += uint64(antiSnipeDuration);
        }
        
        uint256 minimumBid;

        if (auction.highestBid == 0) {
            minimumBid = auction.startingPrice;
        } else {
            minimumBid = auction.highestBid + minBidIncrement;
        }

        if (bidAmount < minimumBid) {
            revert BidTooLow();
        }

        _processPayment(bidAmount);

        ++bidder.totalBids;

        address prevHighestBidder = auction.highestBidder;
        uint256 prevHighestBid = auction.highestBid;

        auction.highestBidder = msg.sender;
        auction.highestBid = bidAmount;

        if (prevHighestBidder != address(0)) {
            Bidder storage prevBidder = bidders[prevHighestBidder];
            prevBidder.balance += prevHighestBid;
            ++prevBidder.totalOutbids;
        }

        emit Bid(auctionId, msg.sender, bidAmount);
    }

    /**
     *
     * buyNow - Buy now phase occurs *before* auction bidding begins
     *
     * @param auctionId - The id of the auction to buy
     *
     */
    function buyNow(uint256 auctionId) external payable {
        Auction storage auction = auctions[auctionId];
        Bidder storage bidder = bidders[msg.sender];

        if (auction.status != Status.Active) {
            revert InvalidStatus();
        }

        if (block.timestamp > auction.buyNowEndTime) {
            revert BuyNowUnavailable();
        }

        _processPayment(auction.buyNowPrice);
        
        auction.status = Status.BuyNow;
        auction.highestBidder = msg.sender;
        auction.highestBid = auction.buyNowPrice;

        ++sellers[auction.seller].totalSold;
        ++bidder.totalBuyNow;

        _transferTokens(auction);

        (bool successMsgValue, ) = payable(auction.seller).call{value: auction.buyNowPrice}("");
        if (!successMsgValue) {
            revert TransferFailed();
        }

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
        Auction storage auction = auctions[auctionId];

        if (auction.status != Status.Active) {
            revert InvalidStatus();
        }

        if (msg.sender != auction.highestBidder) {
            revert NotHighestBidder();
        }

        if (block.timestamp < auction.endTime) {
            revert AuctionNotEnded();
        }

        auction.status = Status.Claimed;

        ++sellers[auction.seller].totalSold;
        ++bidders[msg.sender].totalClaimed;

        _transferTokens(auction);

        emit Claimed(auctionId, auction.highestBidder);
    }

    /**
     *
     * abandon - Seller can mark unclaimed auctions as abandoned after the settlement period
     *
     * @param auctionId - The id of the auction to mark abandoned
     *
     */
    function markAbandoned(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];

        if (auction.status != Status.Active) {
            revert InvalidStatus();
        }

        if (msg.sender != auction.seller) {
            revert NotAuthorized();
        }

        if (block.timestamp < auction.endTime + settlementDuration) {
            revert SettlementPeriodNotExpired();
        }

        if (auction.highestBidder == address(0)) {
            revert AuctionHadNoBids();
        }

        auction.status = Status.Abandoned;

        ++bidders[auction.highestBidder].totalAbandoned;
        ++sellers[auction.seller].totalBidderAbandoned;

        _resetTokens(auction);

        (bool success, ) = payable(auction.highestBidder).call{ value: auction.highestBid }("");
        if (!success) revert TransferFailed();

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
        Auction storage auction = auctions[auctionId];

        if (auction.status != Status.Active) {
            revert InvalidStatus();
        }

        if (block.timestamp > auction.endTime + settlementDuration) {
            revert SettlementPeriodEnded();
        }

        if (msg.sender != auction.highestBidder) {
            revert NotHighestBidder();
        }

        bool isClaimable = true;
        bool allApproved = ENS.isApprovedForAll(auction.seller, address(this));

        for (uint256 i; i < auction.tokenCount; ++i) {
            uint256 tokenId = auction.tokenIds[i];

            isClaimable = isClaimable 
                && (ENS.ownerOf(tokenId) == auction.seller)
                && (allApproved || ENS.getApproved(tokenId) == address(this));
            
            if (!isClaimable) {
                break;
            }
        }

        if (isClaimable) {
            revert AuctionIsClaimable();
        }

        auction.status = Status.Unclaimable;

        ++sellers[auction.seller].totalUnclaimable;

        _resetTokens(auction);

        (bool success, ) = payable(auction.highestBidder).call{ value: auction.highestBid }("");
        if (!success) revert TransferFailed();

        emit Unclaimable(auctionId);
    }

    /**
     *
     * calculateFee - Calculates the auction fee based on seller history
     *
     * @param sellerAddress - Address of seller
     *
     * baseFee: minimal fee for all auctions.
     * linearFee: fee that increases linearly for unsold auctions (0 if none).
     * penaltyFee: fee charged for each auction a buyer marked unclaimable
     *
     * Dynamic fees are designed to encourage sellers to:
     *
     *  a) use Starting Price / Buy Now prices that reflect market conditions
     *  b) list high quality names
     *  c) prevent listing spam
     *  d) make sure all auctions remain claimable
     * 
     */

    function calculateFee(address sellerAddress) public view returns (uint256) {
        Seller storage seller = sellers[sellerAddress];

        return (baseFee +
            linearFee * (seller.totalAuctions - seller.totalSold - seller.totalBidderAbandoned) +
            (penaltyFee * seller.totalUnclaimable));
    }

    /**
     *
     * withdrawBalance - Withdraws bidders balance from the contract
     *
     */
    function withdrawBalance() external {
        uint256 balance = bidders[msg.sender].balance;

        bidders[msg.sender].balance = 0;

        (bool success, ) = payable(msg.sender).call{value: balance}("");
        if (!success) revert TransferFailed();

        emit Withdrawn(msg.sender, balance);
    }

    /**
     *
     * Views
     *
     */

    function getAuctionTokens(uint256 auctionId) external view returns (uint256[] memory) {
        Auction storage auction = auctions[auctionId];

        uint256[] memory tokenIds = new uint256[](auction.tokenCount);

        uint256 tokenCount = auction.tokenCount;

        for (uint256 i; i < tokenCount; ++i) {
            tokenIds[i] = auction.tokenIds[i];
        }

        return tokenIds;
    }

    /**
     *
     * Setters
     *
     */

    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        feeRecipient = feeRecipient_;
        emit FeeRecipientUpdated(feeRecipient_);
    }

    function setMaxTokens(uint256 maxTokens_) external onlyOwner {
        maxTokens = maxTokens_;
        emit MaxTokensUpdated(maxTokens_);
    }

    function setMinBuyNowPrice(uint256 minBuyNowPrice_) external onlyOwner {
        minBuyNowPrice = minBuyNowPrice_;
        emit MinBuyNowPriceUpdated(minBuyNowPrice_);
    }

    function setMinStartingBid(uint256 minStartingPrice_) external onlyOwner {
        minStartingPrice = minStartingPrice_;
        emit MinStartingBidUpdated(minStartingPrice_);
    }

    function setMinBidIncrement(uint256 minBidIncrement_) external onlyOwner {
        minBidIncrement = minBidIncrement_;
        emit MinBidIncrementUpdated(minBidIncrement_);
    }

    function setAuctionDuration(uint256 auctionDuration_) external onlyOwner {
        auctionDuration = auctionDuration_;
        emit AuctionDurationUpdated(auctionDuration_);
    }

    function setBuyNowDuration(uint256 buyNowDuration_) external onlyOwner {
        buyNowDuration = buyNowDuration_;
        emit BuyNowDurationUpdated(buyNowDuration_);
    }

    function setSettlementDuration(uint256 settlementDuration_) external onlyOwner {
        settlementDuration = settlementDuration_;
        emit SettlementDurationUpdated(settlementDuration_);
    }

    function setAntiSnipeDuration(uint256 antiSnipeDuration_) external onlyOwner {
        antiSnipeDuration = antiSnipeDuration_;
        emit AntiSnipeDurationUpdated(antiSnipeDuration_);
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

        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];

            if (auctionTokens[tokenId]) {
                revert TokenAlreadyInAuction();
            }

            auctionTokens[tokenId] = true;

            if (ENS.ownerOf(tokenId) != msg.sender) {
                revert TokenNotOwned();
            }
        }
    }

    /**
     * processPayment - Process payment for a bid. If a bidder has a balance, use that first.
     *
     * @param paymentDue - The total amount due
     *
     */
    function _processPayment(uint256 paymentDue) internal {
        Bidder storage bidder = bidders[msg.sender];

        uint256 paymentFromBalance = bidder.balance;
        uint256 paymentFromMsgValue = msg.value;

        if (bidder.balance >= paymentDue) {
            paymentFromBalance = paymentDue;
            paymentFromMsgValue = 0;
        } else {
            paymentFromBalance = bidder.balance;
            paymentFromMsgValue = paymentDue - bidder.balance;
        }

        if (msg.value != paymentFromMsgValue) {
            revert InvalidValue();
        }

        bidder.balance -= paymentFromBalance;
    }

    /**
     * _transferTokens - Transfer auction tokens to the highest bidder
     *
     * @param auction - The auction to transfer tokens from
     *
     */
    function _transferTokens(Auction storage auction) internal {
        address seller = auction.seller;
        address highestBidder = auction.highestBidder;
        uint256 tokenCount = auction.tokenCount;

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenCount; ++i) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;
            ENS.transferFrom(seller, highestBidder, tokenId);
        }
    }

    /**
     * _resetTokens - Reset auction tokens so they can be auctioned again if needed
     *
     * @param auction - The auction to reset
     *
     */
    function _resetTokens(Auction storage auction) internal {
        uint256 tokenCount = auction.tokenCount;

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenCount; ++i) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;
        }
    }

    receive() external payable {
        revert InvalidValue();
    }

    fallback() external payable {
        revert InvalidValue();
    }
}
