import React, { ReactNode } from 'react';
import '@rainbow-me/rainbowkit/styles.css';
import {
  RainbowKitProvider,
  darkTheme,
  getDefaultConfig
} from '@rainbow-me/rainbowkit';
import { WagmiConfig } from 'wagmi';
import { base } from 'wagmi/chains';
import { http } from 'viem';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

// Create a client for React Query
const queryClient = new QueryClient();

// Configure RainbowKit + Wagmi with only Base Mainnet
const config = getDefaultConfig({
  appName: 'Compound Assistant',
  projectId: 'YOUR_PROJECT_ID', // Get this from https://cloud.walletconnect.com
  chains: [base],
  transports: {
    [base.id]: http(),
  },
  ssr: false, // Disable server-side rendering mode
});

interface WalletProviderProps {
  children: ReactNode;
}

// Create wallet provider component
const WalletProvider: React.FC<WalletProviderProps> = ({ children }) => {
  return (
    <WagmiConfig config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={darkTheme({
            accentColor: '#008000',
            accentColorForeground: 'white',
            borderRadius: 'medium'
          })}
        >
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiConfig>
  );
};

export default WalletProvider; 