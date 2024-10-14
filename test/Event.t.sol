// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/Event.sol";
import "../contracts/EventManager.sol";
import "../contracts/Governance.sol";
import {ERC20, IERC20Errors} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 __decimals) ERC20(name, symbol) {
        _decimals = __decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract EventTest is Test {
    Event public eventContract;
    EventManager public eventManager;
    Governance public governance;
    MockERC20 public protocolToken;

    address public owner;
    address public admin1;
    address public creator;
    address public user1;
    address public user2;
    address public protocolFeeRecipient;
    string[] public outcomes;

    function setUp() public {
        owner = vm.addr(1);
        admin1 = vm.addr(2);
        creator = vm.addr(3);
        user1 = vm.addr(4);
        user2 = vm.addr(5);
        protocolFeeRecipient = vm.addr(6);
        outcomes = new string[](2);

        // Deploy MockERC20 token
        protocolToken = new MockERC20("protocolToken", "BET", 18);

        // Distribute tokens to users
        protocolToken.mint(creator, 10_000 ether);
        protocolToken.mint(user1, 10_000 ether);
        protocolToken.mint(user2, 10_000 ether);

        // Deploy Governance contract and add an admin
        vm.startPrank(owner);
        governance = new Governance(owner);
        governance.addAdmin(admin1);
        vm.stopPrank();

        // Deploy EventManager contract
        eventManager = new EventManager(address(protocolToken), address(governance), protocolFeeRecipient);

        // For testing purposes, we'll deploy an Event contract
        // Event constructor parameters:
        // (title, description, category, outcomes, startTime, endTime, creator, collateralAmount, collateralManager, protocolToken)
        string memory title = "Test Event";
        string memory description = "This is a test event";
        string memory category = "Sports";
        outcomes[0] = "Team A";
        outcomes[1] = "Team B";
        uint256 startTime = block.timestamp + 1 hours; // Starts in 1 hour
        uint256 endTime = block.timestamp + 3 hours; // Ends in 3 hours
        uint256 collateralAmount = 100 ether; // 100 BET

        eventContract = new Event(
            0,
            title,
            description,
            category,
            outcomes,
            startTime,
            endTime,
            creator,
            collateralAmount,
            address(eventManager),
            address(protocolToken)
        );
    }

    function testPlaceBet() public {
        vm.startPrank(user1);

        // Approve the Event contract to spend user1's tokens
        protocolToken.approve(address(eventContract), 50 ether);

        // Place a bet on outcome 0
        eventContract.placeBet(0, 50 ether);

        vm.stopPrank();

        // Check that user1's bet is recorded
        uint256 userBet = eventContract.getUserBet(user1, 0);
        assertEq(userBet, 50 ether);

        // Check that the total staked amount is updated
        uint256 totalStaked = eventContract.totalStaked();
        assertEq(totalStaked, 50 ether);
    }

    function testPlaceBetAfterStartTimeShouldFail() public {
        vm.startPrank(user1);

        // Approve the Event contract to spend user1's tokens
        protocolToken.approve(address(eventContract), 50 ether);

        // Fast forward time to after startTime
        vm.warp(eventContract.startTime());

        // Try to place a bet before the event has started
        vm.expectRevert("Betting is closed");
        eventContract.placeBet(0, 50 ether);

        vm.stopPrank();
    }

    function testPlaceBetAfterEndTimeShouldFail() public {
        vm.startPrank(user1);

        // Approve the Event contract to spend user1's tokens
        protocolToken.approve(address(eventContract), 50 ether);

        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        // Try to place a bet after the event has ended
        vm.expectRevert("Betting is closed");
        eventContract.placeBet(0, 50 ether);

        vm.stopPrank();
    }

    function testSubmitOutcome() public {
        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        vm.startPrank(creator);

        // Submit the outcome
        eventContract.submitOutcome(0);

        vm.stopPrank();

        // Check that the event status is updated to Resolved
        uint256 status = uint256(eventContract.status());
        assertEq(status, uint256(Event.EventStatus.Resolved));

        // Check that the winning outcome is set
        uint256 winningOutcome = eventContract.winningOutcome();
        assertEq(winningOutcome, 0);
    }

    function testSubmitOutcomeBeforeEndTimeShouldFail() public {
        // Fast forward time to before endTime
        vm.warp(eventContract.endTime() - 1 hours);

        vm.startPrank(creator);

        // Try to submit the outcome before the event has ended
        vm.expectRevert("Event has not ended yet");
        eventContract.submitOutcome(0);

        vm.stopPrank();
    }

    function testSubmitOutcomeByNonCreatorShouldFail() public {
        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        vm.startPrank(user1);

        // Try to submit the outcome as a non-creator
        vm.expectRevert("Only event creator");
        eventContract.submitOutcome(0);

        vm.stopPrank();
    }

    function testClaimPayout() public {
        // User1 places a bet
        testPlaceBet();

        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(0);
        vm.stopPrank();

        // Fast forward time to after disputeDeadline
        vm.warp(block.timestamp + 2 hours);

        vm.startPrank(user1);

        // Claim payout
        uint256 initialBalance = protocolToken.balanceOf(user1);
        eventContract.claimPayout();
        uint256 finalBalance = protocolToken.balanceOf(user1);

        vm.stopPrank();

        // Check that user1 received the payout
        assertTrue(finalBalance > initialBalance);

        // Check that hasClaimed is updated
        bool hasClaimed = eventContract.hasClaimed(user1);
        assertTrue(hasClaimed);
    }

    function testClaimPayoutBeforeDisputeDeadlineShouldFail() public {
        // User1 places a bet
        testPlaceBet();

        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(0);
        vm.stopPrank();

        // Try to claim payout before disputeDeadline
        vm.startPrank(user1);

        vm.expectRevert("Dispute period not over");
        eventContract.claimPayout();

        vm.stopPrank();
    }

    function testCreateDispute() public {
        // User1 places a bet
        testPlaceBet();

        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(1); // Let's say the winning outcome is 1
        vm.stopPrank();

        // User1 creates a dispute
        vm.startPrank(user1);

        // Approve the Event contract to spend dispute collateral
        uint256 disputeCollateral = (eventContract.totalStaked() * 10) / 100;
        protocolToken.approve(address(eventContract), disputeCollateral);

        eventContract.createDispute("Disagree with outcome");

        vm.stopPrank();

        // Check that disputeStatus is updated
        uint256 disputeStatus = uint256(eventContract.disputeStatus());
        assertEq(disputeStatus, uint256(Event.DisputeStatus.Disputed));

        // Check that disputingUser is set
        address disputingUser = eventContract.disputingUser();
        assertEq(disputingUser, user1);
    }

    function testCreateDisputeAfterDisputeDeadlineShouldFail() public {
        // User1 places a bet
        testPlaceBet();

        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome
        vm.startPrank(creator);
        eventContract.submitOutcome(1); // Winning outcome is 1
        vm.stopPrank();

        // Fast forward time to after disputeDeadline
        vm.warp(block.timestamp + 2 hours);

        // User1 tries to create a dispute
        vm.startPrank(user1);

        vm.expectRevert("Dispute period has ended");
        eventContract.createDispute("Disagree with outcome");

        vm.stopPrank();
    }

    function testResolveDispute() public {
        // User1 places a bet on outcome 0
        testPlaceBet();

        // Fast forward time to after endTime
        vm.warp(eventContract.endTime() + 1);

        // Creator submits the outcome as outcome 1
        vm.startPrank(creator);
        eventContract.submitOutcome(1);
        vm.stopPrank();

        // User1 creates a dispute
        vm.startPrank(user1);

        uint256 disputeCollateral = (eventContract.totalStaked() * 10) / 100;
        protocolToken.approve(address(eventContract), disputeCollateral);

        eventContract.createDispute("Disagree with outcome");

        vm.stopPrank();

        // Admin resolves the dispute in favor of outcome 0
        vm.startPrank(address(eventManager)); // EventManager calls resolveDispute

        eventContract.resolveDispute(0);

        vm.stopPrank();

        // Check that the winning outcome is updated
        uint256 winningOutcome = eventContract.winningOutcome();
        assertEq(winningOutcome, 0);

        // Check that the dispute status is updated
        uint256 disputeStatus = uint256(eventContract.disputeStatus());
        assertEq(disputeStatus, uint256(Event.DisputeStatus.Resolved));
    }

    function testCancelEvent() public {
        // Fast forward time to before startTime
        vm.warp(eventContract.startTime() - 30 minutes);

        // EventManager cancels the event
        vm.startPrank(address(eventManager));

        eventContract.cancelEvent();

        vm.stopPrank();

        // Check that the event status is updated to Cancelled
        uint256 status = uint256(eventContract.status());
        assertEq(status, uint256(Event.EventStatus.Cancelled));
    }

    function testCancelEventAfterStartTimeShouldFail() public {
        // Fast forward time to after startTime
        vm.warp(eventContract.startTime() + 1);

        // EventManager tries to cancel the event
        vm.startPrank(address(eventManager));

        vm.expectRevert("Cannot cancel after event start time");
        eventContract.cancelEvent();

        vm.stopPrank();
    }

    function testWithdrawBet() public {
        // User1 places a bet
        testPlaceBet();

        // Cancel the event
        vm.warp(eventContract.startTime() - 30 minutes);
        vm.startPrank(address(eventManager));
        eventContract.cancelEvent();
        vm.stopPrank();

        // User1 withdraws their bet
        vm.startPrank(user1);

        uint256 initialBalance = protocolToken.balanceOf(user1);
        eventContract.withdrawBet(0);
        uint256 finalBalance = protocolToken.balanceOf(user1);

        vm.stopPrank();

        // Check that user1 received their bet back
        assertEq(finalBalance - initialBalance, 50 ether);
    }

    function testWithdrawBetWhenEventNotCancelledShouldFail() public {
        // User1 places a bet
        testPlaceBet();

        // User1 tries to withdraw their bet
        vm.startPrank(user1);

        vm.expectRevert("Invalid event status");
        eventContract.withdrawBet(0);

        vm.stopPrank();
    }

    function testUserCannotBetMoreThanTenPercent() public {
        vm.warp(eventContract.startTime() - 10);
        uint256 bettingLimit = eventContract.bettingLimit();
        uint256 userMaxBet = bettingLimit / 10;

        vm.startPrank(user1);
        protocolToken.approve(address(eventContract), userMaxBet + 1 ether);

        // User tries to bet exactly 10% of the betting limit
        eventContract.placeBet(0, userMaxBet);

        // User tries to bet an additional amount, exceeding 10%
        vm.expectRevert("Bet amount exceeds user limit");
        eventContract.placeBet(0, 1 ether);

        vm.stopPrank();
    }
}
