// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Script } from '@std/Script.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { xMorseStaking } from '../src/xMorseStaking.sol';
import { IDN404 } from '../src/interfaces/IDN404.sol';

/**
 * @title DeployMitosisxMorseStaking
 * @notice Deploys xMorseStaking on Mitosis (Mainnet or Testnet)
 * @dev Deploys UUPS upgradeable staking contract for xMorse NFTs with reward distribution
 * 
 * Configuration:
 *   - Mainnet: Chain 124816, xMorse: 0xF8FA261FBeBeBec4241B26125aC21b5541afe600
 *   - Testnet (Dognet): Chain 124859, configurable addresses
 * 
 * Usage (Mainnet):
 *   forge script script/DeployMitosisxMorseStaking.s.sol \
 *     --rpc-url https://rpc.mitosis.org \
 *     --broadcast
 * 
 * Usage (Testnet):
 *   forge script script/DeployMitosisxMorseStaking.s.sol \
 *     --sig "runTestnet(address,address)" \
 *     <XMORSE_ADDRESS> <REWARD_TOKEN_ADDRESS> \
 *     --rpc-url https://rpc.dognet.mitosis.org \
 *     --broadcast
 */
contract DeployMitosisxMorseStaking is Script {
  // Mitosis Mainnet
  address constant XMORSE_MAINNET = 0xF8FA261FBeBeBec4241B26125aC21b5541afe600;
  uint256 constant CHAIN_ID_MAINNET = 124816;

  // Mitosis Dognet (Testnet)
  uint256 constant CHAIN_ID_DOGNET = 124859;

  function run() external {
    _deploy(XMORSE_MAINNET, XMORSE_MAINNET, "Mitosis Mainnet", CHAIN_ID_MAINNET);
  }

  function runTestnet(address xMorseToken, address rewardToken) external {
    _deploy(xMorseToken, rewardToken, "Mitosis Dognet", CHAIN_ID_DOGNET);
  }

  function _deploy(
    address xMorseToken,
    address rewardToken,
    string memory network,
    uint256 chainId
  ) internal {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("=== Deploying xMorseStaking to", network, "===");
    console2.log("Deployer:", deployer);
    console2.log("Chain ID:", chainId);
    console2.log("xMorse Token:", xMorseToken);
    console2.log("");

    // Fetch Mirror NFT address from xMorse
    IDN404 xMorse = IDN404(xMorseToken);
    address mirrorNFT;
    
    console2.log("Fetching xMorse contract info...");
    try xMorse.name() returns (string memory name) {
      console2.log("  xMorse Name:", name);
    } catch {
      console2.log("  xMorse Name: (unable to fetch)");
    }
    
    try xMorse.symbol() returns (string memory symbol) {
      console2.log("  xMorse Symbol:", symbol);
    } catch {
      console2.log("  xMorse Symbol: (unable to fetch)");
    }

    try xMorse.mirrorERC721() returns (address mirror) {
      mirrorNFT = mirror;
      console2.log("  Mirror NFT:", mirrorNFT);
    } catch {
      console2.log("  ERROR: Unable to fetch Mirror NFT address");
      revert("Invalid xMorse token");
    }

    console2.log("  Reward Token:", rewardToken);
    console2.log("");

    vm.startBroadcast(deployerPrivateKey);

    // 1. Deploy xMorseStaking Implementation
    console2.log("1. Deploying xMorseStaking implementation...");
    xMorseStaking stakingImpl = new xMorseStaking();
    console2.log("   Implementation deployed at:", address(stakingImpl));
    console2.log("");

    // 2. Deploy and initialize xMorseStaking Proxy
    console2.log("2. Deploying xMorseStaking proxy...");
    bytes memory initData = abi.encodeCall(
      xMorseStaking.initialize,
      (
        xMorseToken,  // xMorse DN404 token
        mirrorNFT,    // xMorse Mirror NFT
        rewardToken,  // Reward token (can be same as xMorse)
        deployer      // Initial owner
      )
    );

    ERC1967Proxy stakingProxy = new ERC1967Proxy(
      address(stakingImpl),
      initData
    );
    xMorseStaking staking = xMorseStaking(address(stakingProxy));
    console2.log("   Proxy deployed at:", address(staking));
    console2.log("");

    vm.stopBroadcast();

    // Output deployment info
    console2.log("=== xMorseStaking Deployment Complete ===");
    console2.log("");
    console2.log("Deployment Addresses:");
    console2.log("  xMorseStaking Proxy:", address(staking));
    console2.log("  xMorseStaking Implementation:", address(stakingImpl));
    console2.log("  xMorse Token:", xMorseToken);
    console2.log("  Mirror NFT:", mirrorNFT);
    console2.log("  Reward Token:", rewardToken);
    console2.log("  Owner:", deployer);
    console2.log("");
    
    console2.log("Contract Configuration:");
    console2.log("  Owner:", staking.owner());
    console2.log("  Lockup Period:", staking.lockupPeriod() / 1 days, "days");
    console2.log("  Total Staked NFTs:", staking.getTotalStakedNFTs());
    console2.log("  Accumulated Rewards:", staking.accRewardPerNFT());
    console2.log("");

    console2.log("Save to deployments/", network, "-staking.json:");
    console2.log("{");
    console2.log('  "chainId":', chainId, ',');
    console2.log('  "network": "', network, '",');
    console2.log('  "deployer": "', deployer, '",');
    console2.log('  "xMorseStaking": "', address(staking), '",');
    console2.log('  "xMorseStakingImpl": "', address(stakingImpl), '",');
    console2.log('  "xMorse": "', xMorseToken, '",');
    console2.log('  "mirrorNFT": "', mirrorNFT, '",');
    console2.log('  "rewardToken": "', rewardToken, '"');
    console2.log("}");
    console2.log("");

    console2.log("Next Steps:");
    console2.log("1. Configure reward token if needed:");
    console2.log("   forge script script/ConfigurexMorseStaking.s.sol \\");
    console2.log("     --sig 'setRewardToken(address,address)' \\");
    console2.log("     ", address(staking), " <NEW_REWARD_TOKEN> \\");
    console2.log("     --rpc-url <RPC_URL> --broadcast");
    console2.log("");
    console2.log("2. Set operator for automated reward distribution:");
    console2.log("   forge script script/ConfigurexMorseStaking.s.sol \\");
    console2.log("     --sig 'setOperator(address,address)' \\");
    console2.log("     ", address(staking), " <OPERATOR_ADDRESS> \\");
    console2.log("     --rpc-url <RPC_URL> --broadcast");
    console2.log("");
    console2.log("3. View staking info:");
    console2.log("   forge script script/ManageStakingRewards.s.sol \\");
    console2.log("     --sig 'viewStakingInfo(address)' \\");
    console2.log("     ", address(staking), " \\");
    console2.log("     --rpc-url <RPC_URL>");
    console2.log("");
    console2.log("4. Distribute rewards:");
    console2.log("   forge script script/ManageStakingRewards.s.sol \\");
    console2.log("     --sig 'distributeRewards(address)' \\");
    console2.log("     ", address(staking), " \\");
    console2.log("     --rpc-url <RPC_URL> --broadcast");
  }
}

