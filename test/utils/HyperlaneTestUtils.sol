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
    hookEth.setFee(0.01 ether); // Set a reasonable fee for testing
    mailboxEth.setDefaultHook(address(hookEth));
    mailboxEth.setRequiredHook(address(hookEth));

    // Setup Mitosis side
    mailboxMitosis = new TestMailbox(DOMAIN_MITOSIS);
    igpMitosis = new TestInterchainGasPaymaster();
    hookMitosis = new TestPostDispatchHook();
    hookMitosis.setFee(0.01 ether); // Set a reasonable fee for testing
    mailboxMitosis.setDefaultHook(address(hookMitosis));
    mailboxMitosis.setRequiredHook(address(hookMitosis));
  }

  /// @dev Process all pending messages from source mailbox to destination
  /// Note: This requires the mailboxes to be configured with addRemoteMailbox
  /// For TestMailbox, we need to manually process dispatched messages
  function relayMessages(TestMailbox source, TestMailbox destination) internal {
    // TestMailbox doesn't auto-process messages like MockMailbox
    // We need to extract dispatched message and call process() on destination
    // For now, this is a simplified implementation
    // In a real test, you'd capture the Dispatch event and process it
    
    // This is intentionally empty because TestMailbox doesn't provide
    // easy access to dispatched messages. For full integration tests,
    // consider using MockMailbox instead, or manually capture Dispatch events
    // and call destination.process(metadata, message)
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

