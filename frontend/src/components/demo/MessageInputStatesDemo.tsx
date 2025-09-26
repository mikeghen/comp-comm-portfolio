import React from 'react';
import { Card, Button, Spinner } from 'react-bootstrap';

/**
 * Demo component showing all possible MessageInput button states
 * This demonstrates the different states users will see based on their wallet/approval status
 */
const MessageInputStatesDemo: React.FC = () => {
  const buttonStates = [
    {
      title: 'Wallet Not Connected',
      description: 'Default state when no wallet connected or MessageManager not available',
      button: { text: 'Send', variant: 'success' as const, disabled: false }
    },
    {
      title: 'Checking Approval Status',
      description: 'Loading state while checking USDC allowance',
      button: { text: <><Spinner size="sm" /> Checking...</>, variant: 'secondary' as const, disabled: true }
    },
    {
      title: 'Insufficient USDC Balance',
      description: 'User does not have enough USDC (10 USDC required)',
      button: { text: 'Insufficient USDC', variant: 'danger' as const, disabled: true }
    },
    {
      title: 'Needs USDC Approval',
      description: 'User has USDC but needs to approve MessageManager contract',
      button: { text: 'Approve', variant: 'warning' as const, disabled: false }
    },
    {
      title: 'Approving USDC',
      description: 'Approval transaction pending',
      button: { text: <><Spinner size="sm" /> Approving...</>, variant: 'warning' as const, disabled: true }
    },
    {
      title: 'Ready to Pay and Sign',
      description: 'Approved and ready to execute payForMessageWithSig',
      button: { text: 'Pay and Sign Message', variant: 'success' as const, disabled: false }
    },
    {
      title: 'Processing Payment',
      description: 'Contract transaction pending',
      button: { text: <><Spinner size="sm" /> Processing...</>, variant: 'success' as const, disabled: true }
    }
  ];

  return (
    <div className="p-4">
      <h2 className="mb-4">MessageManager Integration - Button States Demo</h2>
      <div className="row">
        {buttonStates.map((state, index) => (
          <div key={index} className="col-md-6 col-lg-4 mb-4">
            <Card>
              <Card.Header>
                <strong>{state.title}</strong>
              </Card.Header>
              <Card.Body>
                <p className="text-muted small">{state.description}</p>
                <div className="d-flex justify-content-between align-items-center">
                  <div className="text-muted small">
                    Connected
                    {state.title === 'Ready to Pay and Sign' && (
                      <span className="ms-2">(10 USDC per message)</span>
                    )}
                  </div>
                  <Button 
                    variant={state.button.variant}
                    disabled={state.button.disabled}
                    size="sm"
                  >
                    {state.button.text}
                  </Button>
                </div>
              </Card.Body>
            </Card>
          </div>
        ))}
      </div>
      
      <Card className="mt-4">
        <Card.Header>
          <strong>Integration Flow Summary</strong>
        </Card.Header>
        <Card.Body>
          <ol>
            <li><strong>User connects wallet</strong> - Button changes from "Send" to checking states</li>
            <li><strong>Check USDC balance</strong> - Ensure user has at least 10 USDC</li>
            <li><strong>Check USDC allowance</strong> - See if MessageManager is approved to spend USDC</li>
            <li><strong>Approve if needed</strong> - User clicks "Approve" to allow USDC spending</li>
            <li><strong>Pay and Sign</strong> - User clicks "Pay and Sign Message" to:
              <ul>
                <li>Create message struct (content hash, payer, nonce)</li>
                <li>Sign EIP-712 typed data</li>
                <li>Call <code>payForMessageWithSig</code> contract method</li>
                <li>Send message through traditional flow</li>
              </ul>
            </li>
          </ol>
          
          <div className="mt-3">
            <strong>Key Features:</strong>
            <ul className="mb-0">
              <li>Dynamic button states based on wallet/approval status</li>
              <li>EIP-712 signature generation for MessageManager domain</li>
              <li>USDC approval for exact message amount (10 USDC per message)</li>
              <li>Proper error handling and loading states</li>
              <li>Fallback to original "Send" behavior when contracts unavailable</li>
            </ul>
          </div>
        </Card.Body>
      </Card>
    </div>
  );
};

export default MessageInputStatesDemo;