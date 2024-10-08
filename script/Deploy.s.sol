// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "../contracts/EventFactory.sol";
// import "../contracts/CollateralManager.sol";

// contract DeployScript is Script {
//     function run() external {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         address PEPRToken = 0xd587E2E5Df410C7b92F573f260110C4b6e79C1a3;
//         // Deploy CollateralManager
//         CollateralManager collateralManager = new CollateralManager(
//             msg.sender, // Protocol fee recipient
//             address(PEPRToken) // Collateral token address (e.g., USDC)
//         );

//         // Deploy EventFactory
//         EventFactory eventFactory = new EventFactory(address(collateralManager));

//         vm.stopBroadcast();
//     }
// }
