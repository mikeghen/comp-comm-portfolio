import React from 'react';
import { Card, Spinner, Alert, Badge } from 'react-bootstrap';
import { usePolicyData } from '../../hooks/usePolicyData';
import { useAccount } from 'wagmi';
import { getNetworkName } from '../../config/contracts';

interface PolicyGridProps {
  text: string;
  maxLength: number;
}

const PolicyGrid: React.FC<PolicyGridProps> = ({ text, maxLength }) => {
  // Create a 100x20 character grid (2000 characters total)
  const GRID_WIDTH = 100;
  const GRID_HEIGHT = 20;
  const GRID_SIZE = GRID_WIDTH * GRID_HEIGHT;

  // Pad or truncate text to fit exactly in the grid
  const gridText = text.padEnd(Math.min(GRID_SIZE, maxLength), ' ').slice(0, Math.min(GRID_SIZE, maxLength));
  
  // Split into rows of 100 characters each
  const rows = [];
  for (let i = 0; i < GRID_HEIGHT; i++) {
    const start = i * GRID_WIDTH;
    const end = start + GRID_WIDTH;
    rows.push(gridText.slice(start, end));
  }

  return (
    <div 
      className="policy-grid" 
      style={{
        fontFamily: 'Courier New, monospace',
        fontSize: '11px',
        lineHeight: '1.2',
        backgroundColor: '#f8f9fa',
        border: '2px solid #6c757d',
        padding: '8px',
        borderRadius: '4px',
        overflow: 'hidden',
        whiteSpace: 'pre',
      }}
    >
      {rows.map((row, index) => (
        <div key={index} style={{ 
          borderBottom: index < rows.length - 1 ? '1px solid #e9ecef' : 'none',
          paddingBottom: '1px'
        }}>
          {row}
        </div>
      ))}
    </div>
  );
};

const PolicyView: React.FC = () => {
  const { isConnected, chainId } = useAccount();
  const { 
    promptText, 
    promptVersion, 
    maxPolicySize, 
    isLoading, 
    isError, 
    isConnected: contractConnected 
  } = usePolicyData();

  if (!isConnected) {
    return (
      <Card>
        <Card.Body>
          <div className="d-flex justify-content-between align-items-center mb-3">
            <h5 className="mb-0">Policy Viewer</h5>
            <Badge bg="warning">Wallet Not Connected</Badge>
          </div>
          <Alert variant="warning">
            Please connect your wallet to view the current policy.
          </Alert>
        </Card.Body>
      </Card>
    );
  }

  if (!contractConnected) {
    return (
      <Card>
        <Card.Body>
          <div className="d-flex justify-content-between align-items-center mb-3">
            <h5 className="mb-0">Policy Viewer</h5>
            <Badge bg="danger">Unsupported Network</Badge>
          </div>
          <Alert variant="danger">
            PolicyManager contract not available on {getNetworkName(chainId)}. 
            Please switch to Ethereum Sepolia to view the policy.
          </Alert>
        </Card.Body>
      </Card>
    );
  }

  if (isLoading) {
    return (
      <Card>
        <Card.Body className="text-center">
          <div className="d-flex justify-content-between align-items-center mb-3">
            <h5 className="mb-0">Policy Viewer</h5>
            <Badge bg="info">Loading</Badge>
          </div>
          <Spinner animation="border" role="status">
            <span className="visually-hidden">Loading policy...</span>
          </Spinner>
          <p className="mt-2">Loading current policy from PolicyManager contract...</p>
        </Card.Body>
      </Card>
    );
  }

  if (isError) {
    return (
      <Card>
        <Card.Body>
          <div className="d-flex justify-content-between align-items-center mb-3">
            <h5 className="mb-0">Policy Viewer</h5>
            <Badge bg="danger">Error</Badge>
          </div>
          <Alert variant="danger">
            Failed to load policy from PolicyManager contract. Please check your connection and try again.
          </Alert>
        </Card.Body>
      </Card>
    );
  }

  return (
    <Card>
      <Card.Body>
        <div className="d-flex justify-content-between align-items-center mb-3">
          <h5 className="mb-0">Policy Viewer</h5>
          <div className="d-flex gap-2">
            <Badge bg="success">Read-Only</Badge>
            <Badge bg="secondary">Version {promptVersion}</Badge>
            <Badge bg="info">{getNetworkName(chainId)}</Badge>
          </div>
        </div>
        
        <div className="mb-3">
          <p className="mb-2">
            <strong>Current Investment Policy</strong> - Viewing policy from PolicyManager contract
            <br />
            <small className="text-muted">
              Policy length: {promptText.length} / {maxPolicySize} characters
              {' · '}
              This is a read-only view
            </small>
          </p>
        </div>
        
        <PolicyGrid text={promptText} maxLength={maxPolicySize} />
        
        <div className="mt-3">
          <small className="text-muted">
            PolicyManager Address: <code>0x10E6e63337ea16F6EC5022A42fCeD95E74Fb3F1D</code>
            {' · '}
            Version: {promptVersion}
          </small>
        </div>
      </Card.Body>
    </Card>
  );
};

export default PolicyView;