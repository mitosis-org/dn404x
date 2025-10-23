// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';

import { xMorseStaking } from '../src/xMorseStaking.sol';

/**
 * @title UpgradexMorseStaking
 * @notice Upgrades xMorseStaking proxy to new implementation (UUPS)
 * @dev Fixes Critical and Medium vulnerabilities:
 *      - [C-1] Reward token change DoS
 *      - [M-1] Precision loss tracking
 * 
 * Usage (Dognet):
 *   forge script script/UpgradexMorseStaking.s.sol \
 *     --rpc-url https://rpc.dognet.mitosis.org \
 *     --broadcast --verify
 * 
 * Usage (Mainnet):
 *   forge script script/UpgradexMorseStaking.s.sol \
 *     --sig "runMainnet()" \
 *     --rpc-url https://rpc.mitosis.org \
 *     --broadcast --verify
 */
contract UpgradexMorseStaking is Script {
  // Dognet addresses
  address constant STAKING_PROXY_DOGNET = 0xf8A91853A75Dd00aBA86E1C031e15cA740b5FBc7;
  
  // Mainnet addresses
  address constant STAKING_PROXY_MAINNET = 0xE48B0509fe69c97de24d223e33e28c787D5D7178;

  function run() external {
    _upgrade(STAKING_PROXY_DOGNET, "Dognet");
  }

  function runMainnet() external {
    _upgrade(STAKING_PROXY_MAINNET, "Mainnet");
  }

  function _upgrade(address proxyAddress, string memory network) internal {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Upgrading xMorseStaking on", network, "===");
    console2.log("Deployer:", deployer);
    console2.log("Proxy Address:", proxyAddress);
    console2.log("");

    xMorseStaking proxy = xMorseStaking(proxyAddress);

    // Get current state before upgrade
    console2.log("Current State:");
    console2.log("  Owner:", proxy.owner());
    console2.log("  xMorse Token:", proxy.xMorseToken());
    console2.log("  Mirror NFT:", proxy.mirrorNFT());
    console2.log("  Reward Token:", proxy.rewardToken());
    console2.log("  Total Staked NFTs:", proxy.getTotalStakedNFTs());
    console2.log("  Accumulated Rewards:", proxy.accRewardPerNFT());
    console2.log("  Lockup Period:", proxy.lockupPeriod() / 1 days, "days");
    
    // Check if we can query accumulatedDust (should fail on old implementation)
    try proxy.accumulatedDust() returns (uint256 dust) {
      console2.log("  Accumulated Dust:", dust);
      console2.log("");
      console2.log("WARNING: Contract already upgraded!");
      return;
    } catch {
      console2.log("  Accumulated Dust: (not available in old version)");
    }
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // 1. Deploy new implementation
    console2.log("1. Deploying new xMorseStaking implementation...");
    xMorseStaking newImpl = new xMorseStaking();
    console2.log("   New implementation deployed at:", address(newImpl));
    console2.log("");

    // 2. Upgrade proxy
    console2.log("2. Upgrading proxy to new implementation...");
    console2.log("   Calling upgradeToAndCall...");
    
    // No initialization data needed for upgrade
    bytes memory data = "";
    proxy.upgradeToAndCall(address(newImpl), data);
    
    console2.log("   Upgrade successful!");
    console2.log("");

    vm.stopBroadcast();

    // Verify upgrade
    console2.log("=== Verifying Upgrade ===");
    console2.log("");
    
    console2.log("New State:");
    console2.log("  Owner:", proxy.owner());
    console2.log("  xMorse Token:", proxy.xMorseToken());
    console2.log("  Reward Token:", proxy.rewardToken());
    console2.log("  Total Staked NFTs:", proxy.getTotalStakedNFTs());
    console2.log("  Accumulated Rewards:", proxy.accRewardPerNFT());
    console2.log("  Lockup Period:", proxy.lockupPeriod() / 1 days, "days");
    
    // New field should now be accessible
    try proxy.accumulatedDust() returns (uint256 dust) {
      console2.log("  Accumulated Dust:", dust, "(NEW FEATURE)");
    } catch {
      console2.log("  ERROR: accumulatedDust() still not accessible!");
    }
    console2.log("");

    console2.log("=== Upgrade Complete ===");
    console2.log("");
    console2.log("Fixes Applied:");
    console2.log("  [C-1] CRITICAL: Reward token change DoS vulnerability");
    console2.log("        - Added check to prevent token change with unclaimed rewards");
    console2.log("  [M-1] MEDIUM: Precision loss tracking");
    console2.log("        - Added accumulatedDust tracking");
    console2.log("        - Added withdrawDust() function for owner");
    console2.log("");
    console2.log("New Functions:");
    console2.log("  - accumulatedDust(): view accumulated precision loss");
    console2.log("  - withdrawDust(): owner can withdraw accumulated dust");
    console2.log("");
    console2.log("Deployment Info:");
    console2.log("  Proxy:", proxyAddress);
    console2.log("  New Implementation:", address(newImpl));
    console2.log("");
    console2.log("Next Steps:");
    console2.log("1. Monitor accumulatedDust():");
    console2.log("   cast call", proxyAddress, '"accumulatedDust()(uint256)" --rpc-url <RPC>');
    console2.log("");
    console2.log("2. Withdraw dust when needed:");
    console2.log("   cast send", proxyAddress, '"withdrawDust()" --rpc-url <RPC> --private-key $PRIVATE_KEY');
    console2.log("");
    console2.log("3. Reward token changes now require all rewards to be claimed first");
  }
}
