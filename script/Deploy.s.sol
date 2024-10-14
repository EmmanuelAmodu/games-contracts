// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/EventFactory.sol";
import "../contracts/CollateralManager.sol";

// forge script script/Deploy.s.sol:DeployScript --broadcast --account pepper-deployer
// forge verify-contract --chain-id 8453 0xB461E25623DFCC311C4eD11AD0163b6c9De0A266 ./contracts/Governance.sol:Governance --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch
// forge verify-contract --chain-id 8453 0x3552b9f4e4401619107179279f3F876cDd4F7170 ./contracts/CollateralManager.sol:CollateralManager --constructor-args $(cast abi-encode "constructor(address,address,address)" 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3 0xB461E25623DFCC311C4eD11AD0163b6c9De0A266 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch
// forge verify-contract --chain-id 8453 0x892D7b41f71c61351cdD13a0CB5b4cB4f0ea14FE ./contracts/EventFactory.sol:EventFactory --constructor-args $(cast abi-encode "constructor(address,address)" 0x3552b9f4e4401619107179279f3F876cDd4F7170 0xB461E25623DFCC311C4eD11AD0163b6c9De0A266) --watch

contract DeployScript is Script {
    function run() external {
        vm.createSelectFork("base");

        vm.startBroadcast();
        console.log("Starting broadcast");

        address PEPRToken = 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3;
        address protocolFeeRecipient = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        // Deploy Governance
        Governance governance = new Governance(protocolFeeRecipient);
        // Deploy CollateralManager
        CollateralManager collateralManager = new CollateralManager(
            PEPRToken,
            address(governance),
            protocolFeeRecipient
        );

        // Deploy EventFactory
        EventFactory eventFactory = new EventFactory(address(collateralManager), address(governance));

        console.log("Governance deployed at:", address(governance));
        console.log("CollateralManager deployed at:", address(collateralManager));
        console.log("EventFactory deployed at:", address(eventFactory));

        vm.stopBroadcast();
    }
}
