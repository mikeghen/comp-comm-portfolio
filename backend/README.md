## Requirements
- Python 3.10+
- Poetry for package management and tooling
  - [Poetry Installation Instructions](https://python-poetry.org/docs/#installation)
- [OpenAI API Key](https://platform.openai.com/docs/quickstart#create-and-export-an-api-key)
- Private Key for the EVM account you want the assistant to use

### Checking Python Version
Before using the example, ensure that you have the correct version of Python installed. The example requires Python 3.10 or higher. You can check your Python version by running:

```bash
python --version
poetry --version
```

## Installation
```bash
poetry install
```

## Run the Compound Assistant

### Set ENV Vars
- Ensure the following ENV Vars are set:
  - "PRIVATE_KEY"
  - "OPENAI_API_KEY"
  - "NETWORK_ID" (Defaults to `base-sepolia`)

```bash
poetry run python server.py
``` 

# Compound Assistant API Specification

This document outlines how to integrate with the Compound Assistant API using React.

## Overview

The Compound Assistant provides a WebSocket-based API for real-time chat interactions using signed messages. The API follows a streaming response pattern where responses from both the main assistant and any tools it uses are streamed back to the client as they become available.

## WebSocket Connection

### Connection Endpoint

```
ws://[server-address]:8000/ws/chat
```

Replace `[server-address]` with the hostname where the server is running (e.g., `localhost` for local development).

## Message Format

### Sending Signed Messages
Messages sent to the API need to be signed by the account.

The message should be sent as JSON strings with the following format:
```
{
  "message": "Your message to the assistant here",
  "signature": "signature of the message, signed by the account.",
  "address": "address of the account, used for signing the message."
}
```

### Receiving Messages

Responses are streamed back as JSON strings with the following format:

```
{
  "type": "agent",
  "content": "Response content from the assistant"
}
```

or

```
{
  "type": "tool",
  "content": "Response from a tool the assistant used"
}
```

The `type` field can be:
- `"agent"`: Direct responses from the assistant
- `"tool"`: Outputs from tools that the assistant uses to answer the query
- `"error"`: Error messages if something goes wrong

## Error Handling

If an error occurs, you'll receive a message with the following format:

```
{
  "type": "error",
  "content": "An error occurred: [error details]"
}
```

If signature verification fails, you'll receive an error message:

```
{
  "type": "error",
  "content": "Signature verification failed. Please ensure you're using the correct wallet."
}
```

## Message Signing and Verification

The Compound Assistant requires all messages to be signed by the user's wallet to verify their identity. This provides several benefits:

1. **Authentication**: Verifies that the message was sent by the owner of the wallet
2. **Message Integrity**: Ensures the message hasn't been tampered with
3. **Security**: Prevents unauthorized access to the assistant's functionality
4. **Personalization**: Allows the assistant to access on-chain data specific to the user's wallet

### How It Works

1. The frontend uses Wagmi's `useSignMessage` hook to create a cryptographic signature of the user's message
2. The signature and the user's wallet address are sent along with the message to the server
3. The server verifies that the signature was created by the claimed wallet address using `eth_account`
4. If verification succeeds, the message is processed by the assistant; otherwise, an error is returned

## React Integration Example
You will find an implementation of a minimalistic React frontend in the `frontend` folder.

Here's a basic example of how to integrate with the Compound Assistant API in a React application for reference:

```jsx
import React, { useState, useEffect, useRef } from 'react';
import { useAccount, useSignMessage } from 'wagmi';

const ChatComponent = () => {
  const [messages, setMessages] = useState([]);
  const [inputMessage, setInputMessage] = useState('');
  const [loading, setLoading] = useState(false);
  const [connected, setConnected] = useState(false);
  const socketRef = useRef(null);
  const { address, isConnected } = useAccount();
  const { signMessageAsync } = useSignMessage();

  // Connect to WebSocket when component mounts
  useEffect(() => {
    // Create WebSocket connection
    socketRef.current = new WebSocket('ws://localhost:8000/ws/chat');
    
    // Connection opened
    socketRef.current.onopen = () => {
      console.log('WebSocket connection established');
      setConnected(true);
    };
    
    // Listen for messages
    socketRef.current.onmessage = (event) => {
      const data = JSON.parse(event.data);
      console.log('Message received:', data);
      
      // Handle different message types
      if (data.type === 'agent' || data.type === 'tool') {
        setMessages(prevMessages => [
          ...prevMessages, 
          {
            role: data.type,
            content: data.content
          }
        ]);
      } else if (data.type === 'error') {
        console.error('Error from server:', data.content);
        // Display error to user
        setMessages(prevMessages => [
          ...prevMessages, 
          {
            role: 'error',
            content: data.content
          }
        ]);
      }
      
      setLoading(false);
    };
    
    // Connection closed
    socketRef.current.onclose = () => {
      console.log('WebSocket connection closed');
      setConnected(false);
    };
    
    // Connection error
    socketRef.current.onerror = (error) => {
      console.error('WebSocket error:', error);
      setConnected(false);
    };
    
    // Clean up WebSocket on component unmount
    return () => {
      if (socketRef.current) {
        socketRef.current.close();
      }
    };
  }, []);
  
  // Send message to the server
  const sendMessage = (e) => {
    e.preventDefault();
    
    if (!inputMessage.trim() || !connected) return;
    
    // Add user message to chat
    setMessages(prevMessages => [
      ...prevMessages, 
      {
        role: 'user',
        content: inputMessage
      }
    ]);
    
    // Send message to server
    const signature = await signMessageAsync({ message: inputMessage });
    const messageToSend = {
      message: inputMessage,
      signature: signature,
      address: address
    };
    
    socketRef.current.send(JSON.stringify(messageToSend));
    setInputMessage('');
    setLoading(true);
  };
  
  return (
    <div className="chat-container">
      <div className="chat-messages">
        {messages.map((message, index) => (
          <div key={index} className={`message ${message.role}`}>
            <div className="message-content">{message.content}</div>
          </div>
        ))}
        {loading && <div className="loading-indicator">Assistant is thinking...</div>}
      </div>
      
      <form onSubmit={sendMessage} className="chat-input-form">
        <input
          type="text"
          value={inputMessage}
          onChange={(e) => setInputMessage(e.target.value)}
          placeholder="Type your message here..."
          disabled={!connected}
        />
        <button type="submit" disabled={!connected || loading}>
          Send
        </button>
      </form>
      
      {!connected && (
        <div className="connection-error">
          Not connected to server. Please check your connection and refresh.
        </div>
      )}
    </div>
  );
};

export default ChatComponent;
```

## Advanced Integration

### Handling Markdown Content

The assistant may respond with Markdown-formatted text. Consider using a Markdown rendering library like `react-markdown` to properly display the formatted content:

```jsx
import ReactMarkdown from 'react-markdown';

// Inside your render function:
<ReactMarkdown>{message.content}</ReactMarkdown>
```

### Persisting Chat History

The server maintains conversation history using a thread ID. Your client doesn't need to send previous messages - just maintain the WebSocket connection or reconnect to the same endpoint to continue the conversation.

### Connection Status Management

For a production application, implement reconnection logic for WebSocket disconnections:

```jsx
useEffect(() => {
  const connectWebSocket = () => {
    socketRef.current = new WebSocket('ws://localhost:8000/ws/chat');
    
    socketRef.current.onopen = () => {
      console.log('WebSocket connection established');
      setConnected(true);
    };
    
    // Other event handlers as in the example above
    
    socketRef.current.onclose = (event) => {
      console.log('WebSocket connection closed:', event);
      setConnected(false);
      
      // Attempt to reconnect after a delay
      if (!event.wasClean) {
        setTimeout(() => {
          console.log('Attempting to reconnect...');
          connectWebSocket();
        }, 3000);
      }
    };
  };
  
  connectWebSocket();
  
  return () => {
    if (socketRef.current) {
      socketRef.current.close();
    }
  };
}, []);
```

## Security Considerations

For production deployments:

1. Use secure WebSockets (WSS) instead of WS
2. Implement proper authentication and authorization
3. Update the CORS configuration in the server to restrict access to trusted domains