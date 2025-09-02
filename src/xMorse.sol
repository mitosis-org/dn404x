// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { DN404 } from '@dn404/DN404.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { GasRouter } from '@mitosis/external/hyperlane/GasRouter.sol';
import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';

import { StandardHookMetadata } from '@hpl/hooks/libs/StandardHookMetadata.sol';
import { Quote } from '@hpl/interfaces/ITokenBridge.sol';

import { IERC721 } from '@oz/interfaces/IERC721.sol';
import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';

import { LibString } from '@solady/utils/LibString.sol';

import { DN404Treasury } from './DN404Treasury.sol';
import { IDN404Treasury } from './interfaces/IDN404Treasury.sol';
import { IMorse } from './interfaces/IMorse.sol';
import { LibTransfer } from './libs/LibTransfer.sol';
import {
  MessageType, MessageCodec, MessageSendNFT, MessageSendNFTPartial
} from './libs/Message.sol';

/// @dev xMorse uses "forced collateral" mode, that means entire supply will be minted to treasury in initializing phase
contract xMorse is DN404, Ownable2StepUpgradeable, GasRouter, UUPSUpgradeable {
  using ERC7201Utils for string;
  using MessageCodec for *;

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
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  //====================================================================================//

  event TransferRemoteNFT(
    bytes32 indexed messageId,
    uint32 indexed destination,
    bytes32 indexed recipient,
    uint256[] tokenIds,
    uint256 gasLimit
  );

  event TransferRemoteNFTPartial(
    bytes32 indexed messageId,
    uint32 indexed destination,
    bytes32[] recipients,
    uint256[] amounts,
    uint256 gasLimit
  );

  event Finalized();

  error InvalidMessageType();
  error TotalAmountMustBeOne();
  error TreasuryBalanceDoesNotMatchInitialTokenSupply();
  error TreasurySkipNFTIsNotSet();

  uint256 public constant TRANSFER_ERC20 = 25_000;
  uint256 public constant TRANSFER_ERC721 = 50_000;

  constructor(address _mailbox) GasRouter(_mailbox) { }

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

    address treasury = address(new DN404Treasury(address(this), _multicall));

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

  function _tokenURI(uint256 tokenId) internal view override returns (string memory result) {
    require(_exists(tokenId), TokenDoesNotExist());

    string memory _baseURI = _getStorageV1().baseURI;
    if (bytes(_baseURI).length != 0) {
      result = LibString.replace(_baseURI, '{id}', LibString.toString(tokenId));
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

  function quoteTransferRemoteNFT(uint32 destination, bytes32 recipient, uint256[] memory tokenIds)
    external
    view
    returns (Quote[] memory quotes)
  {
    uint96 messageType = uint96(uint8(MessageType.SendNFT));
    uint256 baseGasLimit = _getHplGasRouterStorage().destinationGas[destination][messageType];
    uint256 gasLimit = baseGasLimit + tokenIds.length * TRANSFER_ERC721;

    quotes = new Quote[](1);
    quotes[0] = Quote({
      token: address(0),
      amount: _Router_quoteDispatch(
        destination,
        MessageSendNFT({ recipient: recipient, tokenIds: tokenIds }).encode(),
        StandardHookMetadata.overrideGasLimit(gasLimit),
        address(hook())
      )
    });
  }

  function quoteTransferRemoteNFTPartial(
    uint32 destination,
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) external view returns (Quote[] memory quotes) {
    uint96 messageType = uint96(uint8(MessageType.SendNFTPartial));
    uint256 baseGasLimit = _getHplGasRouterStorage().destinationGas[destination][messageType];
    uint256 gasLimit = baseGasLimit + recipients.length * TRANSFER_ERC20;

    quotes = new Quote[](1);
    quotes[0] = Quote({
      token: address(0),
      amount: _Router_quoteDispatch(
        destination,
        MessageSendNFTPartial({ tokenId: tokenId, recipients: recipients, amounts: amounts }).encode(),
        StandardHookMetadata.overrideGasLimit(gasLimit),
        address(hook())
      )
    });
  }

  function transferRemoteNFT(uint32 destination, bytes32 recipient, uint256[] memory tokenIds)
    external
    payable
  {
    address treasury = _getStorageV1().treasury;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      IERC721(address(this)).safeTransferFrom(_msgSender(), treasury, tokenIds[i]);
    }

    bytes memory message = MessageSendNFT({ recipient: recipient, tokenIds: tokenIds }).encode();

    uint96 messageType = uint96(uint8(MessageType.SendNFT));
    uint256 baseGasLimit = _getHplGasRouterStorage().destinationGas[destination][messageType];
    uint256 gasLimit = baseGasLimit + tokenIds.length * TRANSFER_ERC721;

    bytes32 messageId = _Router_dispatch(
      destination,
      msg.value,
      message,
      StandardHookMetadata.overrideGasLimit(gasLimit),
      address(hook())
    );

    emit TransferRemoteNFT(messageId, destination, recipient, tokenIds, gasLimit);
  }

  function transferRemoteNFTPartial(
    uint32 destination,
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) external payable {
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < amounts.length; i++) {
      totalAmount += amounts[i];
    }
    require(totalAmount == 10 ** this.decimals(), TotalAmountMustBeOne());

    IERC721(address(this)).safeTransferFrom(_msgSender(), _getStorageV1().treasury, tokenId);

    bytes memory message =
      MessageSendNFTPartial({ tokenId: tokenId, recipients: recipients, amounts: amounts }).encode();

    uint96 messageType = uint96(uint8(MessageType.SendNFTPartial));
    uint256 baseGasLimit = _getHplGasRouterStorage().destinationGas[destination][messageType];
    uint256 gasLimit = baseGasLimit + recipients.length * TRANSFER_ERC20;

    bytes32 messageId = _Router_dispatch(
      destination,
      msg.value,
      message,
      StandardHookMetadata.overrideGasLimit(gasLimit),
      address(hook())
    );

    emit TransferRemoteNFTPartial(messageId, destination, recipients, amounts, gasLimit);
  }

  function _handle(uint32, bytes32, bytes calldata _message) internal override {
    MessageType _type = MessageType(uint8(_message[0]));

    if (_type == MessageType.SendNFT) {
      MessageSendNFT memory message = _message.decodeSendNFT();

      IDN404Treasury(_getStorageV1().treasury).withdrawNFT(
        message.recipient, //
        message.tokenIds
      );

      return;
    }

    if (_type == MessageType.SendNFTPartial) {
      MessageSendNFTPartial memory message = _message.decodeSendNFTPartial();

      IDN404Treasury(_getStorageV1().treasury).withdrawNFTPartial(
        message.tokenId, //
        message.recipients,
        message.amounts
      );

      return;
    }

    revert InvalidMessageType();
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
  function _authorizeManageMailbox(address) internal override onlyOwner { }
  function _authorizeConfigureGas(address) internal override onlyOwner { }
  function _authorizeConfigureRoute(address) internal override onlyOwner { }
}
