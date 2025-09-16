import React, { useEffect, useState, useMemo } from 'react';
import { Card, ListGroup, Spinner } from 'react-bootstrap';
import AssetRow from './AssetRow';
import { useReadContract, useBlockNumber, useAccount } from 'wagmi';
import { formatUnits } from 'viem';
import { 
  ACCOUNT_ADDRESS,
  ERC20_ABI,
  getContractsByChainId,
  isSupportedChain 
} from '../../config/contracts';
import { getTokenPricesWithFallback } from '../../utils/priceService';

// Define the wallet assets including the new compound tokens
const WALLET_ASSETS = [
  { symbol: 'USDC', contractKey: 'USDC' as const, decimals: 6 },
  { symbol: 'WETH', contractKey: 'WETH' as const, decimals: 18 },
  { symbol: 'cbETH', contractKey: 'cbETH' as const, decimals: 18 },
  { symbol: 'cbBTC', contractKey: 'cbBTC' as const, decimals: 8 },
  { symbol: 'WSTETH', contractKey: 'WSTETH' as const, decimals: 18 },
  { symbol: 'AERO', contractKey: 'AERO' as const, decimals: 18 },
  { symbol: 'cUSDCv3', contractKey: 'cUSDCv3' as const, decimals: 6 },
  { symbol: 'cWETHv3', contractKey: 'cWETHv3' as const, decimals: 18 },
  { symbol: 'cAEROv3', contractKey: 'cAEROv3' as const, decimals: 18 },
];

const WalletAssetsList: React.FC = () => {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  
  // Check if the current chain is supported
  const isSupported = isSupportedChain(chainId);
  
  // Get contract addresses for the current chain
  const contracts = getContractsByChainId(chainId);
  
  // State to track initial loading
  const [hasInitiallyLoaded, setHasInitiallyLoaded] = useState(false);
  
  // State for token prices
  const [tokenPrices, setTokenPrices] = useState<Record<string, number>>({});
  const [pricesLoading, setPricesLoading] = useState(true);
  
  // Fetch token prices on component mount and periodically
  useEffect(() => {
    const fetchPrices = async () => {
      try {
        setPricesLoading(true);
        const symbols = WALLET_ASSETS.map(asset => asset.symbol);
        const prices = await getTokenPricesWithFallback(symbols);
        setTokenPrices(prices);
      } catch (error) {
        console.error('Error fetching token prices:', error);
      } finally {
        setPricesLoading(false);
      }
    };

    // Fetch prices immediately
    fetchPrices();

    // Set up interval to fetch prices every 2 minutes
    const priceInterval = setInterval(fetchPrices, 2 * 60 * 1000);

    return () => clearInterval(priceInterval);
  }, []);
  
  // Create contract read hooks for each wallet asset
  const assetBalanceHooks = WALLET_ASSETS.map(asset => {
    const contractAddress = contracts?.[asset.contractKey];
    
    return useReadContract({
      address: contractAddress,
      abi: ERC20_ABI,
      functionName: 'balanceOf',
      args: [ACCOUNT_ADDRESS],
    });
  });
  
  // Process the wallet assets data
  const processedAssets = useMemo(() => {
    if (!contracts) return [];
    
    return WALLET_ASSETS.map((asset, index) => {
      const contractAddress = contracts[asset.contractKey];
      const balanceResult = assetBalanceHooks[index];
      
      if (!contractAddress || balanceResult.isError || balanceResult.data === undefined) {
        return null;
      }
      
      // Format the balance
      const balance = formatUnits(balanceResult.data as bigint, asset.decimals);
      
      // Get real-time price from CoinGecko (with fallback)
      const price = tokenPrices[asset.symbol] || 0;
      const balanceUSD = (parseFloat(balance) * price).toFixed(2);
      
      return {
        symbol: asset.symbol,
        balance,
        price: price.toFixed(2),
        balanceUSD,
        contractAddress,
      };
    }).filter(asset => asset && parseFloat(asset.balance) > 0);
  }, [contracts, assetBalanceHooks, tokenPrices]);
  
  // Track when initial loading is complete
  useEffect(() => {
    if (!hasInitiallyLoaded) {
      // Check if all hooks have completed (either with data or error)
      const allCompleted = assetBalanceHooks.every(hook => 
        hook.data !== undefined || hook.isError
      );
      
      if (allCompleted && contracts && !pricesLoading) {
        setHasInitiallyLoaded(true);
      }
    }
  }, [hasInitiallyLoaded, contracts, pricesLoading]); // Removed assetBalanceHooks from dependencies
  
  // Create a stable reference for loading check
  const isAnyLoading = assetBalanceHooks.some(hook => hook.isLoading);
  const hasErrors = assetBalanceHooks.some(hook => hook.isError);
  
  // Determine loading state
  const isLoading = !hasInitiallyLoaded && (isAnyLoading || pricesLoading);
  
  return (
    <Card className="mb-4">
      <Card.Header className="bg-white border-bottom">
        <h5 className="mb-0">Holdings</h5>
      </Card.Header>
      <ListGroup variant="flush">
        {!isSupported ? (
          <ListGroup.Item className="text-center py-3 text-warning">
            Please connect to a supported network
          </ListGroup.Item>
        ) : isLoading ? (
          <ListGroup.Item className="text-center py-3">
            <Spinner animation="border" size="sm" /> Loading wallet assets...
          </ListGroup.Item>
        ) : hasErrors ? (
          <ListGroup.Item className="text-center py-3 text-danger">
            Error loading wallet data
            <div className="small mt-1">
              Check console for detailed error information
            </div>
          </ListGroup.Item>
        ) : processedAssets.length === 0 ? (
          <ListGroup.Item className="text-center py-3 text-muted">
            No wallet assets found
          </ListGroup.Item>
        ) : (
          processedAssets.map((asset, index) => {
            if (!asset) return null;
            
            return (
              <AssetRow 
                key={`${asset.symbol}-${asset.contractAddress}`}
                symbol={asset.symbol}
                amount={asset.balance}
                value={asset.balanceUSD}
                price={asset.price}
              />
            );
          })
        )}
      </ListGroup>
    </Card>
  );
};

export default WalletAssetsList;