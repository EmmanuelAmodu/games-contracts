// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Event} from "./Event.sol";
import "./Governance.sol";

contract CollateralManager is ReentrancyGuard {
    address public protocolFeeRecipient;
    uint256 public bettingMultiplier = 5;

    IERC20 public collateralToken;

    // Mapping from event address to collateral amount
    mapping(address => uint256) public collateralBalances; // Key: eventAddress
    mapping(address => bool) public isCollateralLocked; // Key: eventAddress
    mapping(address => int256) public creatorsTrustMultiplier; // Key: creator

    // For simplicity, assume protocol fee recipient can manage disputes
    Governance public governance;

    event CollateralLocked(address indexed eventAddress, uint256 amount);
    event CollateralReleased(address indexed eventAddress, uint256 amount);
    event CollateralForfeited(address indexed eventAddress, uint256 amount);
    event EventClosed(address indexed eventAddress);

    modifier onlyOwner() {
        require(
            msg.sender == governance.owner(),
            "CollateralManager: Only owner can call"
        );
        _;
    }

    modifier onlyApprovedAdmin() {
        require(
            governance.approvedAdmins(msg.sender),
            "CollateralManager: Only approved admin can call"
        );
        _;
    }

    modifier onlyEventCreator(address _eventAddress) {
        require(
            msg.sender == Event(_eventAddress).creator(),
            "CollateralManager: Only event creator can call"
        );
        _;
    }

    constructor(
        address _collateralToken,
        address _governance,
        address _protocolFeeRecipient
    ) {
        protocolFeeRecipient = _protocolFeeRecipient;
        collateralToken = IERC20(_collateralToken);
        governance = Governance(_governance);
    }

    /**
     * @notice Closes an event on behalf of the event creator.
     * @param _eventAddress The address of the event contract.
     */
    function closeEvent(
        address _eventAddress
    ) internal {
        Event eventContract = Event(_eventAddress);

        // Ensure the event is still open and the end time has passed
        require(
            eventContract.status() == Event.EventStatus.Resolved ||
                eventContract.status() == Event.EventStatus.Cancelled,
            "Event is not resolved or cancelled"
        );

        if (eventContract.status() == Event.EventStatus.Resolved)
            eventContract.closeEvent();

        emit EventClosed(_eventAddress);
    }

    /**
     * @notice Locks collateral for a specific event.
     * @param _eventAddress The address of the event contract.
     * @param _creator The address of the event creator.
     * @param _amount The amount of collateral to lock.
     */
    function lockCollateral(
        address _eventAddress,
        address _creator,
        uint256 _amount
    ) external {
        require(
            !isCollateralLocked[_eventAddress],
            "Collateral already locked for this event"
        );

        // Transfer collateral tokens from the creator to this contract
        collateralToken.transferFrom(_creator, address(this), _amount);

        collateralBalances[_eventAddress] += _amount;
        isCollateralLocked[_eventAddress] = true;

        emit CollateralLocked(_eventAddress, _amount);
    }

    /**
     * @notice Increases the locked collateral for a specific event.
     * @param _eventAddress The address of the event contract.
     * @param _amount The amount of additional collateral to lock.
     */
    function increaseCollateral(
        address _eventAddress,
        uint256 _amount
    ) public onlyEventCreator(_eventAddress) {
        require(
            isCollateralLocked[_eventAddress],
            "No collateral locked for this event"
        );

        // Transfer additional collateral tokens from the creator to this contract
        collateralToken.transferFrom(
            Event(_eventAddress).creator(),
            address(this),
            _amount
        );
        collateralBalances[_eventAddress] += _amount;

        Event(_eventAddress).setBetLimit(collateralBalances[_eventAddress]);

        emit CollateralLocked(_eventAddress, _amount);
    }

    /**
     * @notice Allows the event creator to claim the locked collateral after the event is resolved.
     * @param _eventAddress The address of the event contract.
     */
    function claimCollateral(
        address _eventAddress
    ) external onlyEventCreator(_eventAddress) nonReentrant {
        Event _event = Event(_eventAddress);
        require(
            block.timestamp > _event.disputeDeadline(),
            "Dispute period not over"
        );

        // Ensure the event is resolved or canceled
        require(
            _event.status() == Event.EventStatus.Resolved ||
                _event.status() == Event.EventStatus.Cancelled,
            "Event is not resolved or canceled"
        );

        // Transfer fee to governance and creator
        uint256 fee = _event.calculateFee();
        _event.bettingToken().transfer(protocolFeeRecipient, fee / 2);
        _event.bettingToken().transfer(_event.creator(), fee / 2);

        // Release collateral to the creator
        releaseCollateral(_eventAddress);
    }

    /**
     * @notice Allows the event creator to cancel an open event.
     * @param _eventAddress The address of the event contract.
     */
    function cancelEvent(
        address _eventAddress
    ) external onlyEventCreator(_eventAddress) nonReentrant {
        Event _event = Event(_eventAddress);
        require(
            _event.status() == Event.EventStatus.Open,
            "Can only cancel open events"
        );

        _event.cancelEvent();

        // Release collateral back to the creator
        releaseCollateral(_eventAddress);
    }

    /**
     * @notice Allows governance to resolve a dispute.
     * @param _eventAddress The address of the event contract.
     * @param _finalOutCome The final outcome of the event.
     */
    function resolveDispute(
        address _eventAddress,
        uint256 _finalOutCome
    ) external onlyApprovedAdmin nonReentrant {
        Event _event = Event(_eventAddress);
        require(
            _event.disputeStatus() == Event.DisputeStatus.Disputed,
            "Event is not disputed"
        );

        // Update the dispute status in the Event contract before proceeding
        _event.resolveDispute(_finalOutCome);

        // Now you can safely release or forfeit collateral
        if (_finalOutCome != _event.winningOutcome()) {
            forfeitCollateral(_eventAddress);
        } else {
            releaseCollateral(_eventAddress);
        }
    }

    /**
     * @notice Releases collateral back to the event creator.
     * @param _eventAddress The address of the event contract.
     */
    function releaseCollateral(address _eventAddress) internal {
        Event eventContract = Event(_eventAddress);
        uint256 amount = collateralBalances[_eventAddress];

        require(
            eventContract.disputeStatus() != Event.DisputeStatus.Disputed,
            "Cannot release collateral during dispute"
        );
        require(
            isCollateralLocked[_eventAddress],
            "No collateral to release for this event"
        );
        require(amount > 0, "No collateral balance for this event");

        collateralBalances[_eventAddress] = 0;
        isCollateralLocked[_eventAddress] = false;
        creatorsTrustMultiplier[eventContract.creator()] =
            creatorsTrustMultiplier[eventContract.creator()] +
            1;

        // Transfer collateral back to the creator
        collateralToken.transfer(Event(_eventAddress).creator(), amount);

        closeEvent(_eventAddress);
        emit CollateralReleased(_eventAddress, amount);
    }

    /**
     * @notice Forfeits the event's collateral in case of a valid dispute.
     * @param _eventAddress The address of the event contract.
     */
    function forfeitCollateral(address _eventAddress) internal {
        Event eventContract = Event(_eventAddress);
        require(
            isCollateralLocked[_eventAddress],
            "No collateral to forfeit for this event"
        );
        uint256 amount = collateralBalances[_eventAddress];
        require(amount > 0, "No collateral balance for this event");

        collateralBalances[_eventAddress] = 0;
        isCollateralLocked[_eventAddress] = false;

        // Transfer collateral to dispute creator
        uint256 protocolDisputeFee = amount / 10;
        if (
            Event(_eventAddress).disputeStatus() == Event.DisputeStatus.Disputed
        ) {
            collateralToken.transfer(
                Event(_eventAddress).disputingUser(),
                protocolDisputeFee
            );
        }

        if (creatorsTrustMultiplier[eventContract.creator()] > 0) {
            creatorsTrustMultiplier[eventContract.creator()] = -1;
        } else {
            creatorsTrustMultiplier[eventContract.creator()] =
                creatorsTrustMultiplier[eventContract.creator()] -
                1;
        }

        // Transfer collateral to protocol fee recipient
        collateralToken.transfer(protocolFeeRecipient, protocolDisputeFee);

        // Burn remaining collateral
        collateralToken.transfer(address(0), amount - (2 * protocolDisputeFee));

        closeEvent(_eventAddress);
        emit CollateralForfeited(_eventAddress, amount);
    }

    /**
     * @notice Returns the betting multiplier.
     */
    function computeBetLimit(
        address creator,
        uint256 collateralAmount
    ) external view returns (uint256) {
        int256 creatorMultiplier = creatorsTrustMultiplier[creator];

        if (creatorMultiplier < -1)
            return collateralAmount / uint256(creatorMultiplier * -1);
        else if (creatorMultiplier == -1) return collateralAmount;
        else if (creatorMultiplier == 0)
            return bettingMultiplier * collateralAmount;
        return
            uint256(creatorMultiplier) * bettingMultiplier * collateralAmount;
    }

    /**
     * @notice Allows governance to set a new betting multiplier.
     * @param _newMultiplier The new betting multiplier.
     */
    function setBettingMultiplier(uint256 _newMultiplier) external onlyOwner {
        require(_newMultiplier > 0, "Multiplier must be greater than zero");
        bettingMultiplier = _newMultiplier;
    }

    /**
     * @notice Allows governance to update the protocol fee recipient.
     * @param _newRecipient The address of the new fee recipient.
     */
    function setProtocolFeeRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid address");
        protocolFeeRecipient = _newRecipient;
    }

    /**
     * @notice Allows governance to transfer governance rights.
     * @param _newGovernance The address of the new governance.
     */
    function transferGovernance(address _newGovernance) external onlyOwner {
        require(_newGovernance != address(0), "Invalid address");
        governance = Governance(_newGovernance);
    }
}
