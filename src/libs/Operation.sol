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
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getOperationStorageV1() internal view returns (OperationStorageV1 storage $) {
    bytes32 slot = _slot;
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
    return keccak256(
      abi.encodePacked(
        block.chainid, //
        address(this),
        sender,
        _operationNonce(sender)
      )
    );
  }
}
