// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EnsAuctions.sol";
import "./lib/Mock721.sol";
import "./lib/Mock20.sol";

contract EnsAuctionsTest is Test {
    EnsAuctions public auctions;
    Mock721 public mockEns;

    address public user1;
    address public user2;
    address public user3;

    uint256 public startingPrice = 0.01 ether;
    uint256 public buyNowPrice = 0.05 ether;

    uint256 public tokenCount = 10;
    uint256[] public tokenIds = [0, 1, 2];

    receive() external payable {}
    fallback() external payable {}

    function setUp() public {
        mockEns = new Mock721();
        auctions = new EnsAuctions(address(this), address(mockEns));

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
        auctions.bid{value: startingPrice}(1);

        skip(auctions.auctionDuration() + 1);

        auctions.claim(nextAuctionId);

        mockEns.transferFrom(user2, user1, tokenIds[0]);
        mockEns.transferFrom(user2, user1, tokenIds[1]);
        mockEns.transferFrom(user2, user1, tokenIds[2]);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        assertEq(auctions.nextAuctionId(), nextAuctionId + 2, "nextAuctionId should be incremented");
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

    //
    // bid()
    //
    function test_bid_Success() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1);

        (,,,,, address highestBidder, uint256 highestBid,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, startingPrice, "Highest bid incorrect");
    }

    function test_bid_Success_SelfBidding() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1);
        auctions.bid{value: startingPrice + auctions.minBidIncrement()}(1);

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
        auctions.bid{value: 0.06 ether}(1);

        (uint256 endTimeB,,,,,,,,) = auctions.auctions(1);

        assertLt(endTimeA, endTimeB, "New endtime should be greater than old endtime");
    }

    function test_bid_RevertIf_BelowMinimumIncrement() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1);
        auctions.startAuction{value: fee}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);
        
        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1);
        
        vm.startPrank(user3);
        uint256 minBidIncrement = auctions.minBidIncrement();
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: startingPrice + minBidIncrement - 1}(1);
    }

    function test_bid_RevertIf_BidEqualsHighestBid() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId);

        vm.startPrank(user3);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: startingPrice}(auctionId);
    }

    function test_bid_RevertIf_AfterAuctionEnded() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("AuctionEnded()")));
        auctions.bid{value: startingPrice}(1);
    }

    function testFuzz_bid_Success(uint256 bidA, uint256 bidB) public {
        uint256 _bidA = bound(bidA, 0.05 ether, 1000 ether);
        uint256 _bidB = bound(bidB, _bidA + auctions.minBidIncrement(), type(uint256).max);
        vm.assume(_bidB > _bidA && user2.balance >= _bidA && user3.balance >= _bidB);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);
        
        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: _bidA}(1);

        vm.startPrank(user3);
        auctions.bid{value: _bidB}(1);

        (,,,,, address highestBidder, uint256 highestBid,,) = auctions.auctions(1);

        assertEq(highestBidder, user3, "Highest bidder should be this contract");
        assertEq(highestBid, _bidB, "Highest bid should be 0.06 ether");
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
        auctions.bid{value: startingPrice}(auctionId);

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
        auctions.bid{value: startingPrice}(1);

        vm.expectRevert(bytes4(keccak256("AuctionNotEnded()")));
        auctions.claim(1);
    }

    function test_claim_RevertIf_NotHighestBidder() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId);

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
        auctions.bid{value: startingPrice}(auctionId);

        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.startPrank(user1);
        auctions.markAbandoned(auctionId);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("AuctionAbandoned()")));
        auctions.claim(auctionId);
    }

    function test_claim_RevertIf_AuctionClaimed() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId);

        skip(auctions.auctionDuration() + 1);
        
        auctions.claim(auctionId);
        vm.expectRevert(bytes4(keccak256("AuctionClaimed()")));
        auctions.claim(auctionId);
    }

    //
    // withdraw
    //
    function test_withdraw_Success() public {
        vm.deal(address(this), 1 ether);
        vm.startPrank(address(this));
        auctions.withdraw();
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
        auctions.bid{value: 0.07 ether}(1);
        auctions.bid{value: 0.09 ether}(1);
    }

    function test_setMinBidIncrement_RevertIf_BidTooLow() public {
        auctions.setMinBidIncrement(0.02 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1)}(tokenIds, startingPrice, buyNowPrice);

        skip(auctions.buyNowDuration() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.07 ether}(1);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: 0.08 ether}(1);
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
