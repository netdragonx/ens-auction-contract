// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Mock20 is ERC20 {
    constructor() ERC20("Mock20", "MOCK20") {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}