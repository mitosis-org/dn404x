// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { Math } from '@oz/utils/math/Math.sol';
import { SafeCast } from '@oz/utils/math/SafeCast.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';
import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';
import { StdError } from '@mitosis/lib/StdError.sol';
import { IValidatorRewardDistributor } from '@mitosis/interfaces/hub/validator/IValidatorRewardDistributor.sol';

import { IxMorseRewardDistributor } from './interfaces/IxMorseRewardDistributor.sol';
import { IxMorseContributionFeed } from './interfaces/IxMorseContributionFeed.sol';
import { IxMorseStakingV2 } from './interfaces/IxMorseStakingV2.sol';

/// @title xMorseRewardDistributor Storage Contract
/// @notice Storage contract for xMorseRewardDistributor that uses ERC-7201 namespaced storage pattern
contract xMorseRewardDistributorStorageV1 {
  using ERC7201Utils for string;

  /// @custom:storage-location erc7201:mitosis.storage.xMorseRewardDistributor.v1
  struct StorageV1 {
    mapping(address staker => uint256) lastClaimedEpoch;
    mapping(address account => mapping(address claimer => bool)) claimApprovals;
    IxMorseRewardDistributor.ClaimConfig claimConfig;
    address validatorRewardDistributor;  // ValidatorRewardDistributor contract
    address validatorAddress;             // Validator address for claiming
  }

  string private constant _NAMESPACE = 'mitosis.storage.xMorseRewardDistributor.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    assembly {
      $.slot := slot
    }
  }
}

/// @title xMorseRewardDistributor
/// @notice Handles the distribution of rewards to xMorse stakers based on fed contributions
/// @dev Implements reward distribution logic using weight-based calculations
contract xMorseRewardDistributor is
  IxMorseRewardDistributor,
  xMorseRewardDistributorStorageV1,
  Ownable2StepUpgradeable,
  ReentrancyGuard,
  UUPSUpgradeable
{
  using SafeCast for uint256;
  using SafeERC20 for IERC20;

  //====================================================================================//
  //================================== CONSTANTS =======================================//
  //====================================================================================//

  uint8 private constant _CLAIM_CONFIG_VERSION = 1;

  //====================================================================================//
  //================================== IMMUTABLES ======================================//
  //====================================================================================//

  IEpochFeeder private immutable _epochFeeder;
  IxMorseContributionFeed private immutable _contributionFeed;
  IxMorseStakingV2 private immutable _staking;
  IERC20 private immutable _rewardToken;

  //====================================================================================//
  //================================== CONSTRUCTOR =====================================//
  //====================================================================================//

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address epochFeeder_,
    address contributionFeed_,
    address staking_,
    address rewardToken_
  ) {
    _disableInitializers();

    _epochFeeder = IEpochFeeder(epochFeeder_);
    _contributionFeed = IxMorseContributionFeed(contributionFeed_);
    _staking = IxMorseStakingV2(staking_);
    _rewardToken = IERC20(rewardToken_);
  }

  //====================================================================================//
  //================================== INITIALIZATION ==================================//
  //====================================================================================//

  /// @notice Initialize the reward distributor
  /// @param initialOwner_ Initial owner address
  /// @param maxClaimEpochs Maximum epochs to claim at once
  /// @param maxStakerBatchSize Maximum stakers in batch claim
  function initialize(
    address initialOwner_,
    uint32 maxClaimEpochs,
    uint32 maxStakerBatchSize
  ) external initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(initialOwner_);
    __Ownable2Step_init();

    _setClaimConfig(_getStorageV1(), maxClaimEpochs, maxStakerBatchSize);
  }

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @inheritdoc IxMorseRewardDistributor
  function epochFeeder() external view returns (IEpochFeeder) {
    return _epochFeeder;
  }

  /// @inheritdoc IxMorseRewardDistributor
  function contributionFeed() external view returns (IxMorseContributionFeed) {
    return _contributionFeed;
  }

  /// @inheritdoc IxMorseRewardDistributor
  function staking() external view returns (IxMorseStakingV2) {
    return _staking;
  }

  /// @inheritdoc IxMorseRewardDistributor
  function rewardToken() external view returns (address) {
    return address(_rewardToken);
  }

  /// @inheritdoc IxMorseRewardDistributor
  function validatorRewardDistributor() external view returns (address) {
    return _getStorageV1().validatorRewardDistributor;
  }

  /// @inheritdoc IxMorseRewardDistributor
  function validatorAddress() external view returns (address) {
    return _getStorageV1().validatorAddress;
  }

  /// @inheritdoc IxMorseRewardDistributor
  function claimConfig() external view returns (ClaimConfigResponse memory) {
    IxMorseRewardDistributor.ClaimConfig memory claimConfig_ = _getStorageV1().claimConfig;

    return ClaimConfigResponse({
      version: _CLAIM_CONFIG_VERSION,
      maxClaimEpochs: claimConfig_.maxClaimEpochs,
      maxStakerBatchSize: claimConfig_.maxStakerBatchSize
    });
  }

  /// @inheritdoc IxMorseRewardDistributor
  function claimAllowed(address account, address claimer) external view returns (bool) {
    return _isClaimable(account, claimer, _getStorageV1().claimApprovals);
  }

  /// @inheritdoc IxMorseRewardDistributor
  function lastClaimedEpoch(address staker) external view returns (uint256) {
    return _getStorageV1().lastClaimedEpoch[staker];
  }

  /// @inheritdoc IxMorseRewardDistributor
  function claimableRewards(address staker) external view returns (uint256, uint256) {
    StorageV1 storage $ = _getStorageV1();
    uint32 maxClaimEpochs = $.claimConfig.maxClaimEpochs;
    return _claimableRewards($, staker, maxClaimEpochs);
  }

  //====================================================================================//
  //================================== MUTATIVE FUNCTIONS ==============================//
  //====================================================================================//

  /// @inheritdoc IxMorseRewardDistributor
  function setClaimApprovalStatus(address claimer, bool approval) external {
    _getStorageV1().claimApprovals[_msgSender()][claimer] = approval;
    emit ClaimApprovalUpdated(_msgSender(), claimer, approval);
  }

  /// @inheritdoc IxMorseRewardDistributor
  function claimRewards(address staker) external nonReentrant returns (uint256) {
    return _claimRewards(_getStorageV1(), staker, _msgSender());
  }

  /// @inheritdoc IxMorseRewardDistributor
  function batchClaimRewards(address[] calldata stakers) external nonReentrant returns (uint256) {
    StorageV1 storage $ = _getStorageV1();
    require(
      stakers.length <= $.claimConfig.maxStakerBatchSize,
      IxMorseRewardDistributor__MaxStakerBatchSizeExceeded()
    );

    uint256 totalClaimed;
    for (uint256 i = 0; i < stakers.length; i++) {
      totalClaimed += _claimRewards($, stakers[i], _msgSender());
    }

    return totalClaimed;
  }

  //====================================================================================//
  //================================== OWNER FUNCTIONS =================================//
  //====================================================================================//

  /// @inheritdoc IxMorseRewardDistributor
  function setClaimConfig(uint32 maxClaimEpochs, uint32 maxStakerBatchSize) external onlyOwner {
    _setClaimConfig(_getStorageV1(), maxClaimEpochs, maxStakerBatchSize);
  }

  /// @inheritdoc IxMorseRewardDistributor
  function setValidatorRewardDistributor(address _validatorRewardDistributor) external onlyOwner {
    _getStorageV1().validatorRewardDistributor = _validatorRewardDistributor;
  }

  /// @inheritdoc IxMorseRewardDistributor
  function setValidatorAddress(address _validatorAddress) external onlyOwner {
    _getStorageV1().validatorAddress = _validatorAddress;
  }

  /// @inheritdoc IxMorseRewardDistributor
  function claimFromValidator() external onlyOwner nonReentrant returns (uint256) {
    StorageV1 storage $ = _getStorageV1();

    require($.validatorRewardDistributor != address(0), "ValidatorRewardDistributor not set");
    require($.validatorAddress != address(0), "Validator address not set");

    uint256 claimed = IValidatorRewardDistributor($.validatorRewardDistributor).claimOperatorRewards(
      $.validatorAddress
    );

    if (claimed > 0) {
      emit ValidatorRewardsClaimed($.validatorAddress, claimed);
    }

    return claimed;
  }

  //====================================================================================//
  //================================== INTERNAL FUNCTIONS ==============================//
  //====================================================================================//

  /// @notice Set claim configuration
  function _setClaimConfig(
    StorageV1 storage $,
    uint32 maxClaimEpochs,
    uint32 maxStakerBatchSize
  ) internal {
    IxMorseRewardDistributor.ClaimConfig memory newClaimConfig = IxMorseRewardDistributor.ClaimConfig({
      maxClaimEpochs: maxClaimEpochs,
      maxStakerBatchSize: maxStakerBatchSize,
      reserved: 0
    });
    $.claimConfig = newClaimConfig;
    emit ClaimConfigUpdated(_CLAIM_CONFIG_VERSION, abi.encode(newClaimConfig));
  }

  /// @notice Calculate claimable rewards for a staker
  function _claimableRewards(StorageV1 storage $, address staker, uint256 epochCount)
    internal
    view
    returns (uint256, uint256)
  {
    (uint256 start, uint256 end) = _claimRange($.lastClaimedEpoch[staker], _epochFeeder.epoch(), epochCount);
    if (start == end) return (0, start);

    uint256 totalClaimable;

    for (uint256 epoch = start; epoch <= end; epoch++) {
      if (!_contributionFeed.available(epoch)) return (totalClaimable, epoch);
      totalClaimable += _calculateRewardForEpoch(staker, epoch);
    }

    return (totalClaimable, end + 1);
  }

  /// @notice Claim rewards for a staker
  function _claimRewards(StorageV1 storage $, address staker, address recipient)
    internal
    returns (uint256)
  {
    _assertClaimApproval(staker, recipient, $.claimApprovals);

    (uint256 start, uint256 end) =
      _claimRange($.lastClaimedEpoch[staker], _epochFeeder.epoch(), $.claimConfig.maxClaimEpochs);
    if (start == end) return 0;

    uint256 totalClaimed;
    uint256 lastClaimedEpoch_ = start - 1;

    for (uint256 epoch = start; epoch <= end; epoch++) {
      if (!_contributionFeed.available(epoch)) break;

      uint256 claimable = _calculateRewardForEpoch(staker, epoch);

      if (claimable > 0) {
        totalClaimed += claimable;
      }

      lastClaimedEpoch_ = epoch;
    }

    $.lastClaimedEpoch[staker] = lastClaimedEpoch_;

    if (totalClaimed > 0) {
      _rewardToken.safeTransfer(recipient, totalClaimed);
    }

    emit RewardsClaimed(staker, recipient, totalClaimed, start, lastClaimedEpoch_);

    return totalClaimed;
  }

  /// @notice Calculate reward for a staker in a specific epoch
  function _calculateRewardForEpoch(address staker, uint256 epoch)
    internal
    view
    returns (uint256)
  {
    (IxMorseContributionFeed.StakerWeight memory weight, bool exists) =
      _contributionFeed.weightOf(epoch, staker);
    if (!exists) return 0;

    IxMorseContributionFeed.Summary memory summary = _contributionFeed.summary(epoch);
    
    // Get total reward amount from reward token balance or staking contract
    // For simplicity, we calculate proportional share from weight
    uint256 totalReward = _getTotalRewardForEpoch(epoch);
    if (totalReward == 0 || summary.totalWeight == 0) return 0;

    return (uint256(weight.rewardShare) * totalReward) / uint256(summary.totalWeight);
  }

  /// @notice Get total reward amount for an epoch
  /// @dev This should be implemented based on how rewards are funded
  /// @dev For now, returns the contract's reward token balance divided by active epochs
  function _getTotalRewardForEpoch(uint256 /*epoch*/) internal view returns (uint256) {
    // Simple implementation: return available balance
    // In production, this would track per-epoch reward amounts
    return _rewardToken.balanceOf(address(this));
  }

  /// @notice Calculate claim range
  function _claimRange(uint256 lastClaimedEpoch_, uint256 currentEpoch, uint256 epochCount)
    internal
    pure
    returns (uint256, uint256)
  {
    uint256 startEpoch = lastClaimedEpoch_ + 1; // min epoch is 1
    // do not claim rewards for current epoch
    uint256 endEpoch = (Math.min(currentEpoch, startEpoch + epochCount - 1)).toUint96();
    return (startEpoch, endEpoch);
  }

  /// @notice Assert claim approval
  function _assertClaimApproval(
    address account,
    address recipient,
    mapping(address => mapping(address => bool)) storage claimApprovals
  ) internal view {
    require(_isClaimable(account, recipient, claimApprovals), StdError.Unauthorized());
  }

  /// @notice Check if claiming is allowed
  function _isClaimable(
    address account,
    address recipient,
    mapping(address => mapping(address => bool)) storage claimApprovals
  ) internal view returns (bool) {
    return account == recipient || claimApprovals[account][recipient];
  }

  //====================================================================================//
  //================================== UPGRADE =========================================//
  //====================================================================================//

  /// @notice Authorize upgrade (owner only)
  function _authorizeUpgrade(address) internal override onlyOwner { }
}

