// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { ERC20 } from '@oz/token/ERC20/ERC20.sol';

import { xMorseRewardDistributor } from '../src/xMorseRewardDistributor.sol';
import { IxMorseRewardDistributor } from '../src/interfaces/IxMorseRewardDistributor.sol';
import { xMorseContributionFeed } from '../src/xMorseContributionFeed.sol';
import { IxMorseContributionFeed } from '../src/interfaces/IxMorseContributionFeed.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';
import { IxMorseStakingV2 } from '../src/interfaces/IxMorseStakingV2.sol';

contract MockEpochFeeder is IEpochFeeder {
  uint256 private _epoch = 10;

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

contract MockRewardToken is ERC20 {
  constructor() ERC20('gMITO', 'gMITO') {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract MockStaking is IxMorseStakingV2 {
  function xMorseToken() external pure returns (address) { return address(0); }
  function mirrorNFT() external pure returns (address) { return address(0); }
  function rewardToken() external pure returns (address) { return address(0); }
  function lockupPeriod() external pure returns (uint256) { return 0; }
  function stakerTotal(address, uint48) external pure returns (uint256) { return 0; }
  function stakerTotalTWAB(address, uint48) external pure returns (uint256) { return 0; }
  function totalStaked(uint48) external pure returns (uint256) { return 0; }
  function totalStakedTWAB(uint48) external pure returns (uint256) { return 0; }
  function getNFTInfo(uint256) external pure returns (NFTInfo memory) {
    return NFTInfo(address(0), 0, 0, false, 0);
  }
  function getStakedNFTs(address) external pure returns (uint256[] memory) {
    return new uint256[](0);
  }
  function getUnstakingNFTs(address) external pure returns (uint256[] memory) {
    return new uint256[](0);
  }
  function isNFTUnstaking(uint256) external pure returns (bool) { return false; }
  function stake(uint256[] calldata) external pure {}
  function initiateUnstake(uint256[] calldata) external pure {}
  function completeUnstake(uint256[] calldata) external pure {}
  function unstake(uint256[] calldata) external pure {}
  function setLockupPeriod(uint256) external pure {}
  function pause() external pure {}
  function unpause() external pure {}
}

contract xMorseRewardDistributorTest is Test {
  xMorseRewardDistributor public distributor;
  xMorseContributionFeed public feed;
  MockEpochFeeder public epochFeeder;
  MockRewardToken public rewardToken;
  MockStaking public staking;
  
  address public owner;
  address public feeder;
  address public user1;
  address public user2;
  address public treasury;

  function setUp() public {
    owner = makeAddr('owner');
    feeder = makeAddr('feeder');
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');
    treasury = makeAddr('treasury');

    epochFeeder = new MockEpochFeeder();
    rewardToken = new MockRewardToken();
    staking = new MockStaking();

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
  }

  function test_InitialState() public view {
    assertEq(address(distributor.epochFeeder()), address(epochFeeder));
    assertEq(address(distributor.contributionFeed()), address(feed));
    assertEq(address(distributor.staking()), address(staking));
    assertEq(distributor.rewardToken(), address(rewardToken));
    assertEq(distributor.treasuryAddress(), treasury);
    assertEq(distributor.MAX_WALLET_CAP_BPS(), 1000);
  }

  function test_SetTreasuryAddress() public {
    address newTreasury = makeAddr('newTreasury');
    
    vm.expectEmit(true, true, false, false);
    emit IxMorseRewardDistributor.TreasuryAddressUpdated(treasury, newTreasury);
    
    vm.prank(owner);
    distributor.setTreasuryAddress(newTreasury);
    
    assertEq(distributor.treasuryAddress(), newTreasury);
  }

  function test_WeightBasedCalculation() public {
    // Setup epoch 1 with weights
    _setupEpoch1WithWeights();

    // Set epoch reward
    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    // Advance epoch so we can claim
    epochFeeder.setEpoch(2);

    // User1 has 50 weight out of 1000 total = 5% of rewards = 50 ether
    (uint256 claimable1,) = distributor.claimableRewards(user1);
    assertEq(claimable1, 50 ether);

    // User2 has 50 weight = 5% = 50 ether
    (uint256 claimable2,) = distributor.claimableRewards(user2);
    assertEq(claimable2, 50 ether);

    // Treasury has 900 weight out of 1000 total = 90% of rewards = 900 ether (exempt from cap)
    (uint256 claimableTreasury,) = distributor.claimableRewards(treasury);
    assertEq(claimableTreasury, 900 ether);
  }

  function test_TenPercentCapEnforcement() public {
    // Setup epoch where user1 would get more than 10%
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](2);
    // User1 gets 15% weight (should be capped at 10%)
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 150});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: user2, weight: 850});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    // Set epoch reward
    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    epochFeeder.setEpoch(2);

    // User1 should fail to claim because they exceed 10% cap
    vm.prank(user1);
    vm.expectRevert("Exceeds 10% wallet cap");
    distributor.claimRewards(user1);
  }

  function test_TreasuryExemptFromCap() public {
    // Setup epoch where treasury gets 30% (should not be capped)
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 370,  // 70 + 300
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](2);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 70}); // 7% - under cap
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 300}); // 30% > 10% but exempt

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    epochFeeder.setEpoch(2);

    // Treasury should successfully claim ~81% (300/370)
    vm.prank(treasury);
    uint256 claimed = distributor.claimRewards(treasury);
    // 300/370 * 1000 ether = ~810.81 ether
    assertApproxEqAbs(claimed, 810 ether, 1 ether);
    assertApproxEqAbs(rewardToken.balanceOf(treasury), 810 ether, 1 ether);
  }

  function test_ClaimRewards() public {
    _setupEpoch1WithWeights();

    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    epochFeeder.setEpoch(2);

    // User1 claims
    vm.prank(user1);
    uint256 claimed = distributor.claimRewards(user1);
    
    assertEq(claimed, 50 ether);
    assertEq(rewardToken.balanceOf(user1), 50 ether);
    assertEq(distributor.lastClaimedEpoch(user1), 1);
  }

  function test_BatchClaimRewards() public {
    _setupEpoch1WithWeights();

    uint256 totalReward = 1000 ether;
    rewardToken.mint(address(distributor), totalReward);
    
    vm.prank(owner);
    distributor.setEpochReward(1, totalReward);

    epochFeeder.setEpoch(2);

    // Set approval for owner to claim on behalf of all users
    vm.prank(user1);
    distributor.setClaimApprovalStatus(owner, true);
    vm.prank(user2);
    distributor.setClaimApprovalStatus(owner, true);
    vm.prank(treasury);
    distributor.setClaimApprovalStatus(owner, true);

    // Batch claim for all stakers
    address[] memory stakers = new address[](3);
    stakers[0] = user1;
    stakers[1] = user2;
    stakers[2] = treasury;

    vm.prank(owner);
    uint256 totalClaimed = distributor.batchClaimRewards(stakers);
    
    assertEq(totalClaimed, 1000 ether);
    // When owner claims on behalf of users, tokens go to owner (the recipient/claimer)
    assertEq(rewardToken.balanceOf(owner), 1000 ether);
  }

  // Helper function
  function _setupEpoch1WithWeights() internal {
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 3
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    // User1: 5%, User2: 5%, Treasury: 90%
    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](3);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 50});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: user2, weight: 50});
    weights[2] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 900});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();
  }
}

