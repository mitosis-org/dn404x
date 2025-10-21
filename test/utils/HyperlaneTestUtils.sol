// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Test } from '@std/Test.sol';
import { TestMailbox } from '@hpl/test/TestMailbox.sol';
import { TestPostDispatchHook } from '@hpl/test/TestPostDispatchHook.sol';
import { TestInterchainGasPaymaster } from '@hpl/test/TestInterchainGasPaymaster.sol';
import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

/// @dev Hyperlane test utilities for cross-chain message simulation
abstract contract HyperlaneTestUtils is Test {
  using TypeCasts for address;

  TestMailbox public mailboxEth;
  TestMailbox public mailboxMitosis;
  TestPostDispatchHook public hookEth;
  TestPostDispatchHook public hookMitosis;
  TestInterchainGasPaymaster public igpEth;
  TestInterchainGasPaymaster public igpMitosis;

  uint32 public constant DOMAIN_ETH = 1;
  uint32 public constant DOMAIN_MITOSIS = 2;

  function setupHyperlane() internal {
    // Setup Ethereum side
    mailboxEth = new TestMailbox(DOMAIN_ETH);
    igpEth = new TestInterchainGasPaymaster();
    hookEth = new TestPostDispatchHook();

    // Setup Mitosis side
    mailboxMitosis = new TestMailbox(DOMAIN_MITOSIS);
    igpMitosis = new TestInterchainGasPaymaster();
    hookMitosis = new TestPostDispatchHook();
  }

  /// @dev Process all pending messages from source mailbox
  function relayMessages(TestMailbox source, TestMailbox destination) internal {
    // TestMailbox processes messages internally
    // In test environment, messages are auto-processed
    // This is a placeholder for more complex relay scenarios
  }

  /// @dev Get the latest message ID from mailbox
  function getLatestMessageId(TestMailbox mailbox) internal view returns (bytes32) {
    return mailbox.latestDispatchedId();
  }

  /// @dev Helper to convert address to bytes32
  function addressToBytes32(address addr) internal pure returns (bytes32) {
    return addr.addressToBytes32();
  }

  /// @dev Helper to convert bytes32 to address
  function bytes32ToAddress(bytes32 data) internal pure returns (address) {
    return TypeCasts.bytes32ToAddress(data);
  }
}

