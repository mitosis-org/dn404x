// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Ownable } from '@oz/access/Ownable.sol';
import { IERC20Metadata } from '@oz/token/ERC20/extensions/IERC20Metadata.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Address } from '@oz/utils/Address.sol';
import { EnumerableMap } from '@oz/utils/structs/EnumerableMap.sol';

import { Quote } from '@hpl/interfaces/ITokenBridge.sol';
import { TypeCasts } from '@hpl/libs/TypeCasts.sol';

import { IMorse } from './interfaces/IMorse.sol';
import { IxDN404 } from './interfaces/IxDN404.sol';

/**
 * @title xMorseTransferBatch
 * @notice Batches DN404 token transfers for cross-chain efficiency
 * @dev Implements three-mode gas system:
 *      1. transferRemoteNFTPartial (batched with gas refunds)
 *      2. transferRemoteNFT (immediate with no refunds)
 *      3. New batch storage (minimum gas deposit)
 */
contract xMorseTransferBatch is Ownable {
  using Address for address payable;
  using SafeERC20 for IERC20;
  using TypeCasts for *;
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  //====================================================================================//
  //================================== DATA STRUCTURES ===============================//
  //====================================================================================//

  struct Request {
    address sender;
    bytes32 recipient;
    uint256 amount;
    uint256 gasDeposit;
  }

  struct Batch {
    uint32 destination;
    uint256 totalAmount;
    uint256 totalGasDeposit;
    Request[] requests;
  }

  struct TransferParams {
    uint32 destination;
    address recipient;
    uint256 amount;
    uint256 remainingAmount;
    uint256 gasAllocated;
    uint256 currentBatchId;
  }

  //====================================================================================//
  //================================== CONSTANTS =====================================//
  //====================================================================================//

  uint256 public constant DEFAULT_MINIMUM_GAS_DEPOSIT = 0.0001 ether;
  uint256 public constant DEFAULT_BASE_GAS = 100000;
  uint256 public constant DEFAULT_PER_RECIPIENT_GAS = 50000;

  //====================================================================================//
  //================================== IMMUTABLES ====================================//
  //====================================================================================//

  address public immutable morse;
  address public immutable xDN404;

  //====================================================================================//
  //================================== STORAGE =======================================//
  //====================================================================================//

  uint256 private _globalBatchId;
  uint256 private _minimumGasDeposit;
  uint256 private _baseGasEstimate;
  uint256 private _perRecipientGasEstimate;
  uint256 private _fallbackGasEstimate;

  mapping(uint256 => Batch) private _batches;
  mapping(uint256 => mapping(address => uint256)) private _addrToRequestId;
  mapping(uint256 => mapping(address => uint256)) private _addrToRequestIndex;
  mapping(uint32 => uint256) private _destinationToCurrentBatchId;

  //====================================================================================//
  //================================== CUSTOM ERRORS =================================//
  //====================================================================================//

  error InsufficientGasDeposit(uint256 provided, uint256 required);
  error InvalidAmount();
  error InvalidRecipient();
  error InsufficientAvailableTokens(uint256 available, uint256 required);
  error InsufficientGasForTransferModes(uint256 provided, uint256 required);
  error InvalidBatchId(uint256 provided, uint256 max);
  error CannotForceProcessCurrentBatch();
  error BatchEmpty();
  error TransferFailed(address recipient, uint256 amount);

  //====================================================================================//
  //================================== EVENTS ========================================//
  //====================================================================================//

  event BatchCreated(uint256 indexed batchId, uint256 totalAmount, uint256 totalGasDeposit);
  event RequestAdded(
    uint256 indexed batchId, address indexed recipient, uint256 amount, uint256 gasDeposit
  );
  event BatchProcessed(uint256 indexed batchId, uint256 totalAmount, uint256 totalGasDeposit);
  event GasRefunded(address indexed recipient, uint256 amount);
  event MinimumGasDepositUpdated(uint256 oldValue, uint256 newValue);
  event GasEstimateParamsUpdated(uint256 baseGas, uint256 perRecipientGas, uint256 fallbackGas);

  //====================================================================================//
  //================================== CONSTRUCTOR ===================================//
  //====================================================================================//

  constructor(address _morse, address _xDN404) Ownable(_msgSender()) {
    morse = _morse;
    xDN404 = _xDN404;
    _globalBatchId = 0;
    _minimumGasDeposit = DEFAULT_MINIMUM_GAS_DEPOSIT;
    _baseGasEstimate = DEFAULT_BASE_GAS;
    _perRecipientGasEstimate = DEFAULT_PER_RECIPIENT_GAS;
    _fallbackGasEstimate = 0.001 ether;
  }

  //====================================================================================//
  //================================== PUBLIC VIEW ===================================//
  //====================================================================================//

  function nextBatchId() external view returns (uint256) {
    return _globalBatchId;
  }

  function minimumGasDeposit() external view returns (uint256) {
    return _minimumGasDeposit;
  }

  function getBatch(uint256 batchId) external view returns (Batch memory) {
    return _batches[batchId];
  }

  function getRequest(uint256 batchId, uint256 requestIndex) external view returns (Request memory) {
    return _batches[batchId].requests[requestIndex];
  }

  function quoteTransferRemote(uint32 destination, address recipient, uint256 amount)
    external
    view
    returns (uint256 totalGasCost)
  {
    return _calculateRequiredGas(destination, recipient, amount);
  }

  //====================================================================================//
  //================================== PUBLIC FUNCTIONS ==============================//
  //====================================================================================//

  function setMinimumGasDeposit(uint256 minimumGasDeposit_) external onlyOwner {
    uint256 oldValue = _minimumGasDeposit;
    _minimumGasDeposit = minimumGasDeposit_;
    emit MinimumGasDepositUpdated(oldValue, minimumGasDeposit_);
  }

  function setGasEstimateParams(uint256 baseGas_, uint256 perRecipientGas_, uint256 fallbackGas_)
    external
    onlyOwner
  {
    _baseGasEstimate = baseGas_;
    _perRecipientGasEstimate = perRecipientGas_;
    _fallbackGasEstimate = fallbackGas_;
    emit GasEstimateParamsUpdated(baseGas_, perRecipientGas_, fallbackGas_);
  }

  function getGasEstimateParams()
    external
    view
    returns (uint256 baseGas, uint256 perRecipientGas, uint256 fallbackGas)
  {
    return (_baseGasEstimate, _perRecipientGasEstimate, _fallbackGasEstimate);
  }

  /**
   * @notice Transfer tokens to a remote destination with batching optimization
   * @param destination The destination chain ID
   * @param recipient The recipient address
   * @param amount The amount to transfer
   */
  function transferRemote(uint32 destination, address recipient, uint256 amount) external payable {
    TransferParams memory params = TransferParams({
      destination: destination,
      recipient: recipient,
      amount: amount,
      remainingAmount: amount,
      gasAllocated: 0,
      currentBatchId: 0
    });

    _executeTransfer(params);
  }

  function forceProcessBatch(uint256 batchId) external onlyOwner {
    require(batchId <= _globalBatchId, InvalidBatchId(batchId, _globalBatchId));
    require(batchId < _globalBatchId, CannotForceProcessCurrentBatch());

    Batch storage batch = _batches[batchId];
    require(batch.requests.length > 0, BatchEmpty());
    _processBatch(batchId);
  }

  //====================================================================================//
  //================================== INTERNAL CORE ==================================//
  //====================================================================================//

  function _executeTransfer(TransferParams memory params) internal {
    _validateTransferRequest(params.recipient, params.amount);

    uint256 requiredGas = _calculateRequiredGas(params.destination, params.recipient, params.amount);
    require(msg.value >= requiredGas, InsufficientGasForTransferModes(msg.value, requiredGas));

    // Step 1: Handle existing batch completion
    params.currentBatchId = _handleBatchCompletion(params);

    // Step 2: Process full tokens
    params = _processFullTokens(params);

    // Step 3: Handle remaining partial amount
    _handlePartialAmount(params);

    // Step 4: Refund excess gas
    _refundExcessGas(params.gasAllocated);

    // Step 5: Check if batch should be processed
    _checkAndProcessBatch(params.currentBatchId);
  }

  function _handleBatchCompletion(TransferParams memory params) internal returns (uint256) {
    uint256 currentBatchId = _getOrCreateBatchForDestination(params.destination);
    Batch storage batch = _batches[currentBatchId];
    uint256 one = _getTokenUnit();
    uint256 batchRemaining = one - batch.totalAmount;

    if (batch.totalAmount > 0 && params.remainingAmount >= batchRemaining) {
      uint256 gasForBatch =
        _estimateGasForCurrentBatch(params.destination, params.recipient, batchRemaining);

      _addRequestToBatch(currentBatchId, params.recipient, batchRemaining, gasForBatch);
      _processBatch(currentBatchId);
      currentBatchId = _createNewBatchForDestination(params.destination);

      params.remainingAmount -= batchRemaining;
      params.gasAllocated += gasForBatch;
    }

    return currentBatchId;
  }

  function _processFullTokens(TransferParams memory params)
    internal
    returns (TransferParams memory)
  {
    if (params.remainingAmount > 0) {
      (uint256 fullTokens, uint256 partialAmount) =
        _calculateRemainingTokens(params.remainingAmount);

      if (fullTokens > 0) {
        uint256 gasForFullTokens = fullTokens * _minimumGasDeposit;
        _processFullTokenTransfer(
          params.destination, params.recipient, fullTokens, gasForFullTokens
        );
        params.remainingAmount = partialAmount;
        params.gasAllocated += gasForFullTokens;
      }
    }

    return params;
  }

  function _handlePartialAmount(TransferParams memory params) internal {
    if (params.remainingAmount > 0) {
      _addRequestToBatch(
        params.currentBatchId, params.recipient, params.remainingAmount, _minimumGasDeposit
      );
      params.gasAllocated += _minimumGasDeposit;
    }
  }

  function _refundExcessGas(uint256 gasAllocated) internal {
    uint256 excessGas = msg.value - gasAllocated;
    if (excessGas > 0) {
      payable(_msgSender()).sendValue(excessGas);
    }
  }

  //====================================================================================//
  //================================== BATCH MANAGEMENT ==============================//
  //====================================================================================//

  function _getOrCreateBatchForDestination(uint32 destination) internal returns (uint256) {
    uint256 batchId = _destinationToCurrentBatchId[destination];
    if (batchId == 0) {
      return _createNewBatchForDestination(destination);
    }
    return batchId;
  }

  function _createNewBatchForDestination(uint32 destination) internal returns (uint256) {
    _globalBatchId++;
    uint256 newBatchId = _globalBatchId;

    Batch storage newBatch = _batches[newBatchId];
    newBatch.destination = destination;
    newBatch.totalAmount = 0;
    newBatch.totalGasDeposit = 0;

    _destinationToCurrentBatchId[destination] = newBatchId;

    emit BatchCreated(newBatchId, 0, 0);
    return newBatchId;
  }

  function _addRequestToBatch(
    uint256 batchId,
    address recipient,
    uint256 amount,
    uint256 gasDeposit
  ) internal {
    Batch storage batch = _batches[batchId];

    uint256 requestIndex = _addrToRequestIndex[batchId][recipient];
    if (requestIndex == 0) {
      batch.requests.push(
        Request({
          sender: _msgSender(),
          recipient: recipient.addressToBytes32(),
          amount: amount,
          gasDeposit: gasDeposit
        })
      );
      _addrToRequestIndex[batchId][recipient] = batch.requests.length;
      emit RequestAdded(batchId, recipient, amount, gasDeposit);
    } else {
      uint256 actualIndex = requestIndex - 1;
      batch.requests[actualIndex].amount += amount;
      batch.requests[actualIndex].gasDeposit += gasDeposit;
      emit RequestAdded(batchId, recipient, amount, gasDeposit);
    }

    batch.totalAmount += amount;
    batch.totalGasDeposit += gasDeposit;
  }

  function _processBatch(uint256 batchId) internal {
    Batch storage batch = _batches[batchId];
    if (batch.requests.length == 0) return;

    (bytes32[] memory recipients, uint256[] memory amounts) = _prepareBatchArrays(batch);
    uint256 tokenIdForPartial = _getTokenIdForPartialTransfer();
    uint256 gasUsed =
      _estimateGasForBatch(batch.destination, recipients, amounts, tokenIdForPartial);

    if (batch.totalGasDeposit >= gasUsed) {
      _executeBatchTransfer(batch, recipients, amounts, tokenIdForPartial, gasUsed);
      _distributeGasRefunds(batchId, batch.totalGasDeposit - gasUsed);
    } else {
      _refundAllGasDeposits(batchId);
    }

    _destinationToCurrentBatchId[batch.destination] = 0;
    emit BatchProcessed(batchId, batch.totalAmount, batch.totalGasDeposit);
  }

  function _prepareBatchArrays(Batch storage batch)
    internal
    view
    returns (bytes32[] memory, uint256[] memory)
  {
    bytes32[] memory recipients = new bytes32[](batch.requests.length);
    uint256[] memory amounts = new uint256[](batch.requests.length);

    for (uint256 i = 0; i < batch.requests.length; i++) {
      recipients[i] = batch.requests[i].recipient;
      amounts[i] = batch.requests[i].amount;
    }

    return (recipients, amounts);
  }

  function _executeBatchTransfer(
    Batch storage batch,
    bytes32[] memory recipients,
    uint256[] memory amounts,
    uint256 tokenId,
    uint256 gasUsed
  ) internal {
    IxDN404(xDN404).transferRemoteNFTPartial{ value: gasUsed }(
      batch.destination, tokenId, recipients, amounts
    );
  }

  function _checkAndProcessBatch(uint256 batchId) internal {
    Batch storage batch = _batches[batchId];
    uint256 one = _getTokenUnit();

    if (batch.totalAmount >= one) {
      _processBatch(batchId);
      _createNewBatchForDestination(batch.destination);
    }
  }

  //====================================================================================//
  //================================== TOKEN MANAGEMENT ===============================//
  //====================================================================================//

  function _processFullTokenTransfer(
    uint32 destination,
    address recipient,
    uint256 fullTokens,
    uint256 gasAmount
  ) internal {
    uint256[] memory tokenIds = _getAvailableTokenIds(fullTokens);

    IxDN404(xDN404).transferRemoteNFT{ value: gasAmount }(
      destination, recipient.addressToBytes32(), tokenIds
    );
  }

  function _getAvailableTokenIds(uint256 count) internal view returns (uint256[] memory) {
    IMorse.DN404TransferLog[] memory transferLogs = IMorse(morse).getCurrentTransferLogs();
    uint256 availableTokens = transferLogs.length;

    require(availableTokens >= count, InsufficientAvailableTokens(availableTokens, count));

    uint256[] memory tokenIds = new uint256[](count);
    uint256 tokenIndex = 0;

    for (uint256 i = availableTokens - 1; i >= 0 && tokenIndex < count; i--) {
      tokenIds[tokenIndex] = transferLogs[i].id;
      tokenIndex++;
    }

    return tokenIds;
  }

  function _getTokenIdForPartialTransfer() internal view returns (uint256) {
    uint256[] memory availableTokenIds = _getAvailableTokenIds(1);
    return availableTokenIds[0];
  }

  //====================================================================================//
  //================================== GAS CALCULATIONS ===============================//
  //====================================================================================//

  function _calculateRequiredGas(uint32 destination, address recipient, uint256 amount)
    internal
    view
    returns (uint256)
  {
    uint256 totalGas = 0;
    uint256 remainingAmount = amount;

    // Gas for completing current batch (Mode 1)
    uint256 currentBatchId = _globalBatchId;
    Batch storage batch = _batches[currentBatchId];
    uint256 one = _getTokenUnit();
    uint256 batchRemaining = one - batch.totalAmount;

    if (batch.totalAmount > 0 && remainingAmount >= batchRemaining) {
      totalGas += _estimateGasForCurrentBatch(destination, recipient, batchRemaining);
      remainingAmount -= batchRemaining;
    }

    // Gas for full tokens (Mode 2)
    if (remainingAmount > 0) {
      (uint256 fullTokens, uint256 partialAmount) = _calculateRemainingTokens(remainingAmount);

      if (fullTokens > 0) {
        totalGas += fullTokens * _minimumGasDeposit;
        remainingAmount = partialAmount;
      }

      // Gas for remaining partial (Mode 3)
      if (remainingAmount > 0) {
        totalGas += _minimumGasDeposit;
      }
    }

    return totalGas;
  }

  function _estimateGasForCurrentBatch(
    uint32 destination,
    address recipient,
    uint256 additionalAmount
  ) internal view returns (uint256) {
    uint256 currentBatchId = _destinationToCurrentBatchId[destination];
    if (currentBatchId == 0) {
      // No current batch for this destination, use fallback estimation
      return _baseGasEstimate + _perRecipientGasEstimate;
    }

    Batch storage batch = _batches[currentBatchId];

    uint256 totalRequests = batch.requests.length + 1;
    bytes32[] memory recipients = new bytes32[](totalRequests);
    uint256[] memory amounts = new uint256[](totalRequests);

    for (uint256 i = 0; i < batch.requests.length; i++) {
      recipients[i] = batch.requests[i].recipient;
      amounts[i] = batch.requests[i].amount;
    }

    recipients[totalRequests - 1] = recipient.addressToBytes32();
    amounts[totalRequests - 1] = additionalAmount;

    uint256 tokenIdForPartial = _getTokenIdForPartialTransfer();
    return _estimateGasForBatch(destination, recipients, amounts, tokenIdForPartial);
  }

  function _estimateGasForBatch(
    uint32 destination,
    bytes32[] memory recipients,
    uint256[] memory amounts,
    uint256 tokenId
  ) internal view returns (uint256) {
    try IxDN404(xDN404).quoteTransferRemoteNFTPartial(destination, tokenId, recipients, amounts)
    returns (Quote[] memory quotes) {
      if (quotes.length > 0) {
        return quotes[0].amount;
      }
    } catch {
      return _baseGasEstimate + (_perRecipientGasEstimate * recipients.length);
    }

    return _fallbackGasEstimate;
  }

  //====================================================================================//
  //================================== GAS REFUNDS ===================================//
  //====================================================================================//

  function _distributeGasRefunds(uint256 batchId, uint256 excessGas) internal {
    Batch storage batch = _batches[batchId];
    uint256 totalRequests = batch.requests.length;

    for (uint256 i = 0; i < totalRequests; i++) {
      uint256 refundAmount = (excessGas * batch.requests[i].gasDeposit) / batch.totalGasDeposit;
      if (refundAmount > 0) {
        address sender = batch.requests[i].sender;
        payable(sender).sendValue(refundAmount);
        emit GasRefunded(sender, refundAmount);
      }
    }
  }

  function _refundAllGasDeposits(uint256 batchId) internal {
    Batch storage batch = _batches[batchId];

    for (uint256 i = 0; i < batch.requests.length; i++) {
      if (batch.requests[i].gasDeposit > 0) {
        address sender = batch.requests[i].sender;
        payable(sender).sendValue(batch.requests[i].gasDeposit);
        emit GasRefunded(sender, batch.requests[i].gasDeposit);
      }
    }
  }

  //====================================================================================//
  //================================== UTILITIES =====================================//
  //====================================================================================//

  function _validateTransferRequest(address recipient, uint256 amount) internal view {
    require(msg.value >= _minimumGasDeposit, InsufficientGasDeposit(msg.value, _minimumGasDeposit));
    require(amount > 0, InvalidAmount());
    require(recipient != address(0), InvalidRecipient());
  }

  function _calculateRemainingTokens(uint256 remainingAmount)
    internal
    view
    returns (uint256 fullTokens, uint256 partialAmount)
  {
    uint256 one = _getTokenUnit();
    fullTokens = remainingAmount / one;
    partialAmount = remainingAmount % one;
  }

  function _calculateTokenDistribution(uint256 amount)
    internal
    view
    returns (uint256 fullTokens, uint256 partialAmount)
  {
    uint256 one = _getTokenUnit();
    uint256 currentBalance = IERC20(morse).balanceOf(_msgSender());
    uint256 totalAmount = currentBalance + amount;

    uint256 totalFullTokens = totalAmount / one;
    uint256 currentFullTokens = currentBalance / one;

    fullTokens = totalFullTokens - currentFullTokens;
    partialAmount = totalAmount % one;
  }

  function _getTokenUnit() internal view returns (uint256) {
    return 10 ** IERC20Metadata(morse).decimals();
  }

  //====================================================================================//
  //================================== EMERGENCY =====================================//
  //====================================================================================//

  function emergencyWithdraw() external onlyOwner {
    payable(owner()).sendValue(address(this).balance);
  }

  function emergencyWithdrawToken(address token) external onlyOwner {
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
      SafeERC20.safeTransfer(IERC20(token), owner(), balance);
    }
  }

  receive() external payable { }
}
