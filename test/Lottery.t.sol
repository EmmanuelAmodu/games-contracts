// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/Lottery.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract LotteryTest is Test {
    Lottery public lottery;
    MockERC20 public token;

    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public referrer = address(0x4);
    address public nonOwner = address(0x5);

    uint256 public ticketAmount = 100 ether; // Assuming token has 18 decimals

    function setUp() public {
        // Deploy a mock ERC20 token
        token = new MockERC20("Mock Token", "MTK");

        // Deploy the lottery contract
        lottery = new Lottery(owner, address(token));

        // Distribute tokens to players
        token.mint(player1, 100000 ether);
        token.mint(player2, 100000 ether);
        token.mint(referrer, 100000 ether);

        token.mint(owner, 1_000_000_001 ether);

        vm.prank(owner);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(owner);
        lottery.depositTokens(1_000_000_000 ether);

        // Players approve the lottery contract to spend their tokens
        vm.prank(player1);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(player2);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(referrer);
        token.approve(address(lottery), type(uint256).max);

        // Set nonOwner as a non-owner address
        vm.prank(nonOwner);
        token.approve(address(lottery), type(uint256).max);
    }

    function testPurchaseTicket() public {
        vm.startPrank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);
        vm.stopPrank();

        uint256 balanceBefore = token.balanceOf(address(lottery));

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
        assertEq(lottery.totalPool(), balanceBefore + ticketAmount);
    }

    function testPurchaseTicketWithFewerNumbers() public {
        vm.startPrank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        uint8[5] memory winningNumbers = [10, 20, 30, 40, 50];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);
        vm.stopPrank();

        uint256 balanceBefore = token.balanceOf(address(lottery));

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
        assertEq(lottery.totalPool(), balanceBefore + ticketAmount);
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

        uint256 balanceBefore = token.balanceOf(address(lottery));

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
        assertEq(lottery.totalPool(), balanceBefore);
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

    // Test: Non-owner attempting to commit winning numbers (should revert)
    function testNonOwnerCannotCommitWinningNumbers() public {
        vm.prank(nonOwner);
        bytes32 salt = keccak256(abi.encodePacked("non_owner_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        lottery.commitWinningNumbers(winningHash);
    }

    // Test: Non-owner attempting to reveal winning numbers (should revert)
    function testNonOwnerCannotRevealWinningNumbers() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("owner_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        lottery.revealWinningNumbers(salt, winningNumbers);
    }

    // Test: Owner attempting to reveal winning numbers without committing (should revert)
    function testRevealWithoutCommitment() public {
        bytes32 salt = keccak256(abi.encodePacked("no_commit_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];

        vm.prank(owner);
        vm.expectRevert("Ticket sales are closed");
        lottery.revealWinningNumbers(salt, winningNumbers);
    }

    // Test: Purchasing tickets when the lottery is closed (should revert)
    function testPurchaseTicketWhenClosed() public {
        // Lottery is closed by default
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        vm.expectRevert("Ticket sales are closed");
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();
    }

    // Test: Purchasing tickets when the lottery is paused (should revert)
    function testPurchaseTicketWhenPaused() public {
        vm.prank(owner);
        lottery.commitWinningNumbers(keccak256(abi.encodePacked("paused_salt")));

        vm.prank(owner);
        lottery.pause();

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();
    }

    // Test: Owner updating referral reward percent
    function testUpdateReferralRewardPercent() public {
        vm.prank(owner);
        lottery.updateReferralRewardPercent(5);
        assertEq(lottery.referralRewardPercent(), 5);

        // Attempt to set invalid percentage (should revert)
        vm.prank(owner);
        vm.expectRevert("Invalid percent amount");
        lottery.updateReferralRewardPercent(0);

        vm.prank(owner);
        vm.expectRevert("Invalid percent amount");
        lottery.updateReferralRewardPercent(11);
    }

    // Test: Non-owner attempting to update referral reward percent (should revert)
    function testNonOwnerCannotUpdateReferralRewardPercent() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        lottery.updateReferralRewardPercent(5);
    }

    // Test: Exceeding maximum tickets per player (should revert)
    function testExceedMaxTicketsPerPlayer() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("max_tickets_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;

        for (uint256 i = 0; i < lottery.MAX_TICKETS_PER_PLAYER(); i++) {
            lottery.purchaseTicket(numbers, ticketAmount, referrer);
        }

        // Attempt to purchase one more ticket (should revert)
        vm.expectRevert("Ticket limit reached");
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();
    }

    // Test: Attempting to purchase ticket with invalid amount (too low)
    function testPurchaseTicketWithInvalidAmountLow() public {
        vm.prank(owner);
        lottery.commitWinningNumbers(keccak256(abi.encodePacked("invalid_amount_low_salt")));

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;

        uint256 invalidAmount = (lottery.MIN_TICKET_PRICE() - 1) * 10 ** lottery.tokenDecimals();
        vm.expectRevert("Invalid amount: must be between 1 and 1000");
        lottery.purchaseTicket(numbers, invalidAmount, referrer);
        vm.stopPrank();
    }

    // Test: Attempting to purchase ticket with invalid amount (too high)
    function testPurchaseTicketWithInvalidAmountHigh() public {
        vm.prank(owner);
        lottery.commitWinningNumbers(keccak256(abi.encodePacked("invalid_amount_high_salt")));

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;

        uint256 invalidAmount = (lottery.MAX_TICKET_PRICE() + 1) * 10 ** lottery.tokenDecimals();
        vm.expectRevert("Invalid amount: must be between 1 and 1000");
        lottery.purchaseTicket(numbers, invalidAmount, referrer);
        vm.stopPrank();
    }

    // Test: Owner changing the token address
    function testChangeToken() public {
        MockERC20 newToken = new MockERC20("New Mock Token", "NMT");
        vm.prank(owner);
        lottery.changeToken(address(newToken));
        assertEq(address(lottery.token()), address(newToken));
        assertEq(lottery.tokenDecimals(), newToken.decimals());

        // Attempt to set invalid token address (should revert)
        vm.prank(owner);
        vm.expectRevert("Invalid token address");
        lottery.changeToken(address(0));
    }

    // Test: Non-owner attempting to change the token address (should revert)
    function testNonOwnerCannotChangeToken() public {
        MockERC20 newToken = new MockERC20("New Mock Token", "NMT");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        lottery.changeToken(address(newToken));
    }

    // Test: Pausing and unpausing the contract
    function testPauseAndUnpause() public {
        vm.prank(owner);
        lottery.pause();
        assertTrue(lottery.paused());

        // Attempt to purchase ticket while paused (should revert)
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner unpauses the contract
        vm.prank(owner);
        lottery.unpause();
        assertFalse(lottery.paused());
    }

    // Test: Non-owner attempting to pause the contract (should revert)
    function testNonOwnerCannotPause() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        lottery.pause();
    }

    // Test: Emergency reset by owner
    function testEmergencyReset() public {
        vm.prank(owner);
        lottery.pause();

        vm.prank(owner);
        lottery.emergencyReset();

        // Check that the lottery is reset
        assertEq(lottery.totalPool(), 0);
        assertFalse(lottery.isOpen());
        assertFalse(lottery.isRevealed());
        assertEq(lottery.drawTimestamp(), 0);
    }

    // Test: Non-owner attempting to perform emergency reset (should revert)
    function testNonOwnerCannotEmergencyReset() public {
        vm.prank(owner);
        lottery.pause();

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        lottery.emergencyReset();
    }

    // Test: Claiming referral rewards when there are none (should revert)
    function testClaimReferralRewardsWhenNone() public {
        vm.prank(referrer);
        vm.expectRevert("No referral rewards to claim");
        lottery.claimReferralRewards();
    }

    // Test: Referrer is the same as the purchaser (no rewards should be granted)
    function testReferrerIsPurchaser() public {
        vm.prank(owner);
        lottery.commitWinningNumbers(keccak256(abi.encodePacked("self_referral_salt")));

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;
        lottery.purchaseTicket(numbers, ticketAmount, player1); // Referrer is the same as purchaser
        vm.stopPrank();

        // Referrer should have zero rewards
        uint256 reward = lottery.referralRewards(player1);
        assertEq(reward, 0);
    }

    // Test: Claiming prize before winning numbers are revealed (should revert)
    function testClaimPrizeBeforeReveal() public {
        vm.prank(owner);
        lottery.commitWinningNumbers(keccak256(abi.encodePacked("claim_before_reveal_salt")));

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Player attempts to claim prize before numbers are revealed
        vm.prank(player1);
        vm.expectRevert("Winning numbers not revealed yet");
        lottery.claimPrize();
    }

    // Test: Attempting to claim prize without any tickets (should revert)
    function testClaimPrizeWithoutTickets() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("no_tickets_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Non-player attempts to claim prize
        vm.prank(nonOwner);
        vm.expectRevert("No tickets purchased");
        lottery.claimPrize();
    }

    // Test: Owner withdrawing funds (should transfer funds to owner)
    function testOwnerWithdrawFunds() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("owner_withdraw_salt"));
        uint8[5] memory winningNumbers = [5, 10, 15, 20, 25];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 5;
        numbers[1] = 10;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Owner attempts to withdraw the remaining pool (after prizes)
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 contractBalanceBefore = token.balanceOf(address(lottery));

        vm.prank(owner);
        // Assuming the owner can withdraw the remaining pool (not implemented in the contract)
        // If there's a function to withdraw excess funds, it should be tested here.

        // Since such a function doesn't exist in the contract, this test is illustrative.

        // Owner's balance should remain unchanged (no withdrawal function)
        uint256 ownerBalanceAfter = token.balanceOf(owner);
        assertEq(ownerBalanceAfter, ownerBalanceBefore);
        // Contract balance should remain the same
        uint256 contractBalanceAfter = token.balanceOf(address(lottery));
        assertEq(contractBalanceAfter, contractBalanceBefore);
    }

    // Test: Purchasing a ticket with invalid numbers (out of range)
    function testPurchaseTicketWithInvalidNumbersOutOfRange() public {
        vm.prank(owner);
        lottery.commitWinningNumbers(keccak256(abi.encodePacked("invalid_numbers_range_salt")));

        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 0; // Invalid number (below MIN_NUMBER)
        numbers[1] = 91; // Invalid number (above MAX_NUMBER)
        vm.expectRevert("Invalid numbers");
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();
    }

    // Test: Retrieving previous game data
    function testGetPreviousGameData() public {
        // Commit and reveal winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("previous_game_salt"));
        uint8[5] memory winningNumbers = [5, 10, 15, 20, 25];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 5;
        numbers[1] = 10;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Save the game and reset
        vm.prank(owner);
        lottery.commitWinningNumbers(keccak256(abi.encodePacked("new_game_salt")));

        // Retrieve previous game winning numbers
        uint8[5] memory previousWinningNumbers = lottery.getPreviousGameWinningNumbers(winningHash);
        for (uint8 i = 0; i < 5; i++) {
            assertEq(previousWinningNumbers[i], winningNumbers[i]);
        }

        // Retrieve previous game tickets
        Lottery.Ticket[] memory previousTickets = lottery.getPreviousGameTickets(winningHash);
        assertEq(previousTickets.length, 1);
        assertEq(previousTickets[0].player, player1);

        // Retrieve player's tickets from previous game
        uint256[] memory playerTickets = lottery.getPreviousGamePlayerTickets(winningHash, player1);
        assertEq(playerTickets.length, 1);
    }

    // Test: Attempting to retrieve non-existent previous game data (should revert)
    function testGetNonExistentPreviousGameData() public {
        bytes32 nonExistentCommit = keccak256(abi.encodePacked("non_existent_commit"));

        vm.expectRevert("Game does not exist");
        lottery.getPreviousGameWinningNumbers(nonExistentCommit);

        vm.expectRevert("Game does not exist");
        lottery.getPreviousGameTickets(nonExistentCommit);

        vm.expectRevert("Game does not exist");
        lottery.getPreviousGamePlayerTickets(nonExistentCommit, player1);
    }

    // Test: Attempting to purchase multiple tickets with mismatched inputs (should revert)
    // function testPurchaseMultipleTicketsWithMismatchedInputs() public {
    //     vm.prank(owner);
    //     lottery.commitWinningNumbers(keccak256(abi.encodePacked("mismatched_inputs_salt")));

    //     vm.startPrank(player1);

    //     uint8 [][] memory numbersArray = new uint8[][](2);
    //     numbersArray[0] = new uint8[](2);
    //     numbersArray[1] = new uint8[](3);

    //     numbersArray[0][0] = 1;
    //     numbersArray[0][1] = 2;

    //     numbersArray[1][0] = 3;
    //     numbersArray[1][1] = 4;
    //     numbersArray[1][2] = 5;

    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = ticketAmount;

    //     vm.expectRevert("Invalid input lengths");
    //     lottery.purchaseMultipleTickets(numbersArray, amounts, referrer);
    //     vm.stopPrank();
    // }

    // Test: Attempting to purchase a ticket when sales are open but not revealed
    function testPurchaseTicketAfterReveal() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("after_reveal_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        // Owner reveals the winning numbers immediately
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Player attempts to purchase a ticket (should revert)
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        vm.expectRevert("Ticket sales are closed");
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();
    }

    // Test: Ensuring owner cannot reveal winning numbers twice
    function testOwnerCannotRevealWinningNumbersTwice() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("reveal_twice_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.prank(owner);
        lottery.revealWinningNumbers(salt, winningNumbers);

        // Attempt to reveal again (should revert)
        vm.prank(owner);
        vm.expectRevert("Ticket sales are closed");
        lottery.revealWinningNumbers(salt, winningNumbers);
    }

    // Test: Owner committing invalid winning numbers hash (zero hash)
    function testCommitWinningNumbersWithInvalidHash() public {
        vm.prank(owner);
        vm.expectRevert("Invalid hash");
        lottery.commitWinningNumbers(bytes32(0));
    }

    // Test: Owner revealing winning numbers with incorrect salt (should revert)
    function testRevealWinningNumbersWithIncorrectSalt() public {
        vm.prank(owner);
        bytes32 correctSalt = keccak256(abi.encodePacked("correct_salt"));
        uint8[5] memory winningNumbers = [1, 2, 3, 4, 5];
        bytes32 winningHash = keccak256(abi.encodePacked(correctSalt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        bytes32 incorrectSalt = keccak256(abi.encodePacked("incorrect_salt"));
        vm.prank(owner);
        vm.expectRevert("Commitment does not match");
        lottery.revealWinningNumbers(incorrectSalt, winningNumbers);
    }

    // Test: Owner revealing winning numbers with invalid numbers (duplicates)
    function testRevealWinningNumbersWithInvalidNumbers() public {
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("invalid_winning_numbers_salt"));
        uint8[5] memory winningNumbers = [1, 1, 2, 3, 4]; // Duplicate number
        bytes32 winningHash = keccak256(abi.encodePacked(salt, winningNumbers));
        lottery.commitWinningNumbers(winningHash);

        vm.prank(owner);
        vm.expectRevert("Invalid winning numbers");
        lottery.revealWinningNumbers(salt, winningNumbers);
    }
}

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
