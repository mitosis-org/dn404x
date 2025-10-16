// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { IMulticall3 } from '@std/interfaces/IMulticall3.sol';

import { IERC721 } from '@oz/token/ERC721/IERC721.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { xDN404Treasury } from '../src/xDN404Treasury.sol';
import { MockDN404 } from './mocks/MockDN404.sol';
import { SimpleMulticall } from './mocks/SimpleMulticall.sol';

contract xDN404TreasuryTest is Test {
  using TypeCasts for address;

  xDN404Treasury public treasury;
  MockDN404 public token;
  IMulticall3 public multicall;

  address public owner;
  address public recipient1;
  address public recipient2;
  address public nonOwner;

  uint256 constant INITIAL_SUPPLY = 100 ether;

  function setUp() public {
    owner = address(this);
    recipient1 = makeAddr('recipient1');
    recipient2 = makeAddr('recipient2');
    nonOwner = makeAddr('nonOwner');

    // Deploy mock token
    token = new MockDN404('Test NFT', 'TNFT', 18, INITIAL_SUPPLY);

    // Deploy multicall
    address multicallAddr = 0xcA11bde05977b3631167028862bE2a173976CA11;
    if (multicallAddr.code.length == 0) {
      vm.etch(multicallAddr, address(new SimpleMulticall()).code);
    }
    multicall = IMulticall3(multicallAddr);

    // Deploy treasury
    treasury = new xDN404Treasury(address(token), address(multicall));

    // Transfer tokens to treasury
    token.transfer(address(treasury), 10 ether);
    
    vm.prank(address(treasury));
    token.setSkipNFT(false);
  }

  function testWithdrawNFT_Single() public {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    bytes32 recipient = recipient1.addressToBytes32();

    treasury.withdrawNFT(recipient, tokenIds);

    assertEq(IERC721(address(token)).ownerOf(tokenIds[0]), recipient1);
  }

  function testWithdrawNFT_Multiple() public {
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    bytes32 recipient = recipient1.addressToBytes32();

    treasury.withdrawNFT(recipient, tokenIds);

    for (uint256 i = 0; i < tokenIds.length; i++) {
      assertEq(IERC721(address(token)).ownerOf(tokenIds[i]), recipient1);
    }
  }

  function testWithdrawNFT_OnlyOwner() public {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    bytes32 recipient = recipient1.addressToBytes32();

    vm.prank(nonOwner);
    vm.expectRevert();
    treasury.withdrawNFT(recipient, tokenIds);
  }

  function testWithdrawNFTPartial_ValidAmounts() public {
    uint256 tokenId = 1;

    bytes32[] memory recipients = new bytes32[](2);
    recipients[0] = recipient1.addressToBytes32();
    recipients[1] = recipient2.addressToBytes32();

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.6 ether;
    amounts[1] = 0.4 ether;

    treasury.withdrawNFTPartial(tokenId, recipients, amounts);

    assertEq(token.balanceOf(recipient1), 0.6 ether);
    assertEq(token.balanceOf(recipient2), 0.4 ether);
  }

  function testWithdrawNFTPartial_OnlyOwner() public {
    uint256 tokenId = 1;

    bytes32[] memory recipients = new bytes32[](1);
    recipients[0] = recipient1.addressToBytes32();

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 1 ether;

    vm.prank(nonOwner);
    vm.expectRevert();
    treasury.withdrawNFTPartial(tokenId, recipients, amounts);
  }

  function testWithdrawNFTPartial_RevertInvalidTotal() public {
    uint256 tokenId = 1;

    bytes32[] memory recipients = new bytes32[](2);
    recipients[0] = recipient1.addressToBytes32();
    recipients[1] = recipient2.addressToBytes32();

    // Invalid: total is not 1 ether
    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.5 ether;
    amounts[1] = 0.3 ether;

    vm.expectRevert();
    treasury.withdrawNFTPartial(tokenId, recipients, amounts);
  }

  function testReentrancyProtection_WithdrawNFT() public {
    // Deploy malicious contract
    MaliciousReceiver malicious = new MaliciousReceiver(treasury);

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    bytes32 recipient = address(malicious).addressToBytes32();

    // Should revert due to reentrancy guard
    vm.expectRevert();
    treasury.withdrawNFT(recipient, tokenIds);
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }
}

contract MaliciousReceiver {
  xDN404Treasury public treasury;

  constructor(xDN404Treasury _treasury) {
    treasury = _treasury;
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    returns (bytes4)
  {
    // Try to reenter
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 2;
    treasury.withdrawNFT(bytes32(uint256(uint160(address(this)))), tokenIds);
    return this.onERC721Received.selector;
  }
}


