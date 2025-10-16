// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { DN404 } from '@dn404/DN404.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';

/// @dev Mock DN404 token for testing purposes
/// Includes additional features for test verification
contract MockDN404 is DN404 {
  string private _name;
  string private _symbol;
  uint8 private _decimals;

  struct TransferLog {
    address from;
    address to;
    uint256 id;
  }

  TransferLog[] private _transferLogs;

  constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply) {
    _name = name_;
    _symbol = symbol_;
    _decimals = decimals_;

    address mirror = address(new DN404Mirror(msg.sender));
    _initializeDN404(initialSupply, msg.sender, mirror);
  }

  function name() public view override returns (string memory) {
    return _name;
  }

  function symbol() public view override returns (string memory) {
    return _symbol;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  function _tokenURI(uint256) internal pure override returns (string memory) {
    return '';
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(address from, uint256 amount) external {
    _burn(from, amount);
  }

  function logTransfer(address from, address to, uint256 id) external {
    _transferLogs.push(TransferLog({ from: from, to: to, id: id }));
  }

  function getTransferLogs() external view returns (TransferLog[] memory) {
    return _transferLogs;
  }

  function clearTransferLogs() external {
    delete _transferLogs;
  }

  function getTransferLogsCount() external view returns (uint256) {
    return _transferLogs.length;
  }
}

