// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { console2 } from '@std/console2.sol';

import {
  MessageType,
  MessageCodec,
  MessageSendNFT,
  MessageSendNFTPartial
} from '../../src/libs/Message.sol';

contract MessageCodecTest is Test {
  using MessageCodec for *;

  function testEncodeDecode_SendNFT_Single() public {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = 42;

    MessageSendNFT memory original = MessageSendNFT({
      operationId: bytes32(uint256(1)),
      recipient: bytes32(uint256(uint160(address(0x123)))),
      tokenIds: tokenIds
    });

    bytes memory encoded = MessageCodec.encode(original);
    
    // Verify message type
    assertEq(uint8(encoded[0]), uint8(MessageType.SendNFT));

    // Decode
    MessageSendNFT memory decoded = MessageCodec.decodeSendNFT(encoded);

    assertEq(decoded.operationId, original.operationId);
    assertEq(decoded.recipient, original.recipient);
    assertEq(decoded.tokenIds.length, original.tokenIds.length);
    assertEq(decoded.tokenIds[0], original.tokenIds[0]);
  }

  function testEncodeDecode_SendNFT_Multiple() public {
    uint256[] memory tokenIds = new uint256[](5);
    for (uint256 i = 0; i < 5; i++) {
      tokenIds[i] = i + 1;
    }

    MessageSendNFT memory original = MessageSendNFT({
      operationId: bytes32(uint256(999)),
      recipient: bytes32(uint256(uint160(address(0x456)))),
      tokenIds: tokenIds
    });

    bytes memory encoded = MessageCodec.encode(original);
    MessageSendNFT memory decoded = MessageCodec.decodeSendNFT(encoded);

    assertEq(decoded.operationId, original.operationId);
    assertEq(decoded.recipient, original.recipient);
    assertEq(decoded.tokenIds.length, original.tokenIds.length);
    
    for (uint256 i = 0; i < tokenIds.length; i++) {
      assertEq(decoded.tokenIds[i], original.tokenIds[i]);
    }
  }

  function testEncodeDecode_SendNFTPartial() public {
    bytes32[] memory recipients = new bytes32[](3);
    recipients[0] = bytes32(uint256(uint160(address(0x111))));
    recipients[1] = bytes32(uint256(uint160(address(0x222))));
    recipients[2] = bytes32(uint256(uint160(address(0x333))));

    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 0.5 ether;
    amounts[1] = 0.3 ether;
    amounts[2] = 0.2 ether;

    MessageSendNFTPartial memory original = MessageSendNFTPartial({
      operationId: bytes32(uint256(777)),
      tokenId: 123,
      recipients: recipients,
      amounts: amounts
    });

    bytes memory encoded = MessageCodec.encode(original);
    
    // Verify message type
    assertEq(uint8(encoded[0]), uint8(MessageType.SendNFTPartial));

    MessageSendNFTPartial memory decoded = MessageCodec.decodeSendNFTPartial(encoded);

    assertEq(decoded.operationId, original.operationId);
    assertEq(decoded.tokenId, original.tokenId);
    assertEq(decoded.recipients.length, original.recipients.length);
    assertEq(decoded.amounts.length, original.amounts.length);

    for (uint256 i = 0; i < recipients.length; i++) {
      assertEq(decoded.recipients[i], original.recipients[i]);
      assertEq(decoded.amounts[i], original.amounts[i]);
    }
  }

  function testEncode_SendNFT_MaxArrayLength() public {
    uint256[] memory tokenIds = new uint256[](255); // MAX_ARRAY_LENGTH
    for (uint256 i = 0; i < 255; i++) {
      tokenIds[i] = i;
    }

    MessageSendNFT memory message = MessageSendNFT({
      operationId: bytes32(uint256(1)),
      recipient: bytes32(uint256(uint160(address(0x123)))),
      tokenIds: tokenIds
    });

    // Should not revert
    bytes memory encoded = MessageCodec.encode(message);
    assertTrue(encoded.length > 0);
  }

  function testEncode_SendNFT_ExceedsMaxArrayLength() public {
    uint256[] memory tokenIds = new uint256[](256); // Exceeds MAX_ARRAY_LENGTH
    for (uint256 i = 0; i < 256; i++) {
      tokenIds[i] = i;
    }

    MessageSendNFT memory message = MessageSendNFT({
      operationId: bytes32(uint256(1)),
      recipient: bytes32(uint256(uint160(address(0x123)))),
      tokenIds: tokenIds
    });

    vm.expectRevert(MessageCodec.InvalidMessageLength.selector);
    MessageCodec.encode(message);
  }

  function testEncode_SendNFTPartial_ArrayLengthMismatch() public {
    bytes32[] memory recipients = new bytes32[](3);
    recipients[0] = bytes32(uint256(uint160(address(0x111))));
    recipients[1] = bytes32(uint256(uint160(address(0x222))));
    recipients[2] = bytes32(uint256(uint160(address(0x333))));

    uint256[] memory amounts = new uint256[](2); // Mismatch!
    amounts[0] = 0.5 ether;
    amounts[1] = 0.5 ether;

    MessageSendNFTPartial memory message = MessageSendNFTPartial({
      operationId: bytes32(uint256(777)),
      tokenId: 123,
      recipients: recipients,
      amounts: amounts
    });

    vm.expectRevert(MessageCodec.ArrayLengthMismatch.selector);
    MessageCodec.encode(message);
  }

  function testEncode_SendNFTPartial_ExceedsMaxArrayLength() public {
    bytes32[] memory recipients = new bytes32[](256);
    uint256[] memory amounts = new uint256[](256);
    
    for (uint256 i = 0; i < 256; i++) {
      recipients[i] = bytes32(uint256(i));
      amounts[i] = 1;
    }

    MessageSendNFTPartial memory message = MessageSendNFTPartial({
      operationId: bytes32(uint256(1)),
      tokenId: 1,
      recipients: recipients,
      amounts: amounts
    });

    vm.expectRevert(MessageCodec.InvalidMessageLength.selector);
    MessageCodec.encode(message);
  }

  function testDecode_SendNFT_InvalidMessageType() public {
    // Create a message with wrong type
    bytes memory invalidMessage = abi.encodePacked(
      MessageType.SendNFTPartial, // Wrong type!
      bytes32(uint256(1)),
      bytes32(uint256(2)),
      uint8(1),
      uint256(42)
    );

    vm.expectRevert(MessageCodec.InvalidMessageType.selector);
    MessageCodec.decodeSendNFT(invalidMessage);
  }

  function testDecode_SendNFTPartial_InvalidMessageType() public {
    // Create a message with wrong type
    bytes memory invalidMessage = abi.encodePacked(
      MessageType.SendNFT, // Wrong type!
      bytes32(uint256(1)),
      uint256(123),
      uint8(1),
      bytes32(uint256(1)),
      uint256(1 ether)
    );

    vm.expectRevert(MessageCodec.InvalidMessageType.selector);
    MessageCodec.decodeSendNFTPartial(invalidMessage);
  }
}

