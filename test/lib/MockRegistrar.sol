// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../../src/IBaseRegistrar.sol";

contract MockRegistrar is ERC721Enumerable, IBaseRegistrar {

    uint256 expiration = block.timestamp + 365 days;

    constructor() ERC721("MockRegistrar", "MOCKREG") {}

    function nameExpires(uint256) external view returns (uint256) {
        return expiration;
    }

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

    function expireToken(uint256 time) external {
        expiration = block.timestamp - time;
    }
}
