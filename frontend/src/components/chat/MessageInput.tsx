import React, { useState, useEffect } from 'react';
import { Form, Button, Card, Spinner, Toast, ToastContainer } from 'react-bootstrap';
import { useAccount, useWriteContract } from 'wagmi';
import { useUSDCApproval } from '../../hooks/useUSDCApproval';
import { ERC20_ABI, MESSAGE_MANAGER_ABI, getContractAddress } from '../../config/contracts';
import { MESSAGE_PRICE_USDC } from '../../utils/messageManager';

interface MessageInputProps {
  input: string;
  setInput: (value: string) => void;
  handleKeyDown: (e: React.KeyboardEvent<HTMLTextAreaElement>) => void;
  sendMessage: () => void;
  connectionStatus: 'connected' | 'connecting' | 'disconnected';
  isThinking: boolean;
}

function MessageInput({ 
  input, 
  setInput, 
  handleKeyDown, 
  sendMessage, 
  connectionStatus, 
  isThinking 
}: MessageInputProps) {
  const { address: userAddress, chainId } = useAccount();
  const [showToast, setShowToast] = useState(false);
  const [toastMessage, setToastMessage] = useState('');
  const [toastVariant, setToastVariant] = useState<'success' | 'danger'>('success');
  
  // Get USDC approval status
  const { 
    hasApproval, 
    hasSufficientBalance, 
    isLoading: isLoadingApproval,
    usdcAddress,
    messageManagerAddress,
    refetchAllowance 
  } = useUSDCApproval();

  // Contract write hooks
  const { 
    writeContract: writeApproval, 
    isPending: isApprovalPending,
    isSuccess: isApprovalSuccess,
    isError: isApprovalError,
    error: approvalError
  } = useWriteContract();
  
  const { 
    writeContract: writePayMessage, 
    isPending: isPayMessagePending,
    isSuccess: isPayMessageSuccess,
    isError: isPayMessageError,
    error: payMessageError
  } = useWriteContract();

  // Handle success and error states
  useEffect(() => {
    if (isApprovalSuccess) {
      setToastMessage('USDC approval successful!');
      setToastVariant('success');
      setShowToast(true);
      // Refetch allowance to update button state
      refetchAllowance();
    }
  }, [isApprovalSuccess, refetchAllowance]);

  useEffect(() => {
    if (isApprovalError) {
      setToastMessage(`Approval failed: ${approvalError?.message || 'Unknown error'}`);
      setToastVariant('danger');
      setShowToast(true);
    }
  }, [isApprovalError, approvalError]);

  useEffect(() => {
    if (isPayMessageSuccess) {
      setToastMessage('Payment successful! Message sent.');
      setToastVariant('success');
      setShowToast(true);
      // Send message through original flow after successful payment
      sendMessage();
    }
  }, [isPayMessageSuccess, sendMessage]);

  useEffect(() => {
    if (isPayMessageError) {
      setToastMessage(`Payment failed: ${payMessageError?.message || 'Unknown error'}`);
      setToastVariant('danger');
      setShowToast(true);
    }
  }, [isPayMessageError, payMessageError]);

  // Check if we can show the integrated send button
  const canShowIntegratedButton = userAddress && usdcAddress && messageManagerAddress && chainId;
  const isAnyPending = isApprovalPending || isPayMessagePending;

  const handleApproveUSDC = async () => {
    if (!usdcAddress || !messageManagerAddress) return;
    
    try {
      await writeApproval({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [messageManagerAddress, BigInt(MESSAGE_PRICE_USDC)], // Only approve 10 USDC
      });
    } catch (error) {
      console.error('Approval failed:', error);
    }
  };

  const handlePayForMessage = async () => {
    if (!userAddress || !chainId || !messageManagerAddress || !input.trim()) return;

    try {
      // Call the simplified contract function
      await writePayMessage({
        address: messageManagerAddress,
        abi: MESSAGE_MANAGER_ABI,
        functionName: 'payForMessage',
        args: [input.trim()], // Just pass the message string directly
      });
      
      // Success/error handling is done in useEffect hooks above
    } catch (error) {
      console.error('Pay for message failed:', error);
    }
  };

  const getButtonContent = () => {
    if (!canShowIntegratedButton) {
      return { text: 'Send', action: sendMessage, variant: 'success' as const };
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
        <div className={`connection-status ${connectionStatus}`}>
          {connectionStatus.charAt(0).toUpperCase() + connectionStatus.slice(1)}
          {canShowIntegratedButton && hasApproval && (
            <span className="text-muted ms-2">(10 USDC per message)</span>
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
          delay={5000} 
          autohide
          bg={toastVariant}
        >
          <Toast.Header closeButton={false}>
            <strong className="me-auto text-white">
              {toastVariant === 'success' ? 'Success' : 'Error'}
            </strong>
          </Toast.Header>
          <Toast.Body className="text-white">
            {toastMessage}
          </Toast.Body>
        </Toast>
      </ToastContainer>
    </Card.Footer>
  );
}

export default MessageInput;