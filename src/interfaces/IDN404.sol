// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IDN404
/// @notice Interface for DN404 - a hybrid ERC20 and ERC721 implementation
/// @dev This interface includes all public and external functions from the DN404 contract
interface IDN404 {
  /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
  /*                           EVENTS                           */
  /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

  /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
  event Transfer(address indexed from, address indexed to, uint256 amount);

  /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
  event Approval(address indexed owner, address indexed spender, uint256 amount);

  /// @dev Emitted when `owner` sets their skipNFT flag to `status`.
  event SkipNFTSet(address indexed owner, bool status);

  /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
  /*                        CUSTOM ERRORS                       */
  /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

  /// @dev Thrown when attempting to double-initialize the contract.
  error DNAlreadyInitialized();

  /// @dev The function can only be called after the contract has been initialized.
  error DNNotInitialized();

  /// @dev Thrown when attempting to transfer or burn more tokens than sender's balance.
  error InsufficientBalance();

  /// @dev Thrown when a spender attempts to transfer tokens with an insufficient allowance.
  error InsufficientAllowance();

  /// @dev Thrown when minting an amount of tokens that would overflow the max tokens.
  error TotalSupplyOverflow();

  /// @dev The unit must be greater than zero and less than `2**96`.
  error InvalidUnit();

  /// @dev Thrown when the caller for a fallback NFT function is not the mirror contract.
  error SenderNotMirror();

  /// @dev Thrown when attempting to transfer tokens to the zero address.
  error TransferToZeroAddress();

  /// @dev Thrown when the mirror address provided for initialization is the zero address.
  error MirrorAddressIsZero();

  /// @dev Thrown when the link call to the mirror contract reverts.
  error LinkMirrorContractFailed();

  /// @dev Thrown when setting an NFT token approval
  /// and the caller is not the owner or an approved operator.
  error ApprovalCallerNotOwnerNorApproved();

  /// @dev Thrown when transferring an NFT
  /// and the caller is not the owner or an approved operator.
  error TransferCallerNotOwnerNorApproved();

  /// @dev Thrown when transferring an NFT and the from address is not the current owner.
  error TransferFromIncorrectOwner();

  /// @dev Thrown when checking the owner or approved address for a non-existent NFT.
  error TokenDoesNotExist();

  /// @dev The function selector is not recognized.
  error FnSelectorNotRecognized();

  /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
  /*                      ERC20 OPERATIONS                      */
  /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

  /// @dev Returns the decimals places of the token. Defaults to 18.
  function decimals() external view returns (uint8);

  /// @dev Returns the amount of tokens in existence.
  function totalSupply() external view returns (uint256);

  /// @dev Returns the amount of tokens owned by `owner`.
  function balanceOf(address owner) external view returns (uint256);

  /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
  function allowance(address owner, address spender) external view returns (uint256);

  /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
  /// @param spender The address to approve
  /// @param amount The amount to approve
  /// @return success Whether the approval was successful
  function approve(address spender, uint256 amount) external returns (bool);

  /// @dev Transfer `amount` tokens from the caller to `to`.
  /// @param to The recipient address
  /// @param amount The amount to transfer
  /// @return success Whether the transfer was successful
  function transfer(address to, uint256 amount) external returns (bool);

  /// @dev Transfers `amount` tokens from `from` to `to`.
  /// @param from The sender address
  /// @param to The recipient address
  /// @param amount The amount to transfer
  /// @return success Whether the transfer was successful
  function transferFrom(address from, address to, uint256 amount) external returns (bool);

  /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
  /*                     SKIP NFT FUNCTIONS                     */
  /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

  /// @dev Returns true if minting and transferring ERC20s to `owner` will skip minting NFTs.
  /// @param owner The address to check
  /// @return result Whether the address skips NFT minting
  function getSkipNFT(address owner) external view returns (bool result);

  /// @dev Sets the caller's skipNFT flag to `skipNFT`. Returns true.
  /// @param skipNFT Whether to skip NFT minting
  /// @return success Whether the operation was successful
  function setSkipNFT(bool skipNFT) external returns (bool);

  /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
  /*                     MIRROR OPERATIONS                      */
  /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

  /// @dev Returns the address of the mirror NFT contract.
  function mirrorERC721() external view returns (address);

  /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
  /*               METADATA FUNCTIONS TO OVERRIDE               */
  /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

  /// @dev Returns the name of the token.
  function name() external view returns (string memory);

  /// @dev Returns the symbol of the token.
  function symbol() external view returns (string memory);

  /// @dev Returns the Uniform Resource Identifier (URI) for token `id`.
  /// @param id The token ID
  /// @return uri The token URI
  function tokenURI(uint256 id) external view returns (string memory uri);

  /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
  /*                     NFT FALLBACK FUNCTIONS                  */
  /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

  /// @dev Transfers token `id` from `from` to `to` (called by mirror contract).
  /// @param from The current owner of the token
  /// @param to The new owner of the token
  /// @param id The token ID to transfer
  /// @param msgSender The address initiating the transfer
  function transferFromNFT(address from, address to, uint256 id, address msgSender) external;

  /// @dev Sets approval for all NFTs (called by mirror contract).
  /// @param spender The address to approve
  /// @param status Whether to approve or revoke
  /// @param msgSender The address setting the approval
  function setApprovalForAllNFT(address spender, bool status, address msgSender) external;

  /// @dev Returns whether `operator` is approved to manage the NFT tokens of `owner`.
  /// @param owner The token owner
  /// @param operator The operator to check
  /// @return result Whether the operator is approved
  function isApprovedForAllNFT(address owner, address operator) external view returns (bool result);

  /// @dev Returns the owner of token `id` (reverts if token doesn't exist).
  /// @param id The token ID
  /// @return owner The owner of the token
  function ownerOfNFT(uint256 id) external view returns (address owner);

  /// @dev Returns the owner of token `id` (returns zero address if token doesn't exist).
  /// @param id The token ID
  /// @return owner The owner of the token or zero address
  function ownerAtNFT(uint256 id) external view returns (address owner);

  /// @dev Approves `spender` to manage token `id` (called by mirror contract).
  /// @param spender The address to approve
  /// @param id The token ID
  /// @param msgSender The address setting the approval
  /// @return owner The owner of the token
  function approveNFT(address spender, uint256 id, address msgSender)
    external
    returns (address owner);

  /// @dev Returns the account approved to manage token `id`.
  /// @param id The token ID
  /// @return approved The approved address or zero address
  function getApprovedNFT(uint256 id) external view returns (address approved);

  /// @dev Returns `owner` NFT balance.
  /// @param owner The address to check
  /// @return balance The NFT balance
  function balanceOfNFT(address owner) external view returns (uint256 balance);

  /// @dev Returns the total NFT supply.
  /// @return totalSupply The total number of NFTs in existence
  function totalNFTSupply() external view returns (uint256 totalSupply);

  /// @dev Returns the Uniform Resource Identifier (URI) for token `id` (called by mirror).
  /// @param id The token ID
  /// @return uri The token URI
  function tokenURINFT(uint256 id) external view returns (string memory uri);

  /// @dev Returns true to indicate this contract implements DN404.
  /// @return result Always returns true
  function implementsDN404() external view returns (bool result);
}
