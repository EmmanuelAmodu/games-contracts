// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FreePlayToken is ERC20, ReentrancyGuard {
    constructor() ERC20("FreePlay", "FPT") {}
 
    function mint(uint256 amount) public nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) public nonReentrant {
        _burn(msg.sender, amount);
    }
}
