"""PolicyManager contract interface and ABI."""

import json
from typing import Dict, Any, Tuple
from web3 import Web3
from web3.contract import Contract


class PolicyManagerContract:
    """Interface for the PolicyManager smart contract."""
    
    # Contract ABI - extracted from the Solidity contract
    ABI = [
        {
            "type": "constructor",
            "inputs": [
                {"name": "_usdc", "type": "address"},
                {"name": "_mtToken", "type": "address"},
                {"name": "_dev", "type": "address"},
                {"name": "_vault", "type": "address"},
                {"name": "_initialPrompt", "type": "string"}
            ]
        },
        {
            "type": "function",
            "name": "getPrompt",
            "inputs": [],
            "outputs": [
                {"name": "", "type": "string"},
                {"name": "", "type": "uint256"}
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getPromptSlice",
            "inputs": [
                {"name": "start", "type": "uint256"},
                {"name": "end", "type": "uint256"}
            ],
            "outputs": [{"name": "", "type": "string"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "prompt",
            "inputs": [],
            "outputs": [{"name": "", "type": "string"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "promptVersion",
            "inputs": [],
            "outputs": [{"name": "", "type": "uint256"}],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "editPrompt",
            "inputs": [
                {"name": "start", "type": "uint256"},
                {"name": "end", "type": "uint256"},
                {"name": "replacement", "type": "string"}
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "previewEditCost",
            "inputs": [{"name": "changed", "type": "uint256"}],
            "outputs": [
                {"name": "costUSDC", "type": "uint256"},
                {"name": "userMint", "type": "uint256"},
                {"name": "devMint", "type": "uint256"}
            ],
            "stateMutability": "pure"
        },
        {
            "type": "event",
            "name": "PromptEdited",
            "inputs": [
                {"name": "editor", "type": "address", "indexed": True},
                {"name": "start", "type": "uint256", "indexed": False},
                {"name": "end", "type": "uint256", "indexed": False},
                {"name": "replacementLen", "type": "uint256", "indexed": False},
                {"name": "changed", "type": "uint256", "indexed": False},
                {"name": "costUSDC", "type": "uint256", "indexed": False},
                {"name": "userMint", "type": "uint256", "indexed": False},
                {"name": "devMint", "type": "uint256", "indexed": False},
                {"name": "version", "type": "uint256", "indexed": False}
            ],
            "anonymous": False
        }
    ]
    
    def __init__(self, w3: Web3, contract_address: str):
        """Initialize the PolicyManager contract interface.
        
        Args:
            w3: Web3 instance
            contract_address: Address of the deployed PolicyManager contract
        """
        self.w3 = w3
        self.address = Web3.to_checksum_address(contract_address)
        self.contract: Contract = w3.eth.contract(
            address=self.address,
            abi=self.ABI
        )
    
    def get_prompt(self) -> Tuple[str, int]:
        """Get the current prompt and version from the contract.
        
        Returns:
            Tuple of (prompt_text, prompt_version)
        """
        return self.contract.functions.getPrompt().call()
    
    def get_prompt_text_only(self) -> str:
        """Get only the prompt text from the contract.
        
        Returns:
            The current prompt text string
        """
        return self.contract.functions.prompt().call()
    
    def get_prompt_version(self) -> int:
        """Get the current prompt version from the contract.
        
        Returns:
            The current prompt version number
        """
        return self.contract.functions.promptVersion().call()
    
    def get_prompt_slice(self, start: int, end: int) -> str:
        """Get a slice of the prompt for gas efficiency.
        
        Args:
            start: The start index (inclusive)
            end: The end index (exclusive)
            
        Returns:
            The substring of the prompt
        """
        return self.contract.functions.getPromptSlice(start, end).call()
    
    def preview_edit_cost(self, changed: int) -> Tuple[int, int, int]:
        """Preview the cost of an edit without executing it.
        
        Args:
            changed: The number of 10-character units that would be changed
            
        Returns:
            Tuple of (costUSDC, userMint, devMint)
        """
        return self.contract.functions.previewEditCost(changed).call()