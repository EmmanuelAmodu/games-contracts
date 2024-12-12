import { parseArgs } from "node:util";
import { lotteryFactoryAbi } from "./abis/lotteryFactory.abi";
import { lotteryAbi } from "./abis/lottery.abi";
require("dotenv").config();
import * as crypto from "node:crypto";
import {
  createPublicClient,
  createWalletClient,
  http,
  type Hex,
  publicActions,
  getContract,
  type Address,
  encodePacked,
  keccak256,
  isHex,
  size,
  bytesToHex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { anvil, base, baseSepolia, liskSepolia, lisk } from "viem/chains";

const { values } = parseArgs({
  args: Bun.argv,
  options: {
    commit: {
      type: "boolean",
    },
    reveal: {
      type: "boolean",
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
  throw new Error(
    "Please set PRIVATE_KEY, RPC_URL, and CONTRACT_ADDRESS in the .env file"
  );
}

export const publicClient = createPublicClient({
  batch: {
    multicall: true,
  },
  transport: http(RPC_URL),
});

const account = privateKeyToAccount(PRIVATE_KEY as Hex);
const walletClient = createWalletClient({
  account: account,
  transport: http(RPC_URL),
}).extend(publicActions);

// Initialize Contract Instance
const lotteryFactoryContract = getContract({
  address: CONTRACT_ADDRESS as Hex,
  abi: lotteryFactoryAbi,
  // 1b. Or public and/or wallet clients
  client: { public: publicClient, wallet: walletClient },
});

function generateWinningNumbersHash(saltHex: string, numbers: number[]): string {
  // Validate the salt
  if (!isHex(saltHex) || size(saltHex) !== 32) {
    throw new Error(
      "Invalid salt: Must be a 32-byte hex string starting with 0x"
    );
  }

  // Validate the numbers array
  if (!Array.isArray(numbers) || numbers.length !== 5) {
    throw new Error("Numbers array must contain exactly 5 elements");
  }

  // Ensure numbers are unique and within the valid range
  const numberSet = new Set<number>();
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
  const types = ["bytes32", "uint8[5]"];
  const values = [saltHex, numbers];

  // Encode the data using abi.encodePacked equivalent in viem
  const encodedData = encodePacked(types, values);

  // Compute the keccak256 hash
  const hash = keccak256(encodedData);

  return hash;
}

async function commitWinningNumbers(hash: string) {
  try {
    const tokenAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";
    const tx = await lotteryFactoryContract.write.deployLottery(
      [tokenAddress as Address, hash as Hex],
      {
        chain: anvil,
      }
    );

    lotteryFactoryContract.watchEvent.LotteryDeployed(
      {},
      {
        onLogs: (logs) => {
          console.log(logs);
        },
      }
    );

    console.log("Transaction submitted. Hash:", tx);
    console.log("commitWinningNumbers transaction confirmed.");
  } catch (error) {
    console.error("Error committing winning numbers:", error);
  }
}

async function revealWinningNumbers(saltHex: string, numbers: number[]) {
  try {
    const lotteryAddress = await lotteryFactoryContract.read.currentLottery();
    const lotteryContract = getContract({
      address: lotteryAddress,
      abi: lotteryAbi,
      client: { public: publicClient, wallet: walletClient },
    });

    const tx = await lotteryContract.write.revealWinningNumbers(
      [
        saltHex as Hex,
        numbers as unknown as readonly [number, number, number, number, number],
      ],
      {
        chain: anvil,
      }
    );

    console.log("Transaction submitted. Hash:", tx);

    lotteryContract.watchEvent.WinningNumbersRevealed(
      {},
      {
        onLogs: (logs) => {
          console.log("revealWinningNumbers transaction confirmed.");
          console.log(logs);
        },
      }
    );
  } catch (error) {
    console.error("Error revealing winning numbers:", error);
  }
}

// Example Usage
(async () => {
  if (values.commit) {
    console.log("Committing winning numbers...");

    // Generate a random salt (bytes32)
    const randomBytes = crypto.getRandomValues(new Uint8Array(32));
    const saltHex = bytesToHex(randomBytes);

    // Define your winning numbers (ensure they are unique and within 1-90)
    const winningNumbers = [0, 0, 0, 0, 0];

    let index = 0;

    while (index < winningNumbers.length) {
      const num = crypto.randomInt(1, 90);
      if (!winningNumbers.includes(num)) {
        winningNumbers[index] = num;
        index++;
      }
    }

    await Bun.write(
      GAME_VALUE_FILE,
      JSON.stringify({ saltHex, winningNumbers })
    );

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

    console.log(saltHex, winningNumbers);

    // Reveal the winning numbers
    await revealWinningNumbers(saltHex, winningNumbers);
  }
})();
