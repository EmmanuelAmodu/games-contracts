// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/StackBets.sol";
import "../contracts/EventManager.sol";
import "../contracts/Event.sol";

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

contract StackBetsTest is Test {
    MockPepperBaseTokenV1 token;
    EventManager eventManager;
    StackBets stackBets;

    address owner = address(0x1);
    address user = address(0x2);
    address otherUser = address(0x3);
    address governance = address(0x4);
    address creator = address(0x5);
    address protocolFeeRecipient = address(0x5);
    string[] outcomes;
    uint256[] outcomeIndexes;
    address[] eventAddresses;
    Event event1;
    Event event2;
    Event event3;

    function setUp() public {
        // Deploy mock token and mint tokens to users
        token = new MockPepperBaseTokenV1();
        token.mint(user, 1000 ether);
        token.mint(otherUser, 1000 ether);

        outcomes.push("Outcome A");
        outcomes.push("Outcome B");

        // Deploy event manager
        eventManager = new EventManager(address(token), governance, protocolFeeRecipient);

        event1 = new Event(
          0,  //string[] memory _outcomes,
          'Event Title', // string memory _title,
          'Event description',  //string memory _description,
          'Event Category',  //string memory _category,
          outcomes,  //string[] memory _outcomes,
          block.timestamp + 3 hours, // uint256 _startTime,
          block.timestamp + 4 hours, // uint256 _endTime,
          creator,
          address(eventManager),
          address(token)
        );

        event2 = new Event(
          1,  //string[] memory _outcomes,
          'Event Title', // string memory _title,
          'Event description',  //string memory _description,
          'Event Category',  //string memory _category,
          outcomes,  //string[] memory _outcomes,
          block.timestamp + 7 hours, // uint256 _startTime,
          block.timestamp + 8 hours, // uint256 _endTime,
          creator,
          address(eventManager),
          address(token)
        );

        event3 = new Event(
          1,  //string[] memory _outcomes,
          'Event Title', // string memory _title,
          'Event description',  //string memory _description,
          'Event Category',  //string memory _category,
          outcomes,  //string[] memory _outcomes,
          block.timestamp + 10 hours, // uint256 _startTime,
          block.timestamp + 12 hours, // uint256 _endTime,
          creator,
          address(eventManager),
          address(token)
        );

        // Deploy StackBets contract
        vm.prank(owner);
        stackBets = new StackBets(owner, address(eventManager), address(token));

        // Users approve StackBets contract to spend their tokens
        vm.prank(user);
        token.approve(address(stackBets), 1000 ether);

        vm.prank(otherUser);
        token.approve(address(stackBets), 1000 ether);
    }

    function testCreateBetSequence() public {
        // Approve events in StackBets contract
        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event1));

        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event2));

        // Prepare bet sequence data
        eventAddresses.push(address(event1));
        eventAddresses.push(address(event2));

        outcomeIndexes.push(0);
        outcomeIndexes.push(1);

        uint256 amount = 100 ether;

        // User creates a bet sequence
        vm.prank(user);
        uint256 sequenceId = stackBets.createBetSequence(eventAddresses, outcomeIndexes, amount);

        // Verify bet sequence data
        vm.prank(user);
        StackBets.BetSequence memory sequence = stackBets.getUserOneBetSequences(sequenceId);
        assertEq(sequence.active, true);
        assertEq(sequence.betAmounts[0], amount);
        assertEq(sequence.currentIndex, 1); // After placing the first bet, currentIndex is incremented

        // Verify that the bet was placed on event1
        uint256 userBetAmount = event1.userBets(address(stackBets), 0);
        assertEq(userBetAmount, amount);
    }

    function testNotifyOutcomeUserWins() public {
        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event1));

        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event2));

        // Prepare bet sequence data
        eventAddresses.push(address(event1));
        eventAddresses.push(address(event2));

        outcomeIndexes.push(0);
        outcomeIndexes.push(1);

        uint256 amount = 100 ether;

        // User creates a bet sequence
        vm.prank(user);
        uint256 sequenceId = stackBets.createBetSequence(eventAddresses, outcomeIndexes, amount);

        // Close event1 with Outcome A as the winner
        vm.warp(event1.endTime() + 1);
        vm.prank(creator);
        event1.submitOutcome(0);

        vm.warp(event1.disputeDeadline() + 1);
        vm.prank(address(eventManager));
        event1.closeEvent();

        // Notify StackBets of the event outcome
        vm.prank(address(eventManager));
        stackBets.notifyOutcome(address(event1));

        // Verify that the user's sequence progressed to event2
        vm.prank(user);
        StackBets.BetSequence memory sequence = stackBets.getUserOneBetSequences(sequenceId);
        // Since all bets have been placed, sequence.active should be false
        assertEq(sequence.active, false);
        assertEq(sequence.currentIndex, 2); // After placing the second bet

        // Verify that the bet was placed on event2
        uint256 userBetAmount = event2.userBets(address(stackBets), 1);
        assert(userBetAmount > 0);
    }

    function testNotifyOutcomeUserLoses() public {
        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event1));

        eventAddresses.push(address(event1));
        outcomeIndexes.push(0); // Betting on Outcome A

        uint256 amount = 100 ether;

        // User creates a bet sequence
        vm.prank(user);
        uint256 sequenceId = stackBets.createBetSequence(eventAddresses, outcomeIndexes, amount);

        // Close event1 with Outcome A as the winner
        vm.warp(event1.endTime() + 1);
        vm.prank(creator);
        event1.submitOutcome(0);

        vm.warp(event1.disputeDeadline() + 1);
        vm.prank(address(eventManager));
        event1.closeEvent();

        // Notify StackBets of the event outcome
        vm.prank(address(eventManager));
        stackBets.notifyOutcome(address(event1));

        // Verify that the user's sequence is inactive
        vm.prank(user);
        StackBets.BetSequence memory sequence = stackBets.getUserOneBetSequences(sequenceId);
        assertEq(sequence.active, false);
        assertEq(sequence.currentIndex, 1); // No further progression
    }

    function testCollectWinnings() public {
        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event1));

        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event2));

        // Prepare bet sequence data
        eventAddresses.push(address(event1));
        eventAddresses.push(address(event2));

        outcomeIndexes.push(0);
        outcomeIndexes.push(1);

        uint256 amount = 100 ether;

        // User creates a bet sequence
        vm.prank(user);
        uint256 sequenceId = stackBets.createBetSequence(eventAddresses, outcomeIndexes, amount);

        // Close event1 with Outcome A as the winner
        vm.warp(event1.endTime() + 1);
        vm.prank(creator);
        event1.submitOutcome(0);

        vm.warp(event1.disputeDeadline() + 1);
        vm.prank(address(eventManager));
        event1.closeEvent();

        // Notify StackBets of the event outcome
        vm.prank(address(eventManager));
        stackBets.notifyOutcome(address(event1));

        // Close event1 with Outcome A as the winner
        vm.warp(event2.endTime() + 1);
        vm.prank(creator);
        event2.submitOutcome(1);

        vm.warp(event2.disputeDeadline() + 1);
        vm.prank(address(eventManager));
        event2.closeEvent();

        // Notify StackBets of the event outcome
        vm.prank(address(eventManager));
        stackBets.notifyOutcome(address(event2));

        // Verify that the user's sequence is inactive
        vm.prank(user);
        StackBets.BetSequence memory sequence = stackBets.getUserOneBetSequences(sequenceId);
        assertEq(sequence.active, false);

        // User collects winnings
        uint256 userBalanceBefore = token.balanceOf(user);
        vm.prank(user);
        stackBets.collectSequenceWinnings(sequenceId);
        uint256 userBalanceAfter = token.balanceOf(user);

        assert(userBalanceAfter > userBalanceBefore);

        // Verify that winnings are zero after collection
        vm.prank(user);
        StackBets.BetSequence memory updatedSequence = stackBets.getUserOneBetSequences(sequenceId);
        assertEq(updatedSequence.totalWinnings, 0);
    }

    function testEventCancelled() public {
        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event1));

        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event2));

        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event3));

        // Prepare bet sequence data
        eventAddresses.push(address(event1));
        eventAddresses.push(address(event2));
        eventAddresses.push(address(event3));

        outcomeIndexes.push(0);
        outcomeIndexes.push(1);
        outcomeIndexes.push(0);

        uint256 amount = 100 ether;

        // User creates a bet sequence
        vm.prank(user);
        uint256 sequenceId = stackBets.createBetSequence(eventAddresses, outcomeIndexes, amount);

        // Cancel event1
        vm.prank(address(eventManager));
        event1.cancelEvent();

        // Notify StackBets of the event outcome
        vm.prank(address(eventManager));
        stackBets.notifyOutcome(address(event1));

        // Verify that the user's sequence progressed to event2
        vm.prank(user);
        StackBets.BetSequence memory sequence = stackBets.getUserOneBetSequences(sequenceId);
        assertEq(sequence.active, true);
        assertEq(sequence.currentIndex, 2); // After placing the second bet

        // Verify that the bet was placed on event2
        uint256 userBetAmount = event2.userBets(address(stackBets), 1);
        assertEq(userBetAmount, amount);
    }

    function testMultiUserBetSequence() public {
        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event1));

        vm.prank(address(eventManager));
        stackBets.addApprovedEventContract(address(event2));

        // Prepare bet sequence data
        eventAddresses.push(address(event1));
        eventAddresses.push(address(event2));

        outcomeIndexes.push(0);
        outcomeIndexes.push(1);

        uint256 amount = 100 ether;

        // Close event1 with Outcome A as the winner
        vm.warp(event1.endTime() + 1);
        vm.prank(creator);
        event1.submitOutcome(0);

        vm.warp(event1.disputeDeadline() + 1);
        vm.prank(address(eventManager));
        event1.closeEvent();

        // Notify StackBets of the event outcome
        vm.prank(address(eventManager));
        stackBets.notifyOutcome(address(event1));

        // Close event1 with Outcome A as the winner
        vm.warp(event2.endTime() + 1);
        vm.prank(creator);
        event2.submitOutcome(1);

        vm.warp(event2.disputeDeadline() + 1);
        vm.prank(address(eventManager));
        event2.closeEvent();

        // Notify StackBets of the event outcome
        vm.prank(address(eventManager));
        stackBets.notifyOutcome(address(event2));

        // User 1 creates a bet sequence
        vm.prank(user);
        uint256 sequenceId1 = stackBets.createBetSequence(eventAddresses, outcomeIndexes, amount);

        // User 2 creates a bet sequence
        vm.prank(otherUser);
        uint256 sequenceId2 = stackBets.createBetSequence(eventAddresses, outcomeIndexes, amount);

        // Verify that the user's sequence progressed to event2
        vm.prank(user);
        StackBets.BetSequence memory sequence1 = stackBets.getUserOneBetSequences(sequenceId1);
        assertEq(sequence1.currentIndex, 2); // After placing the first bet

        // Verify that the user's sequence progressed to event2
        vm.prank(otherUser);
        StackBets.BetSequence memory sequence2 = stackBets.getUserOneBetSequences(sequenceId2);
        assertEq(sequence2.currentIndex, 2); // After placing the first bet
    }

    function testEmergencyWithdraw() public {
        // Only the owner should be able to call emergencyWithdraw
        uint256 amount = 100 ether;

        // Mint tokens to the StackBets contract
        token.mint(address(stackBets), amount);

        // Attempt to withdraw tokens as non-owner
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        stackBets.emergencyWithdraw(user, amount);

        // Owner withdraws tokens
        vm.prank(owner);
        stackBets.emergencyWithdraw(owner, amount);

        // Verify owner's balance increased
        uint256 ownerBalance = token.balanceOf(owner);
        assertEq(ownerBalance, amount);
    }
}
