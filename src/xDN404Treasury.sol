// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IMulticall3 } from '@std/interfaces/IMulticall3.sol';

import { Ownable } from '@oz/access/Ownable.sol';
import { ERC721Holder } from '@oz/token/ERC721/utils/ERC721Holder.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';

import { IMorse } from './interfaces/IMorse.sol';
import { LibTransfer } from './libs/LibTransfer.sol';

contract xDN404Treasury is Ownable, ERC721Holder, ReentrancyGuard {
  event WithdrawnNFT(bytes32 indexed recipient, uint256[] tokenIds);
  event WithdrawnNFTPartial(uint256 indexed tokenId, bytes32[] recipients, uint256[] amounts);

  address public immutable token;
  IMulticall3 public immutable multicall3;

  constructor(address _token, address _multicall3) Ownable(_msgSender()) {
    token = _token;
    multicall3 = IMulticall3(_multicall3);

    IMorse(token).setSkipNFT(false);
  }

  function withdrawNFT(bytes32 recipient, uint256[] memory tokenIds)
    external
    onlyOwner
    nonReentrant
  {
    LibTransfer.sendNFT(token, recipient, tokenIds);

    emit WithdrawnNFT(recipient, tokenIds);
  }

  function withdrawNFTPartial(
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) external nonReentrant onlyOwner {
    LibTransfer.sendNFTPartial(token, multicall3, tokenId, recipients, amounts);

    emit WithdrawnNFTPartial(tokenId, recipients, amounts);
  }
}
