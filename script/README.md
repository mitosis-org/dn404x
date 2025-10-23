# xDN404 MORSE Scripts Guide

This directory contains Foundry scripts for deploying, upgrading, configuring, and operating the xMorse protocol.

## Table of Contents

- [Deployment Scripts](#deployment-scripts)
- [Upgrade Scripts](#upgrade-scripts)
- [Configuration Scripts](#configuration-scripts)
- [Operations Scripts](#operations-scripts)
- [Emergency Scripts](#emergency-scripts)
- [Environment Setup](#environment-setup)

---

## Deployment Scripts

### DeployMitosisxMorse.s.sol
**Deploy xMorse DN404 token to Mitosis**

```bash
# Deploy to Mitosis Mainnet
forge script script/DeployMitosisxMorse.s.sol \
  --rpc-url https://rpc.mitosis.org \
  --broadcast

# Deployed contracts:
# - xMorse Proxy: DN404 token
# - xMorse Implementation: Implementation contract
# - DN404Mirror: NFT contract
```

**Configuration:**
- Chain: Mitosis Mainnet (124816)
- Mailbox: `0x3a464f746D23Ab22155710f44dB16dcA53e0775E`
- Hook: `0x1e4dE25C3b07c8DF66D4c193693d8B5f3b431d51`

---

### DeployCollateral.s.sol
**Deploy xMorseCollateral to Ethereum**

```bash
# Deploy to Ethereum Mainnet
forge script script/DeployCollateral.s.sol \
  --rpc-url https://eth.drpc.org \
  --broadcast --verify
```

**Configuration:**
- Chain: Ethereum Mainnet (1)
- Token: `0xe591293151fFDadD5E06487087D9b0E2743de92E` (MorseDN404)
- Mailbox: `0xc005dc82818d67AF737725bD4bf75435d065D239`

---

### DeployMitosisxMorseStaking.s.sol
**Deploy xMorseStaking contract to Mitosis**

```bash
# Deploy to Mitosis Mainnet
forge script script/DeployMitosisxMorseStaking.s.sol \
  --rpc-url https://rpc.mitosis.org \
  --broadcast

# Deploy to Mitosis Testnet (Dognet)
forge script script/DeployMitosisxMorseStaking.s.sol \
  --sig "runTestnet(address,address)" \
  <XMORSE_ADDRESS> <REWARD_TOKEN_ADDRESS> \
  --rpc-url https://rpc.dognet.mitosis.org \
  --broadcast
```

**Features:**
- UUPS upgradeable proxy pattern
- NFT staking and reward distribution
- Automatically detects Mirror NFT address
- Default lockup period: 7 days

**Deployed Contracts:**
- Proxy: User-facing contract address (use this for all interactions)
- Implementation: Logic contract (internal use only)

---

## Upgrade Scripts

### UpgradexMorse.s.sol
**Upgrade xMorse implementation contract**

```bash
# Upgrade on Mainnet
forge script script/UpgradexMorse.s.sol \
  --rpc-url https://rpc.mitosis.org \
  --broadcast

# Verify upgrade
forge script script/UpgradexMorse.s.sol \
  --sig "verify()" \
  --rpc-url https://rpc.mitosis.org
```

**Features:**
- Uses UUPS pattern
- Owner-only operation
- Automatically deploys new implementation and upgrades

---

### UpgradeCollateral.s.sol
**Upgrade xMorseCollateral implementation contract**

```bash
# Upgrade on Ethereum Mainnet
forge script script/UpgradeCollateral.s.sol \
  --sig "run(address)" <PROXY_ADDRESS> \
  --rpc-url https://eth.drpc.org \
  --broadcast
```

---

### UpgradexMorseStaking.s.sol
**Upgrade xMorseStaking implementation contract**

```bash
# Upgrade on Mainnet
forge script script/UpgradexMorseStaking.s.sol \
  --sig "run(address)" <PROXY_ADDRESS> \
  --rpc-url https://rpc.mitosis.org \
  --broadcast

# Upgrade on Testnet
forge script script/UpgradexMorseStaking.s.sol \
  --sig "runTestnet(address)" <PROXY_ADDRESS> \
  --rpc-url https://rpc.dognet.mitosis.org \
  --broadcast

# Verify upgrade
forge script script/UpgradexMorseStaking.s.sol \
  --sig "verify(address)" <PROXY_ADDRESS> \
  --rpc-url <RPC_URL>
```

---

## Configuration Scripts

### ConfigurexMorseRouting.s.sol
**Configure cross-chain routing between xMorse and xMorseCollateral**

```bash
# Configure Ethereum side
forge script script/ConfigurexMorseRouting.s.sol \
  --sig "configureEthereum(address,address)" \
  <ETHEREUM_COLLATERAL> <MITOSIS_XMORSE> \
  --rpc-url mainnet --broadcast

# Configure Mitosis side
forge script script/ConfigurexMorseRouting.s.sol \
  --sig "configureMitosis(address,address)" \
  <MITOSIS_XMORSE> <ETHEREUM_COLLATERAL> \
  --rpc-url https://rpc.mitosis.org --broadcast

# Verify configuration
forge script script/ConfigurexMorseRouting.s.sol \
  --sig "verifyEthereum(address,address)" \
  <ETHEREUM_COLLATERAL> <EXPECTED_MITOSIS_XMORSE> \
  --rpc-url mainnet
```

**Configuration includes:**
- Remote router enrollment
- Gas limits (SendNFT: 500,000 / SendNFTPartial: 700,000)

---

### ConfigurexMorseStaking.s.sol
**Manage xMorseStaking contract settings (Owner only)**

#### Set Reward Token
```bash
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "setRewardToken(address,address)" \
  <PROXY> <NEW_REWARD_TOKEN> \
  --rpc-url <RPC_URL> --broadcast
```

#### Set Lockup Period
```bash
# Example: 14 days = 1209600 seconds
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "setLockupPeriod(address,uint256)" \
  <PROXY> 1209600 \
  --rpc-url <RPC_URL> --broadcast
```

#### Set Operator
```bash
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "setOperator(address,address)" \
  <PROXY> <OPERATOR_ADDRESS> \
  --rpc-url <RPC_URL> --broadcast
```

#### Configure Validator Integration
```bash
# Set Validator Reward Distributor
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "setValidatorRewardDistributor(address,address)" \
  <PROXY> <DISTRIBUTOR_ADDRESS> \
  --rpc-url <RPC_URL> --broadcast

# Set Validator Address
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "setValidatorAddress(address,address)" \
  <PROXY> <VALIDATOR_ADDRESS> \
  --rpc-url <RPC_URL> --broadcast
```

#### Emergency Pause
```bash
# Pause
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "pause(address)" <PROXY> \
  --rpc-url <RPC_URL> --broadcast

# Unpause
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "unpause(address)" <PROXY> \
  --rpc-url <RPC_URL> --broadcast
```

#### View Current Configuration (Read-only)
```bash
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "viewConfig(address)" <PROXY> \
  --rpc-url <RPC_URL>
```

---

## Operations Scripts

### ManageStakingRewards.s.sol
**Staking reward distribution and monitoring**

#### Distribute Rewards
```bash
# Distribute rewards (Owner or Operator)
forge script script/ManageStakingRewards.s.sol \
  --sig "distributeRewards(address)" <PROXY> \
  --rpc-url <RPC_URL> --broadcast
```

#### View Staking Information (Read-only)
```bash
# View overall staking statistics
forge script script/ManageStakingRewards.s.sol \
  --sig "viewStakingInfo(address)" <PROXY> \
  --rpc-url <RPC_URL>

# View specific user's staking information
forge script script/ManageStakingRewards.s.sol \
  --sig "viewUserStakes(address,address)" <PROXY> <USER_ADDRESS> \
  --rpc-url <RPC_URL>
```

#### Fund and Distribute Rewards
```bash
# Transfer reward tokens and distribute immediately
forge script script/ManageStakingRewards.s.sol \
  --sig "fundAndDistribute(address,uint256)" \
  <PROXY> <AMOUNT> \
  --rpc-url <RPC_URL> --broadcast
```

#### Test Reward Cycle
```bash
# Test complete reward cycle
forge script script/ManageStakingRewards.s.sol \
  --sig "testRewardCycle(address,uint256)" \
  <PROXY> <AMOUNT> \
  --rpc-url <RPC_URL> --broadcast
```

#### Claim Rewards
```bash
# Claim rewards for specific NFTs
forge script script/ManageStakingRewards.s.sol \
  --sig "claimRewards(address,uint256[])" \
  <PROXY> "[1,2,3]" \
  --rpc-url <RPC_URL> --broadcast

# Claim rewards for all staked NFTs
forge script script/ManageStakingRewards.s.sol \
  --sig "claimAllRewards(address)" <PROXY> \
  --rpc-url <RPC_URL> --broadcast
```

---

## Emergency Scripts

### RescueNFT.s.sol
**Emergency NFT rescue from Collateral contract (Owner only)**

```bash
# Rescue single NFT (Ethereum Mainnet)
forge script script/RescueNFT.s.sol \
  --sig "rescueSingle(address,uint256)" \
  <RECIPIENT_ADDRESS> <TOKEN_ID> \
  --rpc-url mainnet \
  --broadcast

# Rescue multiple NFTs (Ethereum Mainnet)
forge script script/RescueNFT.s.sol \
  --sig "rescueMultiple(address,uint256[])" \
  <RECIPIENT_ADDRESS> "[1234,5678,9012]" \
  --rpc-url mainnet \
  --broadcast

# Check NFT status (Read-only)
forge script script/RescueNFT.s.sol \
  --sig "checkNFT(uint256)" <TOKEN_ID> \
  --rpc-url mainnet

# Rescue on Sepolia
forge script script/RescueNFT.s.sol \
  --sig "rescueSingleSepolia(address,uint256)" \
  <RECIPIENT_ADDRESS> <TOKEN_ID> \
  --rpc-url sepolia \
  --broadcast
```

**Warning:**
- Use this script only in emergency situations
- Only for NFTs stuck due to failed cross-chain messages or other issues
- Owner-only operation

---

## Environment Setup

### .env File Configuration

```bash
# Private Key (Owner/Deployer)
PRIVATE_KEY=0x...

# RPC URLs
MITOSIS_RPC=https://rpc.mitosis.org
MITOSIS_TESTNET_RPC=https://rpc.dognet.mitosis.org
ETHEREUM_RPC=https://eth.drpc.org
SEPOLIA_RPC=https://sepolia.infura.io/v3/YOUR_KEY

# Contract Addresses (Update after deployment)
XMORSE_MITOSIS=0xF8FA261FBeBeBec4241B26125aC21b5541afe600
COLLATERAL_ETHEREUM=0xafF06A0cDCd30965160709F8e56E9B0EB54b177a
STAKING_MITOSIS=0x...
```

### Foundry Configuration

```toml
# Add RPC aliases to foundry.toml
[rpc_endpoints]
mainnet = "https://eth.drpc.org"
sepolia = "https://sepolia.infura.io/v3/${INFURA_KEY}"
mitosis = "https://rpc.mitosis.org"
dognet = "https://rpc.dognet.mitosis.org"
```

---

## Common Deployment Flow

### Initial Deployment (Mainnet)

```bash
# 1. Deploy Collateral to Ethereum
forge script script/DeployCollateral.s.sol \
  --rpc-url mainnet --broadcast --verify

# 2. Deploy xMorse to Mitosis
forge script script/DeployMitosisxMorse.s.sol \
  --rpc-url mitosis --broadcast

# 3. Configure cross-chain routing (Ethereum)
forge script script/ConfigurexMorseRouting.s.sol \
  --sig "configureEthereum(address,address)" \
  <ETHEREUM_COLLATERAL> <MITOSIS_XMORSE> \
  --rpc-url mainnet --broadcast

# 4. Configure cross-chain routing (Mitosis)
forge script script/ConfigurexMorseRouting.s.sol \
  --sig "configureMitosis(address,address)" \
  <MITOSIS_XMORSE> <ETHEREUM_COLLATERAL> \
  --rpc-url mitosis --broadcast

# 5. Deploy Staking contract to Mitosis
forge script script/DeployMitosisxMorseStaking.s.sol \
  --rpc-url mitosis --broadcast

# 6. Configure Staking (reward token, operator, etc.)
forge script script/ConfigurexMorseStaking.s.sol \
  --sig "setOperator(address,address)" \
  <STAKING_PROXY> <OPERATOR_ADDRESS> \
  --rpc-url mitosis --broadcast
```

---

## Reference

### Permissions
- **Owner**: All configuration changes, upgrades, emergency operations
- **Operator**: Reward distribution only

### Gas Limits
- SendNFT: 500,000
- SendNFTPartial: 700,000

### Lockup Period Calculations
```
1 day   = 86400 seconds
7 days  = 604800 seconds (default)
14 days = 1209600 seconds
30 days = 2592000 seconds
```

### Chain Information

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Ethereum Mainnet | 1 | https://eth.drpc.org |
| Sepolia Testnet | 11155111 | https://sepolia.infura.io/v3/... |
| Mitosis Mainnet | 124816 | https://rpc.mitosis.org |
| Mitosis Dognet | 124859 | https://rpc.dognet.mitosis.org |

---

## Related Documentation

- [Main README](../README.md) - Project overview
- [addresses.yaml](../addresses.yaml) - Deployed contract addresses
- [Hyperlane Documentation](https://docs.hyperlane.xyz/) - Cross-chain messaging
- [DN404 Documentation](https://github.com/Vectorized/dn404) - DN404 token standard

---

## Important Notes

1. **Private Key Security**: Never commit `.env` file to version control
2. **Mainnet Operations**: Always test on testnet first before mainnet deployment
3. **Gas Pricing**: Set appropriate gas prices for mainnet deployments
4. **Owner Privileges**: Upgrades and configuration changes are owner-only; manage owner keys securely
5. **Verification**: Always verify operations with `verify` functions after each action
6. **Proxy Pattern**: When deploying UUPS contracts, two addresses are created:
   - Implementation: Contains the logic code
   - Proxy: User-facing contract (use this for all interactions)

---

**Last Updated**: 2025-10-23  
**Version**: 1.0.0
