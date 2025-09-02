import React from 'react';
import { Form, Button, Card } from 'react-bootstrap';

function MessageInput({ 
  input, 
  setInput, 
  handleKeyDown, 
  sendMessage, 
  connectionStatus, 
  isThinking 
}) {
  return (
    <Card.Footer className="p-3 border-top">
      <Form.Group className="mb-2">
        <Form.Control
          as="textarea"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Type your message here..."
          rows="2"
          disabled={connectionStatus !== 'connected' || isThinking}
        />
      </Form.Group>
      <div className="d-flex justify-content-between align-items-center">
        <div className={`connection-status ${connectionStatus}`}>
          {connectionStatus.charAt(0).toUpperCase() + connectionStatus.slice(1)}
        </div>
        <Button 
          variant="success"
          onClick={sendMessage} 
          disabled={connectionStatus !== 'connected' || isThinking}
        >
          Send
        </Button>
      </div>
    </Card.Footer>
  );
}

export default MessageInput; 