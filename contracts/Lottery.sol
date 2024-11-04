// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Powerball Lottery Contract with Percentage-Based Prize Distribution and Protocol Token Support
/// @author
/// @notice This contract implements a lottery where prizes are distributed based on percentages of the total pool, using a protocol ERC20 token.
/// @dev The contract uses a secure commit-reveal scheme for the winning numbers and handles prize distribution according to specified percentages.
contract PowerballLottery is Ownable, ReentrancyGuard, Pausable {
    // State variables
    IERC20 public protocolToken;            // Protocol token used for the lottery
    uint256 public ticketPrice;             // Price per ticket in protocol tokens
    uint256 public totalPool;               // Total amount of tokens in the pool
    bytes32 public winningNumbersHash;      // Commitment to the winning numbers
    bool public isRevealed;                 // Indicates if winning numbers have been revealed
    bool public isClosed;                   // Indicates if ticket sales are closed
    uint256 public drawTimestamp;           // Timestamp when draw occurs

    // Winning numbers
    uint8[5] public winningWhiteBalls;      // Winning white ball numbers
    uint8 public winningPowerBall;          // Winning red Powerball number

    // Player tracking
    address[] public players;                    // List of all player addresses
    mapping(address => bool) public hasPurchased; // Tracks if a player has purchased a ticket

    // Mappings
    mapping(address => Ticket[]) public playerTickets;      // Player address to their tickets
    mapping(address => uint256) public pendingWithdrawals;  // Player address to pending prize amount

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
    
    modifier whenNotClosed() {
        require(!isClosed, "Ticket sales are closed");
        _;
    }

    modifier whenClosed() {
        require(isClosed, "Ticket sales are still open");
        _;
    }

    modifier whenRevealed() {
        require(isRevealed, "Winning numbers not revealed yet");
        _;
    }

    /// @notice Constructor to initialize the contract
    /// @param _ticketPrice The price per ticket in protocol tokens (with decimals)
    /// @param _protocolToken The address of the protocol ERC20 token
    constructor(address initialOwner, uint256 _ticketPrice, address _protocolToken) Ownable(initialOwner) {
        ticketPrice = _ticketPrice; // e.g., 100 * 10**18 for 100 tokens
        protocolToken = IERC20(_protocolToken);
    }

    /// @notice Allows players to purchase a ticket with selected numbers
    /// @param whiteBalls An array of 5 unique numbers between 1 and 69
    /// @param powerBall A number between 1 and 26
    function purchaseTicket(uint8[5] calldata whiteBalls, uint8 powerBall) external whenNotClosed nonReentrant whenNotPaused {
        require(protocolToken.transferFrom(msg.sender, address(this), ticketPrice), "Token transfer failed");
        require(validWhiteBalls(whiteBalls), "Invalid white ball numbers");
        require(powerBall >= 1 && powerBall <= 26, "Invalid Powerball number");

        // Store the ticket
        Ticket memory newTicket = Ticket({
            whiteBalls: whiteBalls,
            powerBall: powerBall,
            claimed: false,
            prize: 0, // Prize will be calculated after winning numbers are revealed
            prizeTier: 0 // Will be set during prize calculation
        });

        playerTickets[msg.sender].push(newTicket);
        totalPool += ticketPrice;

        // Add player to the list if not already present
        if (!hasPurchased[msg.sender]) {
            players.push(msg.sender);
            hasPurchased[msg.sender] = true;
        }

        emit TicketPurchased(msg.sender, playerTickets[msg.sender].length - 1, whiteBalls, powerBall);
    }

    /// @notice Owner commits to the winning numbers using a hash
    /// @param _winningNumbersHash The keccak256 hash of the salt and winning numbers
    function commitWinningNumbers(bytes32 _winningNumbersHash) external onlyOwner whenNotClosed nonReentrant whenNotPaused {
        winningNumbersHash = _winningNumbersHash;
        isClosed = true; // Close ticket sales
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
    ) external onlyOwner whenClosed nonReentrant whenNotPaused {
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

        emit WinningNumbersRevealed(winningWhiteBalls, winningPowerBall);

        // Calculate prizes for all tickets
        calculatePrizes();
    }

    /// @notice Players claim their prizes based on their tickets
    function claimPrizes() external whenRevealed nonReentrant whenNotPaused {
        Ticket[] storage tickets = playerTickets[msg.sender];
        uint256 totalPrize = 0;

        for (uint256 i = 0; i < tickets.length; i++) {
            if (!tickets[i].claimed && tickets[i].prize > 0) {
                totalPrize += tickets[i].prize;
                tickets[i].claimed = true;
            }
        }

        require(totalPrize > 0, "No prizes to claim");
        pendingWithdrawals[msg.sender] += totalPrize;
        totalPendingPrizes += totalPrize;
    }

    /// @notice Withdraw accumulated prizes
    function withdrawPrizes() external nonReentrant whenNotPaused {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No pending withdrawals");
        pendingWithdrawals[msg.sender] = 0;
        totalPendingPrizes -= amount;

        // Transfer prize tokens to the player
        require(protocolToken.transfer(msg.sender, amount), "Token transfer failed");

        emit PrizeClaimed(msg.sender, amount);
    }

    /// @notice Calculates the prizes for all tickets after winning numbers are revealed
    function calculatePrizes() internal {
        // First, categorize tickets into prize tiers
        uint256[6] memory winnersCount; // Index 0 unused, tiers 1-5 correspond to prize tiers

        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            Ticket[] storage tickets = playerTickets[player];
            for (uint256 j = 0; j < tickets.length; j++) {
                if (!tickets[j].claimed) {
                    uint8 prizeTier = determinePrizeTier(tickets[j]);
                    tickets[j].prizeTier = prizeTier;
                    if (prizeTier > 0) {
                        prizeTierWinners[prizeTier].push(player);
                        winnersCount[prizeTier]++;
                    }
                }
            }
        }

        // Now, allocate prizes based on the number of winners in each tier
        for (uint8 tier = 1; tier <= 6; tier++) {
            uint256 tierPercentage = getTierPercentage(tier);
            uint256 tierPrizePool = (totalPool * tierPercentage) / 100;
            uint256 winnerCount = winnersCount[tier];

            if (winnerCount > 0) {
                uint256 prizePerWinner = tierPrizePool / winnerCount;

                // Assign prizes to winners in this tier
                address[] storage tierWinners = prizeTierWinners[tier];
                for (uint256 k = 0; k < tierWinners.length; k++) {
                    address winner = tierWinners[k];
                    Ticket[] storage tickets = playerTickets[winner];
                    for (uint256 l = 0; l < tickets.length; l++) {
                        if (tickets[l].prizeTier == tier && !tickets[l].claimed) {
                            tickets[l].prize = prizePerWinner;
                        }
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
        uint256 availableBalance = protocolToken.balanceOf(address(this)) - totalPendingPrizes;
        require(availableBalance > 0, "No funds available for withdrawal");

        require(protocolToken.transfer(owner(), availableBalance), "Token transfer failed");
    }
}
