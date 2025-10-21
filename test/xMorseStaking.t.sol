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

contract xMorseStakingTest is Test, HyperlaneTestUtils {
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
        INITIAL_SUPPLY,
        owner,
        address(hookMitosis),
        address(0), // ISM
        address(mirror) // Mirror
      )
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
    morse = xMorse(payable(address(proxy)));

    // Deploy and set Treasury
    vm.startPrank(owner);
    xDN404Treasury treasury = new xDN404Treasury(address(morse), multicall);
    treasury.transferOwnership(address(morse));
    morse.setTreasury(address(treasury));
    vm.stopPrank();

    // Get mirror NFT address
    mirrorNFT = IERC721(morse.mirrorERC721());

    // Deploy reward token
    rewardToken = new MockERC20('Reward Token', 'REWARD', 18);

    // Deploy staking contract
    xMorseStaking stakingImpl = new xMorseStaking();
    bytes memory stakingInitData = abi.encodeCall(
      xMorseStaking.initialize, (address(morse), address(mirrorNFT), address(rewardToken), owner)
    );
    ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), stakingInitData);
    staking = xMorseStaking(payable(address(stakingProxy)));

    // Setup: Distribute NFTs to users
    _setupNFTs();

    // Give users ETH for gas payments
    vm.deal(user1, 10 ether);
    vm.deal(user2, 10 ether);
    vm.deal(user3, 10 ether);
  }

  function _setupNFTs() internal {
    // Transfer some tokens to users so they get NFTs
    vm.startPrank(owner);
    morse.transfer(user1, 10 ether); // 10 NFTs
    morse.transfer(user2, 15 ether); // 15 NFTs
    morse.transfer(user3, 5 ether); // 5 NFTs
    vm.stopPrank();
  }

  //====================================================================================//
  //================================== INITIALIZATION TESTS ============================//
  //====================================================================================//

  function testInitialization() public view {
    assertEq(staking.xMorseToken(), address(morse));
    assertEq(staking.mirrorNFT(), address(mirrorNFT));
    assertEq(staking.rewardToken(), address(rewardToken));
    assertEq(staking.owner(), owner);
    assertEq(staking.getTotalStakedNFTs(), 0);
    assertEq(staking.accRewardPerNFT(), 0);
    assertEq(staking.lockupPeriod(), 7 days); // Default lockup period
    
    // CRITICAL: Verify skipNFT is set to prevent unwanted NFT minting
    assertTrue(morse.getSkipNFT(address(staking)), "Staking contract should have skipNFT enabled");
  }

  function testInitialize_RevertIfZeroAddress() public {
    xMorseStaking stakingImpl = new xMorseStaking();

    // Test zero xMorseToken
    vm.expectRevert(IxMorseStaking.ZeroAddress.selector);
    new ERC1967Proxy(
      address(stakingImpl),
      abi.encodeCall(
        xMorseStaking.initialize, (address(0), address(mirrorNFT), address(rewardToken), owner)
      )
    );

    // Test zero mirrorNFT
    vm.expectRevert(IxMorseStaking.ZeroAddress.selector);
    new ERC1967Proxy(
      address(stakingImpl),
      abi.encodeCall(
        xMorseStaking.initialize, (address(morse), address(0), address(rewardToken), owner)
      )
    );

    // Test zero rewardToken
    vm.expectRevert(IxMorseStaking.ZeroAddress.selector);
    new ERC1967Proxy(
      address(stakingImpl),
      abi.encodeCall(xMorseStaking.initialize, (address(morse), address(mirrorNFT), address(0), owner))
    );

    // Test zero owner
    vm.expectRevert(IxMorseStaking.ZeroAddress.selector);
    new ERC1967Proxy(
      address(stakingImpl),
      abi.encodeCall(
        xMorseStaking.initialize, (address(morse), address(mirrorNFT), address(rewardToken), address(0))
      )
    );
  }

  //====================================================================================//
  //================================== STAKING TESTS ===================================//
  //====================================================================================//

  function testStake_Single() public {
    uint256 tokenId = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    
    staking.stake(tokenIds);
    vm.stopPrank();

    assertEq(staking.getTotalStakedNFTs(), 1);
    assertEq(mirrorNFT.ownerOf(tokenId), address(staking));

    IxMorseStaking.NFTInfo memory info = staking.getNFTInfo(tokenId);
    assertEq(info.owner, user1);
    assertEq(info.stakedAt, block.timestamp);
    assertEq(info.lockupEndTime, block.timestamp + 7 days);
    assertEq(info.unclaimedRewards, 0);

    uint256[] memory stakedNFTs = staking.getStakedNFTs(user1);
    assertEq(stakedNFTs.length, 1);
    assertEq(stakedNFTs[0], tokenId);
  }

  function testStake_Multiple() public {
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds[i]);
    }
    staking.stake(tokenIds);
    vm.stopPrank();

    assertEq(staking.getTotalStakedNFTs(), 3);

    for (uint256 i = 0; i < tokenIds.length; i++) {
      assertEq(mirrorNFT.ownerOf(tokenIds[i]), address(staking));
      IxMorseStaking.NFTInfo memory info = staking.getNFTInfo(tokenIds[i]);
      assertEq(info.owner, user1);
    }

    uint256[] memory stakedNFTs = staking.getStakedNFTs(user1);
    assertEq(stakedNFTs.length, 3);
  }

  function testStake_MultipleUsers() public {
    // User1 stakes 2 NFTs
    uint256[] memory user1TokenIds = new uint256[](2);
    user1TokenIds[0] = 1;
    user1TokenIds[1] = 2;

    vm.startPrank(user1);
    for (uint256 i = 0; i < user1TokenIds.length; i++) {
      mirrorNFT.approve(address(staking), user1TokenIds[i]);
    }
    staking.stake(user1TokenIds);
    vm.stopPrank();

    // User2 stakes 3 NFTs
    uint256[] memory user2TokenIds = new uint256[](3);
    user2TokenIds[0] = 11;
    user2TokenIds[1] = 12;
    user2TokenIds[2] = 13;

    vm.startPrank(user2);
    for (uint256 i = 0; i < user2TokenIds.length; i++) {
      mirrorNFT.approve(address(staking), user2TokenIds[i]);
    }
    staking.stake(user2TokenIds);
    vm.stopPrank();

    assertEq(staking.getTotalStakedNFTs(), 5);
    assertEq(staking.getStakedNFTs(user1).length, 2);
    assertEq(staking.getStakedNFTs(user2).length, 3);
  }

  function testStake_RevertIfEmptyArray() public {
    uint256[] memory emptyArray = new uint256[](0);

    vm.prank(user1);
    vm.expectRevert(IxMorseStaking.EmptyArray.selector);
    staking.stake(emptyArray);
  }

  function testStake_RevertIfAlreadyStaked() public {
    uint256 tokenId = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    
    staking.stake(tokenIds);

    // Try to stake again
    vm.expectRevert(abi.encodeWithSelector(IxMorseStaking.NFTAlreadyStaked.selector, tokenId));
    staking.stake(tokenIds);
    vm.stopPrank();
  }

  function testStake_WhenPaused() public {
    vm.prank(owner);
    staking.pause();

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    vm.expectRevert();
    staking.stake(tokenIds);
    vm.stopPrank();
  }

  function testStake_NoUnwantedNFTMinting() public {
    // This test verifies that staking NFTs doesn't cause unwanted NFT creation
    // in the staking contract due to accumulated DN404 tokens
    
    // Get initial state
    uint256 initialContractBalance = morse.balanceOf(address(staking));
    assertEq(initialContractBalance, 0, "Contract should start with 0 balance");
    
    // Stake 5 NFTs from different users
    uint256[] memory tokenIds1 = new uint256[](2);
    tokenIds1[0] = 1;
    tokenIds1[1] = 2;
    
    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds1.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds1[i]);
    }
    staking.stake(tokenIds1);
    vm.stopPrank();
    
    uint256[] memory tokenIds2 = new uint256[](3);
    tokenIds2[0] = 11;
    tokenIds2[1] = 12;
    tokenIds2[2] = 13;
    
    vm.startPrank(user2);
    for (uint256 i = 0; i < tokenIds2.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds2[i]);
    }
    staking.stake(tokenIds2);
    vm.stopPrank();
    
    // Verify contract received the tokens
    uint256 finalContractBalance = morse.balanceOf(address(staking));
    assertEq(finalContractBalance, 5 ether, "Contract should have 5 tokens from 5 NFTs");
    
    // CRITICAL: Verify no new NFTs were minted to the staking contract
    // With skipNFT=true, the contract should have 0 NFTs despite having 5 tokens
    uint256 contractNFTBalance = mirrorNFT.balanceOf(address(staking));
    assertEq(contractNFTBalance, 5, "Contract should have exactly 5 NFTs (the staked ones)");
    
    // Verify the NFT IDs are the ones staked (not newly minted ones)
    assertEq(mirrorNFT.ownerOf(1), address(staking));
    assertEq(mirrorNFT.ownerOf(2), address(staking));
    assertEq(mirrorNFT.ownerOf(11), address(staking));
    assertEq(mirrorNFT.ownerOf(12), address(staking));
    assertEq(mirrorNFT.ownerOf(13), address(staking));
  }

  //====================================================================================//
  //================================== UNSTAKING TESTS =================================//
  //====================================================================================//

  function testUnstake_Success() public {
    // Stake first
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    staking.stake(tokenIds);

    // Fast forward past lockup period
    vm.warp(block.timestamp + 7 days + 1);

    // Unstake
    staking.unstake(tokenIds);
    vm.stopPrank();

    assertEq(staking.getTotalStakedNFTs(), 0);
    assertEq(mirrorNFT.ownerOf(tokenId), user1);

    IxMorseStaking.NFTInfo memory info = staking.getNFTInfo(tokenId);
    assertEq(info.owner, address(0));

    uint256[] memory stakedNFTs = staking.getStakedNFTs(user1);
    assertEq(stakedNFTs.length, 0);
  }

  function testUnstake_Multiple() public {
    // Stake multiple
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds[i]);
    }
    staking.stake(tokenIds);

    // Fast forward past lockup period
    vm.warp(block.timestamp + 7 days + 1);

    // Unstake all
    staking.unstake(tokenIds);
    vm.stopPrank();

    assertEq(staking.getTotalStakedNFTs(), 0);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      assertEq(mirrorNFT.ownerOf(tokenIds[i]), user1);
    }
  }

  function testUnstake_RevertIfLockupNotEnded() public {
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    staking.stake(tokenIds);

    // Try to unstake before lockup ends
    vm.expectRevert(abi.encodeWithSelector(IxMorseStaking.LockupPeriodNotEnded.selector, tokenId));
    staking.unstake(tokenIds);
    vm.stopPrank();
  }

  function testUnstake_RevertIfUnclaimedRewards() public {
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    // Stake
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Distribute rewards
    rewardToken.mint(address(staking), 1000 ether);
    vm.prank(owner);
    staking.distributeRewards();

    // Fast forward past lockup
    vm.warp(block.timestamp + 7 days + 1);

    // Try to unstake with unclaimed rewards
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(IxMorseStaking.UnclaimedRewardsExist.selector, tokenId));
    staking.unstake(tokenIds);
  }

  function testUnstake_RevertIfNotOwner() public {
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    // User1 stakes
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Fast forward past lockup
    vm.warp(block.timestamp + 7 days + 1);

    // User2 tries to unstake
    vm.prank(user2);
    vm.expectRevert(abi.encodeWithSelector(IxMorseStaking.NotNFTOwner.selector, tokenId));
    staking.unstake(tokenIds);
  }

  function testUnstake_RevertIfEmptyArray() public {
    uint256[] memory emptyArray = new uint256[](0);

    vm.prank(user1);
    vm.expectRevert(IxMorseStaking.EmptyArray.selector);
    staking.unstake(emptyArray);
  }

  //====================================================================================//
  //================================== REWARD DISTRIBUTION TESTS =======================//
  //====================================================================================//

  function testDistributeRewards_Success() public {
    // Stake 2 NFTs from user1
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds[i]);
    }
    staking.stake(tokenIds);
    vm.stopPrank();

    // Mint rewards to staking contract
    uint256 rewardAmount = 1000 ether;
    rewardToken.mint(address(staking), rewardAmount);

    // Distribute rewards (as owner)
    uint256 accRewardBefore = staking.accRewardPerNFT();
    vm.prank(owner);
    staking.distributeRewards();
    uint256 accRewardAfter = staking.accRewardPerNFT();

    uint256 expectedRewardPerNFT = (rewardAmount * 1e18) / 2; // 2 NFTs staked
    assertEq(accRewardAfter - accRewardBefore, expectedRewardPerNFT);
  }

  function testDistributeRewards_RevertIfNotOwner() public {
    // Stake 1 NFT
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Mint rewards
    rewardToken.mint(address(staking), 1000 ether);

    // Try to distribute as non-owner (should revert)
    vm.prank(user1);
    vm.expectRevert();
    staking.distributeRewards();

    // Verify owner can distribute
    vm.prank(owner);
    staking.distributeRewards(); // Should succeed
  }

  function testDistributeRewards_MultipleDistributions() public {
    // Stake 3 NFTs
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds[i]);
    }
    staking.stake(tokenIds);
    vm.stopPrank();

    // First distribution
    rewardToken.mint(address(staking), 300 ether);
    vm.prank(owner);
    staking.distributeRewards();
    uint256 accRewardAfter1 = staking.accRewardPerNFT();
    assertEq(accRewardAfter1, (300 ether * 1e18) / 3);

    // Second distribution
    rewardToken.mint(address(staking), 600 ether);
    vm.prank(owner);
    staking.distributeRewards();
    uint256 accRewardAfter2 = staking.accRewardPerNFT();
    assertEq(accRewardAfter2 - accRewardAfter1, (600 ether * 1e18) / 3);
  }

  function testDistributeRewards_RevertIfNoStakers() public {
    rewardToken.mint(address(staking), 1000 ether);

    vm.prank(owner);
    vm.expectRevert(IxMorseStaking.NoStakersInPool.selector);
    staking.distributeRewards();
  }

  function testDistributeRewards_RevertIfNoRewards() public {
    // Stake 1 NFT
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Try to distribute without rewards
    vm.prank(owner);
    vm.expectRevert(IxMorseStaking.NoRewardsAvailable.selector);
    staking.distributeRewards();
  }

  //====================================================================================//
  //================================== CLAIM REWARDS TESTS =============================//
  //====================================================================================//

  function testClaimRewards_Success() public {
    // Stake 1 NFT
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Distribute rewards
    uint256 rewardAmount = 1000 ether;
    rewardToken.mint(address(staking), rewardAmount);
    vm.prank(owner);
    staking.distributeRewards();

    // Check pending rewards
    uint256 pending = staking.getPendingRewards(tokenId);
    assertEq(pending, rewardAmount);

    // Claim rewards
    uint256 balanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimRewards(tokenIds);
    uint256 balanceAfter = rewardToken.balanceOf(user1);

    assertEq(balanceAfter - balanceBefore, rewardAmount);
    assertEq(staking.getPendingRewards(tokenId), 0);
  }

  function testClaimRewards_Multiple() public {
    // User1 stakes 2 NFTs
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds[i]);
    }
    staking.stake(tokenIds);
    vm.stopPrank();

    // Distribute rewards
    uint256 rewardAmount = 1000 ether;
    rewardToken.mint(address(staking), rewardAmount);
    vm.prank(owner);
    staking.distributeRewards();

    // Claim for both NFTs
    uint256 balanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimRewards(tokenIds);
    uint256 balanceAfter = rewardToken.balanceOf(user1);

    assertEq(balanceAfter - balanceBefore, rewardAmount); // Both NFTs get full amount
  }

  function testClaimRewards_ProportionalDistribution() public {
    // User1 stakes 1 NFT
    uint256[] memory user1TokenIds = new uint256[](1);
    user1TokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), user1TokenIds[0]);
    staking.stake(user1TokenIds);
    vm.stopPrank();

    // User2 stakes 2 NFTs
    uint256[] memory user2TokenIds = new uint256[](2);
    user2TokenIds[0] = 11;
    user2TokenIds[1] = 12;

    vm.startPrank(user2);
    for (uint256 i = 0; i < user2TokenIds.length; i++) {
      mirrorNFT.approve(address(staking), user2TokenIds[i]);
    }
    staking.stake(user2TokenIds);
    vm.stopPrank();

    // Total: 3 NFTs staked
    // Distribute 3000 ether rewards (1000 per NFT)
    uint256 rewardAmount = 3000 ether;
    rewardToken.mint(address(staking), rewardAmount);
    vm.prank(owner);
    staking.distributeRewards();

    // User1 claims (1 NFT = 1000 ether)
    uint256 user1BalanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimRewards(user1TokenIds);
    uint256 user1BalanceAfter = rewardToken.balanceOf(user1);
    assertEq(user1BalanceAfter - user1BalanceBefore, 1000 ether);

    // User2 claims (2 NFTs = 2000 ether)
    uint256 user2BalanceBefore = rewardToken.balanceOf(user2);
    vm.prank(user2);
    staking.claimRewards(user2TokenIds);
    uint256 user2BalanceAfter = rewardToken.balanceOf(user2);
    assertEq(user2BalanceAfter - user2BalanceBefore, 2000 ether);
  }

  function testClaimRewards_RevertIfNotOwner() public {
    // User1 stakes
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenId);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Distribute rewards
    rewardToken.mint(address(staking), 1000 ether);
    vm.prank(owner);
    staking.distributeRewards();

    // User2 tries to claim
    vm.prank(user2);
    vm.expectRevert(abi.encodeWithSelector(IxMorseStaking.NotNFTOwner.selector, tokenId));
    staking.claimRewards(tokenIds);
  }

  function testClaimRewards_RevertIfEmptyArray() public {
    uint256[] memory emptyArray = new uint256[](0);

    vm.prank(user1);
    vm.expectRevert(IxMorseStaking.EmptyArray.selector);
    staking.claimRewards(emptyArray);
  }

  function testClaimAllRewards_Success() public {
    // Stake 3 NFTs
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds[i]);
    }
    staking.stake(tokenIds);
    vm.stopPrank();

    // Distribute rewards
    uint256 rewardAmount = 3000 ether;
    rewardToken.mint(address(staking), rewardAmount);
    vm.prank(owner);
    staking.distributeRewards();

    // Claim all
    uint256 balanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimAllRewards();
    uint256 balanceAfter = rewardToken.balanceOf(user1);

    assertEq(balanceAfter - balanceBefore, rewardAmount);
  }

  function testClaimAllRewards_RevertIfNoStakedNFTs() public {
    vm.prank(user1);
    vm.expectRevert(IxMorseStaking.EmptyArray.selector);
    staking.claimAllRewards();
  }

  //====================================================================================//
  //================================== FULL WORKFLOW TESTS =============================//
  //====================================================================================//

  function testFullWorkflow() public {
    // 1. User1 stakes 2 NFTs
    uint256[] memory user1TokenIds = new uint256[](2);
    user1TokenIds[0] = 1;
    user1TokenIds[1] = 2;

    vm.startPrank(user1);
    for (uint256 i = 0; i < user1TokenIds.length; i++) {
      mirrorNFT.approve(address(staking), user1TokenIds[i]);
    }
    staking.stake(user1TokenIds);
    vm.stopPrank();

    // 2. First reward distribution
    rewardToken.mint(address(staking), 2000 ether);
    vm.prank(owner);
    staking.distributeRewards();

    // 3. User2 stakes 1 NFT
    uint256[] memory user2TokenIds = new uint256[](1);
    user2TokenIds[0] = 11;

    vm.startPrank(user2);
    mirrorNFT.approve(address(staking), user2TokenIds[0]);
    staking.stake(user2TokenIds);
    vm.stopPrank();

    // 4. Second reward distribution
    rewardToken.mint(address(staking), 3000 ether);
    vm.prank(owner);
    staking.distributeRewards();

    // 5. User1 claims (should get 2000 from first + 2000 from second = 4000)
    uint256 user1BalanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimAllRewards();
    uint256 user1BalanceAfter = rewardToken.balanceOf(user1);
    assertEq(user1BalanceAfter - user1BalanceBefore, 4000 ether);

    // 6. User2 claims (should get 1000 from second only)
    uint256 user2BalanceBefore = rewardToken.balanceOf(user2);
    vm.prank(user2);
    staking.claimRewards(user2TokenIds);
    uint256 user2BalanceAfter = rewardToken.balanceOf(user2);
    assertEq(user2BalanceAfter - user2BalanceBefore, 1000 ether);

    // 7. Fast forward and unstake
    vm.warp(block.timestamp + 7 days + 1);

    vm.prank(user1);
    staking.unstake(user1TokenIds);

    vm.prank(user2);
    staking.unstake(user2TokenIds);

    assertEq(staking.getTotalStakedNFTs(), 0);
  }

  //====================================================================================//
  //================================== OWNER FUNCTIONS TESTS ===========================//
  //====================================================================================//

  function testSetRewardToken_Success() public {
    MockERC20 newRewardToken = new MockERC20('New Reward', 'NREWARD', 18);

    vm.prank(owner);
    staking.setRewardToken(address(newRewardToken));

    assertEq(staking.rewardToken(), address(newRewardToken));
  }

  function testSetRewardToken_RevertIfNotOwner() public {
    MockERC20 newRewardToken = new MockERC20('New Reward', 'NREWARD', 18);

    vm.prank(user1);
    vm.expectRevert();
    staking.setRewardToken(address(newRewardToken));
  }

  function testSetRewardToken_RevertIfZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(IxMorseStaking.ZeroAddress.selector);
    staking.setRewardToken(address(0));
  }

  function testPause_Success() public {
    vm.prank(owner);
    staking.pause();

    // Try to stake while paused
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    vm.expectRevert();
    staking.stake(tokenIds);
    vm.stopPrank();
  }

  function testUnpause_Success() public {
    vm.prank(owner);
    staking.pause();

    vm.prank(owner);
    staking.unpause();

    // Should be able to stake after unpause
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    staking.stake(tokenIds);
    vm.stopPrank();

    assertEq(staking.getTotalStakedNFTs(), 1);
  }

  function testPause_RevertIfNotOwner() public {
    vm.prank(user1);
    vm.expectRevert();
    staking.pause();
  }

  function testSetLockupPeriod_Success() public {
    uint256 newLockupPeriod = 10;

    vm.prank(owner);
    staking.setLockupPeriod(newLockupPeriod);

    assertEq(staking.lockupPeriod(), newLockupPeriod);
  }

  function testSetLockupPeriod_RevertIfNotOwner() public {
    vm.prank(user1);
    vm.expectRevert();
    staking.setLockupPeriod(10);
  }

  function testSetLockupPeriod_RevertIfTooShort() public {
    vm.prank(owner);
    vm.expectRevert(xMorseStaking.LockupPeriodTooShort.selector);
    staking.setLockupPeriod(0);
  }

  function testSetLockupPeriod_AffectsNewStakes() public {
    // Set lockup to 10 seconds
    vm.prank(owner);
    staking.setLockupPeriod(10);

    // Stake NFT
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Check lockup end time
    IxMorseStaking.NFTInfo memory info = staking.getNFTInfo(1);
    assertEq(info.lockupEndTime - info.stakedAt, 10, "Should have 10-second lockup");

    // Wait 11 seconds and unstake
    vm.warp(block.timestamp + 11);

    vm.prank(user1);
    staking.unstake(tokenIds);

    // Verify NFT returned
    assertEq(mirrorNFT.ownerOf(1), user1, "NFT should be returned to user1");
  }

  //====================================================================================//
  //================================== UPGRADE TESTS ===================================//
  //====================================================================================//

  function testUpgrade_Success() public {
    // Deploy new implementation
    xMorseStaking newImpl = new xMorseStaking();

    // Upgrade
    vm.prank(owner);
    staking.upgradeToAndCall(address(newImpl), '');

    // Verify state is preserved
    assertEq(staking.xMorseToken(), address(morse));
    assertEq(staking.mirrorNFT(), address(mirrorNFT));
  }

  function testUpgrade_RevertIfNotOwner() public {
    xMorseStaking newImpl = new xMorseStaking();

    vm.prank(user1);
    vm.expectRevert();
    staking.upgradeToAndCall(address(newImpl), '');
  }

  //====================================================================================//
  //================================== EDGE CASE TESTS =================================//
  //====================================================================================//

  function testStakeAndImmediateDistribution() public {
    // Stake 1 NFT
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Immediate distribution
    rewardToken.mint(address(staking), 1000 ether);
    vm.prank(owner);
    staking.distributeRewards();

    // Should receive full rewards
    assertEq(staking.getPendingRewards(1), 1000 ether);
  }

  function testMultipleDistributionsBeforeClaim() public {
    // Stake 1 NFT
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), tokenIds[0]);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Multiple distributions
    rewardToken.mint(address(staking), 100 ether);
    vm.prank(owner);
    staking.distributeRewards();

    rewardToken.mint(address(staking), 200 ether);
    vm.prank(owner);
    staking.distributeRewards();

    rewardToken.mint(address(staking), 300 ether);
    vm.prank(owner);
    staking.distributeRewards();

    // Should accumulate all rewards
    assertEq(staking.getPendingRewards(1), 600 ether);

    // Claim all at once
    vm.prank(user1);
    staking.claimRewards(tokenIds);

    assertEq(rewardToken.balanceOf(user1), 600 ether);
  }

  function testArrayManagement_UnstakeMiddleElement() public {
    // Stake 5 NFTs
    uint256[] memory tokenIds = new uint256[](5);
    for (uint256 i = 0; i < 5; i++) {
      tokenIds[i] = i + 1;
    }

    vm.startPrank(user1);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      mirrorNFT.approve(address(staking), tokenIds[i]);
    }
    staking.stake(tokenIds);
    vm.stopPrank();

    // Fast forward
    vm.warp(block.timestamp + 7 days + 1);

    // Unstake middle element (tokenId 3)
    uint256[] memory unstakeIds = new uint256[](1);
    unstakeIds[0] = 3;

    vm.prank(user1);
    staking.unstake(unstakeIds);

    // Check array integrity
    uint256[] memory remaining = staking.getStakedNFTs(user1);
    assertEq(remaining.length, 4);

    // Verify correct elements remain
    bool found1 = false;
    bool found2 = false;
    bool found4 = false;
    bool found5 = false;

    for (uint256 i = 0; i < remaining.length; i++) {
      if (remaining[i] == 1) found1 = true;
      if (remaining[i] == 2) found2 = true;
      if (remaining[i] == 4) found4 = true;
      if (remaining[i] == 5) found5 = true;
    }

    assertTrue(found1 && found2 && found4 && found5);
  }
}

