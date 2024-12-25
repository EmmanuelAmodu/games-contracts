// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./MerkleLotteryDistribution.sol";

/**
 * @title Lottery with Dynamic Rollover Distribution
 * @notice This version:
 *         1) Uses only USDC for payments (no stUSD or transmuter).
 *         2) Fixes ticket cost at exactly 1 USDC each.
 *         3) Allows up to 100 tickets per purchase and 100 total per player.
 *         4) Dynamically rolls unused portions if some match groups have no winners.
 *         5) Reserves 10% of the total pool as "house revenue"; 90% is distributed.
 */
contract Lottery is Ownable, ReentrancyGuard, Pausable, MerkleLotteryDistribution {
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

    // We distribute 90% among these match categories:
    //    5 matches -> 40%
    //    4 matches -> 20%
    //    3 matches -> 15%
    //    2 matches -> 10%
    //    1 match   -> 5%
    // Sum = 90%
    uint256[5] public baseDistribution = [40, 20, 15, 10, 5];
    // baseDistribution[0] = 40% (for 5 matches)
    // baseDistribution[1] = 20% (for 4 matches)
    // baseDistribution[2] = 15% (for 3 matches)
    // baseDistribution[3] = 10% (for 2 matches)
    // baseDistribution[4] = 5%  (for 1 match)

    // ------------------------------------------------------------------
    // State Variables
    // ------------------------------------------------------------------

    // The USDC token (assumed to have 6 decimals in typical usage)
    IERC20 public USDC;
    // We store the sum of all ticket payments (in USDC terms) in `totalPool`.
    uint256 public totalPool; 
    // For convenience, we read the token's decimals (e.g. 6 for USDC).
    uint8 public tokenDecimals;

    // Lottery states
    bool public isOpen;             // Whether ticket purchases are open
    bool public isRevealed;         // Whether winning numbers have been revealed
    uint256 public drawTimestamp;   // Timestamp used for deadlines
    bytes32 public winningNumbersHash;
    uint8[NUM_BALLS] public winningNumbers;

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

    // Match counts (how many tickets matched exactly 0..5 numbers)
    uint256[6] public matchCounts;

    // How much is allocated to each match group (0..5) out of the 90%
    uint256[6] public matchPools;

    // Distribution phases
    enum DistPhase { None, Counting, Counted, Awarding, Done }
    DistPhase public distPhase;

    // Batching indexes
    uint256 public nextTicketToCount;
    uint256 public nextTicketToAward;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event TicketPurchased(address indexed player, uint256 ticketId, uint8[] numbers);
    event WinningNumbersRevealed(uint8[NUM_BALLS] winningNumbers);
    event DistributionPhaseChanged(DistPhase phase);
    event BatchProcessed(uint256 startIndex, uint256 endIndex, DistPhase phase);

    event PrizeClaimed(address indexed player, uint256 ticketId, uint256 amount);
    event NoPrizeToClaim(address indexed player, uint256 ticketId);
    event ReferralRewardClaimed(address indexed referrer, uint256 amount);
    event ReferralRewardPercentUpdated(uint8 newPercent);

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /**
     * @param initialOwner The owner of this contract.
     * @param _winningNumbersHash Commitment hash for the winning numbers.
     * @param _usdc The address of the USDC token.
     */
    constructor(
        address initialOwner,
        bytes32 _winningNumbersHash,
        address _usdc
    ) Ownable(initialOwner) MerkleLotteryDistribution(_usdc) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_winningNumbersHash != bytes32(0), "Invalid hash");

        winningNumbersHash = _winningNumbersHash;
        USDC = IERC20(_usdc);
        tokenDecimals = IERC20Metadata(_usdc).decimals();
        referralRewardPercent = 1; // e.g. 1%

        // Initialize lottery
        isOpen = true;
        isRevealed = false;
        // e.g. let users buy tickets for 1 day
        drawTimestamp = block.timestamp + 1 days;
        distPhase = DistPhase.None;
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
        USDC.safeTransferFrom(msg.sender, address(this), totalCost);
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
        uint8[NUM_BALLS] calldata numbers
    ) external onlyOwner nonReentrant {
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
        drawTimestamp = block.timestamp;

        for (uint8 i = 0; i < NUM_BALLS; i++) {
            winningNumbers[i] = numbers[i];
        }

        // Switch to Counting phase
        distPhase = DistPhase.Counting;
        nextTicketToCount = 0;

        emit WinningNumbersRevealed(winningNumbers);
        emit DistributionPhaseChanged(distPhase);
    }

    // ------------------------------------------------------------------
    // PHASE 1: Counting Matches (batched)
    // ------------------------------------------------------------------

    /**
     * @notice Count how many numbers each ticket matched, in batches to avoid "out of gas."
     * @param batchSize Max number of tickets to process in this call.
     */
    function countMatchesBatch(uint256 batchSize) external nonReentrant {
        require(distPhase == DistPhase.Counting, "Not in Counting phase");
        require(isRevealed, "Numbers not revealed");

        uint256 startIndex = nextTicketToCount;
        uint256 endIndex = startIndex + batchSize;
        if (endIndex > allTickets.length) {
            endIndex = allTickets.length;
        }

        for (uint256 i = startIndex; i < endIndex; i++) {
            uint8 m = _countMatching(allTickets[i].numbers, winningNumbers);
            allTickets[i].matches = m;
            matchCounts[m] += 1;
        }

        nextTicketToCount = endIndex;
        emit BatchProcessed(startIndex, endIndex, distPhase);

        if (nextTicketToCount >= allTickets.length) {
            distPhase = DistPhase.Counted;
            emit DistributionPhaseChanged(distPhase);
        }
    }

    // ------------------------------------------------------------------
    // PHASE 2: Finalize Pools with Dynamic Rollover
    // ------------------------------------------------------------------

    /**
     * @notice Distribute 90% of totalPool among match=5..1 with dynamic rollover.
     *         - If match5 has winners, it gets 40% of the 90%. Otherwise, it rolls down, etc.
     */
    function finalizeMatchPools() external onlyOwner nonReentrant {
        require(distPhase == DistPhase.Counted, "Not in Counted phase");

        // House keeps 10%; we distribute 90%
        uint256 distributionPool = (totalPool * 90) / 100;

        // top-down order: 5->4->3->2->1
        // baseDistribution = [40,20,15,10,5]
        uint8[5] memory groupOrder = [5, 4, 3, 2, 1];

        uint256 leftover = 0;

        for (uint256 i = 0; i < groupOrder.length; i++) {
            uint8 group = groupOrder[i];
            // This group's portion plus leftover
            uint256 portion = leftover + ((distributionPool * baseDistribution[i]) / 100);

            if (matchCounts[group] == 0) {
                // no winners in this group => carry forward
                leftover = portion;
            } else {
                // assign entire portion to this group
                matchPools[group] = portion;
                leftover = 0;
            }
        }

        // If leftover remains after group=1, attempt to find a group from bottom up (1->2->3->4->5)
        if (leftover > 0) {
            for (uint8 g = 1; g <= 5; g++) {
                if (matchCounts[g] > 0) {
                    matchPools[g] += leftover;
                    leftover = 0;
                    break;
                }
            }
        }

        // leftover remains if nobody had any matches at all (i.e., no participants).
        // That leftover stays in the contract effectively.

        // Move on to awarding
        distPhase = DistPhase.Awarding;
        nextTicketToAward = 0;
        emit DistributionPhaseChanged(distPhase);
    }

    // ------------------------------------------------------------------
    // PHASE 3: Awarding Prizes (batched)
    // ------------------------------------------------------------------

    /**
     * @notice Assign each ticket's final `prize`, in batches.
     * @param batchSize Max number of tickets to process in this call.
     */
    function awardPrizesBatch(uint256 batchSize) external nonReentrant {
        require(distPhase == DistPhase.Awarding, "Not in Awarding phase");

        uint256 startIndex = nextTicketToAward;
        uint256 endIndex = startIndex + batchSize;
        if (endIndex > allTickets.length) {
            endIndex = allTickets.length;
        }

        for (uint256 i = startIndex; i < endIndex; i++) {
            Ticket storage t = allTickets[i];
            uint8 m = t.matches;
            if (matchCounts[m] > 0 && matchPools[m] > 0) {
                // integer division leftover remains in contract
                t.prize = matchPools[m] / matchCounts[m];
            }
        }

        nextTicketToAward = endIndex;
        emit BatchProcessed(startIndex, endIndex, distPhase);

        if (nextTicketToAward >= allTickets.length) {
            distPhase = DistPhase.Done;
            emit DistributionPhaseChanged(distPhase);
        }
    }

    // ------------------------------------------------------------------
    // Claim Prizes
    // ------------------------------------------------------------------

    /**
     * @notice Players call this to claim any unclaimed prizes on their tickets.
     */
    function claimPrize() external whenNotPaused nonReentrant {
        require(isRevealed, "Not revealed yet");
        require(distPhase == DistPhase.Done, "Not done awarding");
        require(drawTimestamp + 3 days > block.timestamp, "Cashout deadline passed");

        uint256[] storage ids = playerTickets[msg.sender];
        require(ids.length > 0, "No tickets");

        uint256 totalClaim;
        for (uint256 i = 0; i < ids.length; i++) {
            Ticket storage t = allTickets[ids[i]];
            if (!t.claimed && t.prize > 0) {
                t.claimed = true;
                totalClaim += t.prize;
                emit PrizeClaimed(msg.sender, ids[i], t.prize);
            } else if (!t.claimed && t.prize == 0) {
                t.claimed = true;
                emit NoPrizeToClaim(msg.sender, ids[i]);
            }
        }

        if (totalClaim > 0) {
            // Decrease the pool and send USDC out
            totalPool -= totalClaim;
            USDC.safeTransfer(msg.sender, totalClaim);
        }
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
        USDC.safeTransfer(msg.sender, reward);

        emit ReferralRewardClaimed(msg.sender, reward);
    }

    function updateReferralRewardPercent(uint8 percentAmount) external onlyOwner {
        require(percentAmount <= 10, "Max 10%");
        referralRewardPercent = percentAmount;
        emit ReferralRewardPercentUpdated(percentAmount);
    }

    // ------------------------------------------------------------------
    // Helper Functions
    // ------------------------------------------------------------------

    /**
     * @dev Count how many of the ticket's numbers appear in the winning numbers.
     */
    function _countMatching(uint8[] memory arr, uint8[NUM_BALLS] memory win)
        internal
        pure
        returns (uint8)
    {
        uint8 count;
        for (uint8 i = 0; i < arr.length; i++) {
            for (uint8 j = 0; j < win.length; j++) {
                if (arr[i] == win[j]) {
                    count++;
                    break;
                }
            }
        }
        return count;
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

        uint256 balance = USDC.balanceOf(address(this));
        USDC.safeTransfer(owner(), balance);
        // zero out totalPool, since we've removed everything
        totalPool = 0;
    }

    /**
     * @notice Owner can withdraw a specified amount of USDC at any time (if needed).
     */
    function withdraw(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        require(
            USDC.balanceOf(address(this)) >= amount,
            "Insufficient USDC in contract"
        );
        // Decrease totalPool accordingly (if you want to keep totalPool in sync)
        if (amount <= totalPool) {
            totalPool -= amount;
        } else {
            // If you prefer to keep totalPool as "all tickets", 
            // you can handle differently; this is just an example.
            totalPool = 0;
        }
        USDC.safeTransfer(owner(), amount);
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
