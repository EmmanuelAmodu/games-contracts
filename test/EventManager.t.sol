// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/EventManager.sol";
import "../contracts/Event.sol";
import "../contracts/Governance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock contracts
contract MockERC20 is ERC20 {
    uint8 public _decimals;
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract MockGovernance is Governance {
    mapping(address => bool) public approvedAdmins_;

    constructor(address _owner) Governance(_owner) {
        owner = _owner;
    }

    function setOwner(address _owner) public {
        owner = _owner;
    }

    function isApprovedAdmin(address admin) public view returns (bool) {
        return approvedAdmins_[admin];
    }

    function setApprovedAdmin(address admin, bool approved) public {
        approvedAdmins_[admin] = approved;
    }
}

contract EventManagerTest is Test {
    using stdStorage for StdStorage;

    // Contracts
    EventManager public eventManager;
    Event public eventContract;
    MockERC20 public protocolToken;
    MockGovernance public governance;

    // Addresses
    address public protocolFeeRecipient = address(0x1234);
    address public eventCreator = address(0x1);
    address public user = address(0x2);
    address public admin = address(0x3);
    string[] public outcomes;

    // Initial balances
    uint256 public initialCreatorBalance = 1000 ether;
    uint256 public initialUserBalance = 1000 ether;

    function setUp() public {
        outcomes = new string[](2);
        // Deploy mock governance contract
        governance = new MockGovernance(admin);

        // Deploy mock protocol token
        protocolToken = new MockERC20("Protocol Token", "PTK", 18);

        // Mint tokens to event creator and user
        protocolToken.mint(eventCreator, initialCreatorBalance);
        protocolToken.mint(user, initialUserBalance);

        // Deploy EventManager contract
        eventManager = new EventManager(address(protocolToken), address(governance), protocolFeeRecipient);

        // Set up token allowances
        vm.prank(eventCreator);
        protocolToken.approve(address(eventManager), type(uint256).max);

        vm.prank(user);
        protocolToken.approve(address(eventManager), type(uint256).max);
    }

    // Test event creation
    function testCreateEvent() public {
        // Event parameters
        string memory title = "Test Event";
        string memory description = "This is a test event.";
        string memory category = "Sports";
        outcomes[0] = "Team A Wins";
        outcomes[1] = "Team B Wins";
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = block.timestamp + 2 days;
        uint256 collateralAmount = 100 ether;

        // Create event
        vm.prank(eventCreator);
        (address eventAddress, uint256 eventId) = eventManager.createEvent(
            title,
            description,
            category,
            outcomes,
            startTime,
            endTime,
            collateralAmount
        );

        // Assertions
        assertEq(eventManager.getEvent(eventId), eventAddress);
        assertTrue(eventAddress != address(0));

        // Check that collateral is locked
        uint256 lockedCollateral = eventManager.collateralBalances(eventAddress);
        assertEq(lockedCollateral, collateralAmount);

        // Check event creator's balance
        uint256 expectedBalance = initialCreatorBalance - collateralAmount;
        uint256 actualBalance = protocolToken.balanceOf(eventCreator);
        assertEq(actualBalance, expectedBalance);

        // Check that Event contract has correct parameters
        Event newEvent = Event(eventAddress);
        assertEq(newEvent.title(), title);
        assertEq(newEvent.description(), description);
        assertEq(newEvent.category(), category);
        assertEq(newEvent.creator(), eventCreator);
        assertEq(newEvent.collateralAmount(), collateralAmount);
        assertEq(uint(newEvent.status()), uint(Event.EventStatus.Open));
    }

    // Test event creation with invalid parameters
    function testCreateEventWithZeroCollateral() public {
        // Attempt to create event with zero collateral
        string memory title = "Zero Collateral Event";
        string memory description = "Should fail.";
        string memory category = "Test";
        outcomes[0] = "Option 1";
        outcomes[1] = "Option 2";
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = block.timestamp + 2 days;
        uint256 collateralAmount = 0;

        vm.prank(eventCreator);
        vm.expectRevert("Collateral amount must be greater than zero");
        eventManager.createEvent(
            title,
            description,
            category,
            outcomes,
            startTime,
            endTime,
            collateralAmount
        );
    }

    function testCreateEventWithEndTimeBeforeStartTime() public {
        // Attempt to create event with endTime before startTime
        string memory title = "Invalid Time Event";
        string memory description = "Should fail.";
        string memory category = "Test";
        outcomes[0] = "Option 1";
        outcomes[1] = "Option 2";
        uint256 startTime = block.timestamp + 2 days;
        uint256 endTime = block.timestamp + 1 days; // endTime before startTime
        uint256 collateralAmount = 100 ether;

        vm.prank(eventCreator);
        vm.expectRevert("End time must be after start time");
        eventManager.createEvent(
            title,
            description,
            category,
            outcomes,
            startTime,
            endTime,
            collateralAmount
        );
    }

    function testIncreaseCollateral() public {
        // First, create an event
        testCreateEvent();

        // Retrieve the event address
        address eventAddress = eventManager.allEvents(0);
        uint256 additionalCollateral = 50 ether;

        // Increase collateral
        vm.prank(eventCreator);
        eventManager.increaseCollateral(eventAddress, additionalCollateral);

        // Check new collateral balance
        uint256 totalCollateral = eventManager.collateralBalances(eventAddress);
        assertEq(totalCollateral, 100 ether + additionalCollateral);

        // Check event creator's balance
        uint256 expectedBalance = initialCreatorBalance - 100 ether - additionalCollateral;
        uint256 actualBalance = protocolToken.balanceOf(eventCreator);
        assertEq(actualBalance, expectedBalance);
    }

    function testIncreaseCollateralByNonCreator() public {
        // First, create an event
        testCreateEvent();

        // Retrieve the event address
        address eventAddress = eventManager.allEvents(0);
        uint256 additionalCollateral = 50 ether;

        // Attempt to increase collateral as a non-creator
        vm.prank(user);
        vm.expectRevert("CollateralManager: Only event creator can call");
        eventManager.increaseCollateral(eventAddress, additionalCollateral);
    }

    function testClaimCollateralAfterResolved() public {
        // First, create an event
        testCreateEvent();

        // Retrieve the event address
        address eventAddress = eventManager.allEvents(0);
        Event newEvent = Event(eventAddress);

        // Fast forward to endTime
        uint256 endTime = newEvent.endTime();
        vm.warp(endTime + 1);

        // Submit outcome
        vm.prank(eventCreator);
        newEvent.submitOutcome(0); // Assume outcome index 0 is the winning outcome

        // Fast forward dispute period
        uint256 disputeDeadline = newEvent.disputeDeadline();
        vm.warp(disputeDeadline + 1);

        // Claim collateral
        vm.prank(eventCreator);
        eventManager.claimCollateral(eventAddress);

        // Check that collateral is released
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0);

        // Check that collateral is transferred back to creator
        uint256 expectedBalance = initialCreatorBalance - 100 ether + 100 ether;
        uint256 actualBalance = protocolToken.balanceOf(eventCreator);
        assertEq(actualBalance, expectedBalance);

        // Check that event status is Closed
        assertEq(uint(newEvent.status()), uint(Event.EventStatus.Closed));
    }

    function testClaimCollateralBeforeDisputeDeadline() public {
        // First, create an event
        testCreateEvent();

        // Retrieve the event address
        address eventAddress = eventManager.allEvents(0);
        Event newEvent = Event(eventAddress);

        // Fast forward to endTime
        uint256 endTime = newEvent.endTime();
        vm.warp(endTime + 1);

        // Submit outcome
        vm.prank(eventCreator);
        newEvent.submitOutcome(0); // Assume outcome index 0 is the winning outcome

        // Attempt to claim collateral before dispute deadline
        vm.prank(eventCreator);
        vm.expectRevert("Dispute period not over");
        eventManager.claimCollateral(eventAddress);
    }

    function testCancelEvent() public {
        // First, create an event
        testCreateEvent();

        // Retrieve the event address
        address eventAddress = eventManager.allEvents(0);
        Event newEvent = Event(eventAddress);

        // Cancel the event
        vm.prank(eventCreator);
        eventManager.cancelEvent(eventAddress);

        // Check that event status is Cancelled
        assertEq(uint(newEvent.status()), uint(Event.EventStatus.Cancelled));

        // Check that collateral is released
        uint256 collateralBalance = eventManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, 0);

        // Check that collateral is transferred back to creator
        uint256 expectedBalance = initialCreatorBalance - 100 ether + 100 ether;
        uint256 actualBalance = protocolToken.balanceOf(eventCreator);
        assertEq(actualBalance, expectedBalance);
    }

    function testCancelEventAfterStartTime() public {
        // First, create an event
        testCreateEvent();

        // Retrieve the event address
        address eventAddress = eventManager.allEvents(0);
        Event newEvent = Event(eventAddress);

        // Fast forward to startTime
        uint256 startTime = newEvent.startTime();
        vm.warp(startTime + 1);

        // Attempt to cancel the event
        vm.prank(eventCreator);
        vm.expectRevert("Cannot cancel after event start time");
        eventManager.cancelEvent(eventAddress);
    }

    // Additional tests for edge cases and other functions can be added here
}
