"""Contract configuration and ABIs for MessageManager and other contracts."""

import os
from typing import Dict, Any

# MessageManager contract ABI - focused on events and functions we need
MESSAGE_MANAGER_ABI = [
    {
        "inputs": [
            {"name": "sigHash", "type": "bytes32"}
        ],
        "name": "markMessageProcessed",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "sigHash", "type": "bytes32"},
            {"indexed": True, "name": "payer", "type": "address"},
            {"indexed": False, "name": "messageURI", "type": "string"},
            {"indexed": False, "name": "messageHash", "type": "bytes32"},
            {"indexed": False, "name": "userMint", "type": "uint256"},
            {"indexed": False, "name": "devMint", "type": "uint256"}
        ],
        "name": "MessagePaid",
        "type": "event"
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "sigHash", "type": "bytes32"},
            {"indexed": True, "name": "processor", "type": "address"}
        ],
        "name": "MessageProcessed",
        "type": "event"
    }
]

# Contract addresses by network
CONTRACT_ADDRESSES = {
    # Ethereum Sepolia
    11155111: {
        "MESSAGE_MANAGER": os.getenv("MESSAGE_MANAGER_ADDRESS", "0x0000000000000000000000000000000000000000"),
    },
    # Base Sepolia 
    84532: {
        "MESSAGE_MANAGER": os.getenv("MESSAGE_MANAGER_ADDRESS_BASE_SEPOLIA", "0x0000000000000000000000000000000000000000"),
    },
    # Base Mainnet
    8453: {
        "MESSAGE_MANAGER": os.getenv("MESSAGE_MANAGER_ADDRESS_BASE", "0x0000000000000000000000000000000000000000"),
    }
}

def get_contract_address(network_id: int, contract_name: str) -> str:
    """Get contract address for a specific network and contract."""
    network_contracts = CONTRACT_ADDRESSES.get(network_id, {})
    return network_contracts.get(contract_name, "0x0000000000000000000000000000000000000000")

def get_rpc_url(network_id: int) -> str:
    """Get RPC URL for a specific network."""
    rpc_urls = {
        11155111: os.getenv("ETHEREUM_SEPOLIA_RPC", "https://rpc.sepolia.org"),
        84532: os.getenv("BASE_SEPOLIA_RPC", "https://sepolia.base.org"),
        8453: os.getenv("BASE_MAINNET_RPC", "https://mainnet.base.org")
    }
    return rpc_urls.get(network_id, "")