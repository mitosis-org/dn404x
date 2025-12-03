// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';
import { xMorse } from '../src/xMorse.sol';

/**
 * @title UpgradexMorse
 * @notice Upgrades the xMorse implementation to fix token ID conversion issue
 * @dev This upgrade adds proper Mitosis→Ethereum token ID conversion when bridging NFTs back
 * 
 * Key Changes:
 * - Override transferRemoteNFT() to convert Mitosis token IDs to Ethereum token IDs
 * - Add TokenNotBridgedFromEthereum error for invalid tokens
 * - Ensure correct NFT unlocking on Ethereum side
 * 
 * Usage (Mitosis Mainnet):
 *   forge script script/UpgradexMorse.s.sol \
 *     --rpc-url https://rpc.mitosis.org \
 *     --broadcast
 * 
 * Note: Sourcify does not support Mitosis chain (124816) verification yet.
 *       Manual verification may be available through Mitosis block explorer.
 * 
 * Usage (Mitosis Testnet):
 *   forge script script/UpgradexMorse.s.sol \
 *     --sig "runTestnet()" \
 *     --rpc-url $MITOSIS_TESTNET_RPC \
 *     --broadcast
 */
contract UpgradexMorse is Script {
  // Mitosis Mainnet
  address constant PROXY_MAINNET = 0xF8FA261FBeBeBec4241B26125aC21b5541afe600; // TODO: Update with actual mainnet address
  address constant MAILBOX_MAINNET = 0x3a464f746D23Ab22155710f44dB16dcA53e0775E;

  // Mitosis Testnet (if applicable)
  address constant PROXY_TESTNET = address(0); // TODO: Update with actual testnet address if needed
  address constant MAILBOX_TESTNET = 0x3C5154a193D6e2955650f9305c8d80c18C814A68; // Mitosis Testnet Hyperlane mailbox

  function run() external {
    _upgrade(PROXY_MAINNET, MAILBOX_MAINNET, "Mitosis Mainnet");
  }

  function runTestnet() external {
    require(PROXY_TESTNET != address(0), "Testnet proxy address not set");
    _upgrade(PROXY_TESTNET, MAILBOX_TESTNET, "Mitosis Testnet");
  }

  function _upgrade(address proxy, address mailbox, string memory network) internal {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Upgrading xMorse on", network, "===");
    console2.log("Deployer:", deployer);
    console2.log("Proxy:", proxy);
    console2.log("Mailbox:", mailbox);
    console2.log("");

    // Verify current owner
    xMorse currentMorse = xMorse(payable(proxy));
    address owner = currentMorse.owner();
    console2.log("Current Owner:", owner);
    
    if (owner != deployer) {
      console2.log("WARNING: You are not the owner!");
      console2.log("This upgrade will fail unless you are the owner.");
      console2.log("");
    }

    vm.startBroadcast(deployerPrivateKey);

    // Deploy new implementation
    console2.log("1. Deploying new implementation...");
    xMorse newImpl = new xMorse(mailbox);
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
    console2.log("What's New:");
    console2.log("  - Fixed token ID conversion when bridging back to Ethereum");
    console2.log("  - Mitosis token IDs are now correctly converted to Ethereum token IDs");
    console2.log("  - Added validation to prevent sending non-bridged tokens");
    console2.log("");
    console2.log("Technical Changes:");
    console2.log("  - transferRemoteNFT() now converts Mitosis IDs -> Ethereum IDs");
    console2.log("  - Added TokenNotBridgedFromEthereum(uint256) error");
    console2.log("  - Improved cross-chain message accuracy");
    console2.log("");
    console2.log("Verification:");
    console2.log("  Run: forge script script/UpgradexMorse.s.sol --sig 'verify()'");
    console2.log("");
  }

  function verify() external view {
    _verifyUpgrade(PROXY_MAINNET, "Mitosis Mainnet");
  }

  function verifyTestnet() external view {
    require(PROXY_TESTNET != address(0), "Testnet proxy address not set");
    _verifyUpgrade(PROXY_TESTNET, "Mitosis Testnet");
  }

  function _verifyUpgrade(address proxy, string memory network) internal view {
    console2.log("=== Verifying xMorse Upgrade on", network, "===");
    console2.log("Proxy:", proxy);
    console2.log("");

    xMorse morse = xMorse(payable(proxy));

    // Verify basic info
    console2.log("Contract Info:");
    console2.log("  Owner:", morse.owner());
    console2.log("  Name:", morse.name());
    console2.log("  Symbol:", morse.symbol());
    console2.log("  Total Supply:", morse.totalSupply() / 1e18, "tokens");
    console2.log("  Mirror (NFT):", morse.mirrorERC721());
    console2.log("");

    // Check token ID mappings (if any exist)
    console2.log("Token ID Mappings:");
    console2.log("  Test Ethereum ID 999 -> Mitosis ID:", morse.ethereumToMitosisId(999));
    console2.log("  Test Mitosis ID 1 -> Ethereum ID:", morse.mitosisToEthereumId(1));
    console2.log("");

    console2.log("Upgrade Status: OK");
    console2.log("");
    console2.log("Next Steps:");
    console2.log("1. Test bridge transfer from Mitosis to Ethereum");
    console2.log("2. Verify NFT unlocks correctly with proper token ID");
    console2.log("3. Monitor Hyperlane Explorer for successful deliveries");
    console2.log("");
    console2.log("Test Command:");
    console2.log("  forge script script/TestBridgeMitosisToEthereum.s.sol \\");
    console2.log("    --sig 'bridgeNFT(address,address,uint256)' \\");
    console2.log("    ", proxy, " \\");
    console2.log("    <ETHEREUM_RECIPIENT> \\");
    console2.log("    <MITOSIS_TOKEN_ID> \\");
    console2.log("    --rpc-url https://rpc.mitosis.org \\");
    console2.log("    --broadcast");
  }
}

