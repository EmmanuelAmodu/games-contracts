// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Import OpenZeppelin contracts for security and access control
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Import Chainlink VRF contracts
import "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Upgradeable.sol";

// Import SafeERC20 for safe token transfers
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title On-Chain Crash Game with Chainlink VRF
/// @notice This contract implements an on-chain crash game using Chainlink VRF for randomness.
///         Players can place bets on the game by specifying the amount and intended multiplier.
///         The game outcome is determined by a verifiable random number from Chainlink VRF.
///         Players can claim their payout if they win.
///         The contract owner can manage tokens and withdraw protocol revenue.
contract CrashGame is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VRFConsumerBaseV2Upgradeable
{
    using SafeERC20 for IERC20;

    // Struct to store player bets
    struct Bet {
        address player;
        uint256 amount;
        address token;
        bytes32 gameId;
        uint256 intendedMultiplier; // Multiplier scaled by 100 (e.g., 250 represents 2.50x)
        uint256 multiplier;         // Game outcome multiplier
        bool claimed;
        bool isWon;
    }

    // Mapping from token address to maximum payout amount
    mapping(address => uint256) public tokenMaximumPayout;

    // Mapping from token address to maximum bet amount
    mapping(address => uint256) public tokenMaximumBet;

    // Mapping from token address to minimum bet amount
    mapping(address => uint256) public tokenMinimumBet;

    // Mapping from token address to supported status
    mapping(address => bool) public tokenSupported;

    // Mapping from token address to user winnings
    mapping(address => uint256) private userWinnings;

    // Mapping from token address to user losses
    mapping(address => uint256) private userLosses;

    // Mapping from gameId to player bets
    mapping(bytes32 => mapping(address => Bet)) public bets;

    // Mapping from gameId to participants
    mapping(bytes32 => address[]) public participants;

    // Array of all gameIds
    bytes32[] public gameIds;

    // Mapping from gameId to game result
    mapping(bytes32 => uint256) public gameResults;

    // Chainlink VRF variables
    bytes32 internal keyHash;
    uint256 internal fee;

    // Current gameId
    bytes32 public currentGameId;

    // Max intended multiplier
    uint256 public constant MAX_INTENDED_MULTIPLIER = 10000; // Represents 100x

    // Events
    event BetPlaced(address indexed player, uint256 amount, bytes32 gameId);
    event Payout(address indexed player, uint256 amount, bytes32 gameId);
    event GameResult(bytes32 indexed gameId, uint256 multiplier);
    event GameStarted(bytes32 indexed gameId);
    event GameReset(bytes32 oldGameId, bytes32 newGameId);

    /// @notice Initialize the contract with the owner address and Chainlink VRF parameters.
    /// @param initialOwner The address of the owner of the contract.
    /// @param vrfCoordinator The address of the Chainlink VRF Coordinator.
    /// @param linkToken The address of the LINK token.
    /// @param _keyHash The key hash provided by Chainlink.
    /// @param _fee The fee required to request randomness.
    function initialize(
        address initialOwner,
        address vrfCoordinator,
        address linkToken,
        bytes32 _keyHash,
        uint256 _fee
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __VRFConsumerBase_init(vrfCoordinator, linkToken);

        keyHash = _keyHash;
        fee = _fee;

        // Set the owner
        transferOwnership(initialOwner);

        // Initialize the first gameId
        currentGameId = keccak256(abi.encodePacked(block.timestamp, block.difficulty, block.number));
        gameIds.push(currentGameId);

        // Set default token parameters for Ether (address(0))
        tokenMaximumPayout[address(0)] = 10 ether;
        tokenMaximumBet[address(0)] = 1 ether;
        tokenMinimumBet[address(0)] = 0.01 ether;
        tokenSupported[address(0)] = true;
    }

    /// @notice Pause the contract, disabling certain functions.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract, enabling previously disabled functions.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Allows a player to place a bet on the current game.
    /// @param amount The amount to bet.
    /// @param intendedMultiplier The multiplier the player aims to achieve.
    /// @param token The address of the token to use for betting.
    function placeBet(
        uint256 amount,
        uint256 intendedMultiplier,
        address token
    ) external payable nonReentrant whenNotPaused {
        require(tokenSupported[token], "Token not supported");
        require(intendedMultiplier >= 101, "Multiplier must be at least 1.01x");
        require(intendedMultiplier <= MAX_INTENDED_MULTIPLIER, "Multiplier exceeds maximum");
        require(amount >= tokenMinimumBet[token], "Bet amount below minimum");
        require(amount <= tokenMaximumBet[token], "Bet amount exceeds maximum");

        if (token == address(0)) {
            require(msg.value == amount, "Incorrect Ether amount sent");
        } else {
            require(msg.value == 0, "Ether sent with token bet");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        Bet storage existingBet = bets[currentGameId][msg.sender];
        require(existingBet.player == address(0), "Bet already placed");

        bets[currentGameId][msg.sender] = Bet({
            player: msg.sender,
            amount: amount,
            token: token,
            gameId: currentGameId,
            intendedMultiplier: intendedMultiplier,
            multiplier: 0, // To be set when game result is available
            claimed: false,
            isWon: false
        });

        participants[currentGameId].push(msg.sender);
        emit BetPlaced(msg.sender, amount, currentGameId);
    }

    /// @notice Starts a new game by requesting randomness from Chainlink VRF.
    function startGame() external onlyOwner whenNotPaused returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        require(participants[currentGameId].length > 0, "No bets placed for the current game");

        requestId = requestRandomness(keyHash, fee);

        // Map requestId to currentGameId if necessary
        // In this implementation, we use currentGameId directly
    }

    /// @notice Callback function used by Chainlink VRF Coordinator to return the random number.
    /// @param requestId The ID of the randomness request.
    /// @param randomness The random number generated by Chainlink VRF.
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        // Compute the game result
        uint256 multiplier = computeMultiplier(randomness);
        gameResults[currentGameId] = multiplier;

        // Update bets with the result
        for (uint256 i = 0; i < participants[currentGameId].length; i++) {
            address player = participants[currentGameId][i];
            Bet storage bet = bets[currentGameId][player];
            bet.multiplier = multiplier;

            if (multiplier >= bet.intendedMultiplier) {
                bet.isWon = true;
            } else {
                bet.isWon = false;
                userLosses[bet.token] += bet.amount;
            }
        }

        emit GameResult(currentGameId, multiplier);

        // Prepare for the next game
        bytes32 oldGameId = currentGameId;
        currentGameId = keccak256(abi.encodePacked(randomness, block.timestamp, block.number));
        gameIds.push(currentGameId);

        emit GameStarted(currentGameId);
        emit GameReset(oldGameId, currentGameId);
    }

    /// @notice Computes the game multiplier based on the random number.
    /// @param randomNumber The random number generated by Chainlink VRF.
    /// @return multiplier The crash multiplier scaled by 100 (e.g., 250 represents 2.50x).
    function computeMultiplier(uint256 randomNumber) internal pure returns (uint256 multiplier) {
        // Map the random number to a multiplier between 1.00x and 100.00x
        // Example logic: multiplier = 100 + (randomNumber % 9900); // Multiplier ranges from 100 to 10000
        // Ensure that the multiplier is at least 1.00x (100)
        multiplier = 100 + (randomNumber % 9900); // Multiplier ranges from 100 to 10000 (1.00x to 100.00x)
    }

    /// @notice Allows players to claim their payout after the game result is available.
    /// @param gameId The unique identifier of the game.
    function claimPayout(bytes32 gameId) external nonReentrant whenNotPaused {
        Bet storage bet = bets[gameId][msg.sender];
        require(bet.player == msg.sender, "Bet not found");
        require(!bet.claimed, "Payout already claimed");
        require(gameResults[gameId] > 0, "Game result not available");

        bet.claimed = true;

        if (bet.isWon) {
            uint256 payoutAmount = (bet.amount * bet.intendedMultiplier) / 100;
            uint256 maximumPayout = tokenMaximumPayout[bet.token];
            if (payoutAmount > maximumPayout) {
                payoutAmount = maximumPayout;
            }

            userWinnings[bet.token] += payoutAmount;

            if (bet.token == address(0)) {
                require(address(this).balance >= payoutAmount, "Insufficient Ether balance");
                (bool success, ) = payable(msg.sender).call{value: payoutAmount}("");
                require(success, "Ether transfer failed");
            } else {
                require(IERC20(bet.token).balanceOf(address(this)) >= payoutAmount, "Insufficient token balance");
                IERC20(bet.token).safeTransfer(msg.sender, payoutAmount);
            }

            emit Payout(msg.sender, payoutAmount, gameId);
        } else {
            // Player lost; no payout
        }
    }

    /// @notice Returns the bet placed by a specific player for a specific game.
    /// @param gameId The unique identifier of the game.
    /// @param player The address of the player who placed the bet.
    /// @return bet A Bet struct representing the bet placed by the player.
    function getBet(bytes32 gameId, address player) external view returns (Bet memory) {
        return bets[gameId][player];
    }

    /// @notice Allows the owner to withdraw protocol revenue.
    /// @param amount The amount to withdraw.
    /// @param token The address of the token to withdraw.
    function withdrawProtocolRevenue(uint256 amount, address token) external onlyOwner nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        uint256 netProfit = userLosses[token] - userWinnings[token];
        require(amount <= netProfit, "Amount exceeds net profit");

        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient Ether balance");
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "Ether transfer failed");
        } else {
            require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /// @notice Allows the owner to set the parameters for a supported token.
    /// @param token The address of the token.
    /// @param _maximumPayout The maximum payout amount.
    /// @param _minimumBetAmount The minimum bet amount.
    /// @param _maximumBetAmount The maximum bet amount.
    function setTokenParameters(
        address token,
        uint256 _maximumPayout,
        uint256 _minimumBetAmount,
        uint256 _maximumBetAmount
    ) external onlyOwner {
        require(_maximumPayout > 0, "Invalid maximum payout");
        require(_maximumBetAmount >= _minimumBetAmount, "Maximum bet must be >= minimum bet");

        tokenMaximumPayout[token] = _maximumPayout;
        tokenMinimumBet[token] = _minimumBetAmount;
        tokenMaximumBet[token] = _maximumBetAmount;
        tokenSupported[token] = true;
    }

    /// @notice Allows the owner to remove a token from the supported list.
    /// @param token The address of the token to remove.
    function removeSupportedToken(address token) external onlyOwner {
        tokenSupported[token] = false;
    }

    /// @notice Fallback function to receive Ether.
    receive() external payable {}

    /// @notice Withdraw LINK tokens from the contract (for owner only).
    /// @param amount The amount of LINK to withdraw.
    function withdrawLink(uint256 amount) external onlyOwner {
        require(LINK.balanceOf(address(this)) >= amount, "Insufficient LINK balance");
        LINK.transfer(owner(), amount);
    }
}
