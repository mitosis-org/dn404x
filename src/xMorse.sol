// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { DN404 } from '@dn404/DN404.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '@mitosis/external/hyperlane/GasRouter.sol';
import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';
import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { IERC721 } from '@oz/token/ERC721/IERC721.sol';
import { ERC721Holder } from '@oz/token/ERC721/utils/ERC721Holder.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { xDN404Base } from './xDN404Base.sol';

/// @title xMorse
/// @notice Mitosis-side bridge contract for Morse NFTs
/// @dev Uses mint/burn pattern - mints when receiving from Ethereum, burns when sending back
contract xMorse is DN404, Ownable2StepUpgradeable, GasRouter, UUPSUpgradeable, xDN404Base, ERC721Holder {
  using ERC7201Utils for string;
  using TypeCasts for bytes32;

  //====================================================================================//
  //================================== STORAGE DEFINITION ==============================//
  //====================================================================================//

  struct StorageV1 {
    string name;
    string symbol;
    uint8 decimals;
    string baseURI;
    // Token ID mapping: mitosis tokenId => ethereum tokenId
    mapping(uint256 => uint256) mitosisToEthereumId;
    // Reverse mapping: ethereum tokenId => mitosis tokenId
    mapping(uint256 => uint256) ethereumToMitosisId;
    // Pending mappings: for tracking ethereum tokenIds to be mapped after mint
    uint256[] pendingEthereumTokenIds;
    bytes32 pendingRecipient;
  }

  string private constant _NAMESPACE = 'mitosis.storage.xMorse';
  bytes32 private immutable _STORAGE_SLOT = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _STORAGE_SLOT;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  //====================================================================================//

  event TokenIdMapped(uint256 indexed mitosisTokenId, uint256 indexed ethereumTokenId);

  error TokenIdArrayLengthMismatch();
  error PartialTransfersNotSupported();

  constructor(address _mailbox) xDN404Base(_mailbox) { }

  function initialize(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    string memory _baseURI,
    address _initialOwner,
    address _hook,
    address _ism,
    address _mirror
  ) public initializer {
    // 1. Initialize ownership with msg.sender first (for _MailboxClient_initialize)
    __Ownable_init(_msgSender());
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    // 2. Now msg.sender is owner, so _MailboxClient_initialize succeeds
    _MailboxClient_initialize(_hook, _ism);

    // 3. Initialize DN404 with zero initial supply (mint on demand)
    _initializeDN404(0, address(this), _mirror);

    // 4. Set this contract to skip NFT minting
    // This ensures NFTs transferred to this contract are automatically burned
    _setSkipNFT(address(this), true);

    // 5. Store metadata
    StorageV1 storage $ = _getStorageV1();
    $.name = _name;
    $.symbol = _symbol;
    $.decimals = _decimals;
    $.baseURI = _baseURI;

    // 6. Transfer ownership to the intended initial owner
    if (_initialOwner != _msgSender()) {
      _transferOwnership(_initialOwner);
    }
  }

  function name() public view override returns (string memory) {
    return _getStorageV1().name;
  }

  function symbol() public view override returns (string memory) {
    return _getStorageV1().symbol;
  }

  function decimals() public view override returns (uint8) {
    return _getStorageV1().decimals;
  }

  function baseURI() public view returns (string memory) {
    return _getStorageV1().baseURI;
  }

  function setBaseURI(string memory _baseURI) external onlyOwner {
    _getStorageV1().baseURI = _baseURI;
  }

  /// @notice Get Ethereum token ID from Mitosis token ID
  function getEthereumTokenId(uint256 mitosisTokenId) public view returns (uint256) {
    return _getStorageV1().mitosisToEthereumId[mitosisTokenId];
  }

  /// @notice Get Mitosis token ID from Ethereum token ID
  function getMitosisTokenId(uint256 ethereumTokenId) public view returns (uint256) {
    return _getStorageV1().ethereumToMitosisId[ethereumTokenId];
  }

  function _token() internal view override returns (address) {
    return address(this);
  }

  function _tokenURI(uint256 tokenId) internal view override returns (string memory result) {
    require(_exists(tokenId), TokenDoesNotExist());

    StorageV1 storage $ = _getStorageV1();
    string memory _baseUri = $.baseURI;
    if (bytes(_baseUri).length != 0) {
      // Use the mapped Ethereum token ID if it exists, otherwise use Mitosis token ID
      uint256 ethereumTokenId = $.mitosisToEthereumId[tokenId];
      uint256 displayTokenId = ethereumTokenId != 0 ? ethereumTokenId : tokenId;
      result = LibString.replace(_baseUri, '{id}', LibString.toString(displayTokenId));
    }
  }

  //====================================================================================//
  //================================== BRIDGE FUNCTIONS ================================//
  //====================================================================================//

  /// @dev Called when receiving NFTs from Ethereum - burns sender's NFTs
  /// In Mitosis->Ethereum direction, user calls this to send NFTs back
  /// Transfers specific tokenIds from sender, which triggers DN404 to burn those exact NFTs
  function _fetchNFT(address sender, uint256[] memory tokenIds) internal override {
    StorageV1 storage $ = _getStorageV1();
    address mirror = mirrorERC721();
    
    // Clean up mappings for NFTs being burned
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 mitosisTokenId = tokenIds[i];
      uint256 ethereumTokenId = $.mitosisToEthereumId[mitosisTokenId];
      
      // Clear bidirectional mappings
      if (ethereumTokenId != 0) {
        delete $.mitosisToEthereumId[mitosisTokenId];
        delete $.ethereumToMitosisId[ethereumTokenId];
      }
      
      // Transfer NFT to this contract (DN404 will auto-burn)
      IERC721(mirror).safeTransferFrom(sender, address(this), mitosisTokenId);
    }
  }

  /// @dev Partial transfers not supported in bridge mode
  function _fetchNFTPartial(address sender, uint256 tokenId) internal override {
    revert PartialTransfersNotSupported();
  }

  /// @dev Called when sending NFTs to Mitosis users (Ethereum->Mitosis)
  /// Mints new tokens to recipient
  function _transferNFT(bytes32 recipient, uint256[] memory tokenIds) internal override {
    StorageV1 storage $ = _getStorageV1();
    
    // Store pending mapping info
    $.pendingRecipient = recipient;
    delete $.pendingEthereumTokenIds; // Clear previous pending
    for (uint256 i = 0; i < tokenIds.length; i++) {
      $.pendingEthereumTokenIds.push(tokenIds[i]);
    }
    
    // Mint tokens to recipient (NFTs will be auto-created)
    // Each NFT requires 1 unit (10^decimals)
    address recipientAddr = recipient.bytes32ToAddress();
    uint256 amount = tokenIds.length * (10 ** $.decimals);
    _mint(recipientAddr, amount);
    
    // Mapping will be completed in _afterNFTTransfers
  }

  /// @dev Partial transfers not supported in bridge mode
  function _transferNFTPartial(
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) internal override {
    revert PartialTransfersNotSupported();
  }

  //====================================================================================//
  //================================== HOOKS ===========================================//
  //====================================================================================//

  /// @dev Override to enable _afterNFTTransfers hook
  function _useAfterNFTTransfers() internal pure override returns (bool) {
    return true;
  }

  /// @dev Hook called after NFT transfers to save token ID mappings
  function _afterNFTTransfers(
    address[] memory from,
    address[] memory to,
    uint256[] memory ids
  ) internal override {
    StorageV1 storage $ = _getStorageV1();
    
    // Only process if we have pending mappings
    uint256 pendingLength = $.pendingEthereumTokenIds.length;
    if (pendingLength == 0) {
      return;
    }
    
    // Find mints to the pending recipient
    address recipientAddr = $.pendingRecipient.bytes32ToAddress();
    uint256 mappingIndex = 0;
    
    for (uint256 i = 0; i < ids.length && mappingIndex < pendingLength; i++) {
      // Check if this is a mint (from == address(0)) to our pending recipient
      if (from[i] == address(0) && to[i] == recipientAddr) {
        uint256 mitosisTokenId = ids[i];
        uint256 ethereumTokenId = $.pendingEthereumTokenIds[mappingIndex];
        
        // Save bidirectional mapping
        $.mitosisToEthereumId[mitosisTokenId] = ethereumTokenId;
        $.ethereumToMitosisId[ethereumTokenId] = mitosisTokenId;
        
        emit TokenIdMapped(mitosisTokenId, ethereumTokenId);
        mappingIndex++;
      }
    }
    
    // Verify all mappings were saved before clearing
    require(mappingIndex == pendingLength, TokenIdArrayLengthMismatch());
    
    // Clear pending after processing
    delete $.pendingEthereumTokenIds;
    delete $.pendingRecipient;
  }

  //====================================================================================//
  //================================== ERC721 RECEIVER =================================//
  //====================================================================================//

  /// @dev Override to automatically burn tokens when NFT is received
  /// This ensures the bridge doesn't accumulate ERC20 balance
  function onERC721Received(address, address, uint256, bytes memory)
    public
    virtual
    override
    returns (bytes4)
  {
    // When NFT is transferred to this contract, DN404 automatically increases our ERC20 balance
    // We need to burn that balance to complete the burn process
    uint256 contractBalance = this.balanceOf(address(this));
    if (contractBalance > 0) {
      _burn(address(this), contractBalance);
    }
    return this.onERC721Received.selector;
  }

  //====================================================================================//
  //================================== AUTHORIZATION ===================================//
  //====================================================================================//

  function _authorizeUpgrade(address) internal override onlyOwner { }
  function _authorizeManageMailbox(address) internal override onlyOwner { }
  function _authorizeConfigureGas(address) internal override onlyOwner { }
  function _authorizeConfigureRoute(address) internal override onlyOwner { }
}
