// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Lottery.sol";

contract FreePlayLottery is ERC20, ReentrancyGuard, Ownable {
    Lottery public lottery;

    constructor(address initialOwner) ERC20("FreePlay", "FPL") Ownable(initialOwner) {}
 
    function play(uint8[][] calldata numbers, uint256[] calldata amounts, address referrer) public nonReentrant() {
        require(address(lottery) != address(0), "Lottery address not set");
        require(numbers.length == amounts.length, "Invalid input");
        require(numbers.length > 0, "Invalid input");
        require(numbers.length < 100, "Invalid input");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Invalid amount ticket price");
            require(amounts[i] <= 1000, "Invalid amount ticket price");
            totalAmount += amounts[i];
        }

        _mint(msg.sender, totalAmount);
        lottery.purchaseMultipleTickets(numbers, amounts, referrer);
    }

    function getLotteryAddress() public view returns (address) {
        return address(lottery);
    }

    function withdraw(uint256 amount) public onlyOwner {
        _transfer(address(this), owner(), amount);
    }

    function setLotteryAddress(address _lottery) public {
        require(_lottery != address(0), "Invalid address");
        require(address(lottery) == address(0), "Lottery address already set");
        lottery = Lottery(_lottery);
    }
}
