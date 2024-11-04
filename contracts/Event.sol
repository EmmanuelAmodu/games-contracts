// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IPepperBaseTokenV1} from "./interfaces/IPepperBaseTokenV1.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EventManager} from "./EventManager.sol";

/// @title Event contract for creating prediction pools.
contract Event is ReentrancyGuard {
    string public constant VERSION = "0.1.0"; // Updated version

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
    uint256 public createTime;
    uint256 public startTime;
    uint256 public endTime;
    address public creator;
    uint256 public collateralAmount;
    address public eventManager;
    EventStatus public status;
    uint256 public totalStaked;

    mapping(uint256 => uint256) public outcomeStakes;
    mapping(address => mapping(uint256 => uint256)) public userBets;
    mapping(address => bool) public hasClaimed;
    mapping(address => uint256) public userTotalBets;
    mapping(uint256 => uint256) public outcomeStakers;
    uint256 public totalStakers;

    uint256 public winningOutcome;
    uint256 public protocolFeePercentage = 10; // 10%

    IPepperBaseTokenV1 public protocolToken;

    // Dispute variables
    DisputeStatus public disputeStatus;
    uint256 public disputeDeadline;
    uint256 public disputeRefundDeadline;
    string public disputeReason;
    uint256 public totalDisputeContributions;
    uint256 public disputeCollateralTarget; // Target amount for dispute collateral

    // Mapping of disputing users and their contributions
    mapping(address => uint256) public disputingUsers;

    // Array to keep track of disputing user addresses
    address[] private disputingUserAddresses;

    uint256 public maxDisputingUsers = 100;
    uint256 public minDisputeContribution = 1e18; // Example: minimum 1 token

    // Tracking total payouts for edge case handling
    uint256 public totalPayouts;

    event BetPlaced(address indexed user, uint256 amount, uint256 outcome);
    event BetWithdrawn(address indexed user, uint256 amount, uint256 outcomeIndex);
    event OutcomeSubmitted(uint256 indexed winningOutcome);
    event PayoutClaimed(address indexed user, uint256 amount);
    event EventResolved(uint256 winningOutcome);
    event EventCancelled();
    event DisputeCreated(address indexed user, string reason, uint256 amount);
    event DisputeContribution(address indexed user, uint256 amount, uint256 totalContributed);
    event DisputeResolved(uint256 initialOutcome, uint256 finalOutcome);
    event EventClosed(uint256 eventId);
    event DisputeContributionRefunded(address indexed user, uint256 amount);
    event BetsRefunded();
    event ThumbnailUrlUpdated(string newThumbnailUrl);
    event StreamingUrlUpdated(string newStreamingUrl);
    event UnclaimedDisputeContributionsCollected(uint256 amount);
    event DisputeContributionsForfeited(address indexed creator, uint256 amount);
    event DisputeContributionsDistributed(uint256 toCreator, uint256 toProtocol, uint256 burnt);

    modifier onlyCreator() {
        require(msg.sender == creator, "Only event creator can call");
        _;
    }

    modifier onlyEventManager() {
        require(msg.sender == eventManager, "Only event manager can call");
        _;
    }

    modifier inStatus(EventStatus _status) {
        require(status == _status, "Invalid event status");
        _;
    }

    /// @notice Initializes the event contract.
    constructor(
        uint256 _eventId,
        string memory _title,
        string memory _description,
        string memory _category,
        string[] memory _outcomes,
        uint256 _startTime,
        uint256 _endTime,
        address _creator,
        address _eventManager,
        address _protocolToken
    ) {
        require(_startTime >= block.timestamp + 2 hours, "Start time must be at least 2 hours in the future");
        require(_endTime > _startTime, "End time must be after start time");
        require(_outcomes.length >= 2 && _outcomes.length <= 12, "Invalid number of outcomes");
        require(_creator != address(0), "Invalid creator address");
        require(_eventManager != address(0), "Invalid event manager address");
        require(_protocolToken != address(0), "Invalid protocol token address");

        eventId = _eventId;
        title = _title;
        description = _description;
        category = _category;
        outcomes = _outcomes;
        startTime = _startTime;
        endTime = _endTime;
        creator = _creator;
        eventManager = _eventManager;
        status = EventStatus.Open;
        createTime = block.timestamp;

        protocolToken = IPepperBaseTokenV1(_protocolToken);
    }

    /// @notice Allows users to place bets on the event.
    /// @param _outcomeIndex Outcome to bet on
    /// @param _amount Amount to bet
    function placeBet(uint256 _outcomeIndex, uint256 _amount) external nonReentrant inStatus(EventStatus.Open) {
        require(block.timestamp < startTime, "Betting is closed");
        require(_outcomeIndex < outcomes.length, "Invalid outcome index");
        require(_amount > 0, "Bet amount must be greater than zero");
        require(msg.sender != address(0), "Invalid user address");

        // Transfer tokens before state changes to prevent reentrancy
        protocolToken.transferFrom(msg.sender, address(this), _amount);

        // Update state variables
        userBets[msg.sender][_outcomeIndex] += _amount;
        userTotalBets[msg.sender] += _amount; // Update user's total bets
        outcomeStakes[_outcomeIndex] += _amount;
        outcomeStakers[_outcomeIndex] += 1;
        totalStaked += _amount;
        totalStakers += 1;

        emit BetPlaced(msg.sender, _amount, _outcomeIndex);
    }

    /// @notice Closes the event for betting. Can only be called by the EventManager.
    function closeEvent() external onlyEventManager inStatus(EventStatus.Resolved) {
        require(block.timestamp > endTime, "Event has not ended yet");

        status = EventStatus.Closed;
        emit EventClosed(eventId);
    }

    /// @notice Updates the thumbnail URL of the event. Can only be called by the creator before the event starts.
    /// @param _thumbnailUrl The new thumbnail URL.
    function updateThumbnailUrl(string memory _thumbnailUrl) external onlyCreator {
        require(block.timestamp < startTime, "Cannot update after event start");
        thumbnailUrl = _thumbnailUrl;
        emit ThumbnailUrlUpdated(_thumbnailUrl);
    }

    /// @notice Updates the streaming URL of the event. Can only be called by the creator before the event starts.
    /// @param _streamingUrl The new streaming URL.
    function updateStreamingUrl(string memory _streamingUrl) external onlyCreator {
        require(block.timestamp < startTime, "Cannot update after event start");
        streamingUrl = _streamingUrl;
        emit StreamingUrlUpdated(_streamingUrl);
    }

    /// @notice Submits the outcome of the event. Collateral is not released immediately.
    /// @param _winningOutcome The index of the winning outcome.
    function submitOutcome(uint256 _winningOutcome) external onlyCreator nonReentrant inStatus(EventStatus.Open) {
        require(block.timestamp > endTime, "Event has not ended yet");
        require(_winningOutcome < outcomes.length, "Invalid outcome index");
        winningOutcome = _winningOutcome;
        status = EventStatus.Resolved;

        // Set dispute deadline to 1 hour from now
        disputeDeadline = block.timestamp + 1 hours;
        disputeRefundDeadline = disputeDeadline + 30 days;
        disputeStatus = DisputeStatus.None;

        // Set dispute collateral target to 10% of total staked
        disputeCollateralTarget = (totalStaked * 10) / 100;

        emit OutcomeSubmitted(_winningOutcome);
        emit EventResolved(_winningOutcome);
    }

    /// @notice Allows users to create or contribute to a dispute within the dispute period.
    /// @param _reason A brief reason for the dispute (only required for the first contribution).
    /// @param _amount The amount the user wants to contribute to the dispute.
    function contributeToDispute(string calldata _reason, uint256 _amount) external nonReentrant inStatus(EventStatus.Resolved) {
        require(block.timestamp <= disputeDeadline, "Dispute period has ended");
        require(_amount >= minDisputeContribution, "Contribution below minimum");
        require(msg.sender != address(0), "Invalid user address");

        // Users must have participated in the event to raise a dispute
        require(userTotalBets[msg.sender] > 0, "Only participants can dispute");

        // Update state before external calls
        if (disputingUsers[msg.sender] == 0) {
            require(disputingUserAddresses.length < maxDisputingUsers, "Maximum disputing users reached");
            disputingUserAddresses.push(msg.sender);
        }

        disputingUsers[msg.sender] += _amount;
        totalDisputeContributions += _amount;

        if (disputeStatus == DisputeStatus.None) {
            disputeStatus = DisputeStatus.Disputed;
            disputeReason = _reason;
            emit DisputeCreated(msg.sender, _reason, _amount);
        } else {
            emit DisputeContribution(msg.sender, _amount, totalDisputeContributions);
        }

        // Transfer tokens after state updates
        protocolToken.transferFrom(msg.sender, address(this), _amount);

        // If total contributions meet or exceed the target, lock the dispute
        if (totalDisputeContributions >= disputeCollateralTarget) {
            // Lock the dispute contributions and prevent further contributions
            disputeDeadline = block.timestamp; // Effectively ends the dispute period
        }
    }

    /// @notice Allows users to refund their dispute contributions if the target is not met.
    function refundDisputeContributions() external nonReentrant {
        require(block.timestamp > disputeDeadline, "Dispute period not over");
        require(block.timestamp <= disputeRefundDeadline, "Refund period has ended");
        require(disputeStatus == DisputeStatus.Resolved || disputeStatus == DisputeStatus.None, "Dispute is unresolved");
        require(totalDisputeContributions < disputeCollateralTarget, "Dispute target met");
        uint256 contribution = disputingUsers[msg.sender];
        require(contribution > 0, "No contributions to refund");

        // Update state before external calls
        disputingUsers[msg.sender] = 0;

        // Transfer tokens back to user
        protocolToken.transfer(msg.sender, contribution);

        emit DisputeContributionRefunded(msg.sender, contribution);
    }

    /// @notice Collects dispute contributions for the creator after the dispute is resolved.
    function collectDisputeContributionsForCreator() external onlyEventManager nonReentrant {
        require(disputeStatus == DisputeStatus.Resolved, "Dispute not resolved");
        require(totalDisputeContributions > 0, "No dispute contributions to collect");

        uint256 totalContributions = totalDisputeContributions;
        totalDisputeContributions = 0;

        // Calculate distributions
        uint256 toCreator = (totalContributions * 80) / 100;
        uint256 toProtocol = (totalContributions * 10) / 100;
        uint256 toBurn = totalContributions - toCreator - toProtocol; // Remaining amount

        // Transfer dispute contributions accordingly
        protocolToken.transfer(creator, toCreator);
        protocolToken.transfer(EventManager(eventManager).protocolFeeRecipient(), toProtocol);

        // Burn tokens by sending to zero address
        protocolToken.burn(toBurn);

        emit DisputeContributionsDistributed(toCreator, toProtocol, toBurn);
    }

    function resetTotalDisputeContributions() external onlyEventManager {
        totalDisputeContributions = 0;
    }

    /// @notice Collects unclaimed dispute contributions after the refund period has ended.
    function collectUnclaimedDisputeContributions() external onlyEventManager nonReentrant {
        require(block.timestamp > disputeRefundDeadline, "Collection period not reached");
        require(totalDisputeContributions > 0, "No contributions to collect");

        uint256 unclaimedContributions = 0;

        for (uint256 i = 0; i < disputingUserAddresses.length; i++) {
            address user = disputingUserAddresses[i];
            uint256 contribution = disputingUsers[user];
            if (contribution > 0) {
                unclaimedContributions += contribution;
                disputingUsers[user] = 0; // Reset user's contribution
            }
        }

        totalDisputeContributions = 0;

        // Transfer unclaimed contributions to protocol fee recipient
        if (unclaimedContributions > 0) {
            protocolToken.transfer(EventManager(eventManager).protocolFeeRecipient(), unclaimedContributions);
        }

        emit UnclaimedDisputeContributionsCollected(unclaimedContributions);
    }

    /// @notice Returns the list of disputing user addresses.
    function getDisputingUsers() external view returns (address[] memory) {
        return disputingUserAddresses;
    }

    /// @notice Allows users who bet on the winning outcome to claim their payouts.
    function claimPayout() external nonReentrant returns (uint256 userPayout) {
        require(block.timestamp > disputeDeadline, "Dispute period not over");
        require(status == EventStatus.Resolved || status == EventStatus.Closed, "Event not resolved or closed");
        require(disputeStatus != DisputeStatus.Disputed, "Dispute is unresolved");
        require(!hasClaimed[msg.sender], "Payout already claimed");
        require(msg.sender != address(0), "Invalid user address");

        uint256 userStake = userBets[msg.sender][winningOutcome];
        require(userStake > 0, "No winning bet to claim");

        uint256 winningStake = outcomeStakes[winningOutcome];
        require(winningStake > 0, "No stakes on winning outcome");

        // Mark as claimed before external calls to prevent reentrancy
        hasClaimed[msg.sender] = true;

        // Calculate user's share with high precision to prevent rounding errors
        uint256 loot = totalStaked - winningStake;
        uint256 fee = (loot * protocolFeePercentage) / 100;
        uint256 netLoot = loot - fee;

        userPayout = userStake + ((userStake * netLoot * 1e18) / winningStake) / 1e18;

        // Handle last claimant edge case
        uint256 contractBalance = protocolToken.balanceOf(address(this));
        if (contractBalance < userPayout) {
            userPayout = contractBalance;
        }

        totalPayouts += userPayout;

        // Transfer payout to user
        protocolToken.transfer(msg.sender, userPayout);

        emit PayoutClaimed(msg.sender, userPayout);
    }

    /// @notice Allows users to withdraw their bets if the event is cancelled or refunded.
    /// @param _outcomeIndex The index of the outcome to withdraw the bet from.
    function withdrawBet(uint256 _outcomeIndex) external nonReentrant returns (uint256 userStake) {
        require(_outcomeIndex < outcomes.length, "Invalid outcome index");
        require(msg.sender != address(0), "Invalid user address");
        userStake = userBets[msg.sender][_outcomeIndex];
        require(userStake > 0, "No bet to withdraw");

        require(
            status == EventStatus.Cancelled || (status == EventStatus.Resolved && outcomeStakes[winningOutcome] == 0),
            "Withdrawals not allowed"
        );

        // Ensure no underflow in userTotalBets
        require(userTotalBets[msg.sender] >= userStake, "Underflow in userTotalBets");

        // Update mappings before external calls
        userBets[msg.sender][_outcomeIndex] = 0;
        userTotalBets[msg.sender] -= userStake; // Decrease user's total bets
        outcomeStakes[_outcomeIndex] -= userStake;
        totalStaked -= userStake;

        // Transfer tokens back to user
        protocolToken.transfer(msg.sender, userStake);

        emit BetWithdrawn(msg.sender, userStake, _outcomeIndex);
    }

    /// @notice Pays the fees to the protocol and the event creator.
    /// @param protocolFeeRecipient The address to receive the protocol fees.
    /// @param winningOutcomeChanged Indicates if the winning outcome was changed due to a dispute.
    function payFees(address protocolFeeRecipient, bool winningOutcomeChanged) external onlyEventManager inStatus(EventStatus.Resolved) {
        require(protocolFeeRecipient != address(0), "Invalid fee recipient address");
        uint256 winningStake = outcomeStakes[winningOutcome];

        if (winningStake > 0) {
            uint256 loot = totalStaked - winningStake;
            uint256 fee = (loot * protocolFeePercentage) / 100;

            if (disputeStatus == DisputeStatus.Resolved && winningOutcomeChanged) {
                // Creator lost the dispute; protocol takes full fee
                protocolToken.transfer(protocolFeeRecipient, fee);
            } else {
                // Split fee between protocol and creator
                protocolToken.transfer(protocolFeeRecipient, fee / 2);
                protocolToken.transfer(creator, fee / 2);
            }
        }
    }

    /// @notice Cancels the event. Cannot be called after the event start time.
    function cancelEvent() external onlyEventManager inStatus(EventStatus.Open) {
        require(block.timestamp < startTime - 1 hours, "Cannot cancel event within 1 hour of start time");
        status = EventStatus.Cancelled;

        emit EventCancelled();
    }

    /// @notice Resolves the dispute. Can only be called by EventManager.
    /// @param _finalOutcome The final outcome after dispute resolution.
    function resolveDispute(uint256 _finalOutcome) external onlyEventManager nonReentrant {
        require(disputeStatus == DisputeStatus.Disputed, "No dispute to resolve");
        require(_finalOutcome < outcomes.length, "Invalid outcome index");

        // Update dispute status before external calls
        disputeStatus = DisputeStatus.Resolved;

        uint256 initialOutcome = winningOutcome;
        bool winningOutcomeChanged = _finalOutcome != winningOutcome;

        if (winningOutcomeChanged) {
            winningOutcome = _finalOutcome;
            // Emit event for outcome change
            emit EventResolved(_finalOutcome);
        }

        emit DisputeResolved(initialOutcome, _finalOutcome);

        // Adjust fee distribution based on dispute outcome
        EventManager(eventManager).notifyDisputeResolution(address(this), winningOutcomeChanged);
    }

    // View functions

    /// @notice Returns the user's bet for a given outcome.
    /// @param _user The user's address.
    /// @param _outcomeIndex The index of the outcome.
    function getUserBet(address _user, uint256 _outcomeIndex) external view returns (uint256) {
        return userBets[_user][_outcomeIndex];
    }

    /// @notice Returns the total stake for a given outcome.
    /// @param _outcomeIndex The index of the outcome.
    function getOutcomeStakes(uint256 _outcomeIndex) external view returns (uint256) {
        return outcomeStakes[_outcomeIndex];
    }

    /// @notice Returns the odds for a given outcome.
    /// @param _outcomeIndex The index of the outcome.
    function getOdds(uint256 _outcomeIndex) external view returns (uint256) {
        require(_outcomeIndex < outcomes.length, "Invalid outcome index");

        uint256 outcomeStake = outcomeStakes[_outcomeIndex];
        uint256 otherStakes = totalStaked - outcomeStake;

        if (outcomeStake == 0 || otherStakes == 0) {
            return 0; // No odds available
        }

        return (otherStakes * 1e18) / outcomeStake; // Return odds scaled by 1e18
    }

    /// @notice Returns the event outcomes.
    function getOutcomes() external view returns (string[] memory) {
        return outcomes;
    }

    /// @notice Returns the number of stakers for each outcome.
    function getOutcomeStakers() external view returns (uint256[] memory) {
        uint256[] memory stakers = new uint256[](outcomes.length);
        for (uint256 i = 0; i < outcomes.length; i++) {
            stakers[i] = outcomeStakers[i];
        }
        return stakers;
    }

    /// @notice Refunds all bets if no one bet on the winning outcome.
    function refundAllBets() external onlyEventManager inStatus(EventStatus.Resolved) {
        require(outcomeStakes[winningOutcome] == 0, "Winning bets exist");
        // Allow users to withdraw their bets
        status = EventStatus.Cancelled;
        emit BetsRefunded();
    }
}
