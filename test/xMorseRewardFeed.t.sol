// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { xMorseRewardFeed } from '../src/xMorseRewardFeed.sol';
import { IxMorseRewardFeed } from '../src/interfaces/IxMorseRewardFeed.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

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

contract xMorseRewardFeedTest is Test {
  xMorseRewardFeed public feed;
  MockEpochFeeder public epochFeeder;
  
  address public owner;
  address public feeder;
  address public attacker;
  
  function setUp() public {
    owner = makeAddr('owner');
    feeder = makeAddr('feeder');
    attacker = makeAddr('attacker');
    
    // Deploy mock epoch feeder
    epochFeeder = new MockEpochFeeder();
    epochFeeder.setEpoch(1);
    
    // Deploy reward feed
    xMorseRewardFeed impl = new xMorseRewardFeed(IEpochFeeder(address(epochFeeder)));
    bytes memory initData = abi.encodeCall(xMorseRewardFeed.initialize, (owner, feeder));
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    feed = xMorseRewardFeed(address(proxy));
  }
  
  //====================================================================================//
  //================================== INITIALIZATION TESTS ============================//
  //====================================================================================//
  
  function testInitialization() public view {
    assertEq(feed.owner(), owner);
    assertEq(address(feed.epochFeeder()), address(epochFeeder));
    assertEq(feed.nextEpoch(), 1);
  }
  
  //====================================================================================//
  //================================== INITIALIZE EPOCH TESTS ==========================//
  //====================================================================================//
  
  function testInitializeEpochReward_Success() public {
    vm.prank(feeder);
    feed.initializeEpochReward(1, 1000 ether, 7);
    
    IxMorseRewardFeed.EpochReward memory reward = feed.rewardForEpoch(1);
    assertEq(reward.totalReward, 1000 ether);
    assertEq(reward.totalStakedNFTs, 7);
    assertEq(uint256(reward.status), uint256(IxMorseRewardFeed.ReportStatus.INITIALIZED));
  }
  
  function testInitializeEpochReward_RevertIfNotFeeder() public {
    vm.prank(attacker);
    vm.expectRevert();
    feed.initializeEpochReward(1, 1000 ether, 7);
  }
  
  function testInitializeEpochReward_RevertIfInvalidEpoch() public {
    vm.prank(feeder);
    vm.expectRevert(IxMorseRewardFeed.InvalidEpoch.selector);
    feed.initializeEpochReward(2, 1000 ether, 7); // nextEpoch is 1
  }
  
  function testInitializeEpochReward_RevertIfAlreadyInitialized() public {
    vm.startPrank(feeder);
    feed.initializeEpochReward(1, 1000 ether, 7);
    
    vm.expectRevert(IxMorseRewardFeed.InvalidReportStatus.selector);
    feed.initializeEpochReward(1, 2000 ether, 10);
    vm.stopPrank();
  }
  
  //====================================================================================//
  //================================== FINALIZE EPOCH TESTS ============================//
  //====================================================================================//
  
  function testFinalizeEpochReward_Success() public {
    vm.startPrank(feeder);
    feed.initializeEpochReward(1, 1000 ether, 7);
    feed.finalizeEpochReward(1);
    vm.stopPrank();
    
    assertTrue(feed.available(1));
    assertEq(feed.nextEpoch(), 2);
    
    IxMorseRewardFeed.EpochReward memory reward = feed.rewardForEpoch(1);
    assertEq(uint256(reward.status), uint256(IxMorseRewardFeed.ReportStatus.FINALIZED));
  }
  
  function testFinalizeEpochReward_RevertIfNotInitialized() public {
    vm.prank(feeder);
    vm.expectRevert(IxMorseRewardFeed.InvalidReportStatus.selector);
    feed.finalizeEpochReward(1);
  }
  
  function testFinalizeEpochReward_RevertIfNotFeeder() public {
    vm.prank(feeder);
    feed.initializeEpochReward(1, 1000 ether, 7);
    
    vm.prank(attacker);
    vm.expectRevert();
    feed.finalizeEpochReward(1);
  }
  
  //====================================================================================//
  //================================== REVOKE EPOCH TESTS ==============================//
  //====================================================================================//
  
  function testRevokeEpochReward_Success() public {
    vm.startPrank(feeder);
    feed.initializeEpochReward(1, 1000 ether, 7);
    feed.revokeEpochReward(1);
    vm.stopPrank();
    
    IxMorseRewardFeed.EpochReward memory reward = feed.rewardForEpoch(1);
    assertEq(uint256(reward.status), uint256(IxMorseRewardFeed.ReportStatus.NONE));
    assertEq(reward.totalReward, 0);
    assertEq(reward.totalStakedNFTs, 0);
  }
  
  function testRevokeEpochReward_RevertIfFinalized() public {
    vm.startPrank(feeder);
    feed.initializeEpochReward(1, 1000 ether, 7);
    feed.finalizeEpochReward(1);
    
    vm.expectRevert(IxMorseRewardFeed.InvalidReportStatus.selector);
    feed.revokeEpochReward(1);
    vm.stopPrank();
  }
  
  //====================================================================================//
  //================================== FULL WORKFLOW TESTS =============================//
  //====================================================================================//
  
  function testFullWorkflow_MultipleEpochs() public {
    vm.startPrank(feeder);
    
    // Epoch 1
    feed.initializeEpochReward(1, 1000 ether, 5);
    feed.finalizeEpochReward(1);
    assertEq(feed.nextEpoch(), 2);
    
    // Epoch 2
    feed.initializeEpochReward(2, 2000 ether, 7);
    feed.finalizeEpochReward(2);
    assertEq(feed.nextEpoch(), 3);
    
    // Epoch 3
    feed.initializeEpochReward(3, 500 ether, 10);
    feed.finalizeEpochReward(3);
    assertEq(feed.nextEpoch(), 4);
    
    vm.stopPrank();
    
    // Verify all epochs are available
    assertTrue(feed.available(1));
    assertTrue(feed.available(2));
    assertTrue(feed.available(3));
    assertFalse(feed.available(4));
    
    // Verify data
    IxMorseRewardFeed.EpochReward memory epoch1 = feed.rewardForEpoch(1);
    assertEq(epoch1.totalReward, 1000 ether);
    assertEq(epoch1.totalStakedNFTs, 5);
    
    IxMorseRewardFeed.EpochReward memory epoch2 = feed.rewardForEpoch(2);
    assertEq(epoch2.totalReward, 2000 ether);
    assertEq(epoch2.totalStakedNFTs, 7);
  }
  
  function testAvailable_OnlyFinalizedEpochs() public {
    vm.startPrank(feeder);
    feed.initializeEpochReward(1, 1000 ether, 7);
    vm.stopPrank();
    
    assertFalse(feed.available(1)); // Only initialized, not finalized
    
    vm.prank(feeder);
    feed.finalizeEpochReward(1);
    
    assertTrue(feed.available(1)); // Now finalized
  }
}

