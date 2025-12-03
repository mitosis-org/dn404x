// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { EpochFeeder } from '@mitosis/hub/validator/EpochFeeder.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

/**
 * @title DeploySimpleEpochFeeder
 * @notice Deploys EpochFeeder for epoch timing
 * 
 * Usage (Dognet):
 *   forge script script/DeploySimpleEpochFeeder.s.sol \
 *     --rpc-url https://rpc.dognet.mitosis.org \
 *     --broadcast
 */
contract DeploySimpleEpochFeeder is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Deploying EpochFeeder ===");
    console2.log("Deployer:", deployer);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // Deploy implementation
    console2.log("1. Deploying EpochFeeder implementation...");
    EpochFeeder impl = new EpochFeeder();
    console2.log("   Implementation:", address(impl));
    console2.log("");

    // Calculate initial epoch time (next Monday 00:00 UTC)
    uint48 now_ = uint48(block.timestamp);
    uint48 interval = 604800; // 1 week
    
    // Round up to next Monday
    uint48 daysUntilMonday = uint48((8 - ((now_ / 86400 + 4) % 7)) % 7);
    if (daysUntilMonday == 0) daysUntilMonday = 7; // If today is Monday, start next Monday
    
    uint48 initialEpochTime = now_ + (daysUntilMonday * 86400);
    
    console2.log("2. Deploying EpochFeeder proxy...");
    console2.log("   Initial Epoch Time:", initialEpochTime);
    console2.log("   Interval: 1 week (604800 seconds)");
    
    bytes memory initData = abi.encodeCall(
      EpochFeeder.initialize,
      (
        deployer,         // owner
        initialEpochTime, // first epoch starts next Monday
        interval          // 1 week
      )
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    EpochFeeder feeder = EpochFeeder(address(proxy));
    
    console2.log("   Proxy:", address(feeder));
    console2.log("");

    vm.stopBroadcast();

    // Verification
    console2.log("=== Deployment Complete ===");
    console2.log("");
    console2.log("EpochFeeder:");
    console2.log("  Proxy:", address(feeder));
    console2.log("  Implementation:", address(impl));
    console2.log("  Owner:", deployer);
    console2.log("  Current Epoch:", feeder.epoch());
    console2.log("  Interval:", feeder.interval(), "seconds");
    console2.log("  Interval (days):", feeder.interval() / 86400);
    console2.log("");
    console2.log("Next Steps:");
    console2.log("1. Deploy xMorseRewardFeed with this EpochFeeder address");
    console2.log("2. Upgrade xMorseStaking to V2");
  }
}

