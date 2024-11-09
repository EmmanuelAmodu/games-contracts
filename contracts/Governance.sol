// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

contract Governance {
    string public constant VERSION = "0.0.4";
    address public owner;
    mapping(address => bool) public approvedAdmins;

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event OwnerTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Governance: Only owner can call");
        _;
    }

    modifier onlyAdmin() {
        require(approvedAdmins[msg.sender], "Governance: Only approved admin can call");
        _;
    }

    constructor(address _owner) {
        require(_owner != address(0), "Governance: Owner address cannot be zero");
        owner = _owner;
        approvedAdmins[_owner] = true;
    }

    /**
     * @notice Adds a new admin. Can only be called by the owner.
     * @param _admin The address of the new admin.
     */
    function addAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "Governance: Admin address cannot be zero");
        require(!approvedAdmins[_admin], "Governance: Already an admin");
        approvedAdmins[_admin] = true;
        emit AdminAdded(_admin);
    }

    /**
     * @notice Removes an admin. Can only be called by the owner.
     * @param _admin The address of the admin to remove.
     */
    function removeAdmin(address _admin) external onlyOwner {
        require(approvedAdmins[_admin], "Governance: Not an admin");
        approvedAdmins[_admin] = false;
        emit AdminRemoved(_admin);
    }

    /**
     * @notice Transfers ownership to a new address. Can only be called by the current owner.
     * @param _newOwner The address of the new owner.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Governance: New owner cannot be zero address");

        owner = _newOwner;
        emit OwnerTransferred(owner, _newOwner);
    }

    /**
     * @notice Checks if an address is an approved admin.
     * @param _admin The address to check.
     * @return True if the address is an approved admin, false otherwise.
     */
    function isAdmin(address _admin) external view returns (bool) {
        return approvedAdmins[_admin];
    }
}
