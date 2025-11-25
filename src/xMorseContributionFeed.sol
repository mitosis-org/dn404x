// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { AccessControlEnumerableUpgradeable } from '@ozu/access/extensions/AccessControlEnumerableUpgradeable.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';
import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';
import { StdError } from '@mitosis/lib/StdError.sol';

import { IxMorseContributionFeed } from './interfaces/IxMorseContributionFeed.sol';

/// @title xMorseContributionFeed
/// @notice Manages epoch-based staker contribution feeding for xMorse rewards
/// @dev Follows ValidatorContributionFeed pattern with per-staker weights
/// @dev Report lifecycle:
/// 1. initializeReport
/// 2. pushStakerWeights (can be called multiple times in batches)
/// 3-1. finalizeReport
/// 3-2. revokeReport -> Back to step 1
contract xMorseContributionFeed is
  IxMorseContributionFeed,
  Ownable2StepUpgradeable,
  AccessControlEnumerableUpgradeable,
  UUPSUpgradeable
{
  using ERC7201Utils for string;
  using SafeCast for uint256;

  //====================================================================================//
  //================================== STORAGE =========================================//
  //====================================================================================//

  /// @notice Internal checker for validating report integrity
  struct ReportChecker {
    uint256 totalWeight;     // Accumulated weight during pushing
    uint16 numOfStakers;     // Accumulated number of stakers
    uint80 _reserved;        // Reserved for future use
  }

  /// @notice Internal reward structure per epoch
  struct Reward {
    ReportStatus status;
    uint256 totalWeight;
    StakerWeight[] weights;
    mapping(address staker => uint256 index) weightByStaker;
  }

  /// @custom:storage-location erc7201:mitosis.storage.xMorseContributionFeed.v1
  struct StorageV1 {
    uint256 nextEpoch;
    ReportChecker checker;
    mapping(uint256 epoch => Reward reward) rewards;
  }

  string private constant _NAMESPACE = 'mitosis.storage.xMorseContributionFeed.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  //====================================================================================//
  //================================== CONSTANTS =======================================//
  //====================================================================================//

  /// @notice keccak256('mitosis.role.xMorseContributionFeed.feeder')
  bytes32 public constant FEEDER_ROLE = 0xa33b22848ec080944b3c811b3fe6236387c5104ce69ccd386b545a980fbe6827;
  
  /// @notice Maximum number of weights that can be pushed per transaction
  uint256 public constant MAX_WEIGHTS_PER_ACTION = 1000;

  //====================================================================================//
  //================================== IMMUTABLES ======================================//
  //====================================================================================//

  IEpochFeeder private immutable _epochFeeder;

  //====================================================================================//
  //================================== CONSTRUCTOR =====================================//
  //====================================================================================//

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(IEpochFeeder epochFeeder_) {
    _disableInitializers();
    _epochFeeder = epochFeeder_;
  }

  //====================================================================================//
  //================================== INITIALIZATION ==================================//
  //====================================================================================//

  /// @notice Initialize the contribution feed contract
  /// @param owner_ Initial owner address
  function initialize(address owner_) external initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(owner_);
    __Ownable2Step_init();
    __AccessControl_init();
    __AccessControlEnumerable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, owner_);

    StorageV1 storage $ = _getStorageV1();
    $.nextEpoch = 1;
  }

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @inheritdoc IxMorseContributionFeed
  function epochFeeder() external view returns (IEpochFeeder) {
    return _epochFeeder;
  }

  /// @inheritdoc IxMorseContributionFeed
  function weightCount(uint256 epoch) external view returns (uint256) {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);
    return _weightCount(reward);
  }

  /// @inheritdoc IxMorseContributionFeed
  function weightAt(uint256 epoch, uint256 index) external view returns (StakerWeight memory) {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);
    return reward.weights[index + 1];
  }

  /// @inheritdoc IxMorseContributionFeed
  function weightOf(uint256 epoch, address staker)
    external
    view
    returns (StakerWeight memory, bool)
  {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);

    uint256 index = reward.weightByStaker[staker];
    if (index == 0) {
      StakerWeight memory empty;
      return (empty, false);
    }
    return (reward.weights[index], true);
  }

  /// @inheritdoc IxMorseContributionFeed
  function available(uint256 epoch) external view returns (bool) {
    return _getStorageV1().rewards[epoch].status == ReportStatus.FINALIZED;
  }

  /// @inheritdoc IxMorseContributionFeed
  function summary(uint256 epoch) external view returns (Summary memory) {
    Reward storage reward = _getStorageV1().rewards[epoch];
    _assertReportReady(reward);

    return Summary({
      totalWeight: uint256(reward.totalWeight).toUint128(),
      numOfStakers: _weightCount(reward).toUint128()
    });
  }

  /// @inheritdoc IxMorseContributionFeed
  function nextEpoch() external view returns (uint256) {
    return _getStorageV1().nextEpoch;
  }

  //====================================================================================//
  //================================== FEEDER FUNCTIONS ================================//
  //====================================================================================//

  /// @inheritdoc IxMorseContributionFeed
  function initializeReport(InitReportRequest calldata request) external onlyRole(FEEDER_ROLE) {
    StorageV1 storage $ = _getStorageV1();

    uint256 epoch = $.nextEpoch;

    require(epoch < _epochFeeder.epoch(), StdError.InvalidParameter('epoch'));

    Reward storage reward = $.rewards[epoch];
    require(reward.status == ReportStatus.NONE, IxMorseContributionFeed__InvalidReportStatus());

    reward.status = ReportStatus.INITIALIZED;
    reward.totalWeight = request.totalWeight;
    $.checker.numOfStakers = request.numOfStakers;
    
    // 0 index is reserved for empty slot
    {
      StakerWeight memory empty;
      reward.weights.push(empty);
    }

    emit ReportInitialized(epoch, uint128(request.totalWeight), request.numOfStakers);
  }

  /// @inheritdoc IxMorseContributionFeed
  function pushStakerWeights(StakerWeight[] calldata weights) external onlyRole(FEEDER_ROLE) {
    require(weights.length > 0, IxMorseContributionFeed__InvalidWeightCount());
    require(weights.length <= MAX_WEIGHTS_PER_ACTION, IxMorseContributionFeed__InvalidWeightCount());

    StorageV1 storage $ = _getStorageV1();
    uint256 epoch = $.nextEpoch;

    Reward storage reward = $.rewards[epoch];
    require(reward.status == ReportStatus.INITIALIZED, IxMorseContributionFeed__InvalidReportStatus());

    ReportChecker memory checker = $.checker;

    uint256 weightsLen = reward.weights.length;
    uint256 pushWeightsLen = weights.length;
    
    for (uint256 i = 0; i < pushWeightsLen; i++) {
      StakerWeight memory weight = weights[i];
      require(weight.weight > 0, IxMorseContributionFeed__InvalidWeight());

      uint256 index = reward.weightByStaker[weight.addr];
      require(index == 0, IxMorseContributionFeed__InvalidWeightAddress());

      reward.weights.push(weight);
      reward.weightByStaker[weight.addr] = weightsLen + i;
      checker.totalWeight += weight.weight;
    }

    uint256 prevTotalWeight = $.checker.totalWeight;
    $.checker = checker;

    emit WeightsPushed(epoch, uint128(checker.totalWeight - prevTotalWeight), pushWeightsLen.toUint16());
  }

  /// @inheritdoc IxMorseContributionFeed
  function finalizeReport() external onlyRole(FEEDER_ROLE) {
    StorageV1 storage $ = _getStorageV1();
    uint256 epoch = $.nextEpoch;

    Reward storage reward = $.rewards[epoch];
    require(reward.status == ReportStatus.INITIALIZED, IxMorseContributionFeed__InvalidReportStatus());

    ReportChecker memory checker = $.checker;
    require(checker.totalWeight == reward.totalWeight, IxMorseContributionFeed__InvalidTotalWeight());
    require(checker.numOfStakers == _weightCount(reward), IxMorseContributionFeed__InvalidStakerCount());

    reward.status = ReportStatus.FINALIZED;

    $.nextEpoch++;
    delete $.checker;

    emit ReportFinalized(epoch);
  }

  /// @inheritdoc IxMorseContributionFeed
  function revokeReport() external onlyRole(FEEDER_ROLE) {
    StorageV1 storage $ = _getStorageV1();
    uint256 epoch = $.nextEpoch;

    Reward storage reward = $.rewards[epoch];
    require(
      reward.status == ReportStatus.INITIALIZED || reward.status == ReportStatus.REVOKING,
      IxMorseContributionFeed__InvalidReportStatus()
    );

    // NOTICE: we need to separate revoke sequence because of the gas limit
    uint256 removeCount = Math.min(MAX_WEIGHTS_PER_ACTION, reward.weights.length);
    for (uint256 i = 0; i < removeCount; i++) {
      StakerWeight memory weight = reward.weights[reward.weights.length - 1];
      delete reward.weightByStaker[weight.addr];
      reward.weights.pop();
    }

    if ($.rewards[epoch].weights.length > 0) {
      reward.status = ReportStatus.REVOKING;
      emit ReportRevoking(epoch);
      return;
    }

    delete $.rewards[epoch].weights;
    delete $.rewards[epoch];
    delete $.checker;

    emit ReportRevoked(epoch);
  }

  //====================================================================================//
  //================================== INTERNAL FUNCTIONS ==============================//
  //====================================================================================//

  /// @notice Get the number of stakers (excluding empty slot at index 0)
  function _weightCount(Reward storage reward) internal view returns (uint256) {
    return reward.weights.length - 1;
  }

  /// @notice Assert that report is ready for reading
  function _assertReportReady(Reward storage reward) internal view {
    require(reward.status == ReportStatus.FINALIZED, IxMorseContributionFeed__ReportNotReady());
  }

  //====================================================================================//
  //================================== UPGRADE =========================================//
  //====================================================================================//

  /// @notice Authorize upgrade (owner only)
  function _authorizeUpgrade(address) internal view override onlyOwner { }
}

