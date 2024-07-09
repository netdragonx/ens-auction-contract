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
//  v1.3                                                             https://ens.auction

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

    struct Seller {
        uint24 totalAuctions;
        uint24 totalSold;
        uint24 totalUnclaimable;
        uint24 totalBidderAbandoned;
    }

    struct Token {
        uint256 tokenId;
        bool isWrapped;
    }

    struct Auction {
        Status status;
        uint64 startTime;
        uint64 endTime;
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
    uint256 public settlementDuration = 7 days;
    uint256 public antiSnipeDuration = 30 minutes;
    uint256 public maxTokens = 20;
    uint256 public eventStartDay = 5;
    uint256 public eventStartTime = 16 hours;
    uint256 public eventEndDay = 1;
    uint256 public eventEndTime = 0 hours;
    
    mapping(address => Seller) public sellers;
    mapping(address => uint256) public balances;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => uint256) public tokenOnAuction;

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
     * EXTERNAL FUNCTIONS
     *
     */

    /**
     * startAuction - Starts an auction for one or more ENS tokens
     *
     * @param startingPrice - The starting price for the auction
     * @param buyNowPrice - The buy now price for the auction
     * @param tokenIds - The token ids to auction
     * @param wrapped - Whether the tokens are wrapped
     * @param useDiscount - Whether to check for discounts
     *
     * Note: due to extra gas costs when checking token ownership or balances, we let 
     * the frontend check for discounts offchain and decide whether to check for discounts or not.
     */

    function startAuction(
        uint256 startingPrice,
        uint256 buyNowPrice,
        uint256[] calldata tokenIds,
        bool[] calldata wrapped,
        bool useDiscount
    ) external payable {
        uint256 tokenCount = tokenIds.length;
        uint256 fee = calculateFee(msg.sender, useDiscount);

        if (tokenCount > maxTokens) revert MaxTokensPerTxReached();
        if (startingPrice < minStartingPrice) revert StartPriceTooLow();
        if (buyNowPrice < minBuyNowPrice) revert BuyNowTooLow();
        if (tokenCount == 0 || tokenCount != wrapped.length) revert InvalidLengthOfTokenIds();

        uint64 _eventStartTime = getNextEventStartTime();
        uint64 _eventEndTime = getNextEventEndTime();

        _validateTokens(tokenIds, wrapped, _eventEndTime);

        Auction storage auction = auctions[nextAuctionId];
        auction.seller = msg.sender;
        auction.tokenCount = tokenCount;
        auction.buyNowPrice = buyNowPrice;
        auction.startTime = _eventStartTime;
        auction.endTime = _eventEndTime;
        auction.startingPrice = startingPrice;

        for (uint256 i; i < tokenCount; ++i) {
            auction.tokens[i] = Token(tokenIds[i], wrapped[i]);
        }

        _processFee(fee);

        emit Started(
            nextAuctionId,
            msg.sender,
            startingPrice,
            buyNowPrice,
            auction.startTime,
            auction.endTime,
            tokenCount
        );

        unchecked {
            ++nextAuctionId;
            ++sellers[msg.sender].totalAuctions;
        }
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
        uint256 minimumBid;

        if (auction.status != Status.Active) revert InvalidStatus();
        if (block.timestamp < auction.startTime) revert AuctionBuyNowPeriod();
        if (block.timestamp > auction.endTime) revert AuctionEnded();
        if (msg.sender == auction.seller) revert SellerCannotBid();

        if (block.timestamp >= auction.endTime - antiSnipeDuration) {
            auction.endTime += uint64(antiSnipeDuration);
        }

        if (auction.highestBid == 0) {
            minimumBid = auction.startingPrice;
        } else {
            unchecked {
                minimumBid = auction.highestBid + minBidIncrement;
            }
        }

        if (bidAmount < minimumBid) revert BidTooLow();

        _processPayment(bidAmount);

        address prevHighestBidder = auction.highestBidder;
        uint256 prevHighestBid = auction.highestBid;

        auction.highestBidder = msg.sender;
        auction.highestBid = bidAmount;

        if (prevHighestBidder != address(0)) {
            unchecked {
                balances[prevHighestBidder] += prevHighestBid;
            }
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

        if (auction.status != Status.Active) revert InvalidStatus();
        if (block.timestamp > auction.startTime) revert BuyNowUnavailable();
        if (msg.sender == auction.seller) revert SellerCannotBid();

        _processPayment(auction.buyNowPrice);
        
        auction.status = Status.BuyNow;
        auction.highestBidder = msg.sender;
        auction.highestBid = auction.buyNowPrice;

        unchecked {
            balances[auction.seller] += auction.buyNowPrice;
            ++sellers[auction.seller].totalSold;
        }

        emit BuyNow(auctionId, msg.sender, auction.buyNowPrice);

        _transferTokens(auction);
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

        if (auction.status != Status.Active) revert InvalidStatus();
        if (block.timestamp < auction.endTime) revert AuctionNotEnded();
        if (auction.highestBidder == address(0)) revert AuctionHasNoBids();
        
        auction.status = Status.Claimed;

        unchecked {
            balances[auction.seller] += auction.highestBid;
            ++sellers[auction.seller].totalSold;
        }

        emit Claimed(auctionId, auction.highestBidder);

        _transferTokens(auction);
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
        if (auction.highestBidder == address(0)) revert AuctionHasNoBids();

        auction.status = Status.Abandoned;

        unchecked {
            balances[auction.highestBidder] += auction.highestBid;
            ++sellers[auction.seller].totalBidderAbandoned;
        }

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

        unchecked {
            balances[auction.highestBidder] += auction.highestBid;
            ++sellers[auction.seller].totalUnclaimable;
        }
        
        _resetTokens(auction);

        emit Unclaimable(auctionId);
    }

    /**
     *
     * withdrawBalance - Withdraws your own balance from the contract
     *
     */
    function withdrawBalance() external {
        uint256 balance = balances[msg.sender];

        balances[msg.sender] = 0;

        emit Withdrawn(msg.sender, balance);

        (bool success, ) = payable(msg.sender).call{value: balance}("");
        if (!success) revert TransferFailed();
    }

    /**
     *
     * withdrawBalances - Withdraw and send balance to users if need arises
     *
     * @param addresses - The addresses to withdraw
     *
     */
    function withdrawBalances(address[] calldata addresses) external onlyOwner {
        for (uint256 i; i < addresses.length; ++i) {
            uint256 balance = balances[addresses[i]];
            balances[addresses[i]] = 0;

            emit Withdrawn(addresses[i], balance);

            (bool success, ) = payable(addresses[i]).call{value: balance}("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     *
     * PUBLIC VIEWS
     *
     */

    /**
     *
     * calculateFee - Calculates the auction fee based on seller history
     *
     * @param sellerAddress - Address of seller
     * @param useDiscount - Whether to check for discounts
     *
     * Dynamic fees are designed to encourage sellers to:
     *
     *  a) use Starting Price / Buy Now prices that reflect market conditions
     *  b) list high quality names
     *  c) prevent listing spam
     *  d) make sure all auctions remain claimable
     * 
     */
    function calculateFee(address sellerAddress, bool useDiscount) public view returns (uint256) {
        Seller storage seller = sellers[sellerAddress];

        return feeCalculator.calculateFee(
            _getActiveAuctionCount(),
            sellerAddress,
            seller.totalAuctions,
            seller.totalSold,
            seller.totalUnclaimable,
            seller.totalBidderAbandoned,
            useDiscount
        );
    }

    /**
     * getAuctionTokens - Get the token ids of an auction
     *
     * @param auctionId - The id of the auction
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

    function getNextEventStartTime() public view returns (uint64) {
        return _getEventTime(eventStartDay, eventStartTime);
    }

    function getNextEventEndTime() public view returns (uint64) {
        uint64 startTime = _getEventTime(eventStartDay, eventStartTime);
        uint64 endTime = _getEventTime(eventEndDay, eventEndTime);

        if (startTime >= endTime) {
            endTime += 7 days;
        }

        return endTime;
    }

    function _getEventTime(uint256 dayOfWeek, uint256 time) internal view returns (uint64) {
        uint256 daysUntilNextEvent;
        uint256 nextEventTime;

        unchecked {
            daysUntilNextEvent = (7 + dayOfWeek - (block.timestamp / 1 days + 4) % 7) % 7;
            nextEventTime = (block.timestamp / 1 days + daysUntilNextEvent) * 1 days + time;

            if (daysUntilNextEvent == 0 && block.timestamp % 1 days > time) {
                nextEventTime += 7 days;
            }
        }

        return uint64(nextEventTime);
    }

    /**
     *
     * SETTERS
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

    function setSettlementDuration(uint256 settlementDuration_) external onlyOwner {
        settlementDuration = settlementDuration_;
        emit SettlementDurationUpdated(settlementDuration_);
    }

    function setAntiSnipeDuration(uint256 antiSnipeDuration_) external onlyOwner {
        antiSnipeDuration = antiSnipeDuration_;
        emit AntiSnipeDurationUpdated(antiSnipeDuration_);
    }

    function setEventSchedule(
        uint256 startDayOfWeek,
        uint256 startTime,
        uint256 endDayOfWeek,
        uint256 endTime
    ) external onlyOwner {
        if (startDayOfWeek >= 7 || 
            startTime >= 24 hours || 
            endDayOfWeek >= 7 || 
            endTime >= 24 hours) {
            revert InvalidEventSchedule();
        }
        
        eventStartDay = startDayOfWeek;
        eventStartTime = startTime;
        eventEndDay = endDayOfWeek;
        eventEndTime = endTime;

        emit EventScheduleUpdated(startDayOfWeek, startTime, endDayOfWeek, endTime);
    }

    /**
     *
     * INTERNAL FUNCTIONS
     *
     */


    /**
     * _validateTokens - Validates tokens before an auction starts
     *
     * @param tokenIds - The token ids to auction
     * @param wrapped - Whether the tokens are wrapped
     * @param endTime - The end time of the auction
     *
     */
    function _validateTokens(uint256[] calldata tokenIds, bool[] calldata wrapped, uint64 endTime) internal {
        uint256 length = tokenIds.length;
        uint64 minExpiry = uint64(endTime + settlementDuration);

        for (uint256 i; i < length; ++i) {
            uint256 tokenId = tokenIds[i];
            uint256 existingAuctionId = tokenOnAuction[tokenId];
        
            // Check if the token is already in an auction
            if (existingAuctionId != 0) {
                Auction storage existingAuction = auctions[existingAuctionId];

                if (block.timestamp < existingAuction.endTime || 
                    (
                        block.timestamp >= existingAuction.endTime &&
                        existingAuction.highestBidder != address(0)
                    )
                ) {
                    revert TokenAlreadyInAuction();
                }
            }
            
            // Prevent duplicate tokens in the same auction
            if (existingAuctionId == nextAuctionId) {
                revert TokenAlreadyInAuction();
            }

            tokenOnAuction[tokenId] = nextAuctionId;

            // Check ownership and expiry
            if (wrapped[i]) {
                (address _owner, uint32 fuses, uint64 expiry) = ensNameWrapper.getData(tokenId);
                if (_owner != msg.sender) revert TokenNotOwned();
                if (expiry < minExpiry) revert TokenExpired();
                if (fuses & CANNOT_TRANSFER != 0) revert TokenNotTransferrable();
            } else {
                if (ensRegistrar.ownerOf(tokenId) != msg.sender) revert TokenNotOwned();
                if (ensRegistrar.nameExpires(tokenId) < minExpiry) revert TokenExpired();
            }
        }
    }

    /**
     * _processPayment - Process payment for a bid. If a bidder has a balance, use that first.
     *
     * @param paymentDue - The total amount due
     *
     */
    function _processPayment(uint256 paymentDue) internal {
        uint256 balance = balances[msg.sender];
        uint256 paymentFromBalance;
        uint256 paymentFromMsgValue;

        if (balance >= paymentDue) {
            paymentFromBalance = paymentDue;
            paymentFromMsgValue = 0;
        } else {
            paymentFromBalance = balance;
            paymentFromMsgValue = paymentDue - balance;
        }

        if (msg.value != paymentFromMsgValue) {
            revert InvalidValue();
        }

        if (paymentFromBalance > 0) {
            balances[msg.sender] -= paymentFromBalance;
        }
    }

    /**
     * _processFee - Process fee for new auction. If seller has a balance, use that first.
     *
     * @param paymentDue - The total amount due
     *
     */
    function _processFee(uint256 paymentDue) internal {
        uint256 balance = balances[msg.sender];
        uint256 paymentFromBalance;
        uint256 paymentFromMsgValue;

        if (balance >= paymentDue) {
            paymentFromBalance = paymentDue;
            paymentFromMsgValue = 0;
        } else {
            paymentFromBalance = balance;
            paymentFromMsgValue = paymentDue - balance;
        }

        if (msg.value != paymentFromMsgValue) {
            revert InvalidValue();
        }

        if (paymentFromBalance > 0) {
            balances[msg.sender] -= paymentFromBalance;
        }

        (bool success, ) = payable(feeRecipient).call{value: msg.value + paymentFromBalance}("");
        if (!success) revert TransferFailed();
    }

    /**
     * _transferTokens - Transfer auction tokens to the highest bidder
     *
     * @param auction - The auction to transfer tokens from
     *
     * note: we save some gas by not checking if an auction has any bids as
     * Registrar (ERC721) / NameWrapper (ERC1155) will both revert for transfer
     * attempts to address(0).
     */
    function _transferTokens(Auction storage auction) internal {
        address seller = auction.seller;
        uint256 tokenCount = auction.tokenCount;
        address highestBidder = auction.highestBidder;
        
        _resetTokens(auction);

        for (uint256 i; i < tokenCount; ++i) {
            uint256 tokenId = auction.tokens[i].tokenId;

            if (auction.tokens[i].isWrapped) {
                ensNameWrapper.safeTransferFrom(seller, highestBidder, tokenId, 1, "");
            } else {
                ensRegistrar.transferFrom(seller, highestBidder, tokenId);
            }
        }
    }

    function _getActiveAuctionCount() internal view returns (uint256) {
        uint256 count = 0;

        for (uint256 i = nextAuctionId - 1; i > 0; ) {
            Auction storage auction = auctions[i];

            if (auction.status == Status.Active && block.timestamp < auction.endTime) {
                unchecked {
                    ++count;
                }
            } else if (block.timestamp >= auction.endTime) {
                break;
            }

            unchecked {
                --i;
            }
        }

        return count;
    }

    /**
     * _isClaimable - Internal check if an auction is claimable in case user c
     *
     * @param auction - The auction to check
     *
     */
    function _isClaimable(Auction storage auction) internal view returns (bool) {
        bool isApprovedForAllWrapped = false;
        bool isApprovedForAllUnwrapped = false;
        bool checkApprovedForAllWrapped = false;
        bool checkApprovedForAllUnwrapped = false;

        for (uint256 i; i < auction.tokenCount; ++i) {
            Token memory token = auction.tokens[i];

            if (token.isWrapped) {
                if (!checkApprovedForAllWrapped) {
                    checkApprovedForAllWrapped = true;
                    isApprovedForAllWrapped = ensNameWrapper.isApprovedForAll(auction.seller, address(this));
                }

                if (!isApprovedForAllWrapped && ensNameWrapper.getApproved(token.tokenId) != address(this)) {
                    return false;
                }

                (address _owner, uint32 fuses, ) = ensNameWrapper.getData(token.tokenId);

                if (_owner != auction.seller || fuses & CANNOT_TRANSFER != 0) {
                    return false;
                }
            } else {
                if (!checkApprovedForAllUnwrapped) {
                    checkApprovedForAllUnwrapped = true;
                    isApprovedForAllUnwrapped = ensRegistrar.isApprovedForAll(auction.seller, address(this));
                }

                if (!isApprovedForAllUnwrapped && ensRegistrar.getApproved(token.tokenId) != address(this)) {
                    return false;
                }

                if (ensRegistrar.ownerOf(token.tokenId) != auction.seller) {
                    return false;
                }
            }
        }

        return true;
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
            tokenOnAuction[auction.tokens[i].tokenId] = 0;
        }
    }
}

