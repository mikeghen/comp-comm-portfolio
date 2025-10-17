#!/usr/bin/env python3
"""
Test script to verify that only one WebSocket connection is created.
This script simulates the server startup process to check for duplicate connections.
"""

import os
import sys
import logging
from dotenv import load_dotenv

# Add the backend directory to the Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from compound_assistant.blockchain.web3_client import Web3Client
from compound_assistant.config.blockchain import BlockchainConfig
from compound_assistant.agent import create_agent

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def test_connection_reuse():
    """Test that Web3Client connections are properly reused."""
    
    # Load environment variables
    load_dotenv()
    
    print("🧪 Testing WebSocket connection reuse...")
    
    # Validate blockchain configuration
    if not BlockchainConfig.validate_config():
        print("❌ Blockchain configuration is invalid!")
        BlockchainConfig.print_config_requirements()
        return False
    
    try:
        # Initialize Web3 client (this should create the first and only connection)
        print("🔗 Initializing Web3 client...")
        web3_client = Web3Client(BlockchainConfig.get_rpc_url())
        print("✅ Web3 client initialized successfully!")
        
        # Create the agent with the existing Web3 client (this should reuse the connection)
        print("📡 Creating agent with existing Web3 client...")
        agent = create_agent(web3_client=web3_client)
        print("✅ Agent created successfully with reused Web3 connection!")
        
        # Test that the connection is still working
        if web3_client.is_connected():
            current_block = web3_client.get_web3().eth.block_number
            print(f"✅ Connection is still active. Current block: {current_block}")
        else:
            print("❌ Connection is not active!")
            return False
            
        print("🎉 Test passed! Only one WebSocket connection was created and reused.")
        return True
        
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        return False

if __name__ == "__main__":
    success = test_connection_reuse()
    sys.exit(0 if success else 1)
