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
        bytes32 indexed winningNumbersHash
    );

    // Address of the ERC20 token used in the Lottery
    address public tokenAddress;

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
    /// @param _tokenAddress The address of the ERC20 token used in the Lottery
    constructor(address initialOwner, address _tokenAddress) Ownable(initialOwner) {
        tokenAddress = _tokenAddress;
    }

    /// @notice Deploys a new Lottery contract using CREATE2 with a unique salt
    /// @param _winningNumbersHash The hash of the winning numbers
    /// @return lotteryAddress The address of the deployed Lottery contract
    function deployLottery(bytes32 _winningNumbersHash) onlyOwner external returns (address lotteryAddress) {
        require(tokenAddress != address(0), "Token address cannot be zero");
        require(_winningNumbersHash != bytes32(0), "Winning numbers hash cannot be zero");

        // Increment the deployment counter
        deploymentCounter += 1;

        // Encode the constructor arguments
        bytes memory bytecodeWithArgs = abi.encodePacked(
            type(Lottery).creationCode,
            abi.encode(owner(), address(this), _winningNumbersHash, tokenAddress)
        );

        // Deploy the Lottery contract using CREATE2
        lotteryAddress = Create2.deploy(0, _winningNumbersHash, bytecodeWithArgs);

        // Store the deployed Lottery address
        lotteries[_winningNumbersHash] = lotteryAddress;
        allLotteries.push(lotteryAddress);

        currentLottery = lotteryAddress;
        emit LotteryDeployed(lotteryAddress, _winningNumbersHash);
    }

    /// @notice Ends the current Lottery by revealing the winning numbers
    /// @param salt The unique salt used for deployment
    /// @param numbers The winning numbers
    /// @param newRoot The new Merkle root of the winning numbers
    function endLottery(
        bytes32 salt,
        uint8[5] calldata numbers,
        bytes32 newRoot
    ) external onlyOwner {
        Lottery(currentLottery).revealWinningNumbers(salt, numbers, newRoot);
    }

    /// @notice Computes the address of a Lottery contract to be deployed with given parameters
    /// @param _winningNumbersHash The hash of the winning numbers
    /// @return predicted The predicted address of the Lottery contract
    function getLotteryAddress(
        bytes32 _winningNumbersHash
    ) external view returns (address predicted) {
        bytes memory bytecodeWithArgs = abi.encodePacked(
            type(Lottery).creationCode,
            abi.encode(owner(), address(this), _winningNumbersHash, tokenAddress)
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
    /// @param start The start index of the array
    /// @param end The end index of the array
    /// @return lotteriesList An array of all Lottery contract addresses deployed by the factory
    function getAllLotteries(uint256 start, uint256 end) external view returns (address[] memory) {
        // lotteriesList = allLotteries;
        uint256 length = end - start;
        address[] memory lotteriesList = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            lotteriesList[i] = allLotteries[start + i];
        }

        return lotteriesList;
    }
}
