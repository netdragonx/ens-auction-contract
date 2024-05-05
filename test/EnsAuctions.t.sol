// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/EnsAuctions.sol";
import "../src/IEnsAuctions.sol";
import "./lib/Mock721.sol";

contract EnsAuctionsTest is Test {
    EnsAuctions public auctions;
    Mock721 public mockEns;

    address public feeRecipient;
    address public user1;
    address public user2;
    address public user3;

    uint256 public startingPrice = 0.01 ether;
    uint256 public buyNowPrice = 0.05 ether;

    uint256 public tokenCount = 10;
    uint256[] public tokenIds = [0, 1, 2];
    uint256[] public tokenIds1 = [0];
    uint256[] public tokenIds2 = [1];
    uint256[] public tokenIds3 = [2];

    receive() external payable {}
    fallback() external payable {}

    function setUp() public {
        mockEns = new Mock721();
        auctions = new EnsAuctions(address(mockEns), address(feeRecipient));

        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        mockEns.mint(user1, tokenCount);
        
        vm.prank(user1);
        mockEns.setApprovalForAll(address(auctions), true);
    }

    //
    // startAuction()
    //
    function test_startAuction_Success() public {
        vm.startPrank(user1);

        uint256 startBalance = user1.balance;
        uint256 fee = auctions.calculateFee(user1);

        auctions.startAuction{value: fee}(tokenIds, startingPrice, buyNowPrice);
        assertEq(user1.balance, startBalance - fee, "Balance should decrease by fee");
        assertEq(auctions.nextAuctionId(), 2, "nextAuctionId should be incremented");
        assertEq(feeRecipient.balance, fee, "feeRecipient should have received the fee");

        (
            uint64 _endTime, 
            uint64 _buyNowEndTime, 
            uint8 _tokenCount,
            , 
            address _seller, 
            address _highestBidder, 
            uint256 _highestBid, 
            uint256 _startingPrice, 
            uint256 _buyNowPrice
        ) = auctions.auctions(1);

        assertEq(_endTime, block.timestamp + auctions.auctionDuration(), "Auction end time should be set correctly");
        assertEq(_buyNowEndTime, block.timestamp + auctions.buyNowDuration(), "Buy now end time should be set correctly");
        assertEq(_tokenCount, 3, "Token count should match the number of tokens auctioned");
        assertEq(_seller, user1, "Seller should be user1");
        assertEq(_highestBidder, address(0));
        assertEq(_highestBid, 0 ether);
        assertEq(_startingPrice, startingPrice);
        assertEq(_buyNowPrice, buyNowPrice);

        uint256[] memory auctionTokens = auctions.getAuctionTokens(auctions.nextAuctionId() - 1);
        assertEq(auctionTokens[0], tokenIds[0]);
        assertEq(auctionTokens[1], tokenIds[1]);
        assertEq(auctionTokens[2], tokenIds[2]);
    }

    function testFuzz_startAuction_Success(uint256 _startingPrice) public {
        vm.assume(_startingPrice >= auctions.minStartingPrice());
        vm.assume(user1.balance >= _startingPrice);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        assertEq(auctions.nextAuctionId(), 2, "nextAuctionId should be incremented");

        (
            uint64 _endTime,
            uint64 _buyNowEndTime,
            uint8 _tokenCount,
            ,
            address _seller,
            address _highestBidder,
            uint256 _highestBid,
            ,
        ) = auctions.auctions(1);

        assertEq(_highestBidder, address(0));
        assertEq(_highestBid, 0);
        assertEq(_seller, user1);
        assertEq(_tokenCount, 3);
        assertEq(_endTime, block.timestamp + auctions.auctionDuration());
        assertEq(_buyNowEndTime, block.timestamp + auctions.buyNowDuration());
    }

    function test_startAuction_Success_NextAuctionIdIncrements() public {
        uint256 nextAuctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);

        skip(auctions.auctionDuration() + 1);

        auctions.claim(nextAuctionId);

        mockEns.transferFrom(user2, user1, tokenIds[0]);
        mockEns.transferFrom(user2, user1, tokenIds[1]);
        mockEns.transferFrom(user2, user1, tokenIds[2]);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        assertEq(auctions.nextAuctionId(), nextAuctionId + 2, "nextAuctionId should be incremented");
    }

    function test_startAuction_RevertIf_InvalidFee() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        vm.expectRevert(bytes4(keccak256("InvalidFee()")));
        auctions.startAuction{value: fee - 0.01 ether}(tokenIds, startingPrice, buyNowPrice);
    }

    function test_startAuction_RevertIf_MaxTokensPerTxReached() public {
        auctions.setMaxTokens(10);
        vm.startPrank(user1);
        uint256[] memory manyTokenIds = new uint256[](11);
        uint256 fee = auctions.calculateFee(user1);
        vm.expectRevert(bytes4(keccak256("MaxTokensPerTxReached()")));
        auctions.startAuction{value: fee}(manyTokenIds, startingPrice, buyNowPrice);
    }

    function test_startAuction_RevertIf_StartPriceTooLow() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        vm.expectRevert(bytes4(keccak256("StartPriceTooLow()")));
        auctions.startAuction{value: fee}(tokenIds, startingPrice - 0.001 ether, buyNowPrice);
    }

    function test_startAuction_RevertIf_BuyNowTooLow() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        vm.expectRevert(bytes4(keccak256("BuyNowTooLow()")));
        auctions.startAuction{value: fee}(tokenIds, startingPrice, buyNowPrice - 0.001 ether);
    }

    function test_startAuction_RevertIf_TokenAlreadyInAuction() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        vm.expectRevert(bytes4(keccak256("TokenAlreadyInAuction()")));
        auctions.startAuction{value: fee}(tokenIds, startingPrice, buyNowPrice);
    }

    function test_startAuction_RevertIf_InvalidLengthOfTokenIds() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        vm.expectRevert(bytes4(keccak256("InvalidLengthOfTokenIds()")));
        auctions.startAuction{value: fee}(new uint256[](0), startingPrice, buyNowPrice);
    }

    function test_startAuction_RevertIf_TokenNotOwned() public {
        mockEns.mint(user2, 10);

        uint256[] memory notOwnedTokenIds = new uint256[](1);
        notOwnedTokenIds[0] = tokenCount + 1;

        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        vm.expectRevert(bytes4(keccak256("TokenNotOwned()")));
        auctions.startAuction{value: fee}(notOwnedTokenIds, startingPrice, buyNowPrice);
    }

    function test_startAuction_Fees() public {
        vm.startPrank(user1);
        uint256 startBalance = user1.balance;
        
        uint256 fee1 = auctions.calculateFee(user1);
        auctions.startAuction{value: fee1}(tokenIds1, startingPrice, buyNowPrice);

        uint256 fee2 = auctions.calculateFee(user1);
        auctions.startAuction{value: fee2}(tokenIds2, startingPrice, buyNowPrice);

        uint256 fee3 = auctions.calculateFee(user1);
        auctions.startAuction{value: fee3}(tokenIds3, startingPrice, buyNowPrice);

        // uint256 public baseFee = 0.05 ether;
        // uint256 public linearFee = 0.01 ether;
        // uint256 public penaltyFee = 0.01 ether;
        assertEq(user1.balance, startBalance - fee1 - fee2 - fee3, "Balance should decrease by fee");
        assertEq(feeRecipient.balance, fee1 + fee2 + fee3, "feeRecipient should have received the fee");
        assertEq(fee1, 0.05 ether, "base fee is 0.05 ether");
        assertEq(fee2, 0.06 ether, "fee w/ linear fee is 0.06 ether");
        assertEq(fee3, 0.07 ether, "fee w/ linear fee * 2 is 0.07 ether");
    }

    //
    // bid()
    //
    function test_bid_Success() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);

        (,,,,, address highestBidder, uint256 highestBid,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, startingPrice, "Highest bid incorrect");
    }

    function test_bid_Success_SelfBidding() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);
        auctions.bid{value: startingPrice + auctions.minBidIncrement()}(1, startingPrice + auctions.minBidIncrement());

        (,,,,, address highestBidder, uint256 highestBid,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, startingPrice + auctions.minBidIncrement(), "Highest bid incorrect");
    }

    function test_bid_Success_LastMinuteBidding() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        (uint256 endTimeA,,,,,,,,) = auctions.auctions(1);

        skip(60 * 60 * 24 * 7 - 59); // 1 second before auction ends

        vm.startPrank(user2);
        auctions.bid{value: 0.06 ether}(1, 0.06 ether);

        (uint256 endTimeB,,,,,,,,) = auctions.auctions(1);

        assertLt(endTimeA, endTimeB, "New endtime should be greater than old endtime");
    }

    function test_bid_Success_UsingAvailableBalance() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, 0.01 ether, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.01 ether}(1, 0.01 ether);
        
        (,,,,, address highestBidder1, uint256 highestBid1,,) = auctions.auctions(1);
        assertEq(highestBid1, 0.01 ether);
        assertEq(highestBidder1, user2);

        vm.startPrank(user3);
        auctions.bid{value: 0.02 ether}(1, 0.02 ether);
        
        (,,,,, address highestBidder2, uint256 highestBid2,,) = auctions.auctions(1);
        assertEq(highestBid2, 0.02 ether);
        assertEq(highestBidder2, user3);

        (uint16 totalBids,,,,, uint256 balance) = auctions.bidders(user2);
        assertEq(totalBids, 1, "should have 1 total bids");
        assertEq(balance, 0.01 ether, "balance should be 0.01 ether");

        vm.startPrank(user2);
        auctions.bid{value: 0.02 ether}(1, 0.03 ether);
        
        (,,,,, address highestBidder3, uint256 highestBid3,,) = auctions.auctions(1);
        assertEq(highestBid3, 0.03 ether);
        assertEq(highestBidder3, user2);
        
        assertEq(user2.balance, 1 ether - 0.03 ether);
        assertEq(user3.balance, 1 ether - 0.02 ether);

        (uint16 totalBids2, uint16 totalOutbids2,,,, uint256 balance2) = auctions.bidders(user2);
        assertEq(totalBids2, 2, "should have 2 total bids");
        assertEq(totalOutbids2, 1, "should have 1 total outbids");
        assertEq(balance2, 0, "balance should be 0 ether");

        (uint16 totalBids3, uint16 totalOutbids3,,,, uint256 balance3) = auctions.bidders(user3);
        assertEq(totalBids3, 1, "should have 1 total bids");
        assertEq(totalOutbids3, 1, "should have 1 total outbids");
        assertEq(balance3, 0.02 ether, "balance should be 0.02 ether");
    }

    function test_bid_RevertIf_AuctionBuyNowPeriod() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("AuctionBuyNowPeriod()")));
        auctions.bid{value: startingPrice}(1, startingPrice);
    }

    function test_bid_RevertIf_AuctionEnded() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("AuctionEnded()")));
        auctions.bid{value: startingPrice}(1, startingPrice);
    }

    function test_bid_RevertIf_SellerCannotBid() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.expectRevert(bytes4(keccak256("SellerCannotBid()")));
        auctions.bid{value: startingPrice}(1, startingPrice);
    }

    function test_bid_RevertIf_BelowMinimumIncrement() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        auctions.startAuction{value: fee}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);
        
        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);
        
        vm.startPrank(user3);
        uint256 minBidIncrement = auctions.minBidIncrement();
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: startingPrice + minBidIncrement - 1}(1, startingPrice + minBidIncrement - 1);
    }

    function test_bid_RevertIf_BidEqualsHighestBid() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        vm.startPrank(user3);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
    }

    function testFuzz_bid_Success(uint256 bidA, uint256 bidB) public {
        uint256 _bidA = bound(bidA, 0.05 ether, 1000 ether);
        uint256 _bidB = bound(bidB, _bidA + auctions.minBidIncrement(), type(uint256).max);
        vm.assume(_bidB > _bidA && user2.balance >= _bidA && user3.balance >= _bidB);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: _bidA}(1, _bidA);

        vm.startPrank(user3);
        auctions.bid{value: _bidB}(1, _bidB);

        (,,,,, address highestBidder, uint256 highestBid,,) = auctions.auctions(1);

        assertEq(highestBidder, user3, "Highest bidder should be this contract");
        assertEq(highestBid, _bidB, "Highest bid should be 0.06 ether");
    }

    //
    // buyNow()
    //
    function test_buyNow_Success() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        auctions.startAuction{value: fee}(tokenIds, startingPrice, buyNowPrice);

        assertEq(feeRecipient.balance, fee, "feeRecipient should receive fee");

        vm.startPrank(user2);
        auctions.buyNow{value: buyNowPrice}(1);

        (,,,,, address highestBidder, uint256 highestBid,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, buyNowPrice, "Highest bid incorrect");

        (
            uint16 totalBids, 
            uint16 totalOutbids, 
            uint16 totalClaimed, 
            uint16 totalBuyNow, 
            uint16 totalAbandoned, 
            uint256 balance
        ) = auctions.bidders(user2);

        assertEq(totalBids, 0, "should have 0 total bids");
        assertEq(totalOutbids, 0, "should have 0 total outbids");
        assertEq(totalClaimed, 0, "should have 0 total claimed");
        assertEq(totalBuyNow, 1, "should have 1 total buy now");
        assertEq(totalAbandoned, 0, "should have 0 total abandoned");
        assertEq(balance, 0, "balance should be 0 ether");
    }

    //
    // claim()
    //
    function test_claim_Success() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        (,,,,, address highestBidder, uint256 highestBid,,) = auctions.auctions(auctionId);

        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");

        skip(auctions.auctionDuration() + 1);
        auctions.claim(auctionId);

        assertEq(user2.balance, 1 ether - startingPrice, "user2 should have 0.94 ether");
        assertEq(mockEns.ownerOf(tokenIds[0]), user2, "Should own token 0");
        assertEq(mockEns.ownerOf(tokenIds[1]), user2, "Should own token 1");
        assertEq(mockEns.ownerOf(tokenIds[2]), user2, "Should own token 2");
    }

    function test_claim_RevertIf_BeforeAuctionEnded() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);

        vm.expectRevert(bytes4(keccak256("AuctionNotEnded()")));
        auctions.claim(1);
    }

    function test_claim_RevertIf_NotHighestBidder() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user3);
        vm.expectRevert(bytes4(keccak256("NotHighestBidder()")));
        auctions.claim(auctionId);
    }

    function test_claim_RevertIf_AbandonedAuction() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.startPrank(user1);
        auctions.markAbandoned(auctionId);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.claim(auctionId);
    }

    function test_claim_RevertIf_AuctionClaimed() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + 1);
        
        auctions.claim(auctionId);
        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.claim(auctionId);
    }


    //
    // markAbandoned()
    //
    function test_markAbandoned_Success() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.startPrank(user1);
        auctions.markAbandoned(auctionId);

        (,,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Abandoned, "Status should be Abandoned");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be startingPrice");
    }

    function test_markAbandoned_RevertIf_AuctionAbandoned() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.startPrank(user1);
        auctions.markAbandoned(auctionId);

        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.markAbandoned(auctionId);
    }

    function test_markAbandoned_RevertIf_AuctionHadNoBids() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + auctions.auctionDuration() + auctions.settlementDuration() + 1);
        
        vm.expectRevert(bytes4(keccak256("AuctionHadNoBids()")));
        auctions.markAbandoned(auctionId);
    }

    //
    // markUnclaimable()
    //
    function test_markUnclaimable_Success_SellerMovesTokens() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 moves a token mid auction
        vm.startPrank(user1);
        mockEns.transferFrom(user1, user3, tokenIds[0]);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_Success_SellerRemovesApprovalForAll() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 moves a token mid auction
        vm.startPrank(user1);
        mockEns.setApprovalForAll(address(auctions), false);
        
        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_Success_SellerRemovesApprovalForOne() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        mockEns.setApprovalForAll(address(auctions), false);
        mockEns.approve(address(auctions), tokenIds[0]);
        mockEns.approve(address(auctions), tokenIds[1]);
        mockEns.approve(address(auctions), tokenIds[2]);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 disapproves a token mid auction
        vm.startPrank(user1);
        mockEns.approve(address(0), tokenIds[0]);
        
        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_RevertIf_AuctionIsClaimable() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + 1);

        vm.expectRevert(bytes4(keccak256("AuctionIsClaimable()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_AuctionIsClaimableViaSoloApprovals() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        mockEns.setApprovalForAll(address(auctions), false);
        mockEns.approve(address(auctions), tokenIds[0]);
        mockEns.approve(address(auctions), tokenIds[1]);
        mockEns.approve(address(auctions), tokenIds[2]);

        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + 1);

        vm.expectRevert(bytes4(keccak256("AuctionIsClaimable()")));
        auctions.markUnclaimable(auctionId);
    }

    //
    // withdrawBalance
    //
    function test_withdrawBalance_Success() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, 0.01 ether, buyNowPrice);
        
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.01 ether}(1, 0.01 ether);
        
        (,,,,, address highestBidder1, uint256 highestBid1,,) = auctions.auctions(1);
        assertEq(highestBid1, 0.01 ether);
        assertEq(highestBidder1, user2);

        vm.startPrank(user3);
        auctions.bid{value: 0.02 ether}(1, 0.02 ether);

        vm.startPrank(user2);
        auctions.withdrawBalance();
        assertEq(user2.balance, 1 ether);
    }

    //
    // getters/setters
    //
    function test_getAuctionTokens_Success() public {
        auctions.setMaxTokens(50);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        (uint256[] memory _tokenIds) = auctions.getAuctionTokens(1);

        assertEq(_tokenIds[0], tokenIds[0]);
        assertEq(_tokenIds[1], tokenIds[1]);
        assertEq(_tokenIds[2], tokenIds[2]);
    }

    function test_setMinStartingBid_Success() public {
        auctions.setMinStartingBid(0.01 ether);

        vm.startPrank(user1);

        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
    }

    function test_setMinBidIncrement_Success() public {
        auctions.setMinBidIncrement(0.02 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.07 ether}(1, 0.07 ether);
        auctions.bid{value: 0.09 ether}(1, 0.09 ether);
    }

    function test_setMinBidIncrement_RevertIf_BidTooLow() public {
        auctions.setMinBidIncrement(0.02 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.07 ether}(1, 0.07 ether);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: 0.08 ether}(1, 0.08 ether);
    }

    function test_setMaxTokens_Success() public {
        auctions.setMaxTokens(255);
    }

    function test_setMaxTokens_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setMaxTokens(255);
    }

    function test_setAuctionDuration_Success() public {
        auctions.setAuctionDuration(60 * 60 * 24 * 7);
    }

    function test_setAuctionDuration_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setAuctionDuration(60 * 60 * 24 * 7);
    }

    function test_setSettlementDuration_Success() public {
        auctions.setSettlementDuration(60 * 60 * 24 * 7);
    }

    function test_setSettlementDuration_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setSettlementDuration(60 * 60 * 24 * 7);
    }
}
