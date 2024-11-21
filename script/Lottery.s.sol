// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/Lottery.sol";

// forge script script/Lottery.s.sol:LotteryDeployer --broadcast --account pepper-deployer --rpc-url https://sly-damp-road.base-mainnet.quiknode.pro/7be795a85e70d1d223b6576b7b589970ab612649/
// forge verify-contract 0xCBB032344Cac8454519F9635f92C2582Bb337867 ./contracts/Lottery.sol:Lottery --constructor-args $(cast abi-encode "constructor(address,address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) --chain 8453 --watch 

contract LotteryDeployer is Script {
    function run() external {
        vm.startBroadcast();
        console.log("Starting broadcast");

        address initialOwner = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

        Lottery lottery = new Lottery(initialOwner, USDC);

        console.log("lotteryProxy deployed at:", address(lottery));

        vm.stopBroadcast();
    }
}
