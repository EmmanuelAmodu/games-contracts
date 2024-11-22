// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FreePlayToken is ERC20, ReentrancyGuard {
    uint256 public constant ALLOCATION = 10000 ether;
    mapping(address => uint256) public lastMinted;

    constructor() ERC20("FreePlay", "FPT") {}
 
    function mint() public nonReentrant {
        require(balanceOf(msg.sender) < 1 ether, "Must exhaust allocation before minting again");

        lastMinted[msg.sender] = block.timestamp;
        _mint(msg.sender, ALLOCATION);
    }

    function burn(uint256 amount) public nonReentrant {
        _burn(msg.sender, amount);
    }
}
