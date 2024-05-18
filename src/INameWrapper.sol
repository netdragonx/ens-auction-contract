//SPDX-License-Identifier: MIT
pragma solidity ~0.8.25;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

uint32 constant CANNOT_TRANSFER = 4;
uint32 constant CANNOT_APPROVE = 64;

interface INameWrapper is IERC1155 {
    function ownerOf(uint256 id) external view returns (address owner);
    function getApproved(uint256 tokenId) external view returns (address);
    function getData(
        uint256 id
    ) external view returns (address, uint32, uint64);
}