// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/EventManager.sol";
import "../contracts/Governance.sol";

// forge script script/Deploy.s.sol:DeployScript --broadcast --account pepper-deployer

// forge verify-contract --chain-id 8453 0x7af7dD7B9F669132a0f0803f2F297d99cdF33DfE ./contracts/Governance.sol:Governance --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch
// forge verify-contract --chain-id 8453 0xF420d1ae17edA3E942a77045fac25439109bAD94 ./contracts/CollateralManager.sol:CollateralManager --constructor-args $(cast abi-encode "constructor(address,address,address)" 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3 0x7af7dD7B9F669132a0f0803f2F297d99cdF33DfE 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch
// forge verify-contract --chain-id 8453 0xe0A1dE2224092625773f53531625A4e6402b707C ./contracts/EventFactory.sol:EventFactory --constructor-args $(cast abi-encode "constructor(address,address)" 0xF420d1ae17edA3E942a77045fac25439109bAD94 0x7af7dD7B9F669132a0f0803f2F297d99cdF33DfE) --watch

contract DeployScript is Script {
    function run() external {
        vm.createSelectFork("base");

        vm.startBroadcast();
        console.log("Starting broadcast");

        address PEPRToken = 0x9Ff6a0DC28dfc56858BDC677E77858E00BDF7D44;
        address protocolFeeRecipient = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        // Deploy Governance
        Governance governance = new Governance(protocolFeeRecipient);
        // Deploy CollateralManager
        EventManager collateralManager = new EventManager(
            PEPRToken, // Protocol fee recipient
            address(governance), // Collateral token address (e.g., USDC)
            protocolFeeRecipient
        );

        console.log("Governance deployed at:", address(governance));
        console.log("CollateralManager deployed at:", address(collateralManager));

        vm.stopBroadcast();
    }
}
