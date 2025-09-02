// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

interface IDN404Treasury {
  event WithdrawnNFT(bytes32 indexed recipient, uint256[] tokenIds);
  event WithdrawnNFTPartial(uint256 indexed tokenId, bytes32[] recipients, uint256[] amounts);

  function withdrawNFT(bytes32 recipient, uint256[] memory tokenIds) external;

  function withdrawNFTPartial(
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) external;
}
