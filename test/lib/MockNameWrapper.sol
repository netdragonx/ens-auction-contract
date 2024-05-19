// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../../src/INameWrapper.sol";

contract MockNameWrapper is ERC1155, INameWrapper {
    mapping(uint256 => address) private _owners;
    uint256 private _nextTokenId;
    uint32 private fuses;

    constructor() ERC1155("") {}

    function ownerOf(uint256 tokenId) public view returns (address) {
        return _owners[tokenId];
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        return _owners[tokenId];
    }

    function getData(uint256) public view override returns (address, uint32, uint64) {
        return (address(0), fuses, 0);
    }

    function setFuses(uint32 fuses_) external returns (uint32 newFuses) {
        fuses = fuses_;
        return fuses;
    }

    function mint(address recipient, uint256 count) external payable {
        require(count > 0, "Mint more than 0");

        bytes memory data;
        uint256 nextTokenId = _nextTokenId;

        for (uint256 i; i < count;) {
            _mint(recipient, nextTokenId + i, 1, data);
            _owners[nextTokenId + i] = recipient;

            unchecked {
                ++i;
            }
        }

        _nextTokenId = nextTokenId + count;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override(ERC1155, IERC1155) {
        require(_owners[id] == from, "Not owner");
        super.safeTransferFrom(from, to, id, amount, data);
        _owners[id] = to;
    }
}
