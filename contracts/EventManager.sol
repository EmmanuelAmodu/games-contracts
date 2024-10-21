// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Event} from "./Event.sol";
import "./Governance.sol";

contract EventManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant VERSION = "0.0.6";
    address public protocolFeeRecipient;
    uint256 public bettingMultiplier = 100;
    address[] public allEvents;

    IERC20 public protocolToken;

    // Mapping from event address to collateral amount
    mapping(address => uint256) public collateralBalances; // Key: eventAddress
    mapping(address => bool) public isCollateralLocked; // Key: eventAddress
    mapping(address => int256) public creatorsTrustMultiplier; // Key: creator

    // Governance contract
    Governance public governance;

    event CollateralLocked(address indexed eventAddress, uint256 amount);
    event CollateralReleased(address indexed eventAddress, uint256 amount);
    event CollateralForfeited(address indexed eventAddress, uint256 amount);
    event EventCreated(address indexed eventAddress, address indexed creator, uint256 eventId);
    event EventClosed(address indexed eventAddress);

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
        protocolToken = IERC20(_protocolToken);
        governance = Governance(_governance);
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
        require(_startTime >= block.timestamp + 2 hours, "Start time must be at least 2 hours in the future");
        require(_endTime > _startTime, "End time must be after start time");
        require(_outcomes.length >= 2, "At least two outcomes required");

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

        initializeCreatorMultiplier(msg.sender);

        // Transfer collateral from the creator to the EventManager for this event
        lockCollateral(eventAddress, msg.sender, _collateralAmount);

        allEvents.push(eventAddress);

        emit EventCreated(eventAddress, msg.sender, eventId);
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

        return openEvents;
    }

    /**
     * @notice Returns the address of an event by its ID.
     */
    function getEvent(uint256 eventId) external view returns (address eventAddress) {
        require(eventId < allEvents.length, "Invalid event ID");
        return allEvents[eventId];
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
        protocolToken.safeTransferFrom(_creator, address(this), _amount);

        collateralBalances[_eventAddress] += _amount;
        isCollateralLocked[_eventAddress] = true;

        emit CollateralLocked(_eventAddress, _amount);
    }

    /**
     * @notice Increases the locked collateral for a specific event.
     */
    function increaseCollateral(address _eventAddress, uint256 _amount) public onlyEventCreator(_eventAddress) nonReentrant {
        require(isCollateralLocked[_eventAddress], "No collateral locked for this event");
        require(_amount > 0, "Amount must be greater than zero");

        // Transfer additional collateral tokens from the creator to this contract
        protocolToken.safeTransferFrom(Event(_eventAddress).creator(), address(this), _amount);
        collateralBalances[_eventAddress] += _amount;

        Event(_eventAddress).setBetLimit(collateralBalances[_eventAddress]);

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
            // Transfer fee to governance and creator
            _event.payFees(protocolFeeRecipient);
        }

        // Burn loot if no user wins
        _event.burnLootIfNoUserWin();

        // Release collateral to the creator
        releaseCollateral(_eventAddress);
    }

    /**
     * @notice Allows the event creator to cancel an open event.
     */
    function cancelEvent(address _eventAddress) external onlyEventCreator(_eventAddress) nonReentrant {
        Event _event = Event(_eventAddress);
        require(_event.status() == Event.EventStatus.Open, "Can only cancel open events");
        require(block.timestamp < _event.startTime() - 1 hours, "Cannot cancel event within 1 hour of start time");

        _event.cancelEvent();

        // Release collateral back to the creator
        releaseCollateral(_eventAddress);
    }

    /**
     * @notice Allows governance to resolve a dispute.
     */
    function resolveDispute(address _eventAddress, uint256 _finalOutcome) external onlyApprovedAdmin nonReentrant {
        Event _event = Event(_eventAddress);
        require(_event.disputeStatus() == Event.DisputeStatus.Disputed, "Event is not disputed");

        // Update the dispute status in the Event contract before proceeding
        _event.resolveDispute(_finalOutcome);

        // Now you can safely release or forfeit collateral
        if (_finalOutcome != _event.winningOutcome()) {
            forfeitCollateral(_eventAddress);
        } else {
            releaseCollateral(_eventAddress);
        }
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
        creatorsTrustMultiplier[eventContract.creator()] += 1;

        // Transfer collateral back to the creator
        protocolToken.safeTransfer(eventContract.creator(), amount);

        if (eventContract.status() == Event.EventStatus.Resolved) {
            closeEvent(_eventAddress);
        }

        emit CollateralReleased(_eventAddress, amount);
    }

    /**
     * @notice Forfeits the event's collateral in case of a valid dispute.
     */
    function forfeitCollateral(address _eventAddress) internal {
        Event eventContract = Event(_eventAddress);
        require(isCollateralLocked[_eventAddress], "No collateral to forfeit for this event");
        uint256 amount = collateralBalances[_eventAddress];
        require(amount > 0, "No collateral balance for this event");

        // Update state before external calls
        collateralBalances[_eventAddress] = 0;
        isCollateralLocked[_eventAddress] = false;

        // Transfer collateral to dispute creator
        uint256 protocolDisputeFee = amount / 10;

        protocolToken.safeTransfer(eventContract.disputingUser(), protocolDisputeFee);

        if (creatorsTrustMultiplier[eventContract.creator()] > 0) {
            creatorsTrustMultiplier[eventContract.creator()] = -1;
        } else {
            // Prevent underflow
            if (creatorsTrustMultiplier[eventContract.creator()] > type(int256).min + 1) {
                creatorsTrustMultiplier[eventContract.creator()] -= 1;
            }
        }

        // Transfer collateral to protocol fee recipient
        protocolToken.safeTransfer(protocolFeeRecipient, protocolDisputeFee);

        // Burn remaining collateral
        protocolToken.safeTransfer(address(0), amount - (2 * protocolDisputeFee));

        closeEvent(_eventAddress);
        emit CollateralForfeited(_eventAddress, amount);
    }

    /**
     * @notice Initializes the trust multiplier for a creator.
     */
    function initializeCreatorMultiplier(address creator) internal {
        if (creatorsTrustMultiplier[creator] == int256(0)) {
            creatorsTrustMultiplier[creator] = 1;
        }
    }

    /**
     * @notice Computes the betting limit for an event.
     */
    function computeBetLimit(address creator, uint256 collateralAmount) external view returns (uint256) {
        int256 creatorMultiplier = creatorsTrustMultiplier[creator];

        if (creatorMultiplier <= -1) {
            require(creatorMultiplier > type(int256).min, "Creator multiplier too low");
            uint256 divisor = uint256(-creatorMultiplier);
            require(divisor > 0, "Invalid divisor");
            return collateralAmount / divisor;
        } else if (creatorMultiplier == 0) {
            return bettingMultiplier * collateralAmount;
        }
        return uint256(creatorMultiplier) * bettingMultiplier * collateralAmount;
    }

    /**
     * @notice Allows governance to set a new betting multiplier.
     */
    function setBettingMultiplier(uint256 _newMultiplier) external onlyOwner {
        require(_newMultiplier > 0, "Multiplier must be greater than zero");
        bettingMultiplier = _newMultiplier;
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
     */
    function transferGovernance(address _newGovernance) external onlyOwner {
        require(_newGovernance != address(0), "Invalid address");
        governance = Governance(_newGovernance);
    }

    /**
     * @notice Increases the creator's trust multiplier.
     */
    function increaseCreatorsTrustMultiplier(address creator, uint256 amount) external onlyOwner {
        initializeCreatorMultiplier(creator);
        int256 newMultiplier = creatorsTrustMultiplier[creator] + int256(amount);
        creatorsTrustMultiplier[creator] = newMultiplier;
    }

    /**
     * @notice Decreases the creator's trust multiplier.
     */
    function decreaseCreatorsTrustMultiplier(address creator, uint256 amount) external onlyOwner {
        initializeCreatorMultiplier(creator);
        int256 newMultiplier = creatorsTrustMultiplier[creator] - int256(amount);
        require(newMultiplier > type(int256).min, "Underflow error");
        creatorsTrustMultiplier[creator] = newMultiplier;
    }
}
