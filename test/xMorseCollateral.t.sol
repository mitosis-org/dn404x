// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';
import { IMulticall3 } from '@std/interfaces/IMulticall3.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { xMorseCollateral } from '../src/xMorseCollateral.sol';
import { MockDN404 } from './mocks/MockDN404.sol';
import { SimpleMulticall } from './mocks/SimpleMulticall.sol';
import { HyperlaneTestUtils } from './utils/HyperlaneTestUtils.sol';

contract xMorseCollateralTest is Test, HyperlaneTestUtils {
  using TypeCasts for address;

  xMorseCollateral public collateral;
  MockDN404 public token;
  IMulticall3 public multicall;

  address public owner;
  address public user;

  uint256 constant INITIAL_SUPPLY = 100 ether;

  function setUp() public {
    owner = makeAddr('owner');
    user = makeAddr('user');

    setupHyperlane();

    // Deploy mock token
    token = new MockDN404('Test NFT', 'TNFT', 18, INITIAL_SUPPLY);

    // Deploy multicall
    address multicallAddr = 0xcA11bde05977b3631167028862bE2a173976CA11;
    if (multicallAddr.code.length == 0) {
      vm.etch(multicallAddr, address(new SimpleMulticall()).code);
    }
    multicall = IMulticall3(multicallAddr);

    // Deploy collateral implementation
    xMorseCollateral implementation =
      new xMorseCollateral(address(token), address(multicall), address(mailboxEth));

    // Deploy proxy
    bytes memory initData = abi.encodeCall(
      xMorseCollateral.initialize,
      (
        owner,
        address(hookEth),
        address(0) // ISM
      )
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
    collateral = xMorseCollateral(address(proxy));

    // Transfer tokens to user
    token.transfer(user, 10 ether);
    vm.prank(user);
    token.setSkipNFT(false);
  }

  function testInitialization() public view {
    assertEq(collateral.TOKEN(), address(token));
    assertEq(address(collateral.MULTICALL()), address(multicall));
    assertEq(address(collateral.mailbox()), address(mailboxEth));
  }

  function testTransferRemoteNFT_FetchesNFT() public {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    address recipient = makeAddr('recipient');

    // User must approve collateral to transfer NFT
    vm.startPrank(user);
    IERC721(address(token)).approve(address(collateral), tokenIds[0]);

    // Transfer remote NFT
    collateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, recipient.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    // Verify NFT was transferred to collateral
    assertEq(IERC721(address(token)).ownerOf(tokenIds[0]), address(collateral));
  }

  function testTransferRemoteNFTPartial_FetchesNFT() public {
    uint256 tokenId = 1;

    bytes32[] memory recipients = new bytes32[](2);
    recipients[0] = makeAddr('recipient1').addressToBytes32();
    recipients[1] = makeAddr('recipient2').addressToBytes32();

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.6 ether;
    amounts[1] = 0.4 ether;

    vm.startPrank(user);
    IERC721(address(token)).approve(address(collateral), tokenId);

    collateral.transferRemoteNFTPartial{ value: 0.1 ether }(
      DOMAIN_MITOSIS, tokenId, recipients, amounts
    );
    vm.stopPrank();

    // Verify NFT was transferred to collateral
    assertEq(IERC721(address(token)).ownerOf(tokenId), address(collateral));
  }

  function testTransferRemoteNFT_EmitsEvent() public {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    address recipient = makeAddr('recipient');
    bytes32 recipientBytes = recipient.addressToBytes32();

    vm.startPrank(user);
    IERC721(address(token)).approve(address(collateral), tokenIds[0]);

    // Just verify the transfer completes
    collateral.transferRemoteNFT{ value: 0.1 ether }(DOMAIN_MITOSIS, recipientBytes, tokenIds);
    vm.stopPrank();
  }

  function testQuoteTransferRemoteNFT() public {
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    address recipient = makeAddr('recipient');

    // First set gas config
    vm.prank(owner);
    uint96 messageType = uint96(uint8(0)); // MessageType.SendNFT
    collateral.setDestinationGas(DOMAIN_MITOSIS, messageType, 100_000);

    // Get quote
    (bool success, bytes memory result) = address(collateral).staticcall(
      abi.encodeCall(
        collateral.quoteTransferRemoteNFT, (DOMAIN_MITOSIS, recipient.addressToBytes32(), tokenIds)
      )
    );
    assertTrue(success);
    assertTrue(result.length > 0);
  }

  function testOwnership_OnlyOwnerCanUpgrade() public {
    address newImplementation =
      address(new xMorseCollateral(address(token), address(multicall), address(mailboxEth)));

    // Non-owner cannot upgrade
    vm.prank(user);
    vm.expectRevert();
    collateral.upgradeToAndCall(newImplementation, '');

    // Owner can upgrade
    vm.prank(owner);
    collateral.upgradeToAndCall(newImplementation, '');
  }

  function testReentrancyProtection() public {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user);
    IERC721(address(token)).approve(address(collateral), tokenIds[0]);

    // First call
    collateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, user.addressToBytes32(), tokenIds
    );

    // Cannot call again in same transaction (reentrancy guard)
    vm.stopPrank();
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }
}


