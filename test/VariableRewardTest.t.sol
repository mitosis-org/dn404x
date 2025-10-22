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
import { xDN404Treasury } from '../src/xDN404Treasury.sol';
import { IxMorseStaking } from '../src/interfaces/IxMorseStaking.sol';
import { SimpleMulticall } from './mocks/SimpleMulticall.sol';
import { MockERC20 } from './mocks/MockERC20.sol';
import { HyperlaneTestUtils } from './utils/HyperlaneTestUtils.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

/// @notice Test to verify accurate reward distribution with variable reward amounts
contract VariableRewardTest is Test, HyperlaneTestUtils {
  using TypeCasts for address;

  xMorse public morse;
  xMorseStaking public staking;
  MockERC20 public rewardToken;
  IERC721 public mirrorNFT;

  address public owner;
  address public userA;
  address public userB;
  address public userC;

  uint256 constant INITIAL_SUPPLY = 100 ether;
  address multicall = 0xcA11bde05977b3631167028862bE2a173976CA11;

  function setUp() public {
    owner = makeAddr('owner');
    userA = makeAddr('userA');
    userB = makeAddr('userB');
    userC = makeAddr('userC');

    setupHyperlane();

    if (multicall.code.length == 0) {
      vm.etch(multicall, address(new SimpleMulticall()).code);
    }

    // Deploy xMorse
    xMorse implementation = new xMorse(address(mailboxMitosis));
    DN404Mirror mirror = new DN404Mirror(address(this));

    bytes memory initData = abi.encodeCall(
      xMorse.initialize,
      ('xMorse NFT', 'xMORSE', 18, INITIAL_SUPPLY, owner, address(hookMitosis), address(0), address(mirror))
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
    morse = xMorse(payable(address(proxy)));

    vm.startPrank(owner);
    xDN404Treasury treasury = new xDN404Treasury(address(morse), multicall);
    treasury.transferOwnership(address(morse));
    morse.setTreasury(address(treasury));
    vm.stopPrank();

    mirrorNFT = IERC721(morse.mirrorERC721());

    // Deploy reward token
    rewardToken = new MockERC20('Reward Token', 'REWARD', 18);

    // Deploy staking
    xMorseStaking stakingImpl = new xMorseStaking();
    bytes memory stakingInitData = abi.encodeCall(
      xMorseStaking.initialize, (address(morse), address(mirrorNFT), address(rewardToken), owner)
    );
    ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), stakingInitData);
    staking = xMorseStaking(payable(address(stakingProxy)));

    // Distribute NFTs
    vm.startPrank(owner);
    morse.transfer(userA, 5 ether); // 5 NFTs
    morse.transfer(userB, 5 ether); // 5 NFTs
    morse.transfer(userC, 5 ether); // 5 NFTs
    vm.stopPrank();
  }

  /// @notice Test variable reward amounts with users joining at different times
  function testVariableRewardDistribution_Complex() public {
    console2.log('\n=== Complex Variable Reward Test ===\n');

    // T0: UserA stakes 2 NFTs
    console2.log('T0: UserA stakes NFT #1, #2');
    uint256[] memory userATokens = new uint256[](2);
    userATokens[0] = 1;
    userATokens[1] = 2;

    vm.startPrank(userA);
    for (uint256 i = 0; i < userATokens.length; i++) {
      mirrorNFT.approve(address(staking), userATokens[i]);
    }
    staking.stake(userATokens);
    vm.stopPrank();

    console2.log('  Total staked: 2 NFTs');
    console2.log('  accRewardPerNFT: 0\n');

    // T1: First distribution - 1000 tokens (500 per NFT)
    console2.log('T1: Distribute 1000 tokens');
    rewardToken.mint(address(staking), 1000 ether);
    vm.prank(owner);
    staking.distributeRewards();

    uint256 accReward1 = staking.accRewardPerNFT();
    console2.log('  rewardPerNFT: 1000 / 2 = 500 * 1e18');
    console2.log('  accRewardPerNFT:', accReward1 / 1e18);
    console2.log('  NFT #1 pending:', staking.getPendingRewards(1) / 1e18);
    console2.log('  NFT #2 pending:', staking.getPendingRewards(2) / 1e18);
    console2.log('');

    // T2: UserB stakes 1 NFT
    console2.log('T2: UserB stakes NFT #6');
    uint256[] memory userBTokens = new uint256[](1);
    userBTokens[0] = 6;

    vm.startPrank(userB);
    mirrorNFT.approve(address(staking), userBTokens[0]);
    staking.stake(userBTokens);
    vm.stopPrank();

    IxMorseStaking.NFTInfo memory nft6Info = staking.getNFTInfo(6);
    console2.log('  Total staked: 3 NFTs');
    console2.log('  NFT #6 rewardDebt:', nft6Info.rewardDebt / 1e18);
    console2.log('');

    // T3: Second distribution - 3000 tokens (1000 per NFT)
    console2.log('T3: Distribute 3000 tokens (different amount!)');
    rewardToken.mint(address(staking), 3000 ether);
    vm.prank(owner);
    staking.distributeRewards();

    uint256 accReward2 = staking.accRewardPerNFT();
    console2.log('  rewardPerNFT: 3000 / 3 = 1000 * 1e18');
    console2.log('  accRewardPerNFT:', accReward2 / 1e18, '(cumulative)');
    console2.log('  NFT #1 pending:', staking.getPendingRewards(1) / 1e18);
    console2.log('  NFT #2 pending:', staking.getPendingRewards(2) / 1e18);
    console2.log('  NFT #6 pending:', staking.getPendingRewards(6) / 1e18);
    console2.log('');

    // T4: UserC stakes 2 NFTs
    console2.log('T4: UserC stakes NFT #11, #12');
    uint256[] memory userCTokens = new uint256[](2);
    userCTokens[0] = 11;
    userCTokens[1] = 12;

    vm.startPrank(userC);
    for (uint256 i = 0; i < userCTokens.length; i++) {
      mirrorNFT.approve(address(staking), userCTokens[i]);
    }
    staking.stake(userCTokens);
    vm.stopPrank();

    console2.log('  Total staked: 5 NFTs');
    console2.log('');

    // T5: Third distribution - 500 tokens (100 per NFT)
    console2.log('T5: Distribute 500 tokens (another different amount!)');
    rewardToken.mint(address(staking), 500 ether);
    vm.prank(owner);
    staking.distributeRewards();

    uint256 accReward3 = staking.accRewardPerNFT();
    console2.log('  rewardPerNFT: 500 / 5 = 100 * 1e18');
    console2.log('  accRewardPerNFT:', accReward3 / 1e18, '(cumulative)');
    console2.log('');

    console2.log('Final pending rewards:');
    console2.log('  NFT #1 (UserA):', staking.getPendingRewards(1) / 1e18);
    console2.log('  NFT #2 (UserA):', staking.getPendingRewards(2) / 1e18);
    console2.log('  NFT #6 (UserB):', staking.getPendingRewards(6) / 1e18);
    console2.log('  NFT #11 (UserC):', staking.getPendingRewards(11) / 1e18);
    console2.log('  NFT #12 (UserC):', staking.getPendingRewards(12) / 1e18);
    console2.log('');

    // Verify correctness
    console2.log('=== Verification ===');

    // NFT #1, #2: Should get 500 + 1000 + 100 = 1600
    uint256 pending1 = staking.getPendingRewards(1);
    uint256 pending2 = staking.getPendingRewards(2);
    assertEq(pending1, 1600 ether, 'NFT #1 should have 1600');
    assertEq(pending2, 1600 ether, 'NFT #2 should have 1600');
    console2.log('NFT #1, #2 (UserA): 500 + 1000 + 100 = 1600 CORRECT');

    // NFT #6: Should get 0 + 1000 + 100 = 1100
    uint256 pending6 = staking.getPendingRewards(6);
    assertEq(pending6, 1100 ether, 'NFT #6 should have 1100');
    console2.log('NFT #6 (UserB): 0 + 1000 + 100 = 1100 CORRECT');

    // NFT #11, #12: Should get 0 + 0 + 100 = 100
    uint256 pending11 = staking.getPendingRewards(11);
    uint256 pending12 = staking.getPendingRewards(12);
    assertEq(pending11, 100 ether, 'NFT #11 should have 100');
    assertEq(pending12, 100 ether, 'NFT #12 should have 100');
    console2.log('NFT #11, #12 (UserC): 0 + 0 + 100 = 100 CORRECT');

    // Total distributed
    uint256 totalPending = pending1 + pending2 + pending6 + pending11 + pending12;
    uint256 totalDistributed = 1000 ether + 3000 ether + 500 ether;
    assertEq(totalPending, totalDistributed, 'Total should match');
    console2.log('\nTotal distributed: 1000 + 3000 + 500 = 4500');
    console2.log('Total pending: 1600*2 + 1100 + 100*2 = 4500');
    console2.log('PERFECT MATCH!');

    // Claim and verify
    console2.log('\n=== Claiming Rewards ===');

    vm.prank(userA);
    staking.claimRewards(userATokens);
    assertEq(rewardToken.balanceOf(userA), 3200 ether);
    console2.log('UserA claimed: 3200 (1600 * 2 NFTs)');

    vm.prank(userB);
    staking.claimRewards(userBTokens);
    assertEq(rewardToken.balanceOf(userB), 1100 ether);
    console2.log('UserB claimed: 1100 (1100 * 1 NFT)');

    vm.prank(userC);
    staking.claimRewards(userCTokens);
    assertEq(rewardToken.balanceOf(userC), 200 ether);
    console2.log('UserC claimed: 200 (100 * 2 NFTs)');

    console2.log('\nTotal claimed: 3200 + 1100 + 200 = 4500');
    console2.log('Matches total distributed: 4500');
    console2.log('\n[SUCCESS] ALGORITHM IS PERFECTLY ACCURATE!\n');
  }
}

