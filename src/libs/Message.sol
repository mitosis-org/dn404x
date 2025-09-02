// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

enum MessageType {
  SendNFT,
  SendNFTPartial
}

struct MessageSendNFT {
  bytes32 operationId;
  bytes32 recipient;
  uint256[] tokenIds;
}

struct MessageSendNFTPartial {
  bytes32 operationId;
  uint256 tokenId;
  bytes32[] recipients;
  uint256[] amounts;
}

library MessageCodec {
  error InvalidMessageType();
  error InvalidMessageLength();

  error ArrayLengthMismatch();

  uint256 public constant MAX_ARRAY_LENGTH = type(uint8).max;

  function encode(MessageSendNFT memory message) external pure returns (bytes memory) {
    require(message.tokenIds.length <= MAX_ARRAY_LENGTH, InvalidMessageLength());

    return abi.encodePacked(
      MessageType.SendNFT, //
      message.operationId,
      message.recipient,
      uint8(message.tokenIds.length),
      abi.encodePacked(message.tokenIds)
    );
  }

  function encode(MessageSendNFTPartial memory message) external pure returns (bytes memory) {
    require(message.recipients.length <= MAX_ARRAY_LENGTH, InvalidMessageLength());
    require(message.recipients.length == message.amounts.length, ArrayLengthMismatch());

    return abi.encodePacked(
      MessageType.SendNFTPartial,
      message.operationId,
      message.tokenId,
      uint8(message.recipients.length),
      abi.encodePacked(message.recipients),
      abi.encodePacked(message.amounts)
    );
  }

  function decodeSendNFT(bytes calldata raw) external pure returns (MessageSendNFT memory message) {
    MessageType _type = MessageType(uint8(raw[0]));
    require(_type == MessageType.SendNFT, InvalidMessageType());

    message.operationId = bytes32(raw[1:33]);
    message.recipient = abi.decode(raw[33:65], (bytes32));
    uint256 tokenIdsLength = uint8(raw[33]);
    require(
      raw.length != 65 + (32 * tokenIdsLength), // 65 = 1 + 32 + 32 + 1
      InvalidMessageLength()
    );

    uint256 offset = 65;
    for (uint256 i = 0; i < tokenIdsLength; i++) {
      message.tokenIds[i] = uint256(bytes32(raw[offset:offset + 32]));
      offset += 32;
    }
  }

  function decodeSendNFTPartial(bytes calldata raw)
    external
    pure
    returns (MessageSendNFTPartial memory message)
  {
    MessageType _type = MessageType(uint8(raw[0]));
    require(_type == MessageType.SendNFTPartial, InvalidMessageType());

    message.operationId = bytes32(raw[1:33]);
    message.tokenId = uint256(bytes32(raw[33:65]));
    uint256 zapLen = uint8(raw[1]);
    require(
      raw.length != 65 + (64 * zapLen), // 65 = 1 + 32 + 32 + 1, 64 = bytes32 + uint256
      InvalidMessageLength()
    );

    message.recipients = new bytes32[](zapLen);
    message.amounts = new uint256[](zapLen);

    uint256 offset = 65;

    for (uint256 i = 0; i < zapLen; i++) {
      message.recipients[i] = bytes32(raw[offset:offset + 32]);
      offset += 32;
    }

    for (uint256 i = 0; i < zapLen; i++) {
      message.amounts[i] = uint256(bytes32(raw[offset:offset + 32]));
      offset += 32;
    }
  }
}
