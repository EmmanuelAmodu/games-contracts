// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Import OpenZeppelin contracts for security and access control
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title On-Chain Crash Game with Commit-Reveal Scheme
/// @notice This contract implements a simple on-chain crash game with a commit-reveal scheme.
///         Players can place bets on the game by specifying the amount and intended multiplier.
///         The game owner can commit to a new game's secret by providing a commitment hash.
///         After the reveal deadline has passed, the owner can reveal the secret to resolve the game.
///         Players can claim their payout if they win.
///         The contract owner can withdraw protocol revenue and set the maximum payout multiplier.
/// @dev This contract is for educational purposes only and has not been audited.
contract CrashGame is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Struct to store player bets
    struct Bet {
        address player;
        uint256 amount;
        address token;
        bytes32 gameHash;
        bytes32 resolvedHash;
        uint256 intendedMultiplier;
        uint256 multiplier; // Scaled by 100 (e.g., 250 represents 2.50x)
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

    // Mapping from game hash to player bets
    mapping(bytes32 => mapping(address => Bet)) public bets;

    // Mapping from game hash to participants
    mapping(bytes32 => address[]) public participants;

    // Array of all game hashes
    bytes32[] public gameHashes;

    // Mapping from gameHash to resolvedHash
    mapping(bytes32 => bytes32) public resolvedHashes;

    // Mapping from gameHash to commitment
    mapping(bytes32 => bytes32) public gameCommitments;

    // Mapping from gameHash to result multiplier
    mapping(bytes32 => uint256) public result;

    // Current game hash
    bytes32 public currentGameHash;

    // max multiplier
    uint256 public constant MAX_INTENDED_MULTIPLIER = 10000; // Represents 100x

    // Mapping from gameHash to reveal deadline
    mapping(bytes32 => uint256) public revealDeadline;

    // Constant time window for revealing the game
    uint256 public constant REVEAL_TIME_WINDOW = 10 minutes;

    // Events
    event GameCommitted(bytes32 indexed gameHash, bytes32 commitment);
    event BetPlaced(address indexed player, uint256 amount, bytes32 gameHash);
    event Payout(address indexed player, uint256 amount, bytes32 gameHash);
    event Refunded(address indexed player, uint256 amount, bytes32 gameHash);
    event GameRevealed(bytes32 indexed gameHash, uint256 multiplier, bytes32 hmac);
    event GameHashReset(bytes32 prevGameHash, bytes32 newGameHash);

    // Constructor to set the contract deployer as the owner and initialize parameters
    constructor(address initialOwner) Ownable(initialOwner) {
        // Initialize the first game hash with a unique and unpredictable value
        currentGameHash = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.number));
        gameHashes.push(currentGameHash);
        gameCommitments[currentGameHash] = bytes32(0); // No commitment yet
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

    /// @notice Allows the owner to commit to a new game's secret by providing a commitment hash.
    /// @param commitment The hash of the secret (e.g., keccak256(abi.encodePacked(secret))).
    function commitGame(bytes32 commitment) external onlyOwner {
        require(currentGameHash != bytes32(0), "Previous game not resolved");
        require(gameCommitments[currentGameHash] == bytes32(0), "Commitment already set");
        
        // Store the commitment for the current game
        gameCommitments[currentGameHash] = commitment;
        revealDeadline[currentGameHash] = block.timestamp + REVEAL_TIME_WINDOW;
        
        emit GameCommitted(currentGameHash, commitment);
    }

    /// @notice Allows a player to place a bet on the current committed game.
    /// @param amount The amount of protocol tokens to bet.
    /// @param intendedMultiplier The multiplier the player aims to achieve.
    /// @param token The address of the token to use for betting.
    function placeBet(uint256 amount, uint256 intendedMultiplier, address token) external payable nonReentrant whenNotPaused {
        require(currentGameHash != bytes32(0), "No game committed");
        require(gameCommitments[currentGameHash] != bytes32(0), "Game not yet committed");
        require(tokenMaximumPayout[token] > 0, "Token not supported");
        require(intendedMultiplier > 100, "multiplier must be greater than 1");
        require(amount >= tokenMinimumBet[token], "Bet amount is less than minimum bet");
        require(amount <= tokenMaximumBet[token], "Bet amount exceeds maximum bet");
        require(tokenSupported[token], "Token not supported");
        require(intendedMultiplier <= MAX_INTENDED_MULTIPLIER, "multiplier must be less then 100");

        if (token == address(0)) {
            require(msg.value == amount, "Invalid ETH amount");
        } else {
            require(amount > 0, "Invalid bet amount");
            // Transfer tokens from the player to the contract
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Record the bet with the current gameHash
        Bet storage existingBet = bets[currentGameHash][msg.sender];
        require(existingBet.player == address(0), "Bet already placed");

        bets[currentGameHash][msg.sender] = Bet({
            player: msg.sender,
            amount: amount,
            gameHash: currentGameHash,
            resolvedHash: bytes32(0),
            token: token,
            intendedMultiplier: intendedMultiplier,
            multiplier: 0, // To be set when resolved
            claimed: false,
            isWon: false
        });

        participants[currentGameHash].push(msg.sender);
        emit BetPlaced(msg.sender, amount, currentGameHash);
    }

    /// @notice Returns the bets placed by all players for a specific game.
    /// @param gameHash The unique game-specific hash used as the HMAC key.
    /// @param start The start index of the bets array.
    /// @param end The end index of the bets array.
    /// @return playerBets An array of Bet structs representing the bets placed.
    function getBets(bytes32 gameHash, uint256 start, uint256 end) external view returns (Bet[] memory) {
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
    /// @param gameHash The unique game-specific hash used as the HMAC key.
    /// @param player The address of the player who placed the bet.
    /// @return bet A Bet struct representing the bet placed by the player.
    function getBet(bytes32 gameHash, address player) external view returns (Bet memory) {
        return bets[gameHash][player];
    }

    /// @notice Allows the owner to reveal the secret for the current gameHash.
    /// @param secret The secret value used to generate the commitment.
    function revealGame(string memory secret) external onlyOwner whenNotPaused {
        require(currentGameHash != bytes32(0), "No active game");
        require(gameCommitments[currentGameHash] != bytes32(0), "No commitment found for this gameHash");
        require(block.timestamp <= revealDeadline[currentGameHash], "Reveal deadline passed");
        
        // Verify the commitment
        bytes32 computedCommitment = keccak256(abi.encodePacked(secret));
        bytes32 storedCommitment = gameCommitments[currentGameHash];
        require(computedCommitment == storedCommitment, "Commitment mismatch");
        
        // Compute the resolved hash
        bytes32 resolvedHash = keccak256(abi.encodePacked(currentGameHash, secret));
        
        // Calculate the multiplier using the resolved hash
        (uint256 multiplier, bytes32 hmac) = getResult(resolvedHash);
        
        // Update the game result
        result[currentGameHash] = multiplier;
        resolvedHashes[currentGameHash] = resolvedHash;

        emit GameRevealed(currentGameHash, multiplier, hmac);
        
        // Prepare for the next game by setting the new currentGameHash
        // Using the hmac as the new gameHash ensures linkage between games
        currentGameHash = hmac;
        gameHashes.push(currentGameHash);
        gameCommitments[currentGameHash] = bytes32(0); // No commitment yet
    }

    /// @notice Pays out the winning bets for the current game.
    /// @param gameHash The unique game-specific hash used as the HMAC key.
    function payWinningBets(bytes32 gameHash) external onlyOwner whenNotPaused {
        for (uint256 i = 0; i < participants[gameHash].length; i++) {
            address player = participants[gameHash][i];
            Bet storage bet = bets[gameHash][player];
            if (bet.amount > 0) {
                payout(bet);
            }
        }
    }

    /// @notice Allows users to refund their bet after the reveal deadline has passed.
    /// @param gameHash The unique game-specific hash used as the HMAC key.
    function refundBet(bytes32 gameHash) external nonReentrant whenNotPaused {
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
    /// @param gameHash The unique game-specific hash used as the HMAC key.
    function claimPayout(bytes32 gameHash) external nonReentrant whenNotPaused returns (Bet memory betData) {
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
            if (result[bet.gameHash] >= bet.intendedMultiplier) {
                uint256 maximumPayoutAdjusted = tokenMaximumPayout[bet.token];
                uint256 payoutAmount = bet.amount * bet.intendedMultiplier / 100;
                if (payoutAmount > maximumPayoutAdjusted) {
                    payoutAmount = maximumPayoutAdjusted;
                }

                bet.claimed = true;
                bet.isWon = true;
                bet.multiplier = result[bet.gameHash];
                bet.resolvedHash = resolvedHashes[bet.gameHash];
                userWinnings[bet.token] += payoutAmount;

                if (bet.token == address(0)) {
                    (bool success, ) = msg.sender.call{value: payoutAmount}("");
                    require(success, "Failed to send Ether");
                } else {
                    require(IERC20(bet.token).balanceOf(address(this)) >= payoutAmount, "Insufficient contract token balance");
                    IERC20(bet.token).safeTransfer(msg.sender, payoutAmount);
                }

                emit Payout(msg.sender, payoutAmount, bet.gameHash);
            } else {
                // Mark the bet as resolved but not won
                bet.claimed = true;
                bet.isWon = false;
                bet.multiplier = result[bet.gameHash];
                bet.resolvedHash = resolvedHashes[bet.gameHash];
                userLosses[bet.token] += bet.amount;
            }
        }
    }

    /// @notice Computes the crash multiplier based on the provided secure game hash.
    /// @param secureGameHash The secure game-specific hash used as the HMAC key.
    /// @return multiplier The crash multiplier scaled by 100 (e.g., 250 represents 2.50x).
    /// @return hmac The HMAC-SHA256 hash used for verification.
    function getResult(bytes32 secureGameHash) public pure returns (uint256 multiplier, bytes32 hmac) {
        // Compute HMAC-SHA256(secureGameHash)
        hmac = hmacSha256(secureGameHash, bytes(""));

        // Convert HMAC to uint256
        uint256 hmacInt = uint256(hmac);

        multiplier = 100;
        // Check if hmacInt modulo 33 equals 0
        // hmacInt % 33 == 0 represents a multiplier of 1.00x
        if (hmacInt % 33 == 0) {
            return (multiplier, hmac);
        }

        // Extract the first 52 bits from the HMAC
        uint256 h = hmacInt >> 204; // 256 - 52 = 204

        // Define e as 2^52
        uint256 e = 2**52;

        // Calculate ((100 * e - h) / (e - h))
        // To maintain precision, perform multiplication before division
        uint256 numerator = 100 * e - h;
        uint256 denominator = e - h;

        // Ensure denominator is not zero to prevent division by zero
        require(denominator != 0, "Denominator is zero");

        multiplier = numerator / denominator;
    }

    /// @notice Implements HMAC-SHA256 as per RFC 2104.
    /// @param key The secret key for HMAC.
    /// @param message The message to hash.
    /// @return hmac The resulting HMAC-SHA256 hash.
    function hmacSha256(bytes32 key, bytes memory message) internal pure returns (bytes32 hmac) {
        // Define block size for SHA256
        uint256 blockSize = 64; // 512 bits
    
        // Prepare the key
        bytes memory keyPadded = new bytes(blockSize);
        for (uint256 i = 0; i < blockSize; i++) {
            if (i < 32) {
                keyPadded[i] = key[i];
            } else {
                keyPadded[i] = 0x00; // Pad with zeros if key is shorter than block size
            }
        }
    
        // Define opad and ipad
        bytes memory opad = new bytes(blockSize);
        bytes memory ipad = new bytes(blockSize);
        for (uint256 i = 0; i < blockSize; i++) {
            opad[i] = 0x5c;
            ipad[i] = 0x36;
        }
    
        // XOR key with opad and ipad
        bytes memory oKeyPad = new bytes(blockSize);
        bytes memory iKeyPad = new bytes(blockSize);
        for (uint256 i = 0; i < blockSize; i++) {
            oKeyPad[i] = bytes1(keyPadded[i] ^ opad[i]);
            iKeyPad[i] = bytes1(keyPadded[i] ^ ipad[i]);
        }
    
        // Perform inner SHA256 hash: SHA256(i_key_pad || message)
        bytes memory innerData = abi.encodePacked(iKeyPad, message);
        bytes32 innerHash = sha256(innerData);
    
        // Perform outer SHA256 hash: SHA256(o_key_pad || inner_hash)
        bytes memory outerData = abi.encodePacked(oKeyPad, innerHash);
        hmac = sha256(outerData);
    }
    
    /// @notice Allows the contract owner to withdraw protocol tokens from the contract.
    /// @param amount The amount of tokens to withdraw.
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

    /// @notice Allows the owner to reset the current gameHash manually.
    ///      Useful in case of emergencies or to handle specific scenarios.
    /// @param newGameHash The new game hash to set.
    function resetCurrentGameHash(bytes32 newGameHash) external onlyOwner whenNotPaused {
        require(newGameHash != bytes32(0), "Invalid gameHash");
        require(gameCommitments[newGameHash] == bytes32(0), "GameHash already has a commitment");
        
        currentGameHash = newGameHash;
        gameHashes.push(newGameHash);
        gameCommitments[newGameHash] = bytes32(0); // No commitment yet

        emit GameHashReset(currentGameHash, newGameHash);
    }

    /// @notice Allows the owner to set the maximum payout multiplier.
    /// @param token The address of the token to set the maximum payout for.
    /// @param _maximumPayout The new maximum payout multiplier.
    /// @param _maximumPayout The new maximum payout multiplier.
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

    /// @notice function to accept Ether.
    receive() external payable {}
}
