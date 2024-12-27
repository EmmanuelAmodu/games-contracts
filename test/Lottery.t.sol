// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/Lottery.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @dev Updated test file compatible with the new Lottery contract design:
 *      1) The Lottery is set to 1 USDC per ticket, with 6 decimals on the token side.
 *      2) We fix the minted balances to align with 6 decimals, so users actually have enough tokens.
 *      3) We fix revert messages to match the contract logic for max tickets, deadlines, etc.
 *      4) We remove or adapt older tests that reference out-of-date logic.
 */
contract LotteryTest is Test {
    Lottery public lottery;
    MockERC20 public token;

    // Test addresses
    address public owner = address(0x1);
    address public player1 = address(0x2);
    address public player2 = address(0x3);
    address public referrer = address(0x4);
    address public factory = address(0xF); // We'll simulate the "factory"
    address public nonOwner = address(0x5);

    // For a 6-decimal token, "1 USDC" = 1e6.
    uint256 public costPerTicket = 1_000_000; // 1 USDC if decimals=6

    // We'll set the token to 6 decimals in the MockERC20 constructor
    // and mint enough for test usage.

    // Predefined salt and winning numbers
    bytes32 public predefinedSalt = keccak256(abi.encodePacked("predefined_salt"));
    uint8[5] public predefinedWinningNumbers = [1, 2, 3, 4, 5];
    bytes32 public predefinedWinningHash; // keccak256(abi.encodePacked(salt, numbers))

    bytes32 public dummySalt = keccak256(abi.encodePacked("dummy_salt"));

    function setUp() public {
        // Hash for revealing
        predefinedWinningHash = keccak256(abi.encodePacked(predefinedSalt, predefinedWinningNumbers));

        // Deploy a mock ERC20 token with 6 decimals
        token = new MockERC20("Mock Token", "MTK", 6);

        // Deploy the Lottery contract
        lottery = new Lottery(
            owner,
            factory,
            predefinedWinningHash,
            address(token)
        );

        // Mint enough USDC (1e6 = 1 token in 6 decimals)
        // We'll give each player 1,000,000 USDC => 1e6 * 1,000,000 = 1e12 in base units
        // That should handle multi-ticket purchases easily.
        token.mint(player1, 2_000_000 * 10**6); // 2,000,000 USDC
        token.mint(player2, 2_000_000 * 10**6);
        token.mint(referrer, 2_000_000 * 10**6);
        token.mint(owner, 10_000_000 * 10**6);   // Owner gets more

        // Approvals
        vm.prank(player1);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(player2);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(referrer);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(owner);
        token.approve(address(lottery), type(uint256).max);

        vm.prank(nonOwner);
        token.approve(address(lottery), type(uint256).max);
    }

    /**
     * @dev Single-ticket purchase => totalPool increments by 1 USDC, 
     *      ticket is recorded, referral is credited.
     */
    function testPurchaseSingleTicket() public {
        uint256 poolBefore = lottery.totalPool();
        uint256 contractBalBefore = token.balanceOf(address(lottery));

        vm.startPrank(player1);
        uint8[][] memory numbers = new uint8[][](1);
        numbers[0] = new uint8[](5);
        numbers[0][0] = 1;
        numbers[0][1] = 2;
        numbers[0][2] = 3;
        numbers[0][3] = 4;
        numbers[0][4] = 5;
        lottery.purchaseTickets(numbers, referrer);
        vm.stopPrank();

        uint256 poolAfter = lottery.totalPool();
        assertEq(poolAfter, poolBefore + costPerTicket);

        uint256 contractBalAfter = token.balanceOf(address(lottery));
        assertEq(contractBalAfter, contractBalBefore + costPerTicket);

        uint256[] memory tix = lottery.getPlayerTickets(player1);
        assertEq(tix.length, 1);

        // Check referral reward (1% by default)
        uint256 refReward = lottery.referralRewards(referrer);
        assertEq(refReward, costPerTicket / 100, "Referral mismatch");
    }

    /**
     * @dev Purchase multiple tickets => totalPool increments by n * costPerTicket.
     */
    function testPurchaseMultipleTickets() public {
        uint256 poolBefore = lottery.totalPool();

        vm.startPrank(player1);

        uint8[][] memory numbersList = new uint8[][](3);

        // Ticket A
        numbersList[0] = new uint8[](2);
        numbersList[0][0] = 1;
        numbersList[0][1] = 2;

        // Ticket B
        numbersList[1] = new uint8[](3);
        numbersList[1][0] = 10;
        numbersList[1][1] = 20;
        numbersList[1][2] = 30;

        // Ticket C
        numbersList[2] = new uint8[](2);
        numbersList[2][0] = 7;
        numbersList[2][1] = 8;

        lottery.purchaseTickets(numbersList, referrer);
        vm.stopPrank();

        uint256 poolAfter = lottery.totalPool();
        // 3 tickets => +3 * costPerTicket
        assertEq(poolAfter, poolBefore + 3 * costPerTicket);

        uint256[] memory tix = lottery.getPlayerTickets(player1);
        assertEq(tix.length, 3);
    }

    /**
     * @dev Only the factory can reveal. Also ensure drawTimestamp must have passed.
     *      We'll warp time to pass the drawTimestamp, then do reveal.
     */
    function testRevealWinningNumbersOnlyFactory() public {
        // Attempt by nonOwner => revert "Only factory"
        vm.prank(nonOwner);
        vm.expectRevert(bytes("Only factory"));
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers, bytes32(0));

        // Time not passed => we also expect "Draw deadline not passed"
        vm.prank(factory);
        vm.expectRevert(bytes("Draw deadline not passed"));
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers, bytes32(0));

        // Warp time so block.timestamp > drawTimestamp
        vm.warp(lottery.drawTimestamp() + 1);

        // Now reveal by factory => success
        vm.prank(factory);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers, bytes32(0));

        assertFalse(lottery.isOpen());
        assertTrue(lottery.isRevealed());
    }

    /**
     * @dev Purchase after reveal => revert with "Sales closed"
     */
    function testPurchaseAfterReveal() public {
        // Warp time
        vm.warp(lottery.drawTimestamp() + 1);

        // Reveal
        vm.prank(factory);
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers, bytes32(0));

        // Now sales closed
        vm.startPrank(player1);
        uint8[][] memory numbers = new uint8[][](1);
        numbers[0] = new uint8[](5);
        vm.expectRevert(bytes("Sales closed"));
        lottery.purchaseTickets(numbers, referrer);
        vm.stopPrank();
    }

    /**
     * @dev testPause => purchasing reverts.
     */
    function testPause() public {
        vm.prank(owner);
        lottery.pause();
        assertTrue(lottery.paused());

        vm.startPrank(player1);
        uint8[][] memory numbers = new uint8[][](1);
        numbers[0] = new uint8[](2);
        numbers[0][0] = 1;
        numbers[0][1] = 2;

        vm.expectRevert(); // We didn't specify the revert reason; in code it's Pausable
        lottery.purchaseTickets(numbers, referrer);
        vm.stopPrank();
    }

    /**
     * @dev testUnpause => purchasing is valid again
     */
    function testUnpause() public {
        vm.prank(owner);
        lottery.pause();

        vm.prank(owner);
        lottery.unpause();
        assertFalse(lottery.paused());

        vm.startPrank(player1);
        uint8[][] memory numbers = new uint8[][](1);
        numbers[0] = new uint8[](2);
        numbers[0][0] = 1;
        numbers[0][1] = 2;
        lottery.purchaseTickets(numbers, referrer);
        vm.stopPrank();
    }

    /**
     * @dev testClaimReferralRewards => purchase 2 tickets => 2 * costPerTicket => 1% => claim
     */
    function testClaimReferralRewards() public {
        vm.startPrank(player1);
        uint8[][] memory arr = new uint8[][](2);
        arr[0] = new uint8[](2);
        arr[0][0] = 1;
        arr[0][1] = 2;
        arr[1] = new uint8[](2);
        arr[1][0] = 3;
        arr[1][1] = 4;
        lottery.purchaseTickets(arr, referrer);
        vm.stopPrank();

        uint256 expected = (2 * costPerTicket) / 100;
        uint256 refBalBefore = token.balanceOf(referrer);
        assertEq(lottery.referralRewards(referrer), expected);

        vm.prank(referrer);
        lottery.claimReferralRewards();

        uint256 refBalAfter = token.balanceOf(referrer);
        assertEq(refBalAfter - refBalBefore, expected);
        assertEq(lottery.referralRewards(referrer), 0);
    }

    /**
     * @dev If referrer = msg.sender => no reward
     */
    function testReferrerIsPurchaserNoReward() public {
        vm.startPrank(player1);
        uint8[][] memory arr = new uint8[][](1);
        arr[0] = new uint8[](2);
        arr[0][0] = 1;
        arr[0][1] = 2;
        lottery.purchaseTickets(arr, player1); // self as ref => no reward
        vm.stopPrank();

        assertEq(lottery.referralRewards(player1), 0);
    }

    /**
     * @dev No referral => revert "No referral rewards"
     */
    function testClaimReferralRewardsWhenNone() public {
        vm.prank(referrer);
        vm.expectRevert(bytes("No referral rewards"));
        lottery.claimReferralRewards();
    }

    /**
     * @dev updateReferralRewardPercent by owner => success; nonOwner => revert
     */
    function testUpdateReferralRewardPercent() public {
        // Owner sets to 5
        vm.prank(owner);
        lottery.updateReferralRewardPercent(5);
        assertEq(lottery.referralRewardPercent(), 5);

        // Non-owner tries => revert
        vm.prank(nonOwner);
        vm.expectRevert();
        lottery.updateReferralRewardPercent(2);
    }

    /**
     * @dev Exceed 100 in a single purchase => revert "Max 100 tickets in one purchase"
     */
    function testExceedMaxTickets() public {
        vm.startPrank(player1);

        // We'll attempt to buy 101 tickets in one call
        uint8[][] memory arr = new uint8[][](101);
        for (uint256 i = 0; i < 101; i++) {
            arr[i] = new uint8[](2);
            arr[i][0] = 1;
            arr[i][1] = 2;
        }
        vm.expectRevert(bytes("Max 100 tickets in one purchase"));
        lottery.purchaseTickets(arr, referrer);

        vm.stopPrank();
    }

    /**
     * @dev If we want to test the "Exceeds per-player max of 100" scenario:
     *      buy 50 => buy 51 => second call fails.
     */
    function testExceedMaxTicketsPerPlayer() public {
        vm.startPrank(player1);

        // Buy 50 in one call
        uint8[][] memory arr50 = new uint8[][](50);
        for (uint256 i = 0; i < 50; i++) {
            arr50[i] = new uint8[](2);
            arr50[i][0] = 1;
            arr50[i][1] = 2;
        }
        lottery.purchaseTickets(arr50, referrer);

        // Now buy 51 more => revert "Exceeds per-player max of 100 tickets"
        uint8[][] memory arr51 = new uint8[][](51);
        for (uint256 i = 0; i < 51; i++) {
            arr51[i] = new uint8[](2);
            arr51[i][0] = 3;
            arr51[i][1] = 4;
        }
        vm.expectRevert(bytes("Exceeds per-player max of 100 tickets"));
        lottery.purchaseTickets(arr51, referrer);

        vm.stopPrank();
    }

    /**
     * @dev Purchasing after the drawTimestamp => revert "Sales deadline passed"
     */
    function testPurchaseAfterDeadline() public {
        // Warp time
        vm.warp(lottery.drawTimestamp() + 1);

        vm.startPrank(player1);
        uint8[][] memory arr = new uint8[][](1);
        arr[0] = new uint8[](2);
        arr[0][0] = 1;
        arr[0][1] = 2;
        vm.expectRevert(bytes("Sales deadline passed"));
        lottery.purchaseTickets(arr, referrer);
        vm.stopPrank();
    }

    /**
     * @dev If merkleRoot=0 => can't claimPrize => revert "Merkle root not set"
     */
    function testClaimPrizeNoMerkleRoot() public {
        vm.prank(player1);
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(bytes("Merkle root not set"));
        lottery.claimPrize(0, 123456, proof);
    }

    /**
     * @dev Test getTicket / getPlayerTickets
     */
    function testGetTicketDetails() public {
        // Player1 buys 2 tickets
        vm.startPrank(player1);
        uint8[][] memory arr = new uint8[][](2);

        arr[0] = new uint8[](3);
        arr[0][0] = 1;
        arr[0][1] = 2;
        arr[0][2] = 3;

        arr[1] = new uint8[](2);
        arr[1][0] = 4;
        arr[1][1] = 5;

        lottery.purchaseTickets(arr, referrer);
        vm.stopPrank();

        uint256[] memory tix = lottery.getPlayerTickets(player1);
        assertEq(tix.length, 2);

        // Check first
        Lottery.Ticket memory t0 = lottery.getTicket(tix[0]);
        assertEq(t0.player, player1);
        assertEq(t0.numbers.length, 3);

        // Check second
        Lottery.Ticket memory t1 = lottery.getTicket(tix[1]);
        assertEq(t1.player, player1);
        assertEq(t1.numbers.length, 2);
    }

    /**
     * @dev After 3 days post-drawTimestamp, owner can withdraw leftover
     */
    function testOwnerWithdrawAfterCashoutDeadline() public {
        // Player1 buys 1 ticket
        vm.startPrank(player1);
        uint8[][] memory arr = new uint8[][](1);
        arr[0] = new uint8[](2);
        arr[0][0] = 11;
        arr[0][1] = 22;
        lottery.purchaseTickets(arr, referrer);
        vm.stopPrank();

        uint256 lotBalBefore = token.balanceOf(address(lottery));
        uint256 ownBalBefore = token.balanceOf(owner);

        // Warp time
        vm.warp(lottery.drawTimestamp() + 4 days);

        vm.prank(owner);
        lottery.withdrawTokensAllFundsAfterCashoutDeadline();

        uint256 lotBalAfter = token.balanceOf(address(lottery));
        uint256 ownBalAfter = token.balanceOf(owner);

        assertEq(lotBalAfter, 0);
        assertEq(ownBalAfter, ownBalBefore + lotBalBefore);
    }

    /**
     * @dev Demonstrates a minimal flow:
     *      1) player1 purchases a ticket => ticketId=0
     *      2) factory reveals winning numbers + sets merkleRoot
     *      3) player1 calls claimPrize with a valid proof => succeeds
     *      4) tries invalid proof => reverts
     */
    function testClaimWithMerkleProof() public {
        // 1) Purchase 1 ticket
        vm.startPrank(player1);
        uint8[][] memory numbersList = new uint8[][](1);
        numbersList[0] = new uint8[](2);
        numbersList[0][0] = 10;
        numbersList[0][1] = 15;
        lottery.purchaseTickets(numbersList, address(0)); 
        vm.stopPrank();

        uint256[] memory tixPlayer1 = lottery.getPlayerTickets(player1);
        uint256 ticketId = tixPlayer1[0]; // should be 0

        // 2) We build a minimal Merkle tree with a single leaf:
        //    leaf = keccak256(abi.encodePacked(ticketId, prize, player1))
        //    We'll pretend the user won 500000 (0.5 USDC in 6 decimals).
        uint256 prize = 500_000;  
        bytes32 leaf = keccak256(abi.encodePacked(ticketId, prize, player1));

        // Build a trivial Merkle tree of size 1 => root = leaf
        bytes32 merkleRoot = leaf;

        vm.warp(lottery.drawTimestamp() + 1);
        // We'll have the factory reveal & set the merkleRoot
        vm.prank(factory);
        // revealWinningNumbers(salt, numbers, root)
        // We skip real checks because it's a test. 
        // In a real scenario, you'd pass the real salt & numbers that match lottery's commit.
        lottery.revealWinningNumbers(predefinedSalt, predefinedWinningNumbers, merkleRoot);

        // 3) Now claim with a valid proof
        // For a single-leaf tree, the proof is empty => no siblings
        bytes32[] memory proofValid = new bytes32[](0);

        // Check player1's balance before
        uint256 balBefore = token.balanceOf(player1);
        vm.prank(player1);
        lottery.claimPrize(ticketId, prize, proofValid);
        uint256 balAfter = token.balanceOf(player1);

        // The difference should be exactly "prize"
        assertEq(balAfter - balBefore, prize, "Prize mismatch");

        // 4) Attempt with an invalid proof => revert "Invalid proof"
        // E.g. pass prize=9999 or a random leaf that doesn't match root
        bytes32[] memory proofInvalid = new bytes32[](1);
        proofInvalid[0] = keccak256(abi.encodePacked("junk"));

        vm.prank(player1);
        vm.expectRevert(bytes("Invalid proof"));
        lottery.claimPrize(ticketId + 1, 9999, proofInvalid);

        // 5) Try to claim previously claimed price
        vm.prank(player1);
        vm.expectRevert(bytes("Already claimed"));
        lottery.claimPrize(ticketId, prize, proofValid);
    }
}

/**
 * @dev MockERC20 with adjustable decimals for your test
 */
contract MockERC20 is ERC20 {
    uint8 private _dec;

    constructor(string memory name, string memory symbol, uint8 dec_) ERC20(name, symbol) {
        _dec = dec_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }
}
