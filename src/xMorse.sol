// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { DN404 } from '@dn404/DN404.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '@mitosis/external/hyperlane/GasRouter.sol';
import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';

import { IERC721 } from '@oz/interfaces/IERC721.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { xDN404Base } from './xDN404Base.sol';
import { xDN404Treasury } from './xDN404Treasury.sol';

/// @dev xMorse uses "forced collateral" mode, that means entire supply will be minted to treasury in initializing phase
contract xMorse is DN404, Ownable2StepUpgradeable, GasRouter, UUPSUpgradeable, xDN404Base {
  using ERC7201Utils for string;

  //====================================================================================//
  //================================== STORAGE DEFINITION ==============================//
  //====================================================================================//

  struct StorageV1 {
    string name;
    string symbol;
    uint8 decimals;
    string baseURI;
    //
    address treasury;
    bool initializing;
    uint256 initialTokenSupply;
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

  event Finalized();

  error TreasuryBalanceDoesNotMatchInitialTokenSupply();
  error TreasurySkipNFTIsNotSet();

  constructor(address _mailbox) xDN404Base(_mailbox) { }

  function initialize(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    address _multicall,
    uint256 _initialTokenSupply,
    address _initialOwner,
    address _hook,
    address _ism
  ) public initializer {
    __Ownable_init(_initialOwner);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    _MailboxClient_initialize(_hook, _ism);

    // initial supply goes to initial owner
    // initial owner must send all of supply to treasury to enable this contract
    address mirror = address(new DN404Mirror(_msgSender()));
    _initializeDN404(_initialTokenSupply, _initialOwner, mirror);

    address treasury = address(new xDN404Treasury(address(this), _multicall));

    StorageV1 storage $ = _getStorageV1();
    $.name = _name;
    $.symbol = _symbol;
    $.decimals = _decimals;
    $.treasury = treasury;

    $.initializing = true;
    $.initialTokenSupply = _initialTokenSupply;
  }

  function name() public view override returns (string memory) {
    return _getStorageV1().name;
  }

  function symbol() public view override returns (string memory) {
    return _getStorageV1().symbol;
  }

  function baseURI() public view returns (string memory) {
    return _getStorageV1().baseURI;
  }

  function _token() internal view override returns (address) {
    return address(this);
  }

  function _tokenURI(uint256 tokenId) internal view override returns (string memory result) {
    require(_exists(tokenId), TokenDoesNotExist());

    string memory _baseUri = _getStorageV1().baseURI;
    if (bytes(_baseUri).length != 0) {
      result = LibString.replace(_baseUri, '{id}', LibString.toString(tokenId));
    }
  }

  function finalize() external onlyOwner {
    StorageV1 storage $ = _getStorageV1();

    address treasury = $.treasury;

    uint256 treasuryBalance = this.balanceOf(treasury);
    require(
      !this.getSkipNFT(treasury), // treasury must not skip NFT minting
      TreasurySkipNFTIsNotSet()
    );
    require(
      treasuryBalance == $.initialTokenSupply, // and also balance must match initial token supply
      TreasuryBalanceDoesNotMatchInitialTokenSupply()
    );

    $.initializing = false;

    emit Finalized();
  }

  function _fetchNFT(address sender, uint256[] memory tokenIds) internal override {
    address treasury = _getStorageV1().treasury;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      IERC721(address(this)).safeTransferFrom(sender, treasury, tokenIds[i]);
    }
  }

  function _fetchNFTPartial(address sender, uint256 tokenId) internal override {
    address treasury = _getStorageV1().treasury;
    IERC721(address(this)).safeTransferFrom(sender, treasury, tokenId);
  }

  function _transferNFT(bytes32 recipient, uint256[] memory tokenIds) internal override {
    xDN404Treasury(_getStorageV1().treasury).withdrawNFT(
      recipient, //
      tokenIds
    );
  }

  function _transferNFTPartial(
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) internal override {
    xDN404Treasury(_getStorageV1().treasury).withdrawNFTPartial(
      tokenId, //
      recipients,
      amounts
    );
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
  function _authorizeManageMailbox(address) internal override onlyOwner { }
  function _authorizeConfigureGas(address) internal override onlyOwner { }
  function _authorizeConfigureRoute(address) internal override onlyOwner { }
}
