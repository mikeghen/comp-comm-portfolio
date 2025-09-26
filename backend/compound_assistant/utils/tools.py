"""Tool definitions for the Compound Assistant."""

import json
import os

from eth_account import Account

from coinbase_agentkit import (
    AgentKit,
    AgentKitConfig,
    EthAccountWalletProvider,
    EthAccountWalletProviderConfig,
    compound_action_provider,
    erc20_action_provider,
    uniswap_v3_action_provider,
    wallet_action_provider,
    weth_action_provider,
)
from coinbase_agentkit_langchain import get_langchain_tools

ALLOWED_TOOLS = [
    "CompoundActionProvider_deposit",
    "CompoundActionProvider_redeem", 
    "ERC20ActionProvider_get_balance",
    "UniswapV3ActionProvider_swap_exact_input_single"
]

def initialize_agentkit():
    """
    Initialize the EVM Wallet Provider and AgentKit.
    Returns the AgentKit instance and the wallet provider.
    """
    # Load the private key from the environment variable.
    private_key = os.environ.get("PRIVATE_KEY")
    assert private_key is not None, "You must set PRIVATE_KEY environment variable"
    assert private_key.startswith("0x"), "Private key must start with 0x hex prefix"

    account = Account.from_key(private_key)
    
    wallet_provider = EthAccountWalletProvider(
        config=EthAccountWalletProviderConfig(
            account=account,
            chain_id=os.environ.get("NETWORK_ID")
        )
    )
    
    # Initialize AgentKit with all required action providers.
    agentkit = AgentKit(AgentKitConfig(
        wallet_provider=wallet_provider,
        action_providers=[
            compound_action_provider(), # Only supports supplying and withdrawing from allowed assets from Compound v3
            erc20_action_provider(), # Only supports transferring ERC20 tokens
            uniswap_v3_action_provider(), # Only supports swapping between allowed assets
            wallet_action_provider(), # Only supports transferring ETH
            weth_action_provider(), # Only supports wrapping ETH to WETH
        ]
    ))
    
    return agentkit, wallet_provider

def get_tools():
    """
    Get the LangChain tools from AgentKit and add a Python interpreter tool
    so the agent can perform Python analysis.
    """
    agentkit, _ = initialize_agentkit()
    all_tools = get_langchain_tools(agentkit)
    for tool in all_tools:
        print("Tool Name:",tool.name)
    
    # Only include tools that are in the ALLOWED_TOOLS list
    tools = [tool for tool in all_tools if tool.name in ALLOWED_TOOLS]
    
    print(f"✅ Filtered to {len(tools)} allowed tools out of {len(all_tools)} total tools")
    for tool in tools:
        print(f"   - {tool.name}")

    try:
        # If available, use LangChain's built-in Python interpreter tool.
        from langchain.tools.python.tool import PythonREPLTool
        python_interpreter_tool = PythonREPLTool()
    except ImportError:
        # Fallback: define a basic Python interpreter tool.
        from langchain.tools import Tool

        def python_interpreter(code: str) -> str:
            try:
                # Try evaluation in an empty namespace.
                result = eval(code, {}, {})
                return str(result)
            except Exception:
                try:
                    exec(code, globals(), locals())
                    return "Code executed."
                except Exception as e:
                    return f"Error: {str(e)}"
        
        python_interpreter_tool = Tool(
            name="python_interpreter",
            func=python_interpreter,
            description="Executes Python code for dynamic analysis. Use with caution!"
        )
        
    tools.append(python_interpreter_tool)
    return tools 