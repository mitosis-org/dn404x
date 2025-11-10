// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { Time } from '@oz/utils/types/Time.sol';
import { Ownable2StepUpgradeable } from '@ozu/access/Ownable2StepUpgradeable.sol';
import { ReentrancyGuardUpgradeable } from '@ozu/utils/ReentrancyGuardUpgradeable.sol';
import { PausableUpgradeable } from '@ozu/utils/PausableUpgradeable.sol';
import { UUPSUpgradeable } from '@ozu/proxy/utils/UUPSUpgradeable.sol';

import { IERC20 } from '@oz/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { IERC721 } from '@oz/token/ERC721/IERC721.sol';
import { IERC721Receiver } from '@oz/token/ERC721/IERC721Receiver.sol';

import { ERC7201Utils } from '@mitosis/lib/ERC7201Utils.sol';
import { LibCheckpoint } from '@mitosis/lib/LibCheckpoint.sol';
import { StdError } from '@mitosis/lib/StdError.sol';

import { IxMorseStakingV2 } from './interfaces/IxMorseStakingV2.sol';
import { IDN404 } from './interfaces/IDN404.sol';

/// @notice Interface for Mitosis ValidatorRewardDistributor
interface IValidatorRewardDistributor {
  function claimOperatorRewards(address valAddr) external returns (uint256);
}

/// @title xMorseStakingV2 Storage Contract
/// @notice Separates storage from logic using ERC-7201 namespaced storage pattern
contract xMorseStakingV2StorageV1 {
  using ERC7201Utils for string;

  struct StorageV1 {
    // Token addresses
    address xMorseToken;        // xMorse DN404 token address
    address mirrorNFT;          // xMorse MirrorERC721 address
    address rewardToken;        // Reward token address (gMITO)
    
    // TWAB tracking
    LibCheckpoint.TraceTWAB totalStaked;              // Total staked NFT count over time
    mapping(address => LibCheckpoint.TraceTWAB) stakerTotal;  // Per-staker NFT count over time
    
    // NFT management
    mapping(uint256 => IxMorseStakingV2.NFTInfo) nftInfo;     // tokenId => NFTInfo
    mapping(address => uint256[]) userStakedNFTs;             // user => array of tokenIds
    mapping(uint256 => uint256) tokenIdToIndex;               // tokenId => index in userStakedNFTs array
    
    // Configuration
    uint256 lockupPeriod;                   // Configurable lockup period
    address validatorRewardDistributor;     // ValidatorRewardDistributor contract
    address validatorAddress;               // Validator address for claiming operator rewards
  }

  string private constant _NAMESPACE = 'mitosis.storage.xMorseStakingV2.v1';
  bytes32 private immutable _slot = _NAMESPACE.storageSlot();

  function _getStorageV1() internal view returns (StorageV1 storage $) {
    bytes32 slot = _slot;
    // slither-disable-next-line assembly
    assembly {
      $.slot := slot
    }
  }
}

/// @title xMorseStakingV2
/// @notice Production-ready NFT staking contract with TWAB tracking
/// @dev Implements UUPS upgradeable pattern with ERC-7201 storage namespacing
contract xMorseStakingV2 is
  IxMorseStakingV2,
  xMorseStakingV2StorageV1,
  Ownable2StepUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  UUPSUpgradeable,
  IERC721Receiver
{
  using SafeERC20 for IERC20;
  using LibCheckpoint for LibCheckpoint.TraceTWAB;

  //====================================================================================//
  //================================== CONSTANTS =======================================//
  //====================================================================================//

  /// @notice Default lockup period for staked NFTs (21 days)
  uint256 public constant DEFAULT_LOCKUP_PERIOD = 21 days;

  //====================================================================================//
  //================================== INITIALIZATION ==================================//
  //====================================================================================//

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the staking contract
  /// @param _xMorseToken xMorse DN404 token address
  /// @param _mirrorNFT xMorse MirrorERC721 address
  /// @param _rewardToken Reward token address (gMITO)
  /// @param _owner Initial owner address
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
    $.lockupPeriod = DEFAULT_LOCKUP_PERIOD;

    // CRITICAL: Set skipNFT to true to prevent automatic NFT minting
    // when receiving DN404 tokens from NFT transfers
    IDN404(_xMorseToken).setSkipNFT(true);
  }

  //====================================================================================//
  //================================== STAKING FUNCTIONS ===============================//
  //====================================================================================//

  /// @inheritdoc IxMorseStakingV2
  function stake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
    if (tokenIds.length == 0) revert EmptyArray();

    StorageV1 storage $ = _getStorageV1();
    address staker = _msgSender();
    uint48 now_ = Time.timestamp();

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
        unclaimedRewards: 0,  // DEPRECATED but keep for storage compatibility
        rewardDebt: 0,        // DEPRECATED but keep for storage compatibility
        stakedEpoch: 0        // Not used in V2 TWAB system
      });

      // Add to user's staked NFTs array
      $.tokenIdToIndex[tokenId] = $.userStakedNFTs[staker].length;
      $.userStakedNFTs[staker].push(tokenId);

      emit NFTStaked(staker, tokenId, lockupEndTime);
    }

    // Update TWAB: increase NFT count by tokenIds.length
    uint256 count = tokenIds.length;
    $.stakerTotal[staker].push(count, now_, LibCheckpoint.add);
    $.totalStaked.push(count, now_, LibCheckpoint.add);
  }

  /// @inheritdoc IxMorseStakingV2
  function unstake(uint256[] calldata tokenIds) external nonReentrant whenNotPaused {
    if (tokenIds.length == 0) revert EmptyArray();

    StorageV1 storage $ = _getStorageV1();
    address caller = _msgSender();
    uint48 now_ = Time.timestamp();

    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      NFTInfo storage info = $.nftInfo[tokenId];

      // Verify ownership
      if (info.owner != caller) revert NotNFTOwner(tokenId);
      if (info.owner == address(0)) revert NFTNotStaked(tokenId);

      // Check lockup period
      if (block.timestamp < info.lockupEndTime) revert LockupPeriodNotEnded(tokenId);

      // Transfer NFT back to user
      IERC721($.mirrorNFT).safeTransferFrom(address(this), caller, tokenId);

      // Remove from user's staked NFTs array
      _removeFromUserStakedNFTs($, caller, tokenId);

      // Clear NFT info
      delete $.nftInfo[tokenId];

      emit NFTUnstaked(caller, tokenId);
    }

    // Update TWAB: decrease NFT count by tokenIds.length
    uint256 count = tokenIds.length;
    $.stakerTotal[caller].push(count, now_, LibCheckpoint.sub);
    $.totalStaked.push(count, now_, LibCheckpoint.sub);
  }

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @inheritdoc IxMorseStakingV2
  function xMorseToken() external view returns (address) {
    return _getStorageV1().xMorseToken;
  }

  /// @inheritdoc IxMorseStakingV2
  function mirrorNFT() external view returns (address) {
    return _getStorageV1().mirrorNFT;
  }

  /// @inheritdoc IxMorseStakingV2
  function rewardToken() external view returns (address) {
    return _getStorageV1().rewardToken;
  }

  /// @inheritdoc IxMorseStakingV2
  function lockupPeriod() external view returns (uint256) {
    return _getStorageV1().lockupPeriod;
  }

  /// @inheritdoc IxMorseStakingV2
  function stakerTotal(address staker, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().stakerTotal[staker];
    return trace.upperLookupRecent(timestamp).amount;
  }

  /// @inheritdoc IxMorseStakingV2
  function stakerTotalTWAB(address staker, uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().stakerTotal[staker];
    LibCheckpoint.TWABCheckpoint memory twab = trace.upperLookupRecent(timestamp);
    unchecked {
      return twab.amount * (timestamp - twab.lastUpdate) + twab.twab;
    }
  }

  /// @inheritdoc IxMorseStakingV2
  function totalStaked(uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().totalStaked;
    return trace.upperLookupRecent(timestamp).amount;
  }

  /// @inheritdoc IxMorseStakingV2
  function totalStakedTWAB(uint48 timestamp) external view returns (uint256) {
    LibCheckpoint.TraceTWAB storage trace = _getStorageV1().totalStaked;
    LibCheckpoint.TWABCheckpoint memory twab = trace.upperLookupRecent(timestamp);
    unchecked {
      return twab.amount * (timestamp - twab.lastUpdate) + twab.twab;
    }
  }

  /// @inheritdoc IxMorseStakingV2
  function getNFTInfo(uint256 tokenId) external view returns (NFTInfo memory) {
    return _getStorageV1().nftInfo[tokenId];
  }

  /// @inheritdoc IxMorseStakingV2
  function getStakedNFTs(address user) external view returns (uint256[] memory) {
    return _getStorageV1().userStakedNFTs[user];
  }

  /// @inheritdoc IxMorseStakingV2
  function validatorRewardDistributor() external view returns (address) {
    return _getStorageV1().validatorRewardDistributor;
  }

  /// @inheritdoc IxMorseStakingV2
  function validatorAddress() external view returns (address) {
    return _getStorageV1().validatorAddress;
  }

  //====================================================================================//
  //================================== VALIDATOR REWARDS ===============================//
  //====================================================================================//

  /// @inheritdoc IxMorseStakingV2
  function claimFromValidator() external nonReentrant returns (uint256) {
    StorageV1 storage $ = _getStorageV1();

    if ($.validatorRewardDistributor == address(0)) revert ZeroAddress();
    if ($.validatorAddress == address(0)) revert ZeroAddress();

    // Only owner can claim validator rewards
    if (_msgSender() != owner()) revert NotAuthorized();

    uint256 claimed = IValidatorRewardDistributor($.validatorRewardDistributor).claimOperatorRewards(
      $.validatorAddress
    );

    if (claimed > 0) {
      emit ValidatorRewardsClaimed($.validatorAddress, claimed);
    }

    return claimed;
  }

  //====================================================================================//
  //================================== OWNER FUNCTIONS =================================//
  //====================================================================================//

  /// @inheritdoc IxMorseStakingV2
  function setLockupPeriod(uint256 _lockupPeriod) external onlyOwner {
    if (_lockupPeriod < 1) revert LockupPeriodTooShort();

    StorageV1 storage $ = _getStorageV1();
    uint256 oldPeriod = $.lockupPeriod;
    $.lockupPeriod = _lockupPeriod;

    emit LockupPeriodUpdated(oldPeriod, _lockupPeriod);
  }

  /// @inheritdoc IxMorseStakingV2
  function setValidatorRewardDistributor(address _validatorRewardDistributor) external onlyOwner {
    _getStorageV1().validatorRewardDistributor = _validatorRewardDistributor;
  }

  /// @inheritdoc IxMorseStakingV2
  function setValidatorAddress(address _validatorAddress) external onlyOwner {
    _getStorageV1().validatorAddress = _validatorAddress;
  }

  /// @inheritdoc IxMorseStakingV2
  function pause() external onlyOwner {
    _pause();
  }

  /// @inheritdoc IxMorseStakingV2
  function unpause() external onlyOwner {
    _unpause();
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

