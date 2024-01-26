// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/EnsAuctions.sol";
import "./lib/Mock721.sol";

contract AuctionsTest is Test {
    EnsAuctions public auctions;
    Mock721 public mock721;

    address public theBarn;
    address public user1;
    address public user2;

    uint256 public buyItNow = 0.01 ether;
    uint256 public tokenCount = 10;
    uint256[] public tokenIds = [0, 1, 2];
    uint256[] public tokenIdsOther = [3, 4, 5];
    uint256[] public tokenIdAmounts = [10, 10, 10];
    uint256[] public amounts = [1, 1, 1];

    receive() external payable {}
    fallback() external payable {}
/*
    function setUp() public {
        theBarn = vm.addr(1);
        auctions = new EnsAuctions();
        mock721 = new Mock721();

        user1 = vm.addr(2);
        user2 = vm.addr(3);

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        mock721.mint(theBarn, tokenCount);
        
        vm.startPrank(theBarn);
        mock721.setApprovalForAll(address(auctions), true);
        vm.stopPrank();
    }

    //
    // startAuction()
    //
    function test_startAuction_Success() public {
        vm.startPrank(user1);

        uint256 startBalance = user1.balance;

        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        assertEq(user1.balance, startBalance - 0.05 ether, "Balance should decrease by 0.05 ether");
        assertEq(auctions.nextAuctionId(), 2, "nextAuctionId should be incremented");

        (, address tokenAddress,,,, address highestBidder, uint256 highestBid) = auctions.auctions(1);

        assertEq(tokenAddress, address(mock721));
        assertEq(highestBidder, user1);
        assertEq(highestBid, 0.05 ether);
    }

    function testFuzz_startAuction_Success(uint256 bidAmount) public {
        vm.assume(bidAmount > 0.05 ether);
        vm.assume(user1.balance >= bidAmount);

        vm.startPrank(user1);

        uint256 startBalance = user1.balance;

        auctions.startAuction{value: bidAmount}(tokenIds, buyItNow);
        assertEq(user1.balance, startBalance - bidAmount, "Balance should decrease by bid amount");
        assertEq(auctions.nextAuctionId(), 2, "nextAuctionId should be incremented");

        (, address tokenAddress,,,, address highestBidder, uint256 highestBid) = auctions.auctions(1);

        assertEq(tokenAddress, address(mock721));
        assertEq(highestBidder, user1);
        assertEq(highestBid, bidAmount);
    }

    function test_startAuction_Success_NextAuctionIdIncrements() public {
        uint256 nextAuctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        skip(60 * 60 * 24 * 7 + 1);
        auctions.claim(nextAuctionId);

        mock721.transferFrom(user1, theBarn, tokenIds[0]);
        mock721.transferFrom(user1, theBarn, tokenIds[1]);
        mock721.transferFrom(user1, theBarn, tokenIds[2]);

        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        assertEq(auctions.nextAuctionId(), nextAuctionId + 2, "nextAuctionId should be incremented");
    }

    function test_startAuction_RevertIf_MaxTokensPerTxReached() public {
        auctions.setMaxTokens(10);
        vm.startPrank(user1);
        uint256[] memory manyTokenIds = new uint256[](11);
        vm.expectRevert(bytes4(keccak256("MaxTokensPerTxReached()")));
        auctions.startAuction{value: 0.05 ether}(address(mock721), manyTokenIds);
    }

    function test_startAuction_RevertIf_StartPriceTooLow() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("StartPriceTooLow()")));
        auctions.startAuction{value: 0.04 ether}(tokenIds, buyItNow);
    }

    function test_startAuction_RevertIf_BurnExceedsBalance() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("BurnExceedsBalance()")));
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
    }

    function test_startAuction_RevertIf_TokenAlreadyInAuction() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        vm.expectRevert(bytes4(keccak256("TokenAlreadyInAuction()")));
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
    }

    function test_startAuction_RevertIf_InvalidLengthOfTokenIds() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("InvalidLengthOfTokenIds()")));
        auctions.startAuction{value: 0.05 ether}(address(mock721), new uint256[](0));
    }

    function test_startAuction_RevertIf_TokenNotOwned() public {
        mock721.mint(user2, 10);

        uint256[] memory notOwnedTokenIds = new uint256[](1);
        notOwnedTokenIds[0] = tokenCount + 1;

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("TokenNotOwned()")));
        auctions.startAuction{value: 0.05 ether}(address(mock721), notOwnedTokenIds);
    }

    //
    // bid()
    //
    function test_bid_Success() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        vm.stopPrank();

        vm.startPrank(user2);
        auctions.bid{value: 0.06 ether}(1);

        (,,,,, address highestBidder, uint256 highestBid) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder should be this contract");
        assertEq(highestBid, 0.06 ether, "Highest bid should be 0.06 ether");
    }

    function test_bid_Success_SelfBidding() public {
        vm.startPrank(user1);

        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        auctions.bid{value: 0.06 ether}(1);

        (,,,,, address highestBidder, uint256 highestBid) = auctions.auctions(1);

        assertEq(highestBidder, user1, "Highest bidder should be this contract");
        assertEq(highestBid, 0.06 ether, "Highest bid should be 0.06 ether");
    }

    function test_bid_Success_LastMinuteBidding() public {
        vm.startPrank(user1);

        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        (,, uint256 endTimeA,,,,) = auctions.auctions(1);

        skip(60 * 60 * 24 * 7 - 59 * 59); // 1 second before auction ends

        auctions.bid{value: 0.06 ether}(1);

        (,, uint256 endTimeB,,,,) = auctions.auctions(1);

        assertLt(endTimeA, endTimeB, "New endtime should be greater than old endtime");
    }

    function test_bid_RevertIf_BelowMinimumIncrement() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: 0.055 ether}(1);
    }

    function test_bid_RevertIf_BidEqualsHighestBid() public {
        vm.startPrank(user1);

        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        uint256 auctionId = auctions.nextAuctionId() - 1;

        auctions.bid{value: 0.06 ether}(auctionId);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: 0.06 ether}(auctionId);
    }

    function test_bid_RevertIf_AfterAuctionEnded() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        skip(60 * 60 * 24 * 7 + 1);
        vm.expectRevert(bytes4(keccak256("AuctionEnded()")));
        auctions.bid{value: 0.06 ether}(1);
    }

    function testFuzz_bid_Success(uint256 bidA, uint256 bidB) public {
        uint256 _bidA = bound(bidA, 0.05 ether, 1000 ether);
        uint256 _bidB = bound(bidB, _bidA + auctions.minBidIncrement(), type(uint256).max);
        vm.assume(_bidB > _bidA && user1.balance >= _bidA && user2.balance >= _bidB);

        vm.prank(user1);
        auctions.startAuction{value: _bidA}(tokenIds, buyItNow);

        vm.prank(user2);
        auctions.bid{value: _bidB}(1);

        (,,,,, address highestBidder, uint256 highestBid) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder should be this contract");
        assertEq(highestBid, _bidB, "Highest bid should be 0.06 ether");
    }

    //
    // claim()
    //
    function test_claim_Success_ERC721() public {
        vm.startPrank(user1);

        uint256 auctionId = auctions.nextAuctionId();
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        assertEq(user1.balance, 0.95 ether, "user1 should have 0.95 after starting the auction");

        vm.startPrank(user2);
        auctions.bid{value: 0.06 ether}(auctionId);

        (,,,,, address highestBidder, uint256 highestBid) = auctions.auctions(auctionId);

        assertEq(user1.balance, 1 ether, "user1 should have 1 ether again");
        assertEq(user2.balance, 0.94 ether, "user2 should have 0.95 ether");
        assertEq(highestBidder, user2, "Highest bidder should be user1");
        assertEq(highestBid, 0.06 ether, "Highest bid should be 0.06 ether");

        skip(60 * 60 * 24 * 7 + 1);
        auctions.claim(auctionId);

        assertEq(mock721.ownerOf(tokenIds[0]), user2, "Should own token 0");
        assertEq(mock721.ownerOf(tokenIds[1]), user2, "Should own token 1");
        assertEq(mock721.ownerOf(tokenIds[2]), user2, "Should own token 2");
    }

    function test_claim_RevertIf_BeforeAuctionEnded() public {
        vm.startPrank(user1);

        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        vm.expectRevert(bytes4(keccak256("AuctionNotEnded()")));
        auctions.claim(1);
    }

    function test_claim_RevertIf_NotHighestBidder() public {
        vm.startPrank(user1);

        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 7 + 1);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("NotHighestBidder()")));
        auctions.claim(1);
    }

    function test_claim_RevertIf_AbandonedAuction() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.prank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 14 + 1);

        auctions.abandon(auctionId);

        vm.prank(user1);
        vm.expectRevert(bytes4(keccak256("AuctionAbandoned()")));
        auctions.claim(auctionId);
    }

    function test_claim_RevertIf_AuctionRefunded() public {
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 7 + 1);

        auctions.refund(auctionId);
        vm.expectRevert(bytes4(keccak256("AuctionRefunded()")));
        auctions.claim(auctionId);
    }

    function test_claim_RevertIf_AuctionClaimed() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 7 + 1);

        auctions.claim(auctionId);
        vm.expectRevert(bytes4(keccak256("AuctionClaimed()")));
        auctions.claim(auctionId);
    }

    //
    // refund
    //
    function test_refund_Success_ERC721() public {
        uint256 auctionId = auctions.nextAuctionId();
        auctions.setMaxTokens(50);
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        assertEq(user1.balance, 1 ether - 0.05 ether, "user1 should have 0.05 less");
        assertTrue(auctions.auctionTokensERC721(tokenIds, buyItNow[0]), "Token 0 should not be in auction");
        assertTrue(auctions.auctionTokensERC721(tokenIds, buyItNow[1]), "Token 1 should not be in auction");
        assertTrue(auctions.auctionTokensERC721(tokenIds, buyItNow[2]), "Token 2 should not be in auction");

        skip(60 * 60 * 24 * 7 + 1);

        auctions.refund(auctionId);
        assertEq(user1.balance, 1 ether, "user1 should have 1 ether again");

        (,,,, Status status,,) = auctions.auctions(auctionId);

        assertTrue(status == Status.Refunded, "Auction should be marked as refunded");
        assertFalse(auctions.auctionTokensERC721(tokenIds, buyItNow[0]), "Token 0 should not be in auction");
        assertFalse(auctions.auctionTokensERC721(tokenIds, buyItNow[1]), "Token 1 should not be in auction");
        assertFalse(auctions.auctionTokensERC721(tokenIds, buyItNow[2]), "Token 2 should not be in auction");
    }

    function test_refund_RevertIf_AuctionActive() public {
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        vm.expectRevert(bytes4(keccak256("AuctionActive()")));
        auctions.refund(1);
    }

    function test_refund_RevertIf_SettlementPeriodEnded() public {
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 14 + 1);

        vm.expectRevert(bytes4(keccak256("SettlementPeriodEnded()")));
        auctions.refund(1);
    }

    function test_refund_RevertIf_NotHighestBidder() public {
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);

        vm.prank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 7 + 1);

        vm.prank(user2);
        vm.expectRevert(bytes4(keccak256("NotHighestBidder()")));
        auctions.refund(1);
    }

    function test_refund_RevertIf_AuctionRefunded() public {
        uint256 auctionId = auctions.nextAuctionId();
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 7 + 1);

        auctions.refund(auctionId);
        vm.expectRevert(bytes4(keccak256("AuctionRefunded()")));
        auctions.refund(auctionId);
    }

    function test_refund_RevertIf_AuctionClaimed() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 7 + 1);

        auctions.claim(auctionId);
        vm.expectRevert(bytes4(keccak256("AuctionClaimed()")));
        auctions.refund(auctionId);
    }

    function test_refund_Exploit() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        // Start another auction to keep liquidity in contract
        vm.startPrank(user2);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        vm.startPrank(user1);
        uint256 auctionId = auctions.nextAuctionId() - 2;
        uint256[] memory auctionIds = new uint256[](1);
        auctionIds[0] = auctionId;

        skip(60 * 60 * 24 * 7 + 1);
        auctions.claim(auctionId);

        vm.startPrank(address(this));
        auctions.withdraw(auctionIds);

        (,,,, Status status,,) = auctions.auctions(auctionId);
        assertTrue(status == Status.Withdrawn, "Auction should be marked as withdrawn");

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("AuctionWithdrawn()")));
        auctions.refund(auctionId);
        // assertEq(user1.balance, 1 ether, "user1 should have 1 ether again");
    }

    //
    // abandon
    //
    function test_abandon_Success_ERC721() public {
        uint256 auctionId = auctions.nextAuctionId();
        uint256 startingBid = 0.05 ether;

        vm.prank(user1);
        auctions.startAuction{value: startingBid}(tokenIds, buyItNow);

        assertEq(user1.balance, 0.95 ether, "user1 should have 0.95 after starting the auction");
        assertTrue(auctions.auctionTokensERC721(tokenIds, buyItNow[0]), "Token 0 should not be in auction");
        assertTrue(auctions.auctionTokensERC721(tokenIds, buyItNow[1]), "Token 1 should not be in auction");
        assertTrue(auctions.auctionTokensERC721(tokenIds, buyItNow[2]), "Token 2 should not be in auction");

        skip(60 * 60 * 24 * 14 + 1);

        vm.startPrank(address(this));
        auctions.abandon(auctionId);

        assertEq(
            user1.balance,
            1 ether - startingBid * auctions.ABANDONMENT_FEE_PERCENT() / 100,
            "user1 should have 1 ether - fee"
        );

        (,,,, Status status,,) = auctions.auctions(auctionId);

        assertTrue(status == Status.Abandoned, "Auction should be marked as abandoned");
        assertFalse(auctions.auctionTokensERC721(tokenIds, buyItNow[0]), "Token 0 should not be in auction");
        assertFalse(auctions.auctionTokensERC721(tokenIds, buyItNow[1]), "Token 1 should not be in auction");
        assertFalse(auctions.auctionTokensERC721(tokenIds, buyItNow[2]), "Token 2 should not be in auction");
    }

    function test_abandon_RevertIf_AuctionActive() public {
        vm.prank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        vm.expectRevert(bytes4(keccak256("SettlementPeriodNotExpired()")));
        auctions.abandon(1);
    }

    function test_abandon_RevertIf_SettlementPeriodActive() public {
        vm.prank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 7 + 1);

        vm.expectRevert(bytes4(keccak256("SettlementPeriodNotExpired()")));
        auctions.abandon(1);
    }

    function test_abandon_RevertIf_AuctionAbandoned() public {
        vm.prank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 14 + 1);

        auctions.abandon(1);
        vm.expectRevert(bytes4(keccak256("AuctionAbandoned()")));
        auctions.abandon(1);
    }

    function test_abandon_RevertIf_AuctionRefunded() public {
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        skip(60 * 60 * 24 * 7 + 1);
        auctions.refund(1);
        vm.stopPrank();

        skip(60 * 60 * 24 * 7);

        vm.expectRevert(bytes4(keccak256("AuctionRefunded()")));
        auctions.abandon(1);
    }

    function test_abandon_RevertIf_AuctionClaimed() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        skip(60 * 60 * 24 * 14 + 1);
        auctions.claim(1);
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("AuctionClaimed()")));
        auctions.abandon(1);
    }

    //
    // withdraw
    //
    function test_withdraw_Success() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        uint256 auctionId = auctions.nextAuctionId() - 1;
        uint256[] memory auctionIds = new uint256[](1);
        auctionIds[0] = auctionId;

        skip(60 * 60 * 24 * 14 + 1); // the settlement period has ended
        auctions.claim(auctionId);

        vm.startPrank(address(this));
        auctions.withdraw(auctionIds);

        (,,,, Status status,,) = auctions.auctions(auctionId);
        assertTrue(status == Status.Withdrawn, "Auction should be marked as withdrawn");
    }

    function test_withdraw_RevertIf_ActiveAuction() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        uint256 auctionId = auctions.nextAuctionId() - 1;
        uint256[] memory auctionIds = new uint256[](1);
        auctionIds[0] = auctionId;

        skip(60 * 60 * 24 * 1); // auction is still active

        vm.startPrank(address(this));
        vm.expectRevert(bytes4(keccak256("AuctionNotClaimed()")));
        auctions.withdraw(auctionIds);
    }

    function test_withdraw_RevertIf_SettlementPeriodActive() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        uint256 auctionId = auctions.nextAuctionId() - 1;
        uint256[] memory auctionIds = new uint256[](1);
        auctionIds[0] = auctionId;

        skip(60 * 60 * 24 * 7 + 1); // beginning of the settlement period

        vm.startPrank(address(this));
        vm.expectRevert(bytes4(keccak256("AuctionNotClaimed()")));
        auctions.withdraw(auctionIds);
    }

    function test_withdraw_RevertIf_AuctionWithdrawn() public {
        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        uint256 auctionId = auctions.nextAuctionId() - 1;
        uint256[] memory auctionIds = new uint256[](1);
        auctionIds[0] = auctionId;

        skip(60 * 60 * 24 * 7 + 1); // the settlement period has started
        auctions.claim(auctionId);

        skip(60 * 60 * 24 * 14 + 1); // the settlement period has ended
        vm.startPrank(address(this));
        auctions.withdraw(auctionIds);
        vm.expectRevert(bytes4(keccak256("AuctionNotClaimed()")));
        auctions.withdraw(auctionIds);
    }

    function test_withdraw_RevertIf_AuctionNotClaimed() public {
        vm.prank(theBarn);
        mock721.setApprovalForAll(address(auctions), false);
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        skip(60 * 60 * 24 * 7 + 1);
        auctions.refund(auctionId);
        vm.stopPrank();

        uint256[] memory auctionIds = new uint256[](1);
        auctionIds[0] = auctionId;
        vm.expectRevert(bytes4(keccak256("AuctionNotClaimed()")));
        auctions.withdraw(auctionIds);
    }

    function test_withdraw_RevertIf_AuctionAbandoned() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.prank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        skip(60 * 60 * 24 * 14 + 1);

        auctions.abandon(auctionId);

        uint256[] memory auctionIds = new uint256[](1);
        auctionIds[0] = auctionId;
        vm.expectRevert(bytes4(keccak256("AuctionNotClaimed()")));
        auctions.withdraw(auctionIds);
    }

    //
    // getters/setters
    //
    function test_getAuctionTokens_Success_ERC721() public {
        auctions.setMaxTokens(50);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);

        (, address tokenAddress,,,,,) = auctions.auctions(1);
        assertEq(tokenAddress, address(mock721));

        (uint256[] memory _tokenIds, uint256[] memory _amounts) = auctions.getAuctionTokens(1);

        assertEq(_tokenIds[0], tokenIds[0]);
        assertEq(_tokenIds[1], tokenIds[1]);
        assertEq(_tokenIds[2], tokenIds[2]);
        assertEq(_amounts[0], amounts[0]);
        assertEq(_amounts[1], amounts[1]);
        assertEq(_amounts[2], amounts[2]);
    }

    function test_setMinStartingBid_Success() public {
        auctions.setMinStartingBid(0.01 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.01 ether}(tokenIds, buyItNow);
    }

    function test_setMintBidIncrement_Success() public {
        auctions.setMinBidIncrement(0.02 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        auctions.bid{value: 0.07 ether}(1);
        auctions.bid{value: 0.09 ether}(1);
    }

    function test_setMinBidIncrement_RevertIf_BidTooLow() public {
        auctions.setMinBidIncrement(0.02 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: 0.05 ether}(tokenIds, buyItNow);
        auctions.bid{value: 0.07 ether}(1);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: 0.08 ether}(1);
    }

    function test_setBarnAddress_Success() public {
        auctions.setBarnAddress(vm.addr(420));
    }

    function test_setBarnAddress_RevertIf_NotOwner() public {
        vm.prank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setBarnAddress(vm.addr(420));
    }

    function test_setMaxTokens_Success() public {
        auctions.setMaxTokens(255);
    }

    function test_setMaxTokens_RevertIf_NotOwner() public {
        vm.prank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setMaxTokens(255);
    }

    function test_setAuctionDuration_Success() public {
        auctions.setAuctionDuration(60 * 60 * 24 * 7);
    }

    function test_setAuctionDuration_RevertIf_NotOwner() public {
        vm.prank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setAuctionDuration(60 * 60 * 24 * 7);
    }

    function test_setSettlementDuration_Success() public {
        auctions.setSettlementDuration(60 * 60 * 24 * 7);
    }

    function test_setSettlementDuration_RevertIf_NotOwner() public {
        vm.prank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setSettlementDuration(60 * 60 * 24 * 7);
    }
    */
}
