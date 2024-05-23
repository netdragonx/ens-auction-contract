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

import "solady/src/auth/Ownable.sol";
import "./IEnsAuctions.sol";
import "./IFeeCalculator.sol";
import "./IBaseRegistrar.sol";
import "./INameWrapper.sol";

contract EnsAuctions is IEnsAuctions, Ownable {
    enum Status {
        Active,
        BuyNow,
        Claimed,
        Unclaimable,
        Abandoned
    }

    struct Bidder {
        uint24 totalBids;
        uint24 totalOutbids;
        uint24 totalClaimed;
        uint24 totalBuyNow;
        uint24 totalAbandoned;
        uint256 balance;
    }

    struct Seller {
        uint24 totalAuctions;
        uint24 totalSold;
        uint24 totalUnclaimable;
        uint24 totalBidderAbandoned;
        uint256 balance;
    }

    struct Token {
        uint256 tokenId;
        bool isWrapped;
    }

    struct Auction {
        uint64 endTime;
        uint64 buyNowEndTime;
        Status status;
        address seller;
        address highestBidder;
        uint256 highestBid;
        uint256 startingPrice;
        uint256 buyNowPrice;
        uint256 tokenCount;
        mapping(uint256 => Token) tokens;
    }

    IFeeCalculator public feeCalculator;
    IBaseRegistrar public immutable ensRegistrar;
    INameWrapper   public immutable ensNameWrapper;
    
    address public feeRecipient;
    uint256 public nextAuctionId = 1;
    uint256 public minStartingPrice = 0.01 ether;
    uint256 public minBuyNowPrice = 0.05 ether;
    uint256 public minBidIncrement = 0.01 ether;
    uint256 public auctionDuration = 3 days;
    uint256 public buyNowDuration = 4 hours;
    uint256 public settlementDuration = 7 days;
    uint256 public antiSnipeDuration = 10 minutes;
    uint256 public maxTokens = 20;

    mapping(address => Seller) public sellers;
    mapping(address => Bidder) public bidders;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => bool) public tokenOnAuction;

    constructor(
        address registrar_,
        address nameWrapper_,
        address feeCalculator_,
        address feeRecipient_
    ) {
        _initializeOwner(msg.sender);
        feeRecipient = feeRecipient_;
        feeCalculator = IFeeCalculator(feeCalculator_);
        ensRegistrar = IBaseRegistrar(registrar_);
        ensNameWrapper = INameWrapper(nameWrapper_);
    }

    /**
     *
     * startAuction - Starts an auction for one or more ENS tokens
     *
     * @param tokenIds - The token ids to auction
     *
     */
    function startAuction(
        uint256 startingPrice,
        uint256 buyNowPrice,
        uint256[] calldata tokenIds,
        bool[] calldata wrapped
    ) external payable {
        uint256 tokenCount = tokenIds.length;

        if (calculateFee(msg.sender) != msg.value) revert InvalidFee();
        if (tokenCount > maxTokens) revert MaxTokensPerTxReached();
        if (startingPrice < minStartingPrice) revert StartPriceTooLow();
        if (buyNowPrice < minBuyNowPrice || buyNowPrice <= startingPrice) revert BuyNowTooLow();
        if (tokenCount == 0 || tokenCount != wrapped.length) revert InvalidLengthOfTokenIds();

        _validateTokens(tokenIds, wrapped);

        uint64 endTime = uint64(block.timestamp + auctionDuration);
        uint64 buyNowEndTime = uint64(block.timestamp + buyNowDuration);

        Auction storage auction = auctions[nextAuctionId];
        auction.seller = msg.sender;
        auction.tokenCount = tokenCount;
        auction.buyNowPrice = buyNowPrice;
        auction.buyNowEndTime = buyNowEndTime;
        auction.startingPrice = startingPrice;
        auction.endTime = endTime;

        for (uint256 i; i < tokenCount; ++i) {
            auction.tokens[i] = Token(tokenIds[i], wrapped[i]);
        }

        ++nextAuctionId;
        ++sellers[msg.sender].totalAuctions;

        (bool success, ) = payable(feeRecipient).call{value: msg.value}("");
        if (!success) revert TransferFailed();

        emit Started(
            nextAuctionId - 1,
            msg.sender,
            startingPrice,
            buyNowPrice,
            endTime,
            buyNowEndTime,
            tokenCount,
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
        uint256 minimumBid;

        if (auction.status != Status.Active) revert InvalidStatus();
        if (block.timestamp < auction.buyNowEndTime) revert AuctionBuyNowPeriod();
        if (block.timestamp > auction.endTime) revert AuctionEnded();
        if (msg.sender == auction.seller) revert SellerCannotBid();

        if (block.timestamp >= auction.endTime - antiSnipeDuration) {
            auction.endTime += uint64(antiSnipeDuration);
        }

        if (auction.highestBid == 0) {
            minimumBid = auction.startingPrice;
        } else {
            minimumBid = auction.highestBid + minBidIncrement;
        }

        if (bidAmount < minimumBid) revert BidTooLow();

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

        if (auction.status != Status.Active) revert InvalidStatus();
        if (block.timestamp > auction.buyNowEndTime) revert BuyNowUnavailable();

        _processPayment(auction.buyNowPrice);
        
        auction.status = Status.BuyNow;
        auction.highestBidder = msg.sender;
        auction.highestBid = auction.buyNowPrice;

        sellers[auction.seller].balance += auction.buyNowPrice;
        ++sellers[auction.seller].totalSold;
        ++bidder.totalBuyNow;

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
        Auction storage auction = auctions[auctionId];
        Seller storage seller = sellers[auction.seller];

        if (auction.status != Status.Active) revert InvalidStatus();
        if (block.timestamp < auction.endTime) revert AuctionNotEnded();

        auction.status = Status.Claimed;

        seller.balance += auction.highestBid;
        ++seller.totalSold;
        ++bidders[auction.highestBidder].totalClaimed;

        _transferTokens(auction);

        emit Claimed(auctionId, auction.highestBidder);
    }

    /**
     *
     * abandon - Mark unclaimed auctions as abandoned after the settlement period
     *
     * @param auctionId - The id of the auction to mark abandoned
     *
     */
    function markAbandoned(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];

        if (auction.status != Status.Active) revert InvalidStatus();
        if (msg.sender != auction.seller) revert NotAuthorized();
        if (block.timestamp < auction.endTime + settlementDuration) revert SettlementPeriodNotExpired();
        if (auction.highestBidder == address(0)) revert AuctionHadNoBids();

        auction.status = Status.Abandoned;

        bidders[auction.highestBidder].balance += auction.highestBid;
        ++bidders[auction.highestBidder].totalAbandoned;
        ++sellers[auction.seller].totalBidderAbandoned;

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
        Auction storage auction = auctions[auctionId];
        
        if (auction.status != Status.Active) revert InvalidStatus();
        if (block.timestamp > auction.endTime + settlementDuration) revert SettlementPeriodEnded();
        if (msg.sender != auction.highestBidder) revert NotHighestBidder();
        if (_isClaimable(auction)) revert AuctionIsClaimable();

        auction.status = Status.Unclaimable;

        bidders[auction.highestBidder].balance += auction.highestBid;
        ++sellers[auction.seller].totalUnclaimable;
        
        _resetTokens(auction);

        emit Unclaimable(auctionId);
    }

    /**
     *
     * calculateFee - Calculates the auction fee based on seller history
     *
     * @param sellerAddress - Address of seller
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

        return feeCalculator.calculateFee(
            seller.totalAuctions,
            seller.totalSold,
            seller.totalUnclaimable,
            seller.totalBidderAbandoned
        );
    }

    /**
     *
     * withdrawBalance - Withdraws your complete balance from the contract
     *
     */
    function withdrawBalance() external {
        uint256 balance = bidders[msg.sender].balance + sellers[msg.sender].balance;

        bidders[msg.sender].balance = 0;
        sellers[msg.sender].balance = 0;

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
            tokenIds[i] = auction.tokens[i].tokenId;
        }

        return tokenIds;
    }

    /**
     *
     * Setters
     *
     */

    function setFeeCalculator(address feeCalculator_) external onlyOwner {
        feeCalculator = IFeeCalculator(feeCalculator_);
        emit FeeCalculatorUpdated(feeCalculator_);
    }

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


    /**
     *
     * Internal Functions
     *
     */


    /**
     * _validateTokens - Validates tokens before an auction starts
     *
     * @param tokenIds - The token ids to auction
     * @param wrapped - Whether the tokens are wrapped
     *
     */
    function _validateTokens(uint256[] calldata tokenIds, bool[] calldata wrapped) internal {
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];

            if (tokenOnAuction[tokenId]) revert TokenAlreadyInAuction();

            tokenOnAuction[tokenId] = true;

            if (wrapped[i]) {
                if (ensNameWrapper.ownerOf(tokenId) != msg.sender) revert TokenNotOwned();
                (, uint32 fuses, ) = ensNameWrapper.getData(tokenId);
                if (fuses & CANNOT_TRANSFER != 0) revert TokenNotTransferrable();
            } else {
                if (ensRegistrar.ownerOf(tokenId) != msg.sender) revert TokenNotOwned();
            }

            if (block.timestamp > ensRegistrar.nameExpires(tokenId)) revert TokenExpired();
        }
    }

    /**
     * _isClaimable - Checks if an auction is claimable
     *
     * @param auction - The auction to check
     *
     */
    function _isClaimable(Auction storage auction) internal view returns (bool) {
        bool isClaimable = true;
        bool hasWrapped = false;
        bool hasUnwrapped = false;

        for (uint256 i; i < auction.tokenCount; ++i) {
            Token memory token = auction.tokens[i];

            if (token.isWrapped) {
                if (!hasWrapped) {
                    hasWrapped = true;
                    
                    if (!ensNameWrapper.isApprovedForAll(auction.seller, address(this))) {
                        isClaimable = false;
                        break;
                    }
                }

                if (ensNameWrapper.ownerOf(token.tokenId) != auction.seller) {
                    isClaimable = false;
                    break;
                }

                (, uint32 fuses, ) = ensNameWrapper.getData(token.tokenId);

                if (fuses & CANNOT_TRANSFER != 0) {
                    isClaimable = false;
                    break;
                }
            } else {
                if (!hasUnwrapped) {
                    hasUnwrapped = true;

                    if (!ensRegistrar.isApprovedForAll(auction.seller, address(this))) {
                        isClaimable = false;
                        break;
                    }
                }

                if (ensRegistrar.ownerOf(token.tokenId) != auction.seller) {
                    isClaimable = false;
                    break;
                }
            }
        }

        return isClaimable;
    }

    /**
     * processPayment - Process payment for a bid. If a bidder has a balance, use that first.
     *
     * @param paymentDue - The total amount due
     *
     */
    function _processPayment(uint256 paymentDue) internal {
        Bidder storage bidder = bidders[msg.sender];

        uint256 paymentFromBalance;
        uint256 paymentFromMsgValue;

        if (bidder.balance >= paymentDue) {
            paymentFromBalance = paymentDue;
            paymentFromMsgValue = 0;
        } else {
            paymentFromBalance = bidder.balance;
            paymentFromMsgValue = paymentDue - bidder.balance;
        }

        if (msg.value != paymentFromMsgValue) revert InvalidValue();

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
        uint256 tokenCount = auction.tokenCount;
        address highestBidder = auction.highestBidder;
        
        for (uint256 i; i < tokenCount; ++i) {
            Token memory token = auction.tokens[i];
            tokenOnAuction[token.tokenId] = false;

            if (token.isWrapped) {
                ensNameWrapper.safeTransferFrom(seller, highestBidder, token.tokenId, 1, "");
            } else {
                ensRegistrar.transferFrom(seller, highestBidder, token.tokenId);
            }
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

        for (uint256 i; i < tokenCount; ++i) {
            tokenOnAuction[auction.tokens[i].tokenId] = false;
        }
    }
}
