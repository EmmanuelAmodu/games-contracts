// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Import OpenZeppelin Contracts
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./Lottery.sol";

/// @title LotteryFactory
/// @author Emmanuel Amodu
/// @notice This contract deploys Lottery contracts using CREATE2 for deterministic addresses.
contract LotteryFactory is Ownable {
    // Event emitted when a new Lottery contract is deployed
    event LotteryDeployed(
        address indexed lotteryAddress,
        address indexed owner,
        address indexed token,
        bytes32 salt,
        bytes32 winningNumbersHash
    );

    // Counter to ensure unique salts
    uint256 private deploymentCounter;

    // Mapping from salt to deployed Lottery address
    mapping(bytes32 => address) public lotteries;

    // Array of all deployed Lottery addresses
    address[] public allLotteries;

    // Address of the current Lottery contract
    address public currentLottery;

    /// @notice Constructor that sets the Factory owner
    /// @param initialOwner The address of the initial owner
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Deploys a new Lottery contract using CREATE2 with a unique salt
    /// @param token The ERC20 token address used in the Lottery
    /// @param _winningNumbersHash The hash of the winning numbers
    /// @return lotteryAddress The address of the deployed Lottery contract
    function deployLottery(
        address token,
        bytes32 _winningNumbersHash
    ) external onlyOwner returns (address lotteryAddress) {
        require(token != address(0), "Token address cannot be zero");
        require(_winningNumbersHash != bytes32(0), "Winning numbers hash cannot be zero");

        // Increment the deployment counter
        deploymentCounter += 1;

        // Encode the constructor arguments
        bytes memory bytecodeWithArgs = abi.encodePacked(
            type(Lottery).creationCode,
            abi.encode(owner(), token, _winningNumbersHash)
        );

        // Deploy the Lottery contract using CREATE2
        lotteryAddress = Create2.deploy(0, _winningNumbersHash, bytecodeWithArgs);

        // Store the deployed Lottery address
        lotteries[_winningNumbersHash] = lotteryAddress;
        allLotteries.push(lotteryAddress);

        currentLottery = lotteryAddress;
        emit LotteryDeployed(lotteryAddress, owner(), token, _winningNumbersHash, _winningNumbersHash);
    }

    /// @notice Computes the address of a Lottery contract to be deployed with given parameters
    /// @param token The ERC20 token address used in the Lottery
    /// @param _winningNumbersHash The hash of the winning numbers
    /// @return predicted The predicted address of the Lottery contract
    function getLotteryAddress(
        address token,
        bytes32 _winningNumbersHash
    ) external view returns (address predicted) {
        bytes memory bytecodeWithArgs = abi.encodePacked(
            type(Lottery).creationCode,
            abi.encode(owner(), token, _winningNumbersHash)
        );
        predicted = Create2.computeAddress(_winningNumbersHash, keccak256(bytecodeWithArgs), address(this));
    }

    /// @notice Checks if a Lottery contract has already been deployed with the given salt
    /// @param winningNumbersHash The unique salt used for deployment
    /// @return exists True if the contract exists, false otherwise
    function isLotteryDeployed(bytes32 winningNumbersHash) external view returns (bool exists) {
        address predicted = lotteries[winningNumbersHash];
        if (predicted != address(0)) {
            exists = predicted.code.length > 0;
        } else {
            exists = false;
        }
    }

    /// @notice Retrieves all deployed Lottery contract addresses
    /// @return lotteriesList An array of all Lottery contract addresses deployed by the factory
    function getAllLotteries() external view returns (address[] memory lotteriesList) {
        lotteriesList = allLotteries;
    }
}
