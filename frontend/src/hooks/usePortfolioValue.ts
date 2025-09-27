import { useMemo, useState, useEffect, useRef } from 'react';
import { useReadContract, useBlockNumber, useAccount } from 'wagmi';
import { formatUnits } from 'viem';
import { 
  ACCOUNT_ADDRESS,
  ERC20_ABI, 
  getContractsByChainId, 
  getWalletAssetsByChainId,
  isSupportedChain 
} from '../config/contracts';
import { getTokenPricesWithFallback } from '../utils/priceService';

/**
 * Hook to calculate total portfolio value
 */
export function usePortfolioValue() {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  const prevBlockNumberRef = useRef<bigint | undefined>();
  
  // Check if the current chain is supported
  const isSupported = isSupportedChain(chainId);
  
  // Get contract addresses and wallet assets for current chain
  const contracts = useMemo(() => getContractsByChainId(chainId), [chainId]);
  const walletAssets = useMemo(() => getWalletAssetsByChainId(chainId), [chainId]);
  
  // State for token prices
  const [tokenPrices, setTokenPrices] = useState<Record<string, number>>({});
  const [pricesLoading, setPricesLoading] = useState(true);
  
  // Fetch token prices on component mount and periodically
  useEffect(() => {
    const fetchPrices = async () => {
      try {
        setPricesLoading(true);
        if (walletAssets && walletAssets.length > 0) {
          const symbols = walletAssets.map(asset => asset.symbol);
          const prices = await getTokenPricesWithFallback(symbols);
          setTokenPrices(prices);
        }
      } catch (error) {
        console.error('Error fetching token prices:', error);
      } finally {
        setPricesLoading(false);
      }
    };

    // Only fetch prices if we have assets for this chain
    if (walletAssets && walletAssets.length > 0) {
      // Fetch prices immediately
      fetchPrices();

      // Set up interval to fetch prices every 2 minutes
      const priceInterval = setInterval(fetchPrices, 2 * 60 * 1000);

      return () => clearInterval(priceInterval);
    } else {
      setPricesLoading(false);
    }
  }, [walletAssets]);
  
  // Create hooks for wallet asset balances using a fixed number based on maximum assets
  // This ensures consistent hook order across renders
  const asset0 = walletAssets && walletAssets[0];
  const asset1 = walletAssets && walletAssets[1];
  const asset2 = walletAssets && walletAssets[2];
  const asset3 = walletAssets && walletAssets[3];
  const asset4 = walletAssets && walletAssets[4];
  const asset5 = walletAssets && walletAssets[5];
  const asset6 = walletAssets && walletAssets[6];
  const asset7 = walletAssets && walletAssets[7];
  const asset8 = walletAssets && walletAssets[8];
  
  const contract0Address = contracts && asset0 ? contracts[asset0.contractKey] : undefined;
  const contract1Address = contracts && asset1 ? contracts[asset1.contractKey] : undefined;
  const contract2Address = contracts && asset2 ? contracts[asset2.contractKey] : undefined;
  const contract3Address = contracts && asset3 ? contracts[asset3.contractKey] : undefined;
  const contract4Address = contracts && asset4 ? contracts[asset4.contractKey] : undefined;
  const contract5Address = contracts && asset5 ? contracts[asset5.contractKey] : undefined;
  const contract6Address = contracts && asset6 ? contracts[asset6.contractKey] : undefined;
  const contract7Address = contracts && asset7 ? contracts[asset7.contractKey] : undefined;
  const contract8Address = contracts && asset8 ? contracts[asset8.contractKey] : undefined;
  
  const hook0 = useReadContract({
    address: contract0Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract0Address }
  });
  
  const hook1 = useReadContract({
    address: contract1Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract1Address }
  });
  
  const hook2 = useReadContract({
    address: contract2Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract2Address }
  });
  
  const hook3 = useReadContract({
    address: contract3Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract3Address }
  });
  
  const hook4 = useReadContract({
    address: contract4Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract4Address }
  });
  
  const hook5 = useReadContract({
    address: contract5Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract5Address }
  });
  
  const hook6 = useReadContract({
    address: contract6Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract6Address }
  });
  
  const hook7 = useReadContract({
    address: contract7Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract7Address }
  });
  
  const hook8 = useReadContract({
    address: contract8Address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [ACCOUNT_ADDRESS],
    query: { enabled: !!contract8Address }
  });
  
  // Create array of hooks that correspond to actual assets
  const walletAssetHooks = useMemo(() => {
    if (!walletAssets) return [];
    
    const hooks = [hook0, hook1, hook2, hook3, hook4, hook5, hook6, hook7, hook8];
    return hooks.slice(0, walletAssets.length);
  }, [walletAssets, hook0, hook1, hook2, hook3, hook4, hook5, hook6, hook7, hook8]);
  
  // Calculate total wallet value
  const totalWalletValue = useMemo(() => {
    if (!contracts || !walletAssets || walletAssets.length === 0) return 0;
    
    return walletAssets.reduce((total, asset, index) => {
      const balanceResult = walletAssetHooks[index];
      if (!balanceResult || balanceResult.data === undefined || balanceResult.isError) return total;
      
      const balance = formatUnits(balanceResult.data as bigint, asset.decimals);
      const price = tokenPrices[asset.symbol] || 0;
      const value = parseFloat(balance) * price;
      
      return total + (isNaN(value) ? 0 : value);
    }, 0);
  }, [contracts, walletAssets, walletAssetHooks, blockNumber, tokenPrices]);

  // Track initial load state
  const [hasLoaded, setHasLoaded] = useState(false);
  useEffect(() => {
    if (walletAssetHooks.length > 0) {
      const allLoaded = walletAssetHooks.every(hook => hook.data !== undefined || hook.isError);
      if (allLoaded) {
        setHasLoaded(true);
      }
    } else if (walletAssets && walletAssets.length === 0) {
      setHasLoaded(true);
    }
  }, [walletAssetHooks, walletAssets]);

  // Refetch data when block number changes
  useEffect(() => {
    if (blockNumber && blockNumber !== prevBlockNumberRef.current && walletAssetHooks.length > 0) {
      // Refetch wallet asset balances
      walletAssetHooks.forEach(hook => {
        if (hook && hook.refetch) {
          hook.refetch();
        }
      });
      
      prevBlockNumberRef.current = blockNumber;
    }
  }, [blockNumber, walletAssetHooks]);

  // Determine final loading and error states
  const isWalletLoading = walletAssetHooks.some(hook => hook && hook.isLoading);
  const isWalletError = walletAssetHooks.some(hook => hook && hook.isError);
  const isLoading = (!hasLoaded && isWalletLoading);
  const isError = isWalletError;

  return {
    totalWalletValue,
    isSupported,
    isLoading,
    isError,
    pricesLoading,
    tokenPrices,
    walletAssets,
    walletAssetHooks,
    hasLoaded
  };
}
