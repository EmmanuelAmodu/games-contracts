// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CollateralManager.sol";

contract Event is ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant VERSION = "0.0.4";
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

    uint256 public eventId;
    string public title;
    string public description;
    string public category;
    string public thumbnailUrl;
    string public streamingUrl;
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
    mapping(address => uint256) public userTotalBets;
    mapping(uint256 => uint256) public outcomeStakers;
    uint256 public totalStakers;

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
    event EventClosed(uint256 eventId);

    modifier onlyCreator() {
        require(msg.sender == creator, "Only event creator");
        _;
    }

    modifier onlyCollateralManager() {
        require(msg.sender == collateralManager, "Only collateral manager can call");
        _;
    }

    modifier inStatus(EventStatus _status) {
        require(status == _status, "Invalid event status");
        _;
    }

    constructor(
        uint256 _eventId,
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

        eventId = _eventId;
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
        bettingLimit = CollateralManager(collateralManager).computeBetLimit(creator, _collateralAmount);
    }

    /**
     * @notice Allows users to place bets on the event.
     * @param _outcomeIndex Outcome to bet against
     * @param _amount Amount to bet
     */
    function placeBet(uint256 _outcomeIndex, uint256 _amount) external inStatus(EventStatus.Open) {
        require(block.timestamp < startTime, "Betting is closed");
        require(totalStaked + _amount <= bettingLimit, "Betting limit reached");
        require(_outcomeIndex < outcomes.length, "Invalid outcome index");
        require(_amount > 0, "Bet amount must be greater than zero");

        require(
            userTotalBets[msg.sender] + _amount <= bettingLimit / 10,
            "Bet amount exceeds user limit"
        );

        bettingToken.safeTransferFrom(msg.sender, address(this), _amount);

        userBets[msg.sender][_outcomeIndex] += _amount;
        userTotalBets[msg.sender] += _amount; // Update user's total bets
        outcomeStakes[_outcomeIndex] += _amount;
        outcomeStakers[_outcomeIndex] += 1;
        totalStaked += _amount;
        totalStakers += 1;

        emit BetPlaced(msg.sender, _amount, _outcomeIndex);
    }

    /**
     * @notice Sets the protocol fee percentage. Can only be called by the governance.
     * @param _collateralAmount The new protocol fee percentage.
     */
    function setBetLimit(uint256 _collateralAmount) external onlyCollateralManager {
        bettingLimit = CollateralManager(collateralManager).computeBetLimit(creator, _collateralAmount);
    }

    /**
     * @notice Closes the event for betting. Can only be called by the Collateral Manager.
     */
    function closeEvent() external onlyCollateralManager {
        require(
            status == EventStatus.Resolved || status == EventStatus.Cancelled,
            "Event not resolved or cancelled"
        );
        require(block.timestamp > endTime, "Event has not ended yet");

        status = EventStatus.Closed;
        emit EventClosed(eventId);
    }

    /**
     * @notice Updates the thumbnail URL of the event. Can only be called by the creator.
     * @param _thumbnailUrl The new thumbnail URL.
     */
    function updateThumbnailUrl(string memory _thumbnailUrl) external onlyCreator {
        thumbnailUrl = _thumbnailUrl;
    }

    /**
     * @notice Updates the streaming URL of the event. Can only be called by the creator.
     * @param _streamingUrl The new streaming URL.
     */
    function updateStreamingUrl(string memory _streamingUrl) external onlyCreator {
        streamingUrl = _streamingUrl;
    }

    /**
     * @notice Submits the outcome of the event. Collateral is not released immediately.
     * @param _winningOutcome The index of the winning outcome.
     */
    function submitOutcome(uint256 _winningOutcome) external inStatus(EventStatus.Open) onlyCreator {
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
    function createDispute(string calldata _reason) external inStatus(EventStatus.Resolved) nonReentrant {
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
        require(bettingToken.balanceOf(msg.sender) >= disputeCollateral, "Insufficient balance to create dispute");

        bettingToken.safeTransferFrom(msg.sender, address(this), disputeCollateral);
        disputeStatus = DisputeStatus.Disputed;
        disputingUser = msg.sender;
        disputeReason = _reason;

        emit DisputeCreated(msg.sender, _reason);
    }

    /**
     * @notice Allows users who bet on the winning outcome to claim their payouts.
     */
    function claimPayout() external inStatus(EventStatus.Closed) nonReentrant {
        require(block.timestamp > disputeDeadline, "Dispute period not over");
        require(disputeStatus != DisputeStatus.Disputed, "Dispute is unresolved");
        require(!hasClaimed[msg.sender], "Payout already claimed");

        uint256 userStake = userBets[msg.sender][winningOutcome];
        require(userStake > 0, "No winning bet to claim");

        // Calculate user's share
        uint256 loot = totalStaked - outcomeStakes[winningOutcome];
        uint256 fee = (loot * protocolFeePercentage) / 100;
        uint256 netLoot = loot - fee;

        uint256 userPayout = userStake + (userStake * netLoot) / outcomeStakes[winningOutcome];

        // Transfer payout to user
        bettingToken.safeTransfer(msg.sender, userPayout);

        hasClaimed[msg.sender] = true;

        emit PayoutClaimed(msg.sender, userPayout);
    }

    /**
     * @notice Allows users to withdraw their bets if the event is cancelled.
     * @param _outcomeIndex The index of the outcome to withdraw the bet from.
     */
    function withdrawBet(uint256 _outcomeIndex) external inStatus(EventStatus.Cancelled) {
        require(_outcomeIndex < outcomes.length, "Invalid outcome index");
        uint256 userStake = userBets[msg.sender][_outcomeIndex];
        require(userStake > 0, "No bet to withdraw");

        // Update mappings
        userBets[msg.sender][_outcomeIndex] = 0;
        userTotalBets[msg.sender] -= userStake; // Decrease user's total bets
        outcomeStakes[_outcomeIndex] -= userStake;
        totalStaked -= userStake;

        // Transfer tokens back to user
        bettingToken.safeTransfer(msg.sender, userStake);
    }

    /**
     * @notice Pays the fees to the protocol and the event creator.
     * @param protocolFeeRecipient The address to receive the protocol fees.
     */
    function payFees(address protocolFeeRecipient) external onlyCollateralManager inStatus(EventStatus.Resolved) {
        uint256 winningStake = outcomeStakes[winningOutcome];
        uint256 loot = totalStaked - winningStake;
        uint256 fee = (loot * protocolFeePercentage) / 100;

       bettingToken.safeTransfer(protocolFeeRecipient, fee / 2);
       bettingToken.safeTransfer(creator, fee / 2);
    }

    /**
     * @notice Cancels the event. Cannot be called after the event start time.
     */
    function cancelEvent() external onlyCollateralManager inStatus(EventStatus.Open) {
        require(block.timestamp < startTime, "Cannot cancel after event start time");
        require(status == EventStatus.Open, "Only opened event can be cancelled");
        status = EventStatus.Cancelled;

        emit EventCancelled();
    }

    /**
     * @notice Resolves the dispute. Can be called by governance or an arbitrator.
     * @param _finalOutcome The final outcome after dispute resolution.
     */
    function resolveDispute(uint256 _finalOutcome) external onlyCollateralManager nonReentrant {
        require(disputeStatus == DisputeStatus.Disputed, "No dispute to resolve");
        require(_finalOutcome < outcomes.length, "Invalid outcome index");

        disputeStatus = DisputeStatus.Resolved;

        if (_finalOutcome != winningOutcome) {
            winningOutcome = _finalOutcome;
        } else {
            // 50% User's collateral is transferred to the event creator
            bettingToken.safeTransfer(creator, disputeCollateral / 2);
            // 50% User's collateral is transferred to the governance
            bettingToken.safeTransfer(CollateralManager(collateralManager).protocolFeeRecipient(), disputeCollateral / 2);
        }

        emit DisputeResolved(winningOutcome, _finalOutcome);
    }

    // View functions

    /**
     * @notice Returns the user's bet for a given outcome.
     * @param _user The user's address.
     * @param _outcomeIndex The index of the outcome.
     */
    function getUserBet(address _user, uint256 _outcomeIndex) external view returns (uint256) {
        return userBets[_user][_outcomeIndex];
    }

    /**
     * @notice Returns the total stake for a given outcome.
     * @param _outcomeIndex The index of the outcome.
     */
    function getOutcomeStakes(uint256 _outcomeIndex) external view returns (uint256) {
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

    function getOutcomeStakers() external view returns (uint256[] memory) {
        uint256[] memory stakers = new uint256[](outcomes.length);
        for (uint256 i = 0; i < outcomes.length; i++) {
            stakers[i] = outcomeStakers[i];
        }
        return stakers;
    }
}
