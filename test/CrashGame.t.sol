// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Import OpenZeppelin contracts for security and access control
import "@openzeppelin/contracts/utils/Pausable.sol";
import "forge-std/Test.sol";
import "../contracts/CrashGame.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CrashGameTest is Test {
    CrashGame public crashGame;
    MockERC20 public token;

    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);

    string public secret = "secret";
    bytes32 public commitment;

    uint256 public initialBalance = 100 ether;
    bytes32 public gameHash;

    function setUp() public {
        // Label addresses for clarity in logs
        vm.label(owner, "Owner");
        vm.label(player1, "Player1");
        vm.label(player2, "Player2");

        // Allocate initial balance to owner and players
        vm.deal(owner, initialBalance);
        vm.deal(player1, initialBalance);
        vm.deal(player2, initialBalance);

        // Deploy the contract as the owner
        vm.prank(owner);
        crashGame = new CrashGame(owner);

        // Deploy a mock ERC20 token and allocate to players
        token = new MockERC20("Test Token", "TTK");
        token.mint(player1, initialBalance);
        token.mint(player2, initialBalance);

        // Set maximum payout for the token
        vm.prank(owner);
        crashGame.setMaximumPayout(address(token), 1000 ether);
    }

    function testOwnerCanCommitGame() public {
        // Compute the commitment
        commitment = keccak256(abi.encodePacked(secret));

        // Owner commits the game
        vm.prank(owner);
        crashGame.commitGame(commitment);

        // Verify the commitment is stored
        gameHash = crashGame.currentGameHash();
        bytes32 storedCommitment = crashGame.gameCommitments(gameHash);
        assertEq(storedCommitment, commitment);
    }

    function testPlayerCanPlaceBet() public {
        // Owner commits the game
        testOwnerCanCommitGame();

        uint256 betAmount = 1 ether;
        uint256 intendedMultiplier = 200; // 2x

        // Player1 places a bet
        vm.prank(player1);
        crashGame.placeBet{value: betAmount}(betAmount, intendedMultiplier, address(0));

        // Verify the bet is recorded
        gameHash = crashGame.currentGameHash();
        CrashGame.Bet memory bet = crashGame.getBet(gameHash, player1);

        assertEq(bet.player, player1);
        assertEq(bet.amount, betAmount);
        assertEq(bet.intendedMultiplier, intendedMultiplier);
        assertEq(bet.token, address(0));
    }

    function testPlayerCanPlaceBetWithERC20() public {
        // Owner commits the game
        testOwnerCanCommitGame();

        uint256 betAmount = 50 ether;
        uint256 intendedMultiplier = 300; // 3x

        // Player1 approves the token transfer
        vm.startPrank(player1);
        token.approve(address(crashGame), betAmount);

        // Player1 places a bet with ERC20 token
        crashGame.placeBet(betAmount, intendedMultiplier, address(token));
        vm.stopPrank();

        // Verify the bet is recorded
        gameHash = crashGame.currentGameHash();
        CrashGame.Bet memory bet = crashGame.getBet(gameHash, player1);

        assertEq(bet.player, player1);
        assertEq(bet.amount, betAmount);
        assertEq(bet.intendedMultiplier, intendedMultiplier);
        assertEq(bet.token, address(token));
    }

    function testOwnerCanRevealGame() public {
        // Players place bets
        testPlayerCanPlaceBet();
        // testPlayerCanPlaceBetWithERC20();

        // Move forward in time to simulate passage of time
        vm.warp(block.timestamp + 1 minutes);

        // Owner reveals the game
        vm.prank(owner);
        crashGame.revealGame("secret");

        // Verify the result is stored
        uint256 resultMultiplier = crashGame.result(gameHash);
        assertGt(resultMultiplier, 0);
    }

    function testPlayerCanClaimPayout() public {
        // Players place bets
        testPlayerCanPlaceBet();

        gameHash = crashGame.currentGameHash();

        // Move forward in time to simulate passage of time
        vm.warp(block.timestamp + 1 minutes);

        // Owner reveals the game
        vm.prank(owner);
        crashGame.revealGame("secret");

        // Player1 claims payout
        vm.prank(player1);
        CrashGame.Bet memory bet = crashGame.claimPayout(gameHash);

        // Verify payout
        if (bet.isWon) {
            uint256 expectedPayout = (bet.amount * bet.intendedMultiplier) / 100;
            assertEq(address(player1).balance, initialBalance - bet.amount + expectedPayout);
        } else {
            assertEq(address(player1).balance, initialBalance - bet.amount);
        }
    }

    function testRefundBetAfterDeadline() public {
        // Player places a bet
        testPlayerCanPlaceBet();

        gameHash = crashGame.currentGameHash();

        // Move forward in time past the reveal deadline
        vm.warp(block.timestamp + 11 minutes);

        // Player1 refunds bet
        vm.prank(player1);
        crashGame.refundBet(gameHash);

        // Verify refund
        assertEq(address(player1).balance, initialBalance);
    }

    function testCannotPlaceBetAfterGameRevealed() public {
        // Owner commits and reveals the game immediately
        testOwnerCanCommitGame();
        gameHash = crashGame.currentGameHash();

        vm.prank(owner);
        crashGame.revealGame("secret");

        // Player attempts to place a bet
        vm.prank(player1);
        vm.expectRevert("Game not yet committed");
        crashGame.placeBet{value: 1 ether}(1 ether, 200, address(0));
    }

    function testWithdrawProtocolRevenue() public {
        // Players place bets
        testPlayerCanClaimPayout();

        // Move forward in time to simulate passage of time
        vm.warp(block.timestamp + 1 minutes);

        // Owner withdraws protocol revenue
        vm.prank(owner);
        crashGame.withdrawProtocolRevenue(1 ether, address(0));

        // Verify owner's balance increased
        assertEq(address(owner).balance, initialBalance + 1 ether);
    }

    function testPauseAndUnpause() public {
        testOwnerCanCommitGame();

        // Owner pauses the contract
        vm.prank(owner);
        crashGame.pause();

        // Player attempts to place a bet
        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        crashGame.placeBet{value: 1 ether}(1 ether, 200, address(0));

        // Owner unpauses the contract
        vm.prank(owner);
        crashGame.unpause();

        // Player places a bet successfully
        vm.prank(player1);
        crashGame.placeBet{value: 1 ether}(1 ether, 200, address(0));
    }

    function testSetMaximumPayout() public {
        // Owner sets maximum payout
        vm.prank(owner);
        crashGame.setMaximumPayout(address(0), 50 ether);

        // Verify maximum payout
        uint256 maxPayout = crashGame.tokenMaximumPayout(address(0));
        assertEq(maxPayout, 50 ether);
    }

    function testCannotRevealGameAfterDeadline() public {
        // Owner commits the game
        testOwnerCanCommitGame();

        gameHash = crashGame.currentGameHash();

        // Move forward in time past the reveal deadline
        vm.warp(block.timestamp + 11 minutes);

        // Owner attempts to reveal the game
        vm.prank(owner);
        vm.expectRevert("Reveal deadline passed");
        crashGame.revealGame(string(abi.encodePacked("secret")));
    }

    function testCannotRefundBetBeforeDeadline() public {
        // Player places a bet
        testPlayerCanPlaceBet();

        gameHash = crashGame.currentGameHash();

        // Player attempts to refund bet before deadline
        vm.prank(player1);
        vm.expectRevert("Reveal deadline not passed");
        crashGame.refundBet(gameHash);
    }

    function testCannotClaimPayoutBeforeGameResolved() public {
        // Player places a bet
        testPlayerCanPlaceBet();

        gameHash = crashGame.currentGameHash();

        // Player attempts to claim payout before game is resolved
        vm.prank(player1);
        vm.expectRevert("Game not resolved yet");
        crashGame.claimPayout(gameHash);
    }

    function testCannotClaimPayoutTwice() public {
        // Player places a bet and game is resolved
        testPlayerCanClaimPayout();

        // Player attempts to claim payout again
        vm.prank(player1);
        vm.expectRevert("Payout already claimed");
        crashGame.claimPayout(gameHash);
    }

    function testCannotRefundAfterClaim() public {
        // Player places a bet and game is resolved
        testPlayerCanClaimPayout();

        // Move forward in time past the reveal deadline
        vm.warp(block.timestamp + 11 minutes);

        // Player attempts to refund bet
        vm.prank(player1);
        vm.expectRevert("Bet already claimed or refunded");
        crashGame.refundBet(gameHash);
    }

    function testResetCurrentGameHash() public {
        // Owner resets the current game hash
        bytes32 newGameHash = keccak256(abi.encodePacked("newGameHash"));
        vm.prank(owner);
        crashGame.resetCurrentGameHash(newGameHash);

        // Verify the current game hash is updated
        assertEq(crashGame.currentGameHash(), newGameHash);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
