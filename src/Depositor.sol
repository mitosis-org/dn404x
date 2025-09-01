// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Ownable } from '@oz/access/Ownable.sol';
import { IERC20Metadata } from '@oz/interfaces/IERC20Metadata.sol';
import { IERC2612 } from '@oz/interfaces/IERC2612.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Address } from '@oz/utils/Address.sol';

import { IMitosisVault } from '@mitosis/interfaces/branch/IMitosisVault.sol';

contract Depositor is Ownable {
  using SafeERC20 for IERC20Metadata;

  event Refunded(address indexed to, uint256 amount);
  event AllowanceSet(bytes4 sig, bool allowed);

  error FuncNotAllowed(bytes4 sig);

  IMitosisVault public immutable vault;
  IERC20Metadata public immutable token;

  mapping(bytes4 => bool) public allowed;

  constructor(address initialOwner, address vault_, address token_) Ownable(initialOwner) {
    vault = IMitosisVault(vault_);
    token = IERC20Metadata(token_);
  }

  modifier doRefund() {
    uint256 balanceBefore = token.balanceOf(address(this));

    _;

    uint256 balanceAfter = token.balanceOf(address(this));

    if (balanceAfter > balanceBefore) {
      uint256 refundAmount = balanceAfter - balanceBefore;
      token.safeTransfer(msg.sender, refundAmount);
      emit Refunded(msg.sender, refundAmount);
    }
  }

  function getAllowance(bytes4 sig) external view returns (bool) {
    return allowed[sig];
  }

  function setAllowance(bytes4 sig, bool allowed_) external onlyOwner {
    allowed[sig] = allowed_;

    emit AllowanceSet(sig, allowed_);
  }

  function executeWith(uint256 amount, bytes calldata calldata_)
    external
    doRefund
    returns (bytes memory)
  {
    return _executeWith(amount, calldata_);
  }

  function executeWithPermit(
    uint256 amount,
    uint256 deadline,
    bytes calldata permitData,
    bytes calldata calldata_
  ) external doRefund returns (bytes memory) {
    bytes32 r = bytes32(permitData[:32]);
    bytes32 s = bytes32(permitData[32:64]);
    uint8 v = uint8(permitData[64]);

    IERC2612(address(token)).permit(msg.sender, address(this), amount, deadline, v, r, s);

    return _executeWith(amount, calldata_);
  }

  function _executeWith(uint256 amount, bytes calldata calldata_) internal returns (bytes memory) {
    bytes4 sig = bytes4(calldata_[:4]);
    require(allowed[sig], FuncNotAllowed(sig));

    token.transferFrom(msg.sender, address(this), amount);
    token.approve(address(vault), amount);

    bytes memory returnData = Address.functionCall(address(vault), calldata_);

    return returnData;
  }
}
