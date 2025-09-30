# Portfolio Holdings Injection

This document explains how the Compound Assistant agent is made aware of the current portfolio holdings to enable context-aware operations.

## Overview

The agent's system prompt is enhanced with real-time portfolio balance information, allowing it to understand and execute instructions that reference actual holdings (e.g., "swap all USDC to WETH" where "all" refers to the actual USDC balance).

## Architecture

The implementation uses a two-stage approach to ensure portfolio holdings are always fresh:

### 1. Server Startup (agent.py)
When the server starts, `load_system_prompt()` creates a base system prompt containing:
- Base agent instructions
- Onchain policy (fetched from PolicyManager contract)
- **NOT** portfolio holdings (to ensure freshness)

### 2. Each Agent Call (nodes.py)
When processing a message, `call_agent()`:
- Fetches **fresh** portfolio balances from the blockchain
- Injects the portfolio context into the system prompt
- Final structure: `base_prompt + portfolio_context + onchain_policy`

This ensures balances are current at each agent invocation, even after swaps/deposits/withdrawals.

## Implementation Details

### Portfolio Balance Fetching

**File:** `backend/compound_assistant/utils/portfolio_balances.py`

Key functions:
- `fetch_portfolio_balances()` - Fetches balances for all configured assets
- `format_portfolio_holdings_context()` - Formats balances as JSON for the prompt
- `get_wallet_address()` - Derives wallet address from PRIVATE_KEY env var

### Asset Configuration

Assets are configured to match the frontend's `NETWORK_WALLET_ASSETS` for Ethereum Sepolia:

```python
SEPOLIA_ASSETS = [
    {"symbol": "USDC", "address": "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", "decimals": 6},
    {"symbol": "WETH", "address": "0x2D5ee574e710219a521449679A4A7f2B43f046ad", "decimals": 18},
    {"symbol": "COMP", "address": "0xA6c8D1c55951e8AC44a0EaA959Be5Fd21cc07531", "decimals": 18},
    {"symbol": "WBTC", "address": "0xa035b9e130F2B1AedC733eEFb1C67Ba4c503491F", "decimals": 8},
    {"symbol": "cUSDCv3", "address": "0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e", "decimals": 6},
    {"symbol": "cWETHv3", "address": "0x2943ac1216979aD8dB76D9147F64E61adc126e96", "decimals": 18},
]
```

### Balance Fetching Process

1. Derive wallet address from `PRIVATE_KEY` environment variable
2. For each asset, call `balanceOf(walletAddress)` on the ERC20/Comet contract
3. Convert from wei to human-readable format using asset decimals
4. Return as dictionary: `{"USDC": "10.500124", "WETH": "0.14589390", ...}`

### Prompt Format

Portfolio holdings are injected in this format:

```
---
Your portfolio currently has the following holdings:
{
  "USDC": "10.500124",
  "WETH": "0.14589390",
  "WBTC": "0.000001",
  "COMP": "0",
  "cUSDCv3": "10.349058",
  "cWETHv3": "0.0500000"
}
---
```

### Error Handling

The implementation gracefully handles errors:
- If `ETHEREUM_RPC_URL` is not set: returns zero balances
- If `PRIVATE_KEY` is not set: returns zero balances
- If fetching a specific asset fails: uses "0" for that asset
- All assets are always included, even if balance is 0

## Use Cases

With this feature, the agent can now handle instructions like:

- ✅ "Swap all USDC to WETH" - knows exact USDC balance
- ✅ "Deposit half of my WETH into Compound" - knows exact WETH balance
- ✅ "What's in my portfolio?" - has complete current state
- ✅ "Withdraw all cUSDCv3" - knows exact cUSDCv3 balance

## Configuration

### Environment Variables

Required:
- `ETHEREUM_RPC_URL` - WebSocket RPC endpoint (e.g., `wss://sepolia.infura.io/ws/v3/...`)
- `PRIVATE_KEY` - Private key for the agent's wallet

Optional:
- Defaults to Ethereum Sepolia (chain ID 11155111)
- Asset addresses and decimals are hardcoded to match frontend configuration

### Adding New Assets

To add support for new assets:

1. Update `SEPOLIA_ASSETS` in `portfolio_balances.py`
2. Ensure the frontend's `NETWORK_WALLET_ASSETS` is also updated
3. Include the contract address and decimals

## Testing

The implementation includes comprehensive error handling and logging:

```bash
# Check logs for portfolio balance fetching
✅ Successfully fetched portfolio balances for 6 assets
🔄 Injected fresh portfolio holdings into system prompt
```

### Manual Testing

You can verify balances are being fetched correctly by:

1. Checking the agent logs when it processes a message
2. Asking the agent "What's in my portfolio?"
3. Comparing with blockchain explorer (Sepolia Etherscan)

## Performance Considerations

- Balance fetching adds ~6 RPC calls per agent invocation (one per asset)
- Calls are made sequentially with error handling
- Typical overhead: <1 second on a good RPC connection
- Balances are only fetched at the start of a conversation (when system message is added)

## Future Enhancements

Potential improvements:
- Cache balances for a short duration (e.g., 30 seconds)
- Parallel RPC calls for faster fetching
- Support for multiple chains
- Dynamic asset discovery from on-chain registry
