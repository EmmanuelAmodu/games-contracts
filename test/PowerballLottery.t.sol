// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/PowerballLottery.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PowerballLotteryTest is Test {
    PowerballLottery public lottery;
    MockERC20 public token;

    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public referrer = address(0x4);

    uint256 public ticketPrice = 100 ether; // Assuming token has 18 decimals

    function setUp() public {
        // Deploy a mock ERC20 token
        token = new MockERC20("Mock Token", "MTK", 18);

        // Distribute tokens to players
        token.mint(player1, 1000 ether);
        token.mint(player2, 1000 ether);

        // Deploy the lottery contract
        lottery = new PowerballLottery(owner, ticketPrice, address(token));

        // Transfer ownership to the owner address
        vm.prank(owner);
        lottery.transferOwnership(owner);

        // Players approve the lottery contract to spend their tokens
        vm.prank(player1);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(player2);
        token.approve(address(lottery), type(uint256).max);
    }

    function testPurchaseTicket() public {
        vm.startPrank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        bytes32 winningHash = keccak256(abi.encodePacked(salt, [uint8(1),2,3,4,5], uint8(10)));
        lottery.commitWinningNumbers(winningHash);
        vm.stopPrank();

        vm.startPrank(player1);
        uint8[5] memory whiteBalls = [uint8(1), 2, 3, 4, 5];
        uint8 powerBall = 10;
        lottery.purchaseTicket(whiteBalls, powerBall, referrer);
        vm.stopPrank();

        // Check if the ticket was purchased
        uint256[] memory tickets = lottery.getPlayerTickets(player1);
        assertEq(tickets.length, 1);

        // Check if total pool is updated
        assertEq(lottery.totalPool(), ticketPrice);
    }

    function testRevealWinningNumbersAndCalculatePrizes() public {
        // Owner commits to winning numbers
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        bytes32 winningHash = keccak256(abi.encodePacked(salt, [uint8(1),2,3,4,5], uint8(10)));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket
        vm.startPrank(player1);
        uint8[5] memory whiteBalls1 = [uint8(1), 2, 3, 4, 5];
        uint8 powerBall1 = 10;
        lottery.purchaseTicket(whiteBalls1, powerBall1, referrer);
        vm.stopPrank();

        // Player2 purchases a ticket with fewer matching numbers
        vm.startPrank(player2);
        uint8[5] memory whiteBalls2 = [uint8(1), 2, 3, 4, 6];
        uint8 powerBall2 = 11;
        lottery.purchaseTicket(whiteBalls2, powerBall2, referrer);
        vm.stopPrank();

        // Owner reveals the winning numbers
        vm.prank(owner);
        lottery.revealWinningNumbers(salt, [uint8(1),2,3,4,5], uint8(10));

        // Check if the winning numbers are set
        (uint8[5] memory winningWhiteBalls, ) = lottery.getWinningNumbers();
        for (uint8 i = 0; i < 5; i++) {
            assertEq(winningWhiteBalls[i], uint8(i + 1));
        }
        assertEq(lottery.winningPowerBall(), 10);

        // Check if prizes are calculated
        // Player1 should win the jackpot
        uint256[] memory tickets1 = lottery.getPlayerTickets(player1);
        PowerballLottery.Ticket memory ticket1 = lottery.getTicket(tickets1[0]);
        assertEq(ticket1.prizeTier, 1); // Jackpot
        assertGt(ticket1.prize, 0);

        // Player2 should have a lower prize tier
        uint256[] memory tickets2 = lottery.getPlayerTickets(player2);
        PowerballLottery.Ticket memory ticket2 = lottery.getTicket(tickets2[0]);
        assertEq(ticket2.prizeTier, 3); // Match 4 white balls
        assertGt(ticket2.prize, 0);

        // Check if userWithHighestMatchingNumber is set correctly
        assertEq(lottery.userWithHighestMatchingNumber(), player1);
    }

    function testClaimPrizes() public {
        // Setup and reveal winning numbers as before
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        bytes32 winningHash = keccak256(abi.encodePacked(salt, [uint8(1),2,3,4,5], uint8(10)));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);
        uint8[5] memory whiteBalls1 = [uint8(1), 2, 3, 4, 5];
        uint8 powerBall1 = 10;
        lottery.purchaseTicket(whiteBalls1, powerBall1, referrer);
        vm.stopPrank();

        vm.prank(owner);
        lottery.revealWinningNumbers(salt, [uint8(1),2,3,4,5], uint8(10));

        // Player1 claims prize
        uint256 balanceBefore = token.balanceOf(player1);

        vm.prank(player1);
        lottery.claimPrizes();

        uint256 balanceAfter = token.balanceOf(player1);

        // Check if the prize was transferred
        assertGt(balanceAfter, balanceBefore);

        // Ensure the ticket is marked as claimed
        uint256[] memory tickets1 = lottery.getPlayerTickets(player1);
        PowerballLottery.Ticket memory ticket1 = lottery.getTicket(tickets1[0]);
        assertTrue(ticket1.claimed);
    }

    function testClaimHighestMatchingRewards() public {
        // Setup and reveal winning numbers as before
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        bytes32 winningHash = keccak256(abi.encodePacked(salt, [uint8(1), 2, 3, 4, 5], uint8(10)));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);
        uint8[5] memory whiteBalls1 = [uint8(1), 2, 3, 4, 5];
        uint8 powerBall1 = 10;
        lottery.purchaseTicket(whiteBalls1, powerBall1, referrer);
        vm.stopPrank();

        vm.prank(owner);
        lottery.revealWinningNumbers(salt, [uint8(1),2,3,4,5], uint8(10));

        // Owner sets the highest match prize
        uint256 highestPrize = 500 ether;
        vm.prank(owner);
        lottery.setHighestMatchPrize(highestPrize);

        // Transfer tokens to lottery contract to cover the prize
        token.mint(address(lottery), highestPrize);

        // Player1 claims the highest matching rewards
        uint256 balanceBefore = token.balanceOf(player1);

        vm.prank(player1);
        lottery.claimHighestMatchingRewards();

        uint256 balanceAfter = token.balanceOf(player1);

        // Check if the highest match prize was transferred
        assertEq(balanceAfter - balanceBefore, highestPrize);
    }

    function testReferralRewards() public {
        // Owner commits to winning numbers to open ticket sales
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        bytes32 winningHash = keccak256(abi.encodePacked(salt, [uint8(1),2,3,4,5], uint8(10)));
        lottery.commitWinningNumbers(winningHash);

        // Player1 purchases a ticket with player2 as referrer
        vm.startPrank(player1);
        uint8[5] memory whiteBalls = [uint8(1), 2, 3, 4, 5];
        uint8 powerBall = 10;
        lottery.purchaseTicket(whiteBalls, powerBall, player2);
        vm.stopPrank();

        // Check referral rewards
        uint256 expectedReward = ticketPrice / 10; // 10% of ticket price
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
        // Setup and reveal winning numbers as before
        vm.prank(owner);
        bytes32 salt = keccak256(abi.encodePacked("secret_salt"));
        bytes32 winningHash = keccak256(abi.encodePacked(salt, [uint8(1),2,3,4,5], uint8(10)));
        lottery.commitWinningNumbers(winningHash);

        vm.startPrank(player1);
        uint8[5] memory whiteBalls1 = [uint8(1), 2, 3, 4, 5];
        uint8 powerBall1 = 10;
        lottery.purchaseTicket(whiteBalls1, powerBall1, referrer);
        vm.stopPrank();

        vm.prank(owner);
        lottery.revealWinningNumbers(salt, [uint8(1),2,3,4,5], uint8(10));

        // Owner withdraws remaining funds
        uint256 balanceBefore = token.balanceOf(owner);

        vm.prank(owner);
        lottery.ownerWithdraw();

        uint256 balanceAfter = token.balanceOf(owner);

        // Check if the owner received the remaining funds
        assertGt(balanceAfter, balanceBefore);
    }
}

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol) {
        
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
