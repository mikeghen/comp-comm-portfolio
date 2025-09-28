// Import chain IDs from wagmi
import { base, baseSepolia, sepolia } from 'wagmi/chains';
import { Address } from 'viem';

// The wallet address from the backend (Vault Manager Eth Sepolia)
export const ACCOUNT_ADDRESS = "0x4cef30B8DA9db30D7CEBAd0bD86f82B9489B1d36" as Address;

// Define type for contract addresses using Address from viem
export interface CompoundNetworkContracts {
    Comet: Address;
    COMP: Address;
    USDC?: Address;
    WETH?: Address;
    WBTC?: Address;
    cbETH?: Address;
    cbBTC?: Address;
    WSTETH?: Address;
    AERO?: Address;
    cUSDCv3?: Address;
    cWETHv3?: Address;
    cAEROv3?: Address;
    Faucet?: Address;
    MessageManager?: Address; // Placeholder for MessageManager contract
    ManagementToken?: Address; // ManagementToken contract
}

// Chain ID constants for clarity
const BASE_CHAIN_ID = base.id; // 8453
const BASE_SEPOLIA_CHAIN_ID = baseSepolia.id; // 84532
const ETH_SEPOLIA_CHAIN_ID = sepolia.id; // 11155111

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
        AERO: "0x940181a94A35A4569E4529A3CDfB74e38FD98631",
        cUSDCv3: "0xb125E6687d4313864e53df431d5425969c15Eb2F",
        cWETHv3: "0x46e6b214b524310239732D51387075E0e70970bf",
        cAEROv3: "0x784efeB622244d2348d4F2522f8860B96fbEcE89",
        MessageManager: "0x0000000000000000000000000000000000000000", // Placeholder - replace with actual deployment address
    },
    // Base Sepolia Testnet
    [BASE_SEPOLIA_CHAIN_ID]: {
        Comet: "0x571621Ce60Cebb0c1D442B5afb38B1663C6Bf017",
        COMP: "0x2f535da74048c0874400f0371Fba20DF983A56e2",
        USDC: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        WETH: "0x4200000000000000000000000000000000000006",
        cbETH: "0x774eD9EDB0C5202dF9A86183804b5D9E99dC6CA3",
        Faucet: "0xD76cB57d8B097B80a6eE4D1b4d5ef872bfBa6051",
        MessageManager: "0x0000000000000000000000000000000000000000", // Placeholder - replace with actual deployment address
    },
    // Ethereum Sepolia Testnet
    [ETH_SEPOLIA_CHAIN_ID]: {
        Comet: "0x571621Ce60Cebb0c1D442B5afb38B1663C6Bf017",
        COMP: "0xA6c8D1c55951e8AC44a0EaA959Be5Fd21cc07531",
        USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
        WETH: "0x2D5ee574e710219a521449679A4A7f2B43f046ad",
        WBTC: "0xa035b9e130F2B1AedC733eEFb1C67Ba4c503491F",
        cUSDCv3: "0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e",
        cWETHv3: "0x2943ac1216979aD8dB76D9147F64E61adc126e96",
        Faucet: "0x68793eA49297eB75DFB4610B68e076D2A5c7646C", // Sepolia USDC Faucet
        MessageManager: "0xDa779e0Ed56140Bd700e3B891AD6e107E0Ef764D", // Sepolia MessageManager address
        ManagementToken: "0xEf4f63830E0528254579731C46D69aF74cC7d1ad", // Sepolia ManagementToken address
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
        case ETH_SEPOLIA_CHAIN_ID:
            return 'Ethereum Sepolia';
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

// Network-specific wallet assets configuration
export interface WalletAsset {
    symbol: string;
    contractKey: keyof CompoundNetworkContracts;
    decimals: number;
}

export const NETWORK_WALLET_ASSETS: Record<number, WalletAsset[]> = {
    // Base Mainnet - all assets available
    [BASE_CHAIN_ID]: [
        { symbol: 'USDC', contractKey: 'USDC', decimals: 6 },
        { symbol: 'WETH', contractKey: 'WETH', decimals: 18 },
        { symbol: 'cbETH', contractKey: 'cbETH', decimals: 18 },
        { symbol: 'cbBTC', contractKey: 'cbBTC', decimals: 8 },
        { symbol: 'WSTETH', contractKey: 'WSTETH', decimals: 18 },
        { symbol: 'AERO', contractKey: 'AERO', decimals: 18 },
        { symbol: 'cUSDCv3', contractKey: 'cUSDCv3', decimals: 6 },
        { symbol: 'cWETHv3', contractKey: 'cWETHv3', decimals: 18 },
        { symbol: 'cAEROv3', contractKey: 'cAEROv3', decimals: 18 },
    ],
    // Base Sepolia - limited assets
    [BASE_SEPOLIA_CHAIN_ID]: [
        { symbol: 'USDC', contractKey: 'USDC', decimals: 6 },
        { symbol: 'WETH', contractKey: 'WETH', decimals: 18 },
        { symbol: 'cbETH', contractKey: 'cbETH', decimals: 18 },
    ],
    // Ethereum Sepolia - limited assets
    [ETH_SEPOLIA_CHAIN_ID]: [
        { symbol: 'USDC', contractKey: 'USDC', decimals: 6 },
        { symbol: 'WETH', contractKey: 'WETH', decimals: 18 },
        { symbol: 'COMP', contractKey: 'COMP', decimals: 18 },
        { symbol: 'WBTC', contractKey: 'WBTC', decimals: 8 },
        { symbol: 'cUSDCv3', contractKey: 'cUSDCv3', decimals: 6 },
        { symbol: 'cWETHv3', contractKey: 'cWETHv3', decimals: 18 },
    ],
};

/**
 * Get wallet assets for a specific chain
 */
export function getWalletAssetsByChainId(chainId?: number): WalletAsset[] {
    if (!chainId || !NETWORK_WALLET_ASSETS[chainId]) {
        return [];
    }
    return NETWORK_WALLET_ASSETS[chainId];
}

import ERC20_ABI from "./abi/ERC20.json";
import COMET_ABI from "./abi/Comet.json";
import MESSAGE_MANAGER_ABI from "./abi/MessageManager.json";
import FAUCET_ABI from "./abi/Faucet.json";

export { ERC20_ABI, COMET_ABI, MESSAGE_MANAGER_ABI, FAUCET_ABI };
