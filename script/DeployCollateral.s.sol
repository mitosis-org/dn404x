// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { xMorseCollateral } from '../src/xMorseCollateral.sol';
import { IMorse } from '../src/interfaces/IMorse.sol';

/**
 * @title DeployEthereumCollateral
 * @notice Deploys xMorseCollateral on Ethereum mainnet using existing DN404 token
 * @dev Token: 0xe591293151fFDadD5E06487087D9b0E2743de92E (MorseDN404)
 * 
 * Usage:
 *   forge script script/DeployCollateral.s.sol --rpc-url https://eth.drpc.org --broadcast --verify
 */
contract DeployCollateral is Script {
  // Existing MorseDN404 Token on Ethereum
  address constant TOKEN = 0xe591293151fFDadD5E06487087D9b0E2743de92E;

  // Hyperlane Ethereum Mainnet Addresses
  // Source: https://github.com/hyperlane-xyz/hyperlane-registry/blob/main/chains/ethereum/addresses.yaml
  address constant MAILBOX = 0xc005dc82818d67AF737725bD4bf75435d065D239;
  address constant MERKLE_TREE_HOOK = 0x48e6c30B97748d1e2e03bf3e9FbE3890ca5f8CCA;
  address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Deploying xMorseCollateral to Ethereum Mainnet ===");
    console2.log("Deployer:", deployer);
    console2.log("Token (MorseDN404):", TOKEN);
    console2.log("Mailbox:", MAILBOX);
    console2.log("MerkleTreeHook:", MERKLE_TREE_HOOK);
    console2.log("Multicall3:", MULTICALL3);
    console2.log("");

    // Verify token info
    IMorse token = IMorse(TOKEN);
    console2.log("Token Info:");
    try token.name() returns (string memory name) {
      console2.log("  Name:", name);
    } catch {
      console2.log("  Name: (unable to fetch)");
    }
    try token.symbol() returns (string memory symbol) {
      console2.log("  Symbol:", symbol);
    } catch {
      console2.log("  Symbol: (unable to fetch)");
    }
    try token.totalSupply() returns (uint256 supply) {
      console2.log("  Total Supply:", supply / 1e18, "tokens");
    } catch {
      console2.log("  Total Supply: (unable to fetch)");
    }
    try token.mirrorERC721() returns (address mirror) {
      console2.log("  Mirror (NFT):", mirror);
    } catch {
      console2.log("  Mirror (NFT): (unable to fetch)");
    }
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // 1. Deploy xMorseCollateral Implementation
    console2.log("1. Deploying xMorseCollateral implementation...");
    xMorseCollateral collateralImpl = new xMorseCollateral(
      TOKEN,
      MULTICALL3,
      MAILBOX
    );
    console2.log("   Implementation deployed at:", address(collateralImpl));
    console2.log("");

    // 2. Deploy and initialize xMorseCollateral Proxy
    console2.log("2. Deploying xMorseCollateral proxy...");
    bytes memory initData = abi.encodeCall(
      xMorseCollateral.initialize,
      (
        deployer, // Initial owner
        MERKLE_TREE_HOOK, // Hook
        address(0) // ISM (use default)
      )
    );

    ERC1967Proxy collateralProxy = new ERC1967Proxy(
      address(collateralImpl),
      initData
    );
    xMorseCollateral collateral = xMorseCollateral(address(collateralProxy));
    console2.log("   Proxy deployed at:", address(collateral));
    console2.log("   Owner:", collateral.owner());
    console2.log("   Token:", collateral.TOKEN());
    console2.log("");

    vm.stopBroadcast();

    // Output deployment info
    console2.log("=== Ethereum Mainnet xMorseCollateral Deployment Complete ===");
    console2.log("");
    console2.log("Deployment Addresses:");
    console2.log("  MorseDN404 Token:", TOKEN);
    console2.log("  MorseDN404 Mirror:", token.mirrorERC721());
    console2.log("  xMorseCollateral Proxy:", address(collateral));
    console2.log("  xMorseCollateral Implementation:", address(collateralImpl));
    console2.log("");
    console2.log("Save to deployments/ethereum-collateral.json:");
    console2.log("{");
    console2.log('  "chainId": 1,');
    console2.log('  "network": "ethereum-mainnet",');
    console2.log('  "deployer": "', deployer, '",');
    console2.log('  "token": "', TOKEN, '",');
    console2.log('  "tokenMirror": "', token.mirrorERC721(), '",');
    console2.log('  "xMorseCollateral": "', address(collateral), '",');
    console2.log('  "xMorseCollateralImpl": "', address(collateralImpl), '"');
    console2.log("}");
    console2.log("");
    console2.log("Next steps:");
    console2.log("1. Configure routing to Mitosis destination");
    console2.log("2. Test transfer with TestBridgeMitosisToSepolia.s.sol or similar script");
    console2.log("");
    console2.log("Example configuration command:");
    console2.log("forge script script/ConfigureCollateral.s.sol \\");
    console2.log("  --rpc-url https://eth.drpc.org --broadcast \\");
    console2.log("  --sig \"run(address)\" \\");
    console2.log("  ", address(collateral));
  }
}

