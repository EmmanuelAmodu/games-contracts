// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/Lottery.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// forge script script/LotteryProxy.s.sol:LotteryProxy --broadcast --account 2dmoon-deployer --rpc-url https://rpc.sepolia-api.lisk.com
// forge verify-contract 0xf81093539691337D3b36d1561451DA66165e828F ./contracts/CrashGame.sol:CrashGame --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722)--verifier blockscout --verifier-url https://sepolia-blockscout.lisk.com/api --chain 4202 --watch 

contract LotteryProxy is Script {
    function run() external {
        vm.startBroadcast();
        console.log("Starting broadcast");

        address initialOwner = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        address lotteryProxy = Upgrades.deployUUPSProxy(
            "Lottery.sol",
            abi.encodeCall(Lottery.initialize, (initialOwner, 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722))
        );

        console.log("lotteryProxy deployed at:", lotteryProxy);

        vm.stopBroadcast();
    }
}
