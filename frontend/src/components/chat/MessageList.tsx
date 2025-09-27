import React from 'react';
import ReactMarkdown from 'react-markdown';

interface Message {
  type: 'agent' | 'user' | 'thinking' | 'tool' | 'tool_call' | 'error' | 'signature_pending';
  content: string;
}

interface MessageListProps {
  messages: Message[];
  messagesEndRef: React.RefObject<HTMLDivElement>;
}

function MessageList({ messages, messagesEndRef }: MessageListProps) {
  return (
    <div className="chat-messages p-3 overflow-auto d-flex flex-column">
      {messages.map((message, index) => {
        if (!message.content.trim()) return null;
        return (
          <div className={`message ${message.type} mb-2`} key={index}>
            <div className="message-content">
              {message.type === "tool" ? (
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
}

export default MessageList; 