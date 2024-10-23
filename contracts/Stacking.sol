// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./interfaces/PepperBaseTokenV1.sol";
import "./Event.sol";

contract StackBets {
    PepperBaseTokenV1 public protocolToken;

    struct BetSequence {
        address[] eventAddresses;
        uint256[] outcomeIndexes;
        uint256 initialBetAmount;
        uint256 currentIndex;
        bool active;
    }

    mapping(address => BetSequence[]) public userBetSequences;
    mapping(address => uint256) public userBalances;

    event BetSequenceStarted(address indexed user, uint256 sequenceId);
    event BetPlaced(address indexed user, uint256 sequenceId, address eventAddress, uint256 outcomeIndex, uint256 amount);
    event BetSequenceEnded(address indexed user, uint256 sequenceId);
    event WinningsCollected(address indexed user, uint256 amount);

    constructor(address _protocolToken) {
        protocolToken = PepperBaseTokenV1(_protocolToken);
    }

    function depositTokens(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        protocolToken.transferFrom(msg.sender, address(this), amount);
        userBalances[msg.sender] += amount;
    }

    function withdrawTokens(uint256 amount) external {
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        userBalances[msg.sender] -= amount;
        protocolToken.transfer(msg.sender, amount);
    }

    function startBetSequence(
        address[] calldata eventAddresses,
        uint256[] calldata outcomeIndexes,
        uint256 initialBetAmount
    ) external {
        require(eventAddresses.length > 0, "At least one event required");
        require(eventAddresses.length == outcomeIndexes.length, "Mismatched inputs");
        require(userBalances[msg.sender] >= initialBetAmount, "Insufficient balance");

        // Deduct initial bet amount
        userBalances[msg.sender] -= initialBetAmount;

        // Create new bet sequence
        BetSequence memory sequence = BetSequence({
            eventAddresses: eventAddresses,
            outcomeIndexes: outcomeIndexes,
            initialBetAmount: initialBetAmount,
            currentIndex: 0,
            active: true
        });

        userBetSequences[msg.sender].push(sequence);
        uint256 sequenceId = userBetSequences[msg.sender].length - 1;

        // Place initial bet
        _placeBet(msg.sender, sequenceId, initialBetAmount);

        emit BetSequenceStarted(msg.sender, sequenceId);
    }

    function _placeBet(address user, uint256 sequenceId, uint256 amount) internal {
        BetSequence storage sequence = userBetSequences[user][sequenceId];
        address eventAddress = sequence.eventAddresses[sequence.currentIndex];
        uint256 outcomeIndex = sequence.outcomeIndexes[sequence.currentIndex];

        // Approve Event contract to spend tokens
        protocolToken.approve(eventAddress, amount);

        // Place bet on Event contract
        Event(eventAddress).placeBet(outcomeIndex, amount);

        emit BetPlaced(user, sequenceId, eventAddress, outcomeIndex, amount);
    }

    // Function to be called by off-chain service upon event resolution
    function processEventOutcome(address user, uint256 sequenceId, uint256 winnings) external {
        BetSequence storage sequence = userBetSequences[user][sequenceId];
        require(sequence.active, "Bet sequence not active");

        // Update user balance with winnings
        userBalances[user] += winnings;

        sequence.currentIndex++;

        if (sequence.currentIndex >= sequence.eventAddresses.length) {
            // Bet sequence completed
            sequence.active = false;
            emit BetSequenceEnded(user, sequenceId);
        } else {
            // Place next bet using winnings
            uint256 nextBetAmount = winnings;
            if (userBalances[user] >= nextBetAmount) {
                userBalances[user] -= nextBetAmount;
                _placeBet(user, sequenceId, nextBetAmount);
            } else {
                // Insufficient balance to continue
                sequence.active = false;
                emit BetSequenceEnded(user, sequenceId);
            }
        }
    }

    // Function to be called by users to collect any remaining winnings
    function collectWinnings() external {
        uint256 balance = userBalances[msg.sender];
        require(balance > 0, "No winnings to collect");
        userBalances[msg.sender] = 0;
        protocolToken.transfer(msg.sender, balance);
        emit WinningsCollected(msg.sender, balance);
    }
}
