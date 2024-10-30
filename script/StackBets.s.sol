// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../contracts/StackBets.sol";

// forge script script/StackBets.s.sol:DeployStackBets --broadcast --account pepper-deployer --chain-id 8453
// forge verify-contract --chain-id 8453 0x5a684137fddb5dFF6e2276906BDbf0510F022FBc ./contracts/Governance.sol:Governance --constructor-args $(cast abi-encode "constructor(address)" 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722) --watch

contract DeployStackBets is Script {
    function run() external {
        vm.startBroadcast();
        console.log("Starting broadcast");

        address protocolFeeRecipient = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;
        address eventManager = 0x5a684137fddb5dFF6e2276906BDbf0510F022FBc; // Please replace this with the actual address of the EventManager contract
        address PEPRToken = 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3;

        // Deploy Governance
        StackBets stackBets = new StackBets(protocolFeeRecipient, eventManager, PEPRToken);

        console.log("Governance deployed at:", address(stackBets));

        vm.stopBroadcast();
    }
}
