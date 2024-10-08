// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CollateralManager.sol";

contract Event is ReentrancyGuard {
    enum EventStatus {
        Open,
        Closed,
        Resolved,
        Cancelled
    }

    enum DisputeStatus {
        None,
        Disputed,
        Resolved
    }

    string public title;
    string public description;
    string public category;
    string[] public outcomes;
    uint256 public startTime;
    uint256 public endTime;
    address public creator;
    uint256 public collateralAmount;
    address public collateralManager;
    EventStatus public status;
    uint256 public totalStaked;
    uint256 public bettingLimit;

    mapping(uint256 => uint256) public outcomeStakes;
    mapping(address => mapping(uint256 => uint256)) public userBets;
    mapping(address => bool) public hasClaimed;

    uint256 public winningOutcome;
    uint256 public protocolFeePercentage = 10; // 10%

    IERC20 public bettingToken;

    // Dispute variables
    // V2: Multiple users can create dispute till disputeCollateral to event collateral is reached
    DisputeStatus public disputeStatus;
    uint256 public disputeDeadline;
    address public disputingUser;
    string public disputeReason;
    uint256 public disputeCollateral;

    event BetPlaced(address indexed user, uint256 amount, uint256 outcome);
    event OutcomeSubmitted(uint256 indexed winningOutcome);
    event PayoutClaimed(address indexed user, uint256 amount);
    event EventResolved(uint256 winningOutcome);
    event EventCancelled();
    event DisputeCreated(address indexed user, string reason);
    event DisputeResolved(uint256 initialOutcome, uint256 finalOutcome);
    event EventClosed();

    modifier onlyCreator() {
        require(msg.sender == creator, "Only event creator");
        _;
    }

    modifier onlyCollateralManager() {
        require(
            msg.sender == collateralManager,
            "Only collateral manager can call"
        );
        _;
    }

    modifier inStatus(EventStatus _status) {
        require(status == _status, "Invalid event status");
        _;
    }

    modifier notContract() {
        require(msg.sender == tx.origin, "Contracts not allowed");
        _;
    }

    modifier onlyGovernance() {
        require(
            msg.sender == CollateralManager(collateralManager).governance(),
            "Only governance can call"
        );
        _;
    }

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
    ) {
        require(_startTime >= block.timestamp, "Start time must be in future");
        require(_endTime > _startTime, "End time must be after start time");
        require(_outcomes.length >= 2, "At least two outcomes required");

        title = _title;
        description = _description;
        category = _category;
        outcomes = _outcomes;
        startTime = _startTime;
        endTime = _endTime;
        creator = _creator;
        collateralAmount = _collateralAmount;
        collateralManager = _collateralManager;
        status = EventStatus.Open;

        bettingToken = IERC20(_bettingToken);

        // Calculate betting limit
        bettingLimit = CollateralManager(collateralManager)
            .computeBetLimit(creator, _collateralAmount);
    }

    /**
     * @notice Allows users to place bets on the event.
     * @param _outcomeIndex Outcome to bet against
     * @param _amount Amount to bet
     */
    function placeBet(
        uint256 _outcomeIndex,
        uint256 _amount
    ) external inStatus(EventStatus.Open) notContract {
        require(
            block.timestamp >= startTime && block.timestamp <= endTime,
            "Betting is closed"
        );
        require(totalStaked + _amount <= bettingLimit, "Betting limit reached");
        require(_outcomeIndex < outcomes.length, "Invalid outcome index");
        require(_amount > 0, "Bet amount must be greater than zero");

        // Transfer betting tokens from the user to the contract
        bettingToken.transferFrom(msg.sender, address(this), _amount);

        userBets[msg.sender][_outcomeIndex] += _amount;
        outcomeStakes[_outcomeIndex] += _amount;
        totalStaked += _amount;

        emit BetPlaced(msg.sender, _amount, _outcomeIndex);
    }


    /**
     * @notice Sets the protocol fee percentage. Can only be called by the governance.
     * @param _collateralAmount The new protocol fee percentage.
     */
    function setBetLimit(
        uint256 _collateralAmount
    ) external onlyCollateralManager {
        bettingLimit = CollateralManager(collateralManager)
            .computeBetLimit(creator, _collateralAmount);
    }

    /**
     * @notice Closes the event for betting. Can only be called by the Collateral Manager.
     */
    function closeEvent()
        external
        inStatus(EventStatus.Resolved)
        onlyCollateralManager
    {
        require(block.timestamp > endTime, "Event has not ended yet");
        require(status == EventStatus.Resolved, "Event not resolved");

        status = EventStatus.Closed;
        emit EventClosed();
    }

    /**
     * @notice Submits the outcome of the event. Collateral is not released immediately.
     * @param _winningOutcome The index of the winning outcome.
     */
    function submitOutcome(
        uint256 _winningOutcome
    ) external inStatus(EventStatus.Open) onlyCreator {
        require(block.timestamp > endTime, "Event has not ended yet");
        require(_winningOutcome < outcomes.length, "Invalid outcome index");
        winningOutcome = _winningOutcome;
        status = EventStatus.Resolved;

        // Set dispute deadline to 1 hours from now
        disputeDeadline = block.timestamp + 1 hours;
        disputeStatus = DisputeStatus.None;

        emit OutcomeSubmitted(_winningOutcome);
        emit EventResolved(_winningOutcome);
    }

    /**
     * @notice Allows users to create a dispute within 1 hours after the outcome is submitted.
     * @param _reason A brief reason for the dispute.
     */
    function createDispute(
        string calldata _reason
    ) external inStatus(EventStatus.Resolved) nonReentrant {
        require(block.timestamp <= disputeDeadline, "Dispute period has ended");
        require(disputeStatus == DisputeStatus.None, "Dispute already raised");

        // Users must have participated in the event to raise a dispute
        bool hasBet = false;
        for (uint256 i = 0; i < outcomes.length; i++) {
            if (userBets[msg.sender][i] > 0) {
                hasBet = true;
                break;
            }
        }

        require(hasBet, "Only participants can dispute");

        disputeCollateral = (totalStaked * 10) / 100; // 10% of total staked
        require(
            bettingToken.balanceOf(msg.sender) >= disputeCollateral,
            "Insufficient balance to create dispute"
        );

        bettingToken.transferFrom(msg.sender, address(this), disputeCollateral);
        disputeStatus = DisputeStatus.Disputed;
        disputingUser = msg.sender;
        disputeReason = _reason;

        emit DisputeCreated(msg.sender, _reason);
    }

    /**
     * @notice Allows users who bet on the winning outcome to claim their payouts.
     */
    function claimPayout()
        external
        inStatus(EventStatus.Resolved)
        notContract
        nonReentrant
    {
        require(block.timestamp > disputeDeadline, "Dispute period not over");
        require(
            disputeStatus != DisputeStatus.Disputed,
            "Dispute is unresolved"
        );
        require(!hasClaimed[msg.sender], "Payout already claimed");

        uint256 userStake = userBets[msg.sender][winningOutcome];
        require(userStake > 0, "No winning bet to claim");

        // Calculate user's share
        uint256 loot = totalStaked - outcomeStakes[winningOutcome];
        uint256 fee = (loot * protocolFeePercentage) / 100;
        uint256 netLoot = loot - fee;

        uint256 userPayout = userStake +
            (userStake * netLoot) /
            outcomeStakes[winningOutcome];

        hasClaimed[msg.sender] = true;

        // Transfer payout to user
        bettingToken.transfer(msg.sender, userPayout);

        emit PayoutClaimed(msg.sender, userPayout);
    }

    function withdrawBet(
        uint256 _outcomeIndex
    ) external inStatus(EventStatus.Cancelled) {
        uint256 userStake = userBets[msg.sender][_outcomeIndex];
        require(userStake > 0, "No bet to withdraw");

        // Update mappings
        userBets[msg.sender][_outcomeIndex] = 0;
        outcomeStakes[_outcomeIndex] -= userStake;
        totalStaked -= userStake;

        // Transfer tokens back to user
        bettingToken.transfer(msg.sender, userStake);
    }

    /**
     * @notice Calculates the fee for a given amount based on the current loot.
     * @return The fee amount.
     */
    function calculateFee() public view returns (uint256) {
        uint256 winningStake = outcomeStakes[winningOutcome];
        uint256 loot = totalStaked - winningStake;
        return (loot * protocolFeePercentage) / 100;
    }

    /**
     * @notice Cancels the event. Cannot be called after the event start time.
     */
    function cancelEvent()
        external
        onlyCollateralManager
        inStatus(EventStatus.Open)
    {
        require(
            block.timestamp < startTime,
            "Cannot cancel after event start time"
        );
        require(status == EventStatus.Open, "Only opened event can be cancelled");
        status = EventStatus.Cancelled;

        emit EventCancelled();
    }

    /**
     * @notice Resolves the dispute. Can be called by governance or an arbitrator.
     * @param _finalOutcome The final outcome after dispute resolution.
     */
    function resolveDispute(
        uint256 _finalOutcome
    ) external onlyCollateralManager nonReentrant {
        require(
            disputeStatus == DisputeStatus.Disputed,
            "No dispute to resolve"
        );
        require(_finalOutcome < outcomes.length, "Invalid outcome index");

        disputeStatus = DisputeStatus.Resolved;

        if (_finalOutcome != winningOutcome) {
            winningOutcome = _finalOutcome;
        } else {
            // 50% User's collateral is transferred to the event creator
            bettingToken.transfer(creator, disputeCollateral / 2);
            // 50% User's collateral is transferred to the governance
            bettingToken.transfer(
                CollateralManager(collateralManager).governance(),
                disputeCollateral / 2
            );
        }

        emit DisputeResolved(winningOutcome, _finalOutcome);
    }

    // View functions

    /**
     * @notice Returns the user's bet for a given outcome.
     * @param _user The user's address.
     * @param _outcomeIndex The index of the outcome.
     */
    function getUserBet(
        address _user,
        uint256 _outcomeIndex
    ) external view returns (uint256) {
        return userBets[_user][_outcomeIndex];
    }

    /**
     * @notice Returns the total stake for a given outcome.
     * @param _outcomeIndex The index of the outcome.
     */
    function getOutcomeStakes(
        uint256 _outcomeIndex
    ) external view returns (uint256) {
        return outcomeStakes[_outcomeIndex];
    }

    function getOdds(uint256 _outcomeIndex) external view returns (uint256) {
        require(_outcomeIndex < outcomes.length, "Invalid outcome index");

        uint256 otherStakes = totalStaked - outcomeStakes[_outcomeIndex];
        uint256 outcomeStake = outcomeStakes[_outcomeIndex];

        if (outcomeStake == 0) {
            return 0; // Avoid division by zero, odds are undefined
        }

        return (otherStakes * 1e18) / outcomeStake; // Return odds scaled by 1e18
    }

    /**
     * @notice Returns the event details.
     */
    function getOutcomes() external view returns (string[] memory) {
        return outcomes;
    }
}
