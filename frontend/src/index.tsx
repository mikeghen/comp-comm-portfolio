import React from 'react';
import ReactDOM from 'react-dom/client';
import './styles.css';
import App from './App';
import WalletProvider from './WalletProvider';
import 'bootstrap/dist/css/bootstrap.min.css';

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

root.render(
  <React.StrictMode>
    <WalletProvider>
      <App />
    </WalletProvider>
  </React.StrictMode>
); 