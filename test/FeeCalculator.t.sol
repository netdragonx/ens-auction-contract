// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "./lib/Mock20.sol";
import "../src/DynamicFeeCalculator.sol";

contract FeeCalculatorTest is Test {
    DynamicFeeCalculator public feeCalculator;
    Mock20 public mock20;
    
    address public feeRecipient;
    address public user1;
    address public user2;
    address public user3;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public {
        feeRecipient = vm.addr(100);
        feeCalculator = new DynamicFeeCalculator();
        mock20 = new Mock20();

        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);
    }

    function test_calculateFee_WithoutDiscount() public {
        DynamicFeeCalculator.Discount[] memory newDiscounts = new DynamicFeeCalculator.Discount[](1);

        newDiscounts[0] = DynamicFeeCalculator.Discount({
            tokenType: DynamicFeeCalculator.TokenType.ERC20,
            tokenAddress: address(mock20),
            tokenId: 0,
            threshold: 100,
            discount: 10
        });

        feeCalculator.addDiscounts(newDiscounts);

        mock20.mint(user1, 10000);

        uint256 totalAuctionCount = 10;
        uint24 auctionCount = 5;
        uint24 soldCount = 3;
        uint24 unclaimableCount = 1;
        uint24 abandonedCount = 1;
        
        uint256 fee = feeCalculator.calculateFee(
            totalAuctionCount, 
            user1, 
            auctionCount, 
            soldCount, 
            unclaimableCount, 
            abandonedCount, 
            false
        );

        uint256 expectedFee = ((feeCalculator.baseFee() * totalAuctionCount) +
            (feeCalculator.linearFee() * (auctionCount - soldCount - abandonedCount)) +
            (feeCalculator.penaltyFee() * unclaimableCount));

        assertEq(fee, expectedFee);
    }

    function test_calculateFee_WithDiscount() public {
        DynamicFeeCalculator.Discount[] memory newDiscounts = new DynamicFeeCalculator.Discount[](1);

        uint256 discount = 10;

        newDiscounts[0] = DynamicFeeCalculator.Discount({
            tokenType: DynamicFeeCalculator.TokenType.ERC20,
            tokenAddress: address(mock20),
            tokenId: 0,
            threshold: 100,
            discount: discount
        });

        feeCalculator.addDiscounts(newDiscounts);

        mock20.mint(user1, 10000);

        uint256 totalAuctionCount = 10;
        uint24 auctionCount = 5;
        uint24 soldCount = 3;
        uint24 unclaimableCount = 1;
        uint24 abandonedCount = 1;
        
        uint256 fee = feeCalculator.calculateFee(
            totalAuctionCount, 
            user1, 
            auctionCount, 
            soldCount, 
            unclaimableCount, 
            abandonedCount, 
            true
        );

        uint256 expectedFee = ((feeCalculator.baseFee() * totalAuctionCount) +
            (feeCalculator.linearFee() * (auctionCount - soldCount - abandonedCount)) +
            (feeCalculator.penaltyFee() * unclaimableCount)) * discount / 100;

        assertEq(fee, expectedFee);
    }

    function test_setBaseFee_Success() public {
        feeCalculator.setBaseFee(0.01 ether);

        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        feeCalculator.setBaseFee(0.01 ether);
    }

    function test_setLinearFee_Success() public {
        feeCalculator.setLinearFee(0.01 ether);

        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        feeCalculator.setLinearFee(0.01 ether);
    }

    function test_setLinearFee_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        feeCalculator.setLinearFee(0.01 ether);
    }

    function test_setPenaltyFee_Success() public {
        feeCalculator.setPenaltyFee(0.01 ether);
    }

    function test_setPenaltyFee_RevertIf_NotOwner() public {
        vm.startPrank(vm.addr(69));
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        feeCalculator.setPenaltyFee(0.01 ether);
    }

    function test_addDiscounts_Success() public {
        DynamicFeeCalculator.Discount[] memory newDiscounts = new DynamicFeeCalculator.Discount[](1);

        newDiscounts[0] = DynamicFeeCalculator.Discount({
            tokenType: DynamicFeeCalculator.TokenType.ERC20,
            tokenAddress: address(mock20),
            tokenId: 0,
            threshold: 100,
            discount: 10
        });

        feeCalculator.addDiscounts(newDiscounts);

        (
            DynamicFeeCalculator.TokenType tokenType,
            address tokenAddress,
            uint256 tokenId,
            uint256 threshold,
            uint256 discount
        ) = feeCalculator.discounts(0);

        assertEq(uint8(tokenType), uint8(DynamicFeeCalculator.TokenType.ERC20));
        assertEq(tokenAddress, address(mock20));
        assertEq(tokenId, 0);
        assertEq(threshold, 100);
        assertEq(discount, 10);
    }

    function test_clearDiscounts_Success() public {
        DynamicFeeCalculator.Discount[] memory newDiscounts = new DynamicFeeCalculator.Discount[](1);

        newDiscounts[0] = DynamicFeeCalculator.Discount({
            tokenType: DynamicFeeCalculator.TokenType.ERC20,
            tokenAddress: address(mock20),
            tokenId: 0,
            threshold: 100,
            discount: 10
        });

        feeCalculator.addDiscounts(newDiscounts);
        feeCalculator.discounts(0);
        
        feeCalculator.clearDiscounts();

        vm.expectRevert();
        feeCalculator.discounts(0);
    }   
}
