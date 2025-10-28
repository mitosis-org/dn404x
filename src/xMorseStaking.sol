// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@ozu/utils/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@ozu/utils/PausableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';
import { IERC721Receiver } from '@oz/token/ERC721/IERC721Receiver.sol';

import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';
import { IEpochFeeder } from '@mitosis/interfaces/hub/validator/IEpochFeeder.sol';

import { IxMorseStaking } from './interfaces/IxMorseStaking.sol';
import { IxMorseRewardFeed } from './interfaces/IxMorseRewardFeed.sol';
import { IDN404 } from './interfaces/IDN404.sol';

/// @notice Interface for Mitosis ValidatorRewardDistributor
interface IValidatorRewardDistributor {
  function claimOperatorRewards(address valAddr) external returns (uint256);
}

/// @title xMorseStaking
/// @notice Production-ready NFT staking contract for xMorse MirrorERC721 tokens
/// @dev Implements UUPS upgradeable pattern with ERC-7201 storage namespacing
contract xMorseStaking is
  IxMorseStaking,
  Ownable2StepUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  IERC721Receiver
{
  using SafeERC20 for IERC20;
  using ERC7201Utils for string;

  //====================================================================================//
  //================================== STORAGE DEFINITION ==============================//
  //====================================================================================//

  /// @custom:storage-location erc7201:mitosis.storage.xMorseStaking
  struct StorageV1 {
    address xMorseToken; // xMorse DN404 token address
    address mirrorNFT; // xMorse MirrorERC721 address
    address rewardToken; // Reward token address (owner configurable)
    uint256 totalStakedNFTs; // Total number of NFTs staked
    uint256 accRewardPerNFT; // [DEPRECATED] Accumulated rewards per NFT (scaled by 1e18)
    uint256 totalUnclaimedRewards; // [DEPRECATED] Total unclaimed rewards across all NFTs
    mapping(uint256 => NFTInfo) nftInfo; // tokenId => NFTInfo
    mapping(address => uint256[]) userStakedNFTs; // user => array of tokenIds
    mapping(uint256 => uint256) tokenIdToIndex; // tokenId => index in userStakedNFTs array
    uint256 lockupPeriod; // Configurable lockup period (replaces constant)
    address validatorRewardDistributor; // ValidatorRewardDistributor contract (optional)
    address validatorAddress; // Validator address for claiming operator rewards (optional)
    address operator; // Operator address that can call distributeRewards
    uint256 accumulatedDust; // Accumulated dust from precision loss
    address rewardFeed; // xMorseRewardFeed contract for epoch-based rewards
    mapping(uint256 => uint256) lastClaimedEpoch; // tokenId => last claimed epoch
  }

  string private constant _NAMESPACE = 'mitosis.storage.xMorseStaking';
  bytes32 private immutable _STORAGE_SLOT = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _STORAGE_SLOT;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }

  //====================================================================================//
  //================================== CONSTANTS =======================================//
  //====================================================================================//

  /// @notice Default lockup period for staked NFTs (21 days)
  uint256 public constant DEFAULT_LOCKUP_PERIOD = 21 days;

  /// @notice Precision multiplier for reward calculations
  uint256 public constant PRECISION = 1e18;

  //====================================================================================//
  //================================== ERRORS ==========================================//
  //====================================================================================//

  /// @notice Thrown when lockup period is too short (< 1 second)
  error LockupPeriodTooShort();

  //====================================================================================//
  //================================== MODIFIERS =======================================//
  //====================================================================================//

  /// @notice Modifier to restrict function access to owner or operator
  modifier onlyOwnerOrOperator() {
    StorageV1 storage $ = _getStorageV1();
    if (_msgSender() != owner() && _msgSender() != $.operator) {
      revert IxMorseStaking.NotAuthorized();
    }
    _;
  }

  //====================================================================================//
  //================================== INITIALIZATION ==================================//
  //====================================================================================//

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @inheritdoc IxMorseStaking
  function initialize(
    address _xMorseToken,
    address _mirrorNFT,
    address _rewardToken,
    address _owner
  ) external initializer {
    if (_xMorseToken == address(0)) revert ZeroAddress();
    if (_mirrorNFT == address(0)) revert ZeroAddress();
    if (_rewardToken == address(0)) revert ZeroAddress();
    if (_owner == address(0)) revert ZeroAddress();

    __Ownable_init(_owner);
    __Ownable2Step_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __UUPSUpgradeable_init();

    StorageV1 storage $ = _getStorageV1();
    $.xMorseToken = _xMorseToken;
    $.mirrorNFT = _mirrorNFT;
    $.rewardToken = _rewardToken;
    $.lockupPeriod = DEFAULT_LOCKUP_PERIOD; // Initialize with 21 days

    // CRITICAL: Set skipNFT to true to prevent automatic NFT minting
    // when receiving DN404 tokens from NFT transfers
    IDN404(_xMorseToken).setSkipNFT(true);
  }

  //====================================================================================//
  //================================== STAKING FUNCTIONS ===============================//
  //====================================================================================//

  /// @inheritdoc IxMorseStaking
  function stake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
    if (tokenIds.length == 0) revert EmptyArray();

    StorageV1 storage $ = _getStorageV1();
    address staker = _msgSender();

    // Get current epoch for V2 epoch-based rewards
    uint256 currentEpoch = 0;
    if ($.rewardFeed != address(0)) {
      IxMorseRewardFeed feed = IxMorseRewardFeed($.rewardFeed);
      currentEpoch = feed.epochFeeder().epoch();
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];

      // Check if NFT is already staked
      if ($.nftInfo[tokenId].owner != address(0)) revert NFTAlreadyStaked(tokenId);

      // Transfer NFT from user to this contract
      IERC721($.mirrorNFT).safeTransferFrom(staker, address(this), tokenId);

      // Update NFT info with current lockup period and epoch
      uint256 lockupEndTime = block.timestamp + $.lockupPeriod;
      $.nftInfo[tokenId] = NFTInfo({
        owner: staker,
        stakedAt: block.timestamp,
        lockupEndTime: lockupEndTime,
        unclaimedRewards: 0,      // DEPRECATED but keep for storage compatibility
        rewardDebt: 0,             // DEPRECATED but keep for storage compatibility
        stakedEpoch: currentEpoch  // V2: Record epoch
      });

      // Add to user's staked NFTs array
      $.tokenIdToIndex[tokenId] = $.userStakedNFTs[staker].length;
      $.userStakedNFTs[staker].push(tokenId);

      // Increment total staked
      $.totalStakedNFTs++;

      emit NFTStaked(staker, tokenId, lockupEndTime);
    }
  }

  /// @inheritdoc IxMorseStaking
  function unstake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
    if (tokenIds.length == 0) revert EmptyArray();

    StorageV1 storage $ = _getStorageV1();
    address caller = _msgSender();

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      NFTInfo storage info = $.nftInfo[tokenId];

      // Verify ownership
      if (info.owner != caller) revert NotNFTOwner(tokenId);
      if (info.owner == address(0)) revert NFTNotStaked(tokenId);

      // Check lockup period
      if (block.timestamp < info.lockupEndTime) revert LockupPeriodNotEnded(tokenId);

      // V2: Allow unstake even with pending rewards (user can claim separately)
      // V1: Required claim before unstake (deprecated)

      // Transfer NFT back to user
      IERC721($.mirrorNFT).safeTransferFrom(address(this), caller, tokenId);

      // Remove from user's staked NFTs array
      _removeFromUserStakedNFTs($, caller, tokenId);

      // Clear NFT info
      delete $.nftInfo[tokenId];

      // Decrement total staked
      $.totalStakedNFTs--;

      emit NFTUnstaked(caller, tokenId);
    }
  }

  //====================================================================================//
  //================================== REWARD FUNCTIONS ================================//
  //====================================================================================//

  /// @notice [DEPRECATED V1] Use claimFromValidator() + FEEDER instead
  /// @dev This function is deprecated in V2. Use epoch-based feeding system.
  /// @dev Kept for backward compatibility but will revert if rewardFeed is configured
  function distributeRewards() external view onlyOwnerOrOperator {
    StorageV1 storage $ = _getStorageV1();
    
    // V2: Revert if using epoch-based system
    if ($.rewardFeed != address(0)) {
      revert("DEPRECATED: Use claimFromValidator() + FEEDER feeding instead");
    }
    
    // V1: Legacy logic (not recommended)
    revert("V1 distributeRewards is deprecated. Upgrade to V2 epoch-based system.");
  }

  /// @inheritdoc IxMorseStaking
  function claimRewards(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
    if (tokenIds.length == 0) revert EmptyArray();

    StorageV1 storage $ = _getStorageV1();
    address caller = _msgSender();
    uint256 totalRewards = 0;

    // Get current epoch for V2
    uint256 currentEpoch = 0;
    if ($.rewardFeed != address(0)) {
      IxMorseRewardFeed feed = IxMorseRewardFeed($.rewardFeed);
      currentEpoch = feed.epochFeeder().epoch();
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      NFTInfo storage info = $.nftInfo[tokenId];

      // Verify ownership
      if (info.owner != caller) revert NotNFTOwner(tokenId);
      if (info.owner == address(0)) revert NFTNotStaked(tokenId);

      // Calculate pending rewards
      uint256 pending = _calculatePendingRewards($, tokenId);

      if (pending > 0) {
        // V2: Update last claimed epoch
        if ($.rewardFeed != address(0) && currentEpoch > 0) {
          $.lastClaimedEpoch[tokenId] = currentEpoch - 1; // Claim up to previous epoch
        }

        totalRewards += pending;

        emit RewardsClaimed(caller, tokenId, pending);
      }
    }

    // Transfer rewards if any
    if (totalRewards > 0) {
      IERC20($.rewardToken).safeTransfer(caller, totalRewards);
    }
  }

  /// @inheritdoc IxMorseStaking
  function claimAllRewards() external nonReentrant whenNotPaused {
    StorageV1 storage $ = _getStorageV1();
    address caller = _msgSender();
    uint256[] memory tokenIds = $.userStakedNFTs[caller];

    if (tokenIds.length == 0) revert EmptyArray();

    uint256 totalRewards = 0;

    // Get current epoch for V2
    uint256 currentEpoch = 0;
    if ($.rewardFeed != address(0)) {
      IxMorseRewardFeed feed = IxMorseRewardFeed($.rewardFeed);
      currentEpoch = feed.epochFeeder().epoch();
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      NFTInfo storage info = $.nftInfo[tokenId];

      // Calculate pending rewards
      uint256 pending = _calculatePendingRewards($, tokenId);

      if (pending > 0) {
        // V2: Update last claimed epoch
        if ($.rewardFeed != address(0) && currentEpoch > 0) {
          $.lastClaimedEpoch[tokenId] = currentEpoch - 1; // Claim up to previous epoch
        }

        totalRewards += pending;

        emit RewardsClaimed(caller, tokenId, pending);
      }
    }

    // Transfer rewards if any
    if (totalRewards > 0) {
      IERC20($.rewardToken).safeTransfer(caller, totalRewards);
    }
  }

  //====================================================================================//
  //================================== OWNER FUNCTIONS =================================//
  //====================================================================================//

  /// @inheritdoc IxMorseStaking
  function setRewardToken(address _rewardToken) external onlyOwner {
    if (_rewardToken == address(0)) revert ZeroAddress();

    StorageV1 storage $ = _getStorageV1();
    
    // V2: Simpler - just check contract balance is clean
    uint256 balance = IERC20($.rewardToken).balanceOf(address(this));
    if (balance > $.accumulatedDust) {
      revert("Cannot change reward token with remaining balance");
    }

    address oldToken = $.rewardToken;
    $.rewardToken = _rewardToken;
    
    // Reset accumulated dust when changing reward token
    $.accumulatedDust = 0;

    emit RewardTokenUpdated(oldToken, _rewardToken);
  }

  /// @notice Set lockup period for newly staked NFTs
  /// @param _lockupPeriod New lockup period in seconds
  function setLockupPeriod(uint256 _lockupPeriod) external onlyOwner {
    if (_lockupPeriod < 1) revert LockupPeriodTooShort();

    StorageV1 storage $ = _getStorageV1();
    uint256 oldPeriod = $.lockupPeriod;
    $.lockupPeriod = _lockupPeriod;

    emit LockupPeriodUpdated(oldPeriod, _lockupPeriod);
  }

  /// @notice Set ValidatorRewardDistributor contract address
  /// @param _validatorRewardDistributor Address of ValidatorRewardDistributor contract (0 to disable)
  function setValidatorRewardDistributor(address _validatorRewardDistributor) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    address oldDistributor = $.validatorRewardDistributor;
    $.validatorRewardDistributor = _validatorRewardDistributor;

    emit ValidatorRewardDistributorUpdated(oldDistributor, _validatorRewardDistributor);
  }

  /// @notice Set validator address for claiming operator rewards
  /// @param _validatorAddress Validator address to claim rewards for (0 to disable)
  function setValidatorAddress(address _validatorAddress) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    address oldValidator = $.validatorAddress;
    $.validatorAddress = _validatorAddress;

    emit ValidatorAddressUpdated(oldValidator, _validatorAddress);
  }

  /// @notice Get ValidatorRewardDistributor contract address
  function validatorRewardDistributor() external view returns (address) {
    return _getStorageV1().validatorRewardDistributor;
  }

  /// @notice Get validator address
  function validatorAddress() external view returns (address) {
    return _getStorageV1().validatorAddress;
  }

  /// @notice Set operator address that can call distributeRewards
  /// @param _operator Address of the operator (0 to disable)
  function setOperator(address _operator) external onlyOwner {
    StorageV1 storage $ = _getStorageV1();
    address oldOperator = $.operator;
    $.operator = _operator;

    emit IxMorseStaking.OperatorUpdated(oldOperator, _operator);
  }

  /// @notice Get operator address
  function operator() external view returns (address) {
    return _getStorageV1().operator;
  }

  /// @inheritdoc IxMorseStaking
  function pause() external onlyOwner {
    _pause();
  }

  /// @inheritdoc IxMorseStaking
  function unpause() external onlyOwner {
    _unpause();
  }

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @inheritdoc IxMorseStaking
  function getStakedNFTs(address user) external view returns (uint256[] memory tokenIds) {
    return _getStorageV1().userStakedNFTs[user];
  }

  /// @inheritdoc IxMorseStaking
  function getNFTInfo(uint256 tokenId) external view returns (NFTInfo memory info) {
    return _getStorageV1().nftInfo[tokenId];
  }

  /// @inheritdoc IxMorseStaking
  function getTotalStakedNFTs() external view returns (uint256 total) {
    return _getStorageV1().totalStakedNFTs;
  }

  /// @inheritdoc IxMorseStaking
  function getPendingRewards(uint256 tokenId) external view returns (uint256 pending) {
    return _calculatePendingRewards(_getStorageV1(), tokenId);
  }

  /// @inheritdoc IxMorseStaking
  function xMorseToken() external view returns (address) {
    return _getStorageV1().xMorseToken;
  }

  /// @inheritdoc IxMorseStaking
  function mirrorNFT() external view returns (address) {
    return _getStorageV1().mirrorNFT;
  }

  /// @inheritdoc IxMorseStaking
  function rewardToken() external view returns (address) {
    return _getStorageV1().rewardToken;
  }

  /// @notice [DEPRECATED V1] Accumulated rewards per NFT
  /// @dev This value is no longer updated in V2. Use epoch-based getPendingRewards() instead.
  /// @return Deprecated value (frozen at upgrade)
  function accRewardPerNFT() external view returns (uint256) {
    return _getStorageV1().accRewardPerNFT;
  }

  /// @notice Get current lockup period
  /// @return Current lockup period in seconds
  function lockupPeriod() external view returns (uint256) {
    return _getStorageV1().lockupPeriod;
  }

  /// @notice Get accumulated dust from precision loss
  /// @return Accumulated dust amount
  function accumulatedDust() external view returns (uint256) {
    return _getStorageV1().accumulatedDust;
  }

  /// @notice Withdraw accumulated dust to owner
  /// @dev Only owner can withdraw dust to prevent reward loss
  function withdrawDust() external onlyOwner nonReentrant {
    StorageV1 storage $ = _getStorageV1();
    uint256 dust = $.accumulatedDust;
    
    if (dust == 0) revert ZeroAmount();
    
    $.accumulatedDust = 0;
    IERC20($.rewardToken).safeTransfer(owner(), dust);
  }

  /// @notice Get reward feed address
  /// @return Reward feed contract address
  function rewardFeed() external view returns (address) {
    return _getStorageV1().rewardFeed;
  }

  /// @notice Get last claimed epoch for a token
  /// @param tokenId Token ID
  /// @return Last claimed epoch number
  function lastClaimedEpoch(uint256 tokenId) external view returns (uint256) {
    return _getStorageV1().lastClaimedEpoch[tokenId];
  }

  //====================================================================================//
  //================================== V2 EPOCH-BASED FUNCTIONS ========================//
  //====================================================================================//

  /// @notice Set reward feed contract address (V2)
  /// @param _rewardFeed Address of xMorseRewardFeed contract
  function setRewardFeed(address _rewardFeed) external onlyOwner {
    if (_rewardFeed == address(0)) revert ZeroAddress();

    StorageV1 storage $ = _getStorageV1();
    $.rewardFeed = _rewardFeed;
  }

  /// @notice Claim gMITO from ValidatorRewardDistributor (V2)
  /// @dev Owner/Operator calls this to pull validator rewards
  /// @dev FEEDER then feeds this amount to xMorseRewardFeed
  function claimFromValidator() external onlyOwnerOrOperator nonReentrant returns (uint256) {
    StorageV1 storage $ = _getStorageV1();

    if ($.validatorRewardDistributor == address(0)) revert ZeroAddress();
    if ($.validatorAddress == address(0)) revert ZeroAddress();

    uint256 claimed = IValidatorRewardDistributor($.validatorRewardDistributor).claimOperatorRewards(
      $.validatorAddress
    );

    if (claimed > 0) {
      emit ValidatorRewardsClaimed($.validatorAddress, claimed);
    }

    return claimed;
  }

  /// @notice Get current gMITO balance available for feeding
  /// @return Available balance (excluding dust)
  function availableForFeeding() external view returns (uint256) {
    StorageV1 storage $ = _getStorageV1();
    uint256 balance = IERC20($.rewardToken).balanceOf(address(this));
    return balance > $.accumulatedDust ? balance - $.accumulatedDust : 0;
  }

  //====================================================================================//
  //================================== ERC721 RECEIVER =================================//
  //====================================================================================//

  /// @notice Handle the receipt of an NFT
  /// @dev The ERC721 smart contract calls this function on the recipient after a transfer
  function onERC721Received(address, address, uint256, bytes calldata)
    external
    pure
    override
    returns (bytes4)
  {
    return this.onERC721Received.selector;
  }

  //====================================================================================//
  //================================== INTERNAL FUNCTIONS ==============================//
  //====================================================================================//

  /// @notice Calculate pending rewards for a specific NFT
  /// @param $ Storage pointer
  /// @param tokenId ID of the NFT
  /// @return pending Amount of pending rewards
  function _calculatePendingRewards(StorageV1 storage $, uint256 tokenId)
    internal
    view
    returns (uint256 pending)
  {
    NFTInfo storage info = $.nftInfo[tokenId];
    if (info.owner == address(0)) return 0;

    // V2: Epoch-based rewards (if rewardFeed is configured)
    if ($.rewardFeed != address(0)) {
      return _calculatePendingRewardsV2($, tokenId);
    }

    // V1: Legacy rewards (backward compatibility - DEPRECATED)
    return 0; // V1 logic deprecated after upgrade
  }

  /// @notice Calculate pending rewards using epoch-based feed (V2)
  /// @param $ Storage pointer
  /// @param tokenId ID of the NFT
  /// @return pending Amount of pending rewards
  function _calculatePendingRewardsV2(StorageV1 storage $, uint256 tokenId)
    internal
    view
    returns (uint256 pending)
  {
    NFTInfo storage info = $.nftInfo[tokenId];
    
    IxMorseRewardFeed feed = IxMorseRewardFeed($.rewardFeed);
    IEpochFeeder epochFeeder = feed.epochFeeder();
    
    // Determine epoch range to claim
    uint256 startEpoch = $.lastClaimedEpoch[tokenId];
    if (startEpoch == 0) {
      startEpoch = info.stakedEpoch;
      // If staked at epoch 0, start claiming from epoch 1
      if (startEpoch == 0) startEpoch = 1;
    } else {
      startEpoch += 1; // Start from next epoch after last claim
    }
    
    uint256 currentEpoch = epochFeeder.epoch();
    
    // Determine end epoch: claim up to last finalized epoch
    // If currentEpoch is 0, we can still claim finalized epochs (like epoch 1)
    uint256 endEpoch;
    if (currentEpoch == 0) {
      // Check what epochs are available
      endEpoch = feed.nextEpoch() > 0 ? feed.nextEpoch() - 1 : 0;
    } else {
      // Don't claim current epoch (may not be finalized)
      endEpoch = currentEpoch > 0 ? currentEpoch - 1 : 0;
    }
    
    if (startEpoch > endEpoch) return 0;
    
    uint256 totalPending = 0;
    
    // Iterate through epochs and accumulate rewards
    for (uint256 epoch = startEpoch; epoch <= endEpoch; epoch++) {
      // Skip if epoch reward not available (not finalized)
      if (!feed.available(epoch)) continue;
      
      IxMorseRewardFeed.EpochReward memory epochReward = feed.rewardForEpoch(epoch);
      
      // Calculate reward for this NFT in this epoch
      if (epochReward.totalStakedNFTs > 0 && epochReward.totalReward > 0) {
        uint256 rewardPerNFT = (epochReward.totalReward * PRECISION) / epochReward.totalStakedNFTs;
        totalPending += rewardPerNFT;
      }
    }
    
    return totalPending / PRECISION;
  }

  /// @notice Remove a token ID from user's staked NFTs array
  /// @param $ Storage pointer
  /// @param user Address of the user
  /// @param tokenId Token ID to remove
  function _removeFromUserStakedNFTs(StorageV1 storage $, address user, uint256 tokenId)
    internal
  {
    uint256[] storage userTokens = $.userStakedNFTs[user];
    uint256 index = $.tokenIdToIndex[tokenId];
    uint256 lastIndex = userTokens.length - 1;

    // If not the last element, swap with last element
    if (index != lastIndex) {
      uint256 lastTokenId = userTokens[lastIndex];
      userTokens[index] = lastTokenId;
      $.tokenIdToIndex[lastTokenId] = index;
    }

    // Remove last element
    userTokens.pop();
    delete $.tokenIdToIndex[tokenId];
  }

  /// @notice Authorize upgrade (owner only)
  /// @param newImplementation Address of new implementation
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
}

