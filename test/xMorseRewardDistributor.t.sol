// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@oz/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@oz/token/ERC20/IERC20.sol";

import { xMorseRewardDistributor } from "../src/xMorseRewardDistributor.sol";
import { IxMorseRewardDistributor } from "../src/interfaces/IxMorseRewardDistributor.sol";
import { IxMorseContributionFeed } from "../src/interfaces/IxMorseContributionFeed.sol";
import { IxMorseStakingV2 } from "../src/interfaces/IxMorseStakingV2.sol";
import { IEpochFeeder } from "@mitosis/interfaces/hub/validator/IEpochFeeder.sol";

/// @title xMorseRewardDistributorTest
/// @notice Test suite for xMorseRewardDistributor contract
contract xMorseRewardDistributorTest is Test {
  xMorseRewardDistributor public distributor;
  
  address public owner = address(0x1);
  address public user1 = address(0x2);
  address public user2 = address(0x3);
  
  address public mockEpochFeeder = address(0x100);
  address public mockContributionFeed = address(0x101);
  address public mockStaking = address(0x102);
  address public mockRewardToken = address(0x103);

  function setUp() public {
    // Deploy implementation
    xMorseRewardDistributor impl = new xMorseRewardDistributor(
      mockEpochFeeder,
      mockContributionFeed,
      mockStaking,
      mockRewardToken
    );
    
    // Deploy proxy
    bytes memory initData = abi.encodeWithSelector(
      xMorseRewardDistributor.initialize.selector,
      owner,
      uint32(50),   // maxClaimEpochs
      uint32(100)   // maxStakerBatchSize
    );
    
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    distributor = xMorseRewardDistributor(address(proxy));
  }

  function test_Initialize() public view {
    assertEq(distributor.owner(), owner);
    
    IxMorseRewardDistributor.ClaimConfigResponse memory config = distributor.claimConfig();
    assertEq(config.maxClaimEpochs, 50);
    assertEq(config.maxStakerBatchSize, 100);
    assertEq(config.version, 1);
  }

  function test_ImmutableAddresses() public view {
    assertEq(address(distributor.epochFeeder()), mockEpochFeeder);
    assertEq(address(distributor.contributionFeed()), mockContributionFeed);
    assertEq(address(distributor.staking()), mockStaking);
    assertEq(distributor.rewardToken(), mockRewardToken);
  }

  function test_ClaimApproval() public {
    address claimer = address(0x999);
    
    // User1 approves claimer
    vm.prank(user1);
    distributor.setClaimApprovalStatus(claimer, true);
    
    // Verify
    assertTrue(distributor.claimAllowed(user1, claimer));
    assertFalse(distributor.claimAllowed(user2, claimer));
    
    // Self is always allowed
    assertTrue(distributor.claimAllowed(user1, user1));
  }

  function test_ClaimRewards_NoEpochs() public {
    // Mock empty epoch feeder
    vm.mockCall(
      mockEpochFeeder,
      abi.encodeWithSignature("epoch()"),
      abi.encode(1)
    );

    // No epochs to claim
    vm.prank(user1);
    uint256 claimed = distributor.claimRewards(user1);
    
    assertEq(claimed, 0);
    assertEq(distributor.lastClaimedEpoch(user1), 0);
  }

  function testSkip_ClaimableRewards() public {
    // Mock current epoch
    vm.mockCall(
      mockEpochFeeder,
      abi.encodeWithSignature("epoch()"),
      abi.encode(3)
    );

    // Mock available epochs
    vm.mockCall(
      mockContributionFeed,
      abi.encodeWithSelector(IxMorseContributionFeed.available.selector, 1),
      abi.encode(true)
    );
    vm.mockCall(
      mockContributionFeed,
      abi.encodeWithSelector(IxMorseContributionFeed.available.selector, 2),
      abi.encode(true)
    );

    // Mock weights
    IxMorseContributionFeed.StakerWeight memory weight = IxMorseContributionFeed.StakerWeight({
      addr: user1,
      weight: 100,
      rewardShare: 100
    });

    vm.mockCall(
      mockContributionFeed,
      abi.encodeWithSelector(IxMorseContributionFeed.weightOf.selector, 1, user1),
      abi.encode(weight, true)
    );

    vm.mockCall(
      mockContributionFeed,
      abi.encodeWithSelector(IxMorseContributionFeed.weightOf.selector, 2, user1),
      abi.encode(weight, true)
    );

    // Mock summary
    IxMorseContributionFeed.Summary memory summary = IxMorseContributionFeed.Summary({
      totalWeight: 100,
      numOfStakers: 1
    });

    vm.mockCall(
      mockContributionFeed,
      abi.encodeWithSelector(IxMorseContributionFeed.summary.selector, 1),
      abi.encode(summary)
    );

    vm.mockCall(
      mockContributionFeed,
      abi.encodeWithSelector(IxMorseContributionFeed.summary.selector, 2),
      abi.encode(summary)
    );

    // Mock reward token balance
    vm.mockCall(
      mockRewardToken,
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(distributor)),
      abi.encode(1000e18)
    );

    // Check claimable
    (uint256 claimable, uint256 nextEpoch) = distributor.claimableRewards(user1);
    
    assertTrue(claimable > 0, "Should have claimable rewards");
    assertEq(nextEpoch, 3, "Next epoch should be 3");
  }

  function test_SetClaimConfig() public {
    vm.prank(owner);
    distributor.setClaimConfig(100, 200);
    
    IxMorseRewardDistributor.ClaimConfigResponse memory config = distributor.claimConfig();
    assertEq(config.maxClaimEpochs, 100);
    assertEq(config.maxStakerBatchSize, 200);
  }

  function test_RevertIf_NotOwner() public {
    vm.prank(address(0x999));
    vm.expectRevert();
    distributor.setClaimConfig(100, 200);
  }
}

