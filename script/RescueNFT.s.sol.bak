// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';

import { xMorseCollateral } from '../src/xMorseCollateral.sol';
import { IMorse } from '../src/interfaces/IMorse.sol';

/**
 * @title RescueNFT
 * @notice Emergency rescue script for NFTs locked in xMorseCollateral
 * @dev Only the owner can execute this. Use with caution!
 * 
 * This script is for emergency situations where NFTs are stuck in the collateral contract
 * due to failed cross-chain messages or other issues.
 * 
 * Usage Examples:
 * 
 * 1. Rescue a single NFT (Ethereum Mainnet):
 *    forge script script/RescueNFT.s.sol \
 *      --sig "rescueSingle(address,uint256)" \
 *      <RECIPIENT_ADDRESS> <TOKEN_ID> \
 *      --rpc-url mainnet \
 *      --broadcast
 * 
 * 2. Rescue multiple NFTs (Ethereum Mainnet):
 *    forge script script/RescueNFT.s.sol \
 *      --sig "rescueMultiple(address,uint256[])" \
 *      <RECIPIENT_ADDRESS> "[1234,5678,9012]" \
 *      --rpc-url mainnet \
 *      --broadcast
 * 
 * 3. Check NFT status before rescue:
 *    forge script script/RescueNFT.s.sol \
 *      --sig "checkNFT(uint256)" \
 *      <TOKEN_ID> \
 *      --rpc-url mainnet
 * 
 * 4. Rescue on Sepolia:
 *    forge script script/RescueNFT.s.sol \
 *      --sig "rescueSingleSepolia(address,uint256)" \
 *      <RECIPIENT_ADDRESS> <TOKEN_ID> \
 *      --rpc-url sepolia \
 *      --broadcast
 */
contract RescueNFT is Script {
  // Ethereum Mainnet
  address constant COLLATERAL_MAINNET = 0xafF06A0cDCd30965160709F8e56E9B0EB54b177a;
  address constant TOKEN_MAINNET = 0xe591293151fFDadD5E06487087D9b0E2743de92E; // MorseDN404

  // Sepolia Testnet
  address constant COLLATERAL_SEPOLIA = address(0); // TODO: Update with actual Sepolia address
  address constant TOKEN_SEPOLIA = address(0); // TODO: Update with actual Sepolia address

  /// @notice Rescue a single NFT from mainnet collateral
  function rescueSingle(address recipient, uint256 tokenId) external {
    _rescueSingle(COLLATERAL_MAINNET, TOKEN_MAINNET, recipient, tokenId, "Ethereum Mainnet");
  }

  /// @notice Rescue a single NFT from Sepolia collateral
  function rescueSingleSepolia(address recipient, uint256 tokenId) external {
    require(COLLATERAL_SEPOLIA != address(0), "Sepolia address not set");
    _rescueSingle(COLLATERAL_SEPOLIA, TOKEN_SEPOLIA, recipient, tokenId, "Sepolia Testnet");
  }

  /// @notice Rescue multiple NFTs from mainnet collateral
  function rescueMultiple(address recipient, uint256[] calldata tokenIds) external {
    _rescueMultiple(COLLATERAL_MAINNET, TOKEN_MAINNET, recipient, tokenIds, "Ethereum Mainnet");
  }

  /// @notice Rescue multiple NFTs from Sepolia collateral
  function rescueMultipleSepolia(address recipient, uint256[] calldata tokenIds) external {
    require(COLLATERAL_SEPOLIA != address(0), "Sepolia address not set");
    _rescueMultiple(COLLATERAL_SEPOLIA, TOKEN_SEPOLIA, recipient, tokenIds, "Sepolia Testnet");
  }

  function _rescueSingle(
    address collateral,
    address token,
    address recipient,
    uint256 tokenId,
    string memory network
  ) internal {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    _rescueMultiple(collateral, token, recipient, tokenIds, network);
  }

  function _rescueMultiple(
    address collateral,
    address token,
    address recipient,
    uint256[] memory tokenIds,
    string memory network
  ) internal {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Emergency NFT Rescue on", network, "===");
    console2.log("Executor:", deployer);
    console2.log("Collateral:", collateral);
    console2.log("Token:", token);
    console2.log("Recipient:", recipient);
    console2.log("Token Count:", tokenIds.length);
    console2.log("");

    require(recipient != address(0), "Invalid recipient");
    require(tokenIds.length > 0, "No tokens specified");

    xMorseCollateral coll = xMorseCollateral(collateral);
    IMorse morse = IMorse(token);
    address mirror = morse.mirrorERC721();

    // Verify ownership
    address owner = coll.owner();
    console2.log("Contract Owner:", owner);
    console2.log("Your Address:", deployer);
    
    if (owner != deployer) {
      console2.log("");
      console2.log("ERROR: You are not the owner!");
      console2.log("Only the owner can rescue NFTs.");
      revert("Not owner");
    }
    console2.log("");

    // Check NFT status
    console2.log("NFT Status Check:");
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      console2.log("  Token ID:", tokenId);
      
      try IERC721(mirror).ownerOf(tokenId) returns (address currentOwner) {
        console2.log("    Current Owner:", currentOwner);
        
        if (currentOwner == collateral) {
          console2.log("    Status: LOCKED in collateral (can be rescued)");
        } else if (currentOwner == recipient) {
          console2.log("    Status: Already owned by recipient");
        } else {
          console2.log("    Status: Owned by someone else");
        }
      } catch {
        console2.log("    Status: NFT does not exist");
      }
    }
    console2.log("");

    // Confirm action
    console2.log("WARNING: This is an emergency function!");
    console2.log("  - Bypasses normal bridge flow");
    console2.log("  - Should only be used for stuck NFTs");
    console2.log("  - Cannot be undone");
    console2.log("");

    console2.log("Proceeding with rescue...");
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // Execute rescue
    console2.log("Calling emergencyRescueNFT...");
    coll.emergencyRescueNFT(recipient, tokenIds);
    console2.log("  Rescue transaction executed");
    console2.log("");

    vm.stopBroadcast();

    console2.log("=== Rescue Complete ===");
    console2.log("");
    console2.log("Next Steps:");
    console2.log("1. Wait for transaction confirmation");
    console2.log("2. Verify NFT ownership:");
    console2.log("   forge script script/RescueNFT.s.sol \\");
    console2.log("     --sig 'verifyOwnership(uint256)' \\");
    console2.log("     ", tokenIds[0], " \\");
    console2.log("     --rpc-url <RPC_URL>");
    console2.log("");
    console2.log("Token IDs rescued:");
    for (uint256 i = 0; i < tokenIds.length; i++) {
      console2.log("  -", tokenIds[i]);
    }
  }

  /// @notice Check NFT status on mainnet
  function checkNFT(uint256 tokenId) external view {
    _checkNFT(COLLATERAL_MAINNET, TOKEN_MAINNET, tokenId, "Ethereum Mainnet");
  }

  /// @notice Check NFT status on Sepolia
  function checkNFTSepolia(uint256 tokenId) external view {
    require(COLLATERAL_SEPOLIA != address(0), "Sepolia address not set");
    _checkNFT(COLLATERAL_SEPOLIA, TOKEN_SEPOLIA, tokenId, "Sepolia Testnet");
  }

  function _checkNFT(
    address collateral,
    address token,
    uint256 tokenId,
    string memory network
  ) internal view {
    console2.log("=== NFT Status Check on", network, "===");
    console2.log("Token ID:", tokenId);
    console2.log("Collateral:", collateral);
    console2.log("Token:", token);
    console2.log("");

    IMorse morse = IMorse(token);
    address mirror = morse.mirrorERC721();

    try IERC721(mirror).ownerOf(tokenId) returns (address currentOwner) {
      console2.log("Current Owner:", currentOwner);
      console2.log("");

      if (currentOwner == collateral) {
        console2.log("Status: LOCKED in collateral");
        console2.log("  This NFT is stuck in the collateral contract");
        console2.log("  It can be rescued using the rescue script");
        console2.log("");
        console2.log("To rescue:");
        console2.log("  forge script script/RescueNFT.s.sol \\");
        console2.log("    --sig 'rescueSingle(address,uint256)' \\");
        console2.log("    <RECIPIENT_ADDRESS>", tokenId, "\\");
        console2.log("    --rpc-url <RPC_URL> \\");
        console2.log("    --broadcast");
      } else {
        console2.log("Status: Owned by", currentOwner);
        console2.log("  This NFT is not locked in collateral");
        console2.log("  No rescue needed");
      }
    } catch {
      console2.log("Status: NFT does not exist");
      console2.log("  Token ID", tokenId, "has not been minted");
    }
  }

  /// @notice Verify NFT ownership after rescue
  function verifyOwnership(uint256 tokenId) external view {
    _verifyOwnership(COLLATERAL_MAINNET, TOKEN_MAINNET, tokenId, "Ethereum Mainnet");
  }

  /// @notice Verify NFT ownership after rescue on Sepolia
  function verifyOwnershipSepolia(uint256 tokenId) external view {
    require(COLLATERAL_SEPOLIA != address(0), "Sepolia address not set");
    _verifyOwnership(COLLATERAL_SEPOLIA, TOKEN_SEPOLIA, tokenId, "Sepolia Testnet");
  }

  function _verifyOwnership(
    address collateral,
    address token,
    uint256 tokenId,
    string memory network
  ) internal view {
    console2.log("=== Verifying Ownership on", network, "===");
    console2.log("Token ID:", tokenId);
    console2.log("");

    IMorse morse = IMorse(token);
    address mirror = morse.mirrorERC721();

    try IERC721(mirror).ownerOf(tokenId) returns (address currentOwner) {
      console2.log("Current Owner:", currentOwner);
      console2.log("");

      if (currentOwner == collateral) {
        console2.log("Status: Still in collateral");
        console2.log("  Rescue may have failed or not been executed yet");
      } else {
        console2.log("Status: Successfully transferred");
        console2.log("  NFT is no longer in collateral");
      }
    } catch {
      console2.log("Status: NFT does not exist");
    }
  }

  /// @notice Batch check multiple NFTs
  function checkMultiple(uint256[] calldata tokenIds) external view {
    _checkMultiple(COLLATERAL_MAINNET, TOKEN_MAINNET, tokenIds, "Ethereum Mainnet");
  }

  /// @notice Batch check multiple NFTs on Sepolia
  function checkMultipleSepolia(uint256[] calldata tokenIds) external view {
    require(COLLATERAL_SEPOLIA != address(0), "Sepolia address not set");
    _checkMultiple(COLLATERAL_SEPOLIA, TOKEN_SEPOLIA, tokenIds, "Sepolia Testnet");
  }

  function _checkMultiple(
    address collateral,
    address token,
    uint256[] memory tokenIds,
    string memory network
  ) internal view {
    console2.log("=== Batch NFT Status Check on", network, "===");
    console2.log("Checking", tokenIds.length, "NFTs");
    console2.log("");

    IMorse morse = IMorse(token);
    address mirror = morse.mirrorERC721();

    uint256 lockedCount = 0;
    uint256[] memory lockedTokenIds = new uint256[](tokenIds.length);

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      console2.log("Token ID:", tokenId);

      try IERC721(mirror).ownerOf(tokenId) returns (address currentOwner) {
        if (currentOwner == collateral) {
          console2.log("  Status: LOCKED in collateral");
          lockedTokenIds[lockedCount] = tokenId;
          lockedCount++;
        } else {
          console2.log("  Status: Owned by", currentOwner);
        }
      } catch {
        console2.log("  Status: Does not exist");
      }
    }

    console2.log("");
    console2.log("Summary:");
    console2.log("  Total checked:", tokenIds.length);
    console2.log("  Locked in collateral:", lockedCount);
    console2.log("");

    if (lockedCount > 0) {
      console2.log("Locked Token IDs:");
      for (uint256 i = 0; i < lockedCount; i++) {
        console2.log("  -", lockedTokenIds[i]);
      }
      console2.log("");
      console2.log("To rescue all locked NFTs:");
      console2.log("  forge script script/RescueNFT.s.sol \\");
      console2.log("    --sig 'rescueMultiple(address,uint256[])' \\");
      console2.log("    <RECIPIENT_ADDRESS> '[...]' \\");
      console2.log("    --rpc-url <RPC_URL> \\");
      console2.log("    --broadcast");
    } else {
      console2.log("No NFTs are locked in collateral.");
    }
  }
}

