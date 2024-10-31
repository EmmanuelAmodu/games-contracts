// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/CrashGame.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply);
    }
}

contract CrashGameTest is Test {
    CrashGame crashGame;
    MockERC20 protocolToken;
    address owner;
    address player1;
    address player2;
    bytes32 commitment;
    string secret;
    bytes32 gameHash;

    // Define the same events as in CrashGame for testing purposes
    event GameCommitted(bytes32 indexed gameHash, bytes32 commitment);
    event BetPlaced(address indexed player, uint256 amount, bytes32 gameHash);
    event BetResolved(bytes32 gameHash, uint256 multiplier, bytes32 hmac);
    event Payout(address indexed player, uint256 amount);
    event GameRevealed(bytes32 indexed gameHash, uint256 multiplier, bytes32 hmac);
    event RefundClaimed(address indexed player, bytes32 gameHash, uint256 amount);

    // Set up the initial state before each test
    function setUp() public {
        // Assign addresses
        owner = address(0x1);
        player1 = address(0x2);
        player2 = address(0x3);

        // Deploy MockERC20 token with initial supply as owner
        vm.startPrank(owner);
        protocolToken = new MockERC20("ProtocolToken", "PTK", 1_000_000_000 * 10**18);
        
        // Deploy CrashGame contract
        crashGame = new CrashGame(owner, address(protocolToken));

        // Distribute tokens to players
        protocolToken.transfer(address(crashGame), 500_000_000 * 10**18);
        protocolToken.transfer(player1, 10_000 * 10**18);
        protocolToken.transfer(player2, 10_000 * 10**18);
        vm.stopPrank();

        // Prepare commitment
        secret = "my_secret";
        commitment = keccak256(abi.encodePacked(secret));

        // Compute initial gameHash
        gameHash = crashGame.currentGameHash();
    }

    // Helper function to set the current game as committed
    function commitCurrentGame() internal {
        vm.startPrank(owner);
        crashGame.commitGame(commitment);
        vm.stopPrank();
    }

    // Helper function to reveal the current game
    function revealCurrentGame() internal {
        vm.startPrank(owner);
        console.log("Revealing game with secret:", secret);
        crashGame.revealGame(secret);
        vm.stopPrank();
    }

    // Test deployment
    function testDeployment() public {
        assertEq(crashGame.owner(), owner);
        assertEq(address(crashGame.protocolToken()), address(protocolToken));
        assertTrue(crashGame.currentGameHash() != bytes32(0));
    }

    // Test committing a game
    function testCommitGame() public {
        // Only owner can commit
        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player1));
        crashGame.commitGame(commitment);

        // Owner commits the game
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit GameCommitted(gameHash, commitment);
        crashGame.commitGame(commitment);

        // Verify commitment is set
        bytes32 storedCommitment = crashGame.gameCommitments(gameHash);
        assertEq(storedCommitment, commitment);
    }

    // Test committing a game without resolving the previous one
    function testCommitGameWithoutResolving() public {
        // Owner commits the first game
        commitCurrentGame();

        // Attempt to commit a second game without resolving
        vm.prank(owner);
        vm.expectRevert("Commitment already set");
        crashGame.commitGame(commitment);
    }

    // Test placing a bet
    function testPlaceBet() public {
        commitCurrentGame();

        // Player1 approves CrashGame to spend tokens
        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);

        // Place a valid bet
        vm.expectEmit(true, true, false, true);
        emit BetPlaced(player1, 100 * 10**18, gameHash);
        crashGame.placeBet(100 * 10**18, 200); // 2.00x

        // Verify bet is recorded using tuple destructuring
        (
            address betPlayer,
            uint256 betAmount,
            bytes32 betGameHash,
            bytes32 resolvedHash,
            uint256 intendedMultiplier,
            uint256 multiplier,
            bool claimed,
            bool isWon
        ) = crashGame.bets(gameHash, player1);

        // Construct the Bet struct manually
        CrashGame.Bet memory bet = CrashGame.Bet({
            player: betPlayer,
            amount: betAmount,
            gameHash: betGameHash,
            resolvedHash: resolvedHash,
            intendedMultiplier: intendedMultiplier,
            multiplier: multiplier,
            claimed: claimed,
            isWon: isWon
        });

        assertEq(bet.player, player1);
        assertEq(bet.amount, 100 * 10**18);
        assertEq(bet.intendedMultiplier, 200);
        assertEq(bet.multiplier, 0);
        assertFalse(bet.claimed);
        assertFalse(bet.isWon);

        // Player1 cannot place multiple bets on the same game
        vm.expectRevert("Bet already placed");
        crashGame.placeBet(50 * 10**18, 150);
        vm.stopPrank();
    }

    // Test placing a bet below minimum
    function testPlaceBetBelowMinimum() public {
        commitCurrentGame();

        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);

        vm.expectRevert("Bet amount below minimum");
        crashGame.placeBet(5 * 10**18, 100); // Below minimum (10 tokens)
        vm.stopPrank();
    }

    // Test placing a bet above maximum
    function testPlaceBetAboveMaximum() public {
        commitCurrentGame();

        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);

        vm.expectRevert("Bet amount exceeds maximum");
        crashGame.placeBet(20_000 * 10**18, 100); // Above maximum (10,000 tokens)
        vm.stopPrank();
    }

    // Test revealing a game
    function testRevealGame() public {
        commitCurrentGame();

        // Only owner can reveal
        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player1));
        crashGame.revealGame(secret);

        // Compute expected resolvedHash
        bytes32 resolvedHash = keccak256(abi.encodePacked(gameHash, secret));

        // Get expected multiplier and hmac
        (uint256 expectedMultiplier, bytes32 expectedHmac) = crashGame.getResult(resolvedHash);

        // Owner reveals with correct secret
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit BetResolved(gameHash, expectedMultiplier, expectedHmac);
        vm.expectEmit(true, true, false, true);
        emit GameRevealed(gameHash, expectedMultiplier, expectedHmac);
        crashGame.revealGame(secret);

        // Verify result
        uint256 gameResult = crashGame.result(gameHash);

        console.log("Game result:", gameResult);
        assertEq(gameResult, expectedMultiplier);

        // Verify currentGameHash is updated
        bytes32 newGameHash = expectedHmac;
        assertEq(crashGame.currentGameHash(), newGameHash);
    }

    // Test revealing with incorrect secret
    function testRevealGameWithIncorrectSecret() public {
        commitCurrentGame();

        vm.prank(owner);
        vm.expectRevert("Commitment mismatch");
        crashGame.revealGame("wrong_secret");
    }

    // Test claiming payout for a winning bet
    function testClaimPayoutWinningBet() public {
        secret = "winning_secret";
        commitment = keccak256(abi.encodePacked(secret));
        commitCurrentGame();

        uint256 balanceBeforeBet = protocolToken.balanceOf(player1);
        uint256 betAmount = 100 * 10**18;

        // Player1 places a bet
        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);
        crashGame.placeBet(betAmount, 110); // Intended multiplier: 1.50x
        vm.stopPrank();

        // Owner reveals the game
        revealCurrentGame();

        // Get game result
        uint256 gameResult = crashGame.result(gameHash);

        console.log("Game result:", gameResult);

        // Calculate expected payout
        uint256 expectedPayout = (betAmount * 110) / 100;
        if (expectedPayout > crashGame.maximumPayout()) {
            expectedPayout = crashGame.maximumPayout();
        }

        console.log("Expected payout:", expectedPayout);

        // Player1 claims payout
        vm.startPrank(player1);
        CrashGame.Bet memory bet = crashGame.claimPayout(gameHash);

        // Verify payout
        assertEq(protocolToken.balanceOf(player1), balanceBeforeBet + expectedPayout - betAmount);
        assertTrue(bet.isWon);
        assertTrue(bet.claimed);
        vm.stopPrank();
    }

    // Test claiming payout for a losing bet
    function testClaimPayoutLosingBet() public {
        secret = "losing_secret";
        commitment = keccak256(abi.encodePacked(secret));
    
        commitCurrentGame();

        // Player1 places a bet
        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);
        crashGame.placeBet(100 * 10**18, 250); // Intended multiplier: 2.50x
        vm.stopPrank();

        // Owner reveals the game
        revealCurrentGame();

        // Get game result
        uint256 gameResult = crashGame.result(gameHash);

        console.log("Game result:", gameResult);

        // Player1 claims payout
        vm.startPrank(player1);
        CrashGame.Bet memory bet = crashGame.claimPayout(gameHash);

        // Verify no payout
        assertEq(protocolToken.balanceOf(player1), 10_000 * 10**18 - 100 * 10**18);
        assertFalse(bet.isWon);
        assertTrue(bet.claimed);
        vm.stopPrank();
    }

    // Test claiming payout before game is resolved
    function testClaimPayoutBeforeResolution() public {
        commitCurrentGame();

        // Player1 places a bet
        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);
        crashGame.placeBet(100 * 10**18, 150);
        vm.stopPrank();

        // Player1 tries to claim payout before game is revealed
        vm.startPrank(player1);
        vm.expectRevert("Game not resolved yet");
        crashGame.claimPayout(gameHash);
        vm.stopPrank();
    }

    // Test refunding a bet after reveal timeout
    function testRefundBet() public {
        commitCurrentGame();

        // Player1 places a bet
        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);
        crashGame.placeBet(100 * 10**18, 150);
        vm.stopPrank();

        // Fast forward time beyond the reveal timeout
        uint256 timeout = crashGame.revealTimeoutDuration();
        vm.warp(block.timestamp + timeout + 1 minutes);

        // Player1 refunds the bet
        vm.startPrank(player1);
        vm.expectEmit(true, false, false, true);
        emit RefundClaimed(player1, gameHash, 100 * 10**18);
        crashGame.refundBet(gameHash);
        vm.stopPrank();

        // Verify refund
        assertEq(protocolToken.balanceOf(player1), 10_000 * 10**18);
    }

    // Test refunding a bet before reveal timeout
    function testRefundBetBeforeTimeout() public {
        commitCurrentGame();

        // Player1 places a bet
        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);
        crashGame.placeBet(100 * 10**18, 150);
        vm.stopPrank();

        // Attempt to refund before timeout
        vm.startPrank(player1);
        vm.expectRevert("Reveal period not yet ended");
        crashGame.refundBet(gameHash);
        vm.stopPrank();
    }

    // Test pausing and unpausing the contract
    function testPauseAndUnpause() public {
        // Pause the contract
        vm.prank(owner);
        crashGame.pause();
        assertTrue(crashGame.paused());

        // Attempt to place a bet while paused
        commitCurrentGame();
        vm.startPrank(player1);
        protocolToken.approve(address(crashGame), type(uint256).max);
        // vm.expectRevert("Pausable: paused");
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        crashGame.placeBet(100 * 10**18, 150);
        vm.stopPrank();

        // Unpause the contract
        vm.prank(owner);
        crashGame.unpause();
        assertFalse(crashGame.paused());

        // Now placing a bet should work
        vm.startPrank(player1);
        crashGame.placeBet(100 * 10**18, 150);
        vm.stopPrank();
    }

    // Test withdrawing tokens by the owner
    function testWithdrawTokens() public {
        uint256 balanceBefore = protocolToken.balanceOf(address(crashGame));
        uint256 ownerBalanceBefore = protocolToken.balanceOf(owner);

        // Owner withdraws tokens
        vm.startPrank(owner);
        crashGame.withdrawTokens(300 * 10**18);
        vm.stopPrank();

        // Verify withdrawal
        assertEq(protocolToken.balanceOf(owner), ownerBalanceBefore + 300 * 10**18);
        assertEq(protocolToken.balanceOf(address(crashGame)), balanceBefore - 300 * 10**18);
    }

    // Test that non-owner cannot withdraw tokens
    function testNonOwnerWithdrawTokens() public {
        vm.startPrank(player1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player1));
        crashGame.withdrawTokens(100 * 10**18);
        vm.stopPrank();
    }

    // Test that non-owner cannot reset currentGameHash
    function testNonOwnerResetGameHash() public {
        vm.startPrank(player1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player1));
        crashGame.resetCurrentGameHash(keccak256("new_game_hash"));
        vm.stopPrank();
    }

    // Test that owner can reset currentGameHash
    function testOwnerResetGameHash() public {
        bytes32 newGameHash = keccak256("new_game_hash");

        vm.prank(owner);
        crashGame.resetCurrentGameHash(newGameHash);

        // Verify new gameHash is set
        assertEq(crashGame.currentGameHash(), newGameHash);
    }

    // Test that setting reveal timeout works
    function testSetRevealTimeout() public {
        uint256 newTimeout = 5 minutes;
        vm.prank(owner);
        crashGame.setRevealTimeout(newTimeout);
        assertEq(crashGame.revealTimeoutDuration(), newTimeout);
    }

    // Test that non-owner cannot set reveal timeout
    function testNonOwnerSetRevealTimeout() public {
        uint256 newTimeout = 5 minutes;
        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player1));
        crashGame.setRevealTimeout(newTimeout);
    }

    // Additional tests can be added here, such as testing multiple players, edge cases, etc.
}
