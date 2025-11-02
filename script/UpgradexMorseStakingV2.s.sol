// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';

import { xMorseStaking } from '../src/xMorseStaking.sol';
import { xMorseRewardFeed } from '../src/xMorseRewardFeed.sol';

/**
 * @title UpgradexMorseStakingV2
 * @notice Upgrades xMorseStaking to V2 with epoch-based reward feed
 * 
 * Features:
 *   - Epoch-based reward distribution
 *   - External FEEDER control
 *   - Eliminates owner timing manipulation
 *   - Compatible with ValidatorRewardDistributor
 * 
 * Usage (Dognet):
 *   forge script script/UpgradexMorseStakingV2.s.sol \
 *     --sig "run(address)" <REWARD_FEED_ADDRESS> \
 *     --rpc-url https://rpc.dognet.mitosis.org \
 *     --broadcast --verify
 */
contract UpgradexMorseStakingV2 is Script {
  // Dognet addresses
  address constant STAKING_PROXY_DOGNET = 0xf8A91853A75Dd00aBA86E1C031e15cA740b5FBc7;
  
  // Mainnet addresses
  address constant STAKING_PROXY_MAINNET = 0xE48B0509fe69c97de24d223e33e28c787D5D7178;

  function run(address rewardFeedAddress) external {
    _upgrade(STAKING_PROXY_DOGNET, rewardFeedAddress, "Dognet");
  }

  function runMainnet(address rewardFeedAddress) external {
    _upgrade(STAKING_PROXY_MAINNET, rewardFeedAddress, "Mainnet");
  }

  function _upgrade(address proxyAddress, address rewardFeedAddress, string memory network) internal {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Upgrading xMorseStaking to V2 on", network, "===");
    console2.log("Deployer:", deployer);
    console2.log("Proxy Address:", proxyAddress);
    console2.log("Reward Feed:", rewardFeedAddress);
    console2.log("");

    xMorseStaking proxy = xMorseStaking(proxyAddress);
    xMorseRewardFeed rewardFeed = xMorseRewardFeed(rewardFeedAddress);

    // Get current state before upgrade
    console2.log("Current State (V1):");
    console2.log("  Owner:", proxy.owner());
    console2.log("  xMorse Token:", proxy.xMorseToken());
    console2.log("  Reward Token:", proxy.rewardToken());
    console2.log("  Total Staked NFTs:", proxy.getTotalStakedNFTs());
    console2.log("  Lockup Period:", proxy.lockupPeriod() / 1 days, "days");
    
    // Check if already upgraded
    try proxy.rewardFeed() returns (address currentFeed) {
      if (currentFeed != address(0)) {
        console2.log("  Reward Feed:", currentFeed);
        console2.log("");
        console2.log("WARNING: Contract may already be upgraded to V2!");
        return;
      }
    } catch {
      console2.log("  Reward Feed: (not available - V1)");
    }
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // 1. Deploy new implementation
    console2.log("1. Deploying new xMorseStaking V2 implementation...");
    xMorseStaking newImpl = new xMorseStaking();
    console2.log("   New implementation:", address(newImpl));
    console2.log("");

    // 2. Upgrade proxy
    console2.log("2. Upgrading proxy to V2...");
    bytes memory data = "";
    proxy.upgradeToAndCall(address(newImpl), data);
    console2.log("   Upgrade successful!");
    console2.log("");

    // 3. Configure reward feed
    console2.log("3. Configuring reward feed...");
    proxy.setRewardFeed(rewardFeedAddress);
    console2.log("   Reward feed configured!");
    console2.log("");

    vm.stopBroadcast();

    // Verify upgrade
    console2.log("=== Verifying V2 Upgrade ===");
    console2.log("");
    
    console2.log("New State (V2):");
    console2.log("  Owner:", proxy.owner());
    console2.log("  Reward Feed:", proxy.rewardFeed());
    console2.log("  Total Staked NFTs:", proxy.getTotalStakedNFTs());
    console2.log("  Lockup Period:", proxy.lockupPeriod() / 1 days, "days");
    console2.log("  Epoch Feeder:", address(rewardFeed.epochFeeder()));
    console2.log("  Next Epoch:", rewardFeed.nextEpoch());
    console2.log("");

    console2.log("=== Upgrade Complete ===");
    console2.log("");
    console2.log("V2 Features:");
    console2.log("  - Epoch-based reward distribution");
    console2.log("  - FEEDER-controlled feeding");
    console2.log("  - No more owner timing manipulation");
    console2.log("  - Users claim from finalized epochs");
    console2.log("");
    console2.log("New Functions:");
    console2.log("  - setRewardFeed(address): Configure reward feed");
    console2.log("  - claimFromValidator(): Claim gMITO from validator");
    console2.log("  - availableForFeeding(): Check balance for feeding");
    console2.log("  - rewardFeed(): View reward feed address");
    console2.log("  - lastClaimedEpoch(uint256): View last claimed epoch");
    console2.log("");
    console2.log("Deprecated (but still callable for backward compat):");
    console2.log("  - distributeRewards(): Use claimFromValidator() + FEEDER instead");
    console2.log("");
    console2.log("Deployment Info:");
    console2.log("  Proxy:", proxyAddress);
    console2.log("  Implementation V2:", address(newImpl));
    console2.log("  Reward Feed:", rewardFeedAddress);
  }
}

