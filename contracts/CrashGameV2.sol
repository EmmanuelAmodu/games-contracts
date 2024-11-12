// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Import OpenZeppelin contracts for security and access control
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title On-Chain Crash Game
/// @notice This contract implements an on-chain crash game where players can place bets and cash out before the game crashes.
/// @dev This contract is for educational purposes and has not been audited.
contract CrashGameV2 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // Struct to store player bets
    struct Bet {
        address player;
        uint256 amount;
        address token;
        string gameHash;
        uint256 intendedMultiplier; // Scaled by 100 (e.g., 250 represents 2.50x)
        uint256 multiplier;         // Final multiplier achieved
        bool claimed;
        bool isWon;
        uint256 cashOutMultiplier;  // Multiplier at which the user cashed out
        uint256 cashOutTime;        // Timestamp when the user cashed out
        bool cashedOut;             // Indicates if the user has cashed out
    }

    // Mapping from token address to maximum payout amount
    mapping(address => uint256) public tokenMaximumPayout;

    // Mapping from token address to maximum bet amount
    mapping(address => uint256) public tokenMaximumBet;

    // Mapping from token address to minimum bet amount
    mapping(address => uint256) public tokenMinimumBet;

    // Mapping from token address to supported status
    mapping(address => bool) public tokenSupported;

    mapping(string => bool) public revealInitiated;

    // Mapping from token address to user winnings
    mapping(address => uint256) private userWinnings;

    // Mapping from token address to user losses
    mapping(address => uint256) private userLosses;

    // Mapping from game hash to player bets
    mapping(string => mapping(address => Bet)) public bets;

    // Mapping from game hash to participants
    mapping(string => address[]) public participants;

    // Array of all game hashes
    string[] public gameHashes;

    // Mapping from gameHash to result multiplier
    mapping(string => uint256) public result;

    // Current game hash
    string public currentGameHash;

    // Max multiplier
    uint256 public constant MAX_INTENDED_MULTIPLIER = 10000; // Represents 100x

    // Mapping from gameHash to reveal deadline
    mapping(string => uint256) public revealDeadline;

    // Mapping from game hash to game start time
    mapping(string => uint256) public gameStartTime;

    // Constant time window for revealing the game
    uint256 public constant REVEAL_TIME_WINDOW = 10 minutes;

    // Multiplier rate per second (scaled by 100)
    uint256 public MULTIPLIER_RATE = 5; // Multiplier increases by 0.05x per second

    // Events
    event GameStarted(string indexed gameHash);
    event BetPlaced(address indexed player, uint256 amount, string indexed gameHash);
    event Payout(address indexed player, uint256 amount, string indexed gameHash);
    event Refunded(address indexed player, uint256 amount, string indexed gameHash);
    event GameRevealed(string indexed gameHash, uint256 multiplier);
    event CashOut(address indexed player, uint256 multiplier, string indexed gameHash);

    /// @notice Initialize the contract with the owner address.
    /// @param initialOwner The address of the owner of the contract.
    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        // Initialize the first game hash with a unique and unpredictable value
        currentGameHash = "";
        gameHashes.push(currentGameHash);
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

    /// @notice Starts a new game by setting a unique game hash.
    /// @param _gameHash The unique identifier for the game.
    function startGame(string calldata _gameHash) external onlyOwner whenNotPaused {
        require(result[currentGameHash] > 0, "Previous game not resolved");
        currentGameHash = _gameHash;
        gameStartTime[currentGameHash] = block.timestamp;
        revealDeadline[currentGameHash] = block.timestamp + REVEAL_TIME_WINDOW;
        gameHashes.push(currentGameHash);
        
        emit GameStarted(currentGameHash);
    }

    /// @notice Allows a player to place a bet on the current game.
    /// @param amount The amount of tokens to bet.
    /// @param intendedMultiplier The multiplier the player aims to achieve (scaled by 100).
    /// @param token The address of the token to use for betting.
    function placeBet(uint256 amount, uint256 intendedMultiplier, address token) external payable nonReentrant whenNotPaused {
        require(bytes(currentGameHash).length != 0, "No active game");
        require(tokenSupported[token], "Token not supported");
        require(intendedMultiplier >= 100, "Multiplier must be at least 1.00x");
        require(amount >= tokenMinimumBet[token], "Bet amount is less than minimum bet");
        require(amount <= tokenMaximumBet[token], "Bet amount exceeds maximum bet");
        require(intendedMultiplier <= MAX_INTENDED_MULTIPLIER, "Multiplier must be less than or equal to 100x");

        if (token == address(0)) {
            require(msg.value == amount, "Invalid ETH amount");
        } else {
            // Transfer tokens from the player to the contract
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Ensure the player hasn't already placed a bet for this game
        Bet storage existingBet = bets[currentGameHash][msg.sender];
        require(existingBet.player == address(0), "Bet already placed");

        bets[currentGameHash][msg.sender] = Bet({
            player: msg.sender,
            amount: amount,
            token: token,
            gameHash: currentGameHash,
            intendedMultiplier: intendedMultiplier,
            multiplier: 0, // To be set when resolved
            claimed: false,
            isWon: false,
            cashOutMultiplier: 0,
            cashOutTime: 0,
            cashedOut: false
        });

        participants[currentGameHash].push(msg.sender);
        emit BetPlaced(msg.sender, amount, currentGameHash);
    }

    /// @notice Get the current multiplier for a specific game.
    /// @param gameHash The unique game-specific hash.
    function getCurrentMultiplier(string calldata gameHash) public view returns (uint256) {
        uint256 startTime = gameStartTime[gameHash];
        require(startTime > 0, "Game not started yet");
        uint256 elapsedTime = block.timestamp - startTime;
        uint256 currentMultiplier = 100 + (elapsedTime * MULTIPLIER_RATE);
        return currentMultiplier;
    }

    /// @notice Allows a player to cash out their bet at the current multiplier.
    /// @param gameHash The unique game-specific hash.
    function cashOut(string calldata gameHash) external nonReentrant whenNotPaused {
        require(!revealInitiated[gameHash], "Reveal initiated, cannot cash out");
        require(gameStartTime[gameHash] > 0, "Game not started yet");
        require(result[gameHash] == 0, "Game already revealed");

        Bet storage bet = bets[gameHash][msg.sender];
        require(bet.player == msg.sender, "Not your bet");
        require(!bet.claimed, "Bet already claimed or cashed out");
        require(!bet.cashedOut, "Already cashed out");

        uint256 currentMultiplier = getCurrentMultiplier(gameHash);
        require(currentMultiplier <= bet.intendedMultiplier, "Cannot cash out at higher multiplier than intended");

        bet.cashOutMultiplier = currentMultiplier;
        bet.cashOutTime = block.timestamp;
        bet.cashedOut = true;

        emit CashOut(msg.sender, currentMultiplier, gameHash);
    }

    /// @notice Returns the bets placed by all players for a specific game.
    /// @param gameHash The unique game-specific hash.
    /// @param start The start index of the bets array.
    /// @param end The end index of the bets array.
    /// @return playerBets An array of Bet structs representing the bets placed.
    function getBets(string calldata gameHash, uint256 start, uint256 end) external view returns (Bet[] memory) {
        address[] memory players = participants[gameHash];
        require(end <= players.length, "Invalid end index");
        Bet[] memory playerBets = new Bet[](end - start);
        for (uint256 i = start; i < end; i++) {
            address player = players[i];
            playerBets[i - start] = bets[gameHash][player];
        }
        return playerBets;
    }

    /// @notice Returns the bet placed by a specific player for a specific game.
    /// @param gameHash The unique game-specific hash.
    /// @param player The address of the player who placed the bet.
    /// @return bet A Bet struct representing the bet placed by the player.
    function getBet(string calldata gameHash, address player) external view returns (Bet memory) {
        return bets[gameHash][player];
    }

    /// @notice Initiates the reveal process for the specified game to prevent front-running attacks.
    /// @param gameHash The unique game-specific hash.
    function initiateReveal(string calldata gameHash) external onlyOwner whenNotPaused {
        revealInitiated[gameHash] = true;
    }

    /// @notice Allows the owner to reveal the multiplier for the current game.
    /// @param multiplier The multiplier to set for the current game (scaled by 100).
    function revealGame(uint256 multiplier) external onlyOwner whenNotPaused {
        require(bytes(currentGameHash).length != 0, "No active game");
        require(block.timestamp <= revealDeadline[currentGameHash], "Reveal deadline passed");
        require(multiplier >= 100, "Multiplier must be at least 1.00x");

        // Update the game result
        result[currentGameHash] = multiplier;
        emit GameRevealed(currentGameHash, multiplier);
    }

    /// @notice Pays out the winning bets for the specified game.
    /// @param gameHash The unique game-specific hash.
    function payWinningBets(string calldata gameHash) external onlyOwner whenNotPaused {
        for (uint256 i = 0; i < participants[gameHash].length; i++) {
            address player = participants[gameHash][i];
            Bet storage bet = bets[gameHash][player];
            if (bet.amount > 0) {
                payout(bet);
            }
        }
    }

    /// @notice Allows users to refund their bet after the reveal deadline has passed.
    /// @param gameHash The unique game-specific hash.
    function refundBet(string calldata gameHash) external nonReentrant whenNotPaused {
        require(block.timestamp > revealDeadline[gameHash], "Reveal deadline not passed");
        Bet storage bet = bets[gameHash][msg.sender];
        require(!bet.claimed, "Bet already claimed or refunded");

        bet.claimed = true;

        if (bet.token == address(0)) {
            (bool success, ) = msg.sender.call{value: bet.amount}("");
            require(success, "Failed to send Ether");
        } else {
            IERC20(bet.token).safeTransfer(msg.sender, bet.amount);
        }

        emit Refunded(msg.sender, bet.amount, gameHash);
    }

    /// @notice Allows users to claim their payout after the bet is resolved and they have won.
    /// @param gameHash The unique game-specific hash.
    function claimPayout(string calldata gameHash) external nonReentrant whenNotPaused returns (Bet memory betData) {
        Bet storage bet = bets[gameHash][msg.sender];
        require(bet.player == msg.sender, "Not your bet");
        require(!bet.claimed, "Payout already claimed");
        require(result[gameHash] > 0, "Game not resolved yet");

        payout(bet);
        betData = bet;
    }

    /// @notice Internal function to handle the payout logic for a specific bet.
    /// @param bet The Bet struct representing the player's bet.
    function payout(Bet storage bet) internal {
        if (!bet.claimed) {
            uint256 crashMultiplier = result[bet.gameHash];
            uint256 payoutMultiplier;
            if (bet.cashedOut) {
                payoutMultiplier = bet.cashOutMultiplier;
            } else {
                payoutMultiplier = bet.intendedMultiplier;
            }

            if (payoutMultiplier <= crashMultiplier) {
                // Player wins
                uint256 payoutAmount = (bet.amount * payoutMultiplier) / 100;
                if (payoutAmount > tokenMaximumPayout[bet.token]) {
                    payoutAmount = tokenMaximumPayout[bet.token];
                }
                bet.claimed = true;
                bet.isWon = true;
                bet.multiplier = payoutMultiplier;
                userWinnings[bet.token] += payoutAmount;

                // Transfer payout to player
                if (bet.token == address(0)) {
                    (bool success, ) = bet.player.call{value: payoutAmount}("");
                    require(success, "Failed to send Ether");
                } else {
                    IERC20(bet.token).safeTransfer(bet.player, payoutAmount);
                }
                emit Payout(bet.player, payoutAmount, bet.gameHash);
            } else {
                // Player loses
                bet.claimed = true;
                bet.isWon = false;
                bet.multiplier = payoutMultiplier;
                userLosses[bet.token] += bet.amount;
            }
        }
    }
    
    /// @notice Allows the contract owner to withdraw protocol tokens from the contract.
    /// @param amount The amount of tokens to withdraw.
    /// @param token The address of the token to withdraw.
    function withdrawProtocolRevenue(uint256 amount, address token) external onlyOwner nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        uint256 netProfit = userLosses[token] - userWinnings[token];
        require(amount <= netProfit, "Amount exceeds net profit");

        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Failed to send Ether");
        } else {
            require(IERC20(token).balanceOf(address(this)) >= amount, "Insufficient token balance");
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    /// @notice Allows the owner to set the maximum payout and minimum bet for a token.
    /// @param token The address of the token to set the parameters for.
    /// @param _maximumPayout The new maximum payout amount.
    /// @param _minimumBetAmount The new minimum bet amount.
    function setWhitelistToken(address token, uint256 _maximumPayout, uint256 _minimumBetAmount) external onlyOwner {
        require(_maximumPayout > 0, "Invalid maximum payout");
        tokenMaximumPayout[token] = _maximumPayout;
        tokenMinimumBet[token] = _minimumBetAmount;
        tokenMaximumBet[token] = _maximumPayout / 10;
        tokenSupported[token] = true;
    }

    /// @notice Allows the owner to remove a token from the whitelist.
    /// @param token The address of the token to remove from the whitelist.
    function removeWhitelistToken(address token) external onlyOwner {
        tokenSupported[token] = false;
    }

    /// @notice Function to accept Ether.
    receive() external payable {}

    // Storage gap for upgradeability
    uint256[50] private __gap;
}
