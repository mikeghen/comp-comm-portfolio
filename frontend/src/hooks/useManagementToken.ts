import { useReadContract, useAccount, useBlockNumber } from 'wagmi';
import { formatUnits } from 'viem';
import { ERC20_ABI, getContractAddress } from '../config/contracts';

/**
 * Hook to fetch ManagementToken total supply and calculate token price
 */
export function useManagementToken(portfolioValue: number) {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  
  const managementTokenAddress = getContractAddress(chainId, 'ManagementToken');

  // Fetch total supply of ManagementToken
  const { 
    data: totalSupplyRaw, 
    isLoading: isLoadingTotalSupply, 
    isError: isErrorTotalSupply,
    refetch: refetchTotalSupply 
  } = useReadContract({
    address: managementTokenAddress,
    abi: ERC20_ABI,
    functionName: 'totalSupply',
    query: {
      enabled: !!managementTokenAddress,
    }
  });

  // Format total supply (assuming 18 decimals for MT token)
  const totalSupply = totalSupplyRaw ? parseFloat(formatUnits(totalSupplyRaw as bigint, 18)) : 0;
  
  // Calculate MT token price: Portfolio Value / Total Supply
  const mtTokenPrice = totalSupply > 0 ? portfolioValue / totalSupply : 0;

  return {
    totalSupply,
    mtTokenPrice,
    isLoading: isLoadingTotalSupply,
    isError: isErrorTotalSupply,
    refetchTotalSupply,
    managementTokenAddress,
    blockNumber // For debugging/tracking
  };
}
