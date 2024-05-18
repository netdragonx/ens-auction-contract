// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../../src/INameWrapper.sol";

contract MockNameWrapper is ERC1155, INameWrapper {
    mapping(uint256 => address) private _owners;
    uint256 private _nextTokenId;

    constructor() ERC1155("") {}

    function ownerOf(uint256 tokenId) public view returns (address) {
        return _owners[tokenId];
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        return _owners[tokenId];
    }

    function getData(
        uint256
    ) public pure override returns (address, uint32, uint64) {
        return (address(0), 0, 0);
    }

    function mint(address recipient, uint256 count) external payable {
        require(count > 0, "Mint more than 0");

        bytes memory data;
        uint256 nextTokenId = _nextTokenId;

        for (uint256 i; i < count;) {
            _mint(recipient, nextTokenId + i, 1, data);

            unchecked {
                ++i;
            }
        }

        _nextTokenId = nextTokenId + count;
    }
}
