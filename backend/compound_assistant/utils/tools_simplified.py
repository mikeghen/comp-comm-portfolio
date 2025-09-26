"""Simplified tool definitions for testing event listening functionality."""

class SimpleTool:
    """Simple tool class to replace LangChain Tool."""
    
    def __init__(self, name: str, func, description: str):
        self.name = name
        self.func = func
        self.description = description
    
    def run(self, *args, **kwargs):
        return self.func(*args, **kwargs)

def get_tools():
    """
    Return a minimal set of tools for testing purposes.
    This version doesn't require langchain dependencies.
    """
    
    def simple_analysis(query: str) -> str:
        """Simple analysis tool for testing."""
        return f"Analysis result for: {query}"
    
    def portfolio_check(action: str) -> str:
        """Simple portfolio check tool."""
        return f"Portfolio action executed: {action}"
    
    tools = [
        SimpleTool(
            name="simple_analysis",
            func=simple_analysis,
            description="Performs simple analysis on the given query."
        ),
        SimpleTool(
            name="portfolio_check", 
            func=portfolio_check,
            description="Checks portfolio status or executes portfolio actions."
        )
    ]
    
    print(f"✅ Using {len(tools)} simplified tools for testing")
    for tool in tools:
        print(f"   - {tool.name}")
    
    return tools