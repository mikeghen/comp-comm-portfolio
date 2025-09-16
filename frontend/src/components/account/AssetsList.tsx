import React, { useEffect, useState, useMemo, useRef } from 'react';
import { Card, ListGroup, Spinner } from 'react-bootstrap';
import AssetRow from './AssetRow';
import { useReadContract, useBlockNumber, useAccount } from 'wagmi';
import { formatUnits } from 'viem';
import { 
  ACCOUNT_ADDRESS,
  COMET_ABI, 
  getContractAddress, 
  getNetworkName, 
  isSupportedChain 
} from '../../config/contracts';

// Define a type for asset info
type AssetInfo = {
  asset: `0x${string}`;
  priceFeed: `0x${string}`;
  scale: bigint;
  borrowCollateralFactor: bigint;
  liquidateCollateralFactor: bigint;
  liquidationFactor: bigint;
  supplyCap: bigint;
};

// Define a type for userCollateral return value
type UserCollateral = [bigint, bigint]; // [balance, lastUpdatedTimestamp]

const AssetsList: React.FC = () => {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  const prevBlockNumberRef = useRef<bigint | undefined>();
  
  // Check if the current chain is supported
  const isSupported = isSupportedChain(chainId);
  
  // Get Comet contract address
  const cometAddress = getContractAddress(chainId, 'Comet');
  
  // Fetch the number of collateral assets
  const { 
    data: numAssetsData, 
    isError: numAssetsError,
    refetch: refetchNumAssets
  } = useReadContract({
    address: cometAddress,
    abi: COMET_ABI,
    functionName: 'numAssets',
  });
  
  // Convert to number for iteration
  const numAssets = numAssetsData ? Number(numAssetsData) : 0;
  
  // Create an array of indices to map over
  const assetIndices = useMemo(() => {
    if (numAssets > 0) {
      return Array.from({ length: numAssets }, (_, i) => i);
    }
    return [];
  }, [numAssets]);
  
  // Refetch data when block number changes
  useEffect(() => {
    if (blockNumber && blockNumber !== prevBlockNumberRef.current) {
      refetchNumAssets();
      prevBlockNumberRef.current = blockNumber;
    }
  }, [blockNumber, refetchNumAssets]);
  
  // Initialize arrays to hold our contract calls
  const MAX_ASSETS = 10; // Reasonable maximum number of collateral assets
  const assetInfoResults: Array<ReturnType<typeof useReadContract> & { index: number; refetch: () => void }> = [];
  const assetBalanceResults: Array<ReturnType<typeof useReadContract> & { refetch: () => void }> = [];
  const assetSymbolResults: Array<ReturnType<typeof useReadContract> & { refetch: () => void }> = [];
  const cometPriceResults: Array<ReturnType<typeof useReadContract> & { refetch: () => void }> = [];
  
  // Define hooks for each potential asset (up to MAX_ASSETS)
  for (let i = 0; i < MAX_ASSETS; i++) {
    // Only enable the contract call if this index exists in our asset indices
    const enabled = i < assetIndices.length;
    
    // Asset info
    const assetInfoResult = useReadContract({
      address: enabled ? cometAddress : undefined,
      abi: COMET_ABI,
      functionName: 'getAssetInfo',
      args: [i],
    });
    assetInfoResults.push({ ...assetInfoResult, index: i, refetch: assetInfoResult.refetch });
    
    // Get asset data from the result
    const assetInfo = assetInfoResult.data as AssetInfo | undefined;
    
    // Asset balance - only enabled if we have asset info
    const assetBalanceResult = useReadContract({
      address: cometAddress,
      abi: COMET_ABI,
      functionName: 'userCollateral',
      args: [ACCOUNT_ADDRESS, assetInfo?.asset],
    });
    assetBalanceResults.push({ ...assetBalanceResult, refetch: assetBalanceResult.refetch });
    
    // Asset symbol - only enabled if we have asset info
    const assetSymbolResult = useReadContract({
      address: assetInfo?.asset,
      abi: [
        {
          name: 'symbol',
          type: 'function',
          stateMutability: 'view',
          inputs: [],
          outputs: [{ name: '', type: 'string' }],
        },
      ],
      functionName: 'symbol',
    });
    assetSymbolResults.push({ ...assetSymbolResult, refetch: assetSymbolResult.refetch });
    
    // Add Comet's getPrice call using the price feed address
    const cometPriceResult = useReadContract({
      address: cometAddress,
      abi: COMET_ABI,
      functionName: 'getPrice',
      args: [assetInfo?.priceFeed],
    });
    cometPriceResults.push({ ...cometPriceResult, refetch: cometPriceResult.refetch });
  }
  
  // Refetch all asset data when block number changes
  useEffect(() => {
    if (blockNumber && blockNumber !== prevBlockNumberRef.current && assetIndices.length > 0) {      
      // Refetch all asset data
      assetIndices.forEach(i => {
        if (i < assetInfoResults.length) {
          assetInfoResults[i].refetch();
          assetBalanceResults[i].refetch();
          assetSymbolResults[i].refetch();
          cometPriceResults[i].refetch();
        }
      });
      
      prevBlockNumberRef.current = blockNumber;
    }
  }, [blockNumber, assetIndices, assetInfoResults, assetBalanceResults, assetSymbolResults, cometPriceResults]);

  
  // Process all the data into a usable format
  const [stableCollateralAssets, setStableCollateralAssets] = useState<any[]>([]);
  
  const processedCollateralAssets = useMemo(() => {
    // Only process the indices that exist in our list
    return assetIndices.map(i => {
      const assetInfoResult = assetInfoResults[i];
      
      // Skip if we don't have valid data
      if (assetInfoResult.isError || !assetInfoResult.data) return null;
      
      const info = assetInfoResult.data as AssetInfo;
      const balance = assetBalanceResults[i]?.data as UserCollateral || [0n, 0n];
      const symbol = assetSymbolResults[i]?.data || 'UNKNOWN';
      const cometPrice = cometPriceResults[i]?.data || 0n;
      
      // Calculate decimals from scale (10^decimals = scale)
      const scale = Number(info.scale || 1n);
      const decimals = Math.log10(scale) || 18; // Default to 18 if calculation fails
      
      // Format the balance with proper decimals
      const formattedBalance = formatUnits(balance[0] || 0n, decimals);
      
      // Format price - scaled by 10^8 for price feeds
      const formattedCometPrice = formatUnits(cometPrice as bigint || 0n, 8);
      
      // Calculate USD value using Comet's price
      const valueInUSD = Number(formattedBalance) * Number(formattedCometPrice);
      
      return {
        index: i,
        symbol,
        assetAddress: info.asset,
        priceFeed: info.priceFeed,
        balance: formattedBalance,
        price: formattedCometPrice,
        balanceUSD: valueInUSD.toFixed(2),
        borrowCollateralFactor: formatUnits(info.borrowCollateralFactor || 0n, 18),
        liquidateCollateralFactor: formatUnits(info.liquidateCollateralFactor || 0n, 18),
        liquidationFactor: formatUnits(info.liquidationFactor || 0n, 18),
        supplyCap: info.supplyCap ? formatUnits(info.supplyCap, decimals) : 'No cap',
      };
    }).filter(asset => asset && parseFloat(asset.balance) > 0); // Remove null entries and zero balances
  }, [assetIndices, assetInfoResults, assetBalanceResults, assetSymbolResults, cometPriceResults, blockNumber]);

  // Update stable assets when processed assets change and are valid
  useEffect(() => {
    if (processedCollateralAssets.length > 0) {
      // Create a map of existing assets by index for quick lookup
      const existingAssetsMap = stableCollateralAssets.reduce((acc: Record<number, any>, asset) => {
        acc[asset.index] = asset;
        return acc;
      }, {});

      // Update stable assets, keeping previous values if new ones are invalid
      const updatedAssets = processedCollateralAssets.map(asset => {
        // Skip null assets
        if (!asset) return null;
        
        const existingAsset = existingAssetsMap[asset.index];
        
        // If we have an existing asset, use its values as fallbacks
        if (existingAsset) {
          return {
            ...asset,
            // Ensure numeric values don't become NaN during updates
            balance: !isNaN(parseFloat(asset.balance)) ? asset.balance : existingAsset.balance,
            price: !isNaN(parseFloat(asset.price)) ? asset.price : existingAsset.price,
            balanceUSD: !isNaN(parseFloat(asset.balanceUSD)) ? asset.balanceUSD : existingAsset.balanceUSD,
          };
        }
        
        return asset;
      }).filter(Boolean); // Remove any null values

      // Force update even if assets look the same - important for block number changes
      setStableCollateralAssets([...updatedAssets]);
    }
  }, [processedCollateralAssets, blockNumber]);

  // Add a specific effect just for balance updates
  useEffect(() => {
    if (blockNumber && prevBlockNumberRef.current !== blockNumber && assetIndices.length > 0) {      
      assetIndices.forEach(i => {
        if (i < assetBalanceResults.length) {
          assetBalanceResults[i].refetch();
        }
      });
    }
  }, [blockNumber, assetIndices, assetBalanceResults]);

  // Determine loading and error states
  const initialLoadDone = numAssetsData !== undefined &&
    assetIndices.every(i => assetInfoResults[i]?.data !== undefined && cometPriceResults[i]?.data !== undefined);
  const [hasCollateralLoaded, setHasCollateralLoaded] = useState(false);
  useEffect(() => {
    if (initialLoadDone) {
      setHasCollateralLoaded(true);
    }
  }, [initialLoadDone]);
  const isLoading = !hasCollateralLoaded;

  const isError = numAssetsError || 
                  assetIndices.some(i => assetInfoResults[i]?.isError) ||
                  assetIndices.some(i => cometPriceResults[i]?.isError);
  const error = isError ? 'Error fetching collateral assets' : false;

  // Provide collateral assets
  const collateralAssets = hasCollateralLoaded ? stableCollateralAssets : [];

  return (
    <Card className="mb-4">
      <Card.Header className="bg-white border-bottom">
        <h5 className="mb-0">Compound Assets</h5>
      </Card.Header>
      <ListGroup variant="flush">
        {!isSupported ? (
          <ListGroup.Item className="text-center py-3 text-warning">
            Please connect to a supported network
          </ListGroup.Item>
        ) : isLoading ? (
          <ListGroup.Item className="text-center py-3">
            <Spinner animation="border" size="sm" /> Loading collateral assets...
          </ListGroup.Item>
        ) : error ? (
          <ListGroup.Item className="text-center py-3 text-danger">
            Error loading collateral data
            <div className="small mt-1">
              Check console for detailed error information
            </div>
          </ListGroup.Item>
        ) : collateralAssets.length === 0 ? (
          <ListGroup.Item className="text-center py-3 text-muted">
            No compound assets supplied
          </ListGroup.Item>
        ) : (
          collateralAssets.map((asset) => {
            if (!asset) return null;
            
            return (
              <AssetRow 
                key={asset.index}
                symbol={asset.symbol}
                amount={asset.balance}
                value={asset.balanceUSD}
                price={asset.price}
                borrowCollateralFactor={asset.borrowCollateralFactor}
                liquidateCollateralFactor={asset.liquidateCollateralFactor}
              />
            );
          })
        )}
      </ListGroup>
    </Card>
  );
};

export default AssetsList; 