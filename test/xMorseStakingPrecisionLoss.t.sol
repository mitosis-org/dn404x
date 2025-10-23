// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { xMorse } from '../src/xMorse.sol';
import { xMorseStaking } from '../src/xMorseStaking.sol';
import { IxMorseStaking } from '../src/interfaces/IxMorseStaking.sol';
import { SimpleMulticall } from './mocks/SimpleMulticall.sol';
import { MockERC20 } from './mocks/MockERC20.sol';
import { HyperlaneTestUtils } from './utils/HyperlaneTestUtils.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

contract xMorseStakingPrecisionLossTest is Test, HyperlaneTestUtils {
  using TypeCasts for address;

  xMorse public morse;
  xMorseStaking public staking;
  MockERC20 public rewardToken;
  IERC721 public mirrorNFT;

  address public owner;
  address public user1;
  address public user2;
  address public user3;

  uint256 constant INITIAL_SUPPLY = 100 ether;
  string constant NAME = 'xMorse NFT';
  string constant SYMBOL = 'xMORSE';
  uint8 constant DECIMALS = 18;

  address multicall = 0xcA11bde05977b3631167028862bE2a173976CA11;

  function setUp() public {
    owner = makeAddr('owner');
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');
    user3 = makeAddr('user3');

    setupHyperlane();

    // Deploy mock multicall if needed
    if (multicall.code.length == 0) {
      vm.etch(multicall, address(new SimpleMulticall()).code);
    }

    // Deploy xMorse implementation
    xMorse implementation = new xMorse(address(mailboxMitosis));

    // Deploy DN404Mirror with address(this) as deployer to allow proxy linking
    DN404Mirror mirror = new DN404Mirror(address(this));

    // Deploy proxy
    bytes memory initData = abi.encodeCall(
      xMorse.initialize,
      (
        NAME,
        SYMBOL,
        DECIMALS,
        '', // baseURI
        owner,
        address(hookMitosis),
        address(0), // ISM
        address(mirror) // Mirror
      )
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
    morse = xMorse(payable(address(proxy)));

    // Get mirror NFT address
    mirrorNFT = IERC721(morse.mirrorERC721());

    // Setup bridge
    vm.startPrank(owner);
    morse.enrollRemoteRouter(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))));
    vm.stopPrank();
    
    // Mint NFTs to users directly via bridge simulation
    // User1: 2 NFTs (IDs 1-2)
    _mintNFTsToUser(user1, 2, 1);
    
    // User2: 1 NFT (ID 3)
    _mintNFTsToUser(user2, 1, 3);

    // Deploy reward token
    rewardToken = new MockERC20('Reward Token', 'REWARD', 18);

    // Deploy staking contract
    xMorseStaking stakingImpl = new xMorseStaking();
    bytes memory stakingInitData = abi.encodeCall(
      xMorseStaking.initialize, (address(morse), address(mirrorNFT), address(rewardToken), owner)
    );
    ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), stakingInitData);
    staking = xMorseStaking(payable(address(stakingProxy)));

    // Give users ETH for gas payments
    vm.deal(user1, 10 ether);
    vm.deal(user2, 10 ether);
    vm.deal(user3, 10 ether);
  }

  /// @notice Helper to mint NFTs to a user via bridge simulation
  function _mintNFTsToUser(address user, uint256 count, uint256 startId) internal {
    // Enable NFT minting for user
    vm.prank(user);
    morse.setSkipNFT(false);
    
    // Simulate bridge message
    bytes memory message = abi.encodePacked(
      uint8(0), // MessageType.SendNFT
      bytes32(uint256(1)), // operationId
      user.addressToBytes32(), // recipient
      uint8(count) // tokenIds.length
    );
    for (uint256 i = 0; i < count; i++) {
      message = abi.encodePacked(message, bytes32(startId + i));
    }
    
    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message);
  }

  /// @notice Test precision loss with small amounts
  function testPrecisionLoss_SmallAmounts() public {
    console2.log("\n=== Testing Precision Loss with Small Amounts ===");
    
    // Stake 3 NFTs
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;
    
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), 1);
    mirrorNFT.approve(address(staking), 2);
    staking.stake(new uint256[](1));
    staking.stake(new uint256[](1));
    vm.stopPrank();
    
    vm.startPrank(user2);
    mirrorNFT.approve(address(staking), 3);
    uint256[] memory user2Tokens = new uint256[](1);
    user2Tokens[0] = 3;
    staking.stake(user2Tokens);
    vm.stopPrank();
    
    console2.log("Total staked NFTs:", staking.getTotalStakedNFTs());
    
    // Distribute 100 wei (not divisible by 3)
    uint256 rewardAmount = 100;
    rewardToken.mint(address(staking), rewardAmount);
    
    console2.log("\nDistributing", rewardAmount, "wei to 3 NFTs");
    uint256 balanceBefore = rewardToken.balanceOf(address(staking));
    console2.log("Contract balance before distribution:", balanceBefore);
    
    vm.prank(owner);
    staking.distributeRewards();
    
    uint256 balanceAfter = rewardToken.balanceOf(address(staking));
    console2.log("Contract balance after distribution:", balanceAfter);
    
    // Check pending rewards
    uint256 pending1 = staking.getPendingRewards(1);
    uint256 pending2 = staking.getPendingRewards(2);
    uint256 pending3 = staking.getPendingRewards(3);
    
    console2.log("\nPending rewards:");
    console2.log("  NFT #1:", pending1);
    console2.log("  NFT #2:", pending2);
    console2.log("  NFT #3:", pending3);
    console2.log("  Total claimable:", pending1 + pending2 + pending3);
    console2.log("  Loss:", rewardAmount - (pending1 + pending2 + pending3));
    console2.log("  Loss percentage:", ((rewardAmount - (pending1 + pending2 + pending3)) * 100) / rewardAmount);
    
    // Verify precision loss
    uint256 totalClaimable = pending1 + pending2 + pending3;
    uint256 loss = rewardAmount - totalClaimable;
    
    console2.log("[!] PRECISION LOSS DETECTED");
    console2.log("Loss amount:", loss);
    console2.log("Total distributed:", rewardAmount);
    assertGt(loss, 0, "Precision loss should occur");
    assertEq(loss, rewardAmount % 3, "Loss should equal remainder");
  }

  /// @notice Test cumulative precision loss over multiple distributions
  function testPrecisionLoss_Cumulative() public {
    console2.log("\n=== Testing Cumulative Precision Loss ===");
    
    // Stake 3 NFTs
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), 1);
    mirrorNFT.approve(address(staking), 2);
    uint256[] memory user1Tokens = new uint256[](2);
    user1Tokens[0] = 1;
    user1Tokens[1] = 2;
    staking.stake(user1Tokens);
    vm.stopPrank();
    
    vm.startPrank(user2);
    mirrorNFT.approve(address(staking), 3);
    uint256[] memory user2Tokens = new uint256[](1);
    user2Tokens[0] = 3;
    staking.stake(user2Tokens);
    vm.stopPrank();
    
    uint256 totalLoss = 0;
    uint256 totalDistributed = 0;
    
    // Perform 10 distributions
    for (uint256 i = 1; i <= 10; i++) {
      uint256 rewardAmount = 100; // 100 wei each time
      rewardToken.mint(address(staking), rewardAmount);
      totalDistributed += rewardAmount;
      
      uint256 balanceBefore = rewardToken.balanceOf(address(staking));
      vm.prank(owner);
      staking.distributeRewards();
      uint256 balanceAfter = rewardToken.balanceOf(address(staking));
      
      uint256 pending1 = staking.getPendingRewards(1);
      uint256 pending2 = staking.getPendingRewards(2);
      uint256 pending3 = staking.getPendingRewards(3);
      uint256 totalClaimable = pending1 + pending2 + pending3;
      
      uint256 currentLoss = totalDistributed - totalClaimable;
      totalLoss = currentLoss;
      
      console2.log("Distribution", i, "- Loss so far:", totalLoss);
    }
    
    console2.log("[!] CUMULATIVE PRECISION LOSS");
    console2.log("Total distributed:", totalDistributed);
    console2.log("Total loss:", totalLoss);
    console2.log("Loss percentage (bp):", (totalLoss * 10000) / totalDistributed);
    
    assertGt(totalLoss, 0, "Cumulative loss should occur");
    assertEq(totalLoss, (100 % 3) * 10, "Loss should accumulate");
  }

  /// @notice Test precision loss with larger amounts
  function testPrecisionLoss_LargerAmounts() public {
    console2.log("\n=== Testing Precision Loss with Larger Amounts ===");
    
    // Stake 3 NFTs
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), 1);
    mirrorNFT.approve(address(staking), 2);
    uint256[] memory user1Tokens = new uint256[](2);
    user1Tokens[0] = 1;
    user1Tokens[1] = 2;
    staking.stake(user1Tokens);
    vm.stopPrank();
    
    vm.startPrank(user2);
    mirrorNFT.approve(address(staking), 3);
    uint256[] memory user2Tokens = new uint256[](1);
    user2Tokens[0] = 3;
    staking.stake(user2Tokens);
    vm.stopPrank();
    
    // Distribute 1000 ether
    uint256 rewardAmount = 1000 ether;
    rewardToken.mint(address(staking), rewardAmount);
    
    console2.log("Distributing", rewardAmount / 1 ether, "ether to 3 NFTs");
    
    vm.prank(owner);
    staking.distributeRewards();
    
    uint256 pending1 = staking.getPendingRewards(1);
    uint256 pending2 = staking.getPendingRewards(2);
    uint256 pending3 = staking.getPendingRewards(3);
    uint256 totalClaimable = pending1 + pending2 + pending3;
    uint256 loss = rewardAmount - totalClaimable;
    
    console2.log("\nResults:");
    console2.log("  Total claimable (ether):", totalClaimable / 1 ether);
    console2.log("  Total claimable (wei):", totalClaimable % 1 ether);
    console2.log("  Loss:", loss);
    
    // Even with large amounts, there's still loss due to remainder
    assertGt(loss, 0, "Precision loss should still occur");
    assertLt(loss, 1 ether, "Loss should be less than 1 ether");
  }
}

