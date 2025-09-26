import React from 'react';
import MessageInputStatesDemo from './components/demo/MessageInputStatesDemo';
import 'bootstrap/dist/css/bootstrap.min.css';

/**
 * Simple demo app to showcase MessageManager integration
 */
const DemoApp: React.FC = () => {
  return (
    <div className="min-vh-100" style={{ backgroundColor: '#f8f9fa' }}>
      <MessageInputStatesDemo />
    </div>
  );
};

export default DemoApp;