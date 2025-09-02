# xDN404 MORSE

> WARNING: xMorseTransferBatch has AI written code in it, it is not safe to use now.

A revolutionary cross-chain NFT mechanism that enables seamless NFT transfers between Ethereum and Mitosis chains using the DN404 standard and Hyperlane messaging protocol.

![xDN404 MORSE Architecture](assets/diagram.png)

## 🌟 Overview

xDN404 MORSE is a cutting-edge protocol that bridges the gap between Ethereum and Mitosis chains, allowing users to transfer NFTs across different blockchain networks while maintaining the benefits of the DN404 standard. The protocol implements a sophisticated reroll mechanism for token ID mapping and provides both full NFT transfers and partial ownership transfers.

## 🏗️ Architecture

### Cross-Chain Components

- **Ethereum Side**: `xDN404Collateral` contract that manages underlying DN404 tokens
- **Mitosis Side**: `xDN404` contract that handles cross-chain NFT operations
- **Treasury System**: `xDN404Treasury` for managing cross-chain liquidity and operations

### Key Features

- **Bidirectional NFT Transfers**: Seamlessly move NFTs between Ethereum and Mitosis
- **Partial Ownership**: Support for fractionalized NFT ownership across chains
- **Reroll Mechanism**: Dynamic token ID mapping system for cross-chain operations
- **Gas Optimization**: Efficient cross-chain messaging with Hyperlane integration

## 📦 Installation

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

## 🧪 Development Workflow

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

## 📁 Project Structure

```
dn404x/
├── src/
│   ├── xDN404Base.sol           # Base contract for cross-chain DN404 operations
│   ├── xDN404Treasury.sol       # Treasury contract for cross-chain liquidity
│   ├── xMorse.sol               # Main xMorse contract implementing DN404
│   ├── xMorseCollateral.sol     # Collateral contract for Ethereum side
│   ├── interfaces/               # Contract interfaces
│   └── libs/                     # Utility libraries
├── test/                         # Test files
├── dependencies/                  # Solidity dependencies
├── foundry.toml                  # Foundry configuration
└── package.json                  # Node.js dependencies
```

## 🔧 Configuration

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

## 🚀 Core Contracts

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

### xDN404Treasury.sol

Treasury contract managing cross-chain liquidity and operations:

- Handles incoming cross-chain messages
- Manages token reserves and distributions
- Supports partial ownership transfers

## 🔄 Cross-Chain Operations

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

The protocol implements a sophisticated reroll system that maps token IDs between chains:

- **Ethereum IDs**: `[1 | 2 | 4 | 7 | 9]`
- **Mitosis IDs**: `[3 | 5 | 6 | 8]`
- **Dynamic Mapping**: Token IDs are reassigned during cross-chain transfers to maintain consistency

## 🛡️ Security Features

- **Ownable2Step**: Two-step ownership transfer for enhanced security
- **UUPS Upgradeable**: Upgradeable contract pattern with proper access control
- **Reentrancy Protection**: Built-in protection against reentrancy attacks
- **Gas Limit Validation**: Proper gas estimation and validation for cross-chain operations

## 🧪 Testing

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-contract xMorse

# Run tests with verbose output
forge test -vvv

# Generate gas report
forge test --gas-report
```

## 📊 Gas Optimization

The protocol is designed with gas efficiency in mind:

- **Base Gas Limits**: 25,000 for ERC20 transfers, 50,000 for ERC721 transfers
- **Dynamic Gas Calculation**: Gas limits adjust based on operation complexity
- **Batch Operations**: Support for transferring multiple NFTs in single transaction

## 🔗 Integration

### Hyperlane Integration

- Cross-chain messaging via Hyperlane protocol
- Gas router for efficient cross-chain communication
- Hook system for custom message processing

### Mitosis Protocol

- Integration with Mitosis vault system
- Support for cross-chain liquidity operations
- Treasury management across chains

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📞 Support

For questions and support:

- Open an issue on GitHub
- Join our community discussions
- Check the documentation for common questions

## 🚨 Disclaimer

This software is provided "as is" without warranty of any kind. Use at your own risk. The protocol involves cross-chain operations which carry inherent risks including but not limited to message delivery failures, chain reorganizations, and smart contract vulnerabilities.
