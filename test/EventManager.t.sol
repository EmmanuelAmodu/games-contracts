// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/EventManager.sol";
import "../contracts/Event.sol";
import "../contracts/Governance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MTKN") {
        _mint(msg.sender, 1e30); // Mint a large amount to the deployer
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract EventManagerTest is Test {
    MockToken token;
    EventManager eventManager;
    Governance governance;
    Event eventContract;

    address owner = address(0x1);
    address creator = address(0x2);
    address user1 = address(0x3);
    address user2 = address(0x4);
    address protocolFeeRecipient = address(0x5);
    address admin = address(0x6);

    string[] outcomes = ["Team A wins", "Team B wins"];
    uint256 collateralAmount = 1000e18; // 1000 tokens

    function setUp() public {
        // Set msg.sender to owner
        vm.startPrank(owner);

        // Deploy MockToken
        token = new MockToken();

        // Deploy Governance contract and set owner
        governance = new Governance(owner);

        // Deploy EventManager contract
        eventManager = new EventManager(
            address(token),
            address(governance),
            protocolFeeRecipient
        );

        // Approve admin
        governance.addAdmin(admin);

        vm.stopPrank(); // Stop owner prank

        // Mint tokens to creator and users
        token.mint(creator, 1e24);
        token.mint(user1, 1e24);
        token.mint(user2, 1e24);

        // Creator approves EventManager to spend tokens
        vm.startPrank(creator);
        token.approve(address(eventManager), type(uint256).max);
        vm.stopPrank();

        // Users approve EventManager to spend tokens (if needed)
        vm.startPrank(user1);
        token.approve(address(eventManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(eventManager), type(uint256).max);
        vm.stopPrank();
    }

    function testInitialization() public {
        // Test that the EventManager contract is initialized correctly
        assertEq(eventManager.protocolFeeRecipient(), protocolFeeRecipient);
        assertEq(address(eventManager.protocolToken()), address(token));
        assertEq(address(eventManager.governance()), address(governance));
        assertEq(eventManager.bettingMultiplier(), 100);
    }

    function testCreateEvent() public {
        vm.startPrank(creator);

        // Create an event
        (address eventAddress, uint256 eventId) = eventManager.createEvent(
            "Match A vs B",
            "Description",
            "Sports",
            outcomes,
            block.timestamp + 3 hours, // Start time in 3 hours
            block.timestamp + 5 hours, // End time in 5 hours
            collateralAmount
        );

        vm.stopPrank();

        // Verify that the event is created
        address retrievedEventAddress = eventManager.getEvent(eventId);
        assertEq(eventAddress, retrievedEventAddress);

        // Verify that collateral is locked
        uint256 lockedCollateral = eventManager.collateralBalances(eventAddress);
        assertEq(lockedCollateral, collateralAmount);

        // Verify that the event is stored in creatorEvents
        address[] memory creatorEvents = eventManager.getAllCreatorEvents(creator);
        assertEq(creatorEvents[0], eventAddress);

        // Verify that the event is in allEvents
        address[] memory allEvents = eventManager.getAllOpenEvents();
        assertEq(allEvents[0], eventAddress);
    }

    function testCannotCreateEventWithInvalidParameters() public {
        vm.startPrank(creator);

        // Attempt to create an event with invalid collateral amount
        vm.expectRevert("Collateral amount must be greater than zero");
        eventManager.createEvent(
            "Invalid Event",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            0 // Zero collateral
        );

        // Attempt to create an event with start time in the past
        vm.expectRevert("Start time must be at least 2 hours in the future");
        eventManager.createEvent(
            "Invalid Event",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 1 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );

        vm.stopPrank();
    }

    function testIncreaseCollateral() public {
        // First, create an event
        vm.startPrank(creator);

        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Description",
            "Sports",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );

        // Increase collateral
        uint256 additionalCollateral = 500e18; // 500 tokens
        eventManager.increaseCollateral(eventAddress, additionalCollateral);

        vm.stopPrank();

        // Verify that collateral is increased
        uint256 totalCollateral = eventManager.collateralBalances(eventAddress);
        assertEq(totalCollateral, collateralAmount + additionalCollateral);
    }

    function testOnlyCreatorCanIncreaseCollateral() public {
        // First, create an event
        vm.startPrank(creator);

        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Description",
            "Sports",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );

        vm.stopPrank();

        // User1 tries to increase collateral
        vm.startPrank(user1);
        vm.expectRevert("Only event creator can call");
        eventManager.increaseCollateral(eventAddress, 100e18);
        vm.stopPrank();
    }

    function testResolveDisputeOutcomeChanged() public {
        // Setup: Creator creates an event
        vm.startPrank(creator);
        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Description",
            "Sports",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );
        vm.stopPrank();

        // Users interact with the event
        Event resolvedEventContract = Event(eventAddress);

        vm.startPrank(user1);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(0, 100e18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(1, 100e18);
        vm.stopPrank();
    
        vm.warp(block.timestamp + 4 hours); // Move to after event start time

        // Fast forward to after event end time
        vm.warp(resolvedEventContract.endTime() + 1);

        // Creator submits an incorrect outcome
        vm.startPrank(creator);
        resolvedEventContract.submitOutcome(1); // Assume 1 is incorrect
        vm.stopPrank();

        // User1 contributes to dispute
        vm.startPrank(user1);
        resolvedEventContract.contributeToDispute("Incorrect outcome", 100e18);
        vm.stopPrank();

        // Admin resolves the dispute, changing the outcome
        vm.startPrank(owner);
        eventManager.resolveDispute(eventAddress, 0); // Correct outcome is 0
        vm.stopPrank();

        // Verify that the disputeOutcomeChanged is true
        bool outcomeChanged = eventManager.disputeOutcomeChanged(eventAddress);
        assertEq(outcomeChanged, true);

        // Verify that the creator's collateral is forfeited
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0);

        // User1 can claim their share of forfeited collateral
        vm.startPrank(user1);
        eventManager.claimForfeitedCollateral(eventAddress);
        vm.stopPrank();
    }

    function testResolveDisputeOutcomeUpheld() public {
        // Setup: Creator creates an event
        vm.startPrank(creator);
        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Description",
            "Sports",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );
        vm.stopPrank();

        // Fast forward to after event end time
        Event resolvedEventContract = Event(eventAddress);

        vm.startPrank(user1);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(0, 100e18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(1, 100e18);
        vm.stopPrank();

        vm.warp(resolvedEventContract.endTime() + 1);

        // Creator submits the correct outcome
        vm.startPrank(creator);
        resolvedEventContract.submitOutcome(0); // Correct outcome is 0
        vm.stopPrank();

        // User1 contributes to dispute
        vm.startPrank(user1);
        resolvedEventContract.contributeToDispute("Disagree with outcome", 100e18);
        vm.stopPrank();

        // Admin resolves the dispute, upholding the outcome
        vm.startPrank(admin);
        eventManager.resolveDispute(eventAddress, 0); // Outcome remains 0
        vm.stopPrank();

        // Verify that the disputeOutcomeChanged is false
        bool outcomeChanged = eventManager.disputeOutcomeChanged(eventAddress);
        assertEq(outcomeChanged, false);

        // Creator's collateral should still be locked until claimed
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, collateralAmount);

        vm.warp(resolvedEventContract.disputeDeadline() + 1);

        // Creator can claim their collateral
        vm.startPrank(creator);
        eventManager.claimCollateral(eventAddress);
        vm.stopPrank();

        // Collateral should now be zero
        collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0);
    }

    function testOnlyApprovedAdminCanResolveDispute() public {
        // Setup: Creator creates an event and dispute is raised
        vm.startPrank(creator);
        (address eventAddress, ) = eventManager.createEvent(
            "Event with Dispute",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );
        vm.stopPrank();

        // Fast forward to after event end time and submit outcome
        Event resolvedEventContract = Event(eventAddress);

        vm.startPrank(user1);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(0, 100e18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(1, 100e18);
        vm.stopPrank();

        vm.warp(resolvedEventContract.endTime() + 1);

        vm.startPrank(creator);
        resolvedEventContract.submitOutcome(0);
        vm.stopPrank();

        // User1 contributes to dispute
        vm.startPrank(user1);
        resolvedEventContract.contributeToDispute("Dispute", 100e18);
        vm.stopPrank();

        // Unauthorized user tries to resolve dispute
        vm.startPrank(user1);
        vm.expectRevert("Only approved admin can call");
        eventManager.resolveDispute(eventAddress, 1);
        vm.stopPrank();
    }

    function testClaimForfeitedCollateral() public {
        // Setup similar to previous test where outcome changes
        vm.startPrank(creator);
        (address eventAddress, ) = eventManager.createEvent(
            "Event with Forfeited Collateral",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );
        vm.stopPrank();

        Event resolvedEventContract = Event(eventAddress);
        
        vm.startPrank(user1);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(0, 100e18);
        vm.stopPrank();
    
        vm.warp(resolvedEventContract.endTime() + 1);

        vm.startPrank(creator);
        resolvedEventContract.submitOutcome(1); // Incorrect outcome
        vm.stopPrank();

        vm.startPrank(user1);
        resolvedEventContract.contributeToDispute("Incorrect outcome", 100e18);
        vm.stopPrank();

        vm.startPrank(owner);
        eventManager.resolveDispute(eventAddress, 0); // Correct outcome is 0
        vm.stopPrank();

        // User1 claims forfeited collateral
        vm.startPrank(user1);
        eventManager.claimForfeitedCollateral(eventAddress);
        vm.stopPrank();

        // Verify that the user cannot claim again
        vm.startPrank(user1);
        vm.expectRevert("Already claimed");
        eventManager.claimForfeitedCollateral(eventAddress);
        vm.stopPrank();
    }

    function testCollectUnclaimedCollateral() public {
        // Setup where some users do not claim their share
        vm.startPrank(creator);
        (address eventAddress, ) = eventManager.createEvent(
            "Event with Unclaimed Collateral",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );
        vm.stopPrank();

        Event resolvedEventContract = Event(eventAddress);

        vm.startPrank(user1);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(0, 100e18);
        vm.stopPrank();

        vm.warp(resolvedEventContract.endTime() + 1);

        vm.startPrank(creator);
        resolvedEventContract.submitOutcome(1); // Incorrect outcome
        vm.stopPrank();

        vm.startPrank(user1);
        resolvedEventContract.contributeToDispute("Incorrect outcome", 100e18);
        vm.stopPrank();

        vm.startPrank(owner);
        eventManager.resolveDispute(eventAddress, 0); // Correct outcome is 0
        vm.stopPrank();

        // Fast forward 30 days plus dispute deadline
        vm.warp(resolvedEventContract.disputeDeadline() + 31 days);

        // Owner collects unclaimed collateral
        vm.startPrank(owner);
        eventManager.collectUnclaimedCollateral(eventAddress);
        vm.stopPrank();

        // Verify that forfeited collateral amount is zero
        uint256 forfeitedAmount = eventManager.forfeitedCollateralAmounts(eventAddress);
        assertEq(forfeitedAmount, 0);
    }

    function testComputeBetLimit() public {
        // Initialize creator's trust multiplier (should be 0)
        int256 trustMultiplier = eventManager.creatorsTrustMultiplier(creator);
        assertEq(trustMultiplier, 0);

        // Compute bet limit
        uint256 betLimit = eventManager.computeBetLimit(creator, collateralAmount);
        assertEq(betLimit, 100 * collateralAmount); // bettingMultiplier * trustMultiplier * collateralAmount
    }

    function testIncreaseDecreaseTrustMultiplier() public {
        // Owner increases trust multiplier
        vm.startPrank(owner);
        eventManager.increaseCreatorsTrustMultiplier(creator, 2); // New multiplier should be 3
        vm.stopPrank();

        int256 trustMultiplier = eventManager.creatorsTrustMultiplier(creator);
        assertEq(trustMultiplier, 3);

        // Owner decreases trust multiplier
        vm.startPrank(owner);
        eventManager.decreaseCreatorsTrustMultiplier(creator, 4); // New multiplier should be -1
        vm.stopPrank();

        trustMultiplier = eventManager.creatorsTrustMultiplier(creator);
        assertEq(trustMultiplier, -1);

        // Compute bet limit with negative multiplier
        uint256 betLimit = eventManager.computeBetLimit(creator, collateralAmount);
        assertEq(betLimit, collateralAmount / 1); // collateralAmount / abs(trustMultiplier)
    }

    function testOnlyOwnerCanAdjustTrustMultiplier() public {
        vm.startPrank(user1);
        vm.expectRevert("Only owner can call");
        eventManager.increaseCreatorsTrustMultiplier(creator, 1);
        vm.stopPrank();
    }

    function testSetBettingMultiplier() public {
        vm.startPrank(owner);
        eventManager.setBettingMultiplier(200);
        vm.stopPrank();

        uint256 bettingMultiplier = eventManager.bettingMultiplier();
        assertEq(bettingMultiplier, 200);
    }

    function testOnlyOwnerCanSetBettingMultiplier() public {
        vm.startPrank(user1);
        vm.expectRevert("Only owner can call");
        eventManager.setBettingMultiplier(200);
        vm.stopPrank();
    }

    function testNotifyDisputeResolution() public {
        // This function is called by the Event contract; test that it can only be called by authorized address
        vm.startPrank(user1);
        vm.expectRevert("Only event contract can notify");
        eventManager.notifyDisputeResolution(address(0), true);
        vm.stopPrank();
    }

    function testGetAllOpenEvents() public {
        // Create multiple events
        vm.startPrank(creator);

        for (uint256 i = 0; i < 3; i++) {
            eventManager.createEvent(
                string(abi.encodePacked("Event ", Strings.toString(i))),
                "Description",
                "Category",
                outcomes,
                block.timestamp + 3 hours,
                block.timestamp + 5 hours,
                collateralAmount
            );
        }

        vm.stopPrank();

        // Get all open events
        address[] memory openEvents = eventManager.getAllOpenEvents();
        assertEq(openEvents.length, 3);
    }

    function testEventClosureAfterResolutionNoBetOnWinningOutCome() public {
        // Create an event
        vm.startPrank(creator);

        (address eventAddress, ) = eventManager.createEvent(
            "Event to Close",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );

        vm.stopPrank();

        Event resolvedEventContract = Event(eventAddress);
        vm.warp(resolvedEventContract.endTime() + 1);

        // Submit outcome
        vm.startPrank(creator);
        resolvedEventContract.submitOutcome(0);
        vm.stopPrank();

        // Wait for dispute period to end
        vm.warp(resolvedEventContract.disputeDeadline() + 1);

        // Creator claims collateral, which should trigger event closure
        vm.startPrank(creator);
        eventManager.claimCollateral(eventAddress);
        vm.stopPrank();

        // Verify that the event status is Closed
        Event.EventStatus status = resolvedEventContract.status();
        assertEq(uint256(status), uint256(Event.EventStatus.Cancelled));
    }

    function testEventClosureAfterResolution() public {
        // Create an event
        vm.startPrank(creator);

        (address eventAddress, ) = eventManager.createEvent(
            "Event to Close",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );

        vm.stopPrank();

        Event resolvedEventContract = Event(eventAddress);

        vm.startPrank(user1);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(0, 100e18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(eventAddress, type(uint256).max);
        resolvedEventContract.placeBet(1, 100e18);
        vm.stopPrank();

        vm.warp(resolvedEventContract.endTime() + 1);

        // Submit outcome
        vm.startPrank(creator);
        resolvedEventContract.submitOutcome(0);
        vm.stopPrank();

        // Wait for dispute period to end
        vm.warp(resolvedEventContract.disputeDeadline() + 1);

        // Creator claims collateral, which should trigger event closure
        vm.startPrank(creator);
        eventManager.claimCollateral(eventAddress);
        vm.stopPrank();

        // Verify that the event status is Closed
        Event.EventStatus status = resolvedEventContract.status();
        assertEq(uint256(status), uint256(Event.EventStatus.Closed));
    }

    function testCannotCancelEventWithinOneHourOfStart() public {
        // Create an event that starts in 2 hours
        vm.startPrank(creator);

        (address eventAddress, ) = eventManager.createEvent(
            "Event to Cancel",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 2 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );

        vm.stopPrank();

        // Move time to within 1 hour of start time
        vm.warp(block.timestamp + 1 hours + 1 minutes);

        // Attempt to cancel the event
        vm.startPrank(creator);
        vm.expectRevert("Cannot cancel event within 1 hour of start time");
        eventManager.cancelEvent(eventAddress);
        vm.stopPrank();
    }

    function testCancelEvent() public {
        // Create an event that starts in 3 hours
        vm.startPrank(creator);

        (address eventAddress, ) = eventManager.createEvent(
            "Event to Cancel",
            "Description",
            "Category",
            outcomes,
            block.timestamp + 3 hours,
            block.timestamp + 5 hours,
            collateralAmount
        );

        vm.stopPrank();

        // Move time to before 1 hour of start time
        vm.warp(block.timestamp + 1 hours);

        // Cancel the event
        vm.startPrank(creator);
        eventManager.cancelEvent(eventAddress);
        vm.stopPrank();

        // Verify that collateral is released
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0);
    }

    function testTransferGovernance() public {
        vm.startPrank(owner);
        address newGovernance = address(0x7);
        eventManager.transferGovernance(newGovernance);
        vm.stopPrank();

        Governance updatedGovernance = eventManager.governance();
        assertEq(address(updatedGovernance), newGovernance);
    }

    function testOnlyOwnerCanTransferGovernance() public {
        vm.startPrank(user1);
        vm.expectRevert("Only owner can call");
        eventManager.transferGovernance(address(0x7));
        vm.stopPrank();
    }

    function testSetProtocolFeeRecipient() public {
        vm.startPrank(owner);
        address newRecipient = address(0x8);
        eventManager.setProtocolFeeRecipient(newRecipient);
        vm.stopPrank();

        address updatedRecipient = eventManager.protocolFeeRecipient();
        assertEq(updatedRecipient, newRecipient);
    }

    function testOnlyOwnerCanSetProtocolFeeRecipient() public {
        vm.startPrank(user1);
        vm.expectRevert("Only owner can call");
        eventManager.setProtocolFeeRecipient(address(0x8));
        vm.stopPrank();
    }
}
