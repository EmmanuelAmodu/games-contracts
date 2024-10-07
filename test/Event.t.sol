// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/Event.sol";
import "../contracts/CollateralManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EventTest is Test {
    Event eventContract;
    CollateralManager collateralManager;
    ERC20 token;
    address creator = address(0x1);
    address user = address(0x2);

    function setUp() public {
        token = new ERC20("Test Token", "TTK");
        collateralManager = new CollateralManager(address(this), address(token));

        // Mint tokens to creator and user
        token._mint(creator, 1000 ether);
        token._mint(user, 1000 ether);

        // Set up the event
        vm.prank(creator);
        token.approve(address(collateralManager), 100 ether);
        collateralManager.lockCollateral(creator, 100 ether);

        string;
        outcomes[0] = "Team A Wins";
        outcomes[1] = "Team B Wins";

        eventContract = new Event(
            "Match between Team A and Team B",
            outcomes,
            block.timestamp,
            block.timestamp + 1 days,
            creator,
            100 ether,
            address(collateralManager)
        );
    }

    function testPlaceBet() public {
        vm.prank(user);
        token.approve(address(eventContract), 10 ether);
        vm.prank(user);
        eventContract.placeBet(0, 10 ether);

        assertEq(eventContract.userBets(user, 0), 10 ether);
    }

    // Additional tests for outcome submission, payout distribution, and disputes
}
