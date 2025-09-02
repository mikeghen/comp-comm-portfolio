"""Node definitions for the Compound Assistant graph."""

from typing import Literal

from langchain_core.messages import SystemMessage
from langgraph.graph import END, MessagesState
from langgraph.prebuilt import ToolNode

def call_agent(state: MessagesState, model, system_prompt):
    """
    Node function that calls the LLM with the current messages.
    Injects the system prompt if needed.
    """
    messages = state["messages"]
    # At the beginning of a conversation, ensure the system prompt is present.
    if not any(isinstance(msg, SystemMessage) for msg in messages):
        messages = [SystemMessage(content=system_prompt)] + messages
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