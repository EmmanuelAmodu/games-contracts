// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Event} from "./Event.sol";

contract CollateralManager {
    // address public protocolFeeRecipient;
    uint256 private _bettingMultiplier = 5; // Example multiplier

    IERC20 public collateralToken;

    // Mapping from event address to collateral amount
    mapping(address => uint256) public collateralBalances; // Key: eventAddress
    mapping(address => bool) public isCollateralLocked; // Key: eventAddress
    mapping(address => uint256) public trustedCreatorsMultiplier; // Key: creator

    // For simplicity, assume protocol fee recipient can manage disputes
    address public governance;

    event CollateralLocked(address indexed eventAddress, uint256 amount);
    event CollateralReleased(address indexed eventAddress, uint256 amount);
    event CollateralForfeited(address indexed eventAddress, uint256 amount);
    event EventClosed(address indexed eventAddress);

    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance can call");
        _;
    }

    modifier onlyEventCreator(address _eventAddress) {
        require(
            msg.sender == Event(_eventAddress).creator(),
            "Only event creator can call"
        );
        _;
    }

    modifier onlyEvent(address _eventAddress) {
        require(
            msg.sender == _eventAddress,
            "Only event contract can call"
        );
        _;
    }

    constructor(address _collateralToken, address _governance) {
        // protocolFeeRecipient = _protocolFeeRecipient;
        collateralToken = IERC20(_collateralToken);
        governance = _governance;
    }

    /**
     * @notice Closes an event on behalf of the event creator.
     * @param _eventAddress The address of the event contract.
     */
    function closeEvent(
        address _eventAddress
    ) internal onlyEventCreator(_eventAddress) {
        Event eventContract = Event(_eventAddress);

        // Ensure the event is still open and the end time has passed
        require(
            eventContract.status() == Event.EventStatus.Resolved,
            "Event is not resolved"
        );
        require(
            block.timestamp > eventContract.endTime(),
            "Event has not ended yet"
        );

        // Call closeEvent on the Event contract
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
    ) external onlyEventCreator(_eventAddress) {
        Event _event = Event(_eventAddress);
        require(
            block.timestamp > _event.disputeDeadline(),
            "Dispute period not over"
        );
        require(
            _event.status() == Event.EventStatus.Resolved,
            "Event is not resolved"
        );

        // Transfer fee to governance and creator
        uint256 fee = _event.calculateFee();
        _event.bettingToken().transfer(governance, fee / 2);
        _event.bettingToken().transfer(_event.creator(), fee / 2);

        // Release collateral to the creator
        releaseCollateral(address(this));
    }

    function cancelEvent(
        address _eventAddress
    ) external onlyEventCreator(_eventAddress) {
        Event _event = Event(_eventAddress);
        require(
            _event.status() == Event.EventStatus.Open,
            "Can only cancel open events"
        );

        _event.cancelEvent();

        // Release collateral back to the creator
        releaseCollateral(_eventAddress);
    }

    function resolveDsipute(address _eventAddress, uint256 _finalOutCome) external onlyGovernance {
        Event _event = Event(_eventAddress);
        require(
            _event.disputeStatus() == Event.DisputeStatus.Disputed,
            "Event is not disputed"
        );

        if (_finalOutCome != _event.winningOutcome()) {
            forfeitCollateral(_eventAddress);
        }

        _event.resolveDispute(_finalOutCome);

        // Release collateral back to the creator
        releaseCollateral(_eventAddress);
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
                amount / 10
            );
            amount = amount - protocolDisputeFee;
        }

        // Transfer collateral to protocol fee recipient
        collateralToken.transfer(governance, protocolDisputeFee);
        amount = amount - protocolDisputeFee;

        // Burn remaining collateral
        collateralToken.transfer(address(0), amount);

        closeEvent(_eventAddress);
        emit CollateralForfeited(_eventAddress, amount);
    }

    /**
     * @notice Returns the betting multiplier.
     */
    function bettingMultiplier(
        address creator
    ) external view returns (uint256) {
        if (trustedCreatorsMultiplier[creator] > 0)
            return trustedCreatorsMultiplier[creator];
        return _bettingMultiplier;
    }

    /**
     * @notice Allows governance to set a new betting multiplier.
     * @param _newMultiplier The new betting multiplier.
     */
    function setBettingMultiplier(
        uint256 _newMultiplier
    ) external onlyGovernance {
        require(_newMultiplier > 0, "Multiplier must be greater than zero");
        _bettingMultiplier = _newMultiplier;
    }

    // /**
    //  * @notice Allows governance to update the protocol fee recipient.
    //  * @param _newRecipient The address of the new fee recipient.
    //  */
    // function setProtocolFeeRecipient(address _newRecipient) external onlyGovernance {
    //     require(_newRecipient != address(0), "Invalid address");
    //     protocolFeeRecipient = _newRecipient;
    // }

    /**
     * @notice Allows governance to transfer governance rights.
     * @param _newGovernance The address of the new governance.
     */
    function transferGovernance(
        address _newGovernance
    ) external onlyGovernance {
        require(_newGovernance != address(0), "Invalid address");
        governance = _newGovernance;
    }
}
