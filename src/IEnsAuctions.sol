// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IEnsAuctions {
    function startAuction(
        uint256 startingPrice,
        uint256 buyNowPrice,
        uint256[] calldata tokenIds,
        bool[] calldata wrapped,
        bool useDiscount
    ) external payable;

    function bid(uint256 auctionId, uint256 bidAmount) external payable;
    function buyNow(uint256 auctionId) external payable;
    function claim(uint256 auctionId) external;
    function markAbandoned(uint256 auctionId) external;
    function markUnclaimable(uint256 auctionId) external;
    function withdrawBalance() external;

    function calculateFee(address sellerAddress, bool useDiscount) external view returns (uint256);
    function getAuctionTokens(uint256 auctionId) external view returns (uint256[] memory);
    function getNextEventTime() external view returns (uint64);

    function setMaxTokens(uint256 maxTokens_) external;
    function setMinBuyNowPrice(uint256 minBuyNowPrice_) external;
    function setMinStartingBid(uint256 minStartingPrice_) external;
    function setMinBidIncrement(uint256 minBidIncrement_) external;
    function setAuctionDuration(uint256 auctionDuration_) external;
    function setSettlementDuration(uint256 settlementDuration_) external;
    function setAntiSnipeDuration(uint256 antiSnipeDuration_) external;
    function setEventSchedule(uint256 dayOfWeek, uint256 startTime) external;
    function setFeeCalculator(address feeCalculator_) external;
    function setFeeRecipient(address feeRecipient_) external;

    event Started(
        uint256 auctionId,
        address seller,
        uint256 startingPrice,
        uint256 buyNowPrice,
        uint64 endTime,
        uint64 buyNowEndTime,
        uint256 tokenCount,
        uint256[] tokenIds
    );
    event BuyNow(uint256 indexed auctionId, address buyer, uint256 value);
    event Bid(uint256 indexed auctionId, address bidder, uint256 value);
    event Claimed(uint256 indexed auctionId, address winner);
    event Abandoned(uint256 indexed auctionId);
    event Unclaimable(uint256 indexed auctionId);
    event Withdrawn(address indexed recipient, uint256 amount);
    event FeeCalculatorUpdated(address feeCalculator);
    event FeeRecipientUpdated(address feeRecipient);
    event MinStartingBidUpdated(uint256 minStartingBid);
    event MinBuyNowPriceUpdated(uint256 minBuyNowPrice);
    event MinBidIncrementUpdated(uint256 minBidIncrement);
    event AuctionDurationUpdated(uint256 auctionDuration);
    event SettlementDurationUpdated(uint256 settlementDuration);
    event AntiSnipeDurationUpdated(uint256 antiSnipeDuration);
    event MaxTokensUpdated(uint256 maxTokens);
    event EventScheduleUpdated(uint256 dayOfWeek, uint256 startTime);
    
    error AuctionBuyNowPeriod();
    error AuctionEnded();
    error AuctionHadNoBids();
    error AuctionIsClaimable();
    error AuctionNotEnded();
    error BidTooLow();
    error BuyNowTooLow();
    error BuyNowUnavailable();
    error InvalidEventSchedule();
    error InvalidFee();
    error InvalidLengthOfTokenIds();
    error InvalidStatus();
    error InvalidValue();
    error MaxTokensPerTxReached();
    error NotApproved();
    error NotAuthorized();
    error NotHighestBidder();
    error SellerCannotBid();
    error SettlementPeriodNotExpired();
    error SettlementPeriodEnded();
    error StartPriceTooLow();
    error TokenAlreadyInAuction();
    error TokenExpired();
    error TokenNotOwned();
    error TokenNotTransferrable();
    error TransferFailed();
}
