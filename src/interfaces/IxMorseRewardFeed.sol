// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

/// @title IxMorseRewardFeed
/// @notice Interface for xMorse epoch-based reward feed
/// @dev Similar to ValidatorContributionFeed pattern
interface IxMorseRewardFeed {
  //====================================================================================//
  //================================== ENUMS ===========================================//
  //====================================================================================//

  /// @notice Report status for epoch rewards
  enum ReportStatus {
    NONE,        // No report exists
    INITIALIZED, // Report initialized but not finalized
    FINALIZED,   // Report finalized and available for claims
    REVOKING     // Report being revoked
  }

  //====================================================================================//
  //================================== STRUCTS =========================================//
  //====================================================================================//

  /// @notice Epoch reward data
  struct EpochReward {
    uint256 totalReward;      // Total reward amount for this epoch
    uint256 totalStakedNFTs;  // Snapshot of total staked NFTs
    ReportStatus status;       // Report status
  }

  //====================================================================================//
  //================================== EVENTS ==========================================//
  //====================================================================================//

  /// @notice Emitted when epoch reward is initialized
  event EpochRewardInitialized(uint256 indexed epoch, uint256 totalReward, uint256 totalStakedNFTs);

  /// @notice Emitted when epoch reward is finalized
  event EpochRewardFinalized(uint256 indexed epoch);

  /// @notice Emitted when epoch reward is revoked
  event EpochRewardRevoked(uint256 indexed epoch);

  //====================================================================================//
  //================================== ERRORS ==========================================//
  //====================================================================================//

  /// @notice Thrown when epoch is invalid
  error InvalidEpoch();

  /// @notice Thrown when report status is invalid for the operation
  error InvalidReportStatus();

  /// @notice Thrown when report is not ready for reading
  error ReportNotReady();

  //====================================================================================//
  //================================== FUNCTIONS =======================================//
  //====================================================================================//

  /// @notice Get the epoch feeder contract
  function epochFeeder() external view returns (IEpochFeeder);

  /// @notice Get reward data for specific epoch
  /// @param epoch Epoch number
  /// @return Epoch reward data
  function rewardForEpoch(uint256 epoch) external view returns (EpochReward memory);

  /// @notice Check if epoch reward is available for claiming
  /// @param epoch Epoch number
  /// @return True if epoch is finalized
  function available(uint256 epoch) external view returns (bool);

  /// @notice Get next epoch to be initialized
  function nextEpoch() external view returns (uint256);

  /// @notice Initialize epoch reward (FEEDER_ROLE only)
  /// @param epoch Epoch number
  /// @param totalReward Total reward amount
  /// @param totalStakedNFTs Total staked NFTs snapshot
  function initializeEpochReward(uint256 epoch, uint256 totalReward, uint256 totalStakedNFTs)
    external;

  /// @notice Finalize epoch reward (FEEDER_ROLE only)
  /// @param epoch Epoch number
  function finalizeEpochReward(uint256 epoch) external;

  /// @notice Revoke epoch reward (FEEDER_ROLE only)
  /// @param epoch Epoch number
  function revokeEpochReward(uint256 epoch) external;
}

