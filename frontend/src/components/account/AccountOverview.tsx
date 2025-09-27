import React from 'react';
import { usePortfolioValue } from '../../hooks/usePortfolioValue';

function AccountOverview() {
  // Use shared portfolio value hook
  const {
    totalWalletValue,
    isSupported,
    isLoading,
    isError
  } = usePortfolioValue();

  // Format values for display
  const formattedWalletValue = totalWalletValue.toLocaleString('en-US', {
    style: 'currency',
    currency: 'USD'
  });

  return (
    <div className="card mb-4">
      <div className="card-header bg-white border-bottom">
        <h5 className="mb-0">Portfolio Value</h5>
      </div>
      <div className="card-body bg-light">
        {!isSupported ? (
          <div className="text-center py-2 text-warning">
            Please connect to a supported network
          </div>
        ) : isLoading ? (
          <div className="text-center py-2">
            <div className="spinner-border spinner-border-sm" role="status">
              <span className="visually-hidden">Loading...</span>
            </div> Loading account data...
          </div>
        ) : isError ? (
          <div className="text-center py-2 text-danger">
            Error loading account data
            <div className="small mt-1">
              Check console for detailed error information
            </div>
          </div>
        ) : (
          <>
            <div className="row">
              <div className="col">
                <div className="h4">
                  {formattedWalletValue}
                </div>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

export default AccountOverview;