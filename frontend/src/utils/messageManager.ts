import { keccak256, encodeAbiParameters, toBytes, parseEther } from 'viem';

// MessageManager constants from the contract
export const MESSAGE_PRICE_USDC = 10_000_000; // 10 USDC with 6 decimals
export const MESSAGE_TYPEHASH = keccak256(toBytes("Message(bytes32 messageHash,address payer,uint256 nonce)"));

// EIP-712 Domain for MessageManager
export const MESSAGE_MANAGER_DOMAIN = {
  name: "MessageManager",
  version: "1",
} as const;

// Message struct type for EIP-712
export interface MessageStruct {
  messageHash: `0x${string}`;
  payer: `0x${string}`;
  nonce: bigint;
}

/**
 * Generate a content hash for a message
 */
export function generateContentHash(message: string): `0x${string}` {
  return keccak256(toBytes(message));
}

/**
 * Generate a random nonce for message uniqueness
 */
export function generateNonce(): bigint {
  return BigInt(Math.floor(Math.random() * 1000000));
}

/**
 * Create a Message struct for the contract
 */
export function createMessageStruct(
  messageContent: string,
  payerAddress: `0x${string}`,
  nonce?: bigint
): MessageStruct {
  const contentHash = generateContentHash(messageContent);
  const messageNonce = nonce ?? generateNonce();
  
  return {
    messageHash: contentHash,
    payer: payerAddress,
    nonce: messageNonce,
  };
}

/**
 * Build EIP-712 typed data for MessageManager signature
 */
export function buildMessageManagerTypedData(
  messageStruct: MessageStruct,
  chainId: number,
  messageManagerAddress: `0x${string}`
) {
  return {
    domain: {
      ...MESSAGE_MANAGER_DOMAIN,
      chainId,
      verifyingContract: messageManagerAddress,
    },
    types: {
      Message: [
        { name: "messageHash", type: "bytes32" },
        { name: "payer", type: "address" },
        { name: "nonce", type: "uint256" },
      ],
    },
    primaryType: "Message" as const,
    message: messageStruct,
  };
}