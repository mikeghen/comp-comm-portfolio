"""Main agent definition for the Compound Assistant."""

import os
import yaml

from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph, MessagesState
from langgraph.checkpoint.memory import MemorySaver
from compound_assistant.utils.nodes import call_agent, should_continue, create_tool_node
from compound_assistant.utils.tools import get_tools

def load_system_prompt():
    """
    Load the agent prompt from YAML. 
    """
    config_path = os.path.join(os.path.dirname(__file__), "config", "agent.yaml")
    with open(config_path, "r") as yaml_file:
        agent_config = yaml.safe_load(yaml_file)
    agent = agent_config.get("agent", {})
    
    return (
        "You are a helpful agent that can interact with Compound Finance and Uniswap V3."
        "You have access to a set of tools that allow you to deposit and withdraw from Compound Finance to earn yield."
        "You also have access to tools that allow you to swap assets on Uniswap V3."
        "You can use these tools to help the user manage your portfolio."
        "You maintain a friendly and educational tone in your responses."
        "Show transaction links using https://sepolia.etherscan.io/."
        "You have expert level skills writing Python code specifically for data analysis."
        "\n"    
        # TODO: Read system prompt from on-chain policy prompt.
        f"Your Role: {agent.get('role', '')}\n"
        f"Your Goal: {agent.get('goal', '')}\n"
        f"Your Plan: {agent.get('plan', '')}"
    )

def create_agent(model_name="gpt-4o-mini"):
    """
    Create and return the compiled agent graph.
    """
    # Get tools from AgentKit
    tools = get_tools()
    
    # Initialize LLM and bind it to the tools
    llm = ChatOpenAI(model=model_name)
    model = llm.bind_tools(tools)
    
    # Load system prompt
    system_prompt = load_system_prompt()
    
    # Create a tool node
    tool_node = create_tool_node(tools)
    
    # Create a partial function for the agent node
    agent_node = lambda state: call_agent(state, model, system_prompt)
    
    # Build the state graph
    workflow = StateGraph(MessagesState)
    workflow.add_node("agent", agent_node)
    workflow.add_node("tools", tool_node)
    
    # Set the entry point to the agent node
    workflow.add_edge(START, "agent")
    # Add a conditional edge from the agent node based on the response content
    workflow.add_conditional_edges("agent", should_continue)
    # Always return from the tools node back to the agent
    workflow.add_edge("tools", "agent")
    
    # Persist conversation state across graph runs using MemorySaver
    memory = MemorySaver()
    
    # Compile the workflow into a runnable (executable) graph
    return workflow.compile(checkpointer=memory) 