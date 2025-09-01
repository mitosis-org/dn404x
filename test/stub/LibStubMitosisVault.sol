// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IMitosisVault } from '@mitosis/interfaces/branch/IMitosisVault.sol';
import { IMitosisVaultVLF } from '@mitosis/interfaces/branch/IMitosisVaultVLF.sol';

import { IStubInspector } from '@stub/interface/IStubInspector.sol';
import { IStubManager } from '@stub/interface/IStubManager.sol';

library LibStubMitosisVault {
  function _tom(address stub) private pure returns (IStubManager) {
    return IStubManager(stub);
  }

  function _toi(address stub) private pure returns (IStubInspector) {
    return IStubInspector(stub);
  }

  function initStubMitosisVault(address stub) internal {
    // Register IMitosisVault view functions
    _tom(stub).regF(IMitosisVault.isAssetInitialized.selector, false, 'isAssetInitialized');
    _tom(stub).regF(IMitosisVault.entrypoint.selector, false, 'entrypoint');

    // Register IMitosisVault mutative functions
    _tom(stub).regF(IMitosisVault.initializeAsset.selector, true, 'initializeAsset');
    _tom(stub).regF(IMitosisVault.deposit.selector, true, 'deposit');
    _tom(stub).regF(IMitosisVault.withdraw.selector, true, 'withdraw');
    _tom(stub).regF(IMitosisVault.setEntrypoint.selector, true, 'setEntrypoint');

    // Register IMitosisVaultVLF view functions
    _tom(stub).regF(IMitosisVaultVLF.isVLFInitialized.selector, false, 'isVLFInitialized');
    _tom(stub).regF(IMitosisVaultVLF.availableVLF.selector, false, 'availableVLF');
    _tom(stub).regF(IMitosisVaultVLF.vlfStrategyExecutor.selector, false, 'vlfStrategyExecutor');

    // Register IMitosisVaultVLF mutative functions
    _tom(stub).regF(IMitosisVaultVLF.depositWithSupplyVLF.selector, true, 'depositWithSupplyVLF');
    _tom(stub).regF(IMitosisVaultVLF.initializeVLF.selector, true, 'initializeVLF');
    _tom(stub).regF(IMitosisVaultVLF.allocateVLF.selector, true, 'allocateVLF');
    _tom(stub).regF(IMitosisVaultVLF.deallocateVLF.selector, true, 'deallocateVLF');
    _tom(stub).regF(IMitosisVaultVLF.fetchVLF.selector, true, 'fetchVLF');
    _tom(stub).regF(IMitosisVaultVLF.returnVLF.selector, true, 'returnVLF');
    _tom(stub).regF(IMitosisVaultVLF.settleVLFYield.selector, true, 'settleVLFYield');
    _tom(stub).regF(IMitosisVaultVLF.settleVLFLoss.selector, true, 'settleVLFLoss');
    _tom(stub).regF(IMitosisVaultVLF.settleVLFExtraRewards.selector, true, 'settleVLFExtraRewards');
    _tom(stub).regF(
      IMitosisVaultVLF.setVLFStrategyExecutor.selector, true, 'setVLFStrategyExecutor'
    );
  }

  // ================================================= VIEW FUNCTIONS ================================================= //
  // ====================================== IMitosisVault Specific ===================================== //

  function setRetIsAssetInitialized(address stub, address asset, bool isInitialized)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVault.isAssetInitialized, (asset));
    _tom(stub).setOk(data, abi.encode(isInitialized));
    return stub;
  }

  function setRetEntrypoint(address stub, address entrypointAddr) internal returns (address) {
    bytes memory data = abi.encodeCall(IMitosisVault.entrypoint, ());
    _tom(stub).setOk(data, abi.encode(entrypointAddr));
    return stub;
  }

  // ====================================== IMitosisVaultVLF Specific ====================================== //

  function setRetIsVLFInitialized(address stub, address hubVLFVault, bool isInitialized)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.isVLFInitialized, (hubVLFVault));
    _tom(stub).setOk(data, abi.encode(isInitialized));
    return stub;
  }

  function setRetAvailableVLF(address stub, address hubVLFVault, uint256 available)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.availableVLF, (hubVLFVault));
    _tom(stub).setOk(data, abi.encode(available));
    return stub;
  }

  function setRetVLFStrategyExecutor(address stub, address hubVLFVault, address executor)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.vlfStrategyExecutor, (hubVLFVault));
    _tom(stub).setOk(data, abi.encode(executor));
    return stub;
  }

  // ================================================= MUTATIVE FUNCTIONS ================================================= //

  // Note: Most MitosisVault mutative functions don't return values.
  // These `setRet...` functions primarily register the call pattern as successful (`setOk` without return data).

  // ====================================== IMitosisVault Specific ===================================== //

  function setRetInitializeAsset(address stub, address asset) internal returns (address) {
    bytes memory data = abi.encodeCall(IMitosisVault.initializeAsset, (asset));
    _tom(stub).setOk(data, abi.encode()); // No return value
    return stub;
  }

  function setRetDeposit(address stub, address asset, address to, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVault.deposit, (asset, to, amount));
    _tom(stub).setOk(data, abi.encode()); // No return value
    return stub;
  }

  function setRetWithdraw(address stub, address asset, address to, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVault.withdraw, (asset, to, amount));
    _tom(stub).setOk(data, abi.encode()); // No return value
    return stub;
  }

  function setRetSetEntrypoint(address stub, address entrypointAddr) internal returns (address) {
    bytes memory data = abi.encodeCall(IMitosisVault.setEntrypoint, (entrypointAddr));
    _tom(stub).setOk(data, abi.encode()); // No return value
    return stub;
  }

  // ====================================== IMitosisVaultVLF Specific ====================================== //

  function setRetInitializeVLF(address stub, address hubVLFVault, address asset)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.initializeVLF, (hubVLFVault, asset));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetDepositWithSupplyVLF(
    address stub,
    address asset,
    address to,
    address hubVLFVault,
    uint256 amount
  ) internal returns (address) {
    bytes memory data =
      abi.encodeCall(IMitosisVaultVLF.depositWithSupplyVLF, (asset, to, hubVLFVault, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetAllocateVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.allocateVLF, (hubVLFVault, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetDeallocateVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.deallocateVLF, (hubVLFVault, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetFetchVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.fetchVLF, (hubVLFVault, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetReturnVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.returnVLF, (hubVLFVault, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetSettleVLFYield(address stub, address hubVLFVault, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.settleVLFYield, (hubVLFVault, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetSettleVLFLoss(address stub, address hubVLFVault, uint256 amount)
    internal
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.settleVLFLoss, (hubVLFVault, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetSettleVLFExtraRewards(
    address stub,
    address hubVLFVault,
    address reward,
    uint256 amount
  ) internal returns (address) {
    bytes memory data =
      abi.encodeCall(IMitosisVaultVLF.settleVLFExtraRewards, (hubVLFVault, reward, amount));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  function setRetSetVLFStrategyExecutor(address stub, address hubVLFVault, address executor)
    internal
    returns (address)
  {
    bytes memory data =
      abi.encodeCall(IMitosisVaultVLF.setVLFStrategyExecutor, (hubVLFVault, executor));
    _tom(stub).setOk(data, abi.encode());
    return stub;
  }

  // ================================================= ASSERT FUNCTIONS ================================================= //
  // ====================================== IMitosisVault Specific ===================================== //

  function assertInitializeAsset(address stub, address asset) internal view returns (address) {
    bytes memory data = abi.encodeCall(IMitosisVault.initializeAsset, (asset));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertDeposit(address stub, address asset, address to, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVault.deposit, (asset, to, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertWithdraw(address stub, address asset, address to, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVault.withdraw, (asset, to, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertSetEntrypoint(address stub, address entrypointAddr)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVault.setEntrypoint, (entrypointAddr));
    _toi(stub).expectOk(data);
    return stub;
  }

  // ====================================== IMitosisVaultVLF Specific ====================================== //

  function assertInitializeVLF(address stub, address hubVLFVault, address asset)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.initializeVLF, (hubVLFVault, asset));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertDepositWithSupplyVLF(
    address stub,
    address asset,
    address to,
    address hubVLFVault,
    uint256 amount
  ) internal view returns (address) {
    bytes memory data =
      abi.encodeCall(IMitosisVaultVLF.depositWithSupplyVLF, (asset, to, hubVLFVault, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertAllocateVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.allocateVLF, (hubVLFVault, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertDeallocateVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.deallocateVLF, (hubVLFVault, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertFetchVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.fetchVLF, (hubVLFVault, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertReturnVLF(address stub, address hubVLFVault, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.returnVLF, (hubVLFVault, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertSettleVLFYield(address stub, address hubVLFVault, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.settleVLFYield, (hubVLFVault, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertSettleVLFLoss(address stub, address hubVLFVault, uint256 amount)
    internal
    view
    returns (address)
  {
    bytes memory data = abi.encodeCall(IMitosisVaultVLF.settleVLFLoss, (hubVLFVault, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertSettleVLFExtraRewards(
    address stub,
    address hubVLFVault,
    address reward,
    uint256 amount
  ) internal view returns (address) {
    bytes memory data =
      abi.encodeCall(IMitosisVaultVLF.settleVLFExtraRewards, (hubVLFVault, reward, amount));
    _toi(stub).expectOk(data);
    return stub;
  }

  function assertSetVLFStrategyExecutor(address stub, address hubVLFVault, address executor)
    internal
    view
    returns (address)
  {
    bytes memory data =
      abi.encodeCall(IMitosisVaultVLF.setVLFStrategyExecutor, (hubVLFVault, executor));
    _toi(stub).expectOk(data);
    return stub;
  }
}
