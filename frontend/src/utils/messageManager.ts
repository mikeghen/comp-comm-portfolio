import { keccak256, toBytes } from 'viem';

// MessageManager constants from the contract
export const MESSAGE_PRICE_USDC = 1_000_000; // 10 USDC with 6 decimals

/**
 * Generate a message hash for the simplified contract
 */
export function generateMessageHash(message: string): `0x${string}` {
  return keccak256(toBytes(message));
}

/**
 * Check if a message has been paid for by verifying the stored message is not empty
 */
export function isMessagePaid(storedMessage: string): boolean {
  return storedMessage.length > 0;
}