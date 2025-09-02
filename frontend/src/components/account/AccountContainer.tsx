import React from 'react';
import { Card } from 'react-bootstrap';
import AccountOverview from './AccountOverview';
import AssetsList from './AssetsList';
import BorrowList from './BorrowList';

function AccountContainer() {
  return (
    <Card className="h-100">
      <Card.Body className="overflow-auto">
        <AccountOverview />
        <BorrowList />
        <AssetsList />
      </Card.Body>
    </Card>
  );
}

export default AccountContainer; 