// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';

contract Operation {
  using ERC7201Utils for string;

  //====================================================================================//
  //================================== STORAGE DEFINITION ==============================//
  //====================================================================================//

  struct OperationStorageV1 {
    mapping(bytes32 => uint256) nonce;
  }

  string private constant _NAMESPACE = 'mitosis.storage.libs.Operation';
  bytes32 private immutable _STORAGE_SLOT = _NAMESPACE.storageSlot();

  function _getOperationStorageV1() internal view returns (OperationStorageV1 storage $) {
    bytes32 slot = _STORAGE_SLOT;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  //====================================================================================//

  function getOperationNonce(bytes32 sender) external view returns (uint256) {
    return _operationNonce(sender);
  }

  function nextOperationId(bytes32 sender) external view returns (bytes32) {
    return _getOperationId(sender);
  }

  function _operationNonce(bytes32 sender) internal view virtual returns (uint256) {
    return _getOperationStorageV1().nonce[sender];
  }

  function _useOperationId(bytes32 sender) internal virtual returns (bytes32) {
    bytes32 operationId = _getOperationId(sender);
    _getOperationStorageV1().nonce[sender]++;
    return operationId;
  }

  function _getOperationId(bytes32 sender) internal view virtual returns (bytes32) {
    uint256 chainId = block.chainid;
    address self = address(this);
    uint256 nonce = _operationNonce(sender);
    bytes32 result;

    assembly {
      let ptr := mload(0x40)
      mstore(ptr, chainId)
      mstore(add(ptr, 0x20), shl(96, self))
      mstore(add(ptr, 0x40), sender)
      mstore(add(ptr, 0x60), nonce)
      result := keccak256(ptr, 0x80)
    }
    return result;
  }
}
