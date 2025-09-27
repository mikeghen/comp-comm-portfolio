"""MessageManager contract interface and ABI."""

import json
from typing import Dict, Any
from web3 import Web3
from web3.contract import Contract


class MessageManagerContract:
    """Interface for the MessageManager smart contract."""
    
    # Contract ABI - extracted from the Solidity contract
    ABI = [
        {
            "type": "constructor",
            "inputs": [
                {"name": "_usdc", "type": "address"},
                {"name": "_mtToken", "type": "address"},
                {"name": "_dev", "type": "address"},
                {"name": "_agent", "type": "address"},
                {"name": "_admin", "type": "address"},
                {"name": "_vault", "type": "address"}
            ]
        },
        {
            "type": "function",
            "name": "payForMessage",
            "inputs": [{"name": "message", "type": "string"}],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "markMessageProcessed",
            "inputs": [{"name": "messageHash", "type": "bytes32"}],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "paidMessages",
            "inputs": [{"name": "messageHash", "type": "bytes32"}],
            "outputs": [{"name": "message", "type": "string"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "processedMessages",
            "inputs": [{"name": "messageHash", "type": "bytes32"}],
            "outputs": [{"name": "processed", "type": "bool"}],
            "stateMutability": "view"
        },
        {
            "type": "event",
            "name": "MessagePaid",
            "inputs": [
                {"name": "messageHash", "type": "bytes32", "indexed": True},
                {"name": "payer", "type": "address", "indexed": True},
                {"name": "userMint", "type": "uint256", "indexed": False},
                {"name": "devMint", "type": "uint256", "indexed": False}
            ],
            "anonymous": False
        },
        {
            "type": "event",
            "name": "MessageProcessed",
            "inputs": [
                {"name": "messageHash", "type": "bytes32", "indexed": True},
                {"name": "processor", "type": "address", "indexed": True}
            ],
            "anonymous": False
        },
        {
            "type": "function",
            "name": "AGENT_ROLE",
            "inputs": [],
            "outputs": [{"name": "", "type": "bytes32"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "MESSAGE_PRICE_USDC",
            "inputs": [],
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "MT_PER_MESSAGE_USER",
            "inputs": [],
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view"
        }
    ]
    
    def __init__(self, w3: Web3, contract_address: str):
        """Initialize the MessageManager contract interface.
        
        Args:
            w3: Web3 instance
            contract_address: Address of the deployed MessageManager contract
        """
        self.w3 = w3
        self.address = Web3.to_checksum_address(contract_address)
        self.contract: Contract = w3.eth.contract(
            address=self.address,
            abi=self.ABI
        )
    
    def get_paid_message(self, message_hash: str) -> str:
        """Get the message content for a given message hash.
        
        Args:
            message_hash: The keccak256 hash of the message
            
        Returns:
            The message content string
        """
        normalized_hash = message_hash if message_hash.startswith("0x") else f"0x{message_hash}"
        return self.contract.functions.paidMessages(normalized_hash).call()
    
    def is_message_processed(self, message_hash: str) -> bool:
        """Check if a message has been processed.
        
        Args:
            message_hash: The keccak256 hash of the message
            
        Returns:
            True if the message has been processed, False otherwise
        """
        normalized_hash = message_hash if message_hash.startswith("0x") else f"0x{message_hash}"
        return self.contract.functions.processedMessages(normalized_hash).call()
    
    def mark_message_processed(self, message_hash: str, from_address: str) -> str:
        """Mark a message as processed.
        
        Args:
            message_hash: The keccak256 hash of the message
            from_address: Address of the account calling the function (must have AGENT_ROLE)
            
        Returns:
            Transaction hash
        """
        normalized_hash = message_hash if message_hash.startswith("0x") else f"0x{message_hash}"
        tx = self.contract.functions.markMessageProcessed(normalized_hash).build_transaction({
            'from': from_address,
            'gas': 100000,  # Estimate gas limit
            'gasPrice': self.w3.eth.gas_price,
            'nonce': self.w3.eth.get_transaction_count(from_address),
        })
        return tx
    
    def create_event_filter(self, from_block: str = "latest"):
        """Create an event filter for MessagePaid events.
        
        Args:
            from_block: Block to start listening from (default: "latest")
            
        Returns:
            Event filter for MessagePaid events
        """
        return self.contract.events.MessagePaid.create_filter(
            from_block=from_block
        )
