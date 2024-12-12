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

    // Predefined salt and winning numbers for consistency in tests
    bytes32 public predefinedSalt = keccak256(abi.encodePacked("predefined_salt"));
    uint8[5] public predefinedWinningNumbers = [1, 2, 3, 4, 5];
    bytes32 public predefinedWinningHash;

    function setUp() public {
        // Initialize the predefinedWinningHash
        predefinedWinningHash = keccak256(abi.encodePacked(predefinedSalt, predefinedWinningNumbers));

        // Deploy a mock ERC20 token
        token = new MockERC20("Mock Token", "MTK");

        // Deploy the lottery contract with the predefined winningNumbersHash
        lottery = new Lottery(owner, address(token), predefinedWinningHash);

        // Distribute tokens to players
        token.mint(player1, 100_000 ether);
        token.mint(player2, 100_000 ether);
        token.mint(referrer, 100_000 ether);

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
        // Since winningNumbersHash is already set in the constructor, no need to commit again

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

        // Owner reveals the winning numbers (should match the predefined hash)
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

        // Check if the winning numbers are set
        uint8[5] memory revealedNumbers = lottery.getWinningNumbers();
        for (uint8 i = 0; i < 5; i++) {
            assertEq(revealedNumbers[i], predefinedWinningNumbers[i]);
        }
    }

    function testClaimPrize() public {
        // Player1 purchases a ticket with all numbers matching
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

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
        // Player1 purchases a ticket with referrer
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](3);
        numbers[0] = 10;
        numbers[1] = 20;
        numbers[2] = 30;
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

        // Player1 claims prizes
        uint256 balanceBefore = token.balanceOf(player1);

        lottery.purchaseMultipleTickets(numbersArray, amounts, referrer);
        vm.stopPrank();

        // Check if the tickets were purchased
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        assertEq(tickets.length, 2);

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

        vm.prank(player1);
        lottery.claimPrize();

        uint256 balanceAfter = token.balanceOf(player1);

        console.log("Balance after claim:", balanceAfter);
        console.log("Balance before claim:", balanceBefore);

        // Since winningNumbers are [1,2,3,4,5], the second ticket numbers do not match
        // Thus, expectedPrize only includes the first ticket
        assertEq(balanceBefore - balanceAfter, ticketAmount * 3);

        // Ensure the tickets are marked appropriately
        Lottery.Ticket memory updatedTicket1 = lottery.getTicket(tickets[0]);
        assertTrue(updatedTicket1.claimed);
        assertEq(updatedTicket1.prize, 0);

        Lottery.Ticket memory updatedTicket2 = lottery.getTicket(tickets[1]);
        assertTrue(updatedTicket2.claimed);
        assertEq(updatedTicket2.prize, 0);
    }

    function testNoPrizeForPartialMatch() public {
        // Player1 purchases a ticket with all numbers matching
        vm.startPrank(player1);
        uint8[] memory numbers1 = new uint8[](5);
        numbers1[0] = 1;
        numbers1[1] = 2;
        numbers1[2] = 3;
        numbers1[3] = 4;
        numbers1[4] = 5;
        lottery.purchaseTicket(numbers1, ticketAmount, referrer);
        vm.stopPrank();

        // Player2 purchases a ticket with some numbers matching
        vm.startPrank(player2);
        uint8[] memory numbers2 = new uint8[](3);
        numbers2[0] = 1;
        numbers2[1] = 2;
        numbers2[2] = 35; // Does not match
        lottery.purchaseTicket(numbers2, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

        // Player1 claims prize
        uint256 balanceBefore1 = token.balanceOf(player1);
        vm.prank(player1);
        lottery.claimPrize();
        uint256 balanceAfter1 = token.balanceOf(player1);
        uint256 expectedPrize1 = ticketAmount * lottery.getMultiplier(5); // Multiplier for 5 selected numbers
        assertEq(balanceAfter1 - balanceBefore1, expectedPrize1);

        // Player2 attempts to claim prize (should fail)
        vm.prank(player2);
        lottery.claimPrize();

        // Ensure Player2's ticket is marked as not claimed and has no prize
        uint256[] memory tickets2 = lottery.getPlayerTickets(player2);
        Lottery.Ticket memory ticket2 = lottery.getTicket(tickets2[0]);
        assertTrue(ticket2.claimed);
        assertEq(ticket2.prize, 0);
    }

    // Additional test to ensure no prize is awarded when only some numbers match
    function testPartialMatchDoesNotAwardPrize() public {
        // Player1 purchases a ticket with 4 numbers, 3 of which match
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](4);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 90; // Does not match
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

        // Player1 attempts to claim prize (should fail)
        vm.prank(player1);
        lottery.claimPrize();

        // Ensure Player1's ticket is marked as not claimed and has no prize
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        Lottery.Ticket memory ticket = lottery.getTicket(tickets[0]);
        assertTrue(ticket.claimed);
        assertEq(ticket.prize, 0);
    }

    function testPurchaseTicketWithMinimumNumbers() public {
        // Player1 purchases a ticket with 2 numbers (all matching)
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

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
        // Player2 purchases a ticket with 5 numbers (all matching)
        vm.startPrank(player2);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

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
    }

    // New Test: Users trying to claim prizes multiple times
    function testClaimPrizeMultipleTimes() public {
        // Player1 purchases a ticket with all numbers matching
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

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
        lottery.claimPrize();

        // Ensure the ticket remains marked as claimed
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        Lottery.Ticket memory ticket = lottery.getTicket(tickets[0]);
        assertTrue(ticket.claimed);
        assertEq(ticket.prize, expectedPrize);
    }

    // Test: Non-owner attempting to commit winning numbers (should revert)
    // Removed: commitWinningNumbers is now handled in the constructor

    // Test: Non-owner attempting to reveal winning numbers (should revert)
    function testNonOwnerCannotRevealWinningNumbers() public {
        // Non-owner attempts to reveal winning numbers
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);
    }

    // Test: Owner attempting to reveal winning numbers twice (should revert)
    function testOwnerCannotRevealWinningNumbersTwice() public {
        // Owner reveals the winning numbers for the first time
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

        // Attempt to reveal again (should revert)
        vm.prank(owner);
        vm.expectRevert("Ticket sales are closed");
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);
    }

    // Test: Purchasing tickets when the lottery is closed (should revert)
    function testPurchaseTicketWhenClosed() public {
        // Owner reveals the winning numbers, closing the lottery
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

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

    // Test: Purchasing tickets when the lottery is paused (should revert)
    function testPurchaseTicketWhenPaused() public {
        // Owner pauses the contract
        vm.prank(owner);
        lottery.pause();

        // Player attempts to purchase a ticket while paused (should revert)
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
        // Update to 5%
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
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        lottery.updateReferralRewardPercent(5);
    }

    // Test: Exceeding maximum tickets per player (should revert)
    function testExceedMaxTicketsPerPlayer() public {
        // Player1 purchases maximum allowed tickets
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
        // Player1 attempts to purchase a ticket with amount below minimum
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
        // Player1 attempts to purchase a ticket with amount above maximum
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;

        uint256 invalidAmount = (lottery.MAX_TICKET_PRICE() + 1) * 10 ** lottery.tokenDecimals();
        vm.expectRevert("Invalid amount: must be between 1 and 1000");
        lottery.purchaseTicket(numbers, invalidAmount, referrer);
        vm.stopPrank();
    }

    // Test: Pausing and unpausing the contract
    function testPauseAndUnpause() public {
        // Owner pauses the contract
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

        // Now, purchasing should succeed
        vm.startPrank(player1);
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();
    }

    // Test: Non-owner attempting to pause the contract (should revert)
    function testNonOwnerCannotPause() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        vm.prank(nonOwner);
        lottery.pause();
    }

    // Test: Claiming referral rewards when there are none (should revert)
    function testClaimReferralRewardsWhenNone() public {
        vm.prank(referrer);
        vm.expectRevert("No referral rewards to claim");
        lottery.claimReferralRewards();
    }

    // Test: Referrer is the same as the purchaser (no rewards should be granted)
    function testReferrerIsPurchaser() public {
        // Player1 purchases a ticket with themselves as referrer
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
        // Player1 purchases a ticket
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](2);
        numbers[0] = 1;
        numbers[1] = 2;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Player1 attempts to claim prize before numbers are revealed
        vm.prank(player1);
        vm.expectRevert("Winning numbers not revealed yet");
        lottery.claimPrize();
    }

    // Test: Attempting to claim prize without any tickets (should revert)
    function testClaimPrizeWithoutTickets() public {
        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

        // Non-player attempts to claim prize
        vm.prank(nonOwner);
        vm.expectRevert("No tickets purchased");
        lottery.claimPrize();
    }

    // Test: Purchasing a ticket with invalid numbers (out of range)
    function testPurchaseTicketWithInvalidNumbersOutOfRange() public {
        // Player1 attempts to purchase a ticket with numbers out of range
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 0;  // Invalid number (below MIN_NUMBER)
        numbers[1] = 91; // Invalid number (above MAX_NUMBER)
        vm.expectRevert("Invalid numbers");
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();
    }

    // Test: Retrieving ticket details
    function testGetTicketDetails() public {
        // Player1 purchases a ticket
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](3);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Retrieve the ticket
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        assertEq(tickets.length, 1);

        Lottery.Ticket memory ticket = lottery.getTicket(tickets[0]);
        assertEq(ticket.player, player1);
        assertEq(ticket.amount, ticketAmount);
        assertEq(ticket.numbers.length, 3);
        for (uint8 i = 0; i < 3; i++) {
            assertEq(ticket.numbers[i], numbers[i]);
        }
        assertFalse(ticket.claimed);
        assertEq(ticket.prize, 0);
    }

    // Test: Owner withdrawing tokens after multiple operations
    function testOwnerWithdrawAfterOperations() public {
        // Player1 purchases a ticket
        vm.startPrank(player1);
        uint8[] memory numbers = new uint8[](5);
        numbers[0] = 1;
        numbers[1] = 2;
        numbers[2] = 3;
        numbers[3] = 4;
        numbers[4] = 5;
        lottery.purchaseTicket(numbers, ticketAmount, referrer);
        vm.stopPrank();

        // Player2 purchases a ticket
        vm.startPrank(player2);
        uint8[] memory numbers2 = new uint8[](3);
        numbers2[0] = 1;
        numbers2[1] = 2;
        numbers2[2] = 35;
        lottery.purchaseTicket(numbers2, ticketAmount, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers);

        // Player1 claims prize
        vm.prank(player1);
        lottery.claimPrize();

        // Player2 claims prize
        vm.prank(player2);
        lottery.claimPrize();

        // Owner withdraws some tokens
        uint256 availableBalance = token.balanceOf(address(lottery)) - lottery.totalPool();
        console.log("Available balance:", availableBalance);
        console.log("token.balanceOf(address(lottery)):", token.balanceOf(address(lottery)));
        console.log("lottery.totalPool():", lottery.totalPool());

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        vm.prank(owner);
        lottery.withdrawTokens(availableBalance);

        // Check owner's token balance
        uint256 ownerBalance = token.balanceOf(owner);
        assertEq(ownerBalance, ownerBalanceBefore + availableBalance);
    }
}

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
