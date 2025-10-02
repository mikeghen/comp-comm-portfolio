"""Fetch portfolio balances for the agent's wallet."""

import json
import logging
import os
from typing import Dict, List, Optional
from web3 import Web3
from compound_assistant.blockchain.web3_client import Web3Client

logger = logging.getLogger(__name__)

# ERC20 ABI for balanceOf function
ERC20_ABI = [
    {
        "constant": True,
        "inputs": [{"name": "owner", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function"
    }
]

# Asset configuration for Ethereum Sepolia testnet
# Matches frontend's NETWORK_WALLET_ASSETS configuration
SEPOLIA_ASSETS = [
    {"symbol": "USDC", "address": "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", "decimals": 6},
    {"symbol": "WETH", "address": "0x2D5ee574e710219a521449679A4A7f2B43f046ad", "decimals": 18},
    {"symbol": "COMP", "address": "0xA6c8D1c55951e8AC44a0EaA959Be5Fd21cc07531", "decimals": 18},
    {"symbol": "WBTC", "address": "0xa035b9e130F2B1AedC733eEFb1C67Ba4c503491F", "decimals": 8},
    {"symbol": "cUSDCv3", "address": "0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e", "decimals": 6},
    {"symbol": "cWETHv3", "address": "0x2943ac1216979aD8dB76D9147F64E61adc126e96", "decimals": 18},
]


def get_wallet_address() -> Optional[str]:
    """Get the wallet address from the PRIVATE_KEY environment variable.
    
    Returns:
        Wallet address derived from private key, or None if not configured
    """
    private_key = os.getenv("PRIVATE_KEY")
    if not private_key:
        logger.warning("PRIVATE_KEY not set, cannot determine wallet address")
        return None
    
    # Create a temporary Web3 instance to derive address from private key
    w3 = Web3()
    try:
        account = w3.eth.account.from_key(private_key)
        return account.address
    except Exception as e:
        logger.error(f"Failed to derive wallet address from private key: {e}")
        return None


def fetch_portfolio_balances() -> Dict[str, str]:
    """Fetch current portfolio balances for all assets.
    
    Returns:
        Dictionary mapping asset symbols to their balances as strings.
        Returns "0" for all assets if unable to fetch balances.
    """
    # Initialize result with zeros
    balances = {asset["symbol"]: "0" for asset in SEPOLIA_ASSETS}
    
    try:
        # Get RPC URL and wallet address
        rpc_url = os.getenv("ETHEREUM_RPC_URL")
        wallet_address = get_wallet_address()
        
        if not rpc_url:
            logger.warning("ETHEREUM_RPC_URL not set, returning zero balances")
            return balances
        
        if not wallet_address:
            logger.warning("Wallet address not available, returning zero balances")
            return balances
        
        # Initialize Web3 client
        w3_client = Web3Client(rpc_url)
        w3 = w3_client.get_web3()
        
        # Fetch balance for each asset
        for asset in SEPOLIA_ASSETS:
            try:
                # Create contract instance
                contract_address = Web3.to_checksum_address(asset["address"])
                contract = w3.eth.contract(address=contract_address, abi=ERC20_ABI)
                
                # Call balanceOf
                balance_wei = contract.functions.balanceOf(Web3.to_checksum_address(wallet_address)).call()
                
                # Convert to human-readable format
                balance_float = balance_wei / (10 ** asset["decimals"])
                
                # Format the balance - preserve precision for the agent
                balances[asset["symbol"]] = str(balance_float)
                
                logger.debug(f"Fetched balance for {asset['symbol']}: {balances[asset['symbol']]}")
                
            except Exception as e:
                logger.warning(f"Failed to fetch balance for {asset['symbol']}: {e}")
                # Keep the zero value already set
        
        logger.info(f"✅ Successfully fetched portfolio balances for {len(SEPOLIA_ASSETS)} assets")
        return balances
        
    except Exception as e:
        logger.error(f"❌ Failed to fetch portfolio balances: {e}")
        # Return zeros on error
        return balances


def format_portfolio_holdings_context(balances: Dict[str, str]) -> str:
    """Format portfolio balances as a context block for the system prompt.
    
    Args:
        balances: Dictionary mapping asset symbols to their balances
        
    Returns:
        Formatted string to inject into the system prompt
    """
    # Convert dict to JSON with proper formatting
    holdings_json = json.dumps(balances, indent=2)
    
    context = (
        "---\n"
        f"Your portfolio currently has the following holdings:\n"
        f"{holdings_json}\n"
        "---"
    )
    
    return context
