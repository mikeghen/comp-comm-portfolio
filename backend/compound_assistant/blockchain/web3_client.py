"""Web3 client for connecting to Ethereum networks."""

import os
import logging
from typing import Optional
from web3 import Web3

logger = logging.getLogger(__name__)


class Web3Client:
    """Web3 client for Ethereum network interactions."""
    
    def __init__(self, rpc_url: Optional[str] = None):
        """Initialize Web3 client.
        
        Args:
            rpc_url: RPC URL for the Ethereum network. If not provided, 
                    will use ETHEREUM_RPC_URL environment variable.
        """
        self.rpc_url = rpc_url or os.getenv("ETHEREUM_RPC_URL")
        if not self.rpc_url:
            raise ValueError("RPC URL must be provided or set in ETHEREUM_RPC_URL environment variable")
        
        self.w3: Optional[Web3] = None
        self._connect()
    
    def _connect(self):
        """Establish connection to the Ethereum network."""
        try:
            if not self.rpc_url.startswith("wss://"):
                raise ValueError(
                    "ETHEREUM_RPC_URL must be a WebSocket endpoint (wss://). HTTP is not supported."
                )
            # Use WebSocket provider only
            # Web3.py v7 exposes LegacyWebSocketProvider; WebSocketProvider may exist depending on minor version
            try:
                provider = Web3.WebSocketProvider(self.rpc_url)  # type: ignore[attr-defined]
            except AttributeError:
                provider = Web3.LegacyWebSocketProvider(self.rpc_url)  # fallback for v7
            self.w3 = Web3(provider)
            
            # Test connection
            if self.w3.is_connected():
                chain_id = self.w3.eth.chain_id
                logger.info(f"✅ Connected to Ethereum network (Chain ID: {chain_id})")
                logger.info(f"🔗 Current block number: {self.w3.eth.block_number}")
            else:
                raise ConnectionError("Failed to connect to Ethereum network")
                
        except Exception as e:
            logger.error(f"❌ Failed to connect to Ethereum network: {e}")
            raise
    
    def get_web3(self) -> Web3:
        """Get the Web3 instance.
        
        Returns:
            Web3 instance
            
        Raises:
            RuntimeError: If not connected to the network
        """
        if not self.w3 or not self.w3.is_connected():
            raise RuntimeError("Not connected to Ethereum network")
        return self.w3
    
    def is_connected(self) -> bool:
        """Check if connected to the Ethereum network.
        
        Returns:
            True if connected, False otherwise
        """
        return self.w3 is not None and self.w3.is_connected()
    
    def get_account(self) -> Optional[str]:
        """Get the configured account address.
        
        Returns:
            Account address if configured, None otherwise
        """
        private_key = os.getenv("PRIVATE_KEY")
        if private_key:
            account = self.w3.eth.account.from_key(private_key)
            return account.address
        return None
    
    def reconnect(self):
        """Reconnect to the Ethereum network."""
        logger.info("🔄 Reconnecting to Ethereum network...")
        self._connect()
