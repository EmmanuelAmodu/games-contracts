// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UserWallet {
    using SafeERC20 for IERC20;

    address public owner;
    address public relayer;

    // Nonce to prevent replay attacks
    uint256 public nonce;

    // Allowed contracts
    mapping(address => bool) public allowedContracts;

    // Events
    event Deposited(address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount);
    event ActionExecuted(address indexed to, uint256 value, bytes data);

    modifier onlyRelayer() {
        require(msg.sender == relayer, "Not authorized");
        _;
    }

    modifier onlyAllowedContract(address _contract) {
        require(allowedContracts[_contract], "Contract not allowed");
        _;
    }

    /// @notice Constructor
    /// @param _owner The owner of the wallet
    /// @param _relayer The relayer address
    constructor(address _owner, address _relayer) {
        owner = _owner;
        relayer = _relayer;
    }

    // Accept Ether deposits
    receive() external payable {
        emit Deposited(address(0), msg.value);
    }

    // Fallback function
    fallback() external payable {
        emit Deposited(address(0), msg.value);
    }

    /// @notice Execute an action on behalf of the user
    /// @param to The target contract address
    /// @param value The amount of Ether to send with the call
    /// @param data The calldata to execute
    /// @param _nonce The user's nonce to prevent replay attacks
    /// @param signature The user's signature authorizing the action
    function executeAction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 _nonce,
        bytes calldata signature
    ) external payable onlyRelayer onlyAllowedContract(to) {
        require(_nonce == nonce, "Invalid nonce");
        nonce++;

        // Verify the user's signature
        bytes32 messageHash = getMessageHash(to, value, data, _nonce);
        require(verifySignature(owner, messageHash, signature), "Invalid signature");

        // Execute the action
        (bool success, ) = to.call{value: value}(data);
        require(success, "Action execution failed");

        emit ActionExecuted(to, value, data);
    }

    /// @notice Allows the user to withdraw tokens
    /// @param token The token address (use address(0) for Ether)
    /// @param amount The amount to withdraw
    /// @param to The address to send the funds to
    function withdraw(
        address token,
        uint256 amount,
        address payable to
    ) external {
        require(msg.sender == owner, "Not the owner");

        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient balance");
            (bool success, ) = to.call{value: amount}("");
            require(success, "Ether transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }

        emit Withdrawn(token, amount);
    }

    /// @notice Generates the message hash for signature verification
    /// @param to The target contract address
    /// @param value The amount of Ether to send with the call
    /// @param data The calldata to execute
    /// @param _nonce The user's nonce
    function getMessageHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 _nonce
    ) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), to, value, data, _nonce));
    }

    /// @notice Verifies the signature
    /// @param signer The signer's address
    /// @param messageHash The hash to sign
    /// @param signature The signature
    function verifySignature(
        address signer,
        bytes32 messageHash,
        bytes calldata signature
    ) public pure returns (bool) {
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);

        address recoveredSigner = ecrecover(ethSignedMessageHash, v, r, s);
        return recoveredSigner == signer;
    }

    /// @notice Returns the Ethereum signed message hash
    /// @param messageHash The hash to sign
    function getEthSignedMessageHash(bytes32 messageHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    /// @notice Splits the signature into r, s, and v components
    /// @param sig The signature
    function splitSignature(bytes calldata sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
    }

    /// @notice Allows
    function setAllowedContract(address _contract, bool _allowed) external {
        require(msg.sender == owner, "Not the owner");
        allowedContracts[_contract] = _allowed;
    }

    /// @notice Allows the owner to change the relayer
    /// @param _newRelayer The new relayer address
    function setRelayer(address _newRelayer) external {
        require(msg.sender == owner, "Not the owner");
        require(_newRelayer != address(0), "Invalid address");
        relayer = _newRelayer;
    }
}
