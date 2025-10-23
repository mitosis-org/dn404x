// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { xMorseStaking } from '../src/xMorseStaking.sol';
import { IxMorseStaking } from '../src/interfaces/IxMorseStaking.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';

/**
 * @title ManageStakingRewards
 * @notice Rewards distribution and monitoring for xMorseStaking
 * @dev Owner/operator operations for managing rewards and viewing staking information
 * 
 * Available Functions:
 *   - distributeRewards(address proxy) - Distribute rewards to stakers
 *   - viewStakingInfo(address proxy) - View comprehensive staking statistics
 *   - viewUserStakes(address proxy, address user) - View user's staked NFTs
 *   - fundAndDistribute(address proxy, uint256 amount) - Fund + distribute in one tx
 *   - testRewardCycle(address proxy, uint256 amount) - Complete test cycle
 * 
 * Usage Examples:
 *   # Distribute rewards
 *   forge script script/ManageStakingRewards.s.sol \
 *     --sig "distributeRewards(address)" <PROXY> \
 *     --rpc-url <RPC_URL> --broadcast
 * 
 *   # View staking info (read-only)
 *   forge script script/ManageStakingRewards.s.sol \
 *     --sig "viewStakingInfo(address)" <PROXY> \
 *     --rpc-url <RPC_URL>
 * 
 *   # View user stakes (read-only)
 *   forge script script/ManageStakingRewards.s.sol \
 *     --sig "viewUserStakes(address,address)" <PROXY> <USER> \
 *     --rpc-url <RPC_URL>
 * 
 *   # Fund and distribute
 *   forge script script/ManageStakingRewards.s.sol \
 *     --sig "fundAndDistribute(address,uint256)" <PROXY> <AMOUNT> \
 *     --rpc-url <RPC_URL> --broadcast
 */
contract ManageStakingRewards is Script {
  using SafeERC20 for IERC20;

  //====================================================================================//
  //================================== DISTRIBUTE REWARDS ==============================//
  //====================================================================================//

  /// @notice Distribute available rewards to all staked NFTs
  function distributeRewards(address proxy) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Distributing Rewards ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    // Check if caller is authorized
    address owner = staking.owner();
    address operator = staking.operator();
    console2.log("Owner:", owner);
    console2.log("Operator:", operator);
    
    if (deployer != owner && deployer != operator) {
      console2.log("");
      console2.log("ERROR: You are not authorized to distribute rewards");
      console2.log("Only owner or operator can call this function");
      revert("Not authorized");
    }
    console2.log("");

    // Get current state
    uint256 totalStaked = staking.getTotalStakedNFTs();
    address rewardToken = staking.rewardToken();
    uint256 balance = IERC20(rewardToken).balanceOf(proxy);
    uint256 oldAccReward = staking.accRewardPerNFT();

    console2.log("Pre-Distribution State:");
    console2.log("  Total Staked NFTs:", totalStaked);
    console2.log("  Reward Token:", rewardToken);
    console2.log("  Contract Balance:", balance);
    console2.log("  Current Acc Reward Per NFT:", oldAccReward);
    console2.log("");

    if (totalStaked == 0) {
      console2.log("ERROR: No NFTs staked in the pool");
      revert("No stakers");
    }

    vm.startBroadcast(deployerPrivateKey);
    staking.distributeRewards();
    vm.stopBroadcast();

    // Get new state
    uint256 newAccReward = staking.accRewardPerNFT();
    uint256 distributed = (newAccReward - oldAccReward) * totalStaked / 1e18;

    console2.log("Distribution Complete!");
    console2.log("");
    console2.log("Post-Distribution State:");
    console2.log("  New Acc Reward Per NFT:", newAccReward);
    console2.log("  Rewards Distributed:", distributed);
    console2.log("  Rewards Per NFT:", distributed / totalStaked);
    console2.log("");
  }

  //====================================================================================//
  //================================== VIEW STAKING INFO ===============================//
  //====================================================================================//

  /// @notice View comprehensive staking information
  function viewStakingInfo(address proxy) external view {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== xMorseStaking Information ===");
    console2.log("Proxy:", proxy);
    console2.log("");

    // Core configuration
    console2.log("Configuration:");
    console2.log("  Owner:", staking.owner());
    console2.log("  Operator:", staking.operator());
    console2.log("  xMorse Token:", staking.xMorseToken());
    console2.log("  Mirror NFT:", staking.mirrorNFT());
    console2.log("  Reward Token:", staking.rewardToken());
    console2.log("");

    // Staking statistics
    uint256 totalStaked = staking.getTotalStakedNFTs();
    uint256 accRewardPerNFT = staking.accRewardPerNFT();
    uint256 lockupPeriod = staking.lockupPeriod();

    console2.log("Staking Statistics:");
    console2.log("  Total Staked NFTs:", totalStaked);
    console2.log("  Acc Reward Per NFT:", accRewardPerNFT);
    console2.log("  Lockup Period:", lockupPeriod, "seconds");
    console2.log("  Lockup Period (days):", lockupPeriod / 1 days);
    console2.log("");

    // Token balances
    address rewardToken = staking.rewardToken();
    address xMorseToken = staking.xMorseToken();
    
    console2.log("Contract Balances:");
    try IERC20(rewardToken).balanceOf(proxy) returns (uint256 rewardBalance) {
      console2.log("  Reward Token Balance:", rewardBalance);
      
      try IERC20Metadata(rewardToken).symbol() returns (string memory symbol) {
        console2.log("    Symbol:", symbol);
      } catch {}
    } catch {
      console2.log("  Reward Token Balance: (unable to fetch)");
    }

    try IERC20(xMorseToken).balanceOf(proxy) returns (uint256 xMorseBalance) {
      console2.log("  xMorse Token Balance:", xMorseBalance);
    } catch {
      console2.log("  xMorse Token Balance: (unable to fetch)");
    }
    console2.log("");

    // Validator settings
    address distributor = staking.validatorRewardDistributor();
    address validator = staking.validatorAddress();
    
    console2.log("Validator Integration:");
    console2.log("  Validator Reward Distributor:", distributor);
    console2.log("  Validator Address:", validator);
    
    if (distributor != address(0) && validator != address(0)) {
      console2.log("  Auto-claim Status: ENABLED");
    } else {
      console2.log("  Auto-claim Status: DISABLED");
    }
    console2.log("");

    // Reward distribution calculations
    if (totalStaked > 0) {
      console2.log("Reward Distribution Info:");
      console2.log("  Rewards distributed so far:", (accRewardPerNFT * totalStaked) / 1e18);
      console2.log("  Average rewards per NFT:", accRewardPerNFT / 1e18);
      console2.log("");
    }
  }

  //====================================================================================//
  //================================== VIEW USER STAKES ================================//
  //====================================================================================//

  /// @notice View user's staked NFTs and pending rewards
  function viewUserStakes(address proxy, address user) external view {
    if (proxy == address(0) || user == address(0)) {
      revert("Invalid address");
    }

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== User Staking Information ===");
    console2.log("Proxy:", proxy);
    console2.log("User:", user);
    console2.log("");

    uint256[] memory tokenIds = staking.getStakedNFTs(user);
    
    if (tokenIds.length == 0) {
      console2.log("No NFTs staked by this user");
      console2.log("");
      return;
    }

    console2.log("Total Staked NFTs:", tokenIds.length);
    console2.log("");

    uint256 totalPending = 0;

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      IxMorseStaking.NFTInfo memory info = staking.getNFTInfo(tokenId);
      uint256 pending = staking.getPendingRewards(tokenId);

      console2.log("NFT #", tokenId, ":");
      console2.log("  Staked At:", info.stakedAt);
      console2.log("  Lockup End:", info.lockupEndTime);
      
      if (block.timestamp >= info.lockupEndTime) {
        console2.log("  Lockup Status: UNLOCKED (can unstake)");
      } else {
        uint256 remaining = info.lockupEndTime - block.timestamp;
        console2.log("  Lockup Status: LOCKED");
        console2.log("    Days remaining:", remaining / 1 days);
        console2.log("    Hours remaining:", remaining % 1 days / 1 hours);
      }
      
      console2.log("  Pending Rewards:", pending);
      console2.log("");

      totalPending += pending;
    }

    console2.log("Summary:");
    console2.log("  Total NFTs Staked:", tokenIds.length);
    console2.log("  Total Pending Rewards:", totalPending);
    console2.log("");

    if (totalPending > 0) {
      console2.log("To claim rewards:");
      console2.log("  cast send", proxy, '"claimAllRewards()" --rpc-url <RPC_URL>');
    }
    console2.log("");
  }

  //====================================================================================//
  //================================== FUND AND DISTRIBUTE =============================//
  //====================================================================================//

  /// @notice Fund contract with reward tokens and distribute
  function fundAndDistribute(address proxy, uint256 amount) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }
    if (amount == 0) {
      revert("Amount must be greater than 0");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);
    address rewardToken = staking.rewardToken();

    console2.log("=== Fund and Distribute ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("Reward Token:", rewardToken);
    console2.log("Amount to Fund:", amount);
    console2.log("");

    // Check caller's balance
    uint256 callerBalance = IERC20(rewardToken).balanceOf(deployer);
    console2.log("Caller Balance:", callerBalance);
    
    if (callerBalance < amount) {
      console2.log("ERROR: Insufficient balance");
      revert("Insufficient balance");
    }

    // Check allowance
    uint256 allowance = IERC20(rewardToken).allowance(deployer, proxy);
    console2.log("Current Allowance:", allowance);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // Approve if needed
    if (allowance < amount) {
      console2.log("Approving reward token...");
      IERC20(rewardToken).approve(proxy, amount);
      console2.log("  Approved:", amount);
    }

    // Transfer tokens to staking contract
    console2.log("Transferring tokens to staking contract...");
    IERC20(rewardToken).transfer(proxy, amount);
    console2.log("  Transferred:", amount);
    console2.log("");

    // Distribute rewards
    console2.log("Distributing rewards...");
    staking.distributeRewards();
    console2.log("  Distribution complete!");

    vm.stopBroadcast();

    console2.log("");
    console2.log("Operation Complete!");
    console2.log("Rewards funded and distributed to all stakers");
    console2.log("");
  }

  //====================================================================================//
  //================================== TEST REWARD CYCLE ===============================//
  //====================================================================================//

  /// @notice Test complete reward cycle (for testing purposes)
  function testRewardCycle(address proxy, uint256 amount) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    xMorseStaking staking = xMorseStaking(proxy);
    address rewardToken = staking.rewardToken();

    console2.log("=== Testing Reward Cycle ===");
    console2.log("Proxy:", proxy);
    console2.log("Test Amount:", amount);
    console2.log("");

    // Show before state
    console2.log("BEFORE STATE:");
    console2.log("  Total Staked NFTs:", staking.getTotalStakedNFTs());
    console2.log("  Acc Reward Per NFT:", staking.accRewardPerNFT());
    console2.log("  Contract Balance:", IERC20(rewardToken).balanceOf(proxy));
    console2.log("");

    if (amount > 0) {
      // Fund and distribute
      uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

      vm.startBroadcast(deployerPrivateKey);
      
      IERC20(rewardToken).approve(proxy, amount);
      IERC20(rewardToken).transfer(proxy, amount);
      staking.distributeRewards();
      
      vm.stopBroadcast();

      console2.log("OPERATION:");
      console2.log("  Funded:", amount);
      console2.log("  Distributed: SUCCESS");
      console2.log("");
    }

    // Show after state
    console2.log("AFTER STATE:");
    console2.log("  Total Staked NFTs:", staking.getTotalStakedNFTs());
    console2.log("  Acc Reward Per NFT:", staking.accRewardPerNFT());
    console2.log("  Contract Balance:", IERC20(rewardToken).balanceOf(proxy));
    console2.log("");

    console2.log("Test cycle complete!");
    console2.log("");
  }

  //====================================================================================//
  //================================== CLAIM REWARDS (HELPER) ==========================//
  //====================================================================================//

  /// @notice Helper to claim rewards for specific NFTs
  function claimRewards(address proxy, uint256[] calldata tokenIds) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Claiming Rewards ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("Token IDs:", tokenIds.length);
    console2.log("");

    // Calculate total pending
    uint256 totalPending = 0;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 pending = staking.getPendingRewards(tokenIds[i]);
      console2.log("  NFT #", tokenIds[i], "pending:", pending);
      totalPending += pending;
    }

    console2.log("");
    console2.log("Total to claim:", totalPending);
    console2.log("");

    if (totalPending == 0) {
      console2.log("No rewards to claim");
      return;
    }

    vm.startBroadcast(deployerPrivateKey);
    staking.claimRewards(tokenIds);
    vm.stopBroadcast();

    console2.log("Rewards claimed successfully!");
    console2.log("");
  }

  /// @notice Claim all rewards for caller
  function claimAllRewards(address proxy) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Claiming All Rewards ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    uint256[] memory tokenIds = staking.getStakedNFTs(deployer);
    if (tokenIds.length == 0) {
      console2.log("No staked NFTs found");
      return;
    }

    // Calculate total pending
    uint256 totalPending = 0;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 pending = staking.getPendingRewards(tokenIds[i]);
      totalPending += pending;
    }

    console2.log("Staked NFTs:", tokenIds.length);
    console2.log("Total pending rewards:", totalPending);
    console2.log("");

    if (totalPending == 0) {
      console2.log("No rewards to claim");
      return;
    }

    vm.startBroadcast(deployerPrivateKey);
    staking.claimAllRewards();
    vm.stopBroadcast();

    console2.log("All rewards claimed successfully!");
    console2.log("");
  }
}

