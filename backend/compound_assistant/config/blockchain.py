"""Blockchain configuration settings."""

import os
from typing import Optional

class BlockchainConfig:
    """Configuration for blockchain connections and contracts."""
    
    # Default values
    DEFAULT_MESSAGE_MANAGER_ADDRESS = "0xDa779e0Ed56140Bd700e3B891AD6e107E0Ef764D"
    DEFAULT_SEPOLIA_RPC = "wss://sepolia.infura.io/ws/v3/"
    
    @staticmethod
    def get_rpc_url() -> str:
        """Get the Ethereum RPC URL from environment.
        
        Returns:
            RPC URL for the Ethereum network
            
        Raises:
            ValueError: If RPC URL is not configured
        """
        rpc_url = os.getenv("ETHEREUM_RPC_URL")
        if not rpc_url:
            raise ValueError(
                "ETHEREUM_RPC_URL environment variable is required. "
                "Example: wss://sepolia.infura.io/ws/v3/YOUR_PROJECT_ID"
            )
        return rpc_url
    
    @staticmethod
    def get_agent_private_key() -> str:
        """Get the agent's private key from environment.
        
        Returns:
            Private key for the agent account
            
        Raises:
            ValueError: If private key is not configured
        """
        private_key = os.getenv("PRIVATE_KEY")
        if not private_key:
            raise ValueError(
                "PRIVATE_KEY environment variable is required. "
                "This account must have AGENT_ROLE on the MessageManager contract."
            )
        return private_key
    
    @staticmethod
    def get_message_manager_address() -> str:
        """Get the MessageManager contract address.
        
        Returns:
            Contract address for MessageManager
        """
        return os.getenv(
            "MESSAGE_MANAGER_CONTRACT_ADDRESS", 
            BlockchainConfig.DEFAULT_MESSAGE_MANAGER_ADDRESS
        )
    
    @staticmethod
    def get_event_poll_interval() -> float:
        """Get the event polling interval in seconds.
        
        Returns:
            Polling interval (default: 2.0 seconds)
        """
        try:
            return float(os.getenv("EVENT_POLL_INTERVAL", "2.0"))
        except ValueError:
            return 2.0
    
    @staticmethod
    def validate_config() -> bool:
        """Validate that all required configuration is present.
        
        Returns:
            True if configuration is valid, False otherwise
        """
        try:
            BlockchainConfig.get_rpc_url()
            BlockchainConfig.get_agent_private_key()
            return True
        except ValueError as e:
            print(f"❌ Configuration error: {e}")
            return False
    
    @staticmethod
    def print_config_requirements():
        """Print the required environment variables."""
        print("\n📋 Required Environment Variables:")
        print("=" * 50)
        print("ETHEREUM_RPC_URL         - WebSocket RPC URL for Sepolia")
        print("                          Example: wss://sepolia.infura.io/ws/v3/YOUR_PROJECT_ID")
        print("PRIVATE_KEY              - Private key for agent account (must have AGENT_ROLE)")
        print("\n📋 Optional Environment Variables:")
        print("=" * 50)
        print(f"MESSAGE_MANAGER_CONTRACT_ADDRESS - Contract address (default: {BlockchainConfig.DEFAULT_MESSAGE_MANAGER_ADDRESS})")
        print("EVENT_POLL_INTERVAL      - Event polling interval in seconds (default: 2.0)")
        print("\n💡 Create a .env file in the backend directory with these variables.")
        print("   The agent account must be granted AGENT_ROLE on the MessageManager contract.")
        print("   You can get WebSocket RPC URLs from Infura, Alchemy, or other providers.")
        print()

# Validate config on import
if __name__ == "__main__":
    BlockchainConfig.print_config_requirements()
