// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { DN404 } from '@dn404/DN404.sol';
import { DN404Mirror } from '@dn404/DN404Mirror.sol';
import { Ownable } from '@solady/auth/Ownable.sol';
import { LibString } from '@solady/utils/LibString.sol';
import { SafeTransferLib } from '@solady/utils/SafeTransferLib.sol';
import { IMorse } from '../interfaces/IMorse.sol';

/**
 * @title tMorseDN404
 * @notice Test DN404 token for Sepolia that implements IMorse interface
 * @dev Used for testing cross-chain transfers with xMorseCollateral
 * DN404 already implements IDN404, so we only need to add IMorse-specific methods
 */
contract tMorseDN404 is DN404, Ownable {
  string private _name;
  string private _symbol;
  string private _baseURI;

  constructor(
    string memory name_,
    string memory symbol_,
    uint96 initialTokenSupply,
    address initialSupplyOwner
  ) {
    _initializeOwner(msg.sender);
    _name = name_;
    _symbol = symbol_;

    address mirror = address(new DN404Mirror(msg.sender));
    _initializeDN404(initialTokenSupply, initialSupplyOwner, mirror);
  }

  function name() public view override returns (string memory) {
    return _name;
  }

  function symbol() public view override returns (string memory) {
    return _symbol;
  }

  function _tokenURI(uint256 tokenId) internal view override returns (string memory result) {
    if (bytes(_baseURI).length != 0) {
      result = string(abi.encodePacked(_baseURI, LibString.toString(tokenId)));
    }
  }

  // This allows the owner of the contract to mint more tokens.
  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

  function setBaseURI(string calldata baseURI_) public onlyOwner {
    _baseURI = baseURI_;
  }

  function withdraw() public onlyOwner {
    SafeTransferLib.safeTransferAllETH(msg.sender);
  }

  // IMorse interface implementation
  function getCurrentTransferLogs() external view returns (IMorse.DN404TransferLog[] memory) {
    // For testing purposes, return empty array
    // In production, this would track transfer logs
    return new IMorse.DN404TransferLog[](0);
  }

  function getCurrentTransferLogsCount() external view returns (uint256) {
    // For testing purposes, return 0
    return 0;
  }
}

