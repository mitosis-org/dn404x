// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { IMulticall3 } from '@std/interfaces/IMulticall3.sol';

import { IERC721 } from '@oz/token/ERC721/IERC721.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { LibTransfer } from '../../src/libs/LibTransfer.sol';
import { MockDN404 } from '../mocks/MockDN404.sol';
import { SimpleMulticall } from '../mocks/SimpleMulticall.sol';

contract LibTransferTest is Test {
  using TypeCasts for address;

  MockDN404 public token;
  IMulticall3 public multicall;
  address public sender;
  address public recipient1;
  address public recipient2;

  uint256 constant INITIAL_SUPPLY = 100 ether;
  uint8 constant DECIMALS = 18;

  /// @dev Helper to get NFT contract (Mirror)
  function nftContract() internal view returns (IERC721) {
    return IERC721(token.mirrorERC721());
  }

  function setUp() public {
    sender = makeAddr('sender');
    recipient1 = makeAddr('recipient1');
    recipient2 = makeAddr('recipient2');

    // Deploy mock DN404 token
    token = new MockDN404('Test NFT', 'TNFT', DECIMALS, INITIAL_SUPPLY);

    // Deploy multicall
    address multicallAddr = 0xcA11bde05977b3631167028862bE2a173976CA11;
    if (multicallAddr.code.length == 0) {
      vm.etch(multicallAddr, address(new SimpleMulticall()).code);
    }
    multicall = IMulticall3(multicallAddr);

    // Transfer tokens to sender
    token.transfer(sender, 10 ether);
    
    vm.prank(sender);
    token.setSkipNFT(false);
  }

  function testSendNFT_Single() public {
    // Mint NFT to sender first
    vm.startPrank(sender);
    token.setSkipNFT(false);
    vm.stopPrank();

    // Ensure sender has token balance
    assertGe(token.balanceOf(sender), 1 ether);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    // Transfer NFT from sender to this contract
    vm.startPrank(sender);
    nftContract().safeTransferFrom(sender, address(this), tokenIds[0]);
    vm.stopPrank();

    bytes32 recipient = recipient1.addressToBytes32();

    // Now call LibTransfer.sendNFT from this contract
    LibTransfer.sendNFT(address(token), recipient, tokenIds);

    // Verify NFT was transferred
    assertEq(nftContract().ownerOf(tokenIds[0]), recipient1);
  }

  function testSendNFT_Multiple() public {
    vm.startPrank(sender);
    token.setSkipNFT(false);
    vm.stopPrank();

    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    // Transfer NFTs from sender to this contract
    vm.startPrank(sender);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      nftContract().safeTransferFrom(sender, address(this), tokenIds[i]);
    }
    vm.stopPrank();

    bytes32 recipient = recipient1.addressToBytes32();
    LibTransfer.sendNFT(address(token), recipient, tokenIds);

    // Verify all NFTs were transferred
    for (uint256 i = 0; i < tokenIds.length; i++) {
      assertEq(nftContract().ownerOf(tokenIds[i]), recipient1);
    }
  }

  function testSendNFT_EmptyArray() public {
    uint256[] memory tokenIds = new uint256[](0);
    bytes32 recipient = recipient1.addressToBytes32();

    // Should not revert, just do nothing
    LibTransfer.sendNFT(address(token), recipient, tokenIds);
  }

  function testSendNFTPartial_ValidAmounts() public {
    // Setup: sender has 1 NFT worth of tokens
    vm.startPrank(sender);
    token.setSkipNFT(false);
    vm.stopPrank();

    uint256 tokenId = 1;

    // Transfer NFT to this contract
    vm.startPrank(sender);
    nftContract().safeTransferFrom(sender, address(this), tokenId);
    vm.stopPrank();

    // Prepare partial transfer: 60% to recipient1, 40% to recipient2
    bytes32[] memory recipients = new bytes32[](2);
    recipients[0] = recipient1.addressToBytes32();
    recipients[1] = recipient2.addressToBytes32();

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.6 ether; // 60%
    amounts[1] = 0.4 ether; // 40%

    LibTransfer.sendNFTPartial(address(token), multicall, tokenId, recipients, amounts);

    // Verify balances
    assertEq(token.balanceOf(recipient1), 0.6 ether);
    assertEq(token.balanceOf(recipient2), 0.4 ether);
  }

  function testSendNFTPartial_RevertInvalidTotal() public {
    vm.startPrank(sender);
    token.setSkipNFT(false);
    vm.stopPrank();

    uint256 tokenId = 1;

    vm.startPrank(sender);
    nftContract().safeTransferFrom(sender, address(this), tokenId);
    vm.stopPrank();

    bytes32[] memory recipients = new bytes32[](2);
    recipients[0] = recipient1.addressToBytes32();
    recipients[1] = recipient2.addressToBytes32();

    // Invalid: sum is not 1 ether
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.5 ether;
    amounts[1] = 0.3 ether; // Total = 0.8 ether, not 1

    vm.expectRevert(LibTransfer.TotalAmountMustBeOne.selector);
    LibTransfer.sendNFTPartial(address(token), multicall, tokenId, recipients, amounts);
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }
}

