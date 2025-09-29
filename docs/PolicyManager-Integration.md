# PolicyManager Integration

This document describes the integration between the Compound Assistant backend and the PolicyManager smart contract for dynamic agent prompt management.

## Overview

The backend now fetches the agent prompt from the PolicyManager contract on-chain and appends it to the existing hardcoded system prompt. This allows for dynamic policy updates via on-chain governance while maintaining the necessary base instructions.

## Architecture

The integration consists of several components:

1. **PolicyManagerContract** (`compound_assistant/contracts/policy_manager.py`): Interface for interacting with the PolicyManager smart contract
2. **BlockchainConfig** (`compound_assistant/config/blockchain.py`): Updated configuration to include PolicyManager contract address
3. **Agent System** (`compound_assistant/agent.py`): Modified to fetch and integrate on-chain prompt

## Configuration

### Environment Variables

Add the following optional environment variable to your `.env` file:

```bash
# PolicyManager contract address on Sepolia (default provided, but can be overridden)
POLICY_MANAGER_CONTRACT_ADDRESS=0x10e6e63337ea16f6ec5022a42fced95e74fb3f1d
```

### Default Configuration

- **Sepolia Network**: `0x10e6e63337ea16f6ec5022a42fced95e74fb3f1d`
- If not specified, the system uses the default deployed contract address
- The backend requires `ETHEREUM_RPC_URL` to be configured for on-chain access

## How It Works

1. **Initialization**: When the agent starts, it attempts to connect to the Ethereum network
2. **Prompt Fetching**: The system calls `PolicyManager.getPrompt()` to retrieve the current on-chain prompt
3. **Integration**: The on-chain prompt is appended to the hardcoded system prompt with a clear separator
4. **Fallback**: If the on-chain fetch fails (network issues, RPC unavailable), the system gracefully falls back to using only the hardcoded prompt

### Example Integration

```
[Hardcoded system prompt with base instructions]

Additional Investment Policy from On-Chain Governance:
You are an investment manager for a portfolio. You must keep at least 20% of the portfolio as USDC. You may invest up to 50% in WETH and up to 40% in other assets like COMP and WBTC.
```

## Benefits

1. **Dynamic Updates**: Policy can be updated on-chain without code changes
2. **Governance**: Changes can be managed through on-chain governance mechanisms
3. **Reliability**: System continues to work even if on-chain access is unavailable
4. **Transparency**: All policy changes are recorded on-chain with version tracking

## Error Handling

The system includes robust error handling:

- **Network Failures**: Logs warnings and continues with hardcoded prompt
- **Contract Errors**: Catches and logs contract interaction errors
- **Invalid Data**: Validates prompt data before integration

## Logging

The integration provides detailed logging:

- `INFO`: Successful on-chain prompt fetches and integrations
- `WARNING`: Failed attempts with fallback behavior
- Debug information about prompt lengths and versions

## Development and Testing

For development environments without blockchain access:

1. The system automatically detects missing `ETHEREUM_RPC_URL`
2. Logs appropriate warnings about skipping on-chain fetch
3. Continues with full functionality using hardcoded prompts

## Contract Interface

The `PolicyManagerContract` class provides the following methods:

- `get_prompt()`: Returns (prompt_text, version)
- `get_prompt_text_only()`: Returns only the prompt text
- `get_prompt_version()`: Returns the current version number
- `get_prompt_slice(start, end)`: Gas-efficient partial prompt retrieval

## Security Considerations

1. **Read-Only Access**: The backend only reads from the contract (no write operations)
2. **Validation**: Prompt data is validated before integration
3. **Fallback Safety**: System remains functional even if contract is compromised
4. **Version Tracking**: Contract maintains version numbers for audit trails

## Future Enhancements

1. **Caching**: Implement prompt caching to reduce RPC calls
2. **Event Listening**: Listen for `PromptEdited` events for real-time updates
3. **Multiple Policies**: Support for different policy types or contexts
4. **Access Control**: Integration with role-based prompt access