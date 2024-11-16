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
        token.mint(address(lottery), 1_000_000_000_000 ether);

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

        // Player2 purchases a ticket with 3 numbers (all matching)
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
    }

    function testclaimPrize() public {
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
        lottery.claimPrize();

        uint256 balanceAfter = token.balanceOf(player1);

        // Check if the prize was transferred
        uint256 expectedPrize = ticketAmount * lottery.getMultiplier(5); // Multiplier for 5 selected numbers
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
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Check referral rewards
        uint256 expectedReward = (ticketAmount * 10) / 100; // 10% of ticket amount
        uint256 reward = lottery.referralRewards(referrer);
        assertEq(reward, expectedReward);

        // Player2 claims referral rewards
        uint256 balanceBefore = token.balanceOf(referrer);

        vm.prank(referrer);
        lottery.claimReferralRewards();

        uint256 balanceAfter = token.balanceOf(referrer);

        // Check if the referral reward was transferred
        assertEq(balanceAfter - balanceBefore, expectedReward);
    }

    function testPurchaseMultipleTickets() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [5, 10, 15, 20, 25];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);

        // Prepare numbers for multiple tickets
        uint8 [][] memory numbersArray = new uint8[][](2);
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

        // Note: The function name has a typo in the contract ("purchaseMultipleTickets")
        // Ensure the test calls the correct function name
        lottery.purchaseMultipleTickets(numbersArray, amounts, referrer);
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
        lottery.claimPrize();

        uint256 balanceAfter = token.balanceOf(player1);

        // Calculate expected prize
        uint256 expectedPrize = 0;

        // First ticket: [5,10] - both numbers match
        Lottery.Ticket memory ticket1 = lottery.getTicket(tickets[0]);
        expectedPrize += ticket1.amount * lottery.getMultiplier(2);

        // Second ticket: [15,20,25] - all numbers match
        Lottery.Ticket memory ticket2 = lottery.getTicket(tickets[1]);
        expectedPrize += ticket2.amount * lottery.getMultiplier(3);

        // Check if the prize was transferred
        assertEq(balanceAfter - balanceBefore, expectedPrize);
    }

    function testNoPrizeForPartialMatch() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("partial_match_salt"));
        uint8[5] memory winningNumbers = [10, 20, 30, 40, 50];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket with all numbers matching
        vm.startPrank(player1);
        uint8[] memory numbers1 = new uint8[](5);
        numbers1[0] = 10;
        numbers1[1] = 20;
        numbers1[2] = 30;
        numbers1[3] = 40;
        numbers1[4] = 50;
        lottery.purchaseTicket(numbers1, ticketAmount, referrer);
        vm.stopPrank();

        // Player2 purchases a ticket with some numbers matching
        vm.startPrank(player2);
        uint8[] memory numbers2 = new uint8[](3);
        numbers2[0] = 10;
        numbers2[1] = 20;
        numbers2[2] = 35; // Does not match
        lottery.purchaseTicket(numbers2, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player1 claims prize
        uint256 balanceBefore1 = token.balanceOf(player1);
        vm.prank(player1);
        lottery.claimPrize();
        uint256 balanceAfter1 = token.balanceOf(player1);
        uint256 expectedPrize1 = ticketAmount * lottery.getMultiplier(5); // Multiplier for 5 selected numbers
        assertEq(balanceAfter1 - balanceBefore1, expectedPrize1);

        // Player2 attempts to claim prize (should fail)
        vm.prank(player2);
        vm.expectRevert("No prizes to claim");
        lottery.claimPrize();

        // Ensure Player2's ticket is marked as not claimed and has no prize
        uint256[] memory tickets2 = lottery.getPlayerTickets(player2);
        Lottery.Ticket memory ticket2 = lottery.getTicket(tickets2[0]);
        assertFalse(ticket2.claimed);
        assertEq(ticket2.prize, 0);
    }

    // Additional test to ensure no prize is awarded when only some numbers match
    function testPartialMatchDoesNotAwardPrize() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("partial_match_salt2"));
        uint8[5] memory winningNumbers = [5, 15, 25, 35, 45];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket with 4 numbers, 3 of which match
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](4);
        numbers[0] = 5;
        numbers[1] = 15;
        numbers[2] = 25;
        numbers[3] = 90; // Does not match
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player1 attempts to claim prize (should fail)
        vm.prank(player1);
        vm.expectRevert("No prizes to claim");
        lottery.claimPrize();

        // Ensure Player1's ticket is marked as not claimed and has no prize
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        Lottery.Ticket memory ticket = lottery.getTicket(tickets[0]);
        assertFalse(ticket.claimed);
        assertEq(ticket.prize, 0);
    }

    function testPurchaseTicketWithMinimumNumbers() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("min_numbers_salt"));
        uint8[5] memory winningNumbers = [2, 4, 6, 8, 10];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket with 2 numbers (all matching)
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 2;
        numbers[1] = 4;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player1 claims prize
        uint256 balanceBefore = token.balanceOf(player1);

        vm.prank(player1);
        lottery.claimPrize();

        uint256 balanceAfter = token.balanceOf(player1);

        // Check if the prize was transferred
        uint256 expectedPrize = ticketAmount * lottery.getMultiplier(2); // Multiplier for 2 selected numbers
        assertEq(balanceAfter - balanceBefore, expectedPrize);

        // Ensure the ticket is marked as claimed
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        Lottery.Ticket memory ticket = lottery.getTicket(tickets[0]);
        assertTrue(ticket.claimed);
        assertEq(ticket.prize, expectedPrize);
    }

    function testPurchaseTicketWithMaximumNumbers() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("max_numbers_salt"));
        uint8[5] memory winningNumbers = [11, 22, 33, 44, 55];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player2 purchases a ticket with 5 numbers (all matching)
        vm.startPrank(player2);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 11;
        numbers[1] = 22;
        numbers[2] = 33;
        numbers[3] = 44;
        numbers[4] = 55;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player2 claims prize
        uint256 balanceBefore = token.balanceOf(player2);

        vm.prank(player2);
        lottery.claimPrize();

        uint256 balanceAfter = token.balanceOf(player2);

        // Check if the prize was transferred
        uint256 expectedPrize = ticketAmount * lottery.getMultiplier(5); // Multiplier for 5 selected numbers
        assertEq(balanceAfter - balanceBefore, expectedPrize);

        // Ensure the ticket is marked as claimed
        uint256[] memory tickets = lottery.getPlayerTickets(player2);
        Lottery.Ticket memory ticket = lottery.getTicket(tickets[0]);
        assertTrue(ticket.claimed);
        assertEq(ticket.prize, expectedPrize);
    }

    // New Test: Users attempting to select duplicate numbers (should revert)
    function testPurchaseTicketWithDuplicateNumbers() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("duplicate_numbers_salt"));
        uint8[5] memory winningNumbers = [7, 14, 21, 28, 35];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 attempts to purchase a ticket with duplicate numbers
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](3);
        numbers[0] = 7;
        numbers[1] = 14;
        numbers[2] = 7; // Duplicate number
        vm.expectRevert("Invalid numbers");
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Ensure no ticket was purchased
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        assertEq(tickets.length, 0);

        // Ensure total pool remains unchanged
        assertEq(lottery.totalPool(), 0);
    }

    // New Test: Users trying to claim prizes multiple times
    function testclaimPrizeMultipleTimes() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("multiple_claims_salt"));
        uint8[5] memory winningNumbers = [9, 18, 27, 36, 45];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket with 5 numbers (all matching)
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 9;
        numbers[1] = 18;
        numbers[2] = 27;
        numbers[3] = 36;
        numbers[4] = 45;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player1 claims prize for the first time
        uint256 balanceBeforeFirstClaim = token.balanceOf(player1);
        vm.prank(player1);
        lottery.claimPrize();
        uint256 balanceAfterFirstClaim = token.balanceOf(player1);

        // Check if the first prize was transferred
        uint256 expectedPrize = ticketAmount * lottery.getMultiplier(5); // Multiplier for 5 selected numbers
        assertEq(balanceAfterFirstClaim - balanceBeforeFirstClaim, expectedPrize);

        // Attempt to claim prizes again (should fail)
        vm.prank(player1);
        vm.expectRevert("No prizes to claim");
        lottery.claimPrize();

        // Ensure the ticket remains marked as claimed
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        Lottery.Ticket memory ticket = lottery.getTicket(tickets[0]);
        assertTrue(ticket.claimed);
        assertEq(ticket.prize, expectedPrize);
    }
}

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
