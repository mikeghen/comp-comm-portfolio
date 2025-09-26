import React, { RefObject } from 'react';
import ReactMarkdown from 'react-markdown';

type MessageType = 'agent' | 'user' | 'thinking' | 'tool' | 'tool_call' | 'error' | 'signature_pending';

interface ChatMessage {
  type: MessageType;
  content: string;
}

interface MessageListProps {
  messages: ChatMessage[];
  messagesEndRef: RefObject<HTMLDivElement>;
}

const MessageList: React.FC<MessageListProps> = ({ messages, messagesEndRef }) => {
  return (
    <div className="chat-messages p-3 overflow-auto d-flex flex-column">
      {messages.map((message, index) => {
        if (!message.content.trim()) return null;
        return (
          <div className={`message ${message.type} mb-2`} key={index}>
            <div className="message-content">
              {message.type === 'tool' ? (
                <pre className="tool-result-pre p-2 rounded">
                  {message.content}
                </pre>
              ) : (
                <ReactMarkdown>{message.content}</ReactMarkdown>
              )}
            </div>
          </div>
        );
      })}
      <div ref={messagesEndRef} />
    </div>
  );
};

export default MessageList;