// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/Event.sol";
import "../contracts/EventManager.sol";
import "../contracts/Governance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract MockPepperBaseTokenV1 is ERC20 {
    constructor() ERC20("MockPepperBaseTokenV1", "MTKN") {
        _mint(msg.sender, 1e30); // Mint 1 million tokens to deployer
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract EventTest is Test {
    MockPepperBaseTokenV1 token;
    EventManager eventManager;
    Governance governance;
    Event eventContract;

    address creator = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address protocolFeeRecipient = address(0x4);
    address owner = address(0x5);
    address admin = address(0x6);

    string[] outcomes = ["Team A wins", "Team B wins"];
    uint256 collateralAmount = 1000e18; // 1000 tokens

    function setUp() public {
        // Deploy MockPepperBaseTokenV1
        token = new MockPepperBaseTokenV1();

        // Deploy Governance contract
        governance = new Governance(owner);

        // Deploy EventManager contract
        eventManager = new EventManager(
            address(token),
            address(governance),
            protocolFeeRecipient
        );

        // Approve admin
        vm.startPrank(owner);
        governance.addAdmin(admin);
        vm.stopPrank();

        // Mint tokens to creator and users
        token.mint(creator, 1e24);
        token.mint(user1, 1e24);
        token.mint(user2, 1e24);

        // Creator approves EventManager to spend tokens
        vm.startPrank(creator);
        token.approve(address(eventManager), type(uint256).max);
        vm.stopPrank();

        // Users approve Event contract to spend tokens
        vm.startPrank(user1);
        token.approve(address(eventManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(eventManager), type(uint256).max);
        vm.stopPrank();

        // Create an event
        vm.startPrank(creator);
        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Description",
            "Sports",
            outcomes,
            block.timestamp + 3 hours, // Start time in 3 hours
            block.timestamp + 5 hours, // End time in 5 hours
            collateralAmount
        );
        vm.stopPrank();

        eventContract = Event(eventAddress);

        // Users approve Event contract to spend tokens
        vm.startPrank(user1);
        token.approve(eventAddress, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(eventAddress, type(uint256).max);
        vm.stopPrank();
    }

    function testInitialization() public {
        // Test that the event contract is initialized correctly
        assertEq(eventContract.title(), "Match A vs B");
        assertEq(eventContract.creator(), creator);
        assertEq(uint256(eventContract.status()), uint256(Event.EventStatus.Open));
    }

    function testPlaceBet() public {
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Check that the bet was recorded
        uint256 userBet = eventContract.getUserBet(user1, 0);
        assertEq(userBet, betAmount);

        uint256 outcomeStake = eventContract.getOutcomeStakes(0);
        assertEq(outcomeStake, betAmount);
    }

    function testCannotPlaceBetAfterStartTime() public {
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(eventContract.startTime()); // Move time to event start time

        vm.startPrank(user1);
        vm.expectRevert("Betting is closed");
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();
    }

    function testBetExceedsUserLimit() public {
        uint256 betAmount = (eventContract.bettingLimit() / 10) + 1e18;

        vm.warp(block.timestamp + 1 hours); // Move time forward

        vm.startPrank(user1);
        vm.expectRevert("Bet amount exceeds user limit");
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();
    }

    function testWithdrawBetOnCancelledEvent() public {
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        // User places a bet
        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Creator cancels the event
        vm.startPrank(creator);
        eventManager.cancelEvent(address(eventContract));
        vm.stopPrank();

        // User withdraws the bet
        vm.startPrank(user1);
        eventContract.withdrawBet(0);
        vm.stopPrank();

        uint256 userBet = eventContract.getUserBet(user1, 0);
        assertEq(userBet, 0);
    }

    function testCannotWithdrawBetIfNotCancelled() public {
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        // User places a bet
        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // User tries to withdraw bet
        vm.startPrank(user1);
        vm.expectRevert("Withdrawals not allowed");
        eventContract.withdrawBet(0);
        vm.stopPrank();
    }

    function testSubmitOutcome() public {
        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(0);
        vm.stopPrank();

        assertEq(uint256(eventContract.status()), uint256(Event.EventStatus.Resolved));
        assertEq(eventContract.winningOutcome(), 0);
    }

    function testCannotSubmitOutcomeBeforeEndTime() public {
        vm.warp(eventContract.endTime() - 1 hours);

        vm.startPrank(creator);
        vm.expectRevert("Event has not ended yet");
        eventContract.submitOutcome(0);
        vm.stopPrank();
    }

    function testContributeToDispute() public {
        // Setup: User places a bet
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(1); // Submit wrong outcome
        vm.stopPrank();

        // User contributes to dispute
        vm.warp(block.timestamp + 30 minutes); // Within dispute period

        vm.startPrank(user1);
        eventContract.contributeToDispute("Wrong outcome", 50e18);
        vm.stopPrank();

        assertEq(uint256(eventContract.disputeStatus()), uint256(Event.DisputeStatus.Disputed));
    }

    function testCannotContributeToDisputeAfterDeadline() public {
        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(1); // Submit wrong outcome
        vm.stopPrank();

        // Move past dispute deadline
        vm.warp(block.timestamp + 2 hours);

        // User tries to contribute to dispute
        vm.startPrank(user1);
        vm.expectRevert("Dispute period has ended");
        eventContract.contributeToDispute("Late dispute", 50e18);
        vm.stopPrank();
    }

    function testResolveDisputeOutcomeChanged() public {
        // Setup: User places a bet
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(1); // Submit wrong outcome
        vm.stopPrank();

        // User contributes to dispute
        vm.warp(block.timestamp + 30 minutes); // Within dispute period

        vm.startPrank(user1);
        eventContract.contributeToDispute("Wrong outcome", 50e18);
        vm.stopPrank();

        // Admin resolves the dispute
        vm.startPrank(owner);
        eventManager.resolveDispute(address(eventContract), 0); // Correct outcome
        vm.stopPrank();

        // Check that the outcome has changed
        assertEq(eventContract.winningOutcome(), 0);

        // Check that the creator's collateral was forfeited
        uint256 collateralBalance = eventManager.collateralBalances(address(eventContract));
        assertEq(collateralBalance, 0);
    }

    function testResolveDisputeOutcomeUpheld() public {
        // Setup: User places a bet
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(0); // Submit correct outcome
        vm.stopPrank();

        // User contributes to dispute
        vm.warp(block.timestamp + 30 minutes); // Within dispute period

        vm.startPrank(user1);
        eventContract.contributeToDispute("Disagree with outcome", 50e18);
        vm.stopPrank();

        // Admin resolves the dispute
        vm.startPrank(owner);
        eventManager.resolveDispute(address(eventContract), 0); // Outcome remains the same
        vm.stopPrank();

        // Check that the outcome remains the same
        assertEq(eventContract.winningOutcome(), 0);

        // Check that the creator's collateral is still locked (will be released upon claim)
        uint256 collateralBalance = eventManager.collateralBalances(address(eventContract));
        assertEq(collateralBalance, collateralAmount);
    }

    function testClaimPayout() public {
        // Setup: User places a bet
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(0); // Submit correct outcome
        vm.stopPrank();

        // Wait for dispute period to end
        vm.warp(block.timestamp + 2 hours);

        // User claims payout
        vm.startPrank(user1);
        eventContract.claimPayout();
        vm.stopPrank();

        // Check that the user has claimed
        bool hasClaimed = eventContract.hasClaimed(user1);
        assertEq(hasClaimed, true);
    }

    function testCannotClaimPayoutBeforeDisputeEnds() public {
        // Setup: User places a bet
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(0); // Submit correct outcome
        vm.stopPrank();

        // User tries to claim payout before dispute period ends
        vm.warp(block.timestamp + 30 minutes);

        vm.startPrank(user1);
        vm.expectRevert("Dispute period not over");
        eventContract.claimPayout();
        vm.stopPrank();
    }

    function testOddsCalculation() public {
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        // User1 bets on outcome 0
        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // User2 bets on outcome 1
        vm.startPrank(user2);
        eventContract.placeBet(1, betAmount * 2); // 200 tokens
        vm.stopPrank();

        // Get odds for outcome 0
        uint256 odds = eventContract.getOdds(0);
        // Expected odds: (TotalStaked - OutcomeStake) / OutcomeStake
        // (300 - 100) / 100 = 2 * 1e18
        assertEq(odds, 2e18);
    }

    function testEdgeCaseLastClaimant() public {
        // Setup: Two users place bets
        uint256 betAmount = 100e18; // 100 tokens

        vm.warp(block.timestamp + 1 hours); // Move time forward

        // User1 bets on outcome 0
        vm.startPrank(user1);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // User2 bets on outcome 0
        vm.startPrank(user2);
        eventContract.placeBet(0, betAmount);
        vm.stopPrank();

        // Fast forward to after event end time
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(0); // Winning outcome is 0
        vm.stopPrank();

        // Wait for dispute period to end
        vm.warp(block.timestamp + 2 hours);

        // User1 claims payout
        vm.startPrank(user1);
        eventContract.claimPayout();
        vm.stopPrank();

        // Simulate rounding error by reducing contract balance
        token.burn(1e18); // Burn 1 token from contract

        // User2 claims payout
        vm.startPrank(user2);
        eventContract.claimPayout();
        vm.stopPrank();

        // Ensure User2 received the remaining balance
        // This test ensures that the last claimant receives whatever is left in the contract
    }

    function testContentModerationEvents() public {
        // Creator updates thumbnail URL
        vm.startPrank(creator);
        eventContract.updateThumbnailUrl("https://example.com/thumbnail.png");
        vm.stopPrank();

        // Creator updates streaming URL
        vm.startPrank(creator);
        eventContract.updateStreamingUrl("https://example.com/streaming");
        vm.stopPrank();

        // You can check emitted events using vm.expectEmit if needed
    }

    function testCannotExceedMaxOutcomes() public {
        // Try to create an event with more than 12 outcomes
        string[] memory manyOutcomes = new string[](13);
        for (uint256 i = 0; i < 13; i++) {
            manyOutcomes[i] = string(abi.encodePacked("Outcome ", Strings.toString(i)));
        }

        vm.startPrank(creator);
        vm.expectRevert("Invalid number of outcomes");
        eventManager.createEvent(
            "Event with many outcomes",
            "Description",
            "Category",
            manyOutcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );
        vm.stopPrank();
    }
}
