// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/// @title IxMorseStaking
/// @notice Interface for xMorse NFT staking contract with reward distribution
interface IxMorseStaking {
  //====================================================================================//
  //================================== STRUCTS =========================================//
  //====================================================================================//

  /// @notice Information about a staked NFT
  /// @param owner Current staker who owns this NFT
  /// @param stakedAt Timestamp when NFT was staked
  /// @param lockupEndTime When unstaking becomes available (stakedAt + 7 days)
  /// @param unclaimedRewards Accumulated but unclaimed rewards for this NFT
  /// @param rewardDebt For accurate reward calculation across distributions
  struct NFTInfo {
    address owner;
    uint256 stakedAt;
    uint256 lockupEndTime;
    uint256 unclaimedRewards;
    uint256 rewardDebt;
  }

  //====================================================================================//
  //================================== EVENTS ==========================================//
  //====================================================================================//

  /// @notice Emitted when an NFT is staked
  /// @param user Address of the staker
  /// @param tokenId ID of the staked NFT
  /// @param lockupEndTime Timestamp when unstaking becomes available
  event NFTStaked(address indexed user, uint256 indexed tokenId, uint256 lockupEndTime);

  /// @notice Emitted when an NFT is unstaked
  /// @param user Address of the staker
  /// @param tokenId ID of the unstaked NFT
  event NFTUnstaked(address indexed user, uint256 indexed tokenId);

  /// @notice Emitted when rewards are claimed for an NFT
  /// @param user Address of the claimer
  /// @param tokenId ID of the NFT
  /// @param amount Amount of rewards claimed
  event RewardsClaimed(address indexed user, uint256 indexed tokenId, uint256 amount);

  /// @notice Emitted when rewards are distributed to all staked NFTs
  /// @param amount Total amount of rewards distributed
  /// @param newAccRewardPerNFT Updated accumulated rewards per NFT
  event RewardsDistributed(uint256 amount, uint256 newAccRewardPerNFT);

  /// @notice Emitted when the reward token address is updated
  /// @param oldToken Previous reward token address
  /// @param newToken New reward token address
  event RewardTokenUpdated(address indexed oldToken, address indexed newToken);

  //====================================================================================//
  //================================== ERRORS ==========================================//
  //====================================================================================//

  /// @notice Thrown when an amount is zero but shouldn't be
  error ZeroAmount();

  /// @notice Thrown when an array is empty but shouldn't be
  error EmptyArray();

  /// @notice Thrown when trying to unstake before lockup period ends
  /// @param tokenId ID of the NFT still in lockup
  error LockupPeriodNotEnded(uint256 tokenId);

  /// @notice Thrown when trying to unstake an NFT with unclaimed rewards
  /// @param tokenId ID of the NFT with unclaimed rewards
  error UnclaimedRewardsExist(uint256 tokenId);

  /// @notice Thrown when caller is not the owner of the staked NFT
  /// @param tokenId ID of the NFT
  error NotNFTOwner(uint256 tokenId);

  /// @notice Thrown when an NFT is not currently staked
  /// @param tokenId ID of the NFT
  error NFTNotStaked(uint256 tokenId);

  /// @notice Thrown when trying to stake an already staked NFT
  /// @param tokenId ID of the NFT
  error NFTAlreadyStaked(uint256 tokenId);

  /// @notice Thrown when there are no rewards available
  error NoRewardsAvailable();

  /// @notice Thrown when there are no stakers in the pool
  error NoStakersInPool();

  /// @notice Thrown when an address is zero but shouldn't be
  error ZeroAddress();

  /// @notice Thrown when an invalid NFT contract is provided
  error InvalidNFTContract();

  //====================================================================================//
  //================================== FUNCTIONS =======================================//
  //====================================================================================//

  /// @notice Initialize the staking contract
  /// @param _xMorseToken Address of the xMorse DN404 token
  /// @param _mirrorNFT Address of the xMorse MirrorERC721 contract
  /// @param _rewardToken Address of the reward token (can be updated later)
  /// @param _owner Address of the contract owner
  function initialize(
    address _xMorseToken,
    address _mirrorNFT,
    address _rewardToken,
    address _owner
  ) external;

  /// @notice Stake NFTs from the xMorse Mirror contract
  /// @param tokenIds Array of NFT token IDs to stake
  function stake(uint256[] calldata tokenIds) external;

  /// @notice Unstake NFTs after lockup period if no unclaimed rewards
  /// @param tokenIds Array of NFT token IDs to unstake
  function unstake(uint256[] calldata tokenIds) external;

  /// @notice Claim rewards for specific staked NFTs
  /// @param tokenIds Array of NFT token IDs to claim rewards for
  function claimRewards(uint256[] calldata tokenIds) external;

  /// @notice Claim rewards for all NFTs staked by the caller
  function claimAllRewards() external;

  /// @notice Distribute reward tokens to all staked NFTs
  /// @dev Anyone can call this function to distribute rewards
  function distributeRewards() external;

  /// @notice Set the reward token address (owner only)
  /// @param _rewardToken New reward token address
  function setRewardToken(address _rewardToken) external;

  /// @notice Pause the contract (owner only)
  function pause() external;

  /// @notice Unpause the contract (owner only)
  function unpause() external;

  //====================================================================================//
  //================================== VIEW FUNCTIONS ==================================//
  //====================================================================================//

  /// @notice Get all staked NFT token IDs for a user
  /// @param user Address of the user
  /// @return tokenIds Array of staked NFT token IDs
  function getStakedNFTs(address user) external view returns (uint256[] memory tokenIds);

  /// @notice Get information about a staked NFT
  /// @param tokenId ID of the NFT
  /// @return info NFTInfo struct with all information
  function getNFTInfo(uint256 tokenId) external view returns (NFTInfo memory info);

  /// @notice Get total number of staked NFTs
  /// @return total Total number of NFTs currently staked
  function getTotalStakedNFTs() external view returns (uint256 total);

  /// @notice Get pending rewards for a specific NFT
  /// @param tokenId ID of the NFT
  /// @return pending Amount of pending rewards
  function getPendingRewards(uint256 tokenId) external view returns (uint256 pending);

  /// @notice Get the xMorse token address
  /// @return Address of the xMorse token
  function xMorseToken() external view returns (address);

  /// @notice Get the Mirror NFT address
  /// @return Address of the Mirror NFT contract
  function mirrorNFT() external view returns (address);

  /// @notice Get the reward token address
  /// @return Address of the reward token
  function rewardToken() external view returns (address);

  /// @notice Get accumulated rewards per NFT
  /// @return Accumulated rewards per NFT (scaled by 1e18)
  function accRewardPerNFT() external view returns (uint256);
}

