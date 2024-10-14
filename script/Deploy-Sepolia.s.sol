// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/EventFactory.sol";
import "../contracts/CollateralManager.sol";

// forge script script/Deploy-Sepolia.s.sol:DeployScript --broadcast --account pepper-deployer

// forge verify-contract --chain-id 84532 0x68C3f8318F7371bDaFd31B6b089881256872712b ./contracts/Governance.sol:Governance \
// --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch

// forge verify-contract --chain-id 84532 0xe5d3CdB374EC5CEde0F98BAB2660bd78Df7B9ECb ./contracts/CollateralManager.sol:CollateralManager \
// --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x9Ff6a0DC28dfc56858BDC677E77858E00BDF7D44 0x68C3f8318F7371bDaFd31B6b089881256872712b 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch

// forge verify-contract --chain-id 84532 0xEe0593b670e5570598Ee0c979a0B75F16E5180b0 ./contracts/EventFactory.sol:EventFactory \
// --constructor-args $(cast abi-encode "constructor(address,address)" 0xe5d3CdB374EC5CEde0F98BAB2660bd78Df7B9ECb 0x68C3f8318F7371bDaFd31B6b089881256872712b) --watch

contract DeployScript is Script {
    function run() external {
        vm.createSelectFork("base-sepolia");

        vm.startBroadcast();
        console.log("Starting broadcast");

        address PEPRToken = 0x9Ff6a0DC28dfc56858BDC677E77858E00BDF7D44;
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
        EventFactory eventFactory = new EventFactory(address(collateralManager), address(governance));

        console.log("Governance deployed at:", address(governance));
        console.log("CollateralManager deployed at:", address(collateralManager));
        console.log("EventFactory deployed at:", address(eventFactory));

        vm.stopBroadcast();
    }
}
