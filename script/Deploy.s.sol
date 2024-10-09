// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/EventFactory.sol";
import "../contracts/CollateralManager.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address PEPRToken = 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3;
        address protocolFeeRecipient = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        // Deploy Governance
        Governance governance = new Governance(protocolFeeRecipient);
        // Deploy CollateralManager
        CollateralManager collateralManager = new CollateralManager(
            PEPRToken, // Protocol fee recipient
            address(governance), // Collateral token address (e.g., USDC)
            protocolFeeRecipient
        );

        // Deploy EventFactory
        EventFactory eventFactory = new EventFactory(
            address(collateralManager),
            address(governance)
        );

        console.log("Governance deployed at:", address(governance));
        console.log("CollateralManager deployed at:", address(collateralManager));
        console.log("EventFactory deployed at:", address(eventFactory));

        vm.stopBroadcast();
    }
}
