import { useAccount } from 'wagmi';
import { getContractAddress } from '../config/contracts';
import { sepolia } from 'wagmi/chains';

/**
 * Hook to check if faucet is available and provide contract info
 */
export function useFaucet() {
  const { chainId } = useAccount();
  
  const faucetAddress = getContractAddress(chainId, 'Faucet');
  const usdcAddress = getContractAddress(chainId, 'USDC');
  
  // Faucet is only available on Sepolia
  const isFaucetAvailable = chainId === sepolia.id && !!faucetAddress && !!usdcAddress;

  return {
    faucetAddress,
    usdcAddress,
    isFaucetAvailable,
  };
}
