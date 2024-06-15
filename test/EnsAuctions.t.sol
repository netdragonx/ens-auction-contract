// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/EnsAuctions.sol";
import "../src/IEnsAuctions.sol";
import "../src/DynamicFeeCalculator.sol";
import "../src/INameWrapper.sol";
import "./lib/MockRegistrar.sol";
import "./lib/MockNameWrapper.sol";

contract EnsAuctionsTest is Test {
    EnsAuctions public auctions;
    MockRegistrar public mockRegistrar;
    MockNameWrapper public mockNameWrapper;
    DynamicFeeCalculator public feeCalculator;

    address public feeRecipient;
    address public user1;
    address public user2;
    address public user3;

    uint256 public startingPrice = 0.01 ether;
    uint256 public buyNowPrice = 0.05 ether;

    uint256 public tokenCount = 10;
    uint256[] public tokenIds = [0, 1, 2];
    uint256[] public tokenIds345 = [3, 4, 5];
    uint256[] public tokenIdsB = [10, 11, 12];

    uint256[] public tokenIds1 = [0];
    uint256[] public tokenIds2 = [1];
    uint256[] public tokenIds3 = [2];

    bool[] public wrapped = [true, true, true];
    bool[] public wrapped1 = [true];
    bool[] public wrapped2 = [true];
    bool[] public wrapped3 = [true];
    bool[] public unwrapped = [false, false, false];
    bool[] public unwrapped1 = [false];
    bool[] public unwrapped2 = [false];
    bool[] public unwrapped3 = [false];
    bool[] public wrappedMix = [true, false, true];

    receive() external payable {}
    fallback() external payable {}

    function setUp() public {
        feeRecipient = vm.addr(100);
        mockRegistrar = new MockRegistrar();
        mockNameWrapper = new MockNameWrapper();
        feeCalculator = new DynamicFeeCalculator();

        auctions = new EnsAuctions(
            address(mockRegistrar),
            address(mockNameWrapper),
            address(feeCalculator),
            address(feeRecipient)
        );

        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);

        mockRegistrar.mint(user1, tokenCount);
        mockRegistrar.mint(user2, tokenCount);
        mockNameWrapper.mint(user1, tokenCount);
        mockNameWrapper.mint(user2, tokenCount);

        vm.startPrank(user1);
        mockRegistrar.setApprovalForAll(address(auctions), true);
        mockNameWrapper.setApprovalForAll(address(auctions), true);

        vm.startPrank(user2);
        mockRegistrar.setApprovalForAll(address(auctions), true);
        mockNameWrapper.setApprovalForAll(address(auctions), true);

        vm.stopPrank();
    }

    //
    // startAuction()
    //
    function test_startAuction_Success() public {
        vm.startPrank(user1);

        uint256 startBalance = user1.balance;
        uint256 fee = auctions.calculateFee(user1, false);

        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        assertEq(user1.balance, startBalance - fee, "Balance should decrease by fee");
        assertEq(auctions.nextAuctionId(), 2, "nextAuctionId should be incremented");
        assertEq(feeRecipient.balance, fee, "feeRecipient should have received the fee");

        (
            uint64 _endTime, 
            uint64 _buyNowEndTime, 
            , 
            address _seller, 
            address _highestBidder, 
            uint256 _highestBid, 
            uint256 _startingPrice, 
            uint256 _buyNowPrice,
            uint256 _tokenCount
        ) = auctions.auctions(1);

        assertEq(_buyNowEndTime, auctions.getNextEventTime(), "Buy now end time should be set correctly");
        assertEq(_endTime, auctions.getNextEventTime() + auctions.auctionDuration(), "Auction end time should be set correctly");
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
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        assertEq(auctions.nextAuctionId(), 2, "nextAuctionId should be incremented");

        (
            uint64 _endTime,
            uint64 _buyNowEndTime,
            ,
            address _seller,
            address _highestBidder,
            uint256 _highestBid,
            ,
            ,
            uint256 _tokenCount
        ) = auctions.auctions(1);

        assertEq(_highestBidder, address(0));
        assertEq(_highestBid, 0);
        assertEq(_seller, user1);
        assertEq(_tokenCount, 3);
        assertEq(_buyNowEndTime, auctions.getNextEventTime());
        assertEq(_endTime, auctions.getNextEventTime() + auctions.auctionDuration());
    }

    function test_startAuction_Success_NextAuctionIdIncrements() public {
        uint256 nextAuctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);

        skip(auctions.auctionDuration() + 1);

        auctions.claim(nextAuctionId);

        mockRegistrar.transferFrom(user2, user1, tokenIds[0]);
        mockRegistrar.transferFrom(user2, user1, tokenIds[1]);
        mockRegistrar.transferFrom(user2, user1, tokenIds[2]);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        assertEq(auctions.nextAuctionId(), nextAuctionId + 2, "nextAuctionId should be incremented");
    }

    function test_startAuction_WithWrappedNames() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        
        (
            , 
            ,
            , 
            address _seller, 
            ,
            ,
            ,
            ,
            uint256 _tokenCount
        ) = auctions.auctions(1);

        assertEq(_seller, user1, "Seller should be user1");
        assertEq(_tokenCount, tokenIds.length, "Token count should match the number of tokens auctioned");
    }

    function test_startAuction_RevertIf_InvalidFee() public {
        vm.startPrank(user1);

        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds1, unwrapped1, false);

        fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("InvalidFee()")));
        auctions.startAuction{value: fee - 0.01 ether}(startingPrice, buyNowPrice, tokenIds2, unwrapped2, false);
    }

    function test_startAuction_RevertIf_MaxTokensPerTxReached() public {
        auctions.setMaxTokens(10);
        vm.startPrank(user1);
        uint256[] memory manyTokenIds = new uint256[](11);
        bool[] memory manyWrapped = new bool[](11);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("MaxTokensPerTxReached()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, manyTokenIds, manyWrapped, false);
    }

    function test_startAuction_RevertIf_StartPriceTooLow() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("StartPriceTooLow()")));
        auctions.startAuction{value: fee}(startingPrice - 0.001 ether, buyNowPrice, tokenIds, unwrapped, false);
    }

    function test_startAuction_RevertIf_BuyNowTooLow() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("BuyNowTooLow()")));
        auctions.startAuction{value: fee}(  startingPrice, buyNowPrice - 0.001 ether, tokenIds, unwrapped, false);
    }

    function test_startAuction_RevertIf_BuyNowLessThanStartingPrice() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("BuyNowTooLow()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice - 0.001 ether, tokenIds, unwrapped, false);
    }

    function test_startAuction_RevertIf_TokenAlreadyInAuction() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("TokenAlreadyInAuction()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
    }

    function test_startAuction_RevertIf_InvalidLengthOfTokenIds() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("InvalidLengthOfTokenIds()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, new uint256[](0), new bool[](0), false);
    }

    function test_startAuction_RevertIf_TokenNotOwned() public {
        mockRegistrar.mint(user2, 10);

        uint256[] memory notOwnedTokenIds = new uint256[](1);
        notOwnedTokenIds[0] = tokenCount + 1;

        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("TokenNotOwned()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, notOwnedTokenIds, unwrapped1, false);
    }

    function test_startAuction_Fees() public {
        feeCalculator.setBaseFee(0.02 ether);
        feeCalculator.setLinearFee(0.01 ether);

        vm.startPrank(user1);

        uint256 startBalance = user1.balance;
        
        uint256 fee1 = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee1}(startingPrice, buyNowPrice, tokenIds1, unwrapped1, false);

        uint256 fee2 = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee2}(startingPrice, buyNowPrice, tokenIds2, unwrapped2, false);

        uint256 fee3 = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee3}(startingPrice, buyNowPrice, tokenIds3, unwrapped3, false);

        assertEq(user1.balance, startBalance - fee1 - fee2 - fee3, "Balance should decrease by fee");
        assertEq(feeRecipient.balance, fee1 + fee2 + fee3, "feeRecipient should have received the fee");
        assertEq(fee1, 0 ether, "base fee for first auction is free");
        assertEq(fee2, 0.03 ether, "fee w/ linear fee is 0.02 ether");
        assertEq(fee3, 0.06 ether, "fee w/ linear fee * 2 is 0.02 ether");
    }

    function test_startAuction_RevertIf_WrappedNameNotOwned() public {
        uint256[] memory notOwnedTokenIds = new uint256[](1);
        notOwnedTokenIds[0] = tokenCount + 1;

        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("TokenNotOwned()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, notOwnedTokenIds, wrapped1, false);
    }

    function test_startAuction_RevertIf_WrappedNameAlreadyInAuction() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, wrapped, false);

        fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("TokenAlreadyInAuction()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
    }

    function test_startAuction_RevertIf_WrappedNameNotTransferrable() public {
        mockNameWrapper.setFuses(CANNOT_TRANSFER);

        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("TokenNotTransferrable()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
    }

    function test_startAuction_RevertIf_TokenExpired() public {
        skip(1 days);
        mockRegistrar.expireToken(1 days);

        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        vm.expectRevert(bytes4(keccak256("TokenExpired()")));
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
    }

    //
    // bid()
    //
    function test_bid_Success() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);

        (,,,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, startingPrice, "Highest bid incorrect");
    }

    function test_bid_Success_SelfBidding() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);
        auctions.bid{value: startingPrice + auctions.minBidIncrement()}(1, startingPrice + auctions.minBidIncrement());

        (,,,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, startingPrice + auctions.minBidIncrement(), "Highest bid incorrect");
    }

    function test_bid_Success_LastMinuteBidding() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        (uint256 endTimeA,,,,,,,,) = auctions.auctions(1);

        vm.warp(auctions.getNextEventTime() + auctions.auctionDuration() - 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.06 ether}(1, 0.06 ether);

        (uint256 endTimeB,,,,,,,,) = auctions.auctions(1);

        assertLt(endTimeA, endTimeB, "New endtime should be greater than old endtime");
    }

    function test_bid_Success_UsingAvailableBalance() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(0.01 ether, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.01 ether}(1, 0.01 ether);
        
        (,,,, address highestBidder1, uint256 highestBid1,,,) = auctions.auctions(1);
        assertEq(highestBid1, 0.01 ether);
        assertEq(highestBidder1, user2);

        vm.startPrank(user3);
        auctions.bid{value: 0.02 ether}(1, 0.02 ether);
        
        (,,,, address highestBidder2, uint256 highestBid2,,,) = auctions.auctions(1);
        assertEq(highestBid2, 0.02 ether);
        assertEq(highestBidder2, user3);

        assertEq(auctions.balances(user2), 0.01 ether, "balance should be 0.01 ether");

        vm.startPrank(user2);
        auctions.bid{value: 0.02 ether}(1, 0.03 ether);
        
        (,,,, address highestBidder3, uint256 highestBid3,,,) = auctions.auctions(1);
        assertEq(highestBid3, 0.03 ether);
        assertEq(highestBidder3, user2);
        
        assertEq(user2.balance, 1 ether - 0.03 ether);
        assertEq(user3.balance, 1 ether - 0.02 ether);

        assertEq(auctions.balances(user2), 0 ether, "balance should be 0 ether");
        assertEq(auctions.balances(user3), 0.02 ether, "balance should be 0.02 ether");
    }

    function test_bid_Success_UsingPartOfABalance() public {
        vm.deal(user3, 10 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(0.01 ether, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.5 ether}(1, 0.5 ether);
        
        (,,,, address highestBidder1, uint256 highestBid1,,,) = auctions.auctions(1);
        assertEq(highestBid1, 0.5 ether);
        assertEq(highestBidder1, user2);

        vm.startPrank(user3);
        auctions.bid{value: 0.51 ether}(1, 0.51 ether);
        
        (,,,, address highestBidder2, uint256 highestBid2,,,) = auctions.auctions(1);
        assertEq(highestBid2, 0.51 ether);
        assertEq(highestBidder2, user3);

        assertEq(auctions.balances(user2), 0.5 ether, "incorrect balance");

        // new auction
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(0.01 ether, buyNowPrice, tokenIds345, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid(2, 0.24 ether);
        
        (,,,, address highestBidder3, uint256 highestBid3,,,) = auctions.auctions(2);
        assertEq(highestBid3, 0.24 ether);
        assertEq(highestBidder3, user2);
        assertEq(user2.balance, 0.5 ether);

        assertEq(auctions.balances(user2), 0.26 ether, "incorrect balance");

        vm.startPrank(user3);
        auctions.bid{value: 0.25 ether}(2, 0.25 ether);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("InvalidValue()")));
        auctions.bid(2, 0.51 ether);
    }
    
    function test_bid_WithWrappedNames() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);

        (,,,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, startingPrice, "Highest bid incorrect");
    }

    function test_bid_RevertIf_InvalidStatus() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.startPrank(user2);
        auctions.buyNow{value: buyNowPrice}(1);

        skip(auctions.auctionDuration() + 1);

        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.bid{value: startingPrice + 0.1 ether}(1, startingPrice + 0.1 ether);
    }

    function test_bid_RevertIf_AuctionBuyNowPeriod() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("AuctionBuyNowPeriod()")));
        auctions.bid{value: startingPrice}(1, startingPrice);
    }

    function test_bid_RevertIf_AuctionEnded() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("AuctionEnded()")));
        auctions.bid{value: startingPrice}(1, startingPrice);
    }

    function test_bid_RevertIf_SellerCannotBid() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.expectRevert(bytes4(keccak256("SellerCannotBid()")));
        auctions.bid{value: startingPrice}(1, startingPrice);
    }

    function test_bid_RevertIf_BelowMinimumIncrement() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);
        
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
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        vm.startPrank(user3);
        vm.expectRevert(bytes4(keccak256("BidTooLow()")));
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
    }

    function testFuzz_bid_Success(uint256 bidA, uint256 bidB) public {
        uint256 minIncrement = auctions.minBidIncrement();

        bidA = bound(bidA, 0.05 ether, 100 ether);
        bidB = bound(bidB, bidA + minIncrement, 100000 ether);

        emit log_named_uint("bidA", bidA);
        emit log_named_uint("bidB", bidB);

        vm.deal(user2, bidA);
        vm.deal(user3, bidB);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: bidA}(1, bidA);
        vm.startPrank(user3);
        auctions.bid{value: bidB}(1, bidB);

        (,,,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(1);

        assertEq(highestBidder, user3, "Highest bidder should be user3");
        assertEq(highestBid, bidB, "Highest bid should be bidB");
    }

    //
    // buyNow()
    //
    function test_buyNow_Success() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        assertEq(feeRecipient.balance, fee, "feeRecipient should receive fee");

        vm.startPrank(user2);
        auctions.buyNow{value: buyNowPrice}(1);

        (,,,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(1);

        assertEq(highestBidder, user2, "Highest bidder incorrect");
        assertEq(highestBid, buyNowPrice, "Highest bid incorrect");

        assertEq(auctions.balances(user2), 0, "balance should be 0 ether");

        (
            uint24 totalAuctions,
            uint24 totalSold,
            uint24 totalUnclaimable,
            uint24 totalBidderAbandoned
        ) = auctions.sellers(user1);
        
        assertEq(totalAuctions, 1, "should have 1 total auctions");
        assertEq(totalSold, 1, "should have 1 total sold");
        assertEq(totalUnclaimable, 0, "should have 0 total unclaimable");
        assertEq(totalBidderAbandoned, 0, "should have 0 total bidder abandoned");
        assertEq(auctions.balances(user1), 0.05 ether, "seller balance should be 0.05 ether");
    }

    function test_buyNow_RevertIf_InvalidStatus() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.startPrank(user2);
        auctions.buyNow{value: buyNowPrice}(1);

        vm.startPrank(user3);
        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.buyNow{value: buyNowPrice}(1);
    }

    function test_buyNow_RevertIf_BuyNowUnavailable() public {
        vm.startPrank(user1);
        uint256 fee = auctions.calculateFee(user1, false);
        auctions.startAuction{value: fee}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("BuyNowUnavailable()")));
        auctions.buyNow{value: buyNowPrice}(1);
    }

    //
    // claim()
    //
    function test_claim_Success() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        (,,,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");

        skip(auctions.auctionDuration() + 1);
        auctions.claim(auctionId);

        assertEq(user2.balance, 1 ether - startingPrice, "user2 should have 0.94 ether");
        assertEq(mockRegistrar.ownerOf(tokenIds[0]), user2, "Should own token 0");
        assertEq(mockRegistrar.ownerOf(tokenIds[1]), user2, "Should own token 1");
        assertEq(mockRegistrar.ownerOf(tokenIds[2]), user2, "Should own token 2");

        (
            uint24 totalAuctions,
            uint24 totalSold,
            uint24 totalUnclaimable,
            uint24 totalBidderAbandoned
        ) = auctions.sellers(user1);
        
        assertEq(totalAuctions, 1, "should have 1 total auctions");
        assertEq(totalSold, 1, "should have 1 total sold");
        assertEq(totalUnclaimable, 0, "should have 0 total unclaimable");
        assertEq(totalBidderAbandoned, 0, "should have 0 total bidder abandoned");
        assertEq(auctions.balances(user1), startingPrice, "seller balance should be 0.05 ether");
    }

    function test_claim_Success_WithWrappedNames() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + 1);
        auctions.claim(auctionId);

        assertEq(user2.balance, 1 ether - startingPrice, "user2 should have 0.94 ether");
        assertEq(mockNameWrapper.ownerOf(tokenIds[0]), user2, "Should own wrapped token 0");
        assertEq(mockNameWrapper.ownerOf(tokenIds[1]), user2, "Should own wrapped token 1");
        assertEq(mockNameWrapper.ownerOf(tokenIds[2]), user2, "Should own wrapped token 2");
    }

    function test_claim_RevertIf_BeforeAuctionEnded() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(1, startingPrice);

        vm.expectRevert(bytes4(keccak256("AuctionNotEnded()")));
        auctions.claim(1);
    }

    function test_claim_RevertIf_AbandonedAuction() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

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
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + 1);
        
        auctions.claim(auctionId);
        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.claim(auctionId);
    }

    function test_claim_RevertIf_NoBids() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + auctions.auctionDuration() + 1);

        vm.expectRevert();
        auctions.claim(auctionId);
    }

    //
    // markAbandoned()
    //
    function test_markAbandoned_Success() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.startPrank(user1);
        auctions.markAbandoned(auctionId);

        (,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Abandoned, "Status should be Abandoned");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be startingPrice");
    }

    function test_markAbandoned_RevertIf_InvalidStatus() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

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
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + auctions.auctionDuration() + auctions.settlementDuration() + 1);
        
        vm.expectRevert(bytes4(keccak256("AuctionHadNoBids()")));
        auctions.markAbandoned(auctionId);
    }

    function test_markAbandoned_RevertIf_NotAuthorized() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.startPrank(user2);
        vm.expectRevert(bytes4(keccak256("NotAuthorized()")));
        auctions.markAbandoned(auctionId);
    }

    function test_markAbandoned_RevertIf_SettlementPeriodNotExpired() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("SettlementPeriodNotExpired()")));
        auctions.markAbandoned(auctionId);
    }

    //
    // markUnclaimable()
    //
    function test_markUnclaimable_Success_SellerMovesTokens() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 moves a token mid auction
        vm.startPrank(user1);
        mockRegistrar.transferFrom(user1, user3, tokenIds[0]);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_Success_SellerMovesTokens_Wrapped() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 moves a token mid auction
        vm.startPrank(user1);
        mockNameWrapper.safeTransferFrom(user1, user3, tokenIds[0], 1, "");

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_Success_SellerRemovesApprovalForAll() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 moves a token mid auction
        vm.startPrank(user1);
        mockRegistrar.setApprovalForAll(address(auctions), false);
        
        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_Success_SellerRemovesApprovalForAll_Wrapped() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 moves a token mid auction
        vm.startPrank(user1);
        mockNameWrapper.setApprovalForAll(address(auctions), false);
        
        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_Success_SellerRemovesApprovalForOne() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        mockRegistrar.setApprovalForAll(address(auctions), false);
        mockRegistrar.approve(address(auctions), tokenIds[0]);
        mockRegistrar.approve(address(auctions), tokenIds[1]);
        mockRegistrar.approve(address(auctions), tokenIds[2]);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // user1 disapproves a token mid auction
        vm.startPrank(user1);
        mockRegistrar.approve(address(0), tokenIds[0]);
        
        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_Success_SellerBurnsFusesOnWrappedName() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);

        // burn transfer fuse
        vm.startPrank(user1);
        mockNameWrapper.setFuses(CANNOT_TRANSFER);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user2);
        auctions.markUnclaimable(auctionId);

        (,, EnsAuctions.Status status,, address highestBidder, uint256 highestBid,,,) = auctions.auctions(auctionId);

        assertTrue(status == EnsAuctions.Status.Unclaimable, "Status should be Unclaimable");
        assertEq(highestBidder, user2, "Highest bidder should be user2");
        assertEq(highestBid, startingPrice, "Highest bid should be 0.06 ether");
    }

    function test_markUnclaimable_RevertIf_AuctionIsClaimable() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + 1);

        vm.expectRevert(bytes4(keccak256("AuctionIsClaimable()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_AuctionIsClaimable_Wrapped() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + 1);

        vm.expectRevert(bytes4(keccak256("AuctionIsClaimable()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_InvalidStatus() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.startPrank(user2);
        auctions.buyNow{value: buyNowPrice}(auctionId);
        skip(auctions.auctionDuration() + 1);

        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_InvalidStatus_Wrapped() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);

        vm.startPrank(user2);
        auctions.buyNow{value: buyNowPrice}(auctionId);
        skip(auctions.auctionDuration() + 1);

        vm.expectRevert(bytes4(keccak256("InvalidStatus()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_SettlementPeriodEnded() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.expectRevert(bytes4(keccak256("SettlementPeriodEnded()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_SettlementPeriodEnded_Wrapped() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + auctions.settlementDuration() + 1);

        vm.expectRevert(bytes4(keccak256("SettlementPeriodEnded()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_NotHighestBidder() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user3);
        vm.expectRevert(bytes4(keccak256("NotHighestBidder()")));
        auctions.markUnclaimable(auctionId);
    }

    function test_markUnclaimable_RevertIf_NotHighestBidder_Wrapped() public {
        uint256 auctionId = auctions.nextAuctionId();

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, wrapped, false);
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: startingPrice}(auctionId, startingPrice);
        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user3);
        vm.expectRevert(bytes4(keccak256("NotHighestBidder()")));
        auctions.markUnclaimable(auctionId);
    }

    //
    // withdrawBalance
    //
    function test_withdrawBalance_Success() public {
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(0.01 ether, buyNowPrice, tokenIds, unwrapped, false);
        
        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.01 ether}(1, 0.01 ether);
        
        (,,,, address highestBidder1, uint256 highestBid1,,,) = auctions.auctions(1);
        assertEq(highestBid1, 0.01 ether);
        assertEq(highestBidder1, user2);

        vm.startPrank(user3);
        auctions.bid{value: 0.02 ether}(1, 0.02 ether);

        vm.startPrank(user2);
        auctions.withdrawBalance();
        assertEq(user2.balance, 1 ether);
    }

    function test_withdrawBalance_Success_Combined_BidderSeller() public {
        feeCalculator.setBaseFee(0.05 ether);
        feeCalculator.setLinearFee(0.01 ether);
        auctions.setAuctionDuration(3 days);
        
        uint256 user1Fee = auctions.calculateFee(user1, false);
        uint256 user1Bid = 0.05 ether;

        vm.startPrank(user1);
        auctions.startAuction{value: user1Fee}(0.01 ether, buyNowPrice, tokenIds, unwrapped, false);
        
        vm.warp(auctions.getNextEventTime() + 1);

        uint256 user2Fee = auctions.calculateFee(user2, false);
        uint256 user2Bid = 0.01 ether;

        vm.startPrank(user2);
        auctions.bid{value: user2Bid}(1, user2Bid);
        auctions.startAuction{value: user2Fee}(0.02 ether, buyNowPrice, tokenIdsB, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user1);
        auctions.bid{value: user1Bid}(2, user1Bid);
        
        uint256 user3BidA = 0.02 ether;
        uint256 user3BidB = 0.06 ether;

        vm.startPrank(user3);
        auctions.bid{value: user3BidA}(1, user3BidA);
        auctions.bid{value: user3BidB}(2, user3BidB);

        (,,,, address highestBidder1, uint256 highestBid1,,,) = auctions.auctions(1);
        assertEq(highestBid1, user3BidA);
        assertEq(highestBidder1, user3);

        (,,,, address highestBidder2, uint256 highestBid2,,,) = auctions.auctions(2);
        assertEq(highestBid2, user3BidB);
        assertEq(highestBidder2, user3);

        skip(auctions.auctionDuration() + 1);

        vm.startPrank(user1);
        assertEq(user1.balance, 1 ether - user1Fee - user1Bid);
        auctions.withdrawBalance();
        assertEq(user1.balance, 1 ether - user1Fee);
        
        vm.startPrank(user2);
        assertEq(user2.balance, 1 ether - user2Fee - user2Bid);
        auctions.withdrawBalance();
        assertEq(user2.balance, 1 ether - user2Fee);

        vm.startPrank(user3);
        auctions.claim(1);
        auctions.claim(2);

        vm.startPrank(user1);
        assertEq(user1.balance, 1 ether - user1Fee);
        auctions.withdrawBalance();
        assertEq(user1.balance, 1 ether - user1Fee + user3BidA);
        
        vm.startPrank(user2);
        assertEq(user2.balance, 1 ether - user2Fee);
        auctions.withdrawBalance();
        assertEq(user2.balance, 1 ether - user2Fee + user3BidB);
    }

    //
    // getters/setters
    //
    function test_getAuctionTokens_Success() public {
        auctions.setMaxTokens(50);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        (uint256[] memory _tokenIds) = auctions.getAuctionTokens(1);

        assertEq(_tokenIds[0], tokenIds[0]);
        assertEq(_tokenIds[1], tokenIds[1]);
        assertEq(_tokenIds[2], tokenIds[2]);
    }

    function test_setMinStartingBid_Success() public {
        auctions.setMinStartingBid(0.01 ether);
        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);
    }

    function test_setMinBuyNowPrice_Success() public {
        auctions.setMinBuyNowPrice(5 ether);
    }

    function test_setMinBuyNowPrice_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setMinBuyNowPrice(5 ether);
    }

    function test_setMinBidIncrement_Success() public {
        auctions.setMinBidIncrement(0.02 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

        vm.startPrank(user2);
        auctions.bid{value: 0.07 ether}(1, 0.07 ether);
        auctions.bid{value: 0.09 ether}(1, 0.09 ether);
    }

    function test_setMinBidIncrement_RevertIf_BidTooLow() public {
        auctions.setMinBidIncrement(0.02 ether);

        vm.startPrank(user1);
        auctions.startAuction{value: auctions.calculateFee(user1, false)}(startingPrice, buyNowPrice, tokenIds, unwrapped, false);

        vm.warp(auctions.getNextEventTime() + 1);

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

    function test_setFeeRecipient_Success() public {
        auctions.setFeeRecipient(vm.addr(69));
    }

    function test_setFeeRecipient_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setFeeRecipient(vm.addr(69));
    }

    function test_setAntiSnipeDuration_Success() public {
        auctions.setAntiSnipeDuration(60);
    }

    function test_setAntiSnipeDuration_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setAntiSnipeDuration(60);
    }

    function test_setFeeCalculator_Success() public {
        auctions.setFeeCalculator(address(feeCalculator));
    }

    function test_setFeeCalculator_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        auctions.setFeeCalculator(address(feeCalculator));
    }
}
