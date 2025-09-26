"""Tool definitions for the Compound Assistant."""

import json
import os

# Temporarily provide basic tools until coinbase-agentkit can be installed
def get_tools():
    """
    Return a minimal set of tools for event listener testing.
    This temporarily replaces coinbase-agentkit until it can be properly installed.
    """
    
    print("⚠️  Using fallback tools - coinbase-agentkit not available")
    print("✅ Event listener functionality will work with basic message processing")
    
    # Return empty list for now - the agent will still process messages
    # but won't have access to DeFi tools until coinbase-agentkit is available
    return []