// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin contracts for security and access control
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title On-Chain Crash Game with ERC20 and Commit-Reveal Scheme
contract CrashGame is Ownable, ReentrancyGuard, Pausable {
    // ERC20 Protocol Token
    IERC20 public protocolToken;

    // Game parameters
    uint256 public minimumBet = 10 * 10**18; // 10 tokens
    uint256 public maximumBet = 10000 * 10**18;   // 10,000 tokens
    uint256 public maximumPayout = 50000 * 10**18; // 500.00x
    uint256 public revealTimeoutDuration = 1 minutes; // Duration after which bets can be refunded if not revealed

    // Struct to store player bets
    struct Bet {
        address player;
        uint256 amount;
        bytes32 gameHash;
        bytes32 resolvedHash;
        uint256 intendedMultiplier;
        uint256 multiplier; // Scaled by 100 (e.g., 250 represents 2.50x)
        bool claimed;
        bool isWon;
    }

    // Mapping from game hash to player bets
    mapping(bytes32 => mapping(address => Bet)) public bets;

    // Mapping from game hash to participants
    mapping(bytes32 => address[]) public participants;

    // Array of all game hashes
    bytes32[] public gameHashes;

    // Mapping from gameHash to commitment
    mapping(bytes32 => bytes32) public gameCommitments;

    // Mapping from gameHash to result multiplier
    mapping(bytes32 => uint256) public result;

    // Events
    event GameCommitted(bytes32 indexed gameHash, bytes32 commitment);
    event BetPlaced(address indexed player, uint256 amount, bytes32 gameHash);
    event BetResolved(bytes32 gameHash, uint256 multiplier, bytes32 hmac);
    event Payout(address indexed player, uint256 amount);
    event GameRevealed(bytes32 indexed gameHash, uint256 multiplier, bytes32 hmac);
    event RefundClaimed(address indexed player, bytes32 gameHash, uint256 amount);

    // Current game hash
    bytes32 public currentGameHash;

    // Reveal deadline for each gameHash
    mapping(bytes32 => uint256) public gameRevealDeadline;

    // Constructor to set the contract deployer as the owner and initialize parameters
    constructor(
        address initialOwner,
        address _protocolTokenAddress
    ) Ownable(initialOwner) {
        require(_protocolTokenAddress != address(0), "Invalid token address");
        protocolToken = IERC20(_protocolTokenAddress);
        
        // Initialize the first game hash with a unique and unpredictable value
        currentGameHash = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.number));
        gameHashes.push(currentGameHash);
        gameCommitments[currentGameHash] = bytes32(0); // No commitment yet
        gameRevealDeadline[currentGameHash] = block.timestamp + revealTimeoutDuration;
    }

    /// @notice Pause the contract, disabling certain functions.
    function pause() external onlyOwner {
        _pause();
    }
    
    /// @notice Unpause the contract, enabling previously disabled functions.
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Allows the owner to commit to a new game's secret by providing a commitment hash.
     * @param commitment The hash of the secret (e.g., keccak256(abi.encodePacked(secret))).
     */
    function commitGame(bytes32 commitment) external onlyOwner {
        require(currentGameHash != bytes32(0), "Previous game not resolved");
        require(gameCommitments[currentGameHash] == bytes32(0), "Commitment already set");
        
        // Store the commitment for the current game
        gameCommitments[currentGameHash] = commitment;
        
        // Set the reveal deadline
        gameRevealDeadline[currentGameHash] = block.timestamp + revealTimeoutDuration;
        
        emit GameCommitted(currentGameHash, commitment);
    }

    /**
     * @dev Allows a player to place a bet on the current committed game.
     * @param amount The amount of protocol tokens to bet.
     * @param intendedMultiplier The multiplier the player aims to achieve.
     */
    function placeBet(uint256 amount, uint256 intendedMultiplier) external nonReentrant whenNotPaused {
        require(amount >= minimumBet, "Bet amount below minimum");
        require(amount <= maximumBet, "Bet amount exceeds maximum");
        require(currentGameHash != bytes32(0), "No game committed");
        require(gameCommitments[currentGameHash] != bytes32(0), "Game not yet committed");
        
        // Transfer tokens from the player to the contract
        bool success = protocolToken.transferFrom(msg.sender, address(this), amount);
        require(success, "Token transfer failed");
        
        // Record the bet with the current gameHash
        Bet storage existingBet = bets[currentGameHash][msg.sender];
        require(existingBet.player == address(0), "Bet already placed");
        
        bets[currentGameHash][msg.sender] = Bet({
            player: msg.sender,
            amount: amount,
            gameHash: currentGameHash,
            resolvedHash: bytes32(0),
            intendedMultiplier: intendedMultiplier,
            multiplier: 0, // To be set when resolved
            claimed: false,
            isWon: false
        });

        participants[currentGameHash].push(msg.sender);
        emit BetPlaced(msg.sender, amount, currentGameHash);
    }

    /**
     * @dev Returns the bets placed by all players for a specific game.
     * @param gameHash The unique game-specific hash used as the HMAC key.
     * @return playerBets An array of Bet structs representing the bets placed.
     */
    function getBets(bytes32 gameHash) external view returns (Bet[] memory) {
        address[] memory players = participants[gameHash];
        Bet[] memory playerBets = new Bet[](players.length);
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            playerBets[i] = bets[gameHash][player];
        }
        return playerBets;
    }

    /**
     * @dev Allows the owner to reveal the secret for the current gameHash.
     * @param secret The secret value used to generate the commitment.
     */
    function revealGame(string memory secret) external onlyOwner whenNotPaused {
        require(currentGameHash != bytes32(0), "No active game");
        require(gameCommitments[currentGameHash] != bytes32(0), "No commitment found for this gameHash");
        require(block.timestamp <= gameRevealDeadline[currentGameHash], "Reveal period has ended");
        
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
        
        emit BetResolved(currentGameHash, multiplier, hmac);
        emit GameRevealed(currentGameHash, multiplier, hmac);
        
        // Prepare for the next game by setting the new currentGameHash
        // Using the hmac as the new gameHash ensures linkage between games
        currentGameHash = hmac;
        gameHashes.push(currentGameHash);
        gameCommitments[currentGameHash] = bytes32(0); // No commitment yet
        gameRevealDeadline[currentGameHash] = block.timestamp + revealTimeoutDuration;
    }

    /**
     * @dev Allows users to claim their payout after the bet is resolved and they have won.
     * @param gameHash The unique game-specific hash used as the HMAC key.
     */
    function claimPayout(bytes32 gameHash) external nonReentrant whenNotPaused returns (Bet memory) {
        Bet storage bet = bets[gameHash][msg.sender];
        require(bet.player == msg.sender, "Not your bet");
        require(!bet.claimed, "Payout already claimed");
        require(result[gameHash] > 0, "Game not resolved yet");

        if (result[gameHash] >= bet.intendedMultiplier) {
            // Calculate payout
            uint256 payout = (bet.amount * bet.intendedMultiplier) / 100;
            if (payout > maximumPayout) {
                payout = maximumPayout;
            }
            require(protocolToken.balanceOf(address(this)) >= payout, "Insufficient contract token balance");
            
            // Mark as claimed before transferring to prevent re-entrancy
            bet.claimed = true;
            bet.isWon = true;
            bet.multiplier = result[gameHash];
            bet.resolvedHash = keccak256(abi.encodePacked(gameHash));
            
            // Transfer payout
            bool success = protocolToken.transfer(msg.sender, payout);
            require(success, "Token transfer failed");
            
            emit Payout(msg.sender, payout);
        } else {
            // Mark the bet as resolved but not won
            bet.claimed = true;
            bet.isWon = false;
            bet.multiplier = result[gameHash];
            bet.resolvedHash = keccak256(abi.encodePacked(gameHash));
        }

        Bet memory betData = bet;
        return betData;
    }

    /**
     * @dev Allows users to refund their bets if the reveal period has ended without a reveal.
     * @param gameHash The unique game-specific hash used as the HMAC key.
     */
    function refundBet(bytes32 gameHash) external nonReentrant whenNotPaused {
        require(block.timestamp > gameRevealDeadline[gameHash], "Reveal period not yet ended");
        require(gameHash != bytes32(0), "Invalid gameHash");
        
        Bet storage bet = bets[gameHash][msg.sender];
        require(bet.player == msg.sender, "Not your bet");
        require(result[gameHash] == 0, "Game already resolved");
        require(!bet.claimed, "Bet already refunded or claimed");
        
        uint256 amount = bet.amount;
        require(amount > 0, "No amount to refund");
        
        // Mark as claimed to prevent reentrancy
        bet.claimed = true;
        
        // Transfer tokens back to the user
        bool success = protocolToken.transfer(msg.sender, amount);
        require(success, "Token transfer failed");
        
        emit RefundClaimed(msg.sender, gameHash, amount);
    }

    /**
     * @dev Computes the crash multiplier based on the provided secure game hash.
     * @param secureGameHash The secure game-specific hash used as the HMAC key.
     * @return multiplier The crash multiplier scaled by 100 (e.g., 250 represents 2.50x).
     * @return hmac The HMAC-SHA256 hash used for verification.
     */
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

    /**
     * @dev Implements HMAC-SHA256 as per RFC 2104.
     * @param key The secret key for HMAC.
     * @param message The message to hash.
     * @return hmac The resulting HMAC-SHA256 hash.
     */
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
    
    /**
     * @dev Allows the contract owner to withdraw protocol tokens from the contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawTokens(uint256 amount) external onlyOwner nonReentrant whenNotPaused {
        require(protocolToken.balanceOf(address(this)) >= amount, "Insufficient token balance");
        bool success = protocolToken.transfer(owner(), amount);
        require(success, "Token transfer failed");
    }
    
    /**
     * @dev Allows the contract owner to set a new reveal timeout duration.
     * @param _revealTimeoutDuration The new duration in seconds.
     */
    function setRevealTimeout(uint256 _revealTimeoutDuration) external onlyOwner {
        revealTimeoutDuration = _revealTimeoutDuration;
    }
    
    /**
     * @dev Allows the owner to reset the current gameHash manually.
     * Useful in case of emergencies or to handle specific scenarios.
     * @param newGameHash The new game hash to set.
     */
    function resetCurrentGameHash(bytes32 newGameHash) external onlyOwner whenNotPaused {
        require(newGameHash != bytes32(0), "Invalid gameHash");
        require(gameCommitments[newGameHash] == bytes32(0), "GameHash already has a commitment");
        
        currentGameHash = newGameHash;
        gameHashes.push(newGameHash);
        gameCommitments[newGameHash] = bytes32(0); // No commitment yet
        gameRevealDeadline[newGameHash] = block.timestamp + revealTimeoutDuration;
    }
    
    /**
     * @dev Fallback function to accept Ether if needed.
     * (Optional if you plan to handle ETH as well)
     */
    receive() external payable {}
}
