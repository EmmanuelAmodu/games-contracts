// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/Lottery.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LotteryTest is Test {
    Lottery public lottery;
    MockERC20 public token;

    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public referrer = address(0x4);

    uint256 public ticketAmount = 100 ether; // Assuming token has 18 decimals

    function setUp() public {
        // Deploy a mock ERC20 token
        token = new MockERC20("Mock Token", "MTK");

        // Deploy the lottery contract
        lottery = new Lottery(owner, address(token));

        // Distribute tokens to players
        token.mint(player1, 1000 ether);
        token.mint(player2, 1000 ether);
        token.mint(address(lottery), 1_000_000 ether);

        // Players approve the lottery contract to spend their tokens
        vm.prank(player1);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(player2);
        token.approve(address(lottery), type(uint256).max);
    }

    function testPurchaseTicket() public {
        vm.startPrank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);
        vm.stopPrank();

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Check if the ticket was purchased
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        assertEq(tickets.length, 1);

        // Check if total pool is updated
        assertEq(lottery.totalPool(), ticketAmount);
    }

    function testPurchaseTicketWithFewerNumbers() public {
        vm.startPrank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [10, 20, 30, 40, 50];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);
        vm.stopPrank();

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](3);
        numbers[0] = 10;
        numbers[1] = 20;
        numbers[2] = 30;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Check if the ticket was purchased
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        assertEq(tickets.length, 1);

        // Check if total pool is updated
        assertEq(lottery.totalPool(), ticketAmount);
    }

    function testRevealWinningNumbersAndCalculatePrizes() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket with 5 numbers (all matching)
        vm.startPrank(player1);
        uint8[] memory numbers1 = new uint8[](5); 
        numbers1[0] = 1;
        numbers1[1] = 2;
        numbers1[2] = 3;
        numbers1[3] = 4;
        numbers1[4] = 5;
        lottery.purchaseTicket(numbers1, ticketAmount, referrer);
        vm.stopPrank();

        // Player2 purchases a ticket with 3 numbers (3 matching)
        vm.startPrank(player2);
        uint8[] memory numbers2 = new uint8[](3);
        numbers2[0] = 1;
        numbers2[1] = 2;
        numbers2[2] = 3;
        lottery.purchaseTicket(numbers2, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Check if the winning numbers are set
        uint8[5] memory revealedNumbers = lottery.getWinningNumbers();
        for (uint8 i = 0; i < 5; i++) {
            assertEq(revealedNumbers[i], winningNumbers[i]);
        }

        // Check if prizes are calculated correctly for Player1
        uint256[] memory tickets1 = lottery.getPlayerTickets(player1);
        Lottery.Ticket memory ticket1 = lottery.getTicket(tickets1[0]);
        uint256 expectedMultiplier1 = lottery.multipliers(5); // All 5 numbers match
        assertEq(ticket1.multiplier, expectedMultiplier1);
        assertEq(ticket1.prize, ticketAmount * expectedMultiplier1);

        // Check if prizes are calculated correctly for Player2
        uint256[] memory tickets2 = lottery.getPlayerTickets(player2);
        Lottery.Ticket memory ticket2 = lottery.getTicket(tickets2[0]);
        uint256 expectedMatchingNumbers2 = 3; // 3 numbers match
        uint256 expectedMultiplier2 = lottery.multipliers(expectedMatchingNumbers2);
        assertEq(ticket2.multiplier, expectedMultiplier2);
        assertEq(ticket2.prize, ticketAmount * expectedMultiplier2);
    }

    function testClaimPrizes() public {
        // Setup and reveal winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player1 claims prize
        uint256 balanceBefore = token.balanceOf(player1);

        vm.prank(player1);
        lottery.claimPrizes();

        uint256 balanceAfter = token.balanceOf(player1);

        // Check if the prize was transferred
        uint256 expectedPrize = ticketAmount * lottery.multipliers(5);
        assertEq(balanceAfter - balanceBefore, expectedPrize);

        // Ensure the ticket is marked as claimed
        uint256[] memory tickets1 = lottery.getPlayerTickets(player1);
        Lottery.Ticket memory ticket1 = lottery.getTicket(tickets1[0]);
        assertTrue(ticket1.claimed);
    }

    function testReferralRewards() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [10, 20, 30, 40, 50];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket with player2 as referrer
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](3);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        lottery.purchaseTicket(numbers, ticketAmount, player2);
        vm.stopPrank();

        // Check referral rewards
        uint256 expectedReward = ticketAmount / 10; // 10% of ticket amount
        uint256 reward = lottery.referralRewards(player2);
        assertEq(reward, expectedReward);

        // Player2 claims referral rewards
        uint256 balanceBefore = token.balanceOf(player2);

        vm.prank(player2);
        lottery.claimReferralRewards();

        uint256 balanceAfter = token.balanceOf(player2);

        // Check if the referral reward was transferred
        assertEq(balanceAfter - balanceBefore, expectedReward);
    }

    function testOwnerWithdraw() public {
        // Setup and reveal winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player1 claims prize
        vm.prank(player1);
        lottery.claimPrizes();

        // Owner withdraws remaining funds
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 contractBalanceBeforeWithdraw = token.balanceOf(address(lottery));

        vm.prank(owner);
        lottery.ownerWithdraw();

        uint256 balanceAfter = token.balanceOf(owner);

        // Expected withdrawal is the contract's balance before withdrawal
        uint256 expectedWithdrawal = contractBalanceBeforeWithdraw;

        // Check if the owner received the remaining funds
        assertEq(balanceAfter - balanceBefore, expectedWithdrawal);
    }

    function testPurchaseMultipleTickets() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [5, 10, 15, 20, 25];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);

        // Prepare numbers for multiple tickets
        uint8[][] memory numbersArray = new uint8[][](2);
        numbersArray[0] = new uint8[](2);
        numbersArray[1] = new uint8[](3);

        numbersArray[0][0] = 5;
        numbersArray[0][1] = 10;

        numbersArray[1][0] = 15;
        numbersArray[1][1] = 20;
        numbersArray[1][2] = 25;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ticketAmount;
        amounts[1] = ticketAmount * 2;

        lottery.purcaseMultipleTickets(numbersArray, amounts, referrer);
        vm.stopPrank();

        // Check if the tickets were purchased
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        assertEq(tickets.length, 2);

        // Check if total pool is updated
        assertEq(lottery.totalPool(), ticketAmount + (ticketAmount * 2));

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player1 claims prizes
        uint256 balanceBefore = token.balanceOf(player1);

        vm.prank(player1);
        lottery.claimPrizes();

        uint256 balanceAfter = token.balanceOf(player1);

        // Calculate expected prize
        uint256 expectedPrize = 0;

        // First ticket
        Lottery.Ticket memory ticket1 = lottery.getTicket(tickets[0]);
        uint256 expectedMultiplier1 = lottery.multipliers(2); // 2 matching numbers
        expectedPrize += ticket1.amount * expectedMultiplier1;

        // Second ticket
        Lottery.Ticket memory ticket2 = lottery.getTicket(tickets[1]);
        uint256 expectedMultiplier2 = lottery.multipliers(3); // 3 matching numbers
        expectedPrize += ticket2.amount * expectedMultiplier2;

        // Check if the prize was transferred
        assertEq(balanceAfter - balanceBefore, expectedPrize);
    }
}

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
