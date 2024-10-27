// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/EventManager.sol";
import "../contracts/Event.sol";
import "../contracts/Governance.sol";
import "../contracts/StackBets.sol";
import "../contracts/interfaces/IPepperBaseTokenV1.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockPepperBaseTokenV1 is ERC20, IPepperBaseTokenV1 {
    constructor() ERC20("Mock Pepper Token", "MPT") {
        _mint(msg.sender, 1e24); // Mint tokens to the deployer
    }

    function totalSupply() public view override(ERC20, IPepperBaseTokenV1) returns (uint256) {
        return super.totalSupply();
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override(IPepperBaseTokenV1) {
        _burn(msg.sender, amount);
    }
}

contract EventManagerTest is Test {
    EventManager public eventManager;
    MockPepperBaseTokenV1 public protocolToken;
    Governance public governance;
    StackBets public stackBets;

    address public owner = address(0x1);
    address public protocolFeeRecipient = address(0x2);
    address public creator = address(0x3);
    address public user = address(0x4);
    address public admin = address(0x5);

    string[] public outcomes = ["Team A wins", "Team B wins"];

    function setUp() public {
        // Deploy the mock token and contracts
        vm.startPrank(owner);
        protocolToken = new MockPepperBaseTokenV1();
        governance = new Governance(owner);
        eventManager = new EventManager(address(protocolToken), address(governance), protocolFeeRecipient);
        stackBets = new StackBets(owner, address(eventManager), address(protocolToken));
        eventManager.setStackBets(address(stackBets));
        vm.stopPrank();

        // Mint tokens to the creator and user
        protocolToken.mint(creator, 1e24);
        protocolToken.mint(user, 1e24);

        // Approve the EventManager to spend tokens
        vm.prank(creator);
        protocolToken.approve(address(eventManager), type(uint256).max);

        vm.prank(user);
        protocolToken.approve(address(eventManager), type(uint256).max);

        // Add admin to governance
        vm.prank(owner);
        governance.addAdmin(admin);
    }

    function testCreateEvent() public {
        // Creator creates an event
        vm.prank(creator);
        uint256 startTime = block.timestamp + 3 hours;
        uint256 endTime = block.timestamp + 5 hours;

        (address eventAddress, uint256 eventId) = eventManager.createEvent(
            "Match A vs B",
            "Exciting match between A and B",
            "Sports",
            outcomes,
            startTime,
            endTime
        );

        assertTrue(eventAddress != address(0), "Event address should not be zero");
        assertEq(eventId, 0, "Event ID should be zero");

        // Check that the event is stored correctly
        address storedEventAddress = eventManager.getEvent(eventId);
        assertEq(eventAddress, storedEventAddress, "Stored event address should match");

        // Check that the collateral was locked
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);

        // Compute expected collateral amount based on creator's reputation
        vm.prank(creator);
        uint256 expectedCollateral = eventManager.computeCollateralAmount();

        assertEq(collateralBalance, expectedCollateral, "Collateral balance should match expected amount");
    }

    function testCannotCreateEventWithLowReputation() public {
        // Decrease creator's reputation below the threshold
        vm.prank(owner);
        eventManager.decreaseCreatorsReputation(creator, 100); // Assuming initial reputation is 1

        // Attempt to create an event
        vm.prank(creator);
        uint256 startTime = block.timestamp + 3 hours;
        uint256 endTime = block.timestamp + 5 hours;

        vm.expectRevert("Creator can not create events due to low reputation");
        eventManager.createEvent(
            "Match A vs B",
            "Exciting match between A and B",
            "Sports",
            outcomes,
            startTime,
            endTime
        );
    }

    function testClaimCollateral() public {
        // Creator creates an event
        vm.prank(creator);
        uint256 startTime = block.timestamp + 3 hours;
        uint256 endTime = block.timestamp + 5 hours;

        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Exciting match between A and B",
            "Sports",
            outcomes,
            startTime,
            endTime
        );

        Event eventContract = Event(eventAddress);

        // Fast forward to after the event end time
        vm.warp(endTime + 1);

        // Creator submits the outcome
        vm.prank(creator);
        eventContract.submitOutcome(0);

        // Wait for dispute period to end
        vm.warp(block.timestamp + 2 hours);

        // Creator claims collateral
        vm.prank(creator);
        eventManager.claimCollateral(eventAddress);

        // Collateral balance should be zero
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0, "Collateral balance should be zero after claiming");

        // Creator's balance should reflect the returned collateral
        uint256 creatorBalance = protocolToken.balanceOf(creator);
        uint256 expectedBalance = 1e24; // Since collateral is returned
        assertEq(creatorBalance, expectedBalance, "Creator's balance should reflect returned collateral");
    }

    function testCancelEvent() public {
        // Creator creates an event
        vm.prank(creator);
        uint256 startTime = block.timestamp + 3 hours;
        uint256 endTime = block.timestamp + 5 hours;

        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Exciting match between A and B",
            "Sports",
            outcomes,
            startTime,
            endTime
        );

        // Creator cancels the event
        vm.prank(creator);
        eventManager.cancelEvent(eventAddress);

        // Collateral should be released back to the creator
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0, "Collateral balance should be zero after cancellation");

        // Verify the event status
        Event eventContract = Event(eventAddress);
        assertEq(uint256(eventContract.status()), uint256(Event.EventStatus.Cancelled), "Event status should be Cancelled");
    }

    function testResolveDisputeOutcomeChanged() public {
        // Creator creates an event
        vm.prank(creator);
        uint256 startTime = block.timestamp + 3 hours;
        uint256 endTime = block.timestamp + 5 hours;

        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Exciting match between A and B",
            "Sports",
            outcomes,
            startTime,
            endTime
        );

        Event eventContract = Event(eventAddress);

        // User places a bet
        vm.startPrank(user);
        protocolToken.approve(eventAddress, 100e18);
        eventContract.placeBet(1, 100e18);
        vm.stopPrank();

        // Fast forward to after the event end time
        vm.warp(endTime + 1);

        // Creator submits the wrong outcome
        vm.prank(creator);
        eventContract.submitOutcome(0);

        // User contributes to dispute
        vm.startPrank(user);
        protocolToken.approve(eventAddress, 50e18);
        eventContract.contributeToDispute("Wrong outcome submitted", 50e18);
        vm.stopPrank();

        // Admin resolves the dispute, changing the outcome
        vm.prank(admin);
        eventManager.resolveDispute(eventAddress, 1);

        // Collateral should be forfeited
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0, "Collateral should be forfeited after dispute resolution");

        // Creator's reputation should decrease
        int256 creatorReputation = eventManager.creatorsReputation(creator);
        assertLt(creatorReputation, 1, "Creator's reputation should decrease");

        // User can claim forfeited collateral
        vm.prank(user);
        eventManager.claimForfeitedCollateral(eventAddress);

        // Verify user's balance increased
        uint256 userBalance = protocolToken.balanceOf(user);
        assertGt(userBalance, 1e24, "User's balance should increase due to forfeited collateral");
    }

    function testCollectUnclaimedCollateral() public {
        uint256 startTime = block.timestamp + 3 hours;
        uint256 endTime = block.timestamp + 5 hours;

        vm.prank(creator);
        (address eventAddress, ) = eventManager.createEvent(
            "Match A vs B",
            "Exciting match between A and B",
            "Sports",
            outcomes,
            startTime,
            endTime
        );

        Event eventContract = Event(eventAddress);

        // User places a bet
        vm.prank(user);
        protocolToken.approve(eventAddress, 100e18);

        vm.prank(user);
        eventContract.placeBet(1, 100e18);

        // Fast forward to after the event end time
        vm.warp(endTime + 1);

        // Creator submits the wrong outcome
        vm.prank(creator);
        eventContract.submitOutcome(0); // Incorrect outcome

        // User contributes to dispute
        vm.prank(user);
        protocolToken.approve(eventAddress, 50e18);

        vm.prank(user);
        eventContract.contributeToDispute("Wrong outcome submitted", 50e18);

        // Admin resolves the dispute, changing the outcome
        vm.prank(admin);
        eventManager.resolveDispute(eventAddress, 1); // Correct outcome

        // Fast forward past the dispute refund deadline + 30 days
        vm.warp(block.timestamp + 31 days);

        // Owner collects unclaimed collateral
        vm.prank(owner);
        eventManager.collectUnclaimedCollateral(eventAddress);

        // Forfeited collateral amount should be zero
        uint256 forfeitedAmount = eventManager.forfeitedCollateralAmounts(eventAddress);
        assertEq(forfeitedAmount, 0, "Forfeited collateral should be zero after collection");

        // Verify that the protocol fee recipient received the unclaimed collateral
        uint256 protocolFeeRecipientBalance = protocolToken.balanceOf(protocolFeeRecipient);
        assertGt(protocolFeeRecipientBalance, 0, "Protocol fee recipient should have received unclaimed collateral");
    }

    function testAdministrativeFunctions() public {
        // Test setting protocol fee recipient
        address newRecipient = address(0x6);
        vm.prank(owner);
        eventManager.setProtocolFeeRecipient(newRecipient);
        assertEq(eventManager.protocolFeeRecipient(), newRecipient, "Protocol fee recipient should be updated");

        // Test transferring governance
        address newGovernance = address(0x7);
        vm.prank(owner);
        eventManager.transferGovernance(newGovernance);
        assertEq(address(eventManager.governance()), newGovernance, "Governance address should be updated");
    }

    function testReputationManagement() public {
        // Increase reputation
        vm.prank(owner);
        eventManager.increaseCreatorsReputation(creator, 10);
        int256 increasedReputation = eventManager.creatorsReputation(creator);

        // Expected reputation is 1 (initialized) + 10 (increase)
        int256 expectedReputationAfterIncrease = 1 + 10;
        assertEq(increasedReputation, expectedReputationAfterIncrease, "Reputation should increase correctly");

        // Decrease reputation
        vm.prank(owner);
        eventManager.decreaseCreatorsReputation(creator, 5);
        int256 decreasedReputation = eventManager.creatorsReputation(creator);

        // Expected reputation is previous reputation - 5
        int256 expectedReputationAfterDecrease = increasedReputation - 5;
        assertEq(decreasedReputation, expectedReputationAfterDecrease, "Reputation should decrease correctly");
    }

    function testChangeReputationThreshold() public {
        int256 newThreshold = -20;
        vm.prank(owner);
        eventManager.changeReputationThreshold(newThreshold);
        assertEq(eventManager.reputationThreshold(), newThreshold, "Reputation threshold should be updated");
    }

    function testSetMaxCollateral() public {
        uint256 newMaxCollateral = 2e23;
        vm.prank(owner);
        eventManager.setMaxCollateral(newMaxCollateral);
        assertEq(eventManager.maxCollateral(), newMaxCollateral, "Max collateral should be updated");
    }

    function testComputeCollateralAmount() public {
        // Creator's reputation is initialized to 1
        vm.prank(creator);
        uint256 collateralAmount = eventManager.computeCollateralAmount();

        // Expected collateral calculation
        uint256 maxCollateral = eventManager.maxCollateral();
        int256 reputation = eventManager.creatorsReputation(creator);
        uint256 MAX_REPUTATION = eventManager.MAX_REPUTATION();

        int256 collateralDiscount = int256(maxCollateral) * reputation / int256(MAX_REPUTATION);
        int256 calculatedCollateral = int256(maxCollateral) - collateralDiscount;

        uint256 expectedCollateral = calculatedCollateral >= 0 ? uint256(calculatedCollateral) : 0;
        uint256 minimumCollateral = 1e18;
        if (expectedCollateral < minimumCollateral) {
            expectedCollateral = minimumCollateral;
        }

        assertEq(collateralAmount, expectedCollateral, "Computed collateral amount should match expected value");
    }
}
