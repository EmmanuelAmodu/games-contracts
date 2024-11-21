// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/FreePlayLottery.sol";

// forge script script/FreeToPlayLottery.s.sol:FreeToPlayLotteryDeployer --broadcast --account pepper-deployer --rpc-url https://sly-damp-road.base-mainnet.quiknode.pro/7be795a85e70d1d223b6576b7b589970ab612649/
// forge verify-contract 0x14419015709d8fdf3753A6311688Cb856e86e4AE ./contracts/FreePlayLottery.sol:FreePlayLottery --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --chain 8453 --watch 

contract FreeToPlayLotteryDeployer is Script {
    function run() external {
        vm.startBroadcast();
        console.log("Starting broadcast");

        address initialOwner = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        FreePlayLottery freePlayLottery = new FreePlayLottery(initialOwner);
        Lottery lottery = new Lottery(initialOwner, address(freePlayLottery));
        freePlayLottery.setLotteryAddress(address(lottery));

        console.log("FreePlayLottery deployed at:", address(freePlayLottery));

        vm.stopBroadcast();
    }
}
