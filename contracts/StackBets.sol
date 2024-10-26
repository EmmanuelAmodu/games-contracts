// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPepperBaseTokenV1} from "./interfaces/IPepperBaseTokenV1.sol";
import {EventManager} from "./EventManager.sol";
import {Event} from "./Event.sol";

contract StackBets is ReentrancyGuard, Ownable {
    IPepperBaseTokenV1 public protocolToken;
    EventManager public eventManager;

    struct BetSequence {
        address[] eventAddresses;      // Sequence of Event contract addresses
        uint256[] outcomeIndexes;      // Desired outcomes corresponding to each event
        uint256[] betAmounts;          // Bet amounts for each event
        uint256 currentIndex;          // Current position in the sequence
        bool active;                   // Indicates if the sequence is active
        uint256[] skippedIndices;      // Indices of events that were skipped
        uint256 totalWinnings;         // Total winnings accumulated
    }

    struct UserSequence {
        address user;
        uint256 sequenceId;
    }

    // User address => array of their bet sequences
    mapping(address => BetSequence[]) public userBetSequences;

    // Mapping from event address to array of UserSequence
    mapping(address => UserSequence[]) public eventToUserSequences;

    // List of approved Event contracts
    mapping(address => bool) public approvedEventContracts;

    // Modifier to allow only EventManager
    modifier onlyEventManager() {
        require(msg.sender == address(eventManager), "Caller is not the EventManager contract");
        _;
    }

    // Events
    event BetSequenceCreated(address indexed user, uint256 sequenceId);
    event BetPlaced(address indexed user, uint256 sequenceId, address eventAddress, uint256 outcomeIndex, uint256 amount);
    event BetSkipped(address indexed user, uint256 sequenceId, address eventAddress, string reason);
    event BetSequenceEnded(address indexed user, uint256 sequenceId);
    event WinningsCollected(address indexed user, uint256 amount);
    event EmergencyWithdrawal(address to, uint256 amount);
    event EventContractAdded(address eventContract);
    event EventContractRemoved(address eventContract);

    constructor(address initialOwner, address _eventManager, address _protocolToken) Ownable(initialOwner) {
        require(_protocolToken != address(0), "Invalid token address");
        require(_eventManager != address(0), "Invalid EventManager address");
        protocolToken = IPepperBaseTokenV1(_protocolToken);
        eventManager = EventManager(_eventManager);
    }

    /**
     * @notice Adds an approved Event contract.
     * @param eventContract The address of the Event contract to approve.
     */
    function addApprovedEventContract(address eventContract) external onlyEventManager {
        require(eventContract != address(0), "Invalid Event contract address");
        approvedEventContracts[eventContract] = true;
        emit EventContractAdded(eventContract);
    }

    /**
     * @notice Removes an approved Event contract.
     * @param eventContract The address of the Event contract to remove.
     */
    function removeApprovedEventContract(address eventContract) external onlyEventManager {
        require(approvedEventContracts[eventContract], "Event contract not approved");
        delete approvedEventContracts[eventContract];
        emit EventContractRemoved(eventContract);
    }

    /**
     * @notice Creates a new bet sequence and places the initial bet.
     * @param eventAddresses Array of Event contract addresses.
     * @param outcomeIndexes Array of desired outcome indices corresponding to each event.
     * @param amount The initial amount to bet.
     */
    function createBetSequence(
        address[] calldata eventAddresses,
        uint256[] calldata outcomeIndexes,
        uint256 amount
    ) external nonReentrant returns (uint256 sequenceId) {
        require(amount > 0, "Amount must be greater than zero");
        require(eventAddresses.length > 0, "At least one event required");
        require(eventAddresses.length == outcomeIndexes.length, "Mismatched inputs");

        // Transfer tokens from the user to this contract
        protocolToken.transferFrom(msg.sender, address(this), amount);

        // Create a new bet sequence
        BetSequence storage sequence = userBetSequences[msg.sender].push();
        sequence.eventAddresses = eventAddresses;
        sequence.outcomeIndexes = outcomeIndexes;
        sequence.betAmounts = new uint256[](eventAddresses.length);
        sequence.currentIndex = 0;
        sequence.active = true;
        // sequence.skippedIndices is automatically initialized to an empty array
        sequence.totalWinnings = 0;

        sequenceId = userBetSequences[msg.sender].length - 1;

        // Set the initial bet amount
        sequence.betAmounts[sequence.currentIndex] = amount;

        // Place the initial bet
        _attemptNextBet(msg.sender, sequenceId);

        emit BetSequenceCreated(msg.sender, sequenceId);
    }

    /**
     * @notice Internal function to attempt placing the next bet in the sequence.
     * @param user The address of the user.
     * @param sequenceId The ID of the bet sequence.
     */
    function _attemptNextBet(address user, uint256 sequenceId) internal {
        BetSequence storage sequence = userBetSequences[user][sequenceId];

        while (sequence.currentIndex < sequence.eventAddresses.length) {
            address eventAddress = sequence.eventAddresses[sequence.currentIndex];
            uint256 outcomeIndex = sequence.outcomeIndexes[sequence.currentIndex];

            // Check if the event is approved
            if (!approvedEventContracts[eventAddress]) {
                sequence.skippedIndices.push(sequence.currentIndex);
                emit BetSkipped(user, sequenceId, eventAddress, "Event not approved");
                sequence.currentIndex++;
                continue;
            }

            Event eventContract = Event(eventAddress);

            // Check if event is open for betting and before start time
            if (eventContract.status() != Event.EventStatus.Open || block.timestamp >= eventContract.startTime()) {
                // Event not open for betting, skip it
                sequence.skippedIndices.push(sequence.currentIndex);
                emit BetSkipped(user, sequenceId, eventAddress, "Event not open for betting");
                sequence.currentIndex++;
                continue;
            }

            uint256 betAmount = sequence.betAmounts[sequence.currentIndex];

            // Approve the Event contract to spend tokens
            protocolToken.approve(eventAddress, betAmount);

            // Place bet on the Event contract (bet is placed under StackBets contract's address)
            eventContract.placeBet(sequence.outcomeIndexes[sequence.currentIndex], betAmount);

            // Move to the next index for future bets
            sequence.currentIndex++;

            // Emit the BetPlaced event
            emit BetPlaced(user, sequenceId, eventAddress, outcomeIndex, betAmount);

            // Register this sequence in the eventToUserSequences mapping
            eventToUserSequences[eventAddress].push(UserSequence({
                user: user,
                sequenceId: sequenceId
            }));

            // Exit the loop after placing the bet
            break;
        }

        // If all events have been processed, mark the sequence as inactive
        if (sequence.currentIndex >= sequence.eventAddresses.length) {
            sequence.active = false;
            emit BetSequenceEnded(user, sequenceId);
        }
    }

    /**
     * @notice Called by the EventManager to notify StackBets of an event's outcome.
     * @param eventAddress The address of the event that was resolved.
     */
    function notifyOutcome(address eventAddress) external onlyEventManager nonReentrant {
        UserSequence[] storage sequences = eventToUserSequences[eventAddress];
        Event eventContract = Event(eventAddress);

        if (sequences.length > 0) {
            if (eventContract.status() == Event.EventStatus.Closed) {
                distributePayout(eventContract, sequences);
            }

            if (eventContract.status() == Event.EventStatus.Cancelled) {
                withdrawBetAndDistribute(eventContract, sequences);
            }
        }

        delete approvedEventContracts[eventAddress];
    }

    function distributePayout(Event eventContract, UserSequence[] storage sequences) internal {
        uint256 winningOutcome = eventContract.winningOutcome();
        uint256 totalPayout = eventContract.claimPayout();
        uint256 totalStakeOnWinningOutcome = eventContract.getUserBet(address(this), winningOutcome);

        require(totalStakeOnWinningOutcome > 0, "StackBets contract has no stake on winning outcome");
    
        // Iterate over each sequence and process winnings
        for (uint256 i = 0; i < sequences.length; i++) {
            address user = sequences[i].user;
            uint256 sequenceId = sequences[i].sequenceId;
            BetSequence storage sequence = userBetSequences[user][sequenceId];

            if (!sequence.active) {
                continue; // Skip inactive sequences
            }

            uint256 eventIndex = sequence.currentIndex - 1; // Adjust index since we incremented after placing the bet
            if (sequence.eventAddresses[eventIndex] != address(eventContract)) {
                continue; // Mismatch in expected event
            }

            uint256 desiredOutcome = sequence.outcomeIndexes[eventIndex];
            uint256 userBetAmount = sequence.betAmounts[eventIndex];

            uint256 userWinnings = 0;

            if (desiredOutcome == winningOutcome) {
                // User won
                // Calculate user's share of the total payout
                userWinnings = (userBetAmount * totalPayout) / totalStakeOnWinningOutcome;

                // Update total winnings
                sequence.totalWinnings += userWinnings;

                // Set bet amount for the next event
                if (sequence.currentIndex < sequence.eventAddresses.length) {
                    sequence.betAmounts[sequence.currentIndex] = userWinnings;
                    // Attempt to place the next bet
                    _attemptNextBet(user, sequenceId);
                } else {
                    // Sequence completed
                    sequence.active = false;
                    emit BetSequenceEnded(user, sequenceId);
                }
            } else {
                // User lost, sequence ends
                sequence.active = false;
                emit BetSequenceEnded(user, sequenceId);
            }
        }

        // Clean up
        delete eventToUserSequences[address(eventContract)];
    }

    function withdrawBetAndDistribute(Event eventContract, UserSequence[] storage sequences) internal {
        string[] memory outcomes = eventContract.getOutcomes();

        uint256 totalBets = 0;
        for (uint256 i = 0; i < outcomes.length; i++) {
            uint256 betAmount = eventContract.getUserBet(address(this), i);
            if (betAmount == 0) {
                continue;
            }

            totalBets += eventContract.withdrawBet(i);
        }

        // Iterate over each sequence and process refund
        for (uint256 i = 0; i < sequences.length; i++) {
            address user = sequences[i].user;
            uint256 sequenceId = sequences[i].sequenceId;
            BetSequence storage sequence = userBetSequences[user][sequenceId];

            if (!sequence.active) {
                continue; // Skip inactive sequences
            }

            uint256 eventIndex = sequence.currentIndex - 1; // Adjust index since we incremented after placing the bet
            if (sequence.eventAddresses[eventIndex] != address(eventContract)) {
                continue; // Mismatch in expected event
            }

            uint256 userBetAmount = sequence.betAmounts[eventIndex];

            // Set bet amount for the next event
            if (sequence.currentIndex < sequence.eventAddresses.length) {
                sequence.betAmounts[sequence.currentIndex] = userBetAmount;
                // Attempt to place the next bet
                _attemptNextBet(user, sequenceId);
            } else {
                // Sequence completed
                sequence.active = false;
                emit BetSequenceEnded(user, sequenceId);
            }
        }

        // Clean up
        delete eventToUserSequences[address(eventContract)];
    }

    /**
     * @notice Allows users to collect any accumulated winnings from a specific bet sequence.
     * @param sequenceId The ID of the bet sequence.
     */
    function collectSequenceWinnings(uint256 sequenceId) external nonReentrant {
        BetSequence storage sequence = userBetSequences[msg.sender][sequenceId];
        require(!sequence.active, "Sequence is still active");
        require(sequence.totalWinnings > 0, "No winnings to collect");

        uint256 amount = sequence.totalWinnings;
        sequence.totalWinnings = 0;

        // Transfer winnings to the user
        protocolToken.transfer(msg.sender, amount);
        emit WinningsCollected(msg.sender, amount);
    }

    /**
     * @notice Retrieves the skipped event indices for a user's bet sequence.
     * @param user The address of the user.
     * @param sequenceId The ID of the bet sequence.
     */
    function getSkippedEvents(address user, uint256 sequenceId) external view returns (uint256[] memory) {
        return userBetSequences[user][sequenceId].skippedIndices;
    }

    /**
     * @notice Retrieves active bet sequences for a user.
     * @param user The address of the user.
     * @return An array of active bet sequence IDs.
     */
    function getActiveSequences(address user) external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < userBetSequences[user].length; i++) {
            if (userBetSequences[user][i].active) {
                activeCount++;
            }
        }

        uint256[] memory activeSequences = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < userBetSequences[user].length; i++) {
            if (userBetSequences[user][i].active) {
                activeSequences[index] = i;
                index++;
            }
        }

        return activeSequences;
    }

    function getUserBetSequences() public view returns (BetSequence[] memory) {
        return userBetSequences[msg.sender];
    }

    function getUserOneBetSequences(uint256 sequenceId) public view returns (BetSequence memory) {
        require(sequenceId < userBetSequences[msg.sender].length, "Invalid sequence ID");
        return userBetSequences[msg.sender][sequenceId];
    }

    /**
     * @notice Emergency function to recover tokens mistakenly sent to the contract.
     * @param to The address to send the tokens to.
     * @param amount The amount of tokens to recover.
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        uint256 contractBalance = protocolToken.balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient contract balance");
        protocolToken.transfer(to, amount);
        emit EmergencyWithdrawal(to, amount);
    }
}
