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
    bool isUnstaking;       // Whether NFT is in unstaking process
    uint256 unstakeInitTime; // Timestamp when unstaking was initiated
  }

  //====================================================================================//
  //================================== EVENTS ==========================================//
  //====================================================================================//

  /// @notice Emitted when NFT is staked
  event NFTStaked(address indexed user, uint256 indexed tokenId, uint256 lockupEndTime);

  /// @notice Emitted when NFT is unstaked
  event NFTUnstaked(address indexed user, uint256 indexed tokenId);

  /// @notice Emitted when unstaking is initiated
  event UnstakeInitiated(address indexed user, uint256 indexed tokenId, uint256 unlockTime);

  /// @notice Emitted when unstaking is completed
  event UnstakeCompleted(address indexed user, uint256 indexed tokenId);

  /// @notice Emitted when lockup period is updated
  event LockupPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

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
  error AlreadyUnstaking(uint256 tokenId);
  error NotUnstaking(uint256 tokenId);
  error NFTIsUnstaking(uint256 tokenId);

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

  /// @notice Get all unstaking NFT IDs for a user
  /// @param user Address of the user
  /// @return Array of unstaking token IDs
  function getUnstakingNFTs(address user) external view returns (uint256[] memory);

  /// @notice Check if an NFT is in unstaking process
  /// @param tokenId Token ID to check
  /// @return True if NFT is unstaking
  function isNFTUnstaking(uint256 tokenId) external view returns (bool);

  //====================================================================================//
  //================================== MUTATIVE FUNCTIONS ==============================//
  //====================================================================================//

  /// @notice Stake NFTs
  /// @param tokenIds Array of token IDs to stake
  function stake(uint256[] calldata tokenIds) external;

  /// @notice Initiate unstaking process (TWAB decreases immediately)
  /// @param tokenIds Array of token IDs to unstake
  function initiateUnstake(uint256[] calldata tokenIds) external;

  /// @notice Complete unstaking and retrieve NFTs (after lockup period)
  /// @param tokenIds Array of token IDs to complete unstaking
  function completeUnstake(uint256[] calldata tokenIds) external;

  /// @notice Unstake NFTs (lockup period must have ended) - DEPRECATED, use 2-phase unstaking
  /// @param tokenIds Array of token IDs to unstake
  function unstake(uint256[] calldata tokenIds) external;

  //====================================================================================//
  //================================== OWNER FUNCTIONS =================================//
  //====================================================================================//

  /// @notice Set lockup period for newly staked NFTs
  /// @param _lockupPeriod New lockup period in seconds
  function setLockupPeriod(uint256 _lockupPeriod) external;

  /// @notice Pause contract
  function pause() external;

  /// @notice Unpause contract
  function unpause() external;
}

