// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Import OpenZeppelin contracts for security and access control
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Lottery Contract with All-or-Nothing Prize Distribution
/// @author Emmanuel Amodu
/// @notice This contract implements a lottery where players win only if all their selected numbers match the winning numbers.
contract Lottery is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public token;                                  // Protocol token used for the lottery
    uint256 public totalPool;                             // Total amount of tokens in the pool
    bytes32 public winningNumbersHash;                    // Commitment to the winning numbers
    bool public isRevealed;                               // Indicates if winning numbers have been revealed
    bool public isOpen;                                   // Indicates if ticket sales are open
    uint256 public drawTimestamp;                         // Timestamp when draw occurs
    uint256 public constant MAX_TICKET_PRICE = 1000;      // Maximum ticket price
    uint256 public constant MIN_TICKET_PRICE = 1;         // Minimum ticket price
    uint256 public constant MAX_TICKETS_PER_PLAYER = 100; // Maximum number of tickets per player

    // Player tracking
    address[] public players;                     // List of all player addresses
    mapping(address => bool) public hasPurchased; // Tracks if a player has purchased a ticket

    // Mappings
    mapping(address => uint256[]) public playerTickets;    // Player address to their tickets
    mapping(address => uint256) public referralRewards;    // Player address to their referral rewards
    Ticket[] public allTickets;                            // Array of all tickets

    uint8 public constant MAX_NUMBER = 90;  // Maximum number for the lottery
    uint8 public constant MIN_NUMBER = 1;   // Minimum number for the lottery
    uint8 public constant NUM_BALLS = 5;    // Number of balls in the draw
    uint8 public referralRewardPercent;     // percent of ticket price as referral reward
    uint8 public tokenDecimals;             // Decimals of the protocol token

    // Winning numbers
    uint8[NUM_BALLS] public winningNumbers; // Winning numbers

    struct Ticket {
        uint8[] numbers;    // Player's selected numbers
        address player;     // Player's address
        bool claimed;       // Whether the prize has been claimed
        uint256 amount;     // Amount of tokens staked
        uint256 prize;      // Prize amount for the ticket in tokens
    }

    // Events
    event TicketPurchased(address indexed player, bytes32 indexed commit, uint256 ticketId, uint8[] numbers);
    event WinningNumbersRevealed(uint8[NUM_BALLS] winningNumbers, bytes32 indexed commit);
    event PrizeClaimed(address indexed player, bytes32 indexed commit, uint256 amount);
    event NoPrizeToClaimed(address indexed player, bytes32 indexed commit, uint256 amount);
    event GameSaved(bytes32 indexed commit, uint256 totalPool, uint256 drawTimestamp);
    event ReferralRewardClaimed(address indexed referrer, uint256 amount);
    event LotteryReset(bytes32 indexed commit);
    event ReferralRewardPercentUpdated(uint8 newPercent);
    event TokenAddressChanged(address newToken);

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

    /// @notice Initialize the contract with the owner address.
    /// @param initialOwner The address of the initial owner
    /// @param _token The address of the protocol ERC20 token
    constructor(address initialOwner, address _token, bytes32 _winningNumbersHash) Ownable(initialOwner) {
        require(_token != address(0), "Invalid token address");
        require(_winningNumbersHash != bytes32(0), "Invalid hash");
    
        winningNumbersHash = _winningNumbersHash;
        isOpen = true; // Open ticket sales
        isRevealed = false;
        drawTimestamp = block.timestamp + 1 days; // Set the draw timestamp to 24 hours from deployment
        token = IERC20(_token);
        tokenDecimals = IERC20Metadata(_token).decimals(); // IERC20Metadata includes decimals()
        referralRewardPercent = 10;
    }

    /// @notice Allows players to purchase a ticket with selected numbers
    /// @param numbers An array of unique numbers between MIN_NUMBER and MAX_NUMBER
    /// @param amount The amount of tokens to stake
    /// @param referrer The address of the referrer
    function purchaseTicket(uint8[] calldata numbers, uint256 amount, address referrer) external whenNotPaused whenOpen nonReentrant {
        uint256 minTicketPrice = MIN_TICKET_PRICE * 10**tokenDecimals;
        uint256 maxTicketPrice = MAX_TICKET_PRICE * 10**tokenDecimals;
    
        require(amount >= minTicketPrice && amount <= maxTicketPrice, "Invalid amount: must be between 1 and 1000");
        token.safeTransferFrom(msg.sender, address(this), amount);
        _createTicket(numbers, amount);

        totalPool += amount;

        // Add player to the list if not already present
        if (!hasPurchased[msg.sender]) {
            players.push(msg.sender);
            hasPurchased[msg.sender] = true;
        }

        if (referrer != address(0) && referrer != msg.sender) {
            referralRewards[referrer] += (amount * referralRewardPercent) / 100;
        }
    }

    /// @notice Allows players to purchase multiple tickets with selected numbers
    /// @param numbers An array of arrays, each containing unique numbers between MIN_NUMBER and MAX_NUMBER
    /// @param amounts An array of amounts for each ticket
    /// @param referrer The address of the referrer
    function purchaseMultipleTickets(uint8[][] calldata numbers, uint256[] calldata amounts, address referrer) external whenNotPaused whenOpen nonReentrant {
        uint256 minTicketPrice = MIN_TICKET_PRICE * 10**tokenDecimals;
        uint256 maxTicketPrice = MAX_TICKET_PRICE * 10**tokenDecimals;

        require(numbers.length == amounts.length, "Invalid input lengths");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] >= minTicketPrice && amounts[i] <= maxTicketPrice, "Invalid amount: must be between 1 and 1000");
            totalAmount += amounts[i];
        }

        token.safeTransferFrom(msg.sender, address(this), totalAmount);
        for (uint256 i = 0; i < numbers.length; i++) {
            _createTicket(numbers[i], amounts[i]);
        }

        totalPool += totalAmount;

        // Add player to the list if not already present
        if (!hasPurchased[msg.sender]) {
            players.push(msg.sender);
            hasPurchased[msg.sender] = true;
        }

        if (referrer != address(0) && referrer != msg.sender) {
            referralRewards[referrer] += (totalAmount * referralRewardPercent) / 100;
        }
    }

    /// @notice Internal function to create a ticket
    /// @param numbers An array of unique numbers between MIN_NUMBER and MAX_NUMBER
    /// @param amount The amount of tokens staked
    function _createTicket(uint8[] calldata numbers, uint256 amount) internal {
        require(playerTickets[msg.sender].length < MAX_TICKETS_PER_PLAYER, "Ticket limit reached");
        require(validNumbers(numbers), "Invalid numbers");

        // Store the ticket
        Ticket memory newTicket = Ticket({
            numbers: numbers,
            claimed: false,
            amount: amount,
            player: msg.sender,
            prize: 0 // Prize will be calculated after winning numbers are revealed
        });

        allTickets.push(newTicket);
        playerTickets[msg.sender].push(allTickets.length - 1);

        emit TicketPurchased(msg.sender, winningNumbersHash, allTickets.length - 1, numbers);
    }

    /// @notice Owner reveals the winning numbers by providing the salt and numbers
    /// @param salt The secret salt used in the commitment
    /// @param numbers An array of 5 unique winning numbers
    function revealWinningNumbers(
        bytes32 salt,
        uint8[NUM_BALLS] calldata numbers
    ) external whenNotPaused onlyOwner whenOpen nonReentrant {
        require(!isRevealed, "Winning numbers already revealed");

        // Convert the fixed-size array to a dynamic array for validation
        uint8[] memory numbersDynamic = new uint8[](NUM_BALLS);
        for (uint8 i = 0; i < NUM_BALLS; i++) {
            numbersDynamic[i] = numbers[i];
        }

        require(validNumbers(numbersDynamic), "Invalid winning numbers");

        // Verify commitment
        bytes32 hash = keccak256(abi.encodePacked(salt, numbers));
        require(hash == winningNumbersHash, "Commitment does not match");

        // Set winning numbers
        for (uint8 i = 0; i < NUM_BALLS; i++) {
            winningNumbers[i] = numbers[i];
        }

        isRevealed = true;
        isOpen = false; // Close ticket sales

        uint256 ownerShare = totalPool / 10; // 10% of the pool goes to the owner
        token.safeTransfer(owner(), ownerShare); // 10% of the pool goes to the owner
        totalPool -= ownerShare;

        emit WinningNumbersRevealed(winningNumbers, winningNumbersHash);
    }

    /// @notice Players claim their prizes based on their tickets
    function claimPrize() external whenNotPaused whenRevealed nonReentrant {
        require(playerTickets[msg.sender].length > 0, "No tickets purchased");
        require(isRevealed, "Winning numbers not revealed yet");

        uint256[] storage ticketIds = playerTickets[msg.sender];
        uint256 totalPrize = 0;

        for (uint256 i = 0; i < ticketIds.length; i++) {
            Ticket storage ticket = allTickets[ticketIds[i]];
            calculatePrizes(ticket, winningNumbers);
            if (!ticket.claimed && ticket.prize > 0) {
                totalPrize += ticket.prize;
            }

            ticket.claimed = true;
            totalPool = totalPool - ticket.amount; // Decrement the total pool by the prize amount
        }

        if (totalPrize > 0) {
            token.safeTransfer(msg.sender, totalPrize);
            totalPool -= totalPrize; // Decrement the total pool by the prize amount
            emit PrizeClaimed(msg.sender, winningNumbersHash, totalPrize);
        } else {
            emit NoPrizeToClaimed(msg.sender, winningNumbersHash, totalPrize);
        }
    }

    /// @notice Calculates the prizes for all tickets after winning numbers are revealed
    /// @param ticket The ticket to calculate prizes for
    function calculatePrizes(Ticket storage ticket, uint8[NUM_BALLS] memory gameWinningNumbers) internal {
        if (!ticket.claimed) {
            uint8 matchingNumbers = countMatchingNumbers(ticket.numbers, gameWinningNumbers);

            // Check if the player matched all their selected numbers
            if (matchingNumbers == ticket.numbers.length) {
                // Prize is proportional to the amount staked and number of numbers matched
                uint256 multiplier = getMultiplier(ticket.numbers.length);
                ticket.prize = ticket.amount * multiplier;
            } else {
                ticket.prize = 0; // No prize if not all numbers matched
            }
        }
    }

    /// @notice Determines the multiplier based on the number of numbers selected
    /// @param numSelected The number of numbers the player selected
    /// @return multiplier The multiplier for the ticket
    function getMultiplier(uint256 numSelected) public pure returns (uint256 multiplier) {
        if (numSelected == 2) {
            multiplier = 240;
        } else if (numSelected == 3) {
            multiplier = 2100;
        } else if (numSelected == 4) {
            multiplier = 6000;
        } else if (numSelected == 5) {
            multiplier = 44000;
        } else {
            multiplier = 0;
        }
    }

    /// @notice Counts the number of matching numbers between two arrays
    /// @param numbers The player's selected numbers
    /// @param _winningNumbers The winning numbers
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

    /// @notice Gets the user's ticket IDs for the current game
    /// @param user The address of the user
    /// @return tickets An array of ticket IDs belonging to the user
    function getPlayerTickets(address user) external view returns (uint256[] memory) {
        return playerTickets[user];
    }

    /// @notice Gets the ticket details
    /// @param ticketId The ID of the ticket
    /// @return Ticket The details of the specified ticket
    function getTicket(uint256 ticketId) external view returns (Ticket memory) {
        require(ticketId < allTickets.length, "Ticket does not exist");
        return allTickets[ticketId];
    }

    /// @notice Gets the winning numbers for the current game
    /// @return winningNumbers The winning numbers
    function getWinningNumbers() external view returns (uint8[NUM_BALLS] memory) {
        return winningNumbers;
    }

    /// @notice Validates that the numbers are unique and within the valid range
    /// @param numbers The array of numbers
    /// @return isValid True if the numbers are valid
    function validNumbers(uint8[] memory numbers) internal pure returns (bool isValid) {
        if (numbers.length >= 2 && numbers.length <= NUM_BALLS) {
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
        } else {
            isValid = false;
        }
    }

    /// @notice Allows the referral rewards to be claimed by the referrer
    function claimReferralRewards() external whenNotPaused nonReentrant {
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No referral rewards to claim");

        referralRewards[msg.sender] = 0;
        token.safeTransfer(msg.sender, reward);
    }

    /// @notice Update referralRewardPercent amount
    /// @param percentAmount The new referral reward percentage (must be between 1 and 10)
    function updateReferralRewardPercent(uint8 percentAmount) external whenNotPaused onlyOwner {
        require(percentAmount > 0 && percentAmount <= 10, "Invalid percent amount");
        referralRewardPercent = percentAmount;
        emit ReferralRewardPercentUpdated(percentAmount);
    }

    /// @notice Withdraw all remaining tokens after cashout deadline
    function withdrawTokensAllFundsAfterCashoutDeadline() external onlyOwner nonReentrant() {
        require(block.timestamp > drawTimestamp + 3 days, "Cashout deadline not reached");
        uint256 contractBalance = token.balanceOf(address(this));
        token.safeTransfer(owner(), contractBalance);
    }

    /// @notice Deposit tokens into the contract
    /// @param amount The amount of tokens to deposit
    function depositTokens(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        token.safeTransferFrom(owner(), address(this), amount);
        totalPool += amount;
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }
}
