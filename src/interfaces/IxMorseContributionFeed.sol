// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

/// @title IxMorseContributionFeed
/// @notice Interface for xMorse epoch-based staker contribution feeding
/// @dev Follows ValidatorContributionFeed pattern with per-staker weights
interface IxMorseContributionFeed {
  //====================================================================================//
  //================================== STRUCTS =========================================//
  //====================================================================================//

  /// @notice Staker weight for an epoch
  struct StakerWeight {
    address addr;           // Staker address
    uint256 weight;         // TWAB-based weight for this epoch
  }

  /// @notice Request to initialize a report
  struct InitReportRequest {
    uint256 totalWeight;   // Sum of all staker weights
    uint16 numOfStakers;   // Number of stakers in this epoch
  }

  /// @notice Summary of an epoch's contribution
  struct Summary {
    uint256 totalWeight;    // Total weight across all stakers
    uint128 numOfStakers;   // Number of stakers
  }

  //====================================================================================//
  //================================== ENUMS ===========================================//
  //====================================================================================//

  /// @notice Report status for epoch contributions
  enum ReportStatus {
    NONE,        // No report exists
    INITIALIZED, // Report initialized, waiting for weights
    REVOKING,    // Report being revoked (batched operation)
    FINALIZED    // Report finalized and available
  }

  //====================================================================================//
  //================================== EVENTS ==========================================//
  //====================================================================================//

  /// @notice Emitted when a report is initialized
  event ReportInitialized(uint256 indexed epoch, uint128 totalWeight, uint128 numOfStakers);

  /// @notice Emitted when weights are pushed
  event WeightsPushed(uint256 indexed epoch, uint128 totalWeight, uint128 numOfStakers);

  /// @notice Emitted when a report is finalized
  event ReportFinalized(uint256 indexed epoch);

  /// @notice Emitted when a report is being revoked
  event ReportRevoking(uint256 indexed epoch);

  /// @notice Emitted when a report is revoked
  event ReportRevoked(uint256 indexed epoch);

  //====================================================================================//
  //================================== ERRORS ==========================================//
  //====================================================================================//

  error IxMorseContributionFeed__InvalidReportStatus();
  error IxMorseContributionFeed__InvalidWeightAddress();
  error IxMorseContributionFeed__InvalidWeightCount();
  error IxMorseContributionFeed__InvalidTotalWeight();
  error IxMorseContributionFeed__InvalidStakerCount();
  error IxMorseContributionFeed__InvalidWeight();
  error IxMorseContributionFeed__ReportNotReady();

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @notice Get the epoch feeder contract
  function epochFeeder() external view returns (IEpochFeeder);

  /// @notice Get the number of stakers in an epoch
  /// @param epoch Epoch number
  /// @return Number of stakers
  function weightCount(uint256 epoch) external view returns (uint256);

  /// @notice Get staker weight at a specific index
  /// @param epoch Epoch number
  /// @param index Index in the weights array
  /// @return Staker weight
  function weightAt(uint256 epoch, uint256 index) external view returns (StakerWeight memory);

  /// @notice Get staker weight for a specific address
  /// @param epoch Epoch number
  /// @param staker Staker address
  /// @return weight Staker weight
  /// @return exists Whether the staker exists in this epoch
  function weightOf(uint256 epoch, address staker)
    external
    view
    returns (StakerWeight memory weight, bool exists);

  /// @notice Check if epoch contribution is available for claims
  /// @param epoch Epoch number
  /// @return True if epoch is finalized
  function available(uint256 epoch) external view returns (bool);

  /// @notice Get summary of an epoch's contributions
  /// @param epoch Epoch number
  /// @return Summary information
  function summary(uint256 epoch) external view returns (Summary memory);

  /// @notice Get next epoch to be initialized
  function nextEpoch() external view returns (uint256);

  //====================================================================================//
  //================================== FEEDER FUNCTIONS ================================//
  //====================================================================================//

  /// @notice Initialize a report for the next epoch
  /// @param request Report initialization request
  function initializeReport(InitReportRequest calldata request) external;

  /// @notice Push staker weights in batches (max 1000 per call)
  /// @param weights Array of staker weights
  function pushStakerWeights(StakerWeight[] calldata weights) external;

  /// @notice Finalize the current report
  function finalizeReport() external;

  /// @notice Revoke the current report (batched for gas safety)
  function revokeReport() external;
}

