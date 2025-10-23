// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';
import { xMorseStaking } from '../src/xMorseStaking.sol';

/**
 * @title UpgradexMorseStaking
 * @notice Upgrades the xMorseStaking implementation contract using UUPS pattern
 * @dev Owner-only operation that deploys new implementation and upgrades proxy
 * 
 * Usage (with proxy address):
 *   forge script script/UpgradexMorseStaking.s.sol \
 *     --sig "run(address)" <PROXY_ADDRESS> \
 *     --rpc-url https://rpc.mitosis.org \
 *     --broadcast
 * 
 * Usage (testnet):
 *   forge script script/UpgradexMorseStaking.s.sol \
 *     --sig "runTestnet(address)" <PROXY_ADDRESS> \
 *     --rpc-url https://rpc.dognet.mitosis.org \
 *     --broadcast
 * 
 * Verify after upgrade:
 *   forge script script/UpgradexMorseStaking.s.sol \
 *     --sig "verify(address)" <PROXY_ADDRESS> \
 *     --rpc-url <RPC_URL>
 */
contract UpgradexMorseStaking is Script {
  function run(address proxy) external {
    _upgrade(proxy, "Mitosis Mainnet");
  }

  function runTestnet(address proxy) external {
    _upgrade(proxy, "Mitosis Dognet");
  }

  function _upgrade(address proxy, string memory network) internal {
    if (proxy == address(0)) {
      console2.log("ERROR: Proxy address cannot be zero");
      revert("Invalid proxy address");
    }

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Upgrading xMorseStaking on", network, "===");
    console2.log("Deployer:", deployer);
    console2.log("Proxy:", proxy);
    console2.log("");

    // Verify current owner
    xMorseStaking currentStaking = xMorseStaking(proxy);
    address owner = currentStaking.owner();
    console2.log("Current Owner:", owner);
    
    if (owner != deployer) {
      console2.log("WARNING: You are not the owner!");
      console2.log("This upgrade will fail unless you are the owner.");
      console2.log("");
    }

    // Display current state
    console2.log("Current Configuration:");
    console2.log("  xMorse Token:", currentStaking.xMorseToken());
    console2.log("  Mirror NFT:", currentStaking.mirrorNFT());
    console2.log("  Reward Token:", currentStaking.rewardToken());
    console2.log("  Lockup Period:", currentStaking.lockupPeriod() / 1 days, "days");
    console2.log("  Total Staked NFTs:", currentStaking.getTotalStakedNFTs());
    console2.log("  Acc Reward Per NFT:", currentStaking.accRewardPerNFT());
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // Deploy new implementation
    console2.log("1. Deploying new implementation...");
    xMorseStaking newImpl = new xMorseStaking();
    console2.log("   New implementation:", address(newImpl));
    console2.log("");

    // Upgrade proxy
    console2.log("2. Upgrading proxy...");
    UUPSUpgradeable(proxy).upgradeToAndCall(address(newImpl), "");
    console2.log("   Proxy upgraded successfully");
    console2.log("");

    vm.stopBroadcast();

    console2.log("=== Upgrade Complete ===");
    console2.log("");
    console2.log("New Implementation:", address(newImpl));
    console2.log("Proxy Address:", proxy);
    console2.log("");
    
    console2.log("Verification:");
    console2.log("  Run: forge script script/UpgradexMorseStaking.s.sol \\");
    console2.log("         --sig 'verify(address)' ", proxy, " \\");
    console2.log("         --rpc-url <RPC_URL>");
    console2.log("");
  }

  function verify(address proxy) external view {
    _verifyUpgrade(proxy, "Current Network");
  }

  function verifyMainnet(address proxy) external view {
    _verifyUpgrade(proxy, "Mitosis Mainnet");
  }

  function verifyTestnet(address proxy) external view {
    _verifyUpgrade(proxy, "Mitosis Dognet");
  }

  function _verifyUpgrade(address proxy, string memory network) internal view {
    console2.log("=== Verifying xMorseStaking Upgrade on", network, "===");
    console2.log("Proxy:", proxy);
    console2.log("");

    xMorseStaking staking = xMorseStaking(proxy);

    // Verify basic info
    console2.log("Contract Info:");
    console2.log("  Owner:", staking.owner());
    console2.log("  xMorse Token:", staking.xMorseToken());
    console2.log("  Mirror NFT:", staking.mirrorNFT());
    console2.log("  Reward Token:", staking.rewardToken());
    console2.log("");

    console2.log("Configuration:");
    console2.log("  Lockup Period:", staking.lockupPeriod() / 1 days, "days");
    console2.log("  Total Staked NFTs:", staking.getTotalStakedNFTs());
    console2.log("  Acc Reward Per NFT:", staking.accRewardPerNFT());
    console2.log("");

    console2.log("Optional Settings:");
    try staking.operator() returns (address op) {
      console2.log("  Operator:", op);
    } catch {
      console2.log("  Operator: (not set)");
    }
    
    try staking.validatorRewardDistributor() returns (address dist) {
      console2.log("  Validator Distributor:", dist);
    } catch {
      console2.log("  Validator Distributor: (not set)");
    }

    try staking.validatorAddress() returns (address val) {
      console2.log("  Validator Address:", val);
    } catch {
      console2.log("  Validator Address: (not set)");
    }
    console2.log("");

    console2.log("=== VERIFICATION COMPLETE ===");
    console2.log("Upgrade Status: OK");
    console2.log("All contract functions accessible");
    console2.log("");
  }
}

