// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/EventFactory.sol";
import "../contracts/Event.sol";
import "../contracts/CollateralManager.sol";
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

contract EventFactoryTest is Test {
    EventFactory public eventFactory;
    CollateralManager public collateralManager;
    Governance public governance;
    MockERC20 public bettingToken;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    string[] public outcomes;

    function setUp() public {
        outcomes = new string[](2);
        owner = address(this);

        user1 = vm.addr(1);
        user2 = vm.addr(2);

        // Deploy MockERC20 token
        bettingToken = new MockERC20("Betting Token", "BET", 18);

        // Distribute tokens to users
        bettingToken.mint(user1, 10_000 ether);
        bettingToken.mint(user2, 10_000 ether);

        // Deploy Governance contract
        governance = new Governance(owner);

        // Deploy CollateralManager contract
        collateralManager = new CollateralManager(address(bettingToken), address(governance), user3);

        // Deploy EventFactory contract
        eventFactory = new EventFactory(address(collateralManager), address(governance));

        // Set bettingToken in EventFactory (Assuming you have a setter function)
        eventFactory.setBettingToken(address(bettingToken));
    }

    function testDeployment() public {
        assertEq(eventFactory.collateralManager(), address(collateralManager));
    }

    function testCreateEvent() public {
        vm.startPrank(user1);

        // Parameters for the event
        string memory title = "Test Event";
        string memory description = "This is a test event";
        string memory category = "Sports";
        outcomes[0] = "Team A";
        outcomes[1] = "Team B";
        uint256 startTime = block.timestamp + 60; // Starts in 1 minute
        uint256 endTime = block.timestamp + 3600; // Ends in 1 hour
        uint256 collateralAmount = 100 ether; // 100 BET

        // Approve the CollateralManager to spend user1's BET tokens
        bettingToken.approve(address(collateralManager), collateralAmount);

        // Create the event
        (address eventAddress, uint256 eventId) =
            eventFactory.createEvent(title, description, category, outcomes, startTime, endTime, collateralAmount);

        vm.stopPrank();

        // Verify the event is stored in allEvents
        address storedEventAddress = eventFactory.allEvents(0);
        assertEq(storedEventAddress, eventAddress);

        // Verify the collateral is locked in CollateralManager
        uint256 collateralBalance = collateralManager.collateralBalances(eventAddress);
        assertEq(collateralBalance, collateralAmount);

        // Verify the event has the correct creator
        Event eventContract = Event(eventAddress);
        assertEq(eventContract.creator(), user1);
    }

    function testCreateEventWithoutApprovalShouldFail() public {
        vm.startPrank(user1);

        // Parameters for the event
        string memory title = "Test Event";
        string memory description = "This is a test event";
        string memory category = "Sports";
        outcomes[0] = "Team A";
        outcomes[1] = "Team B";
        uint256 startTime = block.timestamp + 60; // Starts in 1 minute
        uint256 endTime = block.timestamp + 3600; // Ends in 1 hour
        uint256 collateralAmount = 100 ether; // 100 BET

        // Do not approve the CollateralManager

        // Expect revert due to transfer amount exceeding allowance
        // vm.expectRevert("IERC20: insufficient allowance");
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, collateralManager, 0, collateralAmount
            )
        );
        eventFactory.createEvent(title, description, category, outcomes, startTime, endTime, collateralAmount);

        vm.stopPrank();
    }

    function testGetAllOpenEvents() public {
        vm.startPrank(user1);

        // Create multiple events
        for (uint256 i = 0; i < 3; i++) {
            // Parameters for the event
            string memory title = string(abi.encodePacked("Test Event ", vm.toString(i)));
            string memory description = "This is a test event";
            string memory category = "Sports";
            outcomes[0] = "Team A";
            outcomes[1] = "Team B";
            uint256 startTime = block.timestamp + 60; // Starts in 1 minute
            uint256 endTime = block.timestamp + 3600; // Ends in 1 hour
            uint256 collateralAmount = 100 ether; // 100 BET

            // Approve the CollateralManager to spend user1's BET tokens
            bettingToken.approve(address(collateralManager), collateralAmount);

            // Create the event
            eventFactory.createEvent(title, description, category, outcomes, startTime, endTime, collateralAmount);
        }

        vm.stopPrank();

        // Get all open events
        address[] memory openEvents = eventFactory.getAllOpenEvents();

        // Expect 3 open events
        assertEq(openEvents.length, 3);
    }

    function testGetEventById() public {
        vm.startPrank(user1);

        // Parameters for the event
        string memory title = "Test Event";
        string memory description = "This is a test event";
        string memory category = "Sports";
        outcomes[0] = "Team A";
        outcomes[1] = "Team B";
        uint256 startTime = block.timestamp + 60; // Starts in 1 minute
        uint256 endTime = block.timestamp + 3600; // Ends in 1 hour
        uint256 collateralAmount = 100 ether; // 100 BET

        // Approve the CollateralManager to spend user1's BET tokens
        bettingToken.approve(address(collateralManager), collateralAmount);

        // Create the event
        (address eventAddress, uint256 eventId) =
            eventFactory.createEvent(title, description, category, outcomes, startTime, endTime, collateralAmount);

        vm.stopPrank();

        // Retrieve the event address by ID
        address fetchedEventAddress = eventFactory.getEvent(eventId);

        assertEq(fetchedEventAddress, eventAddress);

        // Expect revert when querying invalid event ID
        vm.expectRevert("Invalid event ID");
        eventFactory.getEvent(999);
    }
}
