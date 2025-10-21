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

import { IxMorseStaking } from './interfaces/IxMorseStaking.sol';
import { IDN404 } from './interfaces/IDN404.sol';

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
    uint256 accRewardPerNFT; // Accumulated rewards per NFT (scaled by 1e18)
    uint256 totalUnclaimedRewards; // Total unclaimed rewards across all NFTs
    mapping(uint256 => NFTInfo) nftInfo; // tokenId => NFTInfo
    mapping(address => uint256[]) userStakedNFTs; // user => array of tokenIds
    mapping(uint256 => uint256) tokenIdToIndex; // tokenId => index in userStakedNFTs array
    uint256 lockupPeriod; // Configurable lockup period (replaces constant)
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

  /// @notice Default lockup period for staked NFTs (7 days)
  uint256 public constant DEFAULT_LOCKUP_PERIOD = 7 days;

  /// @notice Precision multiplier for reward calculations
  uint256 public constant PRECISION = 1e18;

  //====================================================================================//
  //================================== EVENTS ==========================================//
  //====================================================================================//

  /// @notice Emitted when lockup period is updated
  event LockupPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

  //====================================================================================//
  //================================== ERRORS ==========================================//
  //====================================================================================//

  /// @notice Thrown when lockup period is too short (< 1 second)
  error LockupPeriodTooShort();

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
    $.lockupPeriod = DEFAULT_LOCKUP_PERIOD; // Initialize with 7 days

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

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];

      // Check if NFT is already staked
      if ($.nftInfo[tokenId].owner != address(0)) revert NFTAlreadyStaked(tokenId);

      // Transfer NFT from user to this contract
      IERC721($.mirrorNFT).safeTransferFrom(staker, address(this), tokenId);

      // Update NFT info with current lockup period
      uint256 lockupEndTime = block.timestamp + $.lockupPeriod;
      $.nftInfo[tokenId] = NFTInfo({
        owner: staker,
        stakedAt: block.timestamp,
        lockupEndTime: lockupEndTime,
        unclaimedRewards: 0,
        rewardDebt: $.accRewardPerNFT
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

      // Calculate and check unclaimed rewards
      uint256 pending = _calculatePendingRewards($, tokenId);
      if (pending > 0) revert UnclaimedRewardsExist(tokenId);

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

  /// @inheritdoc IxMorseStaking
  /// @dev Only owner can distribute rewards to control distribution timing
  function distributeRewards() external onlyOwner nonReentrant whenNotPaused {
    StorageV1 storage $ = _getStorageV1();

    if ($.totalStakedNFTs == 0) revert NoStakersInPool();

    // Get reward token balance held by this contract
    uint256 currentBalance = IERC20($.rewardToken).balanceOf(address(this));
    
    // Calculate new rewards (current balance - already allocated unclaimed rewards)
    uint256 rewardAmount = currentBalance - $.totalUnclaimedRewards;
    if (rewardAmount == 0) revert NoRewardsAvailable();

    // Update accumulated rewards per NFT
    uint256 rewardPerNFT = (rewardAmount * PRECISION) / $.totalStakedNFTs;
    $.accRewardPerNFT += rewardPerNFT;
    
    // Update total unclaimed rewards
    $.totalUnclaimedRewards += rewardAmount;

    emit RewardsDistributed(rewardAmount, $.accRewardPerNFT);
  }

  /// @inheritdoc IxMorseStaking
  function claimRewards(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
    if (tokenIds.length == 0) revert EmptyArray();

    StorageV1 storage $ = _getStorageV1();
    address caller = _msgSender();
    uint256 totalRewards = 0;

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      NFTInfo storage info = $.nftInfo[tokenId];

      // Verify ownership
      if (info.owner != caller) revert NotNFTOwner(tokenId);
      if (info.owner == address(0)) revert NFTNotStaked(tokenId);

      // Calculate pending rewards
      uint256 pending = _calculatePendingRewards($, tokenId);

      if (pending > 0) {
        // Update NFT info
        info.unclaimedRewards = 0;
        info.rewardDebt = $.accRewardPerNFT;

        totalRewards += pending;

        emit RewardsClaimed(caller, tokenId, pending);
      }
    }

    // Transfer rewards if any
    if (totalRewards > 0) {
      // Decrease total unclaimed rewards
      $.totalUnclaimedRewards -= totalRewards;
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

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      NFTInfo storage info = $.nftInfo[tokenId];

      // Calculate pending rewards
      uint256 pending = _calculatePendingRewards($, tokenId);

      if (pending > 0) {
        // Update NFT info
        info.unclaimedRewards = 0;
        info.rewardDebt = $.accRewardPerNFT;

        totalRewards += pending;

        emit RewardsClaimed(caller, tokenId, pending);
      }
    }

    // Transfer rewards if any
    if (totalRewards > 0) {
      // Decrease total unclaimed rewards
      $.totalUnclaimedRewards -= totalRewards;
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
    address oldToken = $.rewardToken;
    $.rewardToken = _rewardToken;

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

  /// @inheritdoc IxMorseStaking
  function accRewardPerNFT() external view returns (uint256) {
    return _getStorageV1().accRewardPerNFT;
  }

  /// @notice Get current lockup period
  /// @return Current lockup period in seconds
  function lockupPeriod() external view returns (uint256) {
    return _getStorageV1().lockupPeriod;
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

    // pending = (accRewardPerNFT - rewardDebt) / PRECISION + unclaimedRewards
    uint256 accReward = $.accRewardPerNFT;
    if (accReward > info.rewardDebt) {
      pending = ((accReward - info.rewardDebt) / PRECISION) + info.unclaimedRewards;
    } else {
      pending = info.unclaimedRewards;
    }
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

