import React from 'react';
import { useAccount } from 'wagmi';
import { useManagementToken } from '../../hooks/useManagementToken';
import { OverlayTrigger, Tooltip } from 'react-bootstrap';

interface ManagementTokenInfoProps {
  portfolioValue: number;
}

function ManagementTokenInfo({ portfolioValue }: ManagementTokenInfoProps) {
  const { chainId } = useAccount();
  
  // Only show on Ethereum Sepolia
  if (chainId !== 11155111) return null;

  // Use ManagementToken hook
  const { 
    totalSupply: mtTotalSupply, 
    mtTokenPrice,
    isLoading,
    isError
  } = useManagementToken(portfolioValue);

  // Format values for display
  const formattedMtPrice = mtTokenPrice.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2,
    maximumFractionDigits: 4
  });

  const formattedMtTotalSupply = mtTotalSupply.toLocaleString('en-US', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 1
  });

  if (isLoading || isError || mtTotalSupply === 0) return null;

  const tooltipContent = (
    <Tooltip id="mt-ev-tooltip">
      <div style={{ maxWidth: '280px', textAlign: 'left' }}>
        <strong>Management Token Expected Value</strong><br/>
        Estimated redeemable value per MT when portfolio enters redemption phase.<br/><br/>
        <strong>Calculation:</strong> Portfolio Value ÷ Total MT Supply<br/>
        <strong>Current:</strong> {portfolioValue.toLocaleString('en-US', { style: 'currency', currency: 'USD' })} ÷ {formattedMtTotalSupply} MT = {formattedMtPrice}<br/><br/>
        <em>Note: This is an estimate. Actual value may differ due to market conditions.</em>
      </div>
    </Tooltip>
  );

  return (
    <div className="card mb-3">
      <div className="card-body py-2">
        <div className="row text-muted small align-items-center">
          <div className="col-5">
            <div className="d-flex align-items-center gap-1">
              <span>MT EV</span>
              <OverlayTrigger
                placement="left"
                delay={{ show: 250, hide: 400 }}
                overlay={tooltipContent}
                trigger={['hover', 'focus']}
              >
                <span 
                  style={{ 
                    fontSize: '0.75rem', 
                    cursor: 'help', 
                    opacity: 0.7,
                    fontWeight: 'bold',
                    color: '#6c757d',
                    border: '1px solid #6c757d',
                    borderRadius: '50%',
                    width: '14px',
                    height: '14px',
                    display: 'inline-flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    lineHeight: 1
                  }}
                >
                  ?
                </span>
              </OverlayTrigger>
            </div>
            <div>{formattedMtPrice}</div>
          </div>
          <div className="col-7">
            <span>Total Supply</span>
            <div>{formattedMtTotalSupply} MT</div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default ManagementTokenInfo;
