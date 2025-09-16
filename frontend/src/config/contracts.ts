// Import chain IDs from wagmi
import { base, baseSepolia } from 'wagmi/chains';
import { Address } from 'viem';

// The wallet address from the backend
export const ACCOUNT_ADDRESS = "0xe6D029C4c6e9c60aD0E49d92C850CD8d3E6C394a" as Address;

// Define type for contract addresses using Address from viem
export interface CompoundNetworkContracts {
    Comet: Address;
    COMP: Address;
    USDC?: Address;
    WETH?: Address;
    cbETH?: Address;
    cbBTC?: Address;
    WSTETH?: Address;
    Faucet?: Address;
}

// Chain ID constants for clarity
const BASE_CHAIN_ID = base.id; // 8453
const BASE_SEPOLIA_CHAIN_ID = baseSepolia.id; // 84532

// TypeScript will enforce that all values are properly formatted addresses
export const CompoundContracts: Record<number, CompoundNetworkContracts> = {
    // Base Mainnet
    [BASE_CHAIN_ID]: {
        Comet: "0xb125E6687d4313864e53df431d5425969c15Eb2F",
        COMP: "0x9e1028F5F1D5eDE59748FFceE5532509976840E0",
        USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        WETH: "0x4200000000000000000000000000000000000006",    
        cbETH: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22",   
        cbBTC: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
        WSTETH: "0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452",
    },
    // Base Sepolia Testnet
    [BASE_SEPOLIA_CHAIN_ID]: {
        Comet: "0x571621Ce60Cebb0c1D442B5afb38B1663C6Bf017",
        COMP: "0x2f535da74048c0874400f0371Fba20DF983A56e2",
        USDC: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        WETH: "0x4200000000000000000000000000000000000006",
        cbETH: "0x774eD9EDB0C5202dF9A86183804b5D9E99dC6CA3",
        Faucet: "0xD76cB57d8B097B80a6eE4D1b4d5ef872bfBa6051"
    }
};

/**
 * Helper function to get contract addresses by chainId
 */
export function getContractsByChainId(chainId?: number): CompoundNetworkContracts | undefined {
    if (!chainId) return undefined;
    return CompoundContracts[chainId];
}

/**
 * Helper function to get a specific contract address by chainId and contract name
 */
export function getContractAddress<K extends keyof CompoundNetworkContracts>(
    chainId: number | undefined, 
    contractName: K
): CompoundNetworkContracts[K] | undefined {
    if (!chainId) return undefined;
    const contracts = CompoundContracts[chainId];
    return contracts?.[contractName];
}

/**
 * Helper function to get a user-friendly network name
 */
export function getNetworkName(chainId?: number): string {
    if (!chainId) return 'Disconnected';
    
    switch (chainId) {
        case BASE_CHAIN_ID:
            return 'Base';
        case BASE_SEPOLIA_CHAIN_ID:
            return 'Base Sepolia';
        default:
            return `Chain ${chainId}`;
    }
}

/**
 * Check if a chain is supported by our application
 */
export function isSupportedChain(chainId?: number): boolean {
    return !!chainId && !!CompoundContracts[chainId];
}

import ERC20_ABI from "./abi/ERC20.json";
import COMET_ABI from "./abi/Comet.json";

export { ERC20_ABI, COMET_ABI };
