// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IMulticall3 } from '@std/interfaces/IMulticall3.sol';

import { GasRouter } from '@mitosis/external/hyperlane/GasRouter.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { StandardHookMetadata } from '@hpl/hooks/libs/StandardHookMetadata.sol';
import { Quote } from '@hpl/interfaces/ITokenBridge.sol';
import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';
import { ERC721Holder } from '@oz/token/ERC721/utils/ERC721Holder.sol';

import { IMorse } from './interfaces/IMorse.sol';
import { LibTransfer } from './libs/LibTransfer.sol';
import {
  MessageType, MessageCodec, MessageSendNFT, MessageSendNFTPartial
} from './libs/Message.sol';

contract xMorseCollateral is Ownable2StepUpgradeable, GasRouter, UUPSUpgradeable, ERC721Holder {
  using SafeERC20 for IERC20Metadata;
  using TypeCasts for *;
  using MessageCodec for *;

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

  error InvalidMessageType();
  error TotalAmountMustBeOne();

  uint256 public constant TRANSFER_ERC20 = 25_000;
  uint256 public constant TRANSFER_ERC721 = 50_000;

  address public immutable token;
  IMulticall3 public immutable multicall;

  constructor(address _token, address _multicall, address _mailbox) GasRouter(_mailbox) {
    token = _token;
    multicall = IMulticall3(_multicall);

    // this contract need to have actual NFTs - to avoid misled burning of user's NFTs
    IMorse(token).setSkipNFT(false);
  }

  function initialize(address initialOwner, address _hook, address _ism) public initializer {
    __Ownable_init(initialOwner);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    _MailboxClient_initialize(_hook, _ism);
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
    for (uint256 i = 0; i < tokenIds.length; i++) {
      IERC721(token).safeTransferFrom(_msgSender(), address(this), tokenIds[i]);
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
    require(totalAmount == 10 ** IERC20Metadata(token).decimals(), TotalAmountMustBeOne());

    IERC721(token).safeTransferFrom(_msgSender(), address(this), tokenId);

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

      LibTransfer.sendNFT(
        token, //
        message.recipient,
        message.tokenIds
      );

      return;
    }

    if (_type == MessageType.SendNFTPartial) {
      MessageSendNFTPartial memory message = _message.decodeSendNFTPartial();

      LibTransfer.sendNFTPartial(
        token, //
        multicall,
        message.tokenId,
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
