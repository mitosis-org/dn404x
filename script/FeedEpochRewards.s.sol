// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';

import { xMorseStaking } from '../src/xMorseStaking.sol';
import { xMorseRewardFeed } from '../src/xMorseRewardFeed.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';

/**
 * @title FeedEpochRewards
 * @notice FEEDER bot script for automated epoch reward feeding
 * 
 * Process:
 *   1. Call xMorseStaking.claimFromValidator()
 *   2. Get gMITO balance and totalStakedNFTs
 *   3. Feed to xMorseRewardFeed
 *   4. Finalize epoch
 * 
 * Usage (Automated - run weekly):
 *   forge script script/FeedEpochRewards.s.sol \
 *     --rpc-url https://rpc.dognet.mitosis.org \
 *     --broadcast
 */
contract FeedEpochRewards is Script {
  // Dognet addresses
  address constant STAKING_DOGNET = 0xf8A91853A75Dd00aBA86E1C031e15cA740b5FBc7;
  address constant REWARD_FEED_DOGNET = address(0); // TODO: Update after deployment
  
  // Mainnet addresses
  address constant STAKING_MAINNET = 0xE48B0509fe69c97de24d223e33e28c787D5D7178;
  address constant REWARD_FEED_MAINNET = address(0); // TODO: Update after deployment

  function run() external {
    _feedEpoch(STAKING_DOGNET, REWARD_FEED_DOGNET, "Dognet");
  }

  function runMainnet() external {
    _feedEpoch(STAKING_MAINNET, REWARD_FEED_MAINNET, "Mainnet");
  }

  function _feedEpoch(address stakingAddress, address feedAddress, string memory network) internal {
    uint256 feederPrivateKey = vm.envUint("PRIVATE_KEY");
    address feeder = vm.addr(feederPrivateKey);

    console2.log("=== Feeding Epoch Rewards on", network, "===");
    console2.log("Feeder:", feeder);
    console2.log("Staking:", stakingAddress);
    console2.log("Reward Feed:", feedAddress);
    console2.log("");

    if (feedAddress == address(0)) {
      console2.log("ERROR: Reward Feed address not set!");
      revert("Reward Feed not configured");
    }

    xMorseStaking staking = xMorseStaking(stakingAddress);
    xMorseRewardFeed rewardFeed = xMorseRewardFeed(feedAddress);

    // Get current state
    uint256 nextEpoch = rewardFeed.nextEpoch();
    uint256 currentEpoch = rewardFeed.epochFeeder().epoch();
    
    console2.log("Current State:");
    console2.log("  Current Epoch:", currentEpoch);
    console2.log("  Next Epoch to Feed:", nextEpoch);
    console2.log("  Total Staked NFTs:", staking.getTotalStakedNFTs());
    console2.log("");

    if (nextEpoch >= currentEpoch) {
      console2.log("No epochs to feed yet. Current epoch not finished.");
      console2.log("Wait until epoch", nextEpoch, "completes.");
      return;
    }

    vm.startBroadcast(feederPrivateKey);

    // Step 1: Claim from validator (if configured)
    console2.log("Step 1: Claiming from ValidatorRewardDistributor...");
    uint256 claimed = 0;
    try staking.claimFromValidator() returns (uint256 amount) {
      claimed = amount;
      console2.log("  Claimed:", claimed / 1 ether, "ether");
    } catch {
      console2.log("  No validator configured or no rewards available");
    }
    console2.log("");

    // Step 2: Get available balance
    console2.log("Step 2: Checking available balance...");
    uint256 available = staking.availableForFeeding();
    console2.log("  Available for feeding:", available / 1 ether, "ether");
    console2.log("");

    if (available == 0) {
      console2.log("No rewards available to feed!");
      vm.stopBroadcast();
      return;
    }

    // Step 3: Get snapshot
    uint256 totalStakedNFTs = staking.getTotalStakedNFTs();
    
    if (totalStakedNFTs == 0) {
      console2.log("No NFTs staked! Cannot feed rewards.");
      vm.stopBroadcast();
      return;
    }

    // Step 4: Feed epoch data
    console2.log("Step 3: Feeding epoch", nextEpoch, "data...");
    console2.log("  Total Reward:", available / 1 ether, "ether");
    console2.log("  Total Staked NFTs:", totalStakedNFTs);
    
    rewardFeed.initializeEpochReward(nextEpoch, available, totalStakedNFTs);
    console2.log("  Epoch initialized!");
    console2.log("");

    // Step 5: Finalize epoch
    console2.log("Step 4: Finalizing epoch", nextEpoch, "...");
    rewardFeed.finalizeEpochReward(nextEpoch);
    console2.log("  Epoch finalized!");
    console2.log("");

    vm.stopBroadcast();

    // Verification
    console2.log("=== Epoch Feeding Complete ===");
    console2.log("");
    console2.log("Epoch", nextEpoch, "Summary:");
    console2.log("  Total Reward:", available / 1 ether, "ether");
    console2.log("  Total NFTs:", totalStakedNFTs);
    console2.log("  Reward per NFT:", (available / totalStakedNFTs) / 1 ether, "ether");
    console2.log("  Status: FINALIZED");
    console2.log("");
    console2.log("Users can now claim epoch", nextEpoch, "rewards!");
    console2.log("Next epoch to feed:", rewardFeed.nextEpoch());
  }
}

