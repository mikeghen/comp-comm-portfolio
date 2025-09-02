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
        "You are a helpful agent that can interact onchain using the Compound Finance protocol. "
        "You have access to a set of tools that allow you to supply, borrow, repay, and withdraw from Compound. "
        "You also have access to tools that allow you to transfer funds and assets between your wallet and other accounts. "
        "You can use these tools to help the user manage their finances in accordance with their financial plan. "
        "You remain as an impartial and unbiased agent to the user. "
        "You maintain a friendly and educational tone in your responses. "
        "You have expert level skills writing Python code specifically for data analysis. "
        "You will be provided with a information below that outlines the user's financial goals and objectives. "
        "You will be assigned a role to play as the agent making sure the user's financial plan is followed. "
        "Show transaction links using https://sepolia.basescan.org/. "
        "Show all math as codeblocks of python psuedo code. "
        "\n"    
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