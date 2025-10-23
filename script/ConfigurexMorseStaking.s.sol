// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { xMorseStaking } from '../src/xMorseStaking.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';

/**
 * @title ConfigurexMorseStaking
 * @notice Configuration management for xMorseStaking contract
 * @dev Owner-only operations for setting parameters and managing contract state
 * 
 * Available Functions:
 *   - setRewardToken(address proxy, address newRewardToken)
 *   - setLockupPeriod(address proxy, uint256 newPeriod)
 *   - setValidatorRewardDistributor(address proxy, address distributor)
 *   - setValidatorAddress(address proxy, address validator)
 *   - setOperator(address proxy, address operator)
 *   - pause(address proxy)
 *   - unpause(address proxy)
 *   - viewConfig(address proxy) - read-only
 * 
 * Usage Examples:
 *   # Set reward token
 *   forge script script/ConfigurexMorseStaking.s.sol \
 *     --sig "setRewardToken(address,address)" \
 *     <PROXY> <NEW_REWARD_TOKEN> \
 *     --rpc-url <RPC_URL> --broadcast
 * 
 *   # Set lockup period (7 days = 604800 seconds)
 *   forge script script/ConfigurexMorseStaking.s.sol \
 *     --sig "setLockupPeriod(address,uint256)" \
 *     <PROXY> 604800 \
 *     --rpc-url <RPC_URL> --broadcast
 * 
 *   # View current configuration
 *   forge script script/ConfigurexMorseStaking.s.sol \
 *     --sig "viewConfig(address)" <PROXY> \
 *     --rpc-url <RPC_URL>
 */
contract ConfigurexMorseStaking is Script {
  
  //====================================================================================//
  //================================== REWARD TOKEN ====================================//
  //====================================================================================//

  /// @notice Set the reward token address
  function setRewardToken(address proxy, address newRewardToken) external {
    if (proxy == address(0) || newRewardToken == address(0)) {
      revert("Invalid address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Setting Reward Token ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    address oldToken = staking.rewardToken();
    console2.log("Current Reward Token:", oldToken);
    console2.log("New Reward Token:", newRewardToken);

    // Try to get token info
    try IERC20Metadata(newRewardToken).symbol() returns (string memory symbol) {
      console2.log("New Token Symbol:", symbol);
    } catch {
      console2.log("New Token Symbol: (unable to fetch)");
    }
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);
    staking.setRewardToken(newRewardToken);
    vm.stopBroadcast();

    console2.log("Reward token updated successfully!");
    console2.log("");
    console2.log("Note: Users should now provide", newRewardToken, "for rewards");
    console2.log("");
  }

  //====================================================================================//
  //================================== LOCKUP PERIOD ===================================//
  //====================================================================================//

  /// @notice Set the lockup period for newly staked NFTs
  function setLockupPeriod(address proxy, uint256 newPeriod) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Setting Lockup Period ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    uint256 oldPeriod = staking.lockupPeriod();
    console2.log("Current Lockup Period:", oldPeriod, "seconds");
    console2.log("  (", oldPeriod / 1 days, "days)");
    console2.log("New Lockup Period:", newPeriod, "seconds");
    console2.log("  (", newPeriod / 1 days, "days)");
    console2.log("");

    if (newPeriod < 1) {
      console2.log("ERROR: Lockup period must be at least 1 second");
      revert("Invalid lockup period");
    }

    vm.startBroadcast(deployerPrivateKey);
    staking.setLockupPeriod(newPeriod);
    vm.stopBroadcast();

    console2.log("Lockup period updated successfully!");
    console2.log("");
    console2.log("Note: This only affects newly staked NFTs");
    console2.log("      Existing stakes retain their original lockup times");
    console2.log("");
  }

  //====================================================================================//
  //================================== VALIDATOR SETTINGS ==============================//
  //====================================================================================//

  /// @notice Set the validator reward distributor contract
  function setValidatorRewardDistributor(address proxy, address distributor) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Setting Validator Reward Distributor ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    address oldDistributor = staking.validatorRewardDistributor();
    console2.log("Current Distributor:", oldDistributor);
    console2.log("New Distributor:", distributor);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);
    staking.setValidatorRewardDistributor(distributor);
    vm.stopBroadcast();

    console2.log("Validator reward distributor updated!");
    console2.log("");
    if (distributor == address(0)) {
      console2.log("Auto-claim from validator disabled");
    } else {
      console2.log("Auto-claim from validator enabled");
      console2.log("Remember to set validator address with setValidatorAddress()");
    }
    console2.log("");
  }

  /// @notice Set the validator address for claiming operator rewards
  function setValidatorAddress(address proxy, address validator) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Setting Validator Address ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    address oldValidator = staking.validatorAddress();
    console2.log("Current Validator:", oldValidator);
    console2.log("New Validator:", validator);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);
    staking.setValidatorAddress(validator);
    vm.stopBroadcast();

    console2.log("Validator address updated!");
    console2.log("");
    if (validator == address(0)) {
      console2.log("Validator rewards disabled");
    } else {
      console2.log("Validator rewards enabled for:", validator);
    }
    console2.log("");
  }

  //====================================================================================//
  //================================== OPERATOR ========================================//
  //====================================================================================//

  /// @notice Set the operator who can call distributeRewards
  function setOperator(address proxy, address operator) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Setting Operator ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    address oldOperator = staking.operator();
    console2.log("Current Operator:", oldOperator);
    console2.log("New Operator:", operator);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);
    staking.setOperator(operator);
    vm.stopBroadcast();

    console2.log("Operator updated successfully!");
    console2.log("");
    if (operator == address(0)) {
      console2.log("Only owner can distribute rewards");
    } else {
      console2.log("Operator", operator, "can now call distributeRewards()");
    }
    console2.log("");
  }

  //====================================================================================//
  //================================== PAUSE/UNPAUSE ===================================//
  //====================================================================================//

  /// @notice Pause the staking contract
  function pause(address proxy) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Pausing Contract ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);
    staking.pause();
    vm.stopBroadcast();

    console2.log("Contract paused!");
    console2.log("");
    console2.log("Disabled operations:");
    console2.log("  - stake()");
    console2.log("  - unstake()");
    console2.log("  - claimRewards()");
    console2.log("  - claimAllRewards()");
    console2.log("  - distributeRewards()");
    console2.log("");
    console2.log("To resume operations, call unpause()");
    console2.log("");
  }

  /// @notice Unpause the staking contract
  function unpause(address proxy) external {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== Unpausing Contract ===");
    console2.log("Proxy:", proxy);
    console2.log("Caller:", deployer);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);
    staking.unpause();
    vm.stopBroadcast();

    console2.log("Contract unpaused!");
    console2.log("All operations resumed");
    console2.log("");
  }

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @notice View current configuration
  function viewConfig(address proxy) external view {
    if (proxy == address(0)) {
      revert("Invalid proxy address");
    }

    xMorseStaking staking = xMorseStaking(proxy);

    console2.log("=== xMorseStaking Configuration ===");
    console2.log("Proxy:", proxy);
    console2.log("");

    console2.log("Core Settings:");
    console2.log("  Owner:", staking.owner());
    console2.log("  xMorse Token:", staking.xMorseToken());
    console2.log("  Mirror NFT:", staking.mirrorNFT());
    console2.log("  Reward Token:", staking.rewardToken());
    console2.log("");

    console2.log("Staking Settings:");
    uint256 lockupPeriod = staking.lockupPeriod();
    console2.log("  Lockup Period:", lockupPeriod, "seconds");
    console2.log("    (", lockupPeriod / 1 days, "days)");
    console2.log("  Total Staked NFTs:", staking.getTotalStakedNFTs());
    console2.log("  Acc Reward Per NFT:", staking.accRewardPerNFT());
    console2.log("");

    console2.log("Operator Settings:");
    address operator = staking.operator();
    console2.log("  Operator:", operator);
    if (operator == address(0)) {
      console2.log("    (only owner can distribute rewards)");
    }
    console2.log("");

    console2.log("Validator Settings:");
    address distributor = staking.validatorRewardDistributor();
    address validator = staking.validatorAddress();
    console2.log("  Validator Reward Distributor:", distributor);
    console2.log("  Validator Address:", validator);
    if (distributor == address(0) || validator == address(0)) {
      console2.log("    (auto-claim disabled)");
    } else {
      console2.log("    (auto-claim enabled)");
    }
    console2.log("");

    // Get reward token balance
    address rewardToken = staking.rewardToken();
    try IERC20(rewardToken).balanceOf(proxy) returns (uint256 balance) {
      console2.log("Balances:");
      console2.log("  Reward Token Balance:", balance);
      try IERC20Metadata(rewardToken).symbol() returns (string memory symbol) {
        console2.log("  Reward Token Symbol:", symbol);
      } catch {}
    } catch {
      console2.log("Balances: (unable to fetch)");
    }
    console2.log("");
  }

  /// @notice Verify configuration for a specific setting
  function verifyRewardToken(address proxy, address expectedToken) external view {
    xMorseStaking staking = xMorseStaking(proxy);
    address actualToken = staking.rewardToken();
    
    console2.log("=== Reward Token Verification ===");
    console2.log("Expected:", expectedToken);
    console2.log("Actual:", actualToken);
    
    if (actualToken == expectedToken) {
      console2.log("Status: MATCH OK");
    } else {
      console2.log("Status: MISMATCH");
    }
    console2.log("");
  }

  /// @notice Verify lockup period
  function verifyLockupPeriod(address proxy, uint256 expectedPeriod) external view {
    xMorseStaking staking = xMorseStaking(proxy);
    uint256 actualPeriod = staking.lockupPeriod();
    
    console2.log("=== Lockup Period Verification ===");
    console2.log("Expected:", expectedPeriod, "seconds");
    console2.log("  (", expectedPeriod / 1 days, "days)");
    console2.log("Actual:", actualPeriod, "seconds");
    console2.log("  (", actualPeriod / 1 days, "days)");
    
    if (actualPeriod == expectedPeriod) {
      console2.log("Status: MATCH OK");
    } else {
      console2.log("Status: MISMATCH");
    }
    console2.log("");
  }
}

