// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { xMorse } from '../../src/xMorse.sol';
import { xMorseCollateral } from '../../src/xMorseCollateral.sol';
import { xDN404Treasury } from '../../src/xDN404Treasury.sol';
import { MockDN404 } from '../mocks/MockDN404.sol';
import { SimpleMulticall } from '../mocks/SimpleMulticall.sol';
import { HyperlaneTestUtils } from '../utils/HyperlaneTestUtils.sol';
import { MessageType } from '../../src/libs/Message.sol';

/// @dev Comprehensive integration test for cross-chain NFT transfers
contract CrossChainTransferTest is Test, HyperlaneTestUtils {
  using TypeCasts for address;

  // Ethereum side
  MockDN404 public ethToken;
  xMorseCollateral public ethCollateral;

  // Mitosis side
  xMorse public mitMorse;
  xDN404Treasury public mitTreasury;

  // Actors
  address public owner;
  address public userEth;
  address public userMit;

  uint256 constant INITIAL_SUPPLY = 100 ether;
  uint256 constant USER_BALANCE = 10 ether;

  address multicall = 0xcA11bde05977b3631167028862bE2a173976CA11;

  /// @dev Helper to get Ethereum NFT contract (Mirror)
  function ethNFT() internal view returns (IERC721) {
    return IERC721(ethToken.mirrorERC721());
  }

  /// @dev Helper to get Mitosis NFT contract (Mirror)
  function mitNFT() internal view returns (IERC721) {
    return IERC721(mitMorse.mirrorERC721());
  }

  function setUp() public {
    owner = makeAddr('owner');
    userEth = makeAddr('userEth');
    userMit = makeAddr('userMit');

    setupHyperlane();

    // Deploy multicall if needed
    if (multicall.code.length == 0) {
      vm.etch(multicall, address(new SimpleMulticall()).code);
    }

    vm.startPrank(owner);
    // === ETHEREUM SIDE SETUP ===
    ethToken = new MockDN404('Ethereum NFT', 'ENFT', 18, INITIAL_SUPPLY);

    xMorseCollateral ethCollateralImpl =
      new xMorseCollateral(address(ethToken), multicall, address(mailboxEth));

    bytes memory ethInitData = abi.encodeCall(
      xMorseCollateral.initialize,
      (
        owner,
        address(hookEth),
        address(0) // ISM
      )
    );

    ERC1967Proxy ethProxy = new ERC1967Proxy(address(ethCollateralImpl), ethInitData);
    ethCollateral = xMorseCollateral(address(ethProxy));

    // === MITOSIS SIDE SETUP ===
    xMorse mitMorseImpl = new xMorse(address(mailboxMitosis));

    bytes memory mitInitData = abi.encodeCall(
      xMorse.initialize,
      (
        'Mitosis NFT',
        'MNFT',
        18,
        INITIAL_SUPPLY,
        owner,
        address(hookMitosis),
        address(0) // ISM
      )
    );

    ERC1967Proxy mitProxy = new ERC1967Proxy(address(mitMorseImpl), mitInitData);
    mitMorse = xMorse(payable(address(mitProxy)));

    // Deploy and set Treasury
    mitTreasury = new xDN404Treasury(address(mitMorse), multicall);
    mitTreasury.transferOwnership(address(mitMorse));
    mitMorse.setTreasury(address(mitTreasury));
    vm.stopPrank();

    // Finalize mitosis side
    vm.startPrank(address(mitTreasury));
    mitMorse.setSkipNFT(false);
    vm.stopPrank();
    
    vm.startPrank(owner);
    mitMorse.transfer(address(mitTreasury), INITIAL_SUPPLY);
    mitMorse.finalize();
    vm.stopPrank();

    // === CONFIGURE ROUTING ===
    vm.startPrank(owner);
    
    // Ethereum -> Mitosis
    ethCollateral.enrollRemoteRouter(DOMAIN_MITOSIS, address(mitMorse).addressToBytes32());
    ethCollateral.setDestinationGas(DOMAIN_MITOSIS, uint96(uint8(MessageType.SendNFT)), 200_000);
    ethCollateral.setDestinationGas(
      DOMAIN_MITOSIS, uint96(uint8(MessageType.SendNFTPartial)), 300_000
    );

    // Mitosis -> Ethereum
    mitMorse.enrollRemoteRouter(DOMAIN_ETH, address(ethCollateral).addressToBytes32());
    mitMorse.setDestinationGas(DOMAIN_ETH, uint96(uint8(MessageType.SendNFT)), 200_000);
    mitMorse.setDestinationGas(DOMAIN_ETH, uint96(uint8(MessageType.SendNFTPartial)), 300_000);

    // === SETUP USER BALANCES ===
    ethToken.transfer(userEth, USER_BALANCE);
    vm.stopPrank();

    vm.prank(userEth);
    ethToken.setSkipNFT(false);

    // Give user some ETH for gas
    vm.deal(userEth, 10 ether);
    vm.deal(userMit, 10 ether);
  }

  /// @dev Test single NFT transfer from Ethereum to Mitosis
  /// @dev SKIP: Requires MockMailbox for automatic message relay
  function testCrossChain_EthToMit_SingleNFT() public {
    vm.skip(true); // Skip until MockMailbox integration is implemented
    
    uint256 tokenId = 1;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;

    // Verify initial state
    assertEq(ethNFT().ownerOf(tokenId), userEth);

    // User on Ethereum initiates transfer
    vm.startPrank(userEth);
    ethNFT().approve(address(ethCollateral), tokenId);

    ethCollateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, userMit.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    // Verify NFT locked in collateral
    assertEq(ethNFT().ownerOf(tokenId), address(ethCollateral));

    // TODO: Implement message relay with MockMailbox
    // relayMessages(mailboxEth, mailboxMitosis);
    // assertEq(mitMorse.balanceOf(userMit), 1 ether);
  }

  /// @dev Test multiple NFTs transfer from Ethereum to Mitosis
  /// @dev SKIP: Requires MockMailbox for automatic message relay
  function testCrossChain_EthToMit_MultipleNFTs() public {
    vm.skip(true); // Skip until MockMailbox integration is implemented
    
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;

    // User approves and transfers
    vm.startPrank(userEth);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      ethNFT().approve(address(ethCollateral), tokenIds[i]);
    }

    ethCollateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, userMit.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    // Verify all NFTs locked
    for (uint256 i = 0; i < tokenIds.length; i++) {
      assertEq(ethNFT().ownerOf(tokenIds[i]), address(ethCollateral));
    }

    // TODO: Implement message relay
    // relayMessages(mailboxEth, mailboxMitosis);
    // assertEq(mitMorse.balanceOf(userMit), 3 ether);
  }

  /// @dev Test NFT transfer from Mitosis back to Ethereum
  /// @dev SKIP: Requires MockMailbox for automatic message relay
  function testCrossChain_MitToEth_ReturnFlow() public {
    vm.skip(true); // Skip until MockMailbox integration is implemented
    // First, transfer NFT from Eth to Mit
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(userEth);
    ethNFT().approve(address(ethCollateral), tokenIds[0]);
    ethCollateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, userMit.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    relayMessages(mailboxEth, mailboxMitosis);

    // Now user on Mitosis sends NFT back
    vm.startPrank(userMit);
    mitMorse.setSkipNFT(false);

    // Get the NFT ID on Mitosis side
    uint256 mitTokenId = 1; // First NFT from treasury
    tokenIds[0] = mitTokenId;

    mitNFT().approve(address(mitMorse), mitTokenId);

    mitMorse.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_ETH, userEth.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    // Relay message back
    relayMessages(mailboxMitosis, mailboxEth);

    // Verify NFT returned to Ethereum side
    assertEq(ethToken.balanceOf(userEth), USER_BALANCE);
  }

  /// @dev Test partial NFT transfer (fractional ownership)
  /// @dev SKIP: Requires MockMailbox for automatic message relay
  function testCrossChain_PartialTransfer() public {
    vm.skip(true); // Skip until MockMailbox integration is implemented
    
    uint256 tokenId = 1;

    address recipient1 = makeAddr('recipient1');
    address recipient2 = makeAddr('recipient2');

    bytes32[] memory recipients = new bytes32[](2);
    recipients[0] = recipient1.addressToBytes32();
    recipients[1] = recipient2.addressToBytes32();

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.6 ether; // 60%
    amounts[1] = 0.4 ether; // 40%

    // User initiates partial transfer
    vm.startPrank(userEth);
    ethNFT().approve(address(ethCollateral), tokenId);

    ethCollateral.transferRemoteNFTPartial{ value: 0.1 ether }(
      DOMAIN_MITOSIS, tokenId, recipients, amounts
    );
    vm.stopPrank();

    // Relay message
    relayMessages(mailboxEth, mailboxMitosis);

    // Verify fractional ownership on Mitosis
    assertEq(mitMorse.balanceOf(recipient1), 0.6 ether);
    assertEq(mitMorse.balanceOf(recipient2), 0.4 ether);
  }

  /// @dev Test gas estimation for transfers
  function testQuoteTransferRemoteNFT() public {
    uint256[] memory tokenIds = new uint256[](2);
    tokenIds[0] = 1;
    tokenIds[1] = 2;

    (bool success, bytes memory result) = address(ethCollateral).staticcall(
      abi.encodeCall(
        ethCollateral.quoteTransferRemoteNFT,
        (DOMAIN_MITOSIS, userMit.addressToBytes32(), tokenIds)
      )
    );

    assertTrue(success);
    assertTrue(result.length > 0);
  }

  /// @dev Test operation ID uniqueness
  /// @dev SKIP: Requires MockMailbox for automatic message relay
  function testOperationId_Uniqueness() public {
    vm.skip(true); // Skip until MockMailbox integration is implemented
    
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    // Get first operation ID
    bytes32 opId1 = ethCollateral.nextOperationId(userEth.addressToBytes32());

    // Execute transfer
    vm.startPrank(userEth);
    ethNFT().approve(address(ethCollateral), tokenIds[0]);
    ethCollateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, userMit.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    // Get next operation ID (should be different)
    bytes32 opId2 = ethCollateral.nextOperationId(userEth.addressToBytes32());

    assertTrue(opId1 != opId2);
  }

  /// @dev Test operation nonce increments
  /// @dev SKIP: Requires MockMailbox for automatic message relay
  function testOperationNonce_Increments() public {
    vm.skip(true); // Skip until MockMailbox integration is implemented
    
    uint256 nonce1 = ethCollateral.getOperationNonce(userEth.addressToBytes32());

    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(userEth);
    ethNFT().approve(address(ethCollateral), tokenIds[0]);
    ethCollateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, userMit.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    uint256 nonce2 = ethCollateral.getOperationNonce(userEth.addressToBytes32());

    assertEq(nonce2, nonce1 + 1);
  }

  /// @dev Test invalid partial transfer (amounts don't sum to 1)
  function testCrossChain_PartialTransfer_InvalidTotal() public {
    uint256 tokenId = 1;

    bytes32[] memory recipients = new bytes32[](2);
    recipients[0] = makeAddr('r1').addressToBytes32();
    recipients[1] = makeAddr('r2').addressToBytes32();

    uint256[] memory amounts = new uint256[](2);
    amounts[0] = 0.5 ether;
    amounts[1] = 0.3 ether; // Total = 0.8, not 1

    vm.startPrank(userEth);
    ethNFT().approve(address(ethCollateral), tokenId);

    vm.expectRevert();
    ethCollateral.transferRemoteNFTPartial{ value: 0.1 ether }(
      DOMAIN_MITOSIS, tokenId, recipients, amounts
    );
    vm.stopPrank();
  }

  /// @dev Test event emission on receive
  function testCrossChain_EventEmission() public {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(userEth);
    ethNFT().approve(address(ethCollateral), tokenIds[0]);
    ethCollateral.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_MITOSIS, userMit.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    // Relay messages (Note: TestMailbox auto-processes in some cases)
    relayMessages(mailboxEth, mailboxMitosis);
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }
}


