import React, { useState } from 'react';
import { Form, Button, Card, Spinner } from 'react-bootstrap';
import { useAccount, useWriteContract, useSignTypedData } from 'wagmi';
import { useUSDCApproval } from '../../hooks/useUSDCApproval';
import { ERC20_ABI, MESSAGE_MANAGER_ABI, getContractAddress } from '../../config/contracts';
import { 
  createMessageStruct, 
  buildMessageManagerTypedData, 
  MESSAGE_PRICE_USDC 
} from '../../utils/messageManager';

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
  const [isProcessingTx, setIsProcessingTx] = useState(false);
  
  // Get USDC approval status
  const { 
    hasApproval, 
    hasSufficientBalance, 
    isLoading: isLoadingApproval,
    usdcAddress,
    messageManagerAddress 
  } = useUSDCApproval();

  // Contract write hooks
  const { writeContract: writeApproval, isPending: isApprovalPending } = useWriteContract();
  const { writeContract: writePayMessage, isPending: isPayMessagePending } = useWriteContract();
  const { signTypedData, isPending: isSignaturePending } = useSignTypedData();

  // Check if we can show the integrated send button
  const canShowIntegratedButton = userAddress && usdcAddress && messageManagerAddress && chainId;
  const isAnyPending = isApprovalPending || isPayMessagePending || isSignaturePending || isProcessingTx;

  const handleApproveUSDC = async () => {
    if (!usdcAddress || !messageManagerAddress) return;
    
    setIsProcessingTx(true);
    try {
      await writeApproval({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [messageManagerAddress, BigInt(MESSAGE_PRICE_USDC) * 1000n], // Approve for many messages
      });
    } catch (error) {
      console.error('Approval failed:', error);
    } finally {
      setIsProcessingTx(false);
    }
  };

  const handlePayAndSignMessage = async () => {
    if (!userAddress || !chainId || !messageManagerAddress || !input.trim()) return;

    setIsProcessingTx(true);
    try {
      // Create message struct
      const messageStruct = createMessageStruct(input, userAddress);
      
      // Build EIP-712 typed data
      const typedData = buildMessageManagerTypedData(messageStruct, chainId, messageManagerAddress);

      // Sign the message
      const signature = await signTypedData(typedData);

      // Call the contract
      await writePayMessage({
        address: messageManagerAddress,
        abi: MESSAGE_MANAGER_ABI,
        functionName: 'payForMessageWithSig',
        args: [messageStruct, signature, input], // messageURI is the original input
      });

      // If successful, also send the message through the original flow
      sendMessage();
    } catch (error) {
      console.error('Pay and sign failed:', error);
    } finally {
      setIsProcessingTx(false);
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
      text: isAnyPending ? <><Spinner size="sm" /> Processing...</> : 'Pay and Sign Message', 
      action: handlePayAndSignMessage, 
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
    </Card.Footer>
  );
}

export default MessageInput; 