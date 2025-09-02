import React, { useMemo, useState, useEffect, useRef } from 'react';
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

function AccountOverview() {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  const prevBlockNumberRef = useRef<bigint | undefined>();
  
  // Check if the current chain is supported
  const isSupported = isSupportedChain(chainId);

  // Get Comet contract address
  const cometAddress = getContractAddress(chainId, 'Comet');

  // ------------------------------
  // Borrow Balance Section
  // ------------------------------
  
  // Fetch borrow balance
  const { 
    data: borrowBalanceData, 
    isLoading: isBorrowLoading, 
    isError: isBorrowError,
    refetch: refetchBorrowBalance
  } = useReadContract({
    address: cometAddress,
    abi: COMET_ABI,
    functionName: 'borrowBalanceOf',
    args: [ACCOUNT_ADDRESS],
  });

  // Track initial load state
  const [hasBorrowLoaded, setHasBorrowLoaded] = useState(false);
  useEffect(() => {
    if (borrowBalanceData !== undefined) {
      setHasBorrowLoaded(true);
    }
  }, [borrowBalanceData]);

  // Format the borrow balance
  const borrowBalance = borrowBalanceData !== undefined ? formatUnits(borrowBalanceData as bigint, 6) : '0';
  
  // ------------------------------
  // Collateral Assets Section
  // ------------------------------
  
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
  
  // Initialize arrays to hold our contract calls
  const MAX_ASSETS = 10; // Reasonable maximum number of collateral assets
  const assetInfoResults: Array<ReturnType<typeof useReadContract> & { index: number; refetch: () => void }> = [];
  const assetBalanceResults: Array<ReturnType<typeof useReadContract> & { refetch: () => void }> = [];
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
    
    // Asset balance
    const assetBalanceResult = useReadContract({
      address: cometAddress,
      abi: COMET_ABI,
      functionName: 'userCollateral',
      args: [ACCOUNT_ADDRESS, assetInfo?.asset],
    });
    assetBalanceResults.push({ ...assetBalanceResult, refetch: assetBalanceResult.refetch });
    
    // Comet price
    const cometPriceResult = useReadContract({
      address: cometAddress,
      abi: COMET_ABI,
      functionName: 'getPrice',
      args: [assetInfo?.priceFeed],
    });
    cometPriceResults.push({ ...cometPriceResult, refetch: cometPriceResult.refetch });
  }

  // Refetch data when block number changes
  useEffect(() => {
    if (blockNumber && blockNumber !== prevBlockNumberRef.current) {
      console.log(`Block number changed to ${blockNumber}, refetching data`);
      refetchBorrowBalance();
      refetchNumAssets();
      
      // Refetch all asset data
      assetIndices.forEach(i => {
        if (i < assetInfoResults.length) {
          assetInfoResults[i].refetch();
          assetBalanceResults[i].refetch();
          cometPriceResults[i].refetch();
        }
      });
      
      prevBlockNumberRef.current = blockNumber;
    }
  }, [blockNumber, refetchBorrowBalance, refetchNumAssets, assetIndices, assetInfoResults, assetBalanceResults, cometPriceResults]);

  // Process collateral assets data
  const collateralAssets = useMemo(() => {
    return assetIndices.map(i => {
      const assetInfoResult = assetInfoResults[i];
      
      // Skip if we don't have valid data
      if (assetInfoResult.isError || !assetInfoResult.data) return null;
      
      const info = assetInfoResult.data as AssetInfo;
      const balance = assetBalanceResults[i]?.data as UserCollateral || [0n, 0n];
      const cometPrice = cometPriceResults[i]?.data || 0n;
      
      // Calculate decimals from scale (10^decimals = scale)
      const scale = Number(info.scale || 1n);
      const decimals = Math.log10(scale) || 18; // Default to 18 if calculation fails
      
      // Format the balance with proper decimals
      const formattedBalance = formatUnits(balance[0] || 0n, decimals);
      
      // Format price - scaled by 10^8 for price feeds
      const formattedPrice = formatUnits(cometPrice as bigint || 0n, 8);
      
      // Calculate USD value using Comet's price
      const valueInUSD = Number(formattedBalance) * Number(formattedPrice);
      
      return {
        balanceUSD: valueInUSD.toFixed(2)
      };
    }).filter(Boolean); // Remove null entries
  }, [assetIndices, assetInfoResults, assetBalanceResults, cometPriceResults]);

  // Determine loading and error states for collateral assets
  const initialLoadDone = numAssetsData !== undefined &&
    assetIndices.every(i => assetInfoResults[i]?.data !== undefined && cometPriceResults[i]?.data !== undefined);
  const [hasCollateralLoaded, setHasCollateralLoaded] = useState(false);
  useEffect(() => {
    if (initialLoadDone) {
      setHasCollateralLoaded(true);
    }
  }, [initialLoadDone]);
  
  // Calculate total values
  const {
    totalCollateralValue,
    totalBorrowedValue,
    netWorth,
    percentChange
  } = useMemo(() => {
    // Convert string collateral values to numbers and sum them up
    const totalCollateral = collateralAssets?.reduce((sum, asset) => {
      const assetValue = parseFloat(asset?.balanceUSD || '0');
      return sum + (isNaN(assetValue) ? 0 : assetValue);
    }, 0) || 0;
    
    // Convert string borrow value to number
    const totalBorrowed = parseFloat(borrowBalance || '0');
    
    // Calculate net worth (collateral - borrowed)
    const net = totalCollateral - totalBorrowed;
    
    // Mock percentage change for now (could be calculated from historical data)
    const percentChangeValue = 3.2;
    
    return {
      totalCollateralValue: totalCollateral,
      totalBorrowedValue: totalBorrowed,
      netWorth: net,
      percentChange: percentChangeValue
    };
  }, [collateralAssets, borrowBalance]);

  // Format values for display
  const formattedNetWorth = netWorth.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD'
  });
  
  const formattedCollateral = totalCollateralValue.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD'
  });
  
  const formattedBorrowed = totalBorrowedValue.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD'
  });

  // Determine final loading and error states
  const isCollateralLoading = !hasCollateralLoaded;
  const isCollateralError = numAssetsError || assetIndices.some(i => assetInfoResults[i]?.isError);
  const isLoading = (!hasBorrowLoaded && isBorrowLoading) || isCollateralLoading;
  const isError = isBorrowError || isCollateralError;

  return (
    <div className="card mb-4">
      <div className="card-header bg-white border-bottom">
        <h5 className="mb-0">Account Overview</h5>
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
            <div className="row mb-3">
              <div className="col">
                <div className="text-muted small">Net Worth</div>
                <div className="h4">
                  {formattedNetWorth}
                </div>
              </div>
            </div>
            <div className="row">
              <div className="col-6 col-md-6">
                <div className="text-muted small">Total Collateral</div>
                <div className="h5 text-success">
                  {formattedCollateral}
                </div>
              </div>
              <div className="col-6 col-md-6">
                <div className="text-muted small">Total Borrowed</div>
                <div className="h5 text-danger">
                  {formattedBorrowed}
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