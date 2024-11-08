// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/CrashGame.sol";

// forge script script/CrashGame.s.sol:DeployCrashGame --broadcast --account pepper-deployer --chain-id 8453
// forge verify-contract 0x3FF32159B36103d9706bfB1e9DBB6d78A90AABfc ./contracts/CrashGame.sol:CrashGame --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722)--verifier blockscout --verifier-url https://sepolia-blockscout.lisk.com/api --chain 4202 --watch 

contract DeployCrashGame is Script {
    function run() external {
        vm.startBroadcast();
        console.log("Starting broadcast");

        address initialOwner = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        // Deploy CollateralManager
        CrashGame crashGame = new CrashGame(initialOwner);

        console.log("CrashGame deployed at:", address(crashGame));

        vm.stopBroadcast();
    }
}
