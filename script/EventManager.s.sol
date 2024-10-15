// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/EventManager.sol";
import "../contracts/Governance.sol";

// forge script script/EventManager.s.sol:DeployEventManager --broadcast --account pepper-deployer
// forge verify-contract --chain-id 8453 0x75C4A34B13a891679241A34bEfA3c5a83bFE032a ./contracts/EventManager.sol:EventManager --constructor-args $(cast abi-encode "constructor(address,address,address)" 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3 0x5a684137fddb5dFF6e2276906BDbf0510F022FBc 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch

contract DeployEventManager is Script {
    function run() external {
        vm.createSelectFork("base");

        vm.startBroadcast();
        console.log("Starting broadcast");

        address PEPRToken = 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3;
        address protocolFeeRecipient = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;
        address governance = 0x5a684137fddb5dFF6e2276906BDbf0510F022FBc;

        // Deploy CollateralManager
        EventManager eventManager = new EventManager(
            PEPRToken, // Protocol fee recipient
            governance, // Collateral token address (e.g., USDC)
            protocolFeeRecipient
        );

        console.log("CollateralManager deployed at:", address(eventManager));

        vm.stopBroadcast();
    }
}
