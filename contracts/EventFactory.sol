// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Event.sol";
import "./CollateralManager.sol";
import "./Governance.sol";

contract EventFactory {
    string public constant VERSION = "0.0.4";
    address public collateralManager;
    address[] public allEvents;
    address public bettingToken;
    Governance public governance;

    event EventCreated(address indexed eventAddress, address indexed creator, uint256 eventId);

    modifier onlyOwner() {
        require(msg.sender == governance.owner(), "CollateralManager: Only owner can call");
        _;
    }

    constructor(address _collateralManager, address _governance) {
        collateralManager = _collateralManager;
        governance = Governance(_governance);
    }

    function createEvent(
        string memory _title,
        string memory _description,
        string memory _category,
        string[] memory _outcomes,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _collateralAmount
    ) external returns (address eventAddress, uint256 eventId) {
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
            collateralManager,
            bettingToken
        );

        eventAddress = address(newEvent);

        // Transfer collateral from the creator to the CollateralManager for this event
        CollateralManager(collateralManager).lockCollateral(eventAddress, msg.sender, _collateralAmount);

        allEvents.push(eventAddress);

        emit EventCreated(eventAddress, msg.sender, eventId);
    }

    function getAllOpenEvents() external view returns (address[] memory) {
        uint256 openEventCount = 0;

        // First, count how many open events there are
        for (uint256 i = 0; i < allEvents.length; i++) {
            if (Event(allEvents[i]).status() == Event.EventStatus.Open) {
                openEventCount++;
            }
        }

        // Now, create an array of the correct size
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

    function getEvent(uint256 eventId) external view returns (address eventAddress) {
        require(eventId < allEvents.length, "Invalid event ID");
        return allEvents[eventId];
    }

    function setBettingToken(address _bettingToken) external onlyOwner {
        bettingToken = _bettingToken;
    }
}
