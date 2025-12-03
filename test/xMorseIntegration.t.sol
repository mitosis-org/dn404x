// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { ERC721 } from '@oz/token/ERC721/ERC721.sol';
import { ERC20 } from '@oz/token/ERC20/ERC20.sol';

import { xMorseStakingV2 } from '../src/xMorseStakingV2.sol';
import { xMorseContributionFeed } from '../src/xMorseContributionFeed.sol';
import { xMorseRewardDistributor } from '../src/xMorseRewardDistributor.sol';
import { IxMorseContributionFeed } from '../src/interfaces/IxMorseContributionFeed.sol';
import { IxMorseRewardDistributor } from '../src/interfaces/IxMorseRewardDistributor.sol';
import { IxMorseStakingV2 } from '../src/interfaces/IxMorseStakingV2.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

contract MockEpochFeeder is IEpochFeeder {
  uint256 private _epoch = 1;

  function epoch() external view returns (uint256) {
    return _epoch;
  }

  function setEpoch(uint256 _newEpoch) external {
    _epoch = _newEpoch;
  }

  function epochAt(uint48) external view returns (uint256) {
    return _epoch;
  }

  function time() external view returns (uint48) {
    return uint48(block.timestamp);
  }

  function timeAt(uint256) external pure returns (uint48) {
    return 0;
  }

  function interval() external pure returns (uint48) {
    return 7 days;
  }

  function intervalAt(uint256) external pure returns (uint48) {
    return 7 days;
  }

  function setNextInterval(uint48) external pure {}
}

contract MockERC721 is ERC721 {
  constructor() ERC721('MockNFT', 'MNFT') {}

  function mint(address to, uint256 tokenId) external {
    _mint(to, tokenId);
  }
}

contract MockDN404 is ERC20 {
  constructor() ERC20('xMorse', 'xMORSE') {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function setSkipNFT(bool) external {
    // Mock implementation
  }
}

contract MockERC20 is ERC20 {
  constructor() ERC20('Token', 'TKN') {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

/// @title xMorseIntegration
/// @notice Full end-to-end integration test for weight-based distribution
contract xMorseIntegrationTest is Test {
  xMorseStakingV2 public staking;
  xMorseContributionFeed public feed;
  xMorseRewardDistributor public distributor;
  MockEpochFeeder public epochFeeder;
  MockERC721 public nft;
  MockDN404 public xMorseToken;
  MockERC20 public rewardToken;

  address public owner;
  address public feeder;
  address public user1;
  address public user2;
  address public user3;
  address public treasury;

  function setUp() public {
    owner = makeAddr('owner');
    feeder = makeAddr('feeder');
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');
    user3 = makeAddr('user3');
    treasury = makeAddr('treasury');

    // Deploy mock dependencies
    epochFeeder = new MockEpochFeeder();
    xMorseToken = new MockDN404();
    nft = new MockERC721();
    rewardToken = new MockERC20();

    // Deploy staking contract
    xMorseStakingV2 stakingImpl = new xMorseStakingV2();
    vm.startPrank(owner);
    bytes memory stakingInitData = abi.encodeWithSelector(
      xMorseStakingV2.initialize.selector,
      address(xMorseToken),
      address(nft),
      address(rewardToken),
      owner
    );
    ERC1967Proxy stakingProxy = new ERC1967Proxy(address(stakingImpl), stakingInitData);
    staking = xMorseStakingV2(address(stakingProxy));
    vm.stopPrank();

    // Deploy contribution feed
    xMorseContributionFeed feedImpl = new xMorseContributionFeed(epochFeeder);
    vm.startPrank(owner);
    bytes memory feedInitData = abi.encodeWithSelector(
      xMorseContributionFeed.initialize.selector,
      owner
    );
    ERC1967Proxy feedProxy = new ERC1967Proxy(address(feedImpl), feedInitData);
    feed = xMorseContributionFeed(address(feedProxy));

    feed.grantRole(feed.FEEDER_ROLE(), feeder);
    vm.stopPrank();

    // Deploy reward distributor
    xMorseRewardDistributor distImpl = new xMorseRewardDistributor(
      address(epochFeeder),
      address(feed),
      address(staking),
      address(rewardToken)
    );
    bytes memory distInitData = abi.encodeWithSelector(
      xMorseRewardDistributor.initialize.selector,
      owner,
      uint32(100),  // maxClaimEpochs
      uint32(50),   // maxStakerBatchSize
      treasury      // treasury address
    );
    ERC1967Proxy distProxy = new ERC1967Proxy(address(distImpl), distInitData);
    distributor = xMorseRewardDistributor(address(distProxy));

    // Mint NFTs to users
    for (uint256 i = 1; i <= 10; i++) {
      if (i <= 4) nft.mint(user1, i);
      else if (i <= 7) nft.mint(user2, i);
      else nft.mint(user3, i);
    }
  }

  /// @notice Test full workflow: stake → feed weights → claim rewards
  function test_FullWorkflow_70_30_Split() public {
    // Step 1: Users stake NFTs
    _stakeNFTs();

    // Step 2: Advance epoch
    epochFeeder.setEpoch(2);

    // Step 3: Off-chain feeder calculates and feeds weights (70/30 split)
    _feedEpoch1Weights();

    // Step 4: Set epoch reward
    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    // Step 5: Users and treasury claim
    vm.prank(user1);
    uint256 user1Claimed = distributor.claimRewards(user1);
    
    vm.prank(user2);
    uint256 user2Claimed = distributor.claimRewards(user2);
    
    vm.prank(treasury);
    uint256 treasuryClaimed = distributor.claimRewards(treasury);

    // Verify 70/30 split
    // User1: 400 weight / 1000 total = 40%
    // User2: 300 weight / 1000 total = 30%
    // Treasury: 300 weight / 1000 total = 30%
    assertEq(user1Claimed, 400 ether);
    assertEq(user2Claimed, 300 ether);
    assertEq(treasuryClaimed, 300 ether);
    assertEq(user1Claimed + user2Claimed + treasuryClaimed, totalReward);
  }

  /// @notice Test that treasury can receive 30% without cap
  function test_Treasury_ExemptFrom10PercentCap() public {
    _stakeNFTs();
    epochFeeder.setEpoch(2);
    _feedEpoch1Weights();

    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    // Treasury claims 30% (exceeds 10% cap but should succeed)
    vm.prank(treasury);
    uint256 treasuryClaimed = distributor.claimRewards(treasury);
    
    assertEq(treasuryClaimed, 300 ether);
  }

  /// @notice Test that regular user exceeding 10% fails
  function test_RegularUser_10PercentCap_Enforced() public {
    _stakeNFTs();
    epochFeeder.setEpoch(2);

    // Feed weights where user1 gets 15% (should fail)
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 3
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](3);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 150}); // 15% - exceeds cap
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: user2, weight: 550});
    weights[2] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 300});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    // User1 should fail to claim
    vm.prank(user1);
    vm.expectRevert("Exceeds 10% wallet cap");
    distributor.claimRewards(user1);
  }

  /// @notice Test 2-phase unstaking excludes user from next epoch
  function test_Unstaking_ExcludesFromNextEpoch() public {
    // Epoch 1: All users stake
    _stakeNFTs();
    epochFeeder.setEpoch(2);
    _feedEpoch1Weights();

    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    // User1 initiates unstake during epoch 2
    uint256[] memory user1Tokens = new uint256[](4);
    for (uint256 i = 0; i < 4; i++) {
      user1Tokens[i] = i + 1;
    }

    vm.prank(user1);
    staking.initiateUnstake(user1Tokens);

    // TWAB should immediately reflect decrease
    uint48 now_ = uint48(block.timestamp);
    assertEq(staking.stakerTotal(user1, now_), 0);

    // Epoch 2: User1 should be excluded from weights
    epochFeeder.setEpoch(3);

    // Feed weights for epoch 2 (user1 excluded)
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 600,  // Only user2 (300) + treasury (300)
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](2);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user2, weight: 300});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 300});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    rewardToken.mint(address(distributor), totalReward);
    vm.prank(owner);
    distributor.setEpochReward(2, totalReward);

    // User2 claims epoch 2
    vm.prank(user2);
    uint256 user2Claimed = distributor.claimRewards(user2);
    
    // User2 should get 50% of epoch 2 (300/600)
    assertEq(user2Claimed, 500 ether);

    // User1 can claim epoch 1 but not epoch 2
    vm.prank(user1);
    uint256 user1TotalClaimed = distributor.claimRewards(user1);
    assertEq(user1TotalClaimed, 400 ether); // Only epoch 1
  }

  /// @notice Test complete unstake after lockup period
  function test_CompleteUnstake_AfterLockup() public {
    _stakeNFTs();

    // User1 initiates unstake
    uint256[] memory user1Tokens = new uint256[](4);
    for (uint256 i = 0; i < 4; i++) {
      user1Tokens[i] = i + 1;
    }

    vm.prank(user1);
    staking.initiateUnstake(user1Tokens);

    // Wait for lockup period
    vm.warp(block.timestamp + 21 days);

    // Complete unstake
    vm.prank(user1);
    staking.completeUnstake(user1Tokens);

    // Verify NFTs returned
    for (uint256 i = 1; i <= 4; i++) {
      assertEq(nft.ownerOf(i), user1);
    }
  }

  /// @notice Test treasury address update
  function test_TreasuryAddressUpdate() public {
    address newTreasury = makeAddr('newTreasury');

    vm.prank(owner);
    distributor.setTreasuryAddress(newTreasury);

    assertEq(distributor.treasuryAddress(), newTreasury);

    // Setup epoch with new treasury
    _stakeNFTs();
    epochFeeder.setEpoch(2);

    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 3
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](3);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 400});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: user2, weight: 300});
    weights[2] = IxMorseContributionFeed.StakerWeight({addr: newTreasury, weight: 300}); // New treasury

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    // New treasury claims (should be exempt from cap)
    vm.prank(newTreasury);
    uint256 claimed = distributor.claimRewards(newTreasury);
    assertEq(claimed, 300 ether);
  }

  // Helper functions
  function _stakeNFTs() internal {
    // User1 stakes tokens 1-4
    uint256[] memory user1Tokens = new uint256[](4);
    for (uint256 i = 0; i < 4; i++) {
      user1Tokens[i] = i + 1;
    }

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(user1Tokens);
    vm.stopPrank();

    // User2 stakes tokens 5-7
    uint256[] memory user2Tokens = new uint256[](3);
    for (uint256 i = 0; i < 3; i++) {
      user2Tokens[i] = i + 5;
    }

    vm.startPrank(user2);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(user2Tokens);
    vm.stopPrank();
  }

  function _feedEpoch1Weights() internal {
    // Total: 1000 weight
    // User1: 400 (40%)
    // User2: 300 (30%)
    // Treasury: 300 (30%)
    
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 3
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](3);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 400});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: user2, weight: 300});
    weights[2] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 300});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();
  }
}

