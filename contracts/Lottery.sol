// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Lottery Contract with Multiplier-Based Prize Distribution
/// @author Emmanuel Amodu
/// @notice This contract implements a lottery where each matched number gives the ticket a multiplier for the payout.
contract Lottery is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public token;                          // Protocol token used for the lottery
    uint256 public totalPool;                     // Total amount of tokens in the pool
    bytes32 public winningNumbersHash;            // Commitment to the winning numbers
    bool public isRevealed;                       // Indicates if winning numbers have been revealed
    bool public isOpen;                           // Indicates if ticket sales are open
    uint256 public drawTimestamp;                 // Timestamp when draw occurs

    // Player tracking
    address[] public players;                     // List of all player addresses
    mapping(address => bool) public hasPurchased; // Tracks if a player has purchased a ticket

    // Mappings
    mapping(address => uint256[]) public playerTickets;    // Player address to their tickets
    mapping(address => uint256) public referralRewards;    // Player address to their referral rewards
    Ticket[] public allTickets;                            // Array of all tickets

    // Total pending prizes
    uint256 public totalPendingPrizes; // Total amount of pending prizes in tokens

    // Multipliers based on the number of matches
    uint256[6] public multipliers = [0, 1, 2, 5, 10, 50]; // Index corresponds to number of matches

    uint8 public constant MAX_NUMBER = 99;  // Maximum number for the lottery
    uint8 public constant MIN_NUMBER = 1;   // Minimum number for the lottery
    uint8 public constant NUM_BALLS = 5;    // Number of balls in the draw
    uint8 public referalRewardPercent = 10; // 10% of ticket price as referral reward

    // Winning numbers
    uint8[NUM_BALLS] public winningNumbers; // Winning numbers

    // Structs
    struct Ticket {
        uint8[] numbers;    // Player's selected numbers
        address player;      // Player's address
        bool claimed;        // Whether the prize has been claimed
        uint256 amount;      // Amount of tokens staked
        uint256 prize;       // Prize amount for the ticket in tokens
        uint256 multiplier;  // Multiplier for the ticket based on matching numbers
    }

    // Events
    event TicketPurchased(address indexed player, uint256 ticketId, uint8[] numbers);
    event WinningNumbersRevealed(uint8[NUM_BALLS] winningNumbers);
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

    /// @notice Constructor to initialize the contract with the protocol token
    /// @param _token The address of the protocol ERC20 token
    constructor(address initialOwner, address _token) Ownable(initialOwner) {
        token = IERC20(_token);
    }

    /// @notice Allows players to purchase a ticket with selected numbers
    /// @param numbers An array of 5 unique numbers between MIN_NUMBER and MAX_NUMBER
    /// @param amount The amount of tokens to stake
    /// @param referrer The address of the referrer
    function purchaseTicket(uint8[] calldata numbers, uint256 amount, address referrer) external whenOpen nonReentrant whenNotPaused {
        token.safeTransferFrom(msg.sender, address(this), amount);
        _createTicket(numbers, referrer, amount);
    }

    /// @notice Allows players to purchase multiple tickets with selected numbers
    /// @param numbers An array of unique numbers between MIN_NUMBER and MAX_NUMBER
    /// @param amounts An array of amounts for each ticket
    /// @param referrer The address of the referrer
    function purcaseMultipleTickets(uint8[][] calldata numbers, uint256[] calldata amounts, address referrer) external whenOpen nonReentrant whenNotPaused {
        require(numbers.length == amounts.length, "Invalid input");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        token.safeTransferFrom(msg.sender, address(this), totalAmount);
        for (uint256 i = 0; i < numbers.length; i++) {
            _createTicket(numbers[i], referrer, amounts[i]);
        }
    }

    /// @notice Allows players to purchase a ticket with selected numbers
    /// @param numbers An array of 5 unique numbers between MIN_NUMBER and MAX_NUMBER
    function _createTicket(uint8[] calldata numbers, address referrer, uint256 amount) internal {
        require(validNumbers(numbers), "Invalid numbers");

        // Store the ticket
        Ticket memory newTicket = Ticket({
            numbers: numbers,
            claimed: false,
            amount: amount,
            player: msg.sender,
            prize: 0,       // Prize will be calculated after winning numbers are revealed
            multiplier: 0   // Will be set during prize calculation
        });

        allTickets.push(newTicket);
        playerTickets[msg.sender].push(allTickets.length - 1);
        totalPool += amount;

        // Add player to the list if not already present
        if (!hasPurchased[msg.sender]) {
            players.push(msg.sender);
            hasPurchased[msg.sender] = true;
        }

        referralRewards[referrer] += amount / referalRewardPercent; // 10% of ticket price as referral reward
        emit TicketPurchased(msg.sender, playerTickets[msg.sender].length - 1, numbers);
    }

    /// @notice Owner commits to the winning numbers using a hash
    /// @param _winningNumbersHash The keccak256 hash of the salt and winning numbers
    function commitWinningNumbers(bytes32 _winningNumbersHash) external onlyOwner whenNotOpen nonReentrant whenNotPaused {
        winningNumbersHash = _winningNumbersHash;
        isOpen = true; // Open ticket sales
        isRevealed = false;
        drawTimestamp = block.timestamp;
    }

    /// @notice Owner reveals the winning numbers by providing the salt and numbers
    /// @param salt The secret salt used in the commitment
    /// @param numbers An array of 5 unique winning numbers
    function revealWinningNumbers(
        bytes32 salt,
        uint8[5] calldata numbers
    ) external onlyOwner whenOpen nonReentrant whenNotPaused {
        require(!isRevealed, "Winning numbers already revealed");

        uint8[] memory numbersFixedLength = new uint8[](NUM_BALLS);
        for (uint8 i = 0; i < NUM_BALLS; i++) {
            numbersFixedLength[i] = numbers[i];
        }
    
        require(validNumbers(numbersFixedLength), "Invalid winning numbers");

        // Verify commitment
        bytes32 hash = keccak256(abi.encodePacked(salt, numbers));
        require(hash == winningNumbersHash, "Commitment does not match");

        // Set winning numbers
        for (uint8 i = 0; i < NUM_BALLS; i++) {
            winningNumbers[i] = numbers[i];
        }

        isRevealed = true;
        isOpen = false; // Close ticket sales

        emit WinningNumbersRevealed(winningNumbers);

        // Calculate prizes for all tickets
        calculatePrizes();
    }

    /// @notice Players claim their prizes based on their tickets
    function claimPrizes() external whenRevealed nonReentrant whenNotPaused {
        uint256[] storage ticketIds = playerTickets[msg.sender];
        uint256 totalPrize = 0;

        for (uint256 i = 0; i < ticketIds.length; i++) {
            Ticket storage ticket = allTickets[ticketIds[i]];
            if (!ticket.claimed && ticket.prize > 0) {
                totalPrize += ticket.prize;
                ticket.claimed = true;
                totalPendingPrizes -= ticket.prize;
            }
        }

        require(totalPrize > 0, "No prizes to claim");
        token.safeTransfer(msg.sender, totalPrize);
        emit PrizeClaimed(msg.sender, totalPrize);
    }

    /// @notice Calculates the prizes for all tickets after winning numbers are revealed
    function calculatePrizes() internal {
        for (uint256 i = 0; i < allTickets.length; i++) {
            Ticket storage ticket = allTickets[i];

            if (!ticket.claimed) {
                uint8 matchingNumbers = countMatchingNumbers(ticket.numbers, winningNumbers);
                ticket.multiplier = getMultiplier(matchingNumbers);
                ticket.prize = ticket.amount * ticket.multiplier;

                // Update totalPendingPrizes
                totalPendingPrizes += ticket.prize;
            }
        }
    }

    /// @notice Determines the multiplier based on the number of matching numbers
    /// @param matchingNumbers The number of matching numbers
    /// @return multiplier The multiplier for the ticket
    function getMultiplier(uint8 matchingNumbers) internal view returns (uint256 multiplier) {
        if (matchingNumbers >= 0 && matchingNumbers <= NUM_BALLS) {
            multiplier = multipliers[matchingNumbers];
        } else {
            multiplier = 0;
        }
    }

    /// @notice Counts the number of matching numbers between two arrays
    /// @param numbers The first array of numbers
    /// @param _winningNumbers The second array of numbers
    /// @return count The count of matching numbers
    function countMatchingNumbers(uint8[] memory numbers, uint8[NUM_BALLS] memory _winningNumbers) internal pure returns (uint8 count) {
        count = 0;
        for (uint8 i = 0; i < numbers.length; i++) {
            for (uint8 j = 0; j < _winningNumbers.length; j++) {
                if (numbers[i] == _winningNumbers[j]) {
                    count++;
                    break;
                }
            }
        }
    }

    /// @notice Gets the user's ticket IDs
    /// @param user The address of the user
    function getPlayerTickets(address user) external view returns (uint256[] memory) {
        return playerTickets[user];
    }

    /// @notice Gets the ticket details
    function getTicket(uint256 ticketId) external view returns (Ticket memory) {
        return allTickets[ticketId];
    }

    /// @notice Gets the winning numbers
    function getWinningNumbers() external view returns (uint8[NUM_BALLS] memory) {
        return winningNumbers;
    }

    /// @notice Validates that the numbers are unique and within the valid range
    /// @param numbers The array of numbers
    /// @return isValid True if the numbers are valid
    function validNumbers(uint8[] memory numbers) internal pure returns (bool isValid) {
        require(numbers.length <= NUM_BALLS, "Invalid number of balls");

        isValid = true;
        for (uint8 i = 0; i < numbers.length; i++) {
            if (numbers[i] < MIN_NUMBER || numbers[i] > MAX_NUMBER) {
                isValid = false;
                break;
            }
            for (uint8 j = i + 1; j < numbers.length; j++) {
                if (numbers[i] == numbers[j]) {
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

    /// @notice Allows the referral rewards to be claimed by the referrer
    function claimReferralRewards() external nonReentrant whenNotPaused {
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No referral rewards to claim");

        referralRewards[msg.sender] = 0;
        token.safeTransfer(msg.sender, reward);
    }

    /// @notice Update referalRewardPercent amount
    function updateReferalRewardPercent(uint8 percentAmount) external onlyOwner whenNotPaused {
        require(percentAmount > 0, "Invalid percent amount");
        require(percentAmount <= 10, "Invalid percent amount");
        referalRewardPercent = percentAmount;
    }
}
