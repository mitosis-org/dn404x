# xDN404 MORSE

> **✅ PRODUCTION STATUS**: This project is deployed on Ethereum and Mitosis mainnets. See [addresses.yaml](addresses.yaml) for deployment details.

A cross-chain NFT transfer protocol that enables NFT transfers between Ethereum and Mitosis chains using the DN404 standard and Hyperlane messaging protocol.

## Overview

xDN404 MORSE connects Ethereum and Mitosis chains for NFT transfers using the DN404 standard. It includes a reroll mechanism for token ID mapping and supports both full NFT transfers and partial ownership transfers.

## Deployed Contracts

### Ethereum Mainnet

| Contract | Address | Description |
|----------|---------|-------------|
| **xMorseCollateral** | [`0xafF06A0cDCd30965160709F8e56E9B0EB54b177a`](https://etherscan.io/address/0xafF06A0cDCd30965160709F8e56E9B0EB54b177a) | Collateral contract managing DN404 tokens |
| **MorseDN404** | [`0x027da47d6a5692c9b5cb64301a07d978ce3cb16c`](https://etherscan.io/address/0x027da47d6a5692c9b5cb64301a07d978ce3cb16c) | DN404 token (ERC20 + ERC721) |

### Mitosis Mainnet

| Contract | Address | Description |
|----------|---------|-------------|
| **xMorse** | [`0xF8FA261FBeBeBec4241B26125aC21b5541afe600`](https://mitoscan.io/address/0xF8FA261FBeBeBec4241B26125aC21b5541afe600) | Cross-chain DN404 contract |
| **xMorseStaking** | [`0xE48B0509fe69c97de24d223e33e28c787D5D7178`](https://mitoscan.io/address/0xE48B0509fe69c97de24d223e33e28c787D5D7178) | NFT staking contract with reward distribution |

> 📋 For complete deployment information including chain IDs, RPC URLs, and deployment metadata, see [addresses.yaml](addresses.yaml).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           xDN404 MORSE Architecture                         │
└─────────────────────────────────────────────────────────────────────────────┘

   Ethereum Mainnet                                      Mitosis Mainnet
   (Chain ID: 1)                                        (Chain ID: 124816)
 ┌──────────────────┐                                 ┌──────────────────┐
 │   MorseDN404     │                                 │     xMorse       │
 │   (DN404 Token)  │                                 │  (DN404 Token)   │
 │                  │                                 │                  │
 │  ERC20 + ERC721  │                                 │ ERC20 + ERC721   │
 └────────┬─────────┘                                 └────────▲─────────┘
          │                                                    │
          │ Lock/Unlock                                 Mint/Burn
          │                                                    │
 ┌────────▼─────────┐         Hyperlane Protocol     ┌────────┴─────────┐
 │ xMorseCollateral │◄───────────────────────────────►│   xMorse Core    │
 │   (Collateral)   │         Cross-Chain             │   (Receiver)     │
 │                  │          Messages                │                  │
 └──────────────────┘                                 └──────────────────┘
          │                                                    │
          │                                                    │
 ┌────────▼──────────────────────────────────────────────────▼─────────┐
 │                         Hyperlane Mailbox                            │
 │                    (Secure Message Passing)                          │
 └──────────────────────────────────────────────────────────────────────┘

                          Transfer Flow Example:
                    
    Ethereum → Mitosis                        Mitosis → Ethereum
    ─────────────────                         ─────────────────
    1. User locks NFT in                      1. User burns NFT on
       xMorseCollateral                          xMorse
    2. Message sent via                       2. Message sent via
       Hyperlane                                 Hyperlane
    3. xMorse mints NFT                       3. xMorseCollateral
       on Mitosis                                unlocks NFT
```

### Cross-Chain Components

- **Ethereum Side**: 
  - `MorseDN404`: DN404 token contract (hybrid ERC20/ERC721)
  - `xMorseCollateral`: Manages collateral and cross-chain messaging
  
- **Mitosis Side**: 
  - `xMorse`: Cross-chain DN404 implementation with mint/burn capabilities
  
- **Bridge Protocol**: 
  - `Hyperlane`: Secure cross-chain messaging and verification

### Features

- **Bidirectional NFT Transfers**: Move NFTs between Ethereum and Mitosis
- **DN404 Standard**: Hybrid ERC20/ERC721 tokens (1 token = 1 NFT)
- **Collateral Model**: Lock tokens on source chain, mint on destination
- **Secure Messaging**: Hyperlane's verified cross-chain communication
- **Gas Optimization**: Efficient message passing and token operations
- **NFT Staking**: Stake xMorse NFTs to earn rewards with configurable lockup periods
- **Reward Distribution**: Automated reward distribution with validator integration support

## Installation

### Prerequisites

- [Foundry](https://getfoundry.sh/) (latest version)
- [Node.js](https://nodejs.org/) (v18+)
- [pnpm](https://pnpm.io/) (v10+)

### Setup

```bash
# Clone the repository
git clone <repository-url>
cd dn404x

# Install dependencies
pnpm install

# Install Solidity dependencies
forge soldeer install -d

# Build contracts
forge build

# Run tests
forge test
```

## Development

### Building and Testing

```bash
# Build contracts
forge build

# Run all tests
forge test

# Run tests with gas reports
forge test --gas-report

# Generate coverage report
pnpm coverage
```

### Code Quality

```bash
# Format code and check style
pnpm lint

# Check formatting without changes
pnpm lint:check
```

### Available Scripts

- `pnpm build` - Compile contracts
- `pnpm lint` - Format code and sort imports
- `pnpm lint:check` - Check code formatting
- `pnpm coverage` - Generate test coverage report

## Project Structure

```
dn404x/
├── src/
│   ├── xDN404Base.sol           # Base contract for cross-chain DN404 operations
│   ├── xMorse.sol               # Main xMorse contract implementing DN404
│   ├── xMorseCollateral.sol     # Collateral contract for Ethereum side
│   ├── xMorseStaking.sol        # NFT staking contract with rewards
│   ├── interfaces/              # Contract interfaces
│   │   ├── IDN404.sol           # DN404 interface
│   │   ├── IMorse.sol           # Morse token interface
│   │   ├── IxDN404.sol          # Cross-chain DN404 interface
│   │   └── IxMorseStaking.sol   # Staking interface
│   ├── libs/                    # Utility libraries
│   ├── periphery/               # Peripheral contracts
│   │   ├── xDN404LPVault.sol    # LP vault for DN404 tokens
│   │   ├── xDN404TransferBatch.sol  # Batch transfer functionality
│   │   └── xDN404TransferRouter.sol # Transfer router
│   ├── examples/                # Example implementations
│   └── test/                    # Internal test utilities
├── test/                        # Test files
├── script/                      # Deployment and utility scripts
├── deployments/                 # Deployment artifacts and addresses
│   ├── mitosis.json             # Mitosis Dognet testnet deployments
│   └── sepolia.json             # Sepolia testnet deployments
├── packages/                    # TypeScript packages
│   └── abis/                    # Generated ABIs and TypeScript bindings
├── dependencies/                # Solidity dependencies (managed by soldeer)
├── addresses.yaml               # Mainnet deployment addresses
├── foundry.toml                 # Foundry configuration
├── package.json                 # Node.js dependencies
└── pnpm-workspace.yaml          # Monorepo workspace configuration
```

## Configuration

### Foundry Configuration

Key settings in `foundry.toml`:

- **Solidity Version**: 0.8.29
- **EVM Version**: Prague
- **Dependencies**: OpenZeppelin, DN404, Mitosis protocol, Hyperlane

### Dependencies & Remappings

| Dependency Name                       | Purpose / Description          | Remapping (foundry.toml) |
| ------------------------------------- | ------------------------------ | ------------------------ |
| `@openzeppelin/contracts`             | Security and utility contracts | `@oz/`                   |
| `@openzeppelin/contracts-upgradeable` | Upgradeable contract support   | `@ozu/`                  |
| `@hyperlane-xyz/core`                 | Cross-chain messaging          | `@hpl/`                  |
| `@mitosis-org/protocol`               | Mitosis vault interfaces       | `mitosis/`               |
| `@mitosis-org/stub`                   | Stub library for testing       | `@stub/`                 |
| `dn404`                               | DN404 token standard           | `@dn404/`                |
| `solady`                              | Gas-optimized utilities        | `@solady/`               |
| `forge-std`                           | Foundry standard library       | `@std/`                  |

## Core Contracts

### xDN404Base.sol

Base contract providing cross-chain DN404 functionality:

- `transferRemoteNFT()`: Transfer complete NFTs to remote chains
- `transferRemoteNFTPartial()`: Transfer partial NFT ownership
- `quoteTransferRemoteNFT()`: Get gas estimates for cross-chain transfers

### xMorse.sol

Main contract implementing the xDN404 standard:

- DN404 token implementation with cross-chain capabilities
- Upgradeable contract architecture
- Treasury integration for cross-chain operations

### xMorseCollateral.sol

Collateral contract managing DN404 tokens on Ethereum:

- Locks NFTs when bridging from Ethereum to Mitosis
- Unlocks NFTs when bridging back from Mitosis
- Cross-chain message handling via Hyperlane

### xMorseStaking.sol

NFT staking contract with reward distribution on Mitosis:

- Stake xMorse Mirror NFTs to earn rewards
- Configurable lockup periods (default: 7 days)
- Fair reward distribution among all stakers
- UUPS upgradeable with owner and operator roles
- Optional validator reward integration

**Key Features:**
- `stake()`: Stake NFTs and start earning rewards
- `unstake()`: Unstake NFTs after lockup period (no unclaimed rewards required)
- `claimRewards()`: Claim accumulated rewards for staked NFTs
- `distributeRewards()`: Distribute rewards to all stakers (owner/operator only)
- Automatic reward calculation per NFT
- Support for custom reward tokens

## Cross-Chain Operations

### Message Types

```solidity
enum MessageType {
    SEND_NFT,           // Full NFT transfer
    SEND_NFT_PARTIAL    // Partial ownership transfer
}
```

### Transfer Flow

1. **Ethereum → Mitosis**: User calls `transferRemoteNFT()` on `xDN404Collateral`
2. **Message Processing**: Hyperlane delivers message to Mitosis chain
3. **NFT Minting**: `xDN404` contract mints corresponding NFT on Mitosis
4. **Reroll Execution**: Token ID mapping is updated for cross-chain consistency

### Reroll Mechanism

The protocol implements a reroll system that maps token IDs between chains:

- **Ethereum IDs**: `[1 | 2 | 4 | 7 | 9]`
- **Mitosis IDs**: `[3 | 5 | 6 | 8]`
- **Dynamic Mapping**: Token IDs are reassigned during cross-chain transfers to maintain consistency

## Security Features

- **Ownable2Step**: Two-step ownership transfer
- **UUPS Upgradeable**: Upgradeable contract pattern with access control
- **Reentrancy Protection**: Protection against reentrancy attacks
- **Gas Limit Validation**: Gas estimation and validation for cross-chain operations

## Staking

### Overview

The xMorseStaking contract allows users to stake their xMorse NFTs on Mitosis to earn rewards. The contract uses a fair distribution mechanism where rewards are distributed proportionally to all staked NFTs.

### Staking Process

1. **Stake NFTs**: Transfer your xMorse Mirror NFTs to the staking contract
2. **Lockup Period**: NFTs are locked for a configurable period (default: 7 days)
3. **Earn Rewards**: Rewards accumulate automatically when distributed by owner/operator
4. **Claim Rewards**: Claim your accumulated rewards at any time
5. **Unstake**: After lockup period ends and all rewards are claimed, unstake your NFTs

### Roles

- **Owner**: Full control over contract settings, upgrades, and emergency operations
- **Operator**: Can distribute rewards to all stakers
- **Users**: Can stake, unstake, and claim rewards for their NFTs

### Configuration

The staking contract supports various configuration options:

- **Reward Token**: Configurable token for rewards (default: xMorse itself)
- **Lockup Period**: Minimum time before unstaking (configurable per deployment)
- **Validator Integration**: Optional integration with Mitosis validator rewards
- **Operator**: Designated address for automated reward distribution

### Usage

For detailed staking operations and script usage, see [script/README.md](script/README.md).

### Key Functions

```solidity
// Staking operations
function stake(uint256[] calldata tokenIds) external;
function unstake(uint256[] calldata tokenIds) external;
function claimRewards(uint256[] calldata tokenIds) external;
function claimAllRewards() external;

// View functions
function getStakedNFTs(address user) external view returns (uint256[] memory);
function getPendingRewards(uint256 tokenId) external view returns (uint256);
function getNFTInfo(uint256 tokenId) external view returns (NFTInfo memory);

// Owner/Operator functions
function distributeRewards() external; // Owner or Operator
function setRewardToken(address _rewardToken) external; // Owner only
function setOperator(address _operator) external; // Owner only
```

## Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract xMorse

# Run staking tests
forge test --match-contract Staking

# Run tests with verbose output
forge test -vvv

# Generate gas report
forge test --gas-report
```

## Gas Optimization

Gas optimization features:

- **Base Gas Limits**: 25,000 for ERC20 transfers, 50,000 for ERC721 transfers
- **Dynamic Gas Calculation**: Gas limits adjust based on operation complexity
- **Batch Operations**: Support for transferring multiple NFTs in single transaction

## Scripts

The project includes comprehensive deployment and management scripts:

- **Deployment Scripts**: Deploy contracts to mainnet and testnet
- **Upgrade Scripts**: Upgrade UUPS proxy implementations
- **Configuration Scripts**: Manage contract settings and parameters
- **Operations Scripts**: Distribute rewards and monitor staking
- **Emergency Scripts**: Rescue stuck NFTs in emergency situations

For complete script documentation, see [script/README.md](script/README.md).

## Integration

### Hyperlane Integration

- Cross-chain messaging via Hyperlane protocol
- Gas router for cross-chain communication
- Hook system for custom message processing

### Mitosis Protocol

- Integration with Mitosis vault system
- Support for cross-chain liquidity operations
- Treasury management across chains
- Optional validator reward distribution for staking

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## Support

For questions and support:

- Open an issue on GitHub
- Join our community discussions
- Check the documentation for common questions

## Disclaimer

This software is provided "as is" without warranty. Use at your own risk. Cross-chain operations carry risks including message delivery failures, chain reorganizations, and smart contract vulnerabilities. This project is in development and not audited.
