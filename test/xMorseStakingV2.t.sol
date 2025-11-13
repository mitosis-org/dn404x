// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@oz/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC721 } from "@oz/token/ERC721/IERC721.sol";
import { Time } from "@oz/utils/types/Time.sol";

import { xMorseStakingV2 } from "../src/xMorseStakingV2.sol";
import { IxMorseStakingV2 } from "../src/interfaces/IxMorseStakingV2.sol";

/// @title xMorseStakingV2Test
/// @notice Test suite for xMorseStakingV2 contract
contract xMorseStakingV2Test is Test {
  xMorseStakingV2 public staking;
  
  address public owner = address(0x1);
  address public user1 = address(0x2);
  address public user2 = address(0x3);
  
  address public mockXMorse = address(0x100);
  address public mockMirrorNFT = address(0x101);
  address public mockRewardToken = address(0x102);

  function setUp() public {
    // Deploy implementation
    xMorseStakingV2 impl = new xMorseStakingV2();
    
    // Mock DN404 setSkipNFT call
    vm.mockCall(
      mockXMorse,
      abi.encodeWithSignature("setSkipNFT(bool)", true),
      abi.encode(true)
    );
    
    // Deploy proxy
    bytes memory initData = abi.encodeWithSelector(
      xMorseStakingV2.initialize.selector,
      mockXMorse,
      mockMirrorNFT,
      mockRewardToken,
      owner
    );
    
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    staking = xMorseStakingV2(address(proxy));
  }

  function test_Initialize() public view {
    assertEq(staking.xMorseToken(), mockXMorse);
    assertEq(staking.mirrorNFT(), mockMirrorNFT);
    assertEq(staking.rewardToken(), mockRewardToken);
    assertEq(staking.owner(), owner);
    assertEq(staking.lockupPeriod(), 21 days);
  }

  function test_Stake_SingleNFT() public {
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    // Mock NFT transfer
    vm.mockCall(
      mockMirrorNFT,
      abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), tokenId),
      abi.encode()
    );

    // Stake as user1
    vm.prank(user1);
    staking.stake(tokenIds);

    // Verify NFT info
    IxMorseStakingV2.NFTInfo memory info = staking.getNFTInfo(tokenId);
    assertEq(info.owner, user1);
    assertEq(info.stakedAt, block.timestamp);
    assertEq(info.lockupEndTime, block.timestamp + 21 days);

    // Verify staked NFTs array
    uint256[] memory stakedNFTs = staking.getStakedNFTs(user1);
    assertEq(stakedNFTs.length, 1);
    assertEq(stakedNFTs[0], tokenId);
  }

  function test_Stake_MultipleNFTs() public {
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    // Mock NFT transfers
    for (uint256 i = 0; i < tokenIds.length; i++) {
      vm.mockCall(
        mockMirrorNFT,
        abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), tokenIds[i]),
        abi.encode()
      );
    }

    // Stake as user1
    vm.prank(user1);
    staking.stake(tokenIds);

    // Verify staked NFTs
    uint256[] memory stakedNFTs = staking.getStakedNFTs(user1);
    assertEq(stakedNFTs.length, 3);
  }

  function test_TWAB_SingleStaker() public {
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    // Mock NFT transfers
    for (uint256 i = 0; i < tokenIds.length; i++) {
      vm.mockCall(
        mockMirrorNFT,
        abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), tokenIds[i]),
        abi.encode()
      );
    }

    uint48 startTime = Time.timestamp();
    
    // Stake as user1
    vm.prank(user1);
    staking.stake(tokenIds);

    // Check TWAB immediately after staking
    uint48 now1 = Time.timestamp();
    uint256 stakerTotal = staking.stakerTotal(user1, now1);
    uint256 stakerTWAB = staking.stakerTotalTWAB(user1, now1);
    
    assertEq(stakerTotal, 2, "Should have 2 NFTs staked");
    assertEq(stakerTWAB, 0, "TWAB should be 0 immediately after stake");

    // Warp 100 seconds
    vm.warp(101);
    uint48 now2 = 101;
    
    uint256 stakerTWAB2 = staking.stakerTotalTWAB(user1, now2);
    assertEq(stakerTWAB2, 200, "TWAB should be 2 NFTs * 100 seconds = 200");

    // Warp another 100 seconds (total 200 seconds from start)
    vm.warp(201);
    uint48 now3 = 201;
    
    uint256 stakerTWAB3 = staking.stakerTotalTWAB(user1, now3);
    assertEq(stakerTWAB3, 400, "TWAB should be 2 NFTs * 200 seconds total = 400");
  }

  function test_TWAB_TotalTracking() public {
    // User1 stakes 2 NFTs
    uint256[] memory tokenIds1 = new uint256[](2);
    tokenIds1[0] = 1;
    tokenIds1[1] = 2;

    for (uint256 i = 0; i < tokenIds1.length; i++) {
      vm.mockCall(
        mockMirrorNFT,
        abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), tokenIds1[i]),
        abi.encode()
      );
    }

    vm.prank(user1);
    staking.stake(tokenIds1);

    // Warp 100 seconds
    vm.warp(block.timestamp + 100);

    // User2 stakes 3 NFTs
    uint256[] memory tokenIds2 = new uint256[](3);
    tokenIds2[0] = 10;
    tokenIds2[1] = 11;
    tokenIds2[2] = 12;

    for (uint256 i = 0; i < tokenIds2.length; i++) {
      vm.mockCall(
        mockMirrorNFT,
        abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user2, address(staking), tokenIds2[i]),
        abi.encode()
      );
    }

    vm.prank(user2);
    staking.stake(tokenIds2);

    uint48 now_ = Time.timestamp();
    
    // Check totals
    uint256 totalStaked = staking.totalStaked(now_);
    assertEq(totalStaked, 5, "Total should be 5 NFTs");

    // Total TWAB should be 200 (2 NFTs * 100 seconds from user1)
    uint256 totalTWAB = staking.totalStakedTWAB(now_);
    assertEq(totalTWAB, 200, "Total TWAB should be 200");
  }

  function test_Unstake_AfterLockup() public {
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    // Mock stake
    vm.mockCall(
      mockMirrorNFT,
      abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), tokenId),
      abi.encode()
    );

    vm.prank(user1);
    staking.stake(tokenIds);

    // Warp past lockup period
    vm.warp(block.timestamp + 21 days + 1);

    // Mock NFT return
    vm.mockCall(
      mockMirrorNFT,
      abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(staking), user1, tokenId),
      abi.encode()
    );

    // Unstake
    vm.prank(user1);
    staking.unstake(tokenIds);

    // Verify NFT info cleared
    IxMorseStakingV2.NFTInfo memory info = staking.getNFTInfo(tokenId);
    assertEq(info.owner, address(0));

    // Verify staked NFTs array empty
    uint256[] memory stakedNFTs = staking.getStakedNFTs(user1);
    assertEq(stakedNFTs.length, 0);
  }

  function test_Unstake_RevertIfLockupNotEnded() public {
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    // Mock stake
    vm.mockCall(
      mockMirrorNFT,
      abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), tokenId),
      abi.encode()
    );

    vm.prank(user1);
    staking.stake(tokenIds);

    // Try to unstake immediately (should fail)
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(IxMorseStakingV2.LockupPeriodNotEnded.selector, tokenId));
    staking.unstake(tokenIds);
  }

  function test_Stake_RevertIfAlreadyStaked() public {
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    // Mock stake
    vm.mockCall(
      mockMirrorNFT,
      abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), tokenId),
      abi.encode()
    );

    vm.prank(user1);
    staking.stake(tokenIds);

    // Try to stake again (should fail)
    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(IxMorseStakingV2.NFTAlreadyStaked.selector, tokenId));
    staking.stake(tokenIds);
  }

  function test_SetLockupPeriod() public {
    uint256 newPeriod = 14 days;
    
    vm.prank(owner);
    staking.setLockupPeriod(newPeriod);
    
    assertEq(staking.lockupPeriod(), newPeriod);
  }

  function test_Pause_Unpause() public {
    vm.prank(owner);
    staking.pause();
    
    // Try to stake while paused (should fail)
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    
    vm.prank(user1);
    vm.expectRevert();
    staking.stake(tokenIds);
    
    // Unpause
    vm.prank(owner);
    staking.unpause();
    
    // Mock and stake should work now
    vm.mockCall(
      mockMirrorNFT,
      abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user1, address(staking), 1),
      abi.encode()
    );
    
    vm.prank(user1);
    staking.stake(tokenIds);
  }
}
