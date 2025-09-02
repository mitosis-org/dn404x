// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IDN404 } from './IDN404.sol';

interface IMorse is IDN404 {
  struct DN404TransferLog {
    address from;
    address to;
    uint256 id;
  }

  function getCurrentTransferLogs() external view returns (DN404TransferLog[] memory);

  function getCurrentTransferLogsCount() external view returns (uint256);
}
