// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { xMorseContributionFeed } from '../src/xMorseContributionFeed.sol';
import { IxMorseContributionFeed } from '../src/interfaces/IxMorseContributionFeed.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

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

contract xMorseContributionFeedTest is Test {
  xMorseContributionFeed public feed;
  MockEpochFeeder public epochFeeder;
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

    // Deploy implementation
    xMorseContributionFeed implementation = new xMorseContributionFeed(epochFeeder);

    // Deploy proxy
    vm.startPrank(owner);
    bytes memory initData = abi.encodeWithSelector(
      xMorseContributionFeed.initialize.selector,
      owner
    );
    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
    feed = xMorseContributionFeed(address(proxy));

    // Grant feeder role
    feed.grantRole(feed.FEEDER_ROLE(), feeder);
    vm.stopPrank();
  }

  function test_InitialState() public view {
    assertEq(address(feed.epochFeeder()), address(epochFeeder));
    assertEq(feed.nextEpoch(), 1);
  }

  function test_InitializeReport() public {
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    assertEq(feed.nextEpoch(), 1);
  }

  function test_PushWeights() public {
    // Initialize report
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1300,
      numOfStakers: 3
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    // Push weights (no rewardShare field, only weight)
    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](3);
    weights[0] = IxMorseContributionFeed.StakerWeight({
      addr: user1,
      weight: 300
    });
    weights[1] = IxMorseContributionFeed.StakerWeight({
      addr: user2,
      weight: 600
    });
    weights[2] = IxMorseContributionFeed.StakerWeight({
      addr: treasury,
      weight: 400  // 30% for treasury
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
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 700});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 300});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    // Finalize
    vm.prank(feeder);
    feed.finalizeReport();

    // Verify
    assertEq(feed.nextEpoch(), 2);
    assertTrue(feed.available(1));

    IxMorseContributionFeed.Summary memory summary = feed.summary(1);
    assertEq(summary.totalWeight, 1000);
    assertEq(summary.numOfStakers, 2);
  }

  function test_WeightOf() public {
    // Setup complete report
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](2);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 700});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 300});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    // Check weightOf
    (IxMorseContributionFeed.StakerWeight memory weight, bool exists) = feed.weightOf(1, user1);
    assertTrue(exists);
    assertEq(weight.addr, user1);
    assertEq(weight.weight, 700);

    (IxMorseContributionFeed.StakerWeight memory treasuryWeight, bool treasuryExists) = feed.weightOf(1, treasury);
    assertTrue(treasuryExists);
    assertEq(treasuryWeight.weight, 300);
  }

  function test_RevokeReport() public {
    // Initialize
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: 1000,
      numOfStakers: 2
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    // Push weights
    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](2);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: 700});
    weights[1] = IxMorseContributionFeed.StakerWeight({addr: treasury, weight: 300});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    // Revoke
    vm.prank(feeder);
    feed.revokeReport();

    // Should be able to initialize again
    vm.prank(feeder);
    feed.initializeReport(request);
  }

  function test_Uint256WeightPrecision() public {
    // Test that we can handle large uint256 weights
    uint256 largeWeight = type(uint256).max / 2;
    
    IxMorseContributionFeed.InitReportRequest memory request = IxMorseContributionFeed.InitReportRequest({
      totalWeight: largeWeight,
      numOfStakers: 1
    });

    vm.prank(feeder);
    feed.initializeReport(request);

    IxMorseContributionFeed.StakerWeight[] memory weights = new IxMorseContributionFeed.StakerWeight[](1);
    weights[0] = IxMorseContributionFeed.StakerWeight({addr: user1, weight: largeWeight});

    vm.prank(feeder);
    feed.pushStakerWeights(weights);

    vm.prank(feeder);
    feed.finalizeReport();

    (IxMorseContributionFeed.StakerWeight memory weight, bool exists) = feed.weightOf(1, user1);
    assertTrue(exists);
    assertEq(weight.weight, largeWeight);
  }
}

