// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IMulticall3 } from '@std/interfaces/IMulticall3.sol';

import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';

import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

library LibTransfer {
  using TypeCasts for *;

  error TotalAmountMustBeOne();

  function sendNFT(address token, bytes32 recipient, uint256[] memory tokenIds) internal {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      IERC721(token).safeTransferFrom(address(this), recipient.bytes32ToAddress(), tokenIds[i]);
    }
  }

  function sendNFTPartial(
    address token,
    IMulticall3 multicall,
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) internal {
    IERC721(token).approve(address(multicall), tokenId);
    uint256 multicallBalance = IERC20(token).balanceOf(address(multicall));

    IMulticall3.Call[] memory calls =
      new IMulticall3.Call[](recipients.length + 1 + multicallBalance > 0 ? 1 : 0);

    uint256 pointer = 0;

    if (multicallBalance > 0) {
      calls[pointer++] = IMulticall3.Call({
        target: address(token),
        callData: abi.encodeCall(
          IERC20.transfer, //
          (address(this), multicallBalance)
        )
      });
    }

    calls[pointer++] = IMulticall3.Call({
      target: address(token),
      callData: abi.encodeCall(
        // NOTE: we assume that the receiver have enough capability to handle the NFT
        IERC721.transferFrom,
        (address(this), address(multicall), tokenId)
      )
    });

    uint256 totalAmount = 0;
    for (uint256 i = 0; i < recipients.length; i++) {
      calls[pointer++] = IMulticall3.Call({
        target: address(token),
        callData: abi.encodeCall(
          IERC20.transfer, //
          (recipients[i].bytes32ToAddress(), amounts[i])
        )
      });
      totalAmount += amounts[i];
    }
    require(totalAmount == 10 ** IERC20Metadata(token).decimals(), TotalAmountMustBeOne());

    multicall.aggregate(calls);
  }
}
