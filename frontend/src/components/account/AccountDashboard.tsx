import React from 'react';
import AccountOverview from './AccountOverview';
import WalletAssetsList from './WalletAssetsList';

const AccountDashboard: React.FC = () => {
  return (
    <div className="container py-4">
      <div className="row">
        <div className="col-12 mb-4">
          <h2>Account Dashboard</h2>
          <p className="text-muted">
            View your Compound account details below
          </p>
        </div>
      </div>
      
      <div className="row">
        <div className="col-12">
          <AccountOverview />
        </div>
      </div>
      
      <div className="row mt-4">
        <div className="col-12">
          <WalletAssetsList />
        </div>
      </div>
    </div>
  );
};

export default AccountDashboard; 