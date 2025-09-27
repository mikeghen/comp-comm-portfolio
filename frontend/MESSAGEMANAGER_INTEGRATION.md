# MessageManager Frontend Integration

This document describes the implementation of the MessageManager contract integration with the frontend send button.

## Overview

The integration transforms the simple "Send" button into a dynamic button that handles USDC approval and payment for messages via the MessageManager contract's `payForMessageWithSig` function.

## Features Implemented

### Dynamic Button States

The send button now displays different states based on the user's wallet and approval status:

1. **"Send"** - Default state when no wallet connected or MessageManager contract not available
2. **"Checking..."** - Loading state while checking USDC allowance  
3. **"Insufficient USDC"** - User doesn't have enough USDC (10 USDC required)
4. **"Approve"** - User has USDC but needs to approve MessageManager contract
5. **"Pay and Sign Message"** - User is approved and ready to execute the full flow

### Complete Transaction Flow

When a user clicks "Pay and Sign Message", the following happens:

1. **Message Preparation**: Creates a MessageManager.Message struct with:
   - `messageHash`: keccak256 hash of the message content
   - `payer`: User's wallet address
   - `nonce`: Random nonce for replay protection

2. **EIP-712 Signing**: Signs typed data according to MessageManager domain:
   - Domain: `{name: "MessageManager", version: "1", chainId, verifyingContract}`
   - Types: Message struct definition
   - Message: The prepared message struct

3. **Contract Call**: Executes `payForMessageWithSig` with:
   - `m`: The message struct
   - `sig`: The EIP-712 signature
   - `messageURI`: The original message content

4. **Traditional Flow**: Also sends the message through the existing WebSocket flow

## Technical Implementation

### Files Created/Modified

- `frontend/src/config/abi/MessageManager.json` - Contract ABI
- `frontend/src/config/contracts.ts` - Added MessageManager addresses (placeholders)
- `frontend/src/utils/messageManager.ts` - EIP-712 utilities and message preparation
- `frontend/src/hooks/useUSDCApproval.ts` - Hook for checking approval status
- `frontend/src/components/chat/MessageInput.tsx` - Updated with full integration
- `frontend/src/components/demo/MessageInputStatesDemo.tsx` - Demo component

### Key Dependencies

- `wagmi` - For contract interactions (`useReadContract`, `useWriteContract`, `useSignTypedData`)
- `viem` - For crypto utilities (`keccak256`, address handling)
- `react-bootstrap` - For UI components

### Contract Integration

The integration uses the MessageManager contract's key function:

```solidity
function payForMessageWithSig(
    Message calldata m, 
    bytes calldata sig, 
    string calldata messageURI
) external nonReentrant
```

Where the Message struct is:
```solidity
struct Message {
    bytes32 messageHash;
    address payer;
    uint256 nonce;
}
```

## Configuration

### Contract Addresses

Currently using placeholder addresses (`0x0000...`). Update these in `contracts.ts`:

```typescript
MessageManager: "0x[ACTUAL_DEPLOYMENT_ADDRESS]"
```

For each supported network:
- Base Mainnet
- Base Sepolia  
- Ethereum Sepolia

### Message Price

The contract requires 10 USDC per message (`MESSAGE_PRICE_USDC = 10_000_000` with 6 decimals).

## Testing

### Demo Mode

Access the button states demo at: `http://localhost:3000/?demo=true`

This shows all possible button states and explains the integration flow.

### Manual Testing

1. Connect a wallet with USDC
2. Observe button state changes
3. Test approval flow
4. Test message signing and payment

## Error Handling

The integration handles various error states:

- Network connection issues
- Insufficient USDC balance
- Contract interaction failures
- Signature rejection by user
- Transaction failures

## Future Improvements

1. **Gas Estimation** - Show estimated gas costs
2. **Transaction History** - Track successful payments
3. **Batch Approvals** - Allow approving for multiple messages at once
4. **Better Error Messages** - More specific error handling and user feedback
5. **Loading Indicators** - Enhanced UX during long-running operations

## Security Considerations

- Uses EIP-712 for structured data signing
- Includes nonce for replay protection
- Validates signatures on-chain
- Proper allowance checks before spending USDC
- Follows standard approval patterns