# CompComm Portfolio Deployment Guide

This document explains how to deploy the CompComm Portfolio system using the modular deployment scripts.

## Overview

The deployment system follows the pattern from [withtally/staker](https://github.com/withtally/staker) and consists of:

1. **DeployBaseImpl.s.sol** - Abstract base deployment script with core logic
2. **BaseNetworkDeploy.s.sol** - Base mainnet specific configuration
3. **BaseDeployment.t.sol** - Integration tests validating deployment

## Architecture

The system uses a composition pattern to avoid inheritance conflicts:

```
CompCommPortfolio (Main Coordinator)
├── ManagementToken (ERC20 with roles)
├── MessageManager (Handles USDC payments for AI messages)
├── PolicyManager (Manages editable investment policy)
└── VaultManager (DeFi integrations + timelock)
```

## Environment Variables

Before deploying, set these environment variables:

```bash
export ADMIN_ADDRESS="0x..."           # Final admin address
export DEV_ADDRESS="0x..."             # Dev share receiver  
export AGENT_ADDRESS="0x..."           # Agent for executing operations
export INITIAL_PROMPT="..."            # Investment policy text
export DEPLOYER_PRIVATE_KEY="0x..."    # Deployer private key (optional, defaults to anvil key)
```

## Deployment

### 1. Base Mainnet Deployment

```bash
cd contracts
forge script script/BaseNetworkDeploy.s.sol:BaseNetworkDeploy --rpc-url $BASE_RPC_URL --broadcast --verify
```

### 2. Test Deployment (Local)

```bash
# Start local node
anvil

# Deploy to local network
forge script script/BaseNetworkDeploy.s.sol:BaseNetworkDeploy --rpc-url http://localhost:8545 --broadcast
```

## Contracts Deployed

The deployment creates:

1. **ManagementToken** - ERC20 token with minting/burning roles
2. **MessageManager** - Handles $10 USDC payments for AI agent messages
3. **PolicyManager** - Manages editable investment policy ($1 USDC per 10 chars)
4. **VaultManager** - 18-month timelock vault with Uniswap v3 + Compound v3 integration
5. **CompCommPortfolio** - Main coordinator contract

## Role Configuration

The deployment automatically sets up:

- **Admin**: Can pause system, configure allowlists, transfer ownership
- **Agent**: Can execute Uniswap swaps and Compound operations
- **MessageManager**: Can mint MT tokens for message payments
- **PolicyManager**: Can mint MT tokens for policy edits  
- **VaultManager**: Can burn MT tokens for redemptions

## Base Mainnet Configuration

The Base deployment configures these allowlists:

### Allowed Assets
- USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- WETH: `0x4200000000000000000000000000000000000006`
- AERO: `0x940181a94A35A4569E4529A3CDfB74e38FD98631`
- sUSDC: `0x3FbC4C6b30fb0db3fA3DE8060B985052B48dED2` (placeholder)

### Allowed Comets
- cUSDCv3: `0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf`
- cWETHv3: `0x46e6b214b524310239732D51387075E0e70970bf`
- cAEROv3: TBD (placeholder address)
- sSUSDv3: TBD (placeholder address)

## Integration Tests

Run the comprehensive test suite:

```bash
forge test --match-contract BaseDeploymentIntegrationTest -vvv
```

Tests validate:
- ✅ Complete deployment flow
- ✅ Admin role configuration and access control
- ✅ Agent role setup across all managers  
- ✅ Allowlist configuration for Base mainnet
- ✅ Token minting and burning functionality
- ✅ System pause/unpause capabilities
- ✅ Access control restrictions

## Post-Deployment

After deployment:

1. **Verify contracts** on Basescan
2. **Test agent operations** with small amounts
3. **Configure monitoring** for events and roles
4. **Set up frontend** to interact with deployed contracts

## Security Considerations

- Admin keys should use multisig or timelock
- Agent keys should be secured and rotated regularly
- Monitor for unusual minting/burning activity
- Verify allowlist configurations match expectations

## Troubleshooting

### Common Issues

1. **"ADMIN_ADDRESS cannot be zero"** - Set required environment variables
2. **Insufficient balance** - Ensure deployer has enough ETH for gas
3. **Network mismatch** - Verify RPC URL matches intended network

### Verification

After deployment, verify:
- All contracts have correct addresses in logs
- Role assignments are correct
- Allowlists contain expected tokens/Comets
- Ownership transferred to admin address

## Extension

To deploy on other networks:

1. Create new deployment script inheriting from `DeployBaseImpl`
2. Override `_portfolioConfiguration()` with network-specific addresses
3. Override `_configureAllowlists()` with network-specific assets
4. Add new script to CI/CD pipeline