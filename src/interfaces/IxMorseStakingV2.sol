// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title IxMorseStakingV2
/// @notice Interface for xMorse NFT staking with TWAB tracking
interface IxMorseStakingV2 {
  //====================================================================================//
  //================================== STRUCTS =========================================//
  //====================================================================================//

  /// @notice NFT staking information
  struct NFTInfo {
    address owner;           // Owner of the staked NFT
    uint256 stakedAt;       // Timestamp when NFT was staked
    uint256 lockupEndTime;  // Timestamp when lockup ends
    uint256 unclaimedRewards; // [DEPRECATED] For storage compatibility
    uint256 rewardDebt;      // [DEPRECATED] For storage compatibility
    uint256 stakedEpoch;     // Epoch when NFT was staked
  }

  //====================================================================================//
  //================================== EVENTS ==========================================//
  //====================================================================================//

  /// @notice Emitted when NFT is staked
  event NFTStaked(address indexed user, uint256 indexed tokenId, uint256 lockupEndTime);

  /// @notice Emitted when NFT is unstaked
  event NFTUnstaked(address indexed user, uint256 indexed tokenId);

  /// @notice Emitted when lockup period is updated
  event LockupPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

  /// @notice Emitted when validator rewards are claimed
  event ValidatorRewardsClaimed(address indexed validatorAddress, uint256 amount);

  //====================================================================================//
  //================================== ERRORS ==========================================//
  //====================================================================================//

  error ZeroAddress();
  error EmptyArray();
  error NFTAlreadyStaked(uint256 tokenId);
  error NFTNotStaked(uint256 tokenId);
  error NotNFTOwner(uint256 tokenId);
  error LockupPeriodNotEnded(uint256 tokenId);
  error LockupPeriodTooShort();
  error NotAuthorized();

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @notice Get xMorse DN404 token address
  function xMorseToken() external view returns (address);

  /// @notice Get xMorse MirrorERC721 NFT address
  function mirrorNFT() external view returns (address);

  /// @notice Get reward token address
  function rewardToken() external view returns (address);

  /// @notice Get current lockup period
  function lockupPeriod() external view returns (uint256);

  /// @notice Get staker's total staked NFT count at a specific timestamp
  /// @param staker Address of the staker
  /// @param timestamp Timestamp to query
  /// @return Total staked NFT count
  function stakerTotal(address staker, uint48 timestamp) external view returns (uint256);

  /// @notice Get staker's time-weighted accumulated balance (TWAB) at a specific timestamp
  /// @param staker Address of the staker
  /// @param timestamp Timestamp to query
  /// @return Time-weighted accumulated NFT count
  function stakerTotalTWAB(address staker, uint48 timestamp) external view returns (uint256);

  /// @notice Get total staked NFT count at a specific timestamp
  /// @param timestamp Timestamp to query
  /// @return Total staked NFT count
  function totalStaked(uint48 timestamp) external view returns (uint256);

  /// @notice Get total time-weighted accumulated balance (TWAB) at a specific timestamp
  /// @param timestamp Timestamp to query
  /// @return Time-weighted accumulated total NFT count
  function totalStakedTWAB(uint48 timestamp) external view returns (uint256);

  /// @notice Get NFT info for a specific token ID
  /// @param tokenId Token ID to query
  /// @return NFT information
  function getNFTInfo(uint256 tokenId) external view returns (NFTInfo memory);

  /// @notice Get all staked NFT IDs for a user
  /// @param user Address of the user
  /// @return Array of staked token IDs
  function getStakedNFTs(address user) external view returns (uint256[] memory);

  /// @notice Get validator reward distributor address
  function validatorRewardDistributor() external view returns (address);

  /// @notice Get validator address
  function validatorAddress() external view returns (address);

  //====================================================================================//
  //================================== MUTATIVE FUNCTIONS ==============================//
  //====================================================================================//

  /// @notice Stake NFTs
  /// @param tokenIds Array of token IDs to stake
  function stake(uint256[] calldata tokenIds) external;

  /// @notice Unstake NFTs (lockup period must have ended)
  /// @param tokenIds Array of token IDs to unstake
  function unstake(uint256[] calldata tokenIds) external;

  /// @notice Claim gMITO from ValidatorRewardDistributor
  /// @return claimed Amount of gMITO claimed
  function claimFromValidator() external returns (uint256 claimed);

  //====================================================================================//
  //================================== OWNER FUNCTIONS =================================//
  //====================================================================================//

  /// @notice Set lockup period for newly staked NFTs
  /// @param _lockupPeriod New lockup period in seconds
  function setLockupPeriod(uint256 _lockupPeriod) external;

  /// @notice Set ValidatorRewardDistributor contract address
  /// @param _validatorRewardDistributor Address of ValidatorRewardDistributor contract
  function setValidatorRewardDistributor(address _validatorRewardDistributor) external;

  /// @notice Set validator address for claiming operator rewards
  /// @param _validatorAddress Validator address
  function setValidatorAddress(address _validatorAddress) external;

  /// @notice Pause contract
  function pause() external;

  /// @notice Unpause contract
  function unpause() external;
}

