// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/EnsAuctionDrops.sol";

contract EnsAuctionDropsTest is Test {
    EnsAuctionDrops public drops;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        drops = new EnsAuctionDrops();
    }

    function testAirdropSuccess() public {
        uint256 tokenId = 1;
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        drops.airdrop(tokenId, recipients);

        assertEq(drops.balanceOf(user1, tokenId), 1);
        assertEq(drops.balanceOf(user2, tokenId), 1);
        assertEq(drops.balanceOf(user3, tokenId), 1);
    }

    function testAirdropEmptyRecipients() public {
        uint256 tokenId = 1;
        address[] memory recipients = new address[](0);

        drops.airdrop(tokenId, recipients);
    }

    function testAirdropOnlyOwner() public {
        uint256 tokenId = 1;
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(user1);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        drops.airdrop(tokenId, recipients);
    }

    function testMint() public {
        uint256 tokenId = 1;
        uint256 amount = 1;

        drops.mint(user1, tokenId, amount);
        assertEq(drops.balanceOf(user1, tokenId), amount);
    }

    function testMintBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 2;

        drops.mintBatch(user1, ids, amounts);
        assertEq(drops.balanceOf(user1, ids[0]), amounts[0]);
        assertEq(drops.balanceOf(user1, ids[1]), amounts[1]);
    }

    function testBurn() public {
        uint256 tokenId = 1;
        uint256 amount = 1;

        drops.mint(user1, tokenId, amount);
        drops.burn(user1, tokenId, amount);
        assertEq(drops.balanceOf(user1, tokenId), 0);
    }

    function testBurnBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 2;

        drops.mintBatch(user1, ids, amounts);
        drops.burnBatch(user1, ids, amounts);
        assertEq(drops.balanceOf(user1, ids[0]), 0);
        assertEq(drops.balanceOf(user1, ids[1]), 0);
    }

    function testSetURI() public {
        uint256 tokenId = 1;
        string memory tokenURI = "https://example.com/token/1";

        drops.setURI(tokenId, tokenURI);
        assertEq(drops.uri(tokenId), tokenURI);
    }

    function testSoulboundTransfer() public {
        uint256 tokenId = 1;
        uint256 amount = 1;

        drops.mint(user1, tokenId, amount);

        vm.prank(user1);
        vm.expectRevert(EnsAuctionDrops.Soulbound.selector);
        drops.safeTransferFrom(user1, user2, tokenId, amount, "");
    }

    function testOnlyOwnerMint() public {
        uint256 tokenId = 1;
        uint256 amount = 1;

        vm.prank(user1);
        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        drops.mint(user2, tokenId, amount);
    }
}
