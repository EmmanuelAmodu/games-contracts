## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
forge script script/LotteryFactoryTestNet.s.sol:LotteryFactoryTestNetDeployer --broadcast --account pepper-deployer --rpc-url https://rpc.sepolia-api.lisk.com

forge verify-contract --rpc-url https://rpc.sepolia-api.lisk.com --verifier blockscout --verifier-url 'https://sepolia-blockscout.lisk.com/api/' --constructor-args $(cast abi-encode "constructor(address,address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722 0x9Ff6a0DC28dfc56858BDC677E77858E00BDF7D44) 0x7Cf08228EC01191c2693B9539D02B37DACCC3f24 contracts/LotteryFactory.sol:LotteryFactory --watch
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
