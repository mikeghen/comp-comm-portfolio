import React, { useMemo, useState, useEffect, useRef } from 'react';
import { useReadContract, useBlockNumber, useAccount } from 'wagmi';
import { formatUnits } from 'viem';
import { 
  ACCOUNT_ADDRESS,
  ERC20_ABI, 
  getContractsByChainId, 
  getWalletAssetsByChainId,
  isSupportedChain 
} from '../../config/contracts';
import { getTokenPricesWithFallback } from '../../utils/priceService';

function AccountOverview() {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  const prevBlockNumberRef = useRef<bigint | undefined>();
  
  // Check if the current chain is supported
  const isSupported = isSupportedChain(chainId);
  
  // Get contract addresses and wallet assets for current chain
  const contracts = getContractsByChainId(chainId);
  const walletAssets = getWalletAssetsByChainId(chainId);
  
  // State for token prices
  const [tokenPrices, setTokenPrices] = useState<Record<string, number>>({});
  const [pricesLoading, setPricesLoading] = useState(true);
  
  // Fetch token prices on component mount and periodically
  useEffect(() => {
    const fetchPrices = async () => {
      try {
        setPricesLoading(true);
        const symbols = walletAssets.map(asset => asset.symbol);
        const prices = await getTokenPricesWithFallback(symbols);
        setTokenPrices(prices);
      } catch (error) {
        console.error('Error fetching token prices:', error);
      } finally {
        setPricesLoading(false);
      }
    };

    // Only fetch prices if we have assets for this chain
    if (walletAssets.length > 0) {
      // Fetch prices immediately
      fetchPrices();

      // Set up interval to fetch prices every 2 minutes
      const priceInterval = setInterval(fetchPrices, 2 * 60 * 1000);

      return () => clearInterval(priceInterval);
    } else {
      setPricesLoading(false);
    }
  }, [walletAssets]);
  
  // Create hooks for wallet asset balances
  const walletAssetHooks = walletAssets.map(asset => {
    const contractAddress = contracts?.[asset.contractKey];
    
    return useReadContract({
      address: contractAddress,
      abi: ERC20_ABI,
      functionName: 'balanceOf',
      args: [ACCOUNT_ADDRESS],
    });
  });
  
  // Calculate total wallet value
  const totalWalletValue = useMemo(() => {
    if (!contracts || walletAssets.length === 0) return 0;
    
    return walletAssets.reduce((total, asset, index) => {
      const balanceResult = walletAssetHooks[index];
      if (balanceResult.data === undefined || balanceResult.isError) return total;
      
      const balance = formatUnits(balanceResult.data as bigint, asset.decimals);
      const price = tokenPrices[asset.symbol] || 0;
      const value = parseFloat(balance) * price;
      
      return total + (isNaN(value) ? 0 : value);
    }, 0);
  }, [contracts, walletAssets, walletAssetHooks, blockNumber, tokenPrices]);

  // Track initial load state
  const [hasLoaded, setHasLoaded] = useState(false);
  useEffect(() => {
    const allLoaded = walletAssetHooks.every(hook => hook.data !== undefined || hook.isError);
    if (allLoaded) {
      setHasLoaded(true);
    }
  }, [walletAssetHooks]);

  // Refetch data when block number changes
  useEffect(() => {
    if (blockNumber && blockNumber !== prevBlockNumberRef.current) {
      // Refetch wallet asset balances
      walletAssetHooks.forEach(hook => {
        hook.refetch();
      });
      
      prevBlockNumberRef.current = blockNumber;
    }
  }, [blockNumber, walletAssetHooks]);


  // Format values for display
  const formattedWalletValue = totalWalletValue.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD'
  });

  // Determine final loading and error states
  const isWalletLoading = walletAssetHooks.some(hook => hook.isLoading);
  const isWalletError = walletAssetHooks.some(hook => hook.isError);
  const isLoading = (!hasLoaded && isWalletLoading);
  const isError = isWalletError;

  return (
    <div className="card mb-4">
      <div className="card-header bg-white border-bottom">
        <h5 className="mb-0">Portfolio Value</h5>
      </div>
      <div className="card-body bg-light">
        {!isSupported ? (
          <div className="text-center py-2 text-warning">
            Please connect to a supported network
          </div>
        ) : isLoading ? (
          <div className="text-center py-2">
            <div className="spinner-border spinner-border-sm" role="status">
              <span className="visually-hidden">Loading...</span>
            </div> Loading account data...
          </div>
        ) : isError ? (
          <div className="text-center py-2 text-danger">
            Error loading account data
            <div className="small mt-1">
              Check console for detailed error information
            </div>
          </div>
        ) : (
          <>
            <div className="row">
              <div className="col">
                <div className="h4">
                  {formattedWalletValue}
                </div>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

export default AccountOverview;