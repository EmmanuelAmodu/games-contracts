// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/CollateralManager.sol";
import "../contracts/Governance.sol";
import "../contracts/Event.sol";
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

contract MockEvent is Event {
    constructor(
        string memory _title,
        string memory _description,
        string memory _category,
        string[] memory _outcomes,
        uint256 _startTime,
        uint256 _endTime,
        address _creator,
        uint256 _collateralAmount,
        address _collateralManager,
        address _bettingToken
    )
        Event(
            0,
            _title,
            _description,
            _category,
            _outcomes,
            _startTime,
            _endTime,
            _creator,
            _collateralAmount,
            _collateralManager,
            _bettingToken
        )
    {}

    function setStatusResolved() external {
        status = EventStatus.Resolved;
        disputeDeadline = block.timestamp + 1 hours;
    }

    function setStatusDisputed() external {
        require(status == EventStatus.Resolved, "Event: Event must be resolved first");
        disputeStatus = DisputeStatus.Disputed;
    }
}

contract CollateralManagerTest is Test {
    CollateralManager public collateralManager;
    Governance public governance;
    MockERC20 public collateralToken;
    MockEvent public eventContract;

    address public owner;
    address public admin1;
    address public user1;
    address public user2;
    address public protocolFeeRecipient;
    string[] public outcomes;

    function setUp() public {
        owner = vm.addr(1);
        admin1 = vm.addr(2);
        user1 = vm.addr(3);
        user2 = vm.addr(4);
        protocolFeeRecipient = vm.addr(5);
        outcomes = new string[](2);

        // Deploy MockERC20 token
        collateralToken = new MockERC20("CollateralToken", "CTK", 18);

        // Distribute tokens to users
        collateralToken.mint(user1, 10_000 ether);
        collateralToken.mint(user2, 10_000 ether);

        // Deploy Governance contract and add an admin
        vm.startPrank(owner);
        governance = new Governance(owner);
        governance.addAdmin(admin1);
        vm.stopPrank();

        // Deploy CollateralManager contract
        collateralManager = new CollateralManager(address(collateralToken), address(governance), protocolFeeRecipient);

        // For testing purposes, we'll deploy an Event contract
        // Event constructor parameters:
        // (title, description, category, outcomes, startTime, endTime, creator, collateralAmount, collateralManager, bettingToken)
        string memory title = "Test Event";
        string memory description = "This is a test event";
        string memory category = "Sports";
        outcomes[0] = "Team A";
        outcomes[1] = "Team B";
        uint256 startTime = block.timestamp + 60; // Starts in 1 minute
        uint256 endTime = block.timestamp + 3600; // Ends in 1 hour
        uint256 collateralAmount = 100 ether; // 100 CTK

        eventContract = new MockEvent(
            title,
            description,
            category,
            outcomes,
            startTime,
            endTime,
            user1,
            collateralAmount,
            address(collateralManager),
            address(collateralToken)
        );
    }

    function testLockCollateral() public {
        // User1 will lock collateral for the event
        vm.startPrank(user1);

        // Approve CollateralManager to spend user1's tokens
        collateralToken.approve(address(collateralManager), 100 ether);

        // Call lockCollateral
        collateralManager.lockCollateral(address(eventContract), user1, 100 ether);

        vm.stopPrank();

        // Check that collateral is locked
        uint256 lockedAmount = collateralManager.collateralBalances(address(eventContract));
        assertEq(lockedAmount, 100 ether);

        bool isLocked = collateralManager.isCollateralLocked(address(eventContract));
        assertTrue(isLocked);
    }

    function testLockCollateralWithoutApprovalShouldFail() public {
        // User1 tries to lock collateral without approving the CollateralManager
        vm.startPrank(user1);

        // Expect revert due to insufficient allowance
        // vm.expectRevert("ERC20: insufficient allowance");
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, collateralManager, 0, 100 ether)
        );
        collateralManager.lockCollateral(address(eventContract), user1, 100 ether);

        vm.stopPrank();
    }

    function testIncreaseCollateral() public {
        // First, lock collateral
        testLockCollateral();

        // User1 increases collateral
        uint256 additionalAmount = 50 ether;
        vm.startPrank(user1);

        // Approve CollateralManager to spend additional tokens
        collateralToken.approve(address(collateralManager), additionalAmount);

        // Call increaseCollateral
        collateralManager.increaseCollateral(address(eventContract), additionalAmount);

        vm.stopPrank();

        // Check that collateral is increased
        uint256 lockedAmount = collateralManager.collateralBalances(address(eventContract));
        assertEq(lockedAmount, 150 ether);
    }

    function testClaimCollateral() public {
        // User1 locks collateral
        testLockCollateral();

        // Simulate event resolution
        vm.startPrank(user1);

        // Simulate event being resolved
        eventContract.setStatusResolved();

        // Fast forward time to after disputeDeadline
        vm.warp(block.timestamp + 2 hours);

        // Attempt to claim collateral
        uint256 initialBalance = collateralToken.balanceOf(user1);

        collateralManager.claimCollateral(address(eventContract));

        vm.stopPrank();

        // Check that collateral has been released to user1
        uint256 finalBalance = collateralToken.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 100 ether);

        // Check that collateral balance is zero
        uint256 lockedAmount = collateralManager.collateralBalances(address(eventContract));
        assertEq(lockedAmount, 0);

        bool isLocked = collateralManager.isCollateralLocked(address(eventContract));
        assertFalse(isLocked);
    }

    function testClaimCollateralBeforeDisputeDeadlineShouldFail() public {
        // User1 locks collateral
        testLockCollateral();

        // Simulate event resolution
        vm.startPrank(user1);

        // Simulate event being resolved
        eventContract.setStatusResolved();

        // Attempt to claim collateral before disputeDeadline
        vm.expectRevert("Dispute period not over");
        collateralManager.claimCollateral(address(eventContract));

        vm.stopPrank();
    }

    function testCancelEvent() public {
        // User1 locks collateral
        testLockCollateral();

        // User1 cancels the event
        vm.startPrank(user1);

        collateralManager.cancelEvent(address(eventContract));

        vm.stopPrank();

        // Check that collateral has been released to user1
        uint256 userBalance = collateralToken.balanceOf(user1);
        assertEq(userBalance, 10_000 ether); // Since collateral has been returned

        // Check that collateral balance is zero
        uint256 lockedAmount = collateralManager.collateralBalances(address(eventContract));
        assertEq(lockedAmount, 0);

        bool isLocked = collateralManager.isCollateralLocked(address(eventContract));
        assertFalse(isLocked);
    }

    function testResolveDispute() public {
        // User1 locks collateral
        testLockCollateral();

        // Simulate the event being resolved
        vm.startPrank(user1);
        eventContract.setStatusResolved();
        vm.stopPrank();

        // Simulate a dispute being raised
        eventContract.setStatusDisputed();

        // Fast forward time to after the event's endTime
        uint256 eventEndTime = eventContract.endTime();
        vm.warp(eventEndTime + 1); // Advance time to just after endTime

        // Admin1 resolves the dispute
        vm.startPrank(admin1);

        // Assert dispute status before resolving
        uint256 disputeStatusBefore = uint256(eventContract.disputeStatus());
        assertEq(disputeStatusBefore, uint256(Event.DisputeStatus.Disputed));

        collateralManager.resolveDispute(address(eventContract), 0);

        vm.stopPrank();

        // Assert dispute status after resolving
        uint256 disputeStatusAfter = uint256(eventContract.disputeStatus());
        assertEq(disputeStatusAfter, uint256(Event.DisputeStatus.Resolved));

        // Check that collateral has been released
        uint256 collateralBalance = collateralManager.collateralBalances(address(eventContract));
        assertEq(collateralBalance, 0);

        bool isLocked = collateralManager.isCollateralLocked(address(eventContract));
        assertFalse(isLocked);
    }

    function testSetBettingMultiplier() public {
        vm.startPrank(owner);

        collateralManager.setBettingMultiplier(10);

        vm.stopPrank();

        uint256 multiplier = collateralManager.bettingMultiplier();
        assertEq(multiplier, 10);
    }

    function testSetBettingMultiplierByNonOwnerShouldFail() public {
        vm.startPrank(user1);

        vm.expectRevert("CollateralManager: Only owner can call");
        collateralManager.setBettingMultiplier(10);

        vm.stopPrank();
    }

    function testSetProtocolFeeRecipient() public {
        vm.startPrank(owner);

        address newRecipient = vm.addr(6);
        collateralManager.setProtocolFeeRecipient(newRecipient);

        vm.stopPrank();

        address recipient = collateralManager.protocolFeeRecipient();
        assertEq(recipient, newRecipient);
    }

    function testTransferGovernance() public {
        vm.startPrank(owner);

        address newGovernance = vm.addr(7);
        collateralManager.transferGovernance(newGovernance);

        vm.stopPrank();

        Governance governanceAddress = collateralManager.governance();
        assertEq(address(governanceAddress), newGovernance);
    }

    function testOnlyEventCreatorModifiers() public {
        // User2 tries to call functions that are only for event creator
        vm.startPrank(user2);

        vm.expectRevert("CollateralManager: Only event creator can call");
        collateralManager.cancelEvent(address(eventContract));

        vm.stopPrank();
    }
}
