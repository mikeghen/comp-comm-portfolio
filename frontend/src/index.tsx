import React from 'react';
import ReactDOM from 'react-dom/client';
import './styles.css';
import App from './App';
import DemoApp from './DemoApp';
import WalletProvider from './WalletProvider';
import 'bootstrap/dist/css/bootstrap.min.css';

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

// Show demo if ?demo=true in URL, otherwise show main app
const showDemo = new URLSearchParams(window.location.search).get('demo') === 'true';

root.render(
  <React.StrictMode>
    {showDemo ? (
      <DemoApp />
    ) : (
      <WalletProvider>
        <App />
      </WalletProvider>
    )}
  </React.StrictMode>
); 