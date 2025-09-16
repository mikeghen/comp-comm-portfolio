import React from 'react';
import AccountOverview from './AccountOverview';
import WalletAssetsList from './WalletAssetsList';
import AssetsList from './AssetsList';

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
        <div className="col-md-6 mb-4 mb-md-0">
          <WalletAssetsList />
        </div>
        <div className="col-md-6">
          <AssetsList />
        </div>
      </div>
    </div>
  );
};

export default AccountDashboard; 