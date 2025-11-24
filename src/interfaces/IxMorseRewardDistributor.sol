// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';
import { IxMorseContributionFeed } from './IxMorseContributionFeed.sol';
import { IxMorseStakingV2 } from './IxMorseStakingV2.sol';

/// @title IxMorseRewardDistributor
/// @notice Interface for xMorse reward distribution based on epoch contributions
interface IxMorseRewardDistributor {
  //====================================================================================//
  //================================== STRUCTS =========================================//
  //====================================================================================//

  /// @notice Configuration for claim operations
  struct ClaimConfig {
    uint32 maxClaimEpochs;      // Maximum number of epochs to claim at once
    uint32 maxStakerBatchSize;  // Maximum number of stakers in batch claim
    uint160 reserved;           // Reserved for future use
  }

  /// @notice Response structure for claim config
  struct ClaimConfigResponse {
    uint8 version;              // Config version
    uint32 maxClaimEpochs;
    uint32 maxStakerBatchSize;
  }

  //====================================================================================//
  //================================== EVENTS ==========================================//
  //====================================================================================//

  /// @notice Emitted when rewards are claimed
  event RewardsClaimed(
    address indexed staker,
    address indexed recipient,
    uint256 totalClaimed,
    uint256 startEpoch,
    uint256 endEpoch
  );

  /// @notice Emitted when claim config is updated
  event ClaimConfigUpdated(uint8 version, bytes data);

  /// @notice Emitted when claim approval status is updated
  event ClaimApprovalUpdated(
    address indexed account, address indexed claimer, bool approval
  );

  /// @notice Emitted when validator rewards are claimed
  event ValidatorRewardsClaimed(address indexed validatorAddress, uint256 amount, uint256 indexed epoch);

  /// @notice Emitted when epoch reward is manually set
  event EpochRewardSet(uint256 indexed epoch, uint256 amount);

  //====================================================================================//
  //================================== ERRORS ==========================================//
  //====================================================================================//

  error IxMorseRewardDistributor__MaxStakerBatchSizeExceeded();
  error IxMorseRewardDistributor__ArrayLengthMismatch();
  error IxMorseRewardDistributor__Unauthorized();

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @notice Get the epoch feeder contract
  function epochFeeder() external view returns (IEpochFeeder);

  /// @notice Get the contribution feed contract
  function contributionFeed() external view returns (IxMorseContributionFeed);

  /// @notice Get the staking contract
  function staking() external view returns (IxMorseStakingV2);

  /// @notice Get the reward token address
  function rewardToken() external view returns (address);

  /// @notice Get validator reward distributor address
  function validatorRewardDistributor() external view returns (address);

  /// @notice Get validator address
  function validatorAddress() external view returns (address);

  /// @notice Get claim configuration
  function claimConfig() external view returns (ClaimConfigResponse memory);

  /// @notice Check if claimer is allowed to claim for an account
  /// @param account Account that owns the rewards
  /// @param claimer Address attempting to claim
  /// @return True if claiming is allowed
  function claimAllowed(address account, address claimer) external view returns (bool);

  /// @notice Get last claimed epoch for a staker
  /// @param staker Staker address
  /// @return Last claimed epoch number
  function lastClaimedEpoch(address staker) external view returns (uint256);

  /// @notice Get total reward for a specific epoch
  /// @param epoch Epoch number
  /// @return Total reward amount for the epoch
  function getEpochReward(uint256 epoch) external view returns (uint256);

  /// @notice Get claimable rewards for a staker
  /// @param staker Staker address
  /// @return claimable Amount of claimable rewards
  /// @return nextEpoch Next epoch after claiming
  function claimableRewards(address staker) external view returns (uint256 claimable, uint256 nextEpoch);

  //====================================================================================//
  //================================== MUTATIVE FUNCTIONS ==============================//
  //====================================================================================//

  /// @notice Set claim approval status for a claimer
  /// @param claimer Address to approve/revoke
  /// @param approval Approval status
  function setClaimApprovalStatus(address claimer, bool approval) external;

  /// @notice Claim rewards for a staker
  /// @param staker Staker address
  /// @return Amount of rewards claimed
  function claimRewards(address staker) external returns (uint256);

  /// @notice Batch claim rewards for multiple stakers
  /// @param stakers Array of staker addresses
  /// @return Total amount of rewards claimed
  function batchClaimRewards(address[] calldata stakers) external returns (uint256);

  /// @notice Claim gMITO from ValidatorRewardDistributor
  /// @dev Owner calls this to pull validator rewards into this contract
  /// @return claimed Amount of gMITO claimed
  function claimFromValidator() external returns (uint256 claimed);

  //====================================================================================//
  //================================== OWNER FUNCTIONS =================================//
  //====================================================================================//

  /// @notice Set claim configuration
  /// @param maxClaimEpochs Maximum epochs to claim at once
  /// @param maxStakerBatchSize Maximum stakers in batch claim
  function setClaimConfig(uint32 maxClaimEpochs, uint32 maxStakerBatchSize) external;

  /// @notice Set ValidatorRewardDistributor contract address
  /// @param _validatorRewardDistributor Address of ValidatorRewardDistributor contract
  function setValidatorRewardDistributor(address _validatorRewardDistributor) external;

  /// @notice Set validator address for claiming operator rewards
  /// @param _validatorAddress Validator address
  function setValidatorAddress(address _validatorAddress) external;

  /// @notice Set reward amount for a specific epoch (manual adjustment)
  /// @param epoch Epoch number
  /// @param amount Total reward amount for the epoch
  function setEpochReward(uint256 epoch, uint256 amount) external;
}

