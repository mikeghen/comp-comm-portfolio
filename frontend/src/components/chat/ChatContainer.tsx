import React, { RefObject } from 'react';
import { Card } from 'react-bootstrap';
import MessageList from './MessageList';
import MessageInput from './MessageInput';

type ConnectionStatus = 'connected' | 'connecting' | 'disconnected';

interface Message {
  type: 'agent' | 'user' | 'thinking' | 'tool' | 'tool_call' | 'error' | 'signature_pending';
  content: string;
}

interface ChatContainerProps {
  isConnected: boolean;
  messages: Message[];
  messagesEndRef: RefObject<HTMLDivElement>;
  input: string;
  setInput: (value: string) => void;
  handleKeyDown: (event: React.KeyboardEvent<HTMLTextAreaElement>) => Promise<void>;
  onPrimaryAction: () => Promise<void>;
  connectionStatus: ConnectionStatus;
  isThinking: boolean;
  buttonLabel: string;
  isButtonDisabled: boolean;
  isProcessingAction: boolean;
}

const ChatContainer: React.FC<ChatContainerProps> = ({
  isConnected,
  messages,
  messagesEndRef,
  input,
  setInput,
  handleKeyDown,
  onPrimaryAction,
  connectionStatus,
  isThinking,
  buttonLabel,
  isButtonDisabled,
  isProcessingAction
}) => {
  return (
    <Card className="h-100 chat-card">
      {isConnected ? (
        <>
          <MessageList messages={messages} messagesEndRef={messagesEndRef} />
          <MessageInput
            input={input}
            setInput={setInput}
            handleKeyDown={handleKeyDown}
            onPrimaryAction={onPrimaryAction}
            connectionStatus={connectionStatus}
            isThinking={isThinking}
            buttonLabel={buttonLabel}
            isButtonDisabled={isButtonDisabled}
            isProcessingAction={isProcessingAction}
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
};

export default ChatContainer;