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

// Define the wallet assets based on the allow list from the issue
const WALLET_ASSETS = [
  { symbol: 'USDC', contractKey: 'USDC' as const, decimals: 6 },
  { symbol: 'WETH', contractKey: 'WETH' as const, decimals: 18 },
  { symbol: 'cbETH', contractKey: 'cbETH' as const, decimals: 18 },
  { symbol: 'cbBTC', contractKey: 'cbBTC' as const, decimals: 8 },
  { symbol: 'WSTETH', contractKey: 'WSTETH' as const, decimals: 18 },
];

const WalletAssetsList: React.FC = () => {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  
  // Check if the current chain is supported
  const isSupported = isSupportedChain(chainId);
  
  // Get contract addresses for the current chain
  const contracts = getContractsByChainId(chainId);
  
  // State to track loading
  const [hasLoaded, setHasLoaded] = useState(false);
  const [walletAssets, setWalletAssets] = useState<any[]>([]);
  
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
      
      // For wallet assets, we'll use a mock price of $1 for USDC and market prices for others
      // In a real implementation, you'd fetch these from a price oracle
      const mockPrices: Record<string, number> = {
        'USDC': 1.00,
        'WETH': 3500.00,
        'cbETH': 3450.00,
        'cbBTC': 95000.00,
        'WSTETH': 4100.00,
      };
      
      const price = mockPrices[asset.symbol] || 0;
      const balanceUSD = (parseFloat(balance) * price).toFixed(2);
      
      return {
        symbol: asset.symbol,
        balance,
        price: price.toFixed(2),
        balanceUSD,
        contractAddress,
      };
    }).filter(Boolean);
  }, [contracts, assetBalanceHooks, blockNumber]);
  
  // Update wallet assets when processed assets change
  useEffect(() => {
    if (processedAssets.length > 0) {
      setWalletAssets(processedAssets);
      setHasLoaded(true);
    } else if (contracts && assetBalanceHooks.every(hook => hook.data !== undefined || hook.isError)) {
      // All hooks have completed (either with data or error), and we have no valid assets
      setHasLoaded(true);
    }
  }, [processedAssets, contracts, assetBalanceHooks]);
  
  // Determine loading and error states
  const isLoading = !hasLoaded && assetBalanceHooks.some(hook => hook.isLoading);
  const hasErrors = assetBalanceHooks.some(hook => hook.isError);
  
  return (
    <Card className="mb-4">
      <Card.Header className="bg-white border-bottom">
        <h5 className="mb-0">Wallet</h5>
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
        ) : walletAssets.length === 0 ? (
          <ListGroup.Item className="text-center py-3 text-muted">
            No wallet assets found
          </ListGroup.Item>
        ) : (
          walletAssets.map((asset, index) => {
            if (!asset) return null;
            
            return (
              <AssetRow 
                key={`${asset.symbol}-${index}`}
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