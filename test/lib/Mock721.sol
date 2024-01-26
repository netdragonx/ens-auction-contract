// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract Mock721 is ERC721Enumerable {
    constructor() ERC721("Mock721", "MOCK721") {}

    function mint(address recipient, uint256 count) external payable {
        require(count > 0, "Mint more than 0");

        bytes memory data;
        uint256 supply = totalSupply();

        for (uint256 i; i < count;) {
            _safeMint(recipient, supply + i, data);

            unchecked {
                ++i;
            }
        }
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "ipfs://QmZTAcMHVjY5oKdxhX5G5AnRPwgJ7v9MMBVhr7AnjAbE9G";
    }
}
