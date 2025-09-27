import { useReadContract, useAccount } from 'wagmi';
import { ERC20_ABI, getContractAddress } from '../config/contracts';
import { MESSAGE_PRICE_USDC } from '../utils/messageManager';

/**
 * Hook to check USDC approval status for MessageManager contract
 */
export function useUSDCApproval() {
  const { address: userAddress, chainId } = useAccount();
  
  const usdcAddress = getContractAddress(chainId, 'USDC');
  const messageManagerAddress = getContractAddress(chainId, 'MessageManager');

  // Check current USDC allowance for MessageManager
  const { 
    data: allowance, 
    isLoading: isLoadingAllowance, 
    isError: isErrorAllowance,
    refetch: refetchAllowance 
  } = useReadContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [userAddress!, messageManagerAddress!],
    query: {
      enabled: !!userAddress && !!usdcAddress && !!messageManagerAddress,
    }
  });

  // Check user's USDC balance
  const { 
    data: balance, 
    isLoading: isLoadingBalance, 
    isError: isErrorBalance,
    refetch: refetchBalance 
  } = useReadContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [userAddress!],
    query: {
      enabled: !!userAddress && !!usdcAddress,
    }
  });

  const hasApproval = allowance ? BigInt(allowance as string) >= BigInt(MESSAGE_PRICE_USDC) : false;
  const hasSufficientBalance = balance ? BigInt(balance as string) >= BigInt(MESSAGE_PRICE_USDC) : false;
  
  const isLoading = isLoadingAllowance || isLoadingBalance;
  const isError = isErrorAllowance || isErrorBalance;

  return {
    allowance,
    balance,
    hasApproval,
    hasSufficientBalance,
    isLoading,
    isError,
    refetchAllowance,
    refetchBalance,
    usdcAddress,
    messageManagerAddress,
  };
}