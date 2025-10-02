"""Node definitions for the Compound Assistant graph."""

import logging
from typing import Literal

from langchain_core.messages import SystemMessage
from langgraph.graph import END, MessagesState
from langgraph.prebuilt import ToolNode
from compound_assistant.utils.portfolio_balances import fetch_portfolio_balances, format_portfolio_holdings_context

logger = logging.getLogger(__name__)

def call_agent(state: MessagesState, model, system_prompt):
    """
    Node function that calls the LLM with the current messages.
    Injects the system prompt with fresh portfolio holdings if needed.
    """
    messages = state["messages"]
    
    # At the beginning of a conversation, ensure the system prompt is present with fresh portfolio holdings
    if not any(isinstance(msg, SystemMessage) for msg in messages):
        # Fetch current portfolio balances
        portfolio_balances = fetch_portfolio_balances()
        portfolio_context = format_portfolio_holdings_context(portfolio_balances)
        
        # The system_prompt contains base prompt and optionally onchain policy
        # We inject portfolio context between them (or after base if no onchain policy)
        # Format: base_prompt + portfolio_context + onchain_policy
        
        # Split system prompt to find where to inject portfolio context
        if "\n\n" in system_prompt:
            # Check if there's an onchain policy (second part after first \n\n)
            parts = system_prompt.split("\n\n", 1)
            # Inject portfolio context after base prompt
            updated_prompt = parts[0] + "\n\n" + portfolio_context
            if len(parts) > 1:
                # Add onchain policy after portfolio context
                updated_prompt = updated_prompt + "\n\n" + parts[1]
        else:
            # No sections, just append portfolio context
            updated_prompt = system_prompt + "\n\n" + portfolio_context
        
        logger.debug("🔄 Injected fresh portfolio holdings into system prompt")
        logger.info(f"📋 Full system prompt:\n{updated_prompt}")
        messages = [SystemMessage(content=updated_prompt)] + messages
    
    response = model.invoke(messages)
    return {"messages": [response]}

def should_continue(state: MessagesState) -> Literal["tools", END]:
    """
    Conditional edge function that determines whether to continue to tools or end.
    """
    last_message = state["messages"][-1]
    # If the LLM has made a tool call, route to the "tools" node.
    if hasattr(last_message, "tool_calls") and last_message.tool_calls:
        return "tools"
    # Otherwise, end execution (reply to the user).
    return END

def create_tool_node(tools):
    """
    Create a tool node that can call our Coinbase tools.
    """
    return ToolNode(tools) 