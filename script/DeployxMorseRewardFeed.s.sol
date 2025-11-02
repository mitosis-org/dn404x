// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { xMorseRewardFeed } from '../src/xMorseRewardFeed.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

/**
 * @title DeployxMorseRewardFeed
 * @notice Deploys xMorseRewardFeed for epoch-based reward distribution
 * 
 * Usage (Dognet):
 *   forge script script/DeployxMorseRewardFeed.s.sol \
 *     --rpc-url https://rpc.dognet.mitosis.org \
 *     --broadcast --verify
 */
contract DeployxMorseRewardFeed is Script {
  // Mitosis Dognet Epoch Feeder (must be deployed first)
  address constant EPOCH_FEEDER_DOGNET = 0x94E2cad3bFB4801c4B589acd255B62D25F2515e6;
  
  // Mitosis Mainnet Epoch Feeder
  address constant EPOCH_FEEDER_MAINNET = address(0); // TODO: Set actual address

  function run() external {
    _deploy(EPOCH_FEEDER_DOGNET, "Dognet");
  }

  function runMainnet() external {
    _deploy(EPOCH_FEEDER_MAINNET, "Mainnet");
  }

  function _deploy(address epochFeeder, string memory network) internal {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Deploying xMorseRewardFeed to", network, "===");
    console2.log("Deployer:", deployer);
    console2.log("Epoch Feeder:", epochFeeder);
    console2.log("");

    if (epochFeeder == address(0)) {
      console2.log("ERROR: Epoch Feeder address not set!");
      console2.log("Please update EPOCH_FEEDER address in the script.");
      revert("Epoch Feeder not configured");
    }

    vm.startBroadcast(deployerPrivateKey);

    // 1. Deploy implementation
    console2.log("1. Deploying xMorseRewardFeed implementation...");
    xMorseRewardFeed impl = new xMorseRewardFeed(IEpochFeeder(epochFeeder));
    console2.log("   Implementation:", address(impl));
    console2.log("");

    // 2. Deploy proxy
    console2.log("2. Deploying xMorseRewardFeed proxy...");
    bytes memory initData = abi.encodeCall(
      xMorseRewardFeed.initialize,
      (
        deployer, // initial owner
        deployer  // initial feeder (can be changed later)
      )
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    xMorseRewardFeed feed = xMorseRewardFeed(address(proxy));
    
    console2.log("   Proxy:", address(feed));
    console2.log("");

    vm.stopBroadcast();

    // Verification
    console2.log("=== Deployment Complete ===");
    console2.log("");
    console2.log("xMorseRewardFeed Addresses:");
    console2.log("  Proxy:", address(feed));
    console2.log("  Implementation:", address(impl));
    console2.log("  Owner:", feed.owner());
    console2.log("  Feeder:", feed.feeder());
    console2.log("  Epoch Feeder:", address(feed.epochFeeder()));
    console2.log("  Next Epoch:", feed.nextEpoch());
    console2.log("");
    
    console2.log("Next Steps:");
    console2.log("1. Upgrade xMorseStaking to V2");
    console2.log("2. Set reward feed in xMorseStaking:");
    console2.log("   cast send <STAKING> 'setRewardFeed(address)' ", address(feed));
    console2.log("");
    console2.log("3. Grant FEEDER role to bot (if different from owner):");
    console2.log("   cast send", address(feed), "'setFeeder(address)' <BOT_ADDRESS>");
  }
}

