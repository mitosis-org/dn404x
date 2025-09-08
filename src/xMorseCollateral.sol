// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IMulticall3 } from '@std/interfaces/IMulticall3.sol';

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IERC721 } from '@oz/token/ERC721/IERC721.sol';
import { ERC721Holder } from '@oz/token/ERC721/utils/ERC721Holder.sol';

import { IMorse } from './interfaces/IMorse.sol';
import { LibTransfer } from './libs/LibTransfer.sol';
import { xDN404Base } from './xDN404Base.sol';

contract xMorseCollateral is Ownable2StepUpgradeable, UUPSUpgradeable, xDN404Base, ERC721Holder {
  address public immutable TOKEN;
  IMulticall3 public immutable MULTICALL;

  constructor(address token_, address _multicall, address _mailbox) xDN404Base(_mailbox) {
    TOKEN = token_;
    MULTICALL = IMulticall3(_multicall);

    // this contract need to have actual NFTs - to avoid misled burning of user's NFTs
    IMorse(TOKEN).setSkipNFT(false);
  }

  function initialize(address initialOwner, address _hook, address _ism) public initializer {
    __Ownable_init(initialOwner);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    _MailboxClient_initialize(_hook, _ism);
  }

  function _token() internal view override returns (address) {
    return TOKEN;
  }

  function _fetchNFT(address sender, uint256[] memory tokenIds) internal override {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      IERC721(TOKEN).safeTransferFrom(sender, address(this), tokenIds[i]);
    }
  }

  function _fetchNFTPartial(address sender, uint256 tokenId) internal override {
    IERC721(TOKEN).safeTransferFrom(sender, address(this), tokenId);
  }

  function _transferNFT(bytes32 recipient, uint256[] memory tokenIds) internal override {
    LibTransfer.sendNFT(
      TOKEN, //
      recipient,
      tokenIds
    );
  }

  function _transferNFTPartial(
    uint256 tokenId,
    bytes32[] memory recipients,
    uint256[] memory amounts
  ) internal override {
    LibTransfer.sendNFTPartial(
      TOKEN, //
      MULTICALL,
      tokenId,
      recipients,
      amounts
    );
  }

  function _authorizeUpgrade(address) internal override onlyOwner { }
  function _authorizeManageMailbox(address) internal override onlyOwner { }
  function _authorizeConfigureGas(address) internal override onlyOwner { }
  function _authorizeConfigureRoute(address) internal override onlyOwner { }
}
