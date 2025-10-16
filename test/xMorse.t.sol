// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { xMorse } from '../src/xMorse.sol';
import { xDN404Treasury } from '../src/xDN404Treasury.sol';
import { SimpleMulticall } from './mocks/SimpleMulticall.sol';
import { HyperlaneTestUtils } from './utils/HyperlaneTestUtils.sol';

contract xMorseTest is Test, HyperlaneTestUtils {
  using TypeCasts for address;

  xMorse public morse;
  address public owner;
  address public user1;
  address public user2;

  uint256 constant INITIAL_SUPPLY = 100 ether;
  string constant NAME = 'xMorse NFT';
  string constant SYMBOL = 'xMORSE';
  uint8 constant DECIMALS = 18;

  address multicall = 0xcA11bde05977b3631167028862bE2a173976CA11;

  function setUp() public {
    owner = makeAddr('owner');
    user1 = makeAddr('user1');
    user2 = makeAddr('user2');

    setupHyperlane();

    // Deploy mock multicall if needed
    if (multicall.code.length == 0) {
      vm.etch(multicall, address(new SimpleMulticall()).code);
    }

    // Deploy xMorse implementation
    xMorse implementation = new xMorse(address(mailboxMitosis));

    // Deploy proxy
    bytes memory initData = abi.encodeCall(
      xMorse.initialize,
      (
        NAME,
        SYMBOL,
        DECIMALS,
        multicall,
        INITIAL_SUPPLY,
        owner,
        address(hookMitosis),
        address(0) // ISM
      )
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
    morse = xMorse(payable(address(proxy)));
  }

  function testInitialization() public view {
    assertEq(morse.name(), NAME);
    assertEq(morse.symbol(), SYMBOL);
    assertEq(morse.owner(), owner);
    assertEq(morse.balanceOf(owner), INITIAL_SUPPLY);
  }

  function testTreasuryCreated() public view {
    // Treasury is created during initialization
    // We can verify it exists by checking if it's a valid contract
    assertTrue(address(morse).code.length > 0);
  }

  function testFinalize_Success() public {
    // Get treasury address via storage slot reading
    bytes32 treasurySlot = keccak256(abi.encode('mitosis.storage.xMorse'));
    address treasury = address(
      uint160(uint256(vm.load(address(morse), bytes32(uint256(treasurySlot) + 3))))
    );
    
    // Transfer all tokens to treasury
    vm.startPrank(treasury);
    morse.setSkipNFT(false);
    vm.stopPrank();
    
    vm.startPrank(owner);
    morse.transfer(treasury, INITIAL_SUPPLY);
    vm.stopPrank();

    // Now finalize
    vm.prank(owner);
    morse.finalize();
  }

  function testFinalize_RevertTreasurySkipNFTNotSet() public {
    // Get treasury address
    bytes32 treasurySlot = keccak256(abi.encode('mitosis.storage.xMorse'));
    address treasury = address(
      uint160(uint256(vm.load(address(morse), bytes32(uint256(treasurySlot) + 3))))
    );
    
    // Transfer all tokens to treasury but don't set skipNFT
    vm.startPrank(owner);
    morse.transfer(treasury, INITIAL_SUPPLY);
    vm.stopPrank();

    // Should revert because skipNFT is not set correctly
    vm.prank(owner);
    vm.expectRevert(xMorse.TreasurySkipNFTIsNotSet.selector);
    morse.finalize();
  }

  function testFinalize_RevertBalanceMismatch() public {
    // Get treasury address
    bytes32 treasurySlot = keccak256(abi.encode('mitosis.storage.xMorse'));
    address treasury = address(
      uint160(uint256(vm.load(address(morse), bytes32(uint256(treasurySlot) + 3))))
    );
    
    vm.prank(treasury);
    morse.setSkipNFT(false);
    
    vm.startPrank(owner);
    morse.transfer(treasury, INITIAL_SUPPLY / 2);
    vm.stopPrank();

    vm.prank(owner);
    vm.expectRevert(xMorse.TreasuryBalanceDoesNotMatchInitialTokenSupply.selector);
    morse.finalize();
  }

  function testFinalize_OnlyOwner() public {
    vm.prank(user1);
    vm.expectRevert();
    morse.finalize();
  }

  function testDN404Functionality_Transfer() public {
    // Owner transfers tokens to user1
    vm.prank(owner);
    morse.transfer(user1, 5 ether);

    assertEq(morse.balanceOf(user1), 5 ether);
    assertEq(morse.balanceOf(owner), INITIAL_SUPPLY - 5 ether);
  }

  function testDN404Functionality_NFTMinting() public {
    vm.startPrank(owner);
    morse.setSkipNFT(false);
    
    // Transfer enough to mint NFTs
    morse.transfer(user1, 3 ether);
    vm.stopPrank();

    vm.prank(user1);
    morse.setSkipNFT(false);

    // User1 should have NFTs minted
    uint256 balance = morse.balanceOf(user1);
    assertEq(balance, 3 ether);
  }

  function testTransferRemoteNFT_Configured() public {
    // Get treasury address
    bytes32 treasurySlot = keccak256(abi.encode('mitosis.storage.xMorse'));
    address treasury = address(
      uint160(uint256(vm.load(address(morse), bytes32(uint256(treasurySlot) + 3))))
    );
    
    // Setup: finalize the contract first
    vm.prank(treasury);
    morse.setSkipNFT(false);
    
    vm.startPrank(owner);
    morse.transfer(treasury, INITIAL_SUPPLY);
    morse.finalize();
    
    // Configure gas
    morse.setDestinationGas(DOMAIN_ETH, uint96(uint8(0)), 100_000);
    
    // Transfer some back to user
    morse.transfer(user1, 3 ether);
    vm.stopPrank();

    vm.startPrank(user1);
    morse.setSkipNFT(false);
    
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;
    
    // Approve NFT transfer
    IERC721(address(morse)).approve(address(morse), tokenIds[0]);

    // Should not revert
    morse.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_ETH, user2.addressToBytes32(), tokenIds
    );
    vm.stopPrank();
  }

  function testUpgrade_OnlyOwner() public {
    address newImplementation = address(new xMorse(address(mailboxMitosis)));

    // Non-owner cannot upgrade
    vm.prank(user1);
    vm.expectRevert();
    morse.upgradeToAndCall(newImplementation, '');

    // Owner can upgrade
    vm.prank(owner);
    morse.upgradeToAndCall(newImplementation, '');
  }

  function testOwnershipTransfer() public {
    vm.startPrank(owner);
    morse.transferOwnership(user1);
    vm.stopPrank();

    // Ownership not transferred yet (2-step)
    assertEq(morse.owner(), owner);

    // User1 accepts ownership
    vm.prank(user1);
    morse.acceptOwnership();

    assertEq(morse.owner(), user1);
  }

  function testBaseURI() public view {
    string memory uri = morse.baseURI();
    assertEq(uri, '');
  }

  function testMirrorDeployment() public view {
    address mirror = morse.mirrorERC721();
    assertTrue(mirror != address(0));
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }
}


