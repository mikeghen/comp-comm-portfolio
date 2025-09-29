import { useReadContract, useAccount, useBlockNumber } from 'wagmi';
import { getContractAddress, POLICY_MANAGER_ABI } from '../config/contracts';

export const usePolicyData = () => {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  
  const policyManagerAddress = getContractAddress(chainId, 'PolicyManager');

  // Get the current policy text and version
  const { 
    data: promptData, 
    isLoading: promptLoading, 
    isError: promptError 
  } = useReadContract({
    address: policyManagerAddress,
    abi: POLICY_MANAGER_ABI,
    functionName: 'getPrompt',
    query: {
      enabled: !!policyManagerAddress,
      refetchOnMount: false,
      refetchOnWindowFocus: false,
    },
  });

  // Get the maximum policy size constant
  const { 
    data: maxPolicySize, 
    isLoading: maxSizeLoading, 
    isError: maxSizeError 
  } = useReadContract({
    address: policyManagerAddress,
    abi: POLICY_MANAGER_ABI,
    functionName: 'MAX_POLICY_SIZE',
    query: {
      enabled: !!policyManagerAddress,
      refetchOnMount: false,
      refetchOnWindowFocus: false,
    },
  });

  // Extract prompt text and version from the returned tuple
  const promptData_typed = promptData as [string, bigint] | undefined;
  const promptText = promptData_typed?.[0] || '';
  const promptVersion = promptData_typed?.[1] || 0n;

  return {
    promptText,
    promptVersion: Number(promptVersion),
    maxPolicySize: Number(maxPolicySize || 0n),
    isLoading: promptLoading || maxSizeLoading,
    isError: promptError || maxSizeError,
    isConnected: !!policyManagerAddress,
  };
};