import { ethers } from "ethers";
import { parseArgs } from "node:util";
import { lotteryAbi } from "./abis/lottery.abi";
require("dotenv").config();
import * as crypto from "node:crypto";

const { values } = parseArgs({
  args: Bun.argv,
  options: {
    commit: {
      type: 'boolean',
    },
    reveal: {
      type: 'boolean',
    },
  },
  strict: true,
  allowPositionals: true,
});

// Environment Variables
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const RPC_URL = process.env.RPC_URL;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const GAME_VALUE_FILE = process.env.GAME_VALUE_FILE;

// Validate Environment Variables
if (!PRIVATE_KEY || !RPC_URL || !CONTRACT_ADDRESS || !GAME_VALUE_FILE) {
  throw new Error("Please set PRIVATE_KEY, RPC_URL, and CONTRACT_ADDRESS in the .env file");
}

// Initialize Provider and Signer
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// Initialize Contract Instance
const lotteryContract = new ethers.Contract(CONTRACT_ADDRESS, lotteryAbi, wallet);

/**
 * Generates the winning numbers hash to commit to the Lottery contract.
 * @param {string} saltHex - A 66-character hexadecimal string starting with '0x' representing the salt (bytes32).
 * @param {number[]} numbers - An array of 5 unique uint8 numbers between 1 and 90.
 * @returns {string} - The keccak256 hash as a 66-character hexadecimal string.
 */
function generateWinningNumbersHash(saltHex: string, numbers: number[]): string {
  // Validate the salt
  if (
    !ethers.isHexString(saltHex) ||
    ethers.dataLength(saltHex) !== 32
  ) {
    throw new Error(
      "Invalid salt: Must be a 32-byte hex string starting with 0x"
    );
  }

  // Validate the numbers array
  if (!Array.isArray(numbers) || numbers.length !== 5) {
    throw new Error("Numbers array must contain exactly 5 elements");
  }

  // Ensure numbers are unique and within the valid range
  const numberSet = new Set();
  for (const num of numbers) {
    if (!Number.isInteger(num) || num < 1 || num > 90) {
      throw new Error("Each number must be an integer between 1 and 90");
    }
    if (numberSet.has(num)) {
      throw new Error("Duplicate numbers are not allowed");
    }
    numberSet.add(num);
  }

  // Prepare the types and values for encoding
  const types = ["bytes32", "uint8", "uint8", "uint8", "uint8", "uint8"];
  const values = [saltHex, ...numbers];

  // Encode the data using abi.encodePacked equivalent in Ethers.js
  const encodedData = ethers.solidityPacked(types, values);

  // Compute the keccak256 hash
  const hash = ethers.keccak256(encodedData);

  return hash;
}

/**
 * Commits the winning numbers hash to the Lottery contract.
 * @param {string} hash - The keccak256 hash of the salt and winning numbers.
 */
async function commitWinningNumbers(hash: string) {
  try {
    const tx = await lotteryContract.commitWinningNumbers(hash);
    console.log("Transaction submitted. Hash:", tx.hash);
    await tx.wait();
    console.log("commitWinningNumbers transaction confirmed.");
  } catch (error) {
    console.error("Error committing winning numbers:", error);
  }
}

/**
 * Reveals the winning numbers by providing the salt and the actual numbers.
 * @param {string} saltHex - The original salt used to generate the hash.
 * @param {number[]} numbers - The array of winning numbers.
 */
async function revealWinningNumbers(saltHex: string, numbers: number[]) {
  try {
    const tx = await lotteryContract.revealWinningNumbers(
      saltHex,
      numbers
    );
    console.log("Transaction submitted. Hash:", tx.hash);
    await tx.wait();
    console.log("revealWinningNumbers transaction confirmed.");
  } catch (error) {
    console.error("Error revealing winning numbers:", error);
  }
}

// Example Usage
(async () => {
  if (values.commit) {
    console.log("Committing winning numbers...");

    // Generate a random salt (bytes32)
    const randomBytes = ethers.randomBytes(32);
    const saltHex = ethers.hexlify(randomBytes);

    // Define your winning numbers (ensure they are unique and within 1-90)
    const winningNumbers = [0, 0, 0, 0, 0]

    let index = 0;

    while (index < winningNumbers.length) {
      const num = crypto.randomInt(1, 90);
      if(!winningNumbers.includes(num)) {
        winningNumbers[index] = num;
        index++;
      }
    }

    await Bun.write(GAME_VALUE_FILE, JSON.stringify({ saltHex, winningNumbers }));

    // Generate the hash
    const winningNumbersHash = generateWinningNumbersHash(
      saltHex,
      winningNumbers
    );

    // Commit the winning numbers hash
    await commitWinningNumbers(winningNumbersHash);
  }

  if (values.reveal) {
    console.log("Revealing winning numbers...");

    const data = await Bun.file(GAME_VALUE_FILE).text();
    const { saltHex, winningNumbers } = JSON.parse(data);

    // Reveal the winning numbers
    await revealWinningNumbers(saltHex, winningNumbers);
  }
})();
