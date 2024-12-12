// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/LotteryFactory.sol";

contract LotteryFactoryDeployer is Script {
    function run() external {
        vm.startBroadcast();
        console.log("Starting broadcast");

        address initialOwner = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        LotteryFactory lotteryFactory = new LotteryFactory(initialOwner);
        console.log("LotteryFactory deployed at:", address(lotteryFactory));

        vm.stopBroadcast();
    }
}
