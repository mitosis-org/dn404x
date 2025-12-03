// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';
import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';

import { IxMorseRewardFeed } from './interfaces/IxMorseRewardFeed.sol';

/// @title xMorseRewardFeed Storage Contract
/// @notice Separates storage from logic following ValidatorContributionFeed pattern
contract xMorseRewardFeedStorageV1 {
  using ERC7201Utils for string;

  struct StorageV1 {
    uint256 nextEpoch;
    address feeder;  // Address authorized to feed epoch rewards
    mapping(uint256 epoch => IxMorseRewardFeed.EpochReward) rewards;
  }

  string private constant _NAMESPACE = 'mitosis.storage.xMorseRewardFeedStorage.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}

/// @title xMorseRewardFeed
/// @notice Manages epoch-based reward data for xMorse staking
/// @dev Similar to ValidatorContributionFeed pattern but simplified for NFT staking
contract xMorseRewardFeed is
  IxMorseRewardFeed,
  xMorseRewardFeedStorageV1,
  Ownable2StepUpgradeable,
  UUPSUpgradeable
{
  //====================================================================================//
  //================================== IMMUTABLES ======================================//
  //====================================================================================//

  IEpochFeeder private immutable _epochFeeder;

  //====================================================================================//
  //================================== MODIFIERS =======================================//
  //====================================================================================//

  /// @notice Modifier to restrict access to feeder role
  modifier onlyFeeder() {
    StorageV1 storage $ = _getStorageV1();
    if (_msgSender() != $.feeder && _msgSender() != owner()) {
      revert("Not authorized");
    }
    _;
  }

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

  /// @notice Initialize the reward feed contract
  /// @param initialOwner Initial owner address
  /// @param initialFeeder Initial feeder address
  function initialize(address initialOwner, address initialFeeder) external initializer {
    if (initialOwner == address(0)) revert("Zero address");
    if (initialFeeder == address(0)) revert("Zero address");

    __Ownable_init(initialOwner);
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    StorageV1 storage $ = _getStorageV1();
    $.nextEpoch = 1;
    $.feeder = initialFeeder;
  }

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @inheritdoc IxMorseRewardFeed
  function epochFeeder() external view returns (IEpochFeeder) {
    return _epochFeeder;
  }

  /// @inheritdoc IxMorseRewardFeed
  function rewardForEpoch(uint256 epoch) external view returns (EpochReward memory) {
    return _getStorageV1().rewards[epoch];
  }

  /// @inheritdoc IxMorseRewardFeed
  function available(uint256 epoch) external view returns (bool) {
    return _getStorageV1().rewards[epoch].status == ReportStatus.FINALIZED;
  }

  /// @inheritdoc IxMorseRewardFeed
  function nextEpoch() external view returns (uint256) {
    return _getStorageV1().nextEpoch;
  }

  /// @notice Get current feeder address
  function feeder() external view returns (address) {
    return _getStorageV1().feeder;
  }

  //====================================================================================//
  //================================== FEEDER FUNCTIONS ================================//
  //====================================================================================//

  /// @inheritdoc IxMorseRewardFeed
  function initializeEpochReward(uint256 epoch, uint256 totalReward, uint256 totalStakedNFTs)
    external
    onlyFeeder
  {
    StorageV1 storage $ = _getStorageV1();

    // Validate epoch
    if (epoch != $.nextEpoch) revert InvalidEpoch();

    // Validate status
    if ($.rewards[epoch].status != ReportStatus.NONE) revert InvalidReportStatus();

    // Initialize epoch reward
    $.rewards[epoch] = EpochReward({
      totalReward: totalReward,
      totalStakedNFTs: totalStakedNFTs,
      status: ReportStatus.INITIALIZED
    });

    emit EpochRewardInitialized(epoch, totalReward, totalStakedNFTs);
  }

  /// @inheritdoc IxMorseRewardFeed
  function finalizeEpochReward(uint256 epoch) external onlyFeeder {
    StorageV1 storage $ = _getStorageV1();

    // Validate status
    if ($.rewards[epoch].status != ReportStatus.INITIALIZED) revert InvalidReportStatus();

    // Finalize epoch
    $.rewards[epoch].status = ReportStatus.FINALIZED;

    // Move to next epoch
    $.nextEpoch++;

    emit EpochRewardFinalized(epoch);
  }

  /// @inheritdoc IxMorseRewardFeed
  function revokeEpochReward(uint256 epoch) external onlyFeeder {
    StorageV1 storage $ = _getStorageV1();

    // Validate status (can only revoke INITIALIZED, not FINALIZED)
    if (
      $.rewards[epoch].status != ReportStatus.INITIALIZED
        && $.rewards[epoch].status != ReportStatus.REVOKING
    ) {
      revert InvalidReportStatus();
    }

    // Clear epoch data
    delete $.rewards[epoch];

    emit EpochRewardRevoked(epoch);
  }

  //====================================================================================//
  //================================== OWNER FUNCTIONS =================================//
  //====================================================================================//

  /// @notice Set feeder address
  /// @param newFeeder New feeder address
  function setFeeder(address newFeeder) external onlyOwner {
    if (newFeeder == address(0)) revert("Zero address");

    StorageV1 storage $ = _getStorageV1();
    $.feeder = newFeeder;
  }

  //====================================================================================//
  //================================== UPGRADE =========================================//
  //====================================================================================//

  /// @notice Authorize upgrade (owner only)
  function _authorizeUpgrade(address) internal override onlyOwner { }
}

