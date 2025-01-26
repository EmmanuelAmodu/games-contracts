// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/LotteryFactory.sol";

contract LotteryFactoryTestNetDeployer is Script {
    function run() external {
        vm.startBroadcast();
        console.log("Starting broadcast");

        bytes32 clientId = 0xb33237270006a2cb6b24935fc83a916d366f4c2a5b9ea8b91ea3b191606c11cf;
        address contractRegistry = 0x7b33B1263901a8cDE3b986b046218f7E7132C479;
        address initialOwner = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;
        address USDC = 0x9Ff6a0DC28dfc56858BDC677E77858E00BDF7D44;

        LotteryFactory lotteryFactory = new LotteryFactory(
            clientId,
            contractRegistry,
            initialOwner,
            USDC
        );
        console.log("LotteryFactory deployed at:", address(lotteryFactory));

        vm.stopBroadcast();
    }
}
