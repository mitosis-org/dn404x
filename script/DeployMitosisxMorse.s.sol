// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

import { xMorse } from '../src/xMorse.sol';

/**
 * @title DeployMitosisxMorse
 * @notice Deploys xMorse on Mitosis Mainnet as a bridge for Ethereum Morse NFTs
 * @dev Uses mint/burn pattern with token ID mapping to maintain same images as Ethereum
 * 
 * Configuration:
 *   - Chain: Mitosis Mainnet (124816)
 *   - RPC: https://rpc.mitosis.org
 *   - Mailbox: 0x3a464f746D23Ab22155710f44dB16dcA53e0775E
 *   - Hook: 0x1e4dE25C3b07c8DF66D4c193693d8B5f3b431d51
 *   - Source: https://github.com/hyperlane-xyz/hyperlane-registry/blob/main/chains/mitosis/
 * 
 * Usage:
 *   forge script script/DeployMitosisxMorse.s.sol \
 *     --rpc-url https://rpc.mitosis.org \
 *     --broadcast --verify
 * 
 * Or with environment variables:
 *   source .env
 *   forge script script/DeployMitosisxMorse.s.sol \
 *     --rpc-url $MITOSIS_RPC \
 *     --broadcast --verify
 */
contract DeployMitosisxMorse is Script {
  // Hyperlane Mitosis Mainnet Addresses
  // Source: https://github.com/hyperlane-xyz/hyperlane-registry/blob/main/chains/mitosis/addresses.yaml
  address constant MAILBOX = 0x3a464f746D23Ab22155710f44dB16dcA53e0775E;
  address constant MERKLE_TREE_HOOK = 0x1e4dE25C3b07c8DF66D4c193693d8B5f3b431d51;

  // Token Metadata
  string constant NAME = 'xMorse';
  string constant SYMBOL = 'xMORSE';
  uint8 constant DECIMALS = 18;
  string constant BASE_URI = 'https://morse.mitosis.org/nft/{id}'; // Update with actual URI

  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Deploying xMorse to Mitosis Mainnet ===");
    console2.log("Deployer:", deployer);
    console2.log("Mailbox:", MAILBOX);
    console2.log("MerkleTreeHook:", MERKLE_TREE_HOOK);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // 1. Deploy DN404Mirror
    console2.log("1. Deploying DN404Mirror...");
    DN404Mirror mirror = new DN404Mirror(deployer);
    console2.log("   Mirror deployed at:", address(mirror));
    console2.log("");

    // 2. Deploy xMorse Implementation
    console2.log("2. Deploying xMorse implementation...");
    xMorse morseImpl = new xMorse(MAILBOX);
    console2.log("   Implementation deployed at:", address(morseImpl));
    console2.log("");

    // 3. Deploy and initialize xMorse Proxy
    console2.log("3. Deploying xMorse proxy...");
    bytes memory initData = abi.encodeCall(
      xMorse.initialize,
      (
        NAME,
        SYMBOL,
        DECIMALS,
        BASE_URI,
        deployer, // Initial owner
        MERKLE_TREE_HOOK, // Hook
        address(0), // ISM (use default)
        address(mirror) // Mirror
      )
    );

    ERC1967Proxy morseProxy = new ERC1967Proxy(
      address(morseImpl),
      initData
    );
    xMorse morse = xMorse(payable(address(morseProxy)));
    console2.log("   Proxy deployed at:", address(morse));
    console2.log("   Owner:", morse.owner());
    console2.log("   Mirror NFT:", morse.mirrorERC721());
    console2.log("   Name:", morse.name());
    console2.log("   Symbol:", morse.symbol());
    console2.log("   Total Supply:", morse.totalSupply() / 1e18, "tokens");
    console2.log("");

    vm.stopBroadcast();

    // Output deployment info
    console2.log("=== Mitosis xMorse Deployment Complete ===");
    console2.log("");
    console2.log("Deployment Addresses:");
    console2.log("  xMorse Proxy:", address(morse));
    console2.log("  xMorse Implementation:", address(morseImpl));
    console2.log("  DN404Mirror (NFT):", address(mirror));
    console2.log("  Deployer/Owner:", deployer);
    console2.log("");
    console2.log("Contract Info:");
    console2.log("  Name:", NAME);
    console2.log("  Symbol:", SYMBOL);
    console2.log("  Decimals:", DECIMALS);
    console2.log("  Base URI:", BASE_URI);
    console2.log("");
    console2.log("Save to deployments/mitosis-xmorse.json:");
    console2.log("{");
    console2.log('  "chainId": 124816,');
    console2.log('  "network": "mitosis-mainnet",');
    console2.log('  "deployer": "', deployer, '",');
    console2.log('  "xMorse": "', address(morse), '",');
    console2.log('  "xMorseImpl": "', address(morseImpl), '",');
    console2.log('  "mirror": "', address(mirror), '",');
    console2.log('  "mailbox": "', MAILBOX, '",');
    console2.log('  "hook": "', MERKLE_TREE_HOOK, '"');
    console2.log("}");
    console2.log("");
    console2.log("Next steps:");
    console2.log("1. Update BASE_URI in the contract if needed:");
    console2.log("   cast send", address(morse), '"setBaseURI(string)" <NEW_URI>');
    console2.log("2. Configure routing to Ethereum Mainnet (use ConfigurexMorseRouting.s.sol)");
    console2.log("3. Test bridge transfer from Ethereum Mainnet");
    console2.log("");
    console2.log("Bridge Configuration:");
    console2.log("  Ethereum Domain: 1");
    console2.log("  Mitosis Domain: 124816");
    console2.log("  Recommended gas limits:");
    console2.log("    - SendNFT: 500000");
    console2.log("    - SendNFTPartial: 700000");
  }
}

