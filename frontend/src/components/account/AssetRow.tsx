import React from 'react';
import { ListGroup, OverlayTrigger, Tooltip } from 'react-bootstrap';

interface AssetRowProps {
  symbol: string;
  amount: string;
  value: string;
  price: string;
  borrowCollateralFactor?: string;
  liquidateCollateralFactor?: string;
}

const AssetRow: React.FC<AssetRowProps> = ({ 
  symbol, 
  amount, 
  value,
  price,
  borrowCollateralFactor,
  liquidateCollateralFactor
}) => {
  // Format values to ensure they are never NaN
  const safeAmount = !isNaN(parseFloat(amount)) ? parseFloat(amount).toFixed(6) : '0.000000';
  const safePrice = !isNaN(parseFloat(price)) ? parseFloat(price).toFixed(2) : '0.00';
  // Value should already be formatted, but we'll add a safeguard
  const safeValue = value || '0.00';

  return (
    <ListGroup.Item className="d-flex justify-content-between align-items-center">
      <div className="d-flex align-items-center">
        <div className="asset-icon me-3">{symbol}</div>
        <div>
          <div>{symbol}</div>
        </div>
      </div>
      <div className="text-center">
        <OverlayTrigger
          placement="top"
          overlay={<Tooltip>Current price from Compound Oracle</Tooltip>}
        >
          <div className="small text-muted mt-1">
            @ ${safePrice}
          </div>
        </OverlayTrigger>
      </div>
      <div className="text-end">
        <div className="text-muted small">{safeAmount} {symbol}</div>
        <div>${safeValue}</div>
      </div>
    </ListGroup.Item>
  );
};

export default AssetRow; 