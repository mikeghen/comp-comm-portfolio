import React, { useState, useEffect, useRef, useMemo } from 'react';
import {
  useAccount,
  useSignMessage,
  useSignTypedData,
  usePublicClient,
  useReadContract,
  useWriteContract,
  useChainId
} from 'wagmi';
import { Container, Row, Col } from 'react-bootstrap';
import 'bootstrap/dist/css/bootstrap.min.css';
import './bootstrap-overrides.css';

// Import components
import Header from './components/layout/Header';
import ChatContainer from './components/chat/ChatContainer';
import AccountContainer from './components/account/AccountContainer';
import { getContractAddress, ERC20_ABI } from './config/contracts';
import MESSAGE_MANAGER_ABI from './config/abi/MessageManager.json';
import {
  MESSAGE_MANAGER_ADDRESS,
  MESSAGE_MANAGER_DOMAIN_NAME,
  MESSAGE_MANAGER_DOMAIN_VERSION,
  MESSAGE_PRICE_USDC,
  MESSAGE_TYPED_DATA,
  MessagePayload
} from './config/messageManager';
import { hashTypedData, keccak256, stringToHex, zeroAddress } from 'viem';

// Define types for messages
interface Message {
  type: 'agent' | 'user' | 'thinking' | 'tool' | 'tool_call' | 'error' | 'signature_pending';
  content: string;
}

const App: React.FC = () => {
  const [messages, setMessages] = useState<Message[]>([
    {
      type: 'agent',
      content: `Welcome to the Compound Community Portfolio! Send a message to make an adjustment to the portfolio.`
    }
  ]);
  const [input, setInput] = useState<string>('');
  const [socket, setSocket] = useState<WebSocket | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'connected' | 'connecting' | 'disconnected'>('disconnected');
  const [isThinking, setIsThinking] = useState<boolean>(false);
  const [isApproving, setIsApproving] = useState<boolean>(false);
  const [isPaying, setIsPaying] = useState<boolean>(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const nonceCounterRef = useRef<number>(0);

  // Use wagmi's useAccount hook to check if wallet is connected
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { signMessageAsync } = useSignMessage();
  const { signTypedDataAsync } = useSignTypedData();
  const publicClient = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const usdcAddress = useMemo(
    () => (chainId ? getContractAddress(chainId, 'USDC') : undefined),
    [chainId]
  );

  const {
    data: allowance,
    refetch: refetchAllowance,
    isLoading: isAllowanceLoading
  } = useReadContract({
    address: usdcAddress ?? zeroAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [address ?? zeroAddress, MESSAGE_MANAGER_ADDRESS],
    query: {
      enabled: Boolean(isConnected && address && usdcAddress)
    }
  });

  const hasApproval = useMemo(() => {
    const allowanceValue = allowance as bigint | undefined;
    if (!allowanceValue) return false;
    try {
      return allowanceValue >= MESSAGE_PRICE_USDC;
    } catch {
      return false;
    }
  }, [allowance]);

  // Connect to WebSocket
  useEffect(() => {
    if (!isConnected) return; // Only connect to WebSocket if wallet is connected
    
    const connectWebSocket = () => {
      setConnectionStatus('connecting');
      
      // Use environment variable if available, otherwise calculate based on current URL
      let wsUrl: string;
      if (import.meta.env.VITE_WS_URL) {
        wsUrl = import.meta.env.VITE_WS_URL;
      } else {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        wsUrl = `${protocol}//${window.location.host}/ws/chat`;
      }
      
      const ws = new WebSocket(wsUrl);
      
      ws.onopen = () => {
        setConnectionStatus('connected');
      };
      
      ws.onmessage = (event: MessageEvent) => {
        const data = JSON.parse(event.data);
        
        if (data.type === 'agent') {
          // Replace thinking message with agent message in a single update
          setMessages(prev => {
            const filteredMessages = prev.filter(msg => msg.type !== 'thinking');
            return [...filteredMessages, { type: 'agent', content: data.content }];
          });
          // Only clear thinking state after updating the messages
          setIsThinking(false);
        } else if (data.type === 'tool') {
          // For tool messages, keep the thinking indicator until we get a final agent response
          setMessages(prev => {
            // Keep thinking message for tool responses
            return [...prev.filter(msg => msg.type !== 'thinking'), 
                   { type: 'tool', content: data.content },
                   { type: 'thinking', content: 'Thinking...' }];
          });
        } else if (data.type === 'tool_call') {
          // Show tool calls similarly to tool responses
          setMessages(prev => {
            const headerText = data.tool ? `Using ${data.tool}:` : 'Using tool:';
            // Keep thinking message for tool calls
            return [...prev.filter(msg => msg.type !== 'thinking'), 
                   { type: 'tool_call', content: `${headerText}\n\n\`\`\`\n${data.content}\n\`\`\`` },
                   { type: 'thinking', content: 'Thinking...' }];
          });
        } else if (data.type === 'error') {
          setMessages(prev => {
            const filteredMessages = prev.filter(msg => msg.type !== 'thinking');
            return [...filteredMessages, { type: 'error', content: data.content }];
          });
          setIsThinking(false);
        }
      };
      
      ws.onclose = () => {
        setConnectionStatus('disconnected');
        setIsThinking(false);
        
        // Try to reconnect after 3 seconds
        setTimeout(connectWebSocket, 3000);
      };
      
      ws.onerror = (error: Event) => {
        console.error('WebSocket error:', error);
        setMessages(prev => {
          const filteredMessages = prev.filter(msg => msg.type !== 'thinking');
          return [...filteredMessages, { 
            type: 'error', 
            content: 'Connection error. Please try again later.' 
          }];
        });
        setIsThinking(false);
      };
      
      setSocket(ws);
      
      // Cleanup on unmount
      return () => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.close();
        }
      };
    };
    
    connectWebSocket();
  }, [isConnected]); // Depend on isConnected to reconnect when wallet state changes

  // Scroll to bottom when messages update
  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages]);

  const handleApprove = async (): Promise<void> => {
    if (!address || !isConnected || !usdcAddress) {
      setMessages(prev => [...prev, {
        type: 'error',
        content: 'Unable to approve USDC spending. Please ensure you are connected to a supported network.'
      }]);
      return;
    }

    setIsApproving(true);
    try {
      const txHash = await writeContractAsync({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [MESSAGE_MANAGER_ADDRESS, MESSAGE_PRICE_USDC]
      });

      if (publicClient) {
        await publicClient.waitForTransactionReceipt({ hash: txHash });
      }
      await refetchAllowance();
    } catch (error) {
      console.error('Error approving MessageManager spending:', error);
      setMessages(prev => [...prev, {
        type: 'error',
        content: 'Approval transaction failed or was rejected. Please try again.'
      }]);
    } finally {
      setIsApproving(false);
    }
  };

  const sendMessage = async (): Promise<void> => {
    if (
      !input.trim()
      || connectionStatus !== 'connected'
      || isThinking
      || !socket
      || !address
      || !chainId
    ) {
      return;
    }

    if (!hasApproval) {
      await handleApprove();
      return;
    }

    setIsPaying(true);

    // Add user message to UI
    setMessages(prev => [...prev, { type: 'user', content: input }]);

    // Add signature pending message
    setMessages(prev => [...prev, { type: 'signature_pending', content: 'Waiting for signature...' }]);

    try {
      // Sign the plain-text message for backend verification
      const messageSignature = await signMessageAsync({ message: input });

      const messageHash = keccak256(stringToHex(input));
      nonceCounterRef.current = (nonceCounterRef.current + 1) % 1000;
      const nonce = BigInt(Date.now()) * 1000n + BigInt(nonceCounterRef.current);
      const payload: MessagePayload = {
        messageHash,
        payer: address,
        nonce
      };

      const domain = {
        name: MESSAGE_MANAGER_DOMAIN_NAME,
        version: MESSAGE_MANAGER_DOMAIN_VERSION,
        chainId,
        verifyingContract: MESSAGE_MANAGER_ADDRESS
      } as const;

      const typedSignature = await signTypedDataAsync({
        domain,
        types: MESSAGE_TYPED_DATA,
        primaryType: 'Message',
        message: payload
      });

      const digest = hashTypedData({
        domain,
        types: MESSAGE_TYPED_DATA,
        primaryType: 'Message',
        message: payload
      });

      const txHash = await writeContractAsync({
        address: MESSAGE_MANAGER_ADDRESS,
        abi: MESSAGE_MANAGER_ABI,
        functionName: 'payForMessageWithSig',
        args: [payload, typedSignature, input]
      });

      if (publicClient) {
        await publicClient.waitForTransactionReceipt({ hash: txHash });
      }
      await refetchAllowance();

      // Remove signature pending message and add thinking message
      setMessages(prev => {
        const filteredMessages = prev.filter(msg => msg.type !== 'signature_pending');
        return [...filteredMessages, { type: 'thinking', content: 'Thinking...' }];
      });

      setIsThinking(true);

      socket.send(JSON.stringify({
        message: input,
        signature: messageSignature,
        address,
        payment: {
          m: {
            messageHash,
            payer: address,
            nonce: nonce.toString()
          },
          sig: typedSignature,
          messageURI: input,
          digest,
          transactionHash: txHash
        }
      }));

      setInput('');
    } catch (error) {
      console.error('Error paying for message:', error);
      setMessages(prev => {
        const filteredMessages = prev.filter(msg => msg.type !== 'signature_pending');
        return [...filteredMessages, {
          type: 'error',
          content: 'Failed to pay for and sign the message. Please try again.'
        }];
      });
    } finally {
      setIsPaying(false);
    }
  };

  // Update the handleKeyDown to be async
  const buttonLabel = (() => {
    if (isAllowanceLoading) {
      return 'Checking approval...';
    }
    if (!hasApproval) {
      return isApproving ? 'Approving...' : 'Approve';
    }
    return isPaying ? 'Paying...' : 'Pay and Sign Message';
  })();

  const buttonModeProcessing = !hasApproval ? isApproving : isPaying;
  const buttonDisabled =
    connectionStatus !== 'connected'
    || isThinking
    || buttonModeProcessing
    || isAllowanceLoading
    || (hasApproval && !input.trim());

  const handlePrimaryAction = async (): Promise<void> => {
    if (!hasApproval) {
      await handleApprove();
      return;
    }
    await sendMessage();
  };

  const handleKeyDown = async (e: React.KeyboardEvent<HTMLTextAreaElement>): Promise<void> => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (buttonDisabled) return;
      await handlePrimaryAction();
    }
  };

  return (
    <div className="d-flex flex-column min-vh-100">
      <Header />

      {/* Main Content */}
      <Container className="py-4 flex-grow-1">
        <Row className="g-4">
          {/* Chat Container */}
          <Col lg={6}>
            <ChatContainer
              isConnected={isConnected}
              messages={messages}
              messagesEndRef={messagesEndRef}
              input={input}
              setInput={setInput}
              handleKeyDown={handleKeyDown}
              onPrimaryAction={handlePrimaryAction}
              connectionStatus={connectionStatus}
              isThinking={isThinking}
              buttonLabel={buttonLabel}
              isButtonDisabled={buttonDisabled}
              isProcessingAction={buttonModeProcessing}
            />
          </Col>
          
          {/* Account Overview */}
          <Col lg={6}>
            <AccountContainer />
          </Col>
        </Row>
      </Container>
    </div>
  );
};

export default App; 