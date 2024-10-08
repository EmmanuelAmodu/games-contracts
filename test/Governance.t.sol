
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../contracts/Governance.sol";

contract GovernanceTest is Test {
    Governance public governance;
    address public owner;
    address public admin1;
    address public admin2;
    address public user1;

    function setUp() public {
        owner = vm.addr(1);
        admin1 = vm.addr(2);
        admin2 = vm.addr(3);
        user1 = vm.addr(4);

        // Start the prank from the owner address
        vm.startPrank(owner);

        // Deploy the Governance contract with the owner address
        governance = new Governance(owner);

        vm.stopPrank();
    }

    function testDeployment() public {
        assertEq(governance.owner(), owner);
    }

    function testAddAdmin() public {
        vm.startPrank(owner);

        // Add admin1
        governance.addAdmin(admin1);

        // Verify that admin1 is now an approved admin
        bool isAdmin = governance.approvedAdmins(admin1);
        assertTrue(isAdmin);

        vm.stopPrank();
    }

    function testRemoveAdmin() public {
        vm.startPrank(owner);

        // Add admin1
        governance.addAdmin(admin1);

        // Remove admin1
        governance.removeAdmin(admin1);

        // Verify that admin1 is no longer an approved admin
        bool isAdmin = governance.approvedAdmins(admin1);
        assertFalse(isAdmin);

        vm.stopPrank();
    }

    function testAddAdminByNonOwnerShouldFail() public {
        vm.startPrank(user1);

        // Try to add admin1 as a non-owner
        vm.expectRevert("Governance: Only owner can call");
        governance.addAdmin(admin1);

        vm.stopPrank();
    }

    function testRemoveAdminByNonOwnerShouldFail() public {
        vm.startPrank(owner);

        // Add admin1
        governance.addAdmin(admin1);

        vm.stopPrank();

        vm.startPrank(user1);

        // Try to remove admin1 as a non-owner
        vm.expectRevert("Governance: Only owner can call");
        governance.removeAdmin(admin1);

        vm.stopPrank();
    }

    function testTransferOwnership() public {
        vm.startPrank(owner);

        // Transfer ownership to user1
        governance.transferOwnership(user1);

        // Verify that the owner has been updated
        assertEq(governance.owner(), user1);

        vm.stopPrank();
    }

    function testTransferOwnershipByNonOwnerShouldFail() public {
        vm.startPrank(user1);

        // Try to transfer ownership as a non-owner
        vm.expectRevert("Governance: Only owner can call");
        governance.transferOwnership(user1);

        vm.stopPrank();
    }

    function testOnlyAdminFunctionality() public {
        // Create a mock contract that uses the onlyAdmin modifier
        MockAdminContract mockAdminContract = new MockAdminContract(governance);

        vm.startPrank(owner);
        // Add admin1
        governance.addAdmin(admin1);
        vm.stopPrank();

        vm.startPrank(admin1);
        // Call the function that requires onlyAdmin
        mockAdminContract.adminFunction();
        vm.stopPrank();

        vm.startPrank(user1);
        // Try to call the function as a non-admin
        vm.expectRevert("Governance: Only approved admin can call");
        mockAdminContract.adminFunction();
        vm.stopPrank();
    }

    function testIsAdminFunction() public {
        vm.startPrank(owner);
        governance.addAdmin(admin1);
        vm.stopPrank();

        // Check if admin1 is admin
        bool isAdmin = governance.isAdmin(admin1);
        assertTrue(isAdmin);

        // Check if user1 is admin
        isAdmin = governance.isAdmin(user1);
        assertFalse(isAdmin);
    }
}

// Mock contract to test onlyAdmin modifier
contract MockAdminContract {
    Governance public governance;

    constructor(Governance _governance) {
        governance = _governance;
    }

    modifier onlyAdmin() {
        require(governance.approvedAdmins(msg.sender), "Governance: Only approved admin can call");
        _;
    }

    function adminFunction() external onlyAdmin {
        // Functionality that only an admin can perform
    }
}
