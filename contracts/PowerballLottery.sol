// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Powerball Lottery Contract with Percentage-Based Prize Distribution and Protocol Token Support
/// @author Emmanuel Amodu
/// @notice This contract implements a lottery where prizes are distributed based on percentages of the total pool, using a protocol ERC20 token.
/// @dev The contract uses a secure commit-reveal scheme for the winning numbers and handles prize distribution according to specified percentages.
contract PowerballLottery is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public token;                          // Protocol token used for the lottery
    uint256 public ticketPrice;                   // Price per ticket in protocol tokens
    uint256 public totalPool;                     // Total amount of tokens in the pool
    bytes32 public winningNumbersHash;            // Commitment to the winning numbers
    bool public isRevealed;                       // Indicates if winning numbers have been revealed
    bool public isOpen;                           // Indicates if ticket sales are closed
    uint256 public drawTimestamp;                 // Timestamp when draw occurs
    address public userWithHighestMatchingNumber; // Address of the player with the highest guess
    uint256 public highestMatchPrize;             // Prize for the highest guess

    // Winning numbers
    uint8[5] public winningWhiteBalls;      // Winning white ball numbers
    uint8 public winningPowerBall;          // Winning red Powerball number

    // Player tracking
    address[] public players;                    // List of all player addresses
    mapping(address => bool) public hasPurchased; // Tracks if a player has purchased a ticket

    // Mappings
    mapping(address => uint256[]) public playerTickets;     // Player address to their tickets
    mapping(address => uint256) public referralRewards;    // Player address to their referrral rewards
    Ticket[] public allTickets;                            // Array of all tickets

    // Total pending prizes
    uint256 public totalPendingPrizes; // Total amount of pending prizes in tokens

    // Prize tiers percentages
    uint256 constant JACKPOT_PERCENTAGE = 45;   // Jackpot (5 white balls + Powerball)
    uint256 constant MATCH_5_PERCENTAGE = 22;   // Match 5 white balls
    uint256 constant MATCH_4_PERCENTAGE = 18;   // Match 4 white balls
    uint256 constant MATCH_3_PERCENTAGE = 6;    // Match 3 white balls
    uint256 constant MATCH_2_PERCENTAGE = 4;    // Match 2 white balls
    uint256 constant MATCH_1_PERCENTAGE = 2;    // Match 1 white ball

    // Total percentages should add up to 100%
    // uint256 constant TOTAL_PERCENTAGE = 100;

    // Structs
    struct Ticket {
        uint8[5] whiteBalls; // Player's white ball numbers
        uint8 powerBall;     // Player's red Powerball number
        address player;       // Player's address
        bool claimed;        // Whether the prize has been claimed
        uint256 prize;       // Prize amount for the ticket in tokens
        uint8 prizeTier;     // Prize tier for the ticket
    }

    // Prize tier tracking
    mapping(uint8 => address[]) public prizeTierWinners; // Mapping from prize tier to array of winner addresses

    // Events
    event TicketPurchased(address indexed player, uint256 ticketId, uint8[5] whiteBalls, uint8 powerBall);
    event WinningNumbersRevealed(uint8[5] winningWhiteBalls, uint8 winningPowerBall);
    event PrizeClaimed(address indexed player, uint256 amount);
    
    modifier whenNotOpen() {
        require(!isOpen, "Ticket sales are still open");
        _;
    }

    modifier whenOpen() {
        require(isOpen, "Ticket sales are closed");
        _;
    }

    modifier whenRevealed() {
        require(isRevealed, "Winning numbers not revealed yet");
        _;
    }

    /// @notice Constructor to initialize the contract
    /// @param _ticketPrice The price per ticket in protocol tokens (with decimals)
    /// @param _token The address of the protocol ERC20 token
    constructor(address initialOwner, uint256 _ticketPrice, address _token) Ownable(initialOwner) {
        ticketPrice = _ticketPrice; // e.g., 100 * 10**18 for 100 tokens
        token = IERC20(_token);
    }

    /// @notice Allows players to purchase a ticket with selected numbers
    /// @param whiteBalls An array of 5 unique numbers between 1 and 69
    /// @param powerBall A number between 1 and 26
    function purchaseTicket(uint8[5] calldata whiteBalls, uint8 powerBall, address referrer) external whenOpen nonReentrant whenNotPaused {
        token.safeTransferFrom(msg.sender, address(this), ticketPrice);
        require(validWhiteBalls(whiteBalls), "Invalid white ball numbers");
        require(powerBall >= 1 && powerBall <= 26, "Invalid Powerball number");

        // Store the ticket
        Ticket memory newTicket = Ticket({
            whiteBalls: whiteBalls,
            powerBall: powerBall,
            claimed: false,
            player: msg.sender,
            prize: 0, // Prize will be calculated after winning numbers are revealed
            prizeTier: 0 // Will be set during prize calculation
        });

        allTickets.push(newTicket);
        playerTickets[msg.sender].push(allTickets.length - 1);
        totalPool += ticketPrice;

        // Add player to the list if not already present
        if (!hasPurchased[msg.sender]) {
            players.push(msg.sender);
            hasPurchased[msg.sender] = true;
        }

        referralRewards[referrer] += ticketPrice / 10; // 10% of ticket price as referral reward
        emit TicketPurchased(msg.sender, playerTickets[msg.sender].length - 1, whiteBalls, powerBall);
    }

    /// @notice Owner commits to the winning numbers using a hash
    /// @param _winningNumbersHash The keccak256 hash of the salt and winning numbers
    function commitWinningNumbers(bytes32 _winningNumbersHash) external onlyOwner whenNotOpen nonReentrant whenNotPaused {
        winningNumbersHash = _winningNumbersHash;
        isOpen = true; // Open ticket sales
        drawTimestamp = block.timestamp;
    }

    /// @notice Owner reveals the winning numbers by providing the salt and numbers
    /// @param salt The secret salt used in the commitment
    /// @param whiteBalls An array of 5 unique winning white ball numbers
    /// @param powerBall The winning Powerball number
    function revealWinningNumbers(
        bytes32 salt,
        uint8[5] calldata whiteBalls,
        uint8 powerBall
    ) external onlyOwner whenOpen nonReentrant whenNotPaused {
        require(!isRevealed, "Winning numbers already revealed");
        require(validWhiteBalls(whiteBalls), "Invalid winning white ball numbers");
        require(powerBall >= 1 && powerBall <= 26, "Invalid winning Powerball number");

        // Verify commitment
        bytes32 hash = keccak256(abi.encodePacked(salt, whiteBalls, powerBall));
        require(hash == winningNumbersHash, "Commitment does not match");

        // Set winning numbers
        winningWhiteBalls = whiteBalls;
        winningPowerBall = powerBall;
        isRevealed = true;
        isOpen = false; // Close ticket sales

        emit WinningNumbersRevealed(winningWhiteBalls, winningPowerBall);

        // Calculate prizes for all tickets
        calculatePrizes();
    }

    /// @notice Players claim their prizes based on their tickets
    function claimPrizes() external whenRevealed nonReentrant whenNotPaused {
        uint256[] storage ticketId = playerTickets[msg.sender];
        uint256 totalPrize = 0;

        for (uint256 i = 0; i < ticketId.length; i++) {
            Ticket storage ticket = allTickets[ticketId[i]];
            if (!ticket.claimed && ticket.prize > 0) {
                totalPrize += ticket.prize;
                ticket.claimed = true;
            }
        }

        require(totalPrize > 0, "No prizes to claim");
        token.safeTransfer(msg.sender, totalPrize);
        emit PrizeClaimed(msg.sender, totalPrize);
    }

    /// @notice Calculates the prizes for all tickets after winning numbers are revealed
    function calculatePrizes() internal {
        uint256[7] memory winnersCount; // Index 0 unused
        uint8 maxMatchingNumbers = 0;

        for (uint256 i = 0; i < allTickets.length; i++) {
            Ticket storage ticket = allTickets[i];

            if (!ticket.claimed) {
                uint8 prizeTier = determinePrizeTier(ticket);
                ticket.prizeTier = prizeTier;
                if (prizeTier > 0) {
                    winnersCount[prizeTier]++;
                }

                // Calculate total matches
                uint8 whiteBallMatches = countMatchingNumbers(ticket.whiteBalls, winningWhiteBalls);
                bool powerBallMatch = (ticket.powerBall == winningPowerBall);
                uint8 totalMatches = whiteBallMatches + (powerBallMatch ? 1 : 0);

                // Update the user with the highest matching number
                if (totalMatches > maxMatchingNumbers) {
                    maxMatchingNumbers = totalMatches;
                    userWithHighestMatchingNumber = ticket.player;
                }
            }
        }

        // Allocate prizes based on tiers
        for (uint8 tier = 1; tier <= 6; tier++) {
            uint256 tierPercentage = getTierPercentage(tier);
            uint256 tierPrizePool = (totalPool * tierPercentage) / 100;
            uint256 winnerCount = winnersCount[tier];

            if (winnerCount > 0) {
                uint256 prizePerWinner = tierPrizePool / winnerCount;

                for (uint256 i = 0; i < allTickets.length; i++) {
                    Ticket storage ticket = allTickets[i];
                    if (ticket.prizeTier == tier && !ticket.claimed) {
                        ticket.prize = prizePerWinner;
                    }
                }
            }
        }
    }

    /// @notice Determines the prize tier for a ticket based on matching numbers
    /// @param ticket The ticket to evaluate
    /// @return prizeTier The prize tier (1 to 6), or 0 if no prize
    function determinePrizeTier(Ticket memory ticket) internal view returns (uint8 prizeTier) {
        uint8 whiteBallMatches = countMatchingNumbers(ticket.whiteBalls, winningWhiteBalls);
        bool powerBallMatch = (ticket.powerBall == winningPowerBall);

        if (whiteBallMatches == 5 && powerBallMatch) {
            prizeTier = 1; // Jackpot
        } else if (whiteBallMatches == 5) {
            prizeTier = 2;
        } else if (whiteBallMatches == 4) {
            prizeTier = 3;
        } else if (whiteBallMatches == 3) {
            prizeTier = 4;
        } else if (whiteBallMatches == 2) {
            prizeTier = 5;
        } else if (whiteBallMatches == 1) {
            prizeTier = 6;
        } else {
            prizeTier = 0;
        }
    }

    /// @notice Gets the percentage allocated to a prize tier
    /// @param tier The prize tier (1 to 6)
    /// @return percentage The percentage allocated to the tier
    function getTierPercentage(uint8 tier) internal pure returns (uint256 percentage) {
        if (tier == 1) {
            percentage = JACKPOT_PERCENTAGE;
        } else if (tier == 2) {
            percentage = MATCH_5_PERCENTAGE;
        } else if (tier == 3) {
            percentage = MATCH_4_PERCENTAGE;
        } else if (tier == 4) {
            percentage = MATCH_3_PERCENTAGE;
        } else if (tier == 5) {
            percentage = MATCH_2_PERCENTAGE;
        } else if (tier == 6) {
            percentage = MATCH_1_PERCENTAGE;
        } else {
            percentage = 0;
        }
    }

    /// @notice Counts the number of matching numbers between two arrays
    /// @param numbers1 The first array of numbers
    /// @param numbers2 The second array of numbers
    /// @return count The count of matching numbers
    function countMatchingNumbers(uint8[5] memory numbers1, uint8[5] memory numbers2) internal pure returns (uint8 count) {
        count = 0;
        for (uint8 i = 0; i < numbers1.length; i++) {
            for (uint8 j = 0; j < numbers2.length; j++) {
                if (numbers1[i] == numbers2[j]) {
                    count++;
                    break;
                }
            }
        }
    }

    /// @notice Gets the users ticket ids
    /// @param user The address of the user
    function getPlayerTickets(address user) external view returns (uint256[] memory) {
        return playerTickets[user];
    }

    /// @notice Gets the ticket details
    function getTicket(uint256 ticketId) external view returns (Ticket memory) {
        return allTickets[ticketId];
    }

    /// @notice Gets Winning numbers
    function getWinningNumbers() external view returns (uint8[5] memory, uint8) {
        return (winningWhiteBalls, winningPowerBall);
    }

    /// @notice Validates that the white ball numbers are unique and within the valid range
    /// @param whiteBalls The array of white ball numbers
    /// @return isValid True if the numbers are valid
    function validWhiteBalls(uint8[5] memory whiteBalls) internal pure returns (bool isValid) {
        isValid = true;
        for (uint8 i = 0; i < whiteBalls.length; i++) {
            if (whiteBalls[i] < 1 || whiteBalls[i] > 69) {
                isValid = false;
                break;
            }
            for (uint8 j = i + 1; j < whiteBalls.length; j++) {
                if (whiteBalls[i] == whiteBalls[j]) {
                    isValid = false;
                    break;
                }
            }
            if (!isValid) {
                break;
            }
        }
    }

    /// @notice Allows the owner to withdraw any remaining tokens after prizes are distributed
    function ownerWithdraw() external onlyOwner whenRevealed nonReentrant whenNotPaused {
        uint256 availableBalance = token.balanceOf(address(this)) - totalPendingPrizes;
        require(availableBalance > 0, "No funds available for withdrawal");

        token.safeTransfer(owner(), availableBalance);
    }

    /// @notice Allows the highest matching number ticket to claim their prize
    function claimHighestMatchingRewards() external nonReentrant whenRevealed whenNotPaused {
        require(msg.sender == userWithHighestMatchingNumber, "You are not the user with the highest matching number");
        require(highestMatchPrize > 0, "No prize for the highest matching number");

        token.safeTransfer(msg.sender, highestMatchPrize);
    }

    /// @notice Allows the owner to withdraw any remaining tokens after prizes are distributed
    function setHighestMatchPrize(uint256 prize) external onlyOwner whenRevealed nonReentrant whenNotPaused {
        highestMatchPrize = prize;
    }

    /// @notice Allows the referral rewards to be claimed by the referrer
    function claimReferralRewards() external nonReentrant whenNotPaused {
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No referral rewards to claim");

        referralRewards[msg.sender] = 0;
        token.safeTransfer(msg.sender, reward);
    }
}
