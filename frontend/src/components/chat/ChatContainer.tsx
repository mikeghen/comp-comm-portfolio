import React from 'react';
import { Card } from 'react-bootstrap';
import MessageList from './MessageList';
import MessageInput from './MessageInput';

function ChatContainer({ 
  isConnected, 
  messages, 
  messagesEndRef, 
  input,
  setInput,
  handleKeyDown,
  sendMessage,
  connectionStatus,
  isThinking
}) {
  return (
    <Card className="h-100 chat-card">
      {isConnected ? (
        <>
          <MessageList messages={messages} messagesEndRef={messagesEndRef} />
          <MessageInput 
            input={input}
            setInput={setInput}
            handleKeyDown={handleKeyDown}
            sendMessage={sendMessage}
            connectionStatus={connectionStatus}
            isThinking={isThinking}
          />
        </>
      ) : (
        <Card.Body className="d-flex flex-column align-items-center justify-content-center text-center p-5">
          <h2>Connect your wallet to start chatting</h2>
          <p className="text-muted">The Compound Community Portfolio requires a connected wallet to interact with the Compound Protocol.</p>
        </Card.Body>
      )}
    </Card>
  );
}

export default ChatContainer; 