import { Address } from 'viem';

export const MESSAGE_MANAGER_ADDRESS = '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC' as Address;
export const MESSAGE_MANAGER_DOMAIN_NAME = 'MessageManager';
export const MESSAGE_MANAGER_DOMAIN_VERSION = '1';
export const MESSAGE_PRICE_USDC = 10_000_000n;

export type MessagePayload = {
  messageHash: `0x${string}`;
  payer: Address;
  nonce: bigint;
};

export type MessageTypedData = {
  Message: [
    { name: 'messageHash'; type: 'bytes32' },
    { name: 'payer'; type: 'address' },
    { name: 'nonce'; type: 'uint256' }
  ];
};

export const MESSAGE_TYPED_DATA: MessageTypedData = {
  Message: [
    { name: 'messageHash', type: 'bytes32' },
    { name: 'payer', type: 'address' },
    { name: 'nonce', type: 'uint256' }
  ]
};
