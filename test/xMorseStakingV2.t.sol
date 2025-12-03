// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { ERC721 } from '@oz/token/ERC721/ERC721.sol';
import { ERC20 } from '@oz/token/ERC20/ERC20.sol';

import { xMorseStakingV2 } from '../src/xMorseStakingV2.sol';
import { IxMorseStakingV2 } from '../src/interfaces/IxMorseStakingV2.sol';

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
    // Mock implementation - does nothing
  }
}

contract MockERC20 is ERC20 {
  constructor() ERC20('gMITO', 'gMITO') {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

contract xMorseStakingV2Test is Test {
  xMorseStakingV2 public staking;
  MockERC721 public nft;
  MockDN404 public xMorseToken;
  MockERC20 public rewardToken;
  
  address public owner;
  address public user1;
  address public user2;

  uint256 constant LOCKUP_PERIOD = 21 days;

  function setUp() public {
    owner = makeAddr('owner');
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');

    // Deploy mock tokens
    xMorseToken = new MockDN404();
    nft = new MockERC721();
    rewardToken = new MockERC20();

    // Deploy staking contract
    xMorseStakingV2 impl = new xMorseStakingV2();
    
    vm.startPrank(owner);
    bytes memory initData = abi.encodeWithSelector(
      xMorseStakingV2.initialize.selector,
      address(xMorseToken),
      address(nft),
      address(rewardToken),
      owner
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    staking = xMorseStakingV2(address(proxy));
    vm.stopPrank();

    // Mint NFTs to users
    nft.mint(user1, 1);
    nft.mint(user1, 2);
    nft.mint(user2, 3);
  }

  function test_InitialState() public view {
    assertEq(staking.xMorseToken(), address(xMorseToken));
    assertEq(staking.mirrorNFT(), address(nft));
    assertEq(staking.rewardToken(), address(rewardToken));
    assertEq(staking.lockupPeriod(), LOCKUP_PERIOD);
  }

  function test_Stake() public {
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Verify NFTs are staked
    IxMorseStakingV2.NFTInfo memory info1 = staking.getNFTInfo(1);
    assertEq(info1.owner, user1);
    assertEq(info1.isUnstaking, false);
    assertEq(info1.lockupEndTime, block.timestamp + LOCKUP_PERIOD);

    // Verify TWAB updated
    uint48 now_ = uint48(block.timestamp);
    assertEq(staking.stakerTotal(user1, now_), 2);
    assertEq(staking.totalStaked(now_), 2);
  }

  function test_InitiateUnstake() public {
    // Stake first
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(tokenIds);

    // Advance time
    vm.warp(block.timestamp + 1 days);

    // Initiate unstake
    staking.initiateUnstake(tokenIds);
    vm.stopPrank();

    // Verify NFTs are marked as unstaking
    IxMorseStakingV2.NFTInfo memory info1 = staking.getNFTInfo(1);
    assertTrue(info1.isUnstaking);
    assertEq(info1.unstakeInitTime, block.timestamp);

    // Verify TWAB decreased immediately
    uint48 now_ = uint48(block.timestamp);
    assertEq(staking.stakerTotal(user1, now_), 0);
    assertEq(staking.totalStaked(now_), 0);

    // Verify getUnstakingNFTs
    uint256[] memory unstaking = staking.getUnstakingNFTs(user1);
    assertEq(unstaking.length, 2);
    assertEq(unstaking[0], 1);
    assertEq(unstaking[1], 2);

    // Verify isNFTUnstaking
    assertTrue(staking.isNFTUnstaking(1));
    assertTrue(staking.isNFTUnstaking(2));
  }

  function test_CompleteUnstake_BeforeLockup_Reverts() public {
    // Stake
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(tokenIds);

    // Initiate unstake
    staking.initiateUnstake(tokenIds);

    // Try to complete before lockup period
    vm.warp(block.timestamp + LOCKUP_PERIOD - 1);
    vm.expectRevert(abi.encodeWithSelector(IxMorseStakingV2.LockupPeriodNotEnded.selector, 1));
    staking.completeUnstake(tokenIds);
    vm.stopPrank();
  }

  function test_CompleteUnstake_Success() public {
    // Stake
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(tokenIds);

    // Initiate unstake
    staking.initiateUnstake(tokenIds);

    // Wait for lockup period
    vm.warp(block.timestamp + LOCKUP_PERIOD);

    // Complete unstake
    staking.completeUnstake(tokenIds);
    vm.stopPrank();

    // Verify NFT returned to user
    assertEq(nft.ownerOf(1), user1);

    // Verify NFT info deleted
    IxMorseStakingV2.NFTInfo memory info = staking.getNFTInfo(1);
    assertEq(info.owner, address(0));

    // Verify not in staked list
    uint256[] memory staked = staking.getStakedNFTs(user1);
    assertEq(staked.length, 0);
  }

  function test_CannotInitiateUnstakeTwice() public {
    // Stake
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(tokenIds);

    // First initiate unstake
    staking.initiateUnstake(tokenIds);

    // Try to initiate again
    vm.expectRevert(abi.encodeWithSelector(IxMorseStakingV2.AlreadyUnstaking.selector, 1));
    staking.initiateUnstake(tokenIds);
    vm.stopPrank();
  }

  function test_TwoPhaseUnstaking_MultipleUsers() public {
    // User1 stakes
    uint256[] memory user1Tokens = new uint256[](2);
    user1Tokens[0] = 1;
    user1Tokens[1] = 2;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(user1Tokens);
    vm.stopPrank();

    // User2 stakes
    uint256[] memory user2Tokens = new uint256[](1);
    user2Tokens[0] = 3;

    vm.startPrank(user2);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(user2Tokens);
    vm.stopPrank();

    // Verify total staked
    uint48 now1 = uint48(block.timestamp);
    assertEq(staking.totalStaked(now1), 3);

    // User1 initiates unstake
    vm.warp(block.timestamp + 1 days);
    vm.prank(user1);
    staking.initiateUnstake(user1Tokens);

    // Total should decrease immediately
    uint48 now2 = uint48(block.timestamp);
    assertEq(staking.totalStaked(now2), 1);  // Only user2's NFT
    assertEq(staking.stakerTotal(user1, now2), 0);
    assertEq(staking.stakerTotal(user2, now2), 1);

    // User1 completes unstake
    vm.warp(block.timestamp + LOCKUP_PERIOD);
    vm.prank(user1);
    staking.completeUnstake(user1Tokens);

    // Verify NFTs returned
    assertEq(nft.ownerOf(1), user1);
    assertEq(nft.ownerOf(2), user1);
    assertEq(nft.ownerOf(3), address(staking));  // Still staked by user2
  }

  function test_CleanNFTInfo_NoDeprecatedFields() public {
    // Stake NFT
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    staking.stake(tokenIds);
    vm.stopPrank();

    // Get NFT info
    IxMorseStakingV2.NFTInfo memory info = staking.getNFTInfo(1);
    
    // Verify clean structure (no deprecated fields)
    assertEq(info.owner, user1);
    assertGt(info.stakedAt, 0);
    assertGt(info.lockupEndTime, 0);
    assertEq(info.isUnstaking, false);
    assertEq(info.unstakeInitTime, 0);
  }

  function test_LockupPeriodUpdate() public {
    uint256 newLockupPeriod = 30 days;
    
    vm.prank(owner);
    staking.setLockupPeriod(newLockupPeriod);
    
    assertEq(staking.lockupPeriod(), newLockupPeriod);
  }

  function test_PauseUnpause() public {
    vm.prank(owner);
    staking.pause();

    // Cannot stake when paused
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    nft.setApprovalForAll(address(staking), true);
    vm.expectRevert();
    staking.stake(tokenIds);
    vm.stopPrank();

    // Unpause
    vm.prank(owner);
    staking.unpause();

    // Can stake again
    vm.prank(user1);
    staking.stake(tokenIds);
  }
}

