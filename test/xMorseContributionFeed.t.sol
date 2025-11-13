// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@oz/proxy/ERC1967/ERC1967Proxy.sol";

import { xMorseContributionFeed } from "../src/xMorseContributionFeed.sol";
import { IxMorseContributionFeed } from "../src/interfaces/IxMorseContributionFeed.sol";
import { IEpochFeeder } from "@mitosis/interfaces/hub/validator/IEpochFeeder.sol";

/// @title xMorseContributionFeedTest
/// @notice Test suite for xMorseContributionFeed contract
contract xMorseContributionFeedTest is Test {
  xMorseContributionFeed public feed;
  
  address public owner = address(0x1);
  address public feeder = address(0x2);
  address public mockEpochFeeder = address(0x100);

  bytes32 public FEEDER_ROLE;

  function setUp() public {
    // Mock epoch feeder
    vm.mockCall(
      mockEpochFeeder,
      abi.encodeWithSignature("epoch()"),
      abi.encode(2) // Current epoch is 2
    );

    // Deploy implementation
    xMorseContributionFeed impl = new xMorseContributionFeed(IEpochFeeder(mockEpochFeeder));
    
    // Deploy proxy
    bytes memory initData = abi.encodeWithSelector(
      xMorseContributionFeed.initialize.selector,
      owner
    );
    
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    feed = xMorseContributionFeed(address(proxy));

    FEEDER_ROLE = feed.FEEDER_ROLE();

    // Grant FEEDER_ROLE to feeder
    vm.prank(owner);
    feed.grantRole(FEEDER_ROLE, feeder);
  }

  function test_Initialize() public view {
    assertEq(feed.nextEpoch(), 1);
    assertTrue(feed.hasRole(FEEDER_ROLE, feeder));
  }

  function test_InitializeReport() public {
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    assertEq(feed.nextEpoch(), 1, "NextEpoch should still be 1");
  }

  function test_PushStakerWeights() public {
    // Initialize report first
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    // Push weights
    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](2);
    weights[0] = IxMorseContributionFeed.StakerWeight({
      addr: address(0x1),
      weight: 600,
      rewardShare: 600
    });
    weights[1] = IxMorseContributionFeed.StakerWeight({
      addr: address(0x2),
      weight: 400,
      rewardShare: 400
    });

    vm.prank(feeder);
    feed.pushStakerWeights(weights);
  }

  function test_FinalizeReport() public {
    // Initialize
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    // Push weights
    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](2);
    weights[0] = IxMorseContributionFeed.StakerWeight({
      addr: address(0x1),
      weight: 600,
      rewardShare: 600
    });
    weights[1] = IxMorseContributionFeed.StakerWeight({
      addr: address(0x2),
      weight: 400,
      rewardShare: 400
    });

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    // Finalize
    vm.prank(feeder);
    feed.finalizeReport();

    // Verify
    assertTrue(feed.available(1), "Epoch 1 should be available");
    assertEq(feed.nextEpoch(), 2, "NextEpoch should advance to 2");

    // Check summary
    IxMorseContributionFeed.Summary memory summary = feed.summary(1);
    assertEq(summary.totalWeight, 1000);
    assertEq(summary.numOfStakers, 2);
  }

  function test_WeightOf() public {
    // Initialize and push
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 1
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](1);
    weights[0] = IxMorseContributionFeed.StakerWeight({
      addr: address(0x123),
      weight: 1000,
      rewardShare: 1000
    });

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    // Check weight
    (IxMorseContributionFeed.StakerWeight memory weight, bool exists) = feed.weightOf(1, address(0x123));
    assertTrue(exists);
    assertEq(weight.addr, address(0x123));
    assertEq(weight.weight, 1000);
    assertEq(weight.rewardShare, 1000);

    // Check non-existent
    (IxMorseContributionFeed.StakerWeight memory weight2, bool exists2) = feed.weightOf(1, address(0x456));
    assertFalse(exists2);
  }

  function test_RevokeReport() public {
    // Initialize
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 1
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    // Push small weights
    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](1);
    weights[0] = IxMorseContributionFeed.StakerWeight({
      addr: address(0x1),
      weight: 1000,
      rewardShare: 1000
    });

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    // Revoke
    vm.prank(feeder);
    feed.revokeReport();

    // Verify
    assertFalse(feed.available(1), "Epoch 1 should not be available");
    assertEq(feed.nextEpoch(), 1, "NextEpoch should still be 1");
  }

  function test_RevertIf_NotFeeder() public {
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 1
    });

    // Try as non-feeder (should fail)
    vm.prank(address(0x999));
    vm.expectRevert();
    feed.initializeReport(request);
  }

  function test_RevertIf_InvalidTotalWeight() public {
    // Initialize
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 1
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    // Push wrong total weight
    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](1);
    weights[0] = IxMorseContributionFeed.StakerWeight({
      addr: address(0x1),
      weight: 500, // Wrong! Should be 1000
      rewardShare: 500
    });

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    // Try to finalize (should fail)
    vm.prank(feeder);
    vm.expectRevert(IxMorseContributionFeed.IxMorseContributionFeed__InvalidTotalWeight.selector);
    feed.finalizeReport();
  }
}

