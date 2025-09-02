// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { StandardHookMetadata } from '@hpl/hooks/libs/StandardHookMetadata.sol';
import { Quote } from '@hpl/interfaces/ITokenBridge.sol';
import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';

import { GasRouter } from '@mitosis/external/hyperlane/GasRouter.sol';

import { IxDN404 } from './interfaces/IxDN404.sol';
import {
  MessageType, MessageCodec, MessageSendNFT, MessageSendNFTPartial
} from './libs/Message.sol';
import { Operation } from './libs/Operation.sol';

abstract contract xDN404Base is IxDN404, GasRouter, ReentrancyGuard, Operation {
  using TypeCasts for *;
  using MessageCodec for *;

  event TransferRemoteNFT(
    bytes32 indexed operationId,
    uint32 indexed destination,
    bytes32 indexed recipient,
    bytes32 messageId,
    uint256[] tokenIds,
    uint256 gasLimit
  );

  event TransferRemoteNFTPartial(
    bytes32 indexed operationId,
    uint32 indexed destination,
    bytes32 messageId,
    bytes32[] recipients,
    uint256[] amounts,
    uint256 gasLimit
  );

  event ReceivedNFT(bytes32 indexed operationId, bytes32 indexed recipient, uint256[] tokenIds);

  event ReceivedNFTPartial(
    bytes32 indexed operationId, uint256 indexed tokenId, bytes32[] recipients, uint256[] amounts
  );

  error InvalidMessageType();
  error TotalAmountMustBeOne();

  uint256 public constant TRANSFER_ERC20 = 25_000;
  uint256 public constant TRANSFER_ERC721 = 50_000;

  constructor(address _mailbox) GasRouter(_mailbox) { }

  function quoteTransferRemoteNFT(uint32 destination, bytes32 recipient, uint256[] memory tokenIds)
    external
    view
    virtual
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
        MessageSendNFT({
          operationId: _getOperationId(_msgSender().addressToBytes32()),
          recipient: recipient,
          tokenIds: tokenIds
        }).encode(),
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
  ) external view virtual returns (Quote[] memory quotes) {
    uint96 messageType = uint96(uint8(MessageType.SendNFTPartial));
    uint256 baseGasLimit = _getHplGasRouterStorage().destinationGas[destination][messageType];
    uint256 gasLimit = baseGasLimit + recipients.length * TRANSFER_ERC20;

    quotes = new Quote[](1);
    quotes[0] = Quote({
      token: address(0),
      amount: _Router_quoteDispatch(
        destination,
        MessageSendNFTPartial({
          operationId: _getOperationId(_msgSender().addressToBytes32()),
          tokenId: tokenId,
          recipients: recipients,
          amounts: amounts
        }).encode(),
        StandardHookMetadata.overrideGasLimit(gasLimit),
        address(hook())
      )
    });
  }

  function transferRemoteNFT(uint32 destination, bytes32 recipient, uint256[] memory tokenIds)
    external
    payable
    virtual
    nonReentrant
  {
    _fetchNFT(_msgSender(), tokenIds);

    bytes32 operationId = _getOperationId(_msgSender().addressToBytes32());
    bytes memory message = MessageSendNFT({
      operationId: operationId,
      recipient: recipient,
      tokenIds: tokenIds
    }).encode();

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

    emit TransferRemoteNFT(
      operationId, //
      destination,
      recipient,
      messageId,
      tokenIds,
      gasLimit
    );
  }

  function transferRemoteNFTPartial(
    uint32 destination,
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) external payable virtual nonReentrant {
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < amounts.length; i++) {
      totalAmount += amounts[i];
    }
    require(totalAmount == 10 ** IERC20Metadata(_token()).decimals(), TotalAmountMustBeOne());

    _fetchNFTPartial(_msgSender(), tokenId);

    bytes32 operationId = _getOperationId(_msgSender().addressToBytes32());
    bytes memory message = MessageSendNFTPartial({
      operationId: operationId,
      tokenId: tokenId,
      recipients: recipients,
      amounts: amounts
    }).encode();

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

    emit TransferRemoteNFTPartial(
      operationId, //
      destination,
      messageId,
      recipients,
      amounts,
      gasLimit
    );
  }

  function _handle(uint32, bytes32, bytes calldata _message) internal override {
    MessageType _type = MessageType(uint8(_message[0]));

    if (_type == MessageType.SendNFT) {
      MessageSendNFT memory message = _message.decodeSendNFT();

      _transferNFT(message.recipient, message.tokenIds);

      emit ReceivedNFT(
        message.operationId, //
        message.recipient,
        message.tokenIds
      );

      return;
    }

    if (_type == MessageType.SendNFTPartial) {
      MessageSendNFTPartial memory message = _message.decodeSendNFTPartial();

      _transferNFTPartial(message.tokenId, message.recipients, message.amounts);

      emit ReceivedNFTPartial(
        message.operationId, //
        message.tokenId,
        message.recipients,
        message.amounts
      );

      return;
    }

    revert InvalidMessageType();
  }

  function _token() internal view virtual returns (address);

  function _fetchNFT(address sender, uint256[] memory tokenIds) internal virtual;

  function _fetchNFTPartial(address sender, uint256 tokenId) internal virtual;

  function _transferNFT(bytes32 recipient, uint256[] memory tokenIds) internal virtual;

  function _transferNFTPartial(
    uint256 tokenId,
    bytes32[] memory recipient,
    uint256[] memory tokenIds
  ) internal virtual;
}
