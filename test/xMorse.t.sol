// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';

import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { xMorse } from '../src/xMorse.sol';
import { SimpleMulticall } from './mocks/SimpleMulticall.sol';
import { HyperlaneTestUtils } from './utils/HyperlaneTestUtils.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

contract xMorseTest is Test, HyperlaneTestUtils {
  using TypeCasts for address;

  xMorse public morse;
  address public owner;
  address public user1;
  address public user2;

  string constant NAME = 'xMorse NFT';
  string constant SYMBOL = 'xMORSE';
  uint8 constant DECIMALS = 18;
  string constant BASE_URI = 'https://morse.example.com/nft/{id}';

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

    // Deploy DN404Mirror with address(this) as deployer to allow proxy linking
    DN404Mirror mirror = new DN404Mirror(address(this));

    // Deploy proxy
    bytes memory initData = abi.encodeCall(
      xMorse.initialize,
      (
        NAME,
        SYMBOL,
        DECIMALS,
        BASE_URI,
        owner,
        address(hookMitosis),
        address(0), // ISM
        address(mirror) // Mirror
      )
    );

    ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
    morse = xMorse(payable(address(proxy)));
    
    // Give users ETH for gas payments
    vm.deal(user1, 10 ether);
    vm.deal(user2, 10 ether);
  }

  function testInitialization() public view {
    assertEq(morse.name(), NAME);
    assertEq(morse.symbol(), SYMBOL);
    assertEq(morse.decimals(), DECIMALS);
    assertEq(morse.owner(), owner);
    assertEq(morse.baseURI(), BASE_URI);
    assertEq(morse.totalSupply(), 0); // Starts with zero supply
  }

  function testSetBaseURI() public {
    string memory newURI = 'https://new-uri.com/token/{id}';
    
    vm.prank(owner);
    morse.setBaseURI(newURI);
    
    assertEq(morse.baseURI(), newURI);
  }

  function testSetBaseURI_OnlyOwner() public {
    vm.prank(user1);
    vm.expectRevert();
    morse.setBaseURI('https://new-uri.com/token/{id}');
  }

  function testMintViaBridge() public {
    // Simulate receiving NFTs from Ethereum
    uint256[] memory ethereumTokenIds = new uint256[](3);
    ethereumTokenIds[0] = 123;
    ethereumTokenIds[1] = 456;
    ethereumTokenIds[2] = 789;

    // Configure gas and enroll remote router
    vm.startPrank(owner);
    morse.setDestinationGas(DOMAIN_ETH, uint96(uint8(0)), 100_000);
    morse.enrollRemoteRouter(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))));
    vm.stopPrank();

    // Simulate Hyperlane message from Ethereum
    bytes memory message = abi.encodePacked(
      uint8(0), // MessageType.SendNFT
      bytes32(uint256(1)), // operationId
      user1.addressToBytes32(), // recipient
      uint8(3), // tokenIds.length
      bytes32(uint256(123)),
      bytes32(uint256(456)),
      bytes32(uint256(789))
    );

    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message);

    // Verify tokens were minted
    assertEq(morse.balanceOf(user1), 3 ether);
    
    // Verify token ID mappings were saved
    // The minted Mitosis token IDs will be sequential (1, 2, 3)
    assertEq(morse.getEthereumTokenId(1), 123);
    assertEq(morse.getEthereumTokenId(2), 456);
    assertEq(morse.getEthereumTokenId(3), 789);
    
    assertEq(morse.getMitosisTokenId(123), 1);
    assertEq(morse.getMitosisTokenId(456), 2);
    assertEq(morse.getMitosisTokenId(789), 3);
  }

  function testTokenURIUsesMappedId() public {
    // Setup: Mint via bridge
    vm.startPrank(owner);
    morse.setDestinationGas(DOMAIN_ETH, uint96(uint8(0)), 100_000);
    morse.enrollRemoteRouter(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))));
    vm.stopPrank();

    bytes memory message = abi.encodePacked(
      uint8(0), // MessageType.SendNFT
      bytes32(uint256(1)), // operationId
      user1.addressToBytes32(), // recipient
      uint8(1), // tokenIds.length
      bytes32(uint256(999)) // Ethereum token ID 999
    );

    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message);

    // Mitosis token ID 1 should map to Ethereum token ID 999
    address mirror = morse.mirrorERC721();
    string memory tokenURI = DN404Mirror(payable(mirror)).tokenURI(1);
    
    // Should use Ethereum token ID in the URI
    assertEq(tokenURI, 'https://morse.example.com/nft/999');
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

  function testMirrorDeployment() public view {
    address mirror = morse.mirrorERC721();
    assertTrue(mirror != address(0));
  }

  /// @notice Test burning NFT and mapping cleanup when sending back to Ethereum
  function testBurnViaBridge() public {
    // Setup: Receive NFT from Ethereum
    vm.startPrank(owner);
    morse.setDestinationGas(DOMAIN_ETH, uint96(uint8(0)), 100_000);
    morse.enrollRemoteRouter(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))));
    vm.stopPrank();

    bytes memory message = abi.encodePacked(
      uint8(0), // MessageType.SendNFT
      bytes32(uint256(1)), // operationId
      user1.addressToBytes32(), // recipient
      uint8(1), // tokenIds.length
      bytes32(uint256(999)) // Ethereum token ID 999
    );

    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message);

    // Verify NFT was minted and mapped
    assertEq(morse.balanceOf(user1), 1 ether);
    assertEq(morse.getEthereumTokenId(1), 999);
    assertEq(morse.getMitosisTokenId(999), 1);

    // Now send it back to Ethereum
    address mirror = morse.mirrorERC721();
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    // User needs to enable NFT for transfer
    morse.setSkipNFT(false);
    
    // Approve and transfer
    IERC721(mirror).approve(address(morse), 1);
    morse.transferRemoteNFT{ value: 0.1 ether }(
      DOMAIN_ETH, user2.addressToBytes32(), tokenIds
    );
    vm.stopPrank();

    // Verify NFT was burned
    assertEq(morse.balanceOf(user1), 0);
    
    // Verify mappings were cleaned up
    assertEq(morse.getEthereumTokenId(1), 0, "Mitosis->Ethereum mapping should be cleared");
    assertEq(morse.getMitosisTokenId(999), 0, "Ethereum->Mitosis mapping should be cleared");
  }

  /// @notice Test round-trip: same Ethereum NFT bridged multiple times
  function testRoundTripMapping() public {
    console2.log("\n=== Round Trip Mapping Test ===\n");
    
    vm.startPrank(owner);
    morse.setDestinationGas(DOMAIN_ETH, uint96(uint8(0)), 100_000);
    morse.enrollRemoteRouter(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))));
    vm.stopPrank();

    // Round 1: Ethereum #999 -> Mitosis
    console2.log("Round 1: Ethereum #999 -> Mitosis");
    bytes memory message1 = abi.encodePacked(
      uint8(0),
      bytes32(uint256(1)),
      user1.addressToBytes32(),
      uint8(1),
      bytes32(uint256(999))
    );
    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message1);

    assertEq(morse.getEthereumTokenId(1), 999, "Round 1: Mitosis #1 -> Ethereum #999");
    assertEq(morse.getMitosisTokenId(999), 1, "Round 1: Ethereum #999 -> Mitosis #1");
    console2.log("  Mitosis NFT #1 created, mapped to Ethereum #999");

    // Send back to Ethereum
    console2.log("\nRound 1: Mitosis #1 -> Ethereum (burn)");
    address mirror = morse.mirrorERC721();
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 1;

    vm.startPrank(user1);
    morse.setSkipNFT(false);
    IERC721(mirror).approve(address(morse), 1);
    morse.transferRemoteNFT{ value: 0.1 ether }(DOMAIN_ETH, user2.addressToBytes32(), tokenIds);
    vm.stopPrank();

    assertEq(morse.getEthereumTokenId(1), 0, "Round 1: Mapping cleared after burn");
    assertEq(morse.getMitosisTokenId(999), 0, "Round 1: Reverse mapping cleared");
    console2.log("  Mitosis NFT #1 burned, mappings cleared");

    // Round 2: Same Ethereum #999 -> Mitosis again
    console2.log("\nRound 2: Ethereum #999 -> Mitosis (again)");
    bytes memory message2 = abi.encodePacked(
      uint8(0),
      bytes32(uint256(2)),
      user1.addressToBytes32(),
      uint8(1),
      bytes32(uint256(999))
    );
    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message2);

    // DN404 reuses burned token IDs from the burnedPool
    // So #1 will be minted again (not #2)
    assertEq(morse.getEthereumTokenId(1), 999, "Round 2: Mitosis #1 (reused) -> Ethereum #999");
    assertEq(morse.getMitosisTokenId(999), 1, "Round 2: Ethereum #999 -> Mitosis #1 (reused)");
    console2.log("  Mitosis NFT #1 re-created (DN404 reuses burned IDs), mapped to Ethereum #999");
    
    console2.log("\n[SUCCESS] Same Ethereum NFT can be bridged multiple times!");
    console2.log("DN404 reuses burned token IDs for gas efficiency.\n");
  }

  /// @notice Test multiple NFTs and verify each mapping is independent
  function testMultipleNFTMappings() public {
    vm.startPrank(owner);
    morse.setDestinationGas(DOMAIN_ETH, uint96(uint8(0)), 100_000);
    morse.enrollRemoteRouter(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))));
    vm.stopPrank();

    // Bridge multiple NFTs
    bytes memory message = abi.encodePacked(
      uint8(0),
      bytes32(uint256(1)),
      user1.addressToBytes32(),
      uint8(3),
      bytes32(uint256(100)),
      bytes32(uint256(200)),
      bytes32(uint256(300))
    );
    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message);

    // Verify all mappings
    assertEq(morse.getEthereumTokenId(1), 100);
    assertEq(morse.getEthereumTokenId(2), 200);
    assertEq(morse.getEthereumTokenId(3), 300);
    
    assertEq(morse.getMitosisTokenId(100), 1);
    assertEq(morse.getMitosisTokenId(200), 2);
    assertEq(morse.getMitosisTokenId(300), 3);

    // Burn only middle NFT
    address mirror = morse.mirrorERC721();
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 2;

    vm.startPrank(user1);
    morse.setSkipNFT(false);
    IERC721(mirror).approve(address(morse), 2);
    morse.transferRemoteNFT{ value: 0.1 ether }(DOMAIN_ETH, user2.addressToBytes32(), tokenIds);
    vm.stopPrank();

    // Verify only middle NFT mapping was cleared
    assertEq(morse.getEthereumTokenId(1), 100, "NFT #1 mapping should remain");
    assertEq(morse.getEthereumTokenId(2), 0, "NFT #2 mapping should be cleared");
    assertEq(morse.getEthereumTokenId(3), 300, "NFT #3 mapping should remain");
    
    assertEq(morse.getMitosisTokenId(100), 1, "Reverse mapping #100 should remain");
    assertEq(morse.getMitosisTokenId(200), 0, "Reverse mapping #200 should be cleared");
    assertEq(morse.getMitosisTokenId(300), 3, "Reverse mapping #300 should remain");
  }

  /// @notice Test that contract has skipNFT enabled to auto-burn received NFTs
  function testContractSkipsNFT() public view {
    assertTrue(morse.getSkipNFT(address(morse)), "Contract should skip NFT minting");
  }

  //====================================================================================//
  //======================= NFT EXTENSION TESTS (NEW FEATURES) =========================//
  //====================================================================================//

  /// @notice Test supportsInterface for IERC721Enumerable
  function testSupportsInterface() public view {
    // IERC721Enumerable: 0x780e9d63
    assertTrue(morse.supportsInterface(0x780e9d63), "Should support IERC721Enumerable");
    
    // IERC721: 0x80ac58cd
    assertTrue(morse.supportsInterface(0x80ac58cd), "Should support IERC721");
    
    // IERC165: 0x01ffc9a7
    assertTrue(morse.supportsInterface(0x01ffc9a7), "Should support IERC165");
    
    // Random interface should return false
    assertFalse(morse.supportsInterface(0x12345678), "Should not support random interface");
  }

  /// @notice Test batchApprove with multiple NFTs
  function testBatchApprove() public {
    // Setup: Mint NFTs to user1
    _mintNFTsToUser(user1, 5);
    
    address mirror = morse.mirrorERC721();
    address operator = makeAddr('operator');
    
    // Batch approve 3 NFTs
    uint256[] memory tokenIds = new uint256[](3);
    tokenIds[0] = 1;
    tokenIds[1] = 2;
    tokenIds[2] = 3;
    
    vm.prank(user1);
    morse.batchApprove(operator, tokenIds);
    
    // Verify all approvals
    assertEq(IERC721(mirror).getApproved(1), operator, "Token 1 should be approved");
    assertEq(IERC721(mirror).getApproved(2), operator, "Token 2 should be approved");
    assertEq(IERC721(mirror).getApproved(3), operator, "Token 3 should be approved");
    assertEq(IERC721(mirror).getApproved(4), address(0), "Token 4 should not be approved");
  }

  /// @notice Test single approveNFT
  function testApproveNFT() public {
    // Setup: Mint NFTs to user1
    _mintNFTsToUser(user1, 3);
    
    address mirror = morse.mirrorERC721();
    address operator = makeAddr('operator');
    
    // Approve single NFT through xMorse
    vm.prank(user1);
    address owner = morse.approveNFT(operator, 1);
    
    // Verify approval
    assertEq(owner, user1, "Should return the owner address");
    assertEq(IERC721(mirror).getApproved(1), operator, "Token 1 should be approved");
    assertEq(IERC721(mirror).getApproved(2), address(0), "Token 2 should not be approved");
  }

  /// @notice Test approveNFT for staking use case
  function testApproveNFT_ForStaking() public {
    // Setup: Mint NFT to user1
    _mintNFTsToUser(user1, 1);
    
    address mirror = morse.mirrorERC721();
    address stakingContract = makeAddr('stakingContract');
    
    // User approves NFT to staking contract through xMorse
    vm.prank(user1);
    morse.approveNFT(stakingContract, 1);
    
    // Verify staking contract can now transfer the NFT
    assertEq(IERC721(mirror).getApproved(1), stakingContract, "Staking contract should be approved");
    
    // Simulate staking contract transferring NFT
    vm.prank(stakingContract);
    IERC721(mirror).transferFrom(user1, stakingContract, 1);
    
    // Verify transfer succeeded
    assertEq(IERC721(mirror).ownerOf(1), stakingContract, "NFT should be owned by staking contract");
  }

  /// @notice Test batchApprove with empty array
  function testBatchApprove_EmptyArray() public {
    uint256[] memory tokenIds = new uint256[](0);
    
    vm.prank(user1);
    morse.batchApprove(makeAddr('operator'), tokenIds);
    // Should not revert
  }

  /// @notice Test tokenByIndex
  function testTokenByIndex() public {
    // Setup: Mint 5 NFTs
    _mintNFTsToUser(user1, 5);
    
    // Test valid indices (0-based)
    assertEq(morse.tokenByIndex(0), 1, "Index 0 should return token 1");
    assertEq(morse.tokenByIndex(1), 2, "Index 1 should return token 2");
    assertEq(morse.tokenByIndex(2), 3, "Index 2 should return token 3");
    assertEq(morse.tokenByIndex(3), 4, "Index 3 should return token 4");
    assertEq(morse.tokenByIndex(4), 5, "Index 4 should return token 5");
  }

  /// @notice Test tokenByIndex with out of bounds
  function testTokenByIndex_OutOfBounds() public {
    // Setup: Mint 3 NFTs
    _mintNFTsToUser(user1, 3);
    
    // Should revert for index >= totalSupply
    vm.expectRevert("Index out of bounds");
    morse.tokenByIndex(3);
    
    vm.expectRevert("Index out of bounds");
    morse.tokenByIndex(100);
  }

  /// @notice Test tokenOfOwnerByIndex
  function testTokenOfOwnerByIndex() public {
    // Setup: Mint NFTs to user1
    _mintNFTsToUser(user1, 3);
    
    // Test valid indices
    uint256 token0 = morse.tokenOfOwnerByIndex(user1, 0);
    uint256 token1 = morse.tokenOfOwnerByIndex(user1, 1);
    uint256 token2 = morse.tokenOfOwnerByIndex(user1, 2);
    
    // Tokens should be 1, 2, 3 (order may vary in DN404)
    assertTrue(token0 >= 1 && token0 <= 3, "Token 0 should be valid");
    assertTrue(token1 >= 1 && token1 <= 3, "Token 1 should be valid");
    assertTrue(token2 >= 1 && token2 <= 3, "Token 2 should be valid");
    
    // Verify all tokens are unique
    assertTrue(token0 != token1 && token0 != token2 && token1 != token2, "All tokens should be unique");
  }

  /// @notice Test tokenOfOwnerByIndex with multiple owners
  function testTokenOfOwnerByIndex_MultipleOwners() public {
    // Mint 3 NFTs to user1
    _mintNFTsToUser(user1, 3);
    
    // Mint 2 NFTs to user2
    _mintNFTsToUser(user2, 2);
    
    address mirror = morse.mirrorERC721();
    
    // User1 should have 3 NFTs
    assertEq(IERC721(mirror).balanceOf(user1), 3, "User1 should have 3 NFTs");
    morse.tokenOfOwnerByIndex(user1, 0);
    morse.tokenOfOwnerByIndex(user1, 1);
    morse.tokenOfOwnerByIndex(user1, 2);
    
    // User2 should have 2 NFTs
    assertEq(IERC721(mirror).balanceOf(user2), 2, "User2 should have 2 NFTs");
    morse.tokenOfOwnerByIndex(user2, 0);
    morse.tokenOfOwnerByIndex(user2, 1);
  }

  /// @notice Test tokenOfOwnerByIndex out of bounds
  function testTokenOfOwnerByIndex_OutOfBounds() public {
    // Mint 2 NFTs to user1
    _mintNFTsToUser(user1, 2);
    
    // Should revert for index >= balance
    vm.expectRevert("Index out of bounds");
    morse.tokenOfOwnerByIndex(user1, 2);
    
    vm.expectRevert("Index out of bounds");
    morse.tokenOfOwnerByIndex(user1, 100);
  }

  /// @notice Test tokensOfOwner
  function testTokensOfOwner() public {
    // Mint 5 NFTs to user1
    _mintNFTsToUser(user1, 5);
    
    uint256[] memory tokens = morse.tokensOfOwner(user1);
    
    assertEq(tokens.length, 5, "Should return 5 tokens");
    
    // Verify all tokens are in range [1, 5]
    for (uint256 i = 0; i < tokens.length; i++) {
      assertTrue(tokens[i] >= 1 && tokens[i] <= 5, "Token should be in valid range");
    }
  }

  /// @notice Test tokensOfOwner with no tokens
  function testTokensOfOwner_Empty() public view {
    uint256[] memory tokens = morse.tokensOfOwner(user1);
    assertEq(tokens.length, 0, "Should return empty array");
  }

  /// @notice Test tokensOfOwner after transfer
  function testTokensOfOwner_AfterTransfer() public {
    // Mint 3 NFTs to user1
    _mintNFTsToUser(user1, 3);
    
    uint256[] memory user1Tokens = morse.tokensOfOwner(user1);
    assertEq(user1Tokens.length, 3, "User1 should have 3 tokens");
    
    // Transfer 1 NFT from user1 to user2
    address mirror = morse.mirrorERC721();
    uint256 tokenToTransfer = user1Tokens[0];
    
    vm.startPrank(user1);
    morse.setSkipNFT(false);
    IERC721(mirror).transferFrom(user1, user2, tokenToTransfer);
    vm.stopPrank();
    
    // Check balances
    uint256[] memory user1TokensAfter = morse.tokensOfOwner(user1);
    uint256[] memory user2Tokens = morse.tokensOfOwner(user2);
    
    assertEq(user1TokensAfter.length, 2, "User1 should have 2 tokens");
    assertEq(user2Tokens.length, 1, "User2 should have 1 token");
    assertEq(user2Tokens[0], tokenToTransfer, "User2 should have the transferred token");
  }

  /// @notice Test tokensOfOwner with large number of NFTs
  function testTokensOfOwner_LargeNumber() public {
    // Mint 20 NFTs
    _mintNFTsToUser(user1, 20);
    
    uint256[] memory tokens = morse.tokensOfOwner(user1);
    assertEq(tokens.length, 20, "Should return 20 tokens");
    
    // Verify all tokens are unique
    for (uint256 i = 0; i < tokens.length; i++) {
      for (uint256 j = i + 1; j < tokens.length; j++) {
        assertTrue(tokens[i] != tokens[j], "All tokens should be unique");
      }
    }
  }

  /// @notice Test that enumerable functions work after upgrade
  function testEnumerableFunctions_AfterUpgrade() public {
    // Mint some NFTs before upgrade
    _mintNFTsToUser(user1, 3);
    
    // Simulate upgrade
    address newImplementation = address(new xMorse(address(mailboxMitosis)));
    vm.prank(owner);
    morse.upgradeToAndCall(newImplementation, "");
    
    // Test that enumerable functions still work
    assertTrue(morse.supportsInterface(0x780e9d63), "Should support IERC721Enumerable after upgrade");
    
    uint256[] memory tokens = morse.tokensOfOwner(user1);
    assertEq(tokens.length, 3, "Should return correct number of tokens after upgrade");
    
    assertEq(morse.tokenByIndex(0), 1, "tokenByIndex should work after upgrade");
    morse.tokenOfOwnerByIndex(user1, 0);  // Should not revert
  }

  //====================================================================================//
  //================================== HELPER FUNCTIONS ================================//
  //====================================================================================//

  /// @dev Helper to mint NFTs to a user via bridge
  function _mintNFTsToUser(address user, uint256 count) internal {
    if (count == 0) return;
    
    // Setup bridge (idempotent, safe to call multiple times)
    vm.startPrank(owner);
    morse.setDestinationGas(DOMAIN_ETH, uint96(uint8(0)), 100_000);
    morse.enrollRemoteRouter(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))));
    vm.stopPrank();
    
    // Create message with count NFTs
    bytes memory message = abi.encodePacked(
      uint8(0), // MessageType.SendNFT
      bytes32(uint256(1)), // operationId
      user.addressToBytes32() // recipient
    );
    
    // Add token count
    message = abi.encodePacked(message, uint8(count));
    
    // Add token IDs (using sequential IDs for simplicity)
    // Use timestamp-based IDs to avoid conflicts between tests
    uint256 baseId = block.timestamp * 10000 + count * 100;
    for (uint256 i = 0; i < count; i++) {
      message = abi.encodePacked(message, bytes32(baseId + i));
    }
    
    vm.prank(address(mailboxMitosis));
    morse.handle(DOMAIN_ETH, bytes32(uint256(uint160(makeAddr('remoteRouter')))), message);
  }

  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }
}
