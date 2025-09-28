import { useReadContract, useAccount, useBlockNumber } from 'wagmi';
import { formatUnits } from 'viem';
import { ERC20_ABI, getContractAddress } from '../config/contracts';

/**
 * Hook to fetch ManagementToken total supply, user balance, and calculate token price
 */
export function useManagementToken(portfolioValue: number) {
  const { chainId, address } = useAccount();
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

  // Fetch user's MT token balance
  const { 
    data: userBalanceRaw, 
    isLoading: isLoadingUserBalance, 
    isError: isErrorUserBalance,
    refetch: refetchUserBalance 
  } = useReadContract({
    address: managementTokenAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [address],
    query: {
      enabled: !!managementTokenAddress && !!address,
    }
  });

  // Format total supply (assuming 18 decimals for MT token)
  const totalSupply = totalSupplyRaw ? parseFloat(formatUnits(totalSupplyRaw as bigint, 18)) : 0;
  
  // Format user balance (assuming 18 decimals for MT token)
  const userBalance = userBalanceRaw ? parseFloat(formatUnits(userBalanceRaw as bigint, 18)) : 0;
  
  // Calculate MT token price: Portfolio Value / Total Supply
  const mtTokenPrice = totalSupply > 0 ? portfolioValue / totalSupply : 0;

  // Calculate user's MT holding value in USD
  const userHoldingValue = userBalance * mtTokenPrice;

  return {
    totalSupply,
    userBalance,
    mtTokenPrice,
    userHoldingValue,
    isLoading: isLoadingTotalSupply || isLoadingUserBalance,
    isError: isErrorTotalSupply || isErrorUserBalance,
    refetchTotalSupply,
    refetchUserBalance,
    managementTokenAddress,
    blockNumber // For debugging/tracking
  };
}
