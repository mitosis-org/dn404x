// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';
import { xMorseCollateral } from '../src/xMorseCollateral.sol';

/**
 * @title UpgradeCollateral
 * @notice Upgrades the xMorseCollateral implementation to add emergency rescue functionality
 */
contract UpgradeCollateral is Script {
  // Ethereum Mainnet
  address constant PROXY = 0xafF06A0cDCd30965160709F8e56E9B0EB54b177a;
  address constant TOKEN = 0xe591293151fFDadD5E06487087D9b0E2743de92E; // MorseDN404
  address constant MULTICALL = 0xcA11bde05977b3631167028862bE2a173976CA11;
  address constant MAILBOX = 0xc005dc82818d67AF737725bD4bf75435d065D239;

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Upgrading xMorseCollateral ===");
    console2.log("Deployer:", deployer);
    console2.log("Proxy:", PROXY);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // Deploy new implementation
    console2.log("1. Deploying new implementation...");
    xMorseCollateral newImpl = new xMorseCollateral(TOKEN, MULTICALL, MAILBOX);
    console2.log("   New implementation:", address(newImpl));
    console2.log("");

    // Upgrade proxy
    console2.log("2. Upgrading proxy...");
    UUPSUpgradeable(PROXY).upgradeToAndCall(address(newImpl), "");
    console2.log("   Proxy upgraded successfully");
    console2.log("");

    vm.stopBroadcast();

    console2.log("=== Upgrade Complete ===");
    console2.log("");
    console2.log("New functionality available:");
    console2.log("  emergencyRescueNFT(address to, uint256[] tokenIds)");
    console2.log("");
    console2.log("To rescue Token ID 7746:");
    console2.log("  cast send", PROXY, "\\");
    console2.log("    'emergencyRescueNFT(address,uint256[])' \\");
    console2.log("    <YOUR_ADDRESS> '[7746]' \\");
    console2.log("    --rpc-url mainnet --private-key $PRIVATE_KEY");
    console2.log("");
  }

  function verify() external view {
    console2.log("=== Verifying Upgrade ===");
    console2.log("Proxy:", PROXY);
    console2.log("");

    xMorseCollateral collateral = xMorseCollateral(PROXY);

    // Verify ownership
    address owner = collateral.owner();
    console2.log("Owner:", owner);
    console2.log("");

    console2.log("Upgrade can be verified after deployment");
    console2.log("Call emergencyRescueNFT to test new functionality");
  }
}

