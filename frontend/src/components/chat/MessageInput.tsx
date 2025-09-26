import React from 'react';
import { Form, Button, Card, Spinner } from 'react-bootstrap';

type ConnectionStatus = 'connected' | 'connecting' | 'disconnected';

interface MessageInputProps {
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

const MessageInput: React.FC<MessageInputProps> = ({
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
  const capitalizedStatus = connectionStatus.charAt(0).toUpperCase() + connectionStatus.slice(1);

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
          {capitalizedStatus}
        </div>
        <Button
          variant="success"
          onClick={() => {
            void onPrimaryAction();
          }}
          disabled={connectionStatus !== 'connected' || isThinking || isButtonDisabled}
          className="d-flex align-items-center gap-2"
        >
          {isProcessingAction && <Spinner animation="border" size="sm" role="status" />}
          <span>{buttonLabel}</span>
        </Button>
      </div>
    </Card.Footer>
  );
};

export default MessageInput;