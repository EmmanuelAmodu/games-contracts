export const lotteryAbi = [
  {
    "inputs": [
      {
        "internalType": "bytes32",
        "name": "_winningNumbersHash",
        "type": "bytes32"
      }
    ],
    "name": "commitWinningNumbers",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "bytes32",
        "name": "salt",
        "type": "bytes32"
      },
      {
        "internalType": "uint8[5]",
        "name": "numbers",
        "type": "uint8[5]"
      }
    ],
    "name": "revealWinningNumbers",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "winningNumbersHash",
    "outputs": [
      {
        "internalType": "bytes32",
        "name": "",
        "type": "bytes32"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  }
] as const;