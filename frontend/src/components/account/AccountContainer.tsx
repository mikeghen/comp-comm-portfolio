import React from 'react';
import { Card } from 'react-bootstrap';
import ManagementTokenInfo from './ManagementTokenInfo';
import AccountOverview from './AccountOverview';
import WalletAssetsList from './WalletAssetsList';
import { usePortfolioValue } from '../../hooks/usePortfolioValue';

function AccountContainer() {
  // Get portfolio value to share with ManagementTokenInfo
  const { totalWalletValue } = usePortfolioValue();
  
  return (
    <Card className="h-100">
      <Card.Body className="overflow-auto">
        <ManagementTokenInfo portfolioValue={totalWalletValue} />
        <AccountOverview />
        <WalletAssetsList />
      </Card.Body>
    </Card>
  );
}

export default AccountContainer; 