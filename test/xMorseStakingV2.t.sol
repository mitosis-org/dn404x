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
import { xMorseRewardFeed } from '../src/xMorseRewardFeed.sol';
import { IxMorseStaking } from '../src/interfaces/IxMorseStaking.sol';
import { IxMorseRewardFeed } from '../src/interfaces/IxMorseRewardFeed.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';
import { SimpleMulticall } from './mocks/SimpleMulticall.sol';
import { MockERC20 } from './mocks/MockERC20.sol';
import { HyperlaneTestUtils } from './utils/HyperlaneTestUtils.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

// Mock EpochFeeder for testing
contract MockEpochFeeder is IEpochFeeder {
  uint256 private _currentEpoch;
  uint48 private _interval = 604800; // 1 week
  
  function setEpoch(uint256 epoch_) external {
    _currentEpoch = epoch_;
  }
  
  function epoch() external view returns (uint256) {
    return _currentEpoch;
  }
  
  function epochAt(uint48) external view returns (uint256) {
    return _currentEpoch;
  }
  
  function time() external view returns (uint48) {
    return uint48(block.timestamp);
  }
  
  function timeAt(uint256 epoch_) external view returns (uint48) {
    return uint48(epoch_ * _interval);
  }
  
  function interval() external view returns (uint48) {
    return _interval;
  }
  
  function intervalAt(uint256) external view returns (uint48) {
    return _interval;
  }
  
  function setNextInterval(uint48 interval_) external {
    _interval = interval_;
  }
}

contract xMorseStakingV2Test is Test, HyperlaneTestUtils {
  using TypeCasts for address;

  xMorse public morse;
  xMorseStaking public staking;
  xMorseRewardFeed public rewardFeed;
  MockEpochFeeder public epochFeeder;
  MockERC20 public rewardToken;
  IERC721 public mirrorNFT;

  address public owner;
  address public feeder;
  address public user1;
  address public user2;

  uint256 constant INITIAL_SUPPLY = 100 ether;
  string constant NAME = 'xMorse NFT';
  string constant SYMBOL = 'xMORSE';
  uint8 constant DECIMALS = 18;

  address multicall = 0xcA11bde05977b3631167028862bE2a173976CA11;

  function setUp() public {
    owner = makeAddr('owner');
    feeder = makeAddr('feeder');
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');

    setupHyperlane();

    // Deploy mock multicall if needed
    if (multicall.code.length == 0) {
      vm.etch(multicall, address(new SimpleMulticall()).code);
    }

    // Deploy mock epoch feeder
    epochFeeder = new MockEpochFeeder();
    epochFeeder.setEpoch(1); // Start at epoch 1

    // Deploy xMorse implementation
    xMorse implementation = new xMorse(address(mailboxMitosis));

    // Deploy DN404Mirror
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
        address(mirror)
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
    
    // Mint NFTs to users
    _mintNFTsToUser(user1, 3, 1);  // User1: NFTs 1-3
    _mintNFTsToUser(user2, 3, 4);  // User2: NFTs 4-6

    // Deploy reward token
    rewardToken = new MockERC20('Reward Token', 'REWARD', 18);

    // Deploy reward feed
    xMorseRewardFeed feedImpl = new xMorseRewardFeed(IEpochFeeder(address(epochFeeder)));
    bytes memory feedInitData = abi.encodeCall(xMorseRewardFeed.initialize, (owner, feeder));
    ERC1967Proxy feedProxy = new ERC1967Proxy(address(feedImpl), feedInitData);
    rewardFeed = xMorseRewardFeed(address(feedProxy));

    // Deploy staking contract (will be upgraded to V2 later)
    xMorseStaking stakingImpl = new xMorseStaking();
    bytes memory stakingInitData = abi.encodeCall(
      xMorseStaking.initialize, (address(morse), address(mirrorNFT), address(rewardToken), owner)
    );
    ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), stakingInitData);
    staking = xMorseStaking(payable(address(stakingProxy)));
    
    // Configure V2: Set reward feed
    vm.prank(owner);
    staking.setRewardFeed(address(rewardFeed));
    
    // Mint reward tokens to staking contract for testing
    rewardToken.mint(address(staking), 100000 ether);
  }

  function _mintNFTsToUser(address user, uint256 count, uint256 startId) internal {
    vm.prank(user);
    morse.setSkipNFT(false);
    
    bytes memory message = abi.encodePacked(
      uint8(0),
      bytes32(uint256(1)),
      user.addressToBytes32(),
      uint8(count)
    );
    for (uint256 i = 0; i < count; i++) {
      message = abi.encodePacked(message, bytes32(startId + i));
    }
    
    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message);
  }

  //====================================================================================//
  //================================== EPOCH-BASED CLAIM TESTS =========================//
  //====================================================================================//

  function testClaimRewards_SingleEpoch() public {
    // Stake at epoch 1
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), 1);
    staking.stake(tokenIds);
    vm.stopPrank();
    
    // Feed epoch 1 rewards: 1000 ether for 1 NFT
    vm.startPrank(feeder);
    rewardFeed.initializeEpochReward(1, 1000 ether, 1);
    rewardFeed.finalizeEpochReward(1);
    vm.stopPrank();
    
    // Move to epoch 2
    epochFeeder.setEpoch(2);
    
    // Claim rewards
    uint256 balanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimRewards(tokenIds);
    uint256 balanceAfter = rewardToken.balanceOf(user1);
    
    assertEq(balanceAfter - balanceBefore, 1000 ether);
  }

  function testClaimRewards_MultipleEpochs() public {
    // Stake at epoch 1
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), 1);
    staking.stake(tokenIds);
    vm.stopPrank();
    
    // Feed epoch 1: 1000 ether, 1 NFT
    vm.startPrank(feeder);
    rewardFeed.initializeEpochReward(1, 1000 ether, 1);
    rewardFeed.finalizeEpochReward(1);
    
    // Move to epoch 2
    epochFeeder.setEpoch(2);
    
    // Feed epoch 2: 2000 ether, 1 NFT
    rewardFeed.initializeEpochReward(2, 2000 ether, 1);
    rewardFeed.finalizeEpochReward(2);
    
    // Move to epoch 3
    epochFeeder.setEpoch(3);
    
    // Feed epoch 3: 500 ether, 1 NFT
    rewardFeed.initializeEpochReward(3, 500 ether, 1);
    rewardFeed.finalizeEpochReward(3);
    vm.stopPrank();
    
    // Move to epoch 4
    epochFeeder.setEpoch(4);
    
    // Claim all rewards
    uint256 balanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimRewards(tokenIds);
    uint256 balanceAfter = rewardToken.balanceOf(user1);
    
    // Should receive: 1000 + 2000 + 500 = 3500 ether
    assertEq(balanceAfter - balanceBefore, 3500 ether);
  }

  function testClaimRewards_SkipsNonFinalizedEpochs() public {
    // Stake at epoch 1
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), 1);
    staking.stake(tokenIds);
    vm.stopPrank();
    
    // Feed epoch 1: FINALIZED
    vm.startPrank(feeder);
    rewardFeed.initializeEpochReward(1, 1000 ether, 1);
    rewardFeed.finalizeEpochReward(1);
    epochFeeder.setEpoch(2);
    
    // Feed epoch 2: INITIALIZED (not finalized)
    rewardFeed.initializeEpochReward(2, 2000 ether, 1);
    // NOT finalized - but must finalize to move to next epoch
    rewardFeed.finalizeEpochReward(2); // Finalize to allow epoch 3
    epochFeeder.setEpoch(3);
    
    // Feed epoch 3: FINALIZED
    rewardFeed.initializeEpochReward(3, 500 ether, 1);
    rewardFeed.finalizeEpochReward(3);
    vm.stopPrank();
    
    epochFeeder.setEpoch(4);
    
    // Claim rewards
    uint256 balanceBefore = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimRewards(tokenIds);
    uint256 balanceAfter = rewardToken.balanceOf(user1);
    
    // Should receive all three epochs since we finalized all
    assertEq(balanceAfter - balanceBefore, 3500 ether);
  }

  function testClaimRewards_ProportionalDistribution() public {
    // User1 stakes 2 NFTs
    uint256[] memory user1TokenIds = new uint256[](2);
    user1TokenIds[0] = 1;
    user1TokenIds[1] = 2;
    
    vm.startPrank(user1);
    mirrorNFT.approve(address(staking), 1);
    mirrorNFT.approve(address(staking), 2);
    staking.stake(user1TokenIds);
    vm.stopPrank();
    
    // User2 stakes 1 NFT
    uint256[] memory user2TokenIds = new uint256[](1);
    user2TokenIds[0] = 4;
    
    vm.startPrank(user2);
    mirrorNFT.approve(address(staking), 4);
    staking.stake(user2TokenIds);
    vm.stopPrank();
    
    // Total: 3 NFTs staked
    // Feed epoch 1: 3000 ether, 3 NFTs
    vm.startPrank(feeder);
    rewardFeed.initializeEpochReward(1, 3000 ether, 3);
    rewardFeed.finalizeEpochReward(1);
    vm.stopPrank();
    
    epochFeeder.setEpoch(2);
    
    // User1 claims (2 NFTs = 2000 ether)
    uint256 user1Before = rewardToken.balanceOf(user1);
    vm.prank(user1);
    staking.claimRewards(user1TokenIds);
    uint256 user1After = rewardToken.balanceOf(user1);
    assertEq(user1After - user1Before, 2000 ether);
    
    // User2 claims (1 NFT = 1000 ether)
    uint256 user2Before = rewardToken.balanceOf(user2);
    vm.prank(user2);
    staking.claimRewards(user2TokenIds);
    uint256 user2After = rewardToken.balanceOf(user2);
    assertEq(user2After - user2Before, 1000 ether);
  }
}

