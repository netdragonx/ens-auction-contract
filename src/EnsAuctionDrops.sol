// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../lib/ERC1155P/contracts/ERC1155P.sol";
import "solady/src/auth/Ownable.sol";

contract EnsAuctionDrops is ERC1155P, Ownable {
    mapping(uint256 => string) private _tokenURIs;
    string private _contractURI;
    
    event ContractURIUpdated();
    
    error Soulbound();
    error InvalidArrayLengths();

    constructor() ERC1155P("EnsAuctionDrops", "EADROP") {
        _initializeOwner(msg.sender);
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _tokenURIs[id];
    }

    function airdrop(uint256 tokenId, address[] calldata recipients) external onlyOwner {
        for (uint256 i; i < recipients.length; ++i) {
            _mint(recipients[i], tokenId, 1, "");
        }
    }

    function mint(address to, uint256 id, uint256 amount) external virtual onlyOwner {
        _mint(to, id, amount, "");
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) public onlyOwner {
        _mintBatch(to, ids, amounts, "");
    }

    function burn(address from, uint256 id, uint256 amount) external onlyOwner {
        _burn(from, id, amount);
    }

    function burnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) external onlyOwner {
        _burnBatch(from, ids, amounts);
    }

    function setURI(uint256 tokenId, string calldata tokenURI) external virtual onlyOwner {
        _tokenURIs[tokenId] = tokenURI;
        emit URI(uri(tokenId), tokenId);
    }

    function setContractURI(string calldata newURI) external onlyOwner {
        _contractURI = newURI;
        emit ContractURIUpdated();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, id, amount, data);

        if (from != address(0) && to != address(0)) {
            revert Soulbound();
        }
    }

    function _beforeBatchTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeBatchTokenTransfer(operator, from, to, ids, amounts, data);

        if (from != address(0) && to != address(0)) {
            revert Soulbound();
        }
    }
}
