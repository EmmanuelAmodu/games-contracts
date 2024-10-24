// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IPepperBaseTokenV1} from "./interfaces/IPepperBaseTokenV1.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Event} from "./Event.sol";
import {Governance} from "./Governance.sol";

contract EventManager is ReentrancyGuard {
    string public constant VERSION = "0.2.0"; // Updated version
    address public protocolFeeRecipient;
    address[] public allEvents;
    uint256 public totalLpRewards;

    IPepperBaseTokenV1 public protocolToken;

    // Liquidity providers mapping and total liquidity
    mapping(address => uint256) public lpBalances; // LP address => balance
    uint256 public totalLiquidity;

    // LP reward per share tracking
    uint256 public accRewardPerShare;
    uint256 public lastRewardBalance;
    mapping(address => uint256) public lpRewardDebt;

    // Mapping from event address to collateral amount
    mapping(address => uint256) public collateralBalances; // Key: eventAddress
    mapping(address => bool) public isCollateralLocked;    // Key: eventAddress

    // Mapping to store the reputation for each creator
    mapping(address => int256) public creatorsReputation;

    // Governance contract
    Governance public governance;

    // Mapping from creator to their events
    mapping(address => address[]) public creatorEvents;

    // Mapping to track if forfeited collateral is claimed
    mapping(address => mapping(address => bool)) public forfeitedCollateralClaims; // eventAddress => user => claimed

    // Mapping to store the amount of collateral forfeited per event
    mapping(address => uint256) public forfeitedCollateralAmounts; // eventAddress => amount

    // Mapping to track dispute resolutions
    mapping(address => bool) public disputeOutcomeChanged; // eventAddress => outcomeChanged

    event CollateralLocked(address indexed eventAddress, uint256 amount);
    event CollateralReleased(address indexed eventAddress, uint256 amount);
    event CollateralForfeited(address indexed eventAddress, uint256 amount);
    event EventCreated(address indexed eventAddress, address indexed creator, uint256 eventId);
    event EventClosed(address indexed eventAddress);
    event CollateralIncreased(address indexed eventAddress, uint256 amount);
    event CollateralClaimed(address indexed eventAddress, address indexed creator, uint256 amount);
    event DisputeResolved(address indexed eventAddress, uint256 finalOutcome);
    event ForfeitedCollateralClaimed(address indexed eventAddress, address indexed user, uint256 amount);
    event LiquidityDeposited(address indexed lp, uint256 amount);
    event LiquidityWithdrawn(address indexed lp, uint256 amount);
    event LPRewardClaimed(address indexed lp, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == governance.owner(), "Only owner can call");
        _;
    }

    modifier onlyApprovedAdmin() {
        require(governance.approvedAdmins(msg.sender), "Only approved admin can call");
        _;
    }

    modifier onlyEventCreator(address _eventAddress) {
        require(msg.sender == Event(_eventAddress).creator(), "Only event creator can call");
        _;
    }

    constructor(address _protocolToken, address _governance, address _protocolFeeRecipient) {
        require(_protocolToken != address(0), "Invalid protocol token address");
        require(_governance != address(0), "Invalid governance address");
        require(_protocolFeeRecipient != address(0), "Invalid fee recipient address");

        protocolFeeRecipient = _protocolFeeRecipient;
        protocolToken = IPepperBaseTokenV1(_protocolToken);
        governance = Governance(_governance);
    }

    /**
     * @notice Allows users to deposit liquidity into the pool.
     */
    function depositLiquidity(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");

        // Update LP's pending rewards
        _updateLpRewards(msg.sender);

        protocolToken.transferFrom(msg.sender, address(this), amount);
        lpBalances[msg.sender] += amount;
        totalLiquidity += amount;

        emit LiquidityDeposited(msg.sender, amount);
    }

    /**
     * @notice Allows users to withdraw their liquidity from the pool along with any pending rewards.
     */
    function withdrawLiquidity(uint256 amount) external nonReentrant {
        require(lpBalances[msg.sender] >= amount, "Insufficient balance");

        // Update LP's pending rewards
        _updateLpRewards(msg.sender);

        lpBalances[msg.sender] -= amount;
        totalLiquidity -= amount;

        protocolToken.transfer(msg.sender, amount);

        emit LiquidityWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Allows LPs to claim their pending rewards.
     */
    function claimLpRewards() external nonReentrant {
        _updateLpRewards(msg.sender);

        uint256 rewards = (lpBalances[msg.sender] * accRewardPerShare) / 1e18 - lpRewardDebt[msg.sender];
        require(rewards > 0, "No rewards to claim");

        lpRewardDebt[msg.sender] = (lpBalances[msg.sender] * accRewardPerShare) / 1e18;

        protocolToken.transfer(msg.sender, rewards);

        emit LPRewardClaimed(msg.sender, rewards);
    }

    /**
     * @notice Internal function to update an LP's reward debt.
     */
    function _updateLpRewards(address lp) internal {
        uint256 totalRewardBalance = protocolToken.balanceOf(address(this)) - totalLiquidity - _totalCollateral();

        if (totalLiquidity > 0) {
            uint256 rewards = totalRewardBalance - lastRewardBalance;

            if (rewards > 0) {
                accRewardPerShare += (rewards * 1e18) / totalLiquidity;
                lastRewardBalance = totalRewardBalance;
            }
        }

        if (lp != address(0)) {
            lpRewardDebt[lp] = (lpBalances[lp] * accRewardPerShare) / 1e18;
        }
    }

    /**
     * @notice Calculates the total collateral locked in the contract.
     */
    function _totalCollateral() internal view returns (uint256 totalCollateral) {
        for (uint256 i = 0; i < allEvents.length; i++) {
            totalCollateral += collateralBalances[allEvents[i]];
        }
    }

    /**
     * @notice Creates a new event.
     */
    function createEvent(
        string memory _title,
        string memory _description,
        string memory _category,
        string[] memory _outcomes,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _collateralAmount
    ) external nonReentrant returns (address eventAddress, uint256 eventId) {
        require(_collateralAmount > 0, "Collateral amount must be greater than zero");
        require(_collateralAmount <= 1e24, "Collateral amount exceeds maximum limit"); // Example maximum
        require(_startTime >= block.timestamp + 2 hours, "Start time must be at least 2 hours in the future");
        require(_endTime > _startTime, "End time must be after start time");
        require(_outcomes.length >= 2 && _outcomes.length <= 10, "Invalid number of outcomes");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(creatorsReputation[msg.sender] > -30, "Creator reputation must be greater than -30");

        // Deploy a new Event contract
        eventId = allEvents.length;
        Event newEvent = new Event(
            eventId,
            _title,
            _description,
            _category,
            _outcomes,
            _startTime,
            _endTime,
            msg.sender,
            _collateralAmount,
            address(this),
            address(protocolToken)
        );

        eventAddress = address(newEvent);

        // Transfer collateral from the creator to the EventManager for this event
        lockCollateral(eventAddress, msg.sender, _collateralAmount);

        // Initialize creator's Reputation if not set
        initializeCreatorReputation(msg.sender);

        allEvents.push(eventAddress);
        creatorEvents[msg.sender].push(eventAddress);

        emit EventCreated(eventAddress, msg.sender, eventId);
    }

    /**
     * @notice Locks collateral for a specific event.
     */
    function lockCollateral(address _eventAddress, address _creator, uint256 _amount) internal {
        require(protocolToken.balanceOf(_creator) >= _amount, "Insufficient balance for collateral");
        require(
            protocolToken.allowance(_creator, address(this)) >= _amount,
            "Insufficient allowance for collateral"
        );
        require(!isCollateralLocked[_eventAddress], "Collateral already locked for this event");

        // Transfer collateral tokens from the creator to this contract
        protocolToken.transferFrom(_creator, address(this), _amount);

        collateralBalances[_eventAddress] += _amount;
        isCollateralLocked[_eventAddress] = true;

        emit CollateralLocked(_eventAddress, _amount);
    }

    /**
     * @notice Allows the event creator to claim the locked collateral after the event is resolved.
     */
    function claimCollateral(address _eventAddress) external onlyEventCreator(_eventAddress) nonReentrant {
        Event _event = Event(_eventAddress);
        require(block.timestamp > _event.disputeDeadline(), "Dispute period not over");

        // Ensure the event is resolved or canceled
        require(
            _event.status() == Event.EventStatus.Resolved || _event.status() == Event.EventStatus.Cancelled,
            "Event is not resolved or canceled"
        );

        if (_event.status() == Event.EventStatus.Resolved) {
            require(_event.disputeStatus() != Event.DisputeStatus.Disputed, "Event is disputed");
            // Transfer fee to LPs, platform, and creator
            bool winningOutcomeChanged = disputeOutcomeChanged[_eventAddress];
            _event.payFees(winningOutcomeChanged);
        }

        // Release collateral to the creator
        releaseCollateral(_eventAddress);

        // Update creator's reputation
        increaseCreatorsReputation(msg.sender, 1);

        emit CollateralClaimed(_eventAddress, msg.sender, collateralBalances[_eventAddress]);
    }

    /**
     * @notice Releases collateral back to the event creator.
     */
    function releaseCollateral(address _eventAddress) internal {
        Event eventContract = Event(_eventAddress);
        uint256 amount = collateralBalances[_eventAddress];

        require(
            eventContract.disputeStatus() != Event.DisputeStatus.Disputed,
            "Cannot release collateral during dispute"
        );
        require(isCollateralLocked[_eventAddress], "No collateral to release for this event");
        require(amount > 0, "No collateral balance for this event");

        // Update state before external calls
        collateralBalances[_eventAddress] = 0;
        isCollateralLocked[_eventAddress] = false;

        // Transfer collateral back to the creator
        protocolToken.transfer(eventContract.creator(), amount);

        if (eventContract.status() == Event.EventStatus.Resolved) {
            closeEvent(_eventAddress);
        }

        emit CollateralReleased(_eventAddress, amount);
    }

    /**
     * @notice Closes an event.
     * @param _eventAddress The address of the event contract.
     */
    function closeEvent(address _eventAddress) internal {
        Event eventContract = Event(_eventAddress);

        // Ensure the event is resolved
        require(
            eventContract.status() == Event.EventStatus.Resolved,
            "Event is not resolved"
        );

        if (eventContract.status() == Event.EventStatus.Resolved) {
            eventContract.closeEvent();
        }

        emit EventClosed(_eventAddress);
    }

    /**
     * @notice Pays the fees to LPs, the platform, and the event creator.
     * @param feeAmount The total fee amount.
     * @param creator The event creator's address.
     * @param winningOutcomeChanged Indicates if the winning outcome was changed due to a dispute.
     */
    function distributeFees(uint256 feeAmount, address creator, bool winningOutcomeChanged) external nonReentrant {
        require(msg.sender == tx.origin || msg.sender == address(this), "Invalid caller");

        uint256 lpFee = (feeAmount * 5) / 10; // 5%
        uint256 platformFee = (feeAmount * 1) / 10; // 1%
        uint256 creatorFee = feeAmount - lpFee - platformFee; // Remaining 4%

        // Update LP rewards
        _updateLpRewards(address(0)); // Update global rewards

        // Transfer platform fee
        protocolToken.transfer(protocolFeeRecipient, platformFee);

        // Transfer creator fee
        if (!winningOutcomeChanged) {
            protocolToken.transfer(creator, creatorFee);
        } else {
            // If the winning outcome was changed, the creator doesn't get the fee
            protocolToken.transfer(protocolFeeRecipient, creatorFee);
        }

        // The LP fee remains in the contract and will be accounted in rewards
        lastRewardBalance += lpFee;
    }

    /**
     * @notice Forfeits the event's collateral in case of a valid dispute.
     */
    function forfeitCollateral(address _eventAddress) internal {
        require(isCollateralLocked[_eventAddress], "No collateral to forfeit for this event");
        uint256 amount = collateralBalances[_eventAddress];
        require(amount > 0, "No collateral balance for this event");

        // Update state before external calls
        collateralBalances[_eventAddress] = 0;
        isCollateralLocked[_eventAddress] = false;

        // Calculate distributions
        uint256 toDisputingUsers = (amount * 80) / 100;
        uint256 toProtocol = (amount * 10) / 100;
        uint256 toBurn = amount - toDisputingUsers - toProtocol; // Remaining amount

        // Store the forfeited collateral amount for disputing users
        forfeitedCollateralAmounts[_eventAddress] = toDisputingUsers;

        // Transfer protocol fee
        protocolToken.transfer(protocolFeeRecipient, toProtocol);

        // Burn tokens
        protocolToken.burn(toBurn);

        // Close the event
        closeEvent(_eventAddress);

        emit CollateralForfeited(_eventAddress, amount);
    }

    /**
     * @notice Allows users to claim their share of forfeited collateral.
     * @param _eventAddress The address of the event.
     */
    function claimForfeitedCollateral(address _eventAddress) external nonReentrant {
        Event eventContract = Event(_eventAddress);
        require(eventContract.disputeStatus() == Event.DisputeStatus.Resolved, "Dispute not resolved");
        require(forfeitedCollateralAmounts[_eventAddress] > 0, "No collateral forfeited");

        uint256 userContribution = eventContract.disputingUsers(msg.sender);
        require(userContribution > 0, "No contribution to dispute");
        require(!forfeitedCollateralClaims[_eventAddress][msg.sender], "Already claimed");

        uint256 totalContributions = eventContract.totalDisputeContributions();
        require(totalContributions > 0, "Total dispute contributions must be greater than zero");

        uint256 amount = (forfeitedCollateralAmounts[_eventAddress] * userContribution) / totalContributions;
        require(amount > 0, "No collateral to claim");

        // Mark as claimed before transferring
        forfeitedCollateralClaims[_eventAddress][msg.sender] = true;

        // Transfer the user's share
        protocolToken.transfer(msg.sender, amount);

        emit ForfeitedCollateralClaimed(_eventAddress, msg.sender, amount);
    }

    /**
     * @notice Allows governance to resolve a dispute.
     */
    function resolveDispute(address _eventAddress, uint256 _finalOutcome) external onlyApprovedAdmin nonReentrant {
        Event _event = Event(_eventAddress);
        require(_event.disputeStatus() == Event.DisputeStatus.Disputed, "Event is not disputed");

        uint256 initialOutcome = _event.winningOutcome();

        // Update the dispute status in the Event contract before proceeding
        _event.resolveDispute(_finalOutcome);

        bool winningOutcomeChanged = _finalOutcome != initialOutcome;
        disputeOutcomeChanged[_eventAddress] = winningOutcomeChanged;

        // Now you can safely release or forfeit collateral
        if (winningOutcomeChanged) {
            // Forfeit collateral
            forfeitCollateral(_eventAddress);

            // Decrease creators reputation by 20% or 10 points which ever is high
            int256 decreaseByAmount = creatorsReputation[_event.creator()] / 5;
            if (decreaseByAmount < 10) {
                decreaseByAmount = 10;
            }

            decreaseCreatorsReputation(_event.creator(), uint256(decreaseByAmount));

            emit DisputeResolved(_eventAddress, _finalOutcome);
        } else {
            // Transfer dispute contributions accordingly
            _event.collectDisputeContributionsForCreator();

            emit DisputeResolved(_eventAddress, _finalOutcome);
        }
    }

    /**
     * @notice Returns all open events.
     */
    function getAllOpenEvents() external view returns (address[] memory) {
        uint256 openEventCount = 0;

        for (uint256 i = 0; i < allEvents.length; i++) {
            if (Event(allEvents[i]).status() == Event.EventStatus.Open) {
                openEventCount++;
            }
        }

        address[] memory openEvents = new address[](openEventCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allEvents.length; i++) {
            if (Event(allEvents[i]).status() == Event.EventStatus.Open) {
                openEvents[index] = allEvents[i];
                index++;
            }
        }

        // sort by creator reputation descending
        address[] memory sortedEvents = new address[](openEventCount);
        for (uint256 i = 0; i < openEvents.length; i++) {
            sortedEvents[i] = openEvents[i];
            for (uint256 j = i + 1; j < openEvents.length; j++) {
                if (creatorsReputation[Event(openEvents[j]).creator()] >
                    creatorsReputation[Event(sortedEvents[i]).creator()]) {
                    address temp = sortedEvents[i];
                    sortedEvents[i] = openEvents[j];
                    sortedEvents[j] = temp;
                }
            }
        }

        return sortedEvents;
    }

    /**
     * @notice Allows governance to update the protocol fee recipient.
     */
    function setProtocolFeeRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid address");
        protocolFeeRecipient = _newRecipient;
    }

    /**
     * @notice Allows governance to transfer governance rights.
     * Implement timelock or multi-signature as needed.
     */
    function transferGovernance(address _newGovernance) external onlyOwner {
        require(_newGovernance != address(0), "Invalid address");
        governance = Governance(_newGovernance);
    }

    /**
     * @notice Initializes the trust multiplier for a creator.
     */
    function initializeCreatorReputation(address creator) internal {
        if (creatorsReputation[creator] == int256(0)) {
            creatorsReputation[creator] = 1;
        }
    }

    /**
     * @notice Increases the creator's trust multiplier.
     * @param creator The address of the creator.
     * @param amount The amount to increase the multiplier by.
     */
    function increaseCreatorsReputation(address creator, uint256 amount) public onlyOwner {
        initializeCreatorReputation(creator);
        int256 reputation = creatorsReputation[creator] + int256(amount);
        creatorsReputation[creator] = reputation;
    }

    /**
     * @notice Decreases the creator's trust multiplier.
     * @param creator The address of the creator.
     * @param amount The amount to decrease the multiplier by.
     */
    function decreaseCreatorsReputation(address creator, uint256 amount) public onlyOwner {
        initializeCreatorReputation(creator);
        int256 reputation = creatorsReputation[creator] - int256(amount);
        require(reputation > type(int256).min, "Underflow error");
        creatorsReputation[creator] = reputation;
    }
}
