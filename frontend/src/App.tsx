import React, { useState, useEffect, useRef } from 'react';
import { useAccount, useSignMessage } from 'wagmi';
import { Container, Row, Col } from 'react-bootstrap';
import 'bootstrap/dist/css/bootstrap.min.css';
import './bootstrap-overrides.css';

// Import components
import Header from './components/layout/Header';
import ChatContainer from './components/chat/ChatContainer';
import AccountContainer from './components/account/AccountContainer';

// Define types for messages
interface Message {
  type: 'agent' | 'user' | 'thinking' | 'tool' | 'tool_call' | 'error' | 'signature_pending';
  content: string;
}

const App: React.FC = () => {
  const [messages, setMessages] = useState<Message[]>([
    {
      type: 'agent',
      content: `Welcome to the Compound Assistant! I can help you interact with the Compound Protocol on the blockchain.`
    }
  ]);
  const [input, setInput] = useState<string>('');
  const [socket, setSocket] = useState<WebSocket | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'connected' | 'connecting' | 'disconnected'>('disconnected');
  const [isThinking, setIsThinking] = useState<boolean>(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  
  // Use wagmi's useAccount hook to check if wallet is connected
  const { address, isConnected } = useAccount();
  const { signMessageAsync } = useSignMessage();

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
      
      console.log('Connecting to WebSocket:', wsUrl);
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

  const sendMessage = async (): Promise<void> => {
    if (!input.trim() || connectionStatus !== 'connected' || isThinking || !socket) return;
    
    // Add user message to UI
    setMessages(prev => [...prev, { type: 'user', content: input }]);
    
    // Add signature pending message
    setMessages(prev => [...prev, { type: 'signature_pending', content: 'Waiting for signature...' }]);
    
    try {
      // Sign the message with the connected wallet
      const signature = await signMessageAsync({ message: input });
      
      // Remove signature pending message and add thinking message
      setMessages(prev => {
        const filteredMessages = prev.filter(msg => msg.type !== 'signature_pending');
        return [...filteredMessages, { type: 'thinking', content: 'Thinking...' }];
      });
      
      // Set thinking state after signature is obtained
      setIsThinking(true);
      
      // Send signed message to server
      socket.send(JSON.stringify({ 
        message: input,
        signature: signature,
        address: address
      }));
      
      // Clear input
      setInput('');
    } catch (error) {
      console.error('Error signing message:', error);
      setMessages(prev => {
        // Remove signature pending message
        const filteredMessages = prev.filter(msg => msg.type !== 'signature_pending');
        return [...filteredMessages, { 
          type: 'error', 
          content: 'Failed to sign message. Please try again.' 
        }];
      });
    }
  };

  // Update the handleKeyDown to be async
  const handleKeyDown = async (e: React.KeyboardEvent<HTMLTextAreaElement>): Promise<void> => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      await sendMessage();
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
              sendMessage={sendMessage}
              connectionStatus={connectionStatus}
              isThinking={isThinking}
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