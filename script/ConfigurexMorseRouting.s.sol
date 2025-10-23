// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { xMorse } from '../src/xMorse.sol';
import { xMorseCollateral } from '../src/xMorseCollateral.sol';
import { MessageType } from '../src/libs/Message.sol';

/**
 * @title ConfigurexMorseRouting
 * @notice Configures cross-chain routing between Ethereum Mainnet and Mitosis Mainnet for xMorse bridge
 * @dev Run this after deploying both xMorseCollateral (Ethereum) and xMorse (Mitosis)
 * 
 * Usage:
 *   # Configure Ethereum side
 *   forge script script/ConfigurexMorseRouting.s.sol:ConfigurexMorseRouting \
 *     --sig "configureEthereum(address,address)" \
 *     <COLLATERAL_ADDRESS> <MITOSIS_XMORSE_ADDRESS> \
 *     --rpc-url mainnet --broadcast
 * 
 *   # Configure Mitosis side
 *   forge script script/ConfigurexMorseRouting.s.sol:ConfigurexMorseRouting \
 *     --sig "configureMitosis(address,address)" \
 *     <MITOSIS_XMORSE_ADDRESS> <ETHEREUM_COLLATERAL_ADDRESS> \
 *     --rpc-url https://rpc.mitosis.org --broadcast
 * 
 *   # Configure both (if using same deployer key)
 *   forge script script/ConfigurexMorseRouting.s.sol:ConfigurexMorseRouting \
 *     --sig "configureAll(address,address)" \
 *     <ETHEREUM_COLLATERAL> <MITOSIS_XMORSE> \
 *     --rpc-url mainnet --broadcast
 */
contract ConfigurexMorseRouting is Script {
  using TypeCasts for address;

  // Chain domains
  uint32 constant DOMAIN_ETHEREUM = 1;
  uint32 constant DOMAIN_MITOSIS = 124816;

  // Gas limits
  uint256 constant GAS_SEND_NFT = 500_000;
  uint256 constant GAS_SEND_NFT_PARTIAL = 700_000;

  /// @notice Configure Ethereum xMorseCollateral to route to Mitosis xMorse
  function configureEthereum(address ethereumCollateral, address mitosisxMorse) external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    
    console2.log("=== Configuring Ethereum Mainnet xMorseCollateral ===");
    console2.log("Collateral:", ethereumCollateral);
    console2.log("Remote xMorse:", mitosisxMorse);
    console2.log("Remote Domain:", DOMAIN_MITOSIS);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    xMorseCollateral collateral = xMorseCollateral(ethereumCollateral);

    // Enroll remote router
    console2.log("1. Enrolling remote router...");
    collateral.enrollRemoteRouter(DOMAIN_MITOSIS, mitosisxMorse.addressToBytes32());
    console2.log("   Remote router enrolled");

    // Set gas limits
    console2.log("2. Setting gas limits...");
    collateral.setDestinationGas(
      DOMAIN_MITOSIS,
      uint96(uint8(MessageType.SendNFT)),
      uint128(GAS_SEND_NFT)
    );
    console2.log("   SendNFT gas:", GAS_SEND_NFT);

    collateral.setDestinationGas(
      DOMAIN_MITOSIS,
      uint96(uint8(MessageType.SendNFTPartial)),
      uint128(GAS_SEND_NFT_PARTIAL)
    );
    console2.log("   SendNFTPartial gas:", GAS_SEND_NFT_PARTIAL);

    vm.stopBroadcast();

    console2.log("");
    console2.log("Ethereum Mainnet configuration complete!");
    console2.log("Users can now bridge NFTs from Ethereum to Mitosis");
    console2.log("");
  }

  /// @notice Configure Mitosis xMorse to route to Ethereum xMorseCollateral
  function configureMitosis(address mitosisxMorse, address ethereumCollateral) external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    
    console2.log("=== Configuring Mitosis Mainnet xMorse ===");
    console2.log("xMorse:", mitosisxMorse);
    console2.log("Remote Collateral:", ethereumCollateral);
    console2.log("Remote Domain:", DOMAIN_ETHEREUM);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    xMorse morse = xMorse(payable(mitosisxMorse));

    // Enroll remote router
    console2.log("1. Enrolling remote router...");
    morse.enrollRemoteRouter(DOMAIN_ETHEREUM, ethereumCollateral.addressToBytes32());
    console2.log("   Remote router enrolled");

    // Set gas limits
    console2.log("2. Setting gas limits...");
    morse.setDestinationGas(
      DOMAIN_ETHEREUM,
      uint96(uint8(MessageType.SendNFT)),
      uint128(GAS_SEND_NFT)
    );
    console2.log("   SendNFT gas:", GAS_SEND_NFT);

    morse.setDestinationGas(
      DOMAIN_ETHEREUM,
      uint96(uint8(MessageType.SendNFTPartial)),
      uint128(GAS_SEND_NFT_PARTIAL)
    );
    console2.log("   SendNFTPartial gas:", GAS_SEND_NFT_PARTIAL);

    vm.stopBroadcast();

    console2.log("");
    console2.log("Mitosis Mainnet configuration complete!");
    console2.log("Users can now bridge NFTs from Mitosis back to Ethereum");
    console2.log("");
  }

  /// @notice Configure both sides (requires same owner on both chains)
  /// @dev This won't work with different RPCs in the same script
  ///      Use configureEthereum and configureMitosis separately
  function configureAll(address ethereumCollateral, address mitosisxMorse) external view {
    console2.log("=== Configure Both Chains ===");
    console2.log("");
    console2.log("Run these commands separately:");
    console2.log("");
    console2.log("1. Configure Ethereum Mainnet:");
    console2.log("   forge script script/ConfigurexMorseRouting.s.sol \\");
    console2.log("     --sig 'configureEthereum(address,address)' \\");
    console2.log("     ", ethereumCollateral, " \\");
    console2.log("     ", mitosisxMorse, " \\");
    console2.log("     --rpc-url mainnet --broadcast");
    console2.log("");
    console2.log("2. Configure Mitosis Mainnet:");
    console2.log("   forge script script/ConfigurexMorseRouting.s.sol \\");
    console2.log("     --sig 'configureMitosis(address,address)' \\");
    console2.log("     ", mitosisxMorse, " \\");
    console2.log("     ", ethereumCollateral, " \\");
    console2.log("     --rpc-url https://rpc.mitosis.org --broadcast");
    console2.log("");
  }

  /// @notice Verify Ethereum xMorseCollateral routing configuration
  function verifyEthereum(address ethereumCollateral, address expectedMitosisxMorse) external view {
    console2.log("=== Verifying Ethereum Mainnet Configuration ===");
    console2.log("Collateral:", ethereumCollateral);
    console2.log("Expected Remote xMorse:", expectedMitosisxMorse);
    console2.log("");

    xMorseCollateral collateral = xMorseCollateral(ethereumCollateral);

    // Check remote router
    bytes32 registeredRouter = collateral.routers(DOMAIN_MITOSIS);
    bytes32 expectedRouter = expectedMitosisxMorse.addressToBytes32();
    
    console2.log("1. Remote Router Check:");
    console2.log("   Registered:", vm.toString(registeredRouter));
    console2.log("   Expected:  ", vm.toString(expectedRouter));
    
    if (registeredRouter == expectedRouter) {
      console2.log("   Status: MATCH OK");
    } else if (registeredRouter == bytes32(0)) {
      console2.log("   Status: NOT CONFIGURED (run configureEthereum)");
    } else {
      console2.log("   Status: MISMATCH (wrong remote address)");
    }
    console2.log("");

    // Gas limits check via quote (indirect verification)
    console2.log("2. Gas Configuration:");
    console2.log("   To verify gas limits, use cast:");
    console2.log("   cast call", ethereumCollateral);
    console2.log("     'quoteTransferRemoteNFT(uint32,bytes32,uint256[])'");
    console2.log("     --rpc-url mainnet");
    console2.log("");

    // Overall status
    if (registeredRouter == expectedRouter) {
      console2.log("=== ROUTER VERIFICATION PASSED ===");
      console2.log("Ethereum xMorseCollateral router is properly configured!");
      console2.log("Use 'quote' function to verify gas settings work correctly");
    } else {
      console2.log("=== VERIFICATION FAILED ===");
      console2.log("Run configureEthereum() to fix");
    }
    console2.log("");
  }

  /// @notice Verify Mitosis xMorse routing configuration
  function verifyMitosis(address mitosisxMorse, address expectedEthereumCollateral) external view {
    console2.log("=== Verifying Mitosis Mainnet Configuration ===");
    console2.log("xMorse:", mitosisxMorse);
    console2.log("Expected Remote Collateral:", expectedEthereumCollateral);
    console2.log("");

    xMorse morse = xMorse(payable(mitosisxMorse));

    // Check remote router
    bytes32 registeredRouter = morse.routers(DOMAIN_ETHEREUM);
    bytes32 expectedRouter = expectedEthereumCollateral.addressToBytes32();
    
    console2.log("1. Remote Router Check:");
    console2.log("   Registered:", vm.toString(registeredRouter));
    console2.log("   Expected:  ", vm.toString(expectedRouter));
    
    if (registeredRouter == expectedRouter) {
      console2.log("   Status: MATCH OK");
    } else if (registeredRouter == bytes32(0)) {
      console2.log("   Status: NOT CONFIGURED (run configureMitosis)");
    } else {
      console2.log("   Status: MISMATCH (wrong remote address)");
    }
    console2.log("");

    // Gas limits check via quote (indirect verification)
    console2.log("2. Gas Configuration:");
    console2.log("   To verify gas limits, use cast:");
    console2.log("   cast call", mitosisxMorse);
    console2.log("     'quoteTransferRemoteNFT(uint32,bytes32,uint256[])'");
    console2.log("     --rpc-url https://rpc.mitosis.org");
    console2.log("");

    // Overall status
    if (registeredRouter == expectedRouter) {
      console2.log("=== ROUTER VERIFICATION PASSED ===");
      console2.log("Mitosis xMorse router is properly configured!");
      console2.log("Use 'quote' function to verify gas settings work correctly");
    } else {
      console2.log("=== VERIFICATION FAILED ===");
      console2.log("Run configureMitosis() to fix");
    }
    console2.log("");
  }
}

