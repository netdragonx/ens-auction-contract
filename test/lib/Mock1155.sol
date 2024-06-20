// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Mock1155 is ERC1155("https://example.com/{id}.json") {
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external virtual {
        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes memory data) public {
        _mintBatch(to, ids, amounts, data);
    }

    function burn(address from, uint256 id, uint256 amount) external {
        _burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) external {
        _burnBatch(from, ids, amounts);
    }

    function uri(uint256) public pure override returns (string memory) {
        return "ipfs://Qmabc123";
    }
}
