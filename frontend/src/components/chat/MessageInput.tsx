import React, { useState, useEffect } from 'react';
import { Form, Button, Card, Spinner, Toast, ToastContainer } from 'react-bootstrap';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { useUSDCApproval } from '../../hooks/useUSDCApproval';
import { useFaucet } from '../../hooks/useFaucet';
import { ERC20_ABI, MESSAGE_MANAGER_ABI, FAUCET_ABI, getContractAddress } from '../../config/contracts';
import { MESSAGE_PRICE_USDC } from '../../utils/messageManager';

interface MessageInputProps {
  input: string;
  setInput: (value: string) => void;
  handleKeyDown: (e: React.KeyboardEvent<HTMLTextAreaElement>) => void;
  sendMessage: (options?: { skipClearInput?: boolean; skipUserMessage?: boolean }) => void;
  connectionStatus: 'connected' | 'connecting' | 'disconnected';
  isThinking: boolean;
  addUserMessage: (content: string) => void;
}

function MessageInput({ 
  input, 
  setInput, 
  handleKeyDown, 
  sendMessage, 
  connectionStatus, 
  isThinking,
  addUserMessage 
}: MessageInputProps) {
  const { address: userAddress, chainId } = useAccount();
  const [showToast, setShowToast] = useState(false);
  const [toastMessage, setToastMessage] = useState('');
  const [toastVariant, setToastVariant] = useState<'success' | 'danger'>('success');
  const [payTxHash, setPayTxHash] = useState<`0x${string}` | undefined>(undefined);
  const [approvalTxHash, setApprovalTxHash] = useState<`0x${string}` | undefined>(undefined);
  const [faucetTxHash, setFaucetTxHash] = useState<`0x${string}` | undefined>(undefined);
  
  // Get USDC approval status
  const { 
    hasApproval, 
    hasSufficientBalance, 
    isLoading: isLoadingApproval,
    usdcAddress,
    messageManagerAddress,
    refetchAllowance,
    refetchBalance 
  } = useUSDCApproval();

  // Get faucet status
  const { 
    faucetAddress, 
    usdcAddress: faucetUsdcAddress, 
    isFaucetAvailable 
  } = useFaucet();

  // Contract write hooks
  const { 
    writeContract: writeApproval, 
    isPending: isApprovalPending,
    isSuccess: isApprovalSuccess,
    isError: isApprovalError,
    error: approvalError,
    data: approvalHash
  } = useWriteContract();
  
  const { 
    writeContract: writePayMessage,
    writeContractAsync: writePayMessageAsync,
    isPending: isPayMessagePending,
    isSuccess: isPayMessageSuccess,
    isError: isPayMessageError,
    error: payMessageError
  } = useWriteContract();

  const { 
    writeContract: writeFaucet,
    isPending: isFaucetPending,
    isSuccess: isFaucetSuccess,
    isError: isFaucetError,
    error: faucetError,
    data: faucetHash
  } = useWriteContract();

  // Wait for payForMessage tx confirmation
  const {
    isLoading: isPayTxConfirming,
    isSuccess: isPayTxConfirmed,
  } = useWaitForTransactionReceipt({ hash: payTxHash });

  // Wait for approval tx confirmation
  const {
    isLoading: isApprovalTxConfirming,
    isSuccess: isApprovalTxConfirmed,
  } = useWaitForTransactionReceipt({ hash: approvalTxHash });

  // Wait for faucet tx confirmation
  const {
    isLoading: isFaucetTxConfirming,
    isSuccess: isFaucetTxConfirmed,
  } = useWaitForTransactionReceipt({ hash: faucetTxHash });

  // Handle success and error states
  useEffect(() => {
    if (isApprovalTxConfirmed) {
      setToastMessage('USDC approval confirmed!');
      setToastVariant('success');
      setShowToast(true);
      // Refetch allowance to update button state after confirmation
      refetchAllowance();
      // Reset approval hash
      setApprovalTxHash(undefined);
    }
  }, [isApprovalTxConfirmed, refetchAllowance]);

  useEffect(() => {
    if (isApprovalError) {
      setToastMessage('Approval failed. Please try again.');
      setToastVariant('danger');
      setShowToast(true);
    }
  }, [isApprovalError, approvalError]);

  // Track approval transaction hash when it becomes available
  useEffect(() => {
    if (isApprovalSuccess && approvalHash) {
      setApprovalTxHash(approvalHash as `0x${string}`);
    }
  }, [isApprovalSuccess, approvalHash]);

  useEffect(() => {
    if (isPayTxConfirmed) {
      setToastMessage('Payment successful! The agent is now processing your message.');
      setToastVariant('success');
      setShowToast(true);
      // Now that payment is confirmed, add the thinking message (skip user message since already added)
      sendMessage({ skipClearInput: true, skipUserMessage: true });
      // Refresh allowance so button state stays correct
      refetchAllowance();
      // Reset stored hash
      setPayTxHash(undefined);
    }
  }, [isPayTxConfirmed, sendMessage, refetchAllowance]);

  useEffect(() => {
    if (isPayMessageError) {
      setToastMessage('Payment failed.');
      setToastVariant('danger');
      setShowToast(true);
    }
  }, [isPayMessageError, payMessageError]);

  // Track faucet transaction hash when it becomes available
  useEffect(() => {
    if (isFaucetSuccess && faucetHash) {
      setFaucetTxHash(faucetHash as `0x${string}`);
    }
  }, [isFaucetSuccess, faucetHash]);

  useEffect(() => {
    if (isFaucetTxConfirmed) {
      setToastMessage('USDC received from faucet! You can now send messages.');
      setToastVariant('success');
      setShowToast(true);
      // Refresh balance so button state updates
      refetchBalance();
      // Reset stored hash
      setFaucetTxHash(undefined);
    }
  }, [isFaucetTxConfirmed, refetchBalance]);

  useEffect(() => {
    if (isFaucetError) {
      setToastMessage('Faucet request failed. Please try again.');
      setToastVariant('danger');
      setShowToast(true);
    }
  }, [isFaucetError, faucetError]);

  // Check if we can show the integrated send button
  const canShowIntegratedButton = userAddress && usdcAddress && messageManagerAddress && chainId;
  const isAnyPending = isApprovalPending || isPayMessagePending || isPayTxConfirming || isApprovalTxConfirming;

  const handleApproveUSDC = async () => {
    if (!usdcAddress || !messageManagerAddress) return;
    
    try {
      // Approve a larger amount (100 USDC) so users don't need to approve every message
      const approvalAmount = BigInt(MESSAGE_PRICE_USDC) * BigInt(10); // 10 messages worth
      writeApproval({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [messageManagerAddress, approvalAmount],
      });
    } catch (error) {
      console.error('Approval failed:', error);
    }
  };

  const handlePayForMessage = async () => {
    if (!userAddress || !chainId || !messageManagerAddress || !input.trim()) return;

    // Immediately add user message to chat and clear input
    const messageContent = input.trim();
    addUserMessage(messageContent);
    setInput('');

    try {
      // Call the simplified contract function
      const hash = await writePayMessageAsync({
        address: messageManagerAddress,
        abi: MESSAGE_MANAGER_ABI,
        functionName: 'payForMessage',
        args: [messageContent], // Use the saved message content
      });
      // Track tx hash to await confirmation
      if (hash) setPayTxHash(hash as `0x${string}`);
      
      // Success/error handling is done in useEffect hooks above
    } catch (error) {
      console.error('Pay for message failed:', error);
    }
  };

  const handleFaucetRequest = async () => {
    if (!faucetAddress || !faucetUsdcAddress) return;
    
    try {
      writeFaucet({
        address: faucetAddress,
        abi: FAUCET_ABI,
        functionName: 'drip',
        args: [faucetUsdcAddress],
      });
    } catch (error) {
      console.error('Faucet request failed:', error);
    }
  };

  const getButtonContent = () => {
    if (!canShowIntegratedButton) {
      return { text: 'Send', action: () => sendMessage(), variant: 'success' as const };
    }

    if (isLoadingApproval) {
      return { 
        text: <><Spinner size="sm" /> Checking...</>, 
        action: () => {}, 
        variant: 'secondary' as const,
        disabled: true
      };
    }

    if (!hasSufficientBalance) {
      return { 
        text: 'Insufficient USDC', 
        action: () => {}, 
        variant: 'danger' as const,
        disabled: true
      };
    }

    if (!hasApproval) {
      return { 
        text: isAnyPending ? <><Spinner size="sm" /> Approving...</> : 'Approve', 
        action: handleApproveUSDC, 
        variant: 'warning' as const
      };
    }

    return { 
      text: isAnyPending ? <><Spinner size="sm" /> Processing...</> : 'Pay and Send Message', 
      action: handlePayForMessage, 
      variant: 'success' as const
    };
  };

  const buttonConfig = getButtonContent();
  const isDisabled = connectionStatus !== 'connected' || isThinking || buttonConfig.disabled || isAnyPending;

  return (
    <Card.Footer className="p-3 border-top">
      <Form.Group className="mb-2">
        <Form.Control
          as="textarea"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Type your message here..."
          rows={2}
          disabled={connectionStatus !== 'connected' || isThinking}
        />
      </Form.Group>
      <div className="d-flex justify-content-between align-items-center">
        <div>
          <div className={`connection-status ${connectionStatus}`}>
            {connectionStatus.charAt(0).toUpperCase() + connectionStatus.slice(1)}
            {canShowIntegratedButton && hasApproval && (
              <span className="text-muted ms-2">(1 USDC per message)</span>
            )}
          </div>
          {isFaucetAvailable && (
            <small>
              <button 
                type="button"
                className="btn btn-link p-0 text-decoration-none small"
                onClick={handleFaucetRequest}
                disabled={isFaucetPending || isFaucetTxConfirming}
                style={{ fontSize: '0.75rem' }}
              >
                {isFaucetPending || isFaucetTxConfirming ? (
                  <>
                    <Spinner size="sm" className="me-1" />
                    Getting USDC...
                  </>
                ) : (
                  'Get USDC from Faucet'
                )}
              </button>
            </small>
          )}
        </div>
        <Button 
          variant={buttonConfig.variant}
          onClick={buttonConfig.action} 
          disabled={isDisabled}
        >
          {buttonConfig.text}
        </Button>
      </div>
      
      {/* Toast notifications */}
      <ToastContainer position="top-end" className="p-3">
        <Toast
          show={showToast}
          onClose={() => setShowToast(false)}
          delay={4000}
          autohide
          bg="light"
          className="shadow-sm border"
        >
          <Toast.Body className={toastVariant === 'success' ? 'text-success' : 'text-danger'}>
            {toastMessage}
          </Toast.Body>
        </Toast>
      </ToastContainer>
    </Card.Footer>
  );
}

export default MessageInput;