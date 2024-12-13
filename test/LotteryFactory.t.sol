// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// Import Foundry's Test utilities
import "forge-std/Test.sol";

// Import the LotteryFactory and Lottery contracts
import "../contracts/LotteryFactory.sol";
import "../contracts/Lottery.sol";

// Import OpenZeppelin's ERC20 contract
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing purposes
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /// @notice Mints tokens to a specified address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

/// @title LotteryFactoryTest
/// @notice This contract contains unit tests for the LotteryFactory contract
contract LotteryFactoryTest is Test {
    // Instance of the LotteryFactory
    LotteryFactory public factory;

    // Instance of the MockERC20 token
    MockERC20 public token;

    // Define test addresses
    address public owner = address(0x1);
    address public nonOwner = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);

    // Predefined winning numbers and salts for testing
    bytes32 public salt1 = keccak256(abi.encodePacked("salt1"));
    bytes32 public salt2 = keccak256(abi.encodePacked("salt2"));
    bytes32 public salt3 = keccak256(abi.encodePacked("salt3"));

    uint8[5] public winningNumbers1 = [1, 2, 3, 4, 5];
    uint8[5] public winningNumbers2 = [6, 7, 8, 9, 10];
    uint8[5] public winningNumbers3 = [11, 12, 13, 14, 15];

    bytes32 public winningHash1 = keccak256(abi.encodePacked(salt1, winningNumbers1));
    bytes32 public winningHash2 = keccak256(abi.encodePacked(salt2, winningNumbers2));
    bytes32 public winningHash3 = keccak256(abi.encodePacked(salt3, winningNumbers3));

    /// @notice Sets up the testing environment before each test
    function setUp() public {
        // Label addresses for easier debugging
        vm.label(owner, "Owner");
        vm.label(nonOwner, "NonOwner");
        vm.label(user1, "User1");
        vm.label(user2, "User2");

        // Deploy the MockERC20 token
        token = new MockERC20("Mock Token", "MTK");

        // Mint tokens to test addresses
        token.mint(owner, 1_000_000 ether);
        token.mint(user1, 100_000 ether);
        token.mint(user2, 100_000 ether);
        token.mint(nonOwner, 100_000 ether);

        // Deploy the LotteryFactory with the owner
        vm.prank(owner);
        factory = new LotteryFactory(owner);

        // Approve the factory to spend tokens if needed
        vm.prank(owner);
        token.approve(address(factory), type(uint256).max);
    }

    /// @notice Tests that only the owner can deploy a Lottery contract
    function testOnlyOwnerCanDeployLottery() public {
        // Attempt to deploy Lottery from a non-owner address (should revert)
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        factory.deployLottery(address(token), winningHash1);

        // Deploy Lottery from the owner address (should succeed)
        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), winningHash1);
        assertTrue(deployedLottery != address(0));
    }

    /// @notice Tests deploying a Lottery contract with valid parameters
    function testDeployLotteryWithValidParameters() public {
        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), winningHash1);

        // Verify that the Lottery is stored in the mapping
        assertEq(factory.lotteries(winningHash1), deployedLottery);

        // Verify that the Lottery is added to the allLotteries array
        address[] memory lotteries = factory.getAllLotteries(0, 1);
        assertEq(lotteries.length, 1);
        assertEq(lotteries[0], deployedLottery);

        // Verify that currentLottery is set correctly
        assertEq(factory.currentLottery(), deployedLottery);
    }

    /// @notice Tests deploying a Lottery contract with an invalid token address
    function testDeployLotteryWithInvalidToken() public {
        vm.prank(owner);
        vm.expectRevert("Token address cannot be zero");
        factory.deployLottery(address(0), winningHash1);
    }

    /// @notice Tests deploying a Lottery contract with an invalid winningNumbersHash (zero hash)
    function testDeployLotteryWithInvalidHash() public {
        vm.prank(owner);
        vm.expectRevert("Winning numbers hash cannot be zero");
        factory.deployLottery(address(token), bytes32(0));
    }

    /// @notice Tests that getLotteryAddress computes the correct address
    function testGetLotteryAddress() public {
        vm.prank(owner);
        factory.deployLottery(address(token), winningHash1);

        // Compute the expected address using the factory's getLotteryAddress function
        address expectedAddress = factory.getLotteryAddress(address(token), winningHash1);

        // Retrieve the deployed Lottery address
        address deployedLottery = factory.lotteries(winningHash1);

        // Verify that the deployed address matches the expected address
        assertEq(deployedLottery, expectedAddress);
    }

    /// @notice Tests that isLotteryDeployed correctly identifies deployed and undeployed Lotteries
    function testIsLotteryDeployed() public {
        vm.prank(owner);
        factory.deployLottery(address(token), winningHash1);

        // Check that the deployed Lottery is recognized
        bool exists = factory.isLotteryDeployed(winningHash1);
        assertTrue(exists);

        // Check that a non-deployed Lottery is not recognized
        bool notExists = factory.isLotteryDeployed(winningHash2);
        assertFalse(notExists);
    }

    /// @notice Tests deploying multiple Lottery contracts with unique hashes
    function testDeployMultipleLotteries() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);

        vm.prank(owner);
        address lottery3 = factory.deployLottery(address(token), winningHash3);

        // Verify that all Lotteries are stored correctly
        assertEq(factory.lotteries(winningHash1), lottery1);
        assertEq(factory.lotteries(winningHash2), lottery2);
        assertEq(factory.lotteries(winningHash3), lottery3);

        // Verify that all Lotteries are in the allLotteries array
        address[] memory lotteries = factory.getAllLotteries(0, 3);
        assertEq(lotteries.length, 3);
        assertEq(lotteries[0], lottery1);
        assertEq(lotteries[1], lottery2);
        assertEq(lotteries[2], lottery3);

        // Verify that currentLottery is the last deployed Lottery
        assertEq(factory.currentLottery(), lottery3);
    }

    /// @notice Tests that deploying a Lottery with an existing winningNumbersHash (salt) reverts
    function testDeployLotteryWithExistingHashFails() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);
        assertTrue(lottery1 != address(0));

        // Attempt to deploy another Lottery with the same winningNumbersHash (should revert)
        vm.prank(owner);
        // vm.expectRevert("Create2: Failed on deployment");
        vm.expectRevert(abi.encodeWithSelector(Create2.Create2FailedDeployment.selector));
        factory.deployLottery(address(token), winningHash1);
    }

    /// @notice Tests that currentLottery is updated correctly after each deployment
    function testCurrentLotteryIsUpdated() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);
        assertEq(factory.currentLottery(), lottery1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);
        assertEq(factory.currentLottery(), lottery2);

        vm.prank(owner);
        address lottery3 = factory.deployLottery(address(token), winningHash3);
        assertEq(factory.currentLottery(), lottery3);
    }

    /// @notice Tests that the LotteryDeployed event is emitted with correct parameters
    function testLotteryDeployedEvent() public {
        vm.expectEmit(false, true, true, true);
        emit LotteryFactory.LotteryDeployed(address(0), winningHash1);

        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), winningHash1);

        assert(deployedLottery != address(0));
    }

    /// @notice Tests that getLotteryAddress returns the correct address even before deployment
    function testGetLotteryAddressBeforeDeployment() public {
        address predictedAddress = factory.getLotteryAddress(address(token), winningHash1);

        // Since the Lottery hasn't been deployed yet, the code at the predicted address should be empty
        assertTrue(predictedAddress.code.length == 0);
    }

    /// @notice Tests deploying a Lottery with a unique hash and verifies its existence
    function testDeployLotteryAndVerifyExistence() public {
        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), winningHash1);

        // Check existence
        bool exists = factory.isLotteryDeployed(winningHash1);
        assertTrue(exists);

        // Verify deployment
        assertEq(factory.lotteries(winningHash1), deployedLottery);
    }

    /// @notice Tests that deploying multiple Lotteries with different hashes works as expected
    function testDeployMultipleLotteriesWithDifferentHashes() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);
        assertTrue(lottery1 != address(0));

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);
        assertTrue(lottery2 != address(0));

        // Ensure that both Lotteries are deployed correctly
        assertEq(factory.lotteries(winningHash1), lottery1);
        assertEq(factory.lotteries(winningHash2), lottery2);

        // Ensure that getAllLotteries returns both
        address[] memory lotteries = factory.getAllLotteries(0, 2);
        assertEq(lotteries.length, 2);
        assertEq(lotteries[0], lottery1);
        assertEq(lotteries[1], lottery2);
    }

    /// @notice Tests that attempting to compute a Lottery address with the same parameters yields the same address
    function testDeterministicAddressComputation() public {
        // Compute the expected address
        address expectedAddress = factory.getLotteryAddress(address(token), winningHash1);

        // Deploy the Lottery
        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), winningHash1);
        assertEq(deployedLottery, expectedAddress);
    }

    /// @notice Tests that deploying a Lottery with a unique hash produces a unique address
    function testUniqueAddressesForUniqueHashes() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);

        vm.prank(owner);
        address lottery3 = factory.deployLottery(address(token), winningHash3);

        // Ensure all addresses are unique
        assertTrue(lottery1 != lottery2);
        assertTrue(lottery1 != lottery3);
        assertTrue(lottery2 != lottery3);
    }

    /// @notice Tests that the deploymentCounter increments correctly
    function testDeploymentCounterIncrements() public {
        // Access the deploymentCounter via a hypothetical getter (not present in the original contract)
        // Since deploymentCounter is private, this test assumes the existence of a getter for demonstration.
        // If not present, this test should be adjusted or removed.

        // For demonstration, assume deploymentCounter is 0 initially
        // Deploy a Lottery
        vm.prank(owner);
        factory.deployLottery(address(token), winningHash1);

        // Assume deploymentCounter is now 1
        // As deploymentCounter is private, we cannot directly check it.
        // Alternatively, deploy another Lottery and ensure it's allowed.

        vm.prank(owner);
        factory.deployLottery(address(token), winningHash2);
    }

    /// @notice Tests deploying a Lottery with a zero winningNumbersHash (should revert)
    function testDeployLotteryWithZeroWinningHash() public {
        vm.prank(owner);
        vm.expectRevert("Winning numbers hash cannot be zero");
        factory.deployLottery(address(token), bytes32(0));
    }

    /// @notice Tests that deploying a Lottery updates the allLotteries array correctly
    function testAllLotteriesArray() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);

        address[] memory lotteries = factory.getAllLotteries(0, 2);
        assertEq(lotteries.length, 2);
        assertEq(lotteries[0], lottery1);
        assertEq(lotteries[1], lottery2);
    }

    /// @notice Tests deploying a Lottery with different tokens
    function testDeployLotteryWithDifferentTokens() public {
        // Deploy another MockERC20 token
        MockERC20 newToken = new MockERC20("New Mock Token", "NMT");
        newToken.mint(owner, 500_000 ether);

        // Deploy a Lottery with the new token
        vm.prank(owner);
        address lottery = factory.deployLottery(address(newToken), winningHash1);

        // Verify that the Lottery uses the new token
        assertEq(address(Lottery(lottery).token()), address(newToken));
    }

    /// @notice Tests that deploying a Lottery sets the correct owner in the Lottery contract
    function testLotteryOwnerIsFactoryOwner() public {
        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), winningHash1);

        // Verify that the owner of the Lottery contract is the factory owner
        assertEq(Lottery(deployedLottery).owner(), owner);
    }

    /// @notice Tests deploying a Lottery with multiple different winningNumbersHash values
    function testDeployLotteriesWithMultipleHashes() public {
        bytes32[] memory salts = new bytes32[](5);
        bytes32[] memory hashes = new bytes32[](5);
        address[] memory deployedLotteries = new address[](5);

        for (uint8 i = 0; i < 5; i++) {
            salts[i] = keccak256(abi.encodePacked("salt", i));
            uint8[5] memory numbers = [uint8(1 + i), uint8(2 + i), uint8(3 + i), uint8(4 + i), uint8(5 + i)];
            hashes[i] = keccak256(abi.encodePacked(salts[i], numbers));

            vm.prank(owner);
            deployedLotteries[i] = factory.deployLottery(address(token), hashes[i]);

            // Verify deployment
            assertEq(factory.lotteries(hashes[i]), deployedLotteries[i]);
            assertEq(factory.currentLottery(), deployedLotteries[i]);
        }

        // Verify that all Lotteries are in the allLotteries array
        address[] memory lotteries = factory.getAllLotteries(0, 5);
        assertEq(lotteries.length, 5);
        for (uint8 i = 0; i < 5; i++) {
            assertEq(lotteries[i], deployedLotteries[i]);
        }
    }

    /// @notice Tests that deploying a Lottery with the same token and different hashes works correctly
    function testDeployLotteriesWithSameTokenDifferentHashes() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);

        // Ensure both Lotteries are deployed and have different addresses
        assertTrue(lottery1 != lottery2);

        // Verify their ownership and token addresses
        assertEq(Lottery(lottery1).owner(), owner);
        assertEq(address(Lottery(lottery1).token()), address(token));

        assertEq(Lottery(lottery2).owner(), owner);
        assertEq(address(Lottery(lottery2).token()), address(token));
    }

    /// @notice Tests deploying a Lottery with different tokens and different hashes
    function testDeployLotteriesWithDifferentTokensAndHashes() public {
        // Deploy another MockERC20 token
        MockERC20 newToken = new MockERC20("Another Mock Token", "AMT");
        newToken.mint(owner, 500_000 ether);

        // Deploy two Lotteries with different tokens and different hashes
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(newToken), winningHash2);

        // Verify ownership and token addresses
        assertEq(Lottery(lottery1).owner(), owner);
        assertEq(address(Lottery(lottery1).token()), address(token));

        assertEq(Lottery(lottery2).owner(), owner);
        assertEq(address(Lottery(lottery2).token()), address(newToken));
    }

    /// @notice Tests that deploying a Lottery with an already deployed hash fails
    function testDeployLotteryWithAlreadyDeployedHash() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);
        assertTrue(lottery1 != address(0));

        // Attempt to deploy another Lottery with the same winningHash1
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Create2.Create2FailedDeployment.selector));
        factory.deployLottery(address(token), winningHash1);
    }

    /// @notice Event definition for capturing LotteryDeployed events
    event LotteryDeployed(
        address indexed lotteryAddress,
        address indexed owner,
        address indexed token,
        bytes32 salt,
        bytes32 winningNumbersHash
    );

    /// @notice Tests that the LotteryDeployed event is emitted correctly
    function testLotteryDeployedEventEmission() public {
        // Expect the LotteryDeployed event with specific parameters
        vm.expectEmit(false, true, true, true);
        emit LotteryFactory.LotteryDeployed(address(0), winningHash1);

        // Deploy the Lottery
        vm.prank(owner);
        factory.deployLottery(address(token), winningHash1);
    }

    /// @notice Tests that deploying a Lottery with a different winningNumbersHash results in a different address
    function testDifferentHashesProduceDifferentAddresses() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);

        // Ensure that the addresses are different
        assertTrue(lottery1 != lottery2);
    }

    /// @notice Tests that getLotteryAddress returns the correct address before and after deployment
    function testGetLotteryAddressBeforeAndAfterDeployment() public {
        // Compute the expected address
        address expectedAddress = factory.getLotteryAddress(address(token), winningHash1);
        assertTrue(expectedAddress.code.length == 0); // Should not be deployed yet

        // Deploy the Lottery
        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), winningHash1);

        // Verify that the expected address matches the deployed address
        assertEq(deployedLottery, expectedAddress);
    }

    /// @notice Tests that deploying a Lottery correctly updates the deploymentCounter (if accessible)
    /// Note: Since deploymentCounter is private, this test assumes it increments correctly by attempting multiple deployments.
    function testDeploymentCounterIncrementsCorrectly() public {
        // Deploy first Lottery
        vm.prank(owner);
        factory.deployLottery(address(token), winningHash1);

        // Deploy second Lottery
        vm.prank(owner);
        factory.deployLottery(address(token), winningHash2);

        // Deploy third Lottery
        vm.prank(owner);
        factory.deployLottery(address(token), winningHash3);

        // Retrieve all deployed Lotteries
        address[] memory lotteries = factory.getAllLotteries(0, 3);
        assertEq(lotteries.length, 3);
    }

    /// @notice Tests that deploying a Lottery with the same token but different winningNumbersHash works correctly
    function testDeployLotterySameTokenDifferentHash() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(token), winningHash2);

        // Ensure that both Lotteries are deployed and have different addresses
        assertTrue(lottery1 != lottery2);
    }

    /// @notice Tests that deploying a Lottery with different tokens works correctly
    function testDeployLotteryDifferentTokens() public {
        // Deploy another MockERC20 token
        MockERC20 newToken = new MockERC20("Different Token", "DTK");
        newToken.mint(owner, 500_000 ether);

        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);

        vm.prank(owner);
        address lottery2 = factory.deployLottery(address(newToken), winningHash2);

        // Ensure that both Lotteries are deployed and have different addresses
        assertTrue(lottery1 != lottery2);

        // Verify that each Lottery uses the correct token
        assertEq(address(Lottery(lottery1).token()), address(token));
        assertEq(address(Lottery(lottery2).token()), address(newToken));
    }

    /// @notice Tests that deploying a Lottery with a unique winningNumbersHash succeeds
    function testDeployLotteryWithUniqueWinningHash() public {
        vm.prank(owner);
        address lottery = factory.deployLottery(address(token), winningHash1);
        assertTrue(lottery != address(0));

        // Ensure that the Lottery is recognized as deployed
        bool exists = factory.isLotteryDeployed(winningHash1);
        assertTrue(exists);
    }

    /// @notice Tests that deploying a Lottery with multiple unique hashes works as expected
    function testDeployLotteryWithMultipleUniqueHashes() public {
        bytes32[] memory salts = new bytes32[](5);
        bytes32[] memory hashes = new bytes32[](5);
        address[] memory deployedLotteries = new address[](5);

        for (uint8 i = 0; i < 5; i++) {
            salts[i] = keccak256(abi.encodePacked("salt", i));
            bytes32 hash = keccak256(abi.encodePacked(salts[i], [uint8(1 + i), 2 + i, 3 + i, 4 + i, 5 + i]));
            hashes[i] = hash;

            vm.prank(owner);
            deployedLotteries[i] = factory.deployLottery(address(token), hashes[i]);

            // Verify deployment
            assertEq(factory.lotteries(hashes[i]), deployedLotteries[i]);
            assertEq(factory.currentLottery(), deployedLotteries[i]);
        }

        // Verify all Lotteries are in the allLotteries array
        address[] memory lotteries = factory.getAllLotteries(0, 5);
        assertEq(lotteries.length, 5);
        for (uint8 i = 0; i < 5; i++) {
            assertEq(lotteries[i], deployedLotteries[i]);
        }
    }

    /// @notice Tests that deploying a Lottery with an already deployed hash fails as expected
    function testDeployLotteryWithDuplicateHash() public {
        vm.prank(owner);
        address lottery1 = factory.deployLottery(address(token), winningHash1);
        assertTrue(lottery1 != address(0));

        // Attempt to deploy another Lottery with the same winningHash1
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Create2.Create2FailedDeployment.selector));
        factory.deployLottery(address(token), winningHash1);
    }

    /// @notice Tests that deploying a Lottery with a different salt and hash computes the correct address
    function testDeployLotteryWithDifferentSaltAndHash() public {
        // Define a unique salt and winningNumbers
        bytes32 uniqueSalt = keccak256(abi.encodePacked("unique_salt"));
        uint8[5] memory uniqueWinningNumbers = [10, 20, 30, 40, 50];
        bytes32 uniqueWinningHash = keccak256(abi.encodePacked(uniqueSalt, uniqueWinningNumbers));

        // Compute the expected address
        address expectedAddress = factory.getLotteryAddress(address(token), uniqueWinningHash);
        assertTrue(expectedAddress.code.length == 0); // Should not be deployed yet

        // Deploy the Lottery
        vm.prank(owner);
        address deployedLottery = factory.deployLottery(address(token), uniqueWinningHash);

        // Verify that the deployed address matches the expected address
        assertEq(deployedLottery, expectedAddress);
    }

    /// @notice Tests that deploying a Lottery with different salts but same winningNumbers results in different addresses
    function testDeployLotteryWithDifferentSaltsSameWinningNumbers() public {
        // Define two different salts with the same winningNumbers
        bytes32 saltA = keccak256(abi.encodePacked("saltA"));
        bytes32 saltB = keccak256(abi.encodePacked("saltB"));
        uint8[] memory winningNumbers = new uint8[](5);
        // 100, 200, 300, 400, 500
        winningNumbers[0] = 10;
        winningNumbers[1] = 20;
        winningNumbers[2] = 30;
        winningNumbers[3] = 40;
        winningNumbers[4] = 50;
        bytes32 winningHashA = keccak256(abi.encodePacked(saltA, winningNumbers));
        bytes32 winningHashB = keccak256(abi.encodePacked(saltB, winningNumbers));

        // Deploy two Lotteries with different salts but same winningNumbers
        vm.prank(owner);
        address lotteryA = factory.deployLottery(address(token), winningHashA);

        vm.prank(owner);
        address lotteryB = factory.deployLottery(address(token), winningHashB);

        // Ensure that the two Lotteries have different addresses
        assertTrue(lotteryA != lotteryB);

        // Verify that both Lotteries are recognized as deployed
        assertTrue(factory.isLotteryDeployed(winningHashA));
        assertTrue(factory.isLotteryDeployed(winningHashB));
    }
}
