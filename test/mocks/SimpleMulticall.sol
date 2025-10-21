// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @dev Simple multicall for testing - implements only what we need
contract SimpleMulticall {
  struct Call {
    address target;
    bytes callData;
  }

  function aggregate(Call[] calldata calls) external payable returns (uint256, bytes[] memory) {
    bytes[] memory results = new bytes[](calls.length);
    for (uint256 i = 0; i < calls.length; i++) {
      (bool success, bytes memory result) = calls[i].target.call(calls[i].callData);
      require(success, 'Multicall: call failed');
      results[i] = result;
    }
    return (block.number, results);
  }
}

