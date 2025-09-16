import React, { useEffect, useState, useRef, useMemo } from 'react';
import { Card, ListGroup, Spinner } from 'react-bootstrap';
import { useReadContract, useBlockNumber, useAccount } from 'wagmi';
import { formatUnits } from 'viem';
import { 
  ACCOUNT_ADDRESS,
  COMET_ABI, 
  getContractAddress, 
  getNetworkName, 
  isSupportedChain 
} from '../../config/contracts';

const BorrowList: React.FC = () => {
  const { chainId } = useAccount();
  const { data: blockNumber } = useBlockNumber({ watch: true });
  const prevBlockNumberRef = useRef<bigint | undefined>();
  
  // Check if the current chain is supported
  const isSupported = isSupportedChain(chainId);
  const networkName = getNetworkName(chainId);
  
  // Get Comet contract address
  const cometAddress = getContractAddress(chainId, 'Comet');

  // Fetch borrow balance
  const { 
    data: borrowBalanceData, 
    isLoading: isBorrowLoading, 
    isError: isBorrowError,
    error: borrowError,
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

  // ------------------------------
  // Interest Rate Calculation Logic
  // ------------------------------
  
  // Fetch total borrowed base asset
  const { 
    data: totalBorrowData, 
    isError: totalBorrowError,
    refetch: refetchTotalBorrow
  } = useReadContract({
    address: cometAddress,
    abi: COMET_ABI,
    functionName: 'totalBorrow',
  });

  // Fetch total supplied base asset
  const { 
    data: totalSupplyData, 
    isError: totalSupplyError,
    refetch: refetchTotalSupply
  } = useReadContract({
    address: cometAddress,
    abi: COMET_ABI,
    functionName: 'totalSupply',
  });

  // Calculate utilization rate
  const utilization = useMemo(() => {
    if (totalSupplyData && totalBorrowData && (totalSupplyData as bigint) > 0n) {
      return (totalBorrowData as bigint * 10n ** 18n) / (totalSupplyData as bigint);
    }
    return 0n;
  }, [totalBorrowData, totalSupplyData]);

  // Fetch borrow rate based on utilization
  const { 
    data: borrowRateData, 
    isError: borrowRateError,
    refetch: refetchBorrowRate
  } = useReadContract({
    address: cometAddress,
    abi: COMET_ABI,
    functionName: 'getBorrowRate',
    args: [utilization],
  });

  // Track initial rates load
  const [hasRatesLoaded, setHasRatesLoaded] = useState(false);
  useEffect(() => {
    if (borrowRateData !== undefined) {
      setHasRatesLoaded(true);
    }
  }, [borrowRateData]);

  // Format rates to annual percentage rates (APR)
  const SECONDS_PER_YEAR = 31_536_000n; // 365 * 24 * 60 * 60
  const [stableBorrowAPR, setStableBorrowAPR] = useState(
    borrowRateData !== undefined
      ? formatUnits((borrowRateData as bigint) * SECONDS_PER_YEAR, 18)
      : '0'
  );

  useEffect(() => {
    if (borrowRateData !== undefined) {
      setStableBorrowAPR(formatUnits((borrowRateData as bigint) * SECONDS_PER_YEAR, 18));
    }
  }, [borrowRateData]);

  // Format for display (percentage with 2 decimal places)
  const formattedBorrowAPR = stableBorrowAPR ? `${(parseFloat(stableBorrowAPR) * 100).toFixed(2)}%` : 'N/A';

  // ------------------------------
  // Refetch data when block number changes
  // ------------------------------
  useEffect(() => {
    if (blockNumber && blockNumber !== prevBlockNumberRef.current) {
      refetchBorrowBalance();
      refetchTotalBorrow();
      refetchTotalSupply();
      refetchBorrowRate();
      prevBlockNumberRef.current = blockNumber;
    }
  }, [blockNumber, refetchBorrowBalance, refetchTotalBorrow, refetchTotalSupply, refetchBorrowRate]);

  // Refetch rates when utilization changes
  useEffect(() => {
    refetchBorrowRate();
  }, [utilization, refetchBorrowRate]);

  // Format the borrow balance
  const borrowBalance = borrowBalanceData !== undefined ? formatUnits(borrowBalanceData as bigint, 6) : '0';

  // Calculate weekly interest based on actual borrowAPR - use 6 decimal places
  const borrowAPRValue = parseFloat(stableBorrowAPR);
  const weeklyInterest = (parseFloat(borrowBalance) * borrowAPRValue / 52).toFixed(6);

  // Determine final loading state
  const isLoading = (!hasBorrowLoaded && isBorrowLoading) || (!hasRatesLoaded && borrowRateData === undefined);

  // Determine error state
  const isError = isBorrowError || totalBorrowError || totalSupplyError || borrowRateError;

  // Format the balance for display
  const formattedBalance = parseFloat(borrowBalance).toFixed(6);
  const dollarValue = parseFloat(borrowBalance).toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD'
  });

  return (
    <Card className="mb-4">
      <Card.Header className="bg-white border-bottom">
        <h5 className="mb-0">Borrowed</h5>
      </Card.Header>
      <ListGroup variant="flush">
        {!isSupported ? (
          <ListGroup.Item className="text-center py-3 text-warning">
            Please connect to a supported network
          </ListGroup.Item>
        ) : isLoading ? (
          <ListGroup.Item className="text-center py-3">
            <Spinner animation="border" size="sm" /> Loading borrowing...
          </ListGroup.Item>
        ) : isError ? (
          <ListGroup.Item className="text-center py-3 text-danger">
            Error loading borrowing data
            <div className="small mt-1">
              Check console for detailed error information
            </div>
          </ListGroup.Item>
        ) : parseFloat(borrowBalance) > 0 ? (
          <ListGroup.Item className="d-flex justify-content-between align-items-center">
            <div className="d-flex align-items-center">
              <div>
                <div>USDC</div>
                <div className="text-muted small">{formattedBorrowAPR} APR</div>
              </div>
            </div>
            <div className="text-end">
              <div className="text-muted small">{formattedBalance} USDC</div>
              <div>{dollarValue}</div>
              <div className="text-danger small">-${weeklyInterest}/week</div>
            </div>
          </ListGroup.Item>
        ) : (
          <ListGroup.Item className="text-center py-3 text-muted">
            No outstanding borrowing.
          </ListGroup.Item>
        )}
      </ListGroup>
    </Card>
  );
};

export default BorrowList; 