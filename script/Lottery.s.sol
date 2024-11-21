// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/Lottery.sol";

// forge script script/Lottery.s.sol:LotteryDeployer --broadcast --account pepper-deployer --rpc-url https://silent-thrilling-sea.base-sepolia.quiknode.pro/99f3a182ebb5acb7e0273692e76914b835b04e82/
// forge verify-contract 0xf81093539691337D3b36d1561451DA66165e828F ./contracts/CrashGame.sol:CrashGame --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722)--verifier blockscout --verifier-url https://sepolia-blockscout.lisk.com/api --chain 4202 --watch 

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
