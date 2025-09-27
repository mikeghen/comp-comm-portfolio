import React, { useState, useEffect, useRef } from 'react';
import { useAccount } from 'wagmi';
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
      content: `Welcome to the Compound Community Portfolio! Send a message to make an adjustment to the portfolio.`
    }
  ]);
  const [input, setInput] = useState<string>('');
  const [connectionStatus, setConnectionStatus] = useState<'connected' | 'connecting' | 'disconnected'>('disconnected');
  const [isThinking, setIsThinking] = useState<boolean>(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimerRef = useRef<number | null>(null);
  
  // Use wagmi's useAccount hook to check if wallet is connected
  const { isConnected } = useAccount();

  // Connect to WebSocket
  useEffect(() => {
    // If wallet disconnects, ensure cleanup
    if (!isConnected) {
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current);
        reconnectTimerRef.current = null;
      }
      if (wsRef.current) {
        try {
          wsRef.current.onclose = null;
          wsRef.current.close();
        } catch (error) {
          console.warn('Error closing WebSocket connection:', error);
        }
        wsRef.current = null;
      }
      setConnectionStatus('disconnected');
      setIsThinking(false);
      return;
    }

    let didUnmount = false;

    const connect = () => {
      // Avoid duplicate connection if already open or connecting
      const existing = wsRef.current;
      if (existing && (existing.readyState === WebSocket.OPEN || existing.readyState === WebSocket.CONNECTING)) {
        return;
      }

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
      wsRef.current = ws;

      ws.onopen = () => {
        if (didUnmount) return;
        setConnectionStatus('connected');
      };

      ws.onmessage = (event: MessageEvent) => {
        if (didUnmount) return;
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
        if (didUnmount) return;
        setConnectionStatus('disconnected');
        setIsThinking(false);
        
        // Try to reconnect after 3 seconds
        if (reconnectTimerRef.current) {
          clearTimeout(reconnectTimerRef.current);
        }
        reconnectTimerRef.current = window.setTimeout(() => {
          connect();
        }, 3000);
      };
      
      ws.onerror = (error: Event) => {
        if (didUnmount) return;
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
    };
    
    connect();

    return () => {
      didUnmount = true;
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current);
        reconnectTimerRef.current = null;
      }
      const ws = wsRef.current;
      if (ws) {
        try {
          ws.onclose = null; // avoid reconnection on manual close
          if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
            ws.close();
          }
        } catch {}
        wsRef.current = null;
      }
    };
  }, [isConnected]); // Depend on isConnected to reconnect when wallet state changes

  // Scroll to bottom when messages update
  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages]);

  const sendMessage = async (): Promise<void> => {
    if (!input.trim() || connectionStatus !== 'connected' || isThinking) return;

    // Add user message to UI
    setMessages(prev => [...prev, { type: 'user', content: input }]);

    // Add thinking message immediately (no signature flow)
    setMessages(prev => [...prev, { type: 'thinking', content: 'Thinking...' }]);
    setIsThinking(true);

    // Clear input
    setInput('');
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