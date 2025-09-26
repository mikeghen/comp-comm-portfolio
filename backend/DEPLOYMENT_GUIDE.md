# Event Listener Deployment Guide

## Overview

This implementation adds event-driven message processing to the Compound Assistant backend. When a user pays for a message on-chain via the MessageManager contract, the backend automatically processes the message and delivers the response.

## Architecture

```
User pays for message on-chain → MessagePaid event → Backend processes → markMessageProcessed → Response broadcast
```

## Components

1. **Event Listener** (`compound_assistant/event_listener.py`)
   - Listens for MessagePaid events from MessageManager contract
   - Processes messages using the existing agent
   - Calls markMessageProcessed on-chain
   - Broadcasts responses to WebSocket clients

2. **Contract Configuration** (`compound_assistant/config/contracts.py`)
   - MessageManager ABI for events and function calls
   - Multi-network support
   - Environment-based configuration

3. **Server Integration** (`server.py`)
   - Background event listener service
   - Enhanced WebSocket broadcast functionality
   - Shared message processing pipeline

## Environment Variables Required

```bash
# Network Configuration
NETWORK_ID=11155111                    # Chain ID (11155111 = Ethereum Sepolia)
PRIVATE_KEY=0x...                     # Agent's private key (needs AGENT_ROLE)

# Contract Addresses
MESSAGE_MANAGER_ADDRESS=0x...         # MessageManager contract address

# Optional: Custom RPC endpoints
ETHEREUM_SEPOLIA_RPC=https://rpc.sepolia.org
BASE_SEPOLIA_RPC=https://sepolia.base.org
BASE_MAINNET_RPC=https://mainnet.base.org

# Agent Configuration
OPENAI_API_KEY=sk-proj-...           # For AI agent functionality
```

## Deployment Steps

### 1. Contract Deployment
Deploy MessageManager contract and note the address. Ensure the agent's address has the `AGENT_ROLE`.

### 2. Environment Setup
Create `.env` file with required variables:
```bash
cp .env.example .env
# Edit .env with actual values
```

### 3. Dependencies
```bash
pip install web3 eth_account fastapi uvicorn langchain-openai langgraph python-dotenv
```

### 4. Start Server
```bash
python server.py
```

The server will:
- Start the FastAPI WebSocket server on port 8000
- Initialize the event listener in the background
- Begin monitoring for MessagePaid events

## Testing

### Unit Tests
```bash
# Test event listener functionality
python /tmp/test_event_listener.py

# Test end-to-end processing
python /tmp/test_e2e_event_processing.py

# Test server startup
python /tmp/test_server_startup.py
```

### Manual Testing
1. Deploy MessageManager contract
2. Configure environment with real contract address and agent key
3. Start the backend server
4. Pay for a message on-chain using the frontend
5. Verify the message is processed and marked as completed

## Security Considerations

1. **Private Key Security**: The agent's private key must be securely managed
2. **AGENT_ROLE**: Only the configured agent address can mark messages as processed
3. **Event Replay**: The system uses sigHash to prevent duplicate processing
4. **Network Reliability**: Robust error handling for network interruptions

## Monitoring

The system logs key events:
- Event listener startup/shutdown
- MessagePaid events received
- Message processing status
- Contract interaction results
- WebSocket broadcast activity

## Production Readiness

Current implementation includes:
- ✅ Event listening infrastructure
- ✅ Message processing pipeline  
- ✅ On-chain interaction (markMessageProcessed)
- ✅ WebSocket broadcasting
- ✅ Error handling and logging
- ✅ Multi-network support

For production, consider:
- [ ] Event persistence and replay protection
- [ ] Metrics and monitoring dashboards
- [ ] Rate limiting and spam protection
- [ ] Circuit breakers for external dependencies
- [ ] Full coinbase-agentkit integration