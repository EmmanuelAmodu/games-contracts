// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lottery with Dynamic Rollover Distribution
 * @notice This version:
 *         1) Uses only USDC for payments (no stUSD or transmuter).
 *         2) Fixes ticket cost at exactly 1 USDC each.
 *         3) Allows up to 100 tickets per purchase and 100 total per player.
 *         4) Dynamically rolls unused portions if some match groups have no winners.
 *         5) Reserves 10% of the total pool as "house revenue"; 90% is distributed.
 */
contract Lottery is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------
    // Constants / Configuration
    // ------------------------------------------------------------------

    uint8 public constant NUM_BALLS = 5;
    uint8 public constant MIN_NUMBER = 1;
    uint8 public constant MAX_NUMBER = 90;

    // Each ticket costs exactly 1 USDC
    // Max 100 tickets total for each player
    uint256 public constant TICKETS_PER_PLAYER_MAX = 100; 

    // ------------------------------------------------------------------
    // State Variables
    // ------------------------------------------------------------------

    // The USDC token (assumed to have 6 decimals in typical usage)
    IERC20 public immutable token;
    // We store the sum of all ticket payments (in USDC terms) in `totalPool`.
    uint256 public totalPool; 
    // For convenience, we read the token's decimals (e.g. 6 for USDC).
    uint8 public tokenDecimals;

    // Lottery states
    bool public isOpen;                      // Whether ticket purchases are open
    bool public isRevealed;                  // Whether winning numbers have been revealed
    uint256 public drawTimestamp;            // Timestamp used for deadlines
    bytes32 public winningNumbersHash;       // Commitment hash for the winning numbers
    uint8[NUM_BALLS] public winningNumbers;  // The actual winning numbers
    address public factory;                  // Lottery Factory address

    // The Merkle root for (ticketId, prize) pairs
    bytes32 public merkleRoot;

    // Keep track of which tickets have been claimed
    mapping(uint256 => bool) public isClaimed;

    // Tickets
    struct Ticket {
        uint8[] numbers; 
        address player; 
        bool claimed;   
        uint256 prize;  
        uint8 matches;  
    }

    Ticket[] public allTickets;                 // All tickets across all users
    mapping(address => uint256[]) public playerTickets; 
    mapping(address => bool) public hasPurchased;
    address[] public players;

    // Referral
    mapping(address => uint256) public referralRewards;
    uint8 public referralRewardPercent;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event TicketPurchased(address indexed player, uint256 ticketId, uint8[] numbers);
    event WinningNumbersRevealed(uint8[NUM_BALLS] winningNumbers);
    event MerkleRootSet(bytes32 root);
    event PrizeClaimed(address indexed player, uint256 ticketId, uint256 amount);
    event NoPrizeToClaim(address indexed player, uint256 ticketId);
    event ReferralRewardClaimed(address indexed referrer, uint256 amount);
    event ReferralRewardPercentUpdated(uint8 newPercent);

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /**
     * @param initialOwner The owner of this contract.
     * @param _winningNumbersHash Commitment hash for the winning numbers.
     * @param _tokenAddress The address of the USDC token.
     */
    constructor(
        address initialOwner,
        address _factory,
        bytes32 _winningNumbersHash,
        address _tokenAddress
    ) Ownable(initialOwner) {
        require(_tokenAddress != address(0), "Invalid USDC address");
        require(_winningNumbersHash != bytes32(0), "Invalid hash");

        factory = _factory;
        winningNumbersHash = _winningNumbersHash;
        token = IERC20(_tokenAddress);
        tokenDecimals = IERC20Metadata(_tokenAddress).decimals();
        referralRewardPercent = 1; // e.g. 1%

        // Initialize lottery
        isOpen = true;
        isRevealed = false;
        // e.g. let users buy tickets for 1 day
        drawTimestamp = block.timestamp + 1 days;
    }

    // ------------------------------------------------------------------
    // Purchase Tickets
    // ------------------------------------------------------------------

    /**
     * @notice Buy multiple tickets, each costing exactly 1 USDC.
     *         Up to 100 tickets in a single purchase, and up to 100 total.
     * @param numbersList An array of arrays of chosen numbers (2..5 unique numbers per ticket).
     * @param referrer Optional referral address.
     */
    function purchaseTickets(
        uint8[][] calldata numbersList,
        address referrer
    ) external whenNotPaused nonReentrant {
        require(isOpen, "Sales closed");
        require(drawTimestamp > block.timestamp, "Sales deadline passed");

        uint256 numTickets = numbersList.length;
        require(numTickets > 0, "No tickets provided");
        require(numTickets <= 100, "Max 100 tickets in one purchase");
        // Ensure total tickets per player doesn't exceed 100
        require(
            playerTickets[msg.sender].length + numTickets <= TICKETS_PER_PLAYER_MAX,
            "Exceeds per-player max of 100 tickets"
        );

        // Each ticket costs 1 USDC => total cost = numTickets * (1 USDC)
        // In base units, that's numTickets * (10^tokenDecimals).
        uint256 costPerTicket = 10 ** tokenDecimals; // e.g. 1_000_000 for 6 decimals
        uint256 totalCost = numTickets * costPerTicket;

        // Transfer USDC from user to contract
        token.safeTransferFrom(msg.sender, address(this), totalCost);
        // Increase totalPool by totalCost
        totalPool += totalCost;

        // Create each ticket
        for (uint256 i = 0; i < numTickets; i++) {
            _createTicket(numbersList[i]);
        }

        // Track player if first time
        if (!hasPurchased[msg.sender]) {
            players.push(msg.sender);
            hasPurchased[msg.sender] = true;
        }

        // Referral
        if (referrer != address(0) && referrer != msg.sender) {
            referralRewards[referrer] += (totalCost * referralRewardPercent) / 100;
        }
    }

    /**
     * @dev Internal helper to create a single Ticket with the user-chosen numbers.
     *      The actual cost has already been transferred, we just store the ticket data.
     */
    function _createTicket(uint8[] calldata numbers) internal {
        require(validNumbers(numbers), "Invalid ticket numbers");

        Ticket memory t = Ticket({
            numbers: numbers,
            player: msg.sender,
            claimed: false,
            prize: 0,
            matches: 0
        });

        allTickets.push(t);
        uint256 ticketId = allTickets.length - 1;
        playerTickets[msg.sender].push(ticketId);

        emit TicketPurchased(msg.sender, ticketId, numbers);
    }

    // ------------------------------------------------------------------
    // Reveal Winning Numbers
    // ------------------------------------------------------------------

    /**
     * @notice Owner reveals the winning numbers by providing salt + numbers that match the commit.
     */
    function revealWinningNumbers(
        bytes32 salt,
        uint8[NUM_BALLS] calldata numbers,
        bytes32 newRoot
    ) external onlyFactory nonReentrant {
        require(block.timestamp > drawTimestamp, "Draw deadline not passed");
        require(isOpen, "Already closed");
        require(!isRevealed, "Already revealed");

        // Validate
        uint8[] memory dynamicNums = new uint8[](NUM_BALLS);
        for (uint8 i = 0; i < NUM_BALLS; i++) {
            dynamicNums[i] = numbers[i];
        }
        require(validNumbers(dynamicNums), "Invalid winning numbers");

        // Check commitment
        bytes32 computedHash = keccak256(abi.encodePacked(salt, numbers));
        require(computedHash == winningNumbersHash, "Commit mismatch");

        // Close sales
        isOpen = false;
        isRevealed = true;

        for (uint8 i = 0; i < NUM_BALLS; i++) {
            winningNumbers[i] = numbers[i];
        }

        _setMerkleRoot(newRoot);
        emit WinningNumbersRevealed(winningNumbers);
    }

    /**
     * @notice Sets the new merkle root after you've computed final rewards off-chain.
     *         Only owner can call.
     */
    function _setMerkleRoot(bytes32 newRoot) internal {
        merkleRoot = newRoot;
        emit MerkleRootSet(newRoot);
    }

    /**
     * @notice Users call this to claim their final prize for a given `ticketId`.
     * @param ticketId The ticket ID.
     * @param prize The prize amount (in USDC) for this ticket.
     * @param merkleProof The Merkle proof showing that (ticketId, prize) is in the distribution.
     */
    function claimPrize(
        uint256 ticketId,
        uint256 prize,
        bytes32[] calldata merkleProof
    ) external {
        require(merkleRoot != bytes32(0), "Merkle root not set");
        require(!isClaimed[ticketId], "Already claimed");

        // 1) Reconstruct the leaf
        bytes32 leaf = keccak256(abi.encodePacked(ticketId, prize, msg.sender));
        // If you want to store user address in the leaf, include `msg.sender`.

        // 2) Verify proof => root
        bool valid = MerkleProof.verify(merkleProof, merkleRoot, leaf);
        require(valid, "Invalid proof");

        // Mark claimed
        isClaimed[ticketId] = true;

        // Transfer USDC
        require(token.balanceOf(address(this)) >= prize, "Not enough USDC in contract");
        token.safeTransfer(msg.sender, prize);

        emit PrizeClaimed(msg.sender, ticketId, prize);
    }

    // ------------------------------------------------------------------
    // Referral Rewards
    // ------------------------------------------------------------------

    /**
     * @notice Referrers can claim their accumulated referral rewards (in USDC).
     */
    function claimReferralRewards() external whenNotPaused nonReentrant {
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No referral rewards");
        referralRewards[msg.sender] = 0;
        token.safeTransfer(msg.sender, reward);

        emit ReferralRewardClaimed(msg.sender, reward);
    }

    function updateReferralRewardPercent(uint8 percentAmount) external onlyOwner {
        require(percentAmount <= 10, "Max 10%");
        referralRewardPercent = percentAmount;
        emit ReferralRewardPercentUpdated(percentAmount);
    }

    /**
     * @dev Validate ticket numbers: 2..5 unique numbers within [MIN_NUMBER..MAX_NUMBER].
     */
    function validNumbers(uint8[] memory nums) public pure returns (bool) {
        if (nums.length < 2 || nums.length > NUM_BALLS) {
            return false;
        }
        for (uint256 i = 0; i < nums.length; i++) {
            if (nums[i] < MIN_NUMBER || nums[i] > MAX_NUMBER) {
                return false;
            }
            for (uint256 j = i + 1; j < nums.length; j++) {
                if (nums[i] == nums[j]) {
                    return false;
                }
            }
        }
        return true;
    }

    // ------------------------------------------------------------------
    // View Helpers
    // ------------------------------------------------------------------

    function getTicket(uint256 ticketId) external view returns (Ticket memory) {
        require(ticketId < allTickets.length, "Invalid ticket ID");
        return allTickets[ticketId];
    }

    function getPlayerTickets(address user) external view returns (uint256[] memory) {
        return playerTickets[user];
    }

    // ------------------------------------------------------------------
    // Owner Maintenance / Emergencies
    // ------------------------------------------------------------------

    /**
     * @notice After the cashout deadline, the owner can withdraw the leftover USDC (if any).
     */
    function withdrawTokensAllFundsAfterCashoutDeadline() 
        external 
        onlyOwner 
        nonReentrant 
    {
        require(block.timestamp > drawTimestamp + 3 days, "Cashout not ended");

        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(owner(), balance);
        // zero out totalPool, since we've removed everything
        totalPool = 0;
    }

    /**
     * @notice Pause the contract (emergencies).
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
