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
        uint256 betAmount;             // Amount to bet
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

    // Modifier to allow only Event manager
    modifier onlyEventManager() {
        require(msg.sender == address(eventManager), "Caller is not a valid Event Manager contract");
        _;
    }

    // Events
    event BetSequenceCreated(address indexed user, uint256 sequenceId);
    event BetPlaced(address indexed user, uint256 sequenceId, address eventAddress, uint256 outcomeIndex, uint256 amount);
    event BetSkipped(address indexed user, uint256 sequenceId, address eventAddress, string reason);
    event BetSequenceEnded(address indexed user, uint256 sequenceId);
    event WinningsCollected(address indexed user, uint256 amount);
    event TokensDeposited(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed user, uint256 amount);
    event OwnerUpdated(address newOwner);
    event EventContractAdded(address eventContract);
    event EventContractRemoved(address eventContract);

    // List of approved Event contracts
    mapping(address => bool) public approvedEventContracts;

    constructor(address initialOwner, address _eventManager, address _protocolToken) Ownable(initialOwner) {
        require(_protocolToken != address(0), "Invalid token address");
        protocolToken = IPepperBaseTokenV1(_protocolToken);
        eventManager = EventManager(_eventManager);
    }

    /**
     * @notice Creates a new bet sequence and places the initial bet.
     * @param eventAddresses Array of Event contract addresses.
     * @param outcomeIndexes Array of desired outcome indices corresponding to each event.
     * @param amount The total amount to be used for the bet sequence.
     */
    function createBetSequence(
        address[] calldata eventAddresses,
        uint256[] calldata outcomeIndexes,
        uint256 amount
    ) external nonReentrant returns (uint256 sequenceId) {
        require(amount > 0, "Amount must be greater than zero");
        require(eventAddresses.length > 0, "At least one event required");
        require(eventAddresses.length == outcomeIndexes.length, "Mismatched inputs");

        // Transfer tokens to this contract
        protocolToken.transferFrom(msg.sender, address(this), amount);

        // Create a new bet sequence
        BetSequence storage sequence = userBetSequences[msg.sender].push();
        sequence.eventAddresses = eventAddresses;
        sequence.outcomeIndexes = outcomeIndexes;
        sequence.betAmount = amount; // Set initial bet amount
        sequence.currentIndex = 0;
        sequence.active = true;
        sequence.skippedIndices = new uint256[](0);
        sequence.totalWinnings = 0;

        sequenceId = userBetSequences[msg.sender].length - 1;

        // Place the initial bet
        _placeBet(msg.sender, sequenceId);

        emit BetSequenceCreated(msg.sender, sequenceId);
    }

    /**
     * @notice Internal function to place a bet on a specific event.
     * @param user The address of the user.
     * @param sequenceId The ID of the bet sequence.
     */
    function _placeBet(address user, uint256 sequenceId) internal {
        BetSequence storage sequence = userBetSequences[user][sequenceId];
        require(sequence.active, "Bet sequence inactive");
        require(sequence.currentIndex < sequence.eventAddresses.length, "No more events in sequence");

        address eventAddress = sequence.eventAddresses[sequence.currentIndex];
        uint256 outcomeIndex = sequence.outcomeIndexes[sequence.currentIndex];
        Event eventContract = Event(eventAddress);

        // Check if event is open for betting and before start time
        if (eventContract.status() != Event.EventStatus.Open || block.timestamp >= eventContract.startTime()) {
            // Event not open for betting, skip it
            sequence.skippedIndices.push(sequence.currentIndex);
            emit BetSkipped(user, sequenceId, eventAddress, "Event not open for betting");
            sequence.currentIndex++;
            _attemptNextBet(user, sequenceId);
            return;
        }

        // Approve Event contract to spend tokens
        protocolToken.approve(eventAddress, sequence.betAmount);

        // Place bet on Event contract
        eventContract.placeBet(outcomeIndex, sequence.betAmount);

        // Capture the amount placed for accurate event emission
        uint256 amountPlaced = sequence.betAmount;

        // Reset betAmount after placing the bet
        sequence.betAmount = 0;

        emit BetPlaced(user, sequenceId, eventAddress, outcomeIndex, amountPlaced);

        // Register this sequence in the eventToUserSequences mapping
        eventToUserSequences[eventAddress].push(UserSequence({
            user: user,
            sequenceId: sequenceId
        }));
    }

    /**
     * @notice Attempts to place the next bet in the sequence after handling skips.
     * @param user The address of the user.
     * @param sequenceId The ID of the bet sequence.
     */
    function _attemptNextBet(address user, uint256 sequenceId) internal {
        BetSequence storage sequence = userBetSequences[user][sequenceId];
        if (sequence.currentIndex >= sequence.eventAddresses.length) {
            // Sequence completed
            sequence.active = false;
            emit BetSequenceEnded(user, sequenceId);
            return;
        }

        // Place the next bet
        _placeBet(user, sequenceId);
    }

    /**
     * @notice Called by Event contracts to notify StackBets of an event's outcome.
     * @param eventAddress The address of the event that was resolved.
     */
    function notifyOutcome(address eventAddress) external onlyEventManager nonReentrant {
        UserSequence[] storage sequences = eventToUserSequences[eventAddress];
        Event eventContract = Event(eventAddress);
    
        require(eventContract.status() == Event.EventStatus.Closed, "Event not closed yet");
        require(sequences.length > 0, "No sequences waiting on this event");

        // Create a temporary array to hold sequences to process
        UserSequence[] memory sequencesToProcess = new UserSequence[](sequences.length);
        uint256 count = 0;

        // Copy sequences to a memory array for iteration
        for (uint256 i = 0; i < sequences.length; i++) {
            sequencesToProcess[count] = sequences[i];
            count++;
        }

        // Clear the original array to prevent reprocessing
        delete eventToUserSequences[eventAddress];

        // Interact with the Event contract to claim total payout
        uint256 totalPayout = eventContract.claimPayout();

        // Retrieve the winning outcome
        uint256 winningOutcome = eventContract.winningOutcome();

        // Retrieve total stake on winning outcome
        uint256 winningStake = eventContract.outcomeStakes(winningOutcome);

        require(winningStake > 0, "No stakes on winning outcome");

        // Iterate over each sequence and distribute winnings
        for (uint256 i = 0; i < count; i++) {
            address user = sequencesToProcess[i].user;
            uint256 sequenceId = sequencesToProcess[i].sequenceId;
            BetSequence storage sequence = userBetSequences[user][sequenceId];

            if (!sequence.active) {
                continue; // Skip inactive sequences
            }

            // Ensure the current event in the sequence matches the notified event
            if (sequence.currentIndex >= sequence.eventAddresses.length || sequence.eventAddresses[sequence.currentIndex] != eventAddress) {
                continue; // Mismatch in expected event
            }

            uint256 desiredOutcome = sequence.outcomeIndexes[sequence.currentIndex];
            uint256 userBetAmount = sequence.betAmount; // Current bet amount

            if (desiredOutcome == winningOutcome) {
                // Calculate user's share of the total payout
                uint256 userShare = (userBetAmount * totalPayout) / winningStake;

                // Update total winnings
                sequence.totalWinnings += userShare;

                // Update betAmount for the next bet
                sequence.betAmount = userShare;

                // Place the next bet using winnings
                _placeBet(user, sequenceId);
            } else {
                // User lost the bet, terminate the sequence
                sequence.active = false;
                sequence.betAmount = 0; // Reset betAmount
                emit BetSequenceEnded(user, sequenceId);
                // No action needed as winnings are zero
            }
        }
    }

    /**
     * @notice Allows users to collect any accumulated winnings from a specific bet sequence.
     * @param sequenceId The ID of the bet sequence.
     */
    function collectSequenceWinnings(uint256 sequenceId) external nonReentrant {
        BetSequence storage sequence = userBetSequences[msg.sender][sequenceId];
        require(sequence.active == false, "Sequence is still active");
        require(sequence.totalWinnings > 0, "No winnings to collect");

        uint256 amount = sequence.totalWinnings;
        sequence.totalWinnings = 0;

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

    /**
     * @notice Emergency function to recover tokens mistakenly sent to the contract.
     * @param to The address to send the tokens to.
     * @param amount The amount of tokens to recover.
     */
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Invalid recipient");
        require(protocolToken.balanceOf(address(this)) >= amount, "Insufficient contract balance");
        protocolToken.transfer(to, amount);
    }
}
