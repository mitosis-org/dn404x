// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Quote } from '@hpl/interfaces/ITokenBridge.sol';

interface IxDN404 {
  function quoteTransferRemoteNFT(uint32 destination, bytes32 recipient, uint256[] memory tokenIds)
    external
    view
    returns (Quote[] memory);

  function quoteTransferRemoteNFTPartial(
    uint32 destination,
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) external view returns (Quote[] memory);

  function transferRemoteNFT(uint32 destination, bytes32 recipient, uint256[] memory tokenIds)
    external
    payable;

  function transferRemoteNFTPartial(
    uint32 destination,
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) external payable;
}
