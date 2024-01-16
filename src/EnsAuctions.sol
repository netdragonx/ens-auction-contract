// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "solady/src/auth/Ownable.sol";

enum Status {
    Active,
    Claimed,
    Refunded,
    Abandoned,
    Withdrawn
}

struct EnsAuction {
    uint64 endTime;
    uint8 tokenCount;
    Status status;
    address highestBidder;
    uint256 highestBid;
    mapping(uint256 => uint256) tokenIds;
}

contract EnsAuctions is Ownable {
    uint256 public constant ABANDONMENT_FEE_PERCENT = 20;
    IERC721 public constant ENS_BASE_REGISTRAR = IERC721(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);

    uint256 public maxTokens = 10;
    uint256 public nextAuctionId = 1;
    uint256 public minStartingBid = 0.05 ether;
    uint256 public minBidIncrement = 0.01 ether;
    uint256 public auctionDuration = 7 days;
    uint256 public settlementDuration = 7 days;
    
    mapping(uint256 => EnsAuction) public auctions;
    mapping(uint256 => bool) public auctionTokens;

    error AuctionAbandoned();
    error AuctionActive();
    error AuctionClaimed();
    error AuctionEnded();
    error AuctionIsApproved();
    error AuctionNotClaimed();
    error AuctionNotEnded();
    error AuctionRefunded();
    error AuctionWithdrawn();
    error BidTooLow();
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

    event Abandoned(uint256 indexed auctionId, address indexed bidder, uint256 indexed fee);
    event AuctionStarted(address indexed bidder, uint256[] indexed tokenIds);
    event Claimed(uint256 indexed auctionId, address indexed winner);
    event NewBid(uint256 indexed auctionId, address indexed bidder, uint256 indexed value);
    event Refunded(uint256 indexed auctionId, address indexed bidder, uint256 indexed value);
    event Withdrawn(uint256 indexed auctionId, address indexed bidder, uint256 indexed value);

    constructor() {
        _initializeOwner(msg.sender);
    }

    /**
     *
     * startAuction - Starts an auction for one or more ENS
     *
     * @param tokenIds - The token ids to auction
     *
     */

    function startAuction(uint256[] calldata tokenIds) external payable {
        if (msg.value < minStartingBid) {
            revert StartPriceTooLow();
        }

        _validateAuctionTokens(tokenIds);

        EnsAuction storage auction = auctions[nextAuctionId];

        auction.endTime = uint64(block.timestamp + auctionDuration);
        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        auction.tokenCount = uint8(tokenIds.length);

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenIds.length;) {
            tokenMap[i] = tokenIds[i];

            unchecked {
                ++i;
            }
        }

        unchecked {
            ++nextAuctionId;
        }

        emit AuctionStarted(msg.sender, tokenIds);
    }

    /**
     * bid - Places a bid on an auction
     *
     * @param auctionId - The id of the auction to bid on
     *
     */

    function bid(uint256 auctionId) external payable {
        EnsAuction storage auction = auctions[auctionId];

        if (block.timestamp > auction.endTime) {
            revert AuctionEnded();
        }

        if (block.timestamp >= auction.endTime - 1 hours) {
            auction.endTime += 1 hours;
        }

        if (msg.value < auction.highestBid + minBidIncrement) {
            revert BidTooLow();
        }

        address prevHighestBidder = auction.highestBidder;
        uint256 prevHighestBid = auction.highestBid;

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        if (prevHighestBidder != address(0)) {
            (bool success,) = payable(prevHighestBidder).call{value: prevHighestBid}("");
            if (!success) revert TransferFailed();
        }

        emit NewBid(auctionId, msg.sender, msg.value);
    }

    /**
     * claim - Claims the tokens from an auction
     *
     * @param auctionId - The id of the auction to claim
     *
     */

    function claim(uint256 auctionId) external {
        EnsAuction storage auction = auctions[auctionId];

        if (block.timestamp < auction.endTime) {
            revert AuctionNotEnded();
        }

        if (msg.sender != auction.highestBidder) {
            revert NotHighestBidder();
        }

        if (auction.status != Status.Active) {
            if (auction.status == Status.Refunded) {
                revert AuctionRefunded();
            } else if (auction.status == Status.Claimed) {
                revert AuctionClaimed();
            } else if (auction.status == Status.Abandoned) {
                revert AuctionAbandoned();
            }
        }

        auction.status = Status.Claimed;

        _transferTokens(auction);
        
        emit Claimed(auctionId, msg.sender);
    }

    /**
     * refund - Refunds are available during the settlement period if the item is not approved for transfer
     *
     * @param auctionId - The id of the auction to refund
     *
     */
    function refund(uint256 auctionId) external {
        EnsAuction storage auction = auctions[auctionId];
        uint256 highestBid = auction.highestBid;
        uint256 endTime = auction.endTime;

        if (block.timestamp < endTime) {
            revert AuctionActive();
        }

        if (block.timestamp > endTime + settlementDuration) {
            revert SettlementPeriodEnded();
        }

        if (msg.sender != auction.highestBidder) {
            revert NotHighestBidder();
        }

        if (auction.status != Status.Active) {
            if (auction.status == Status.Refunded) {
                revert AuctionRefunded();
            } else if (auction.status == Status.Claimed) {
                revert AuctionClaimed();
            } else if (auction.status == Status.Withdrawn) {
                revert AuctionWithdrawn();
            }
        }

        _checkAndResetTokens(auction);
        
        auction.status = Status.Refunded;

        (bool success,) = payable(msg.sender).call{value: highestBid}("");
        if (!success) revert TransferFailed();

        emit Refunded(auctionId, msg.sender, highestBid);
    }

    /**
     *
     * abandon - Mark unclaimed auctions as abandoned after the settlement period
     *
     * @param auctionId - The id of the auction to abandon
     *
     */
    function abandon(uint256 auctionId) external onlyOwner {
        EnsAuction storage auction = auctions[auctionId];
        address highestBidder = auction.highestBidder;
        uint256 highestBid = auction.highestBid;

        if (block.timestamp < auction.endTime + settlementDuration) {
            revert SettlementPeriodNotExpired();
        }

        if (auction.status != Status.Active) {
            if (auction.status == Status.Abandoned) {
                revert AuctionAbandoned();
            } else if (auction.status == Status.Refunded) {
                revert AuctionRefunded();
            } else if (auction.status == Status.Claimed) {
                revert AuctionClaimed();
            }
        }

        auction.status = Status.Abandoned;

        _resetTokens(auction);
        
        uint256 fee = highestBid * ABANDONMENT_FEE_PERCENT / 100;

        (bool success,) = payable(highestBidder).call{value: highestBid - fee}("");
        if (!success) revert TransferFailed();

        (success,) = payable(msg.sender).call{value: fee}("");
        if (!success) revert TransferFailed();

        emit Abandoned(auctionId, highestBidder, fee);
    }

    /**
     * withdraw - Withdraws the highest bid from claimed auctions
     *
     * @param auctionIds - The ids of the auctions to withdraw from
     *
     * @notice - Auctions can only be withdrawn after the settlement period has ended.
     *
     */

    function withdraw(uint256[] calldata auctionIds) external onlyOwner {
        uint256 totalAmount;

        for (uint256 i; i < auctionIds.length;) {
            EnsAuction storage auction = auctions[auctionIds[i]];

            if (auction.status != Status.Claimed) {
                revert AuctionNotClaimed();
            }

            totalAmount += auction.highestBid;
            auction.status = Status.Withdrawn;

            unchecked {
                ++i;
            }
        }

        (bool success,) = payable(msg.sender).call{value: totalAmount}("");
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

        for (uint256 i; i < tokenCount;) {
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

    function setMinStartingBid(uint256 minStartingBid_) external onlyOwner {
        minStartingBid = minStartingBid_;
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

    function _validateAuctionTokens(uint256[] calldata tokenIds) internal {
        if (tokenIds.length == 0) {
            revert InvalidLengthOfTokenIds();
        }

        IERC721 erc721Contract = IERC721(ENS_BASE_REGISTRAR);

        if (tokenIds.length > maxTokens) {
            revert MaxTokensPerTxReached();
        }

        for (uint256 i; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];

            if (auctionTokens[tokenId]) {
                revert TokenAlreadyInAuction();
            }

            auctionTokens[tokenId] = true;

            if (erc721Contract.ownerOf(tokenId) != msg.sender) {
                revert TokenNotOwned();
            }

            unchecked {
                ++i;
            }
        }
    }


    function _transferTokens(EnsAuction storage auction) internal {
        uint256 tokenCount = auction.tokenCount;
        address highestBidder = auction.highestBidder;

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenCount;) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;
            ENS_BASE_REGISTRAR.transferFrom(msg.sender, highestBidder, tokenId);

            unchecked {
                ++i;
            }
        }
    }


    function _resetTokens(EnsAuction storage auction) internal {
        uint256 tokenCount = auction.tokenCount;

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        for (uint256 i; i < tokenCount;) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;

            unchecked {
                ++i;
            }
        }
    }

    function _checkAndResetTokens(EnsAuction storage auction) internal {
        uint256 tokenCount = auction.tokenCount;

        mapping(uint256 => uint256) storage tokenMap = auction.tokenIds;

        bool notRefundable = ENS_BASE_REGISTRAR.isApprovedForAll(msg.sender, address(this));

        for (uint256 i; i < tokenCount;) {
            uint256 tokenId = tokenMap[i];
            auctionTokens[tokenId] = false;

            notRefundable = notRefundable && (ENS_BASE_REGISTRAR.ownerOf(tokenId) == msg.sender);

            unchecked {
                ++i;
            }
        }

        if (notRefundable) {
            revert AuctionIsApproved();
        }
    }
}
