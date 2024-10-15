// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/Governance.sol";

// forge script script/GovernanceManager.s.sol:DeployGovernanceManager --broadcast --account pepper-deployer
// forge verify-contract --chain-id 8453 0x5a684137fddb5dFF6e2276906BDbf0510F022FBc ./contracts/Governance.sol:Governance --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch

contract DeployGovernanceManager is Script {
    function run() external {
        vm.createSelectFork("base");

        vm.startBroadcast();
        console.log("Starting broadcast");

        address protocolFeeRecipient = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        // Deploy Governance
        Governance governance = new Governance(protocolFeeRecipient);

        console.log("Governance deployed at:", address(governance));

        vm.stopBroadcast();
    }
}
