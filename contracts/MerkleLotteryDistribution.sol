// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MerkleLotteryDistribution
 * @notice Example contract that stores a Merkle root for final ticket prizes.
 *         Users claim with a proof. There's no on-chain loop over tickets.
 */
abstract contract MerkleLotteryDistribution is Ownable {
    using SafeERC20 for IERC20;

    // USDC token
    IERC20 public immutable usdc;

    // The Merkle root for (ticketId, prize) pairs
    bytes32 public merkleRoot;

    // Keep track of which tickets have been claimed
    mapping(uint256 => bool) public isClaimed;

    event MerkleRootSet(bytes32 root);
    event PrizeClaimed(uint256 ticketId, address claimer, uint256 amount);

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    /**
     * @notice Sets the new merkle root after you've computed final rewards off-chain.
     *         Only owner can call.
     */
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        merkleRoot = newRoot;
        emit MerkleRootSet(newRoot);
    }

    /**
     * @notice Users call this to claim their final prize for a given `ticketId`.
     * @param ticketId The ticket ID.
     * @param prize The prize amount (in USDC) for this ticket.
     * @param merkleProof The Merkle proof showing that (ticketId, prize) is in the distribution.
     */
    function claimPrize(
        uint256 ticketId,
        uint256 prize,
        bytes32[] calldata merkleProof
    ) external {
        require(merkleRoot != bytes32(0), "Merkle root not set");
        require(!isClaimed[ticketId], "Already claimed");

        // 1) Reconstruct the leaf
        bytes32 leaf = keccak256(abi.encodePacked(ticketId, prize, msg.sender));
        // If you want to store user address in the leaf, include `msg.sender`.

        // 2) Verify proof => root
        bool valid = MerkleProof.verify(merkleProof, merkleRoot, leaf);
        require(valid, "Invalid proof");

        // Mark claimed
        isClaimed[ticketId] = true;

        // Transfer USDC
        require(usdc.balanceOf(address(this)) >= prize, "Not enough USDC in contract");
        usdc.safeTransfer(msg.sender, prize);

        emit PrizeClaimed(ticketId, msg.sender, prize);
    }
}
