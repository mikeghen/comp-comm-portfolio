"""API server for the Compound Assistant."""

import os
import json
from typing import List, Dict, Any
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage
from eth_account.messages import encode_defunct
from web3 import Web3

from compound_assistant import create_agent

# Load environment variables
load_dotenv()

# Create FastAPI app
app = FastAPI(title="Compound Assistant API")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins like "http://localhost:3000"
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create the agent
agent = create_agent()

# Thread ID for persistence
THREAD_ID = "Compound Assistant"

# Initialize Web3 for signature verification
w3 = Web3()

# Define message model
class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    messages: List[Message]

class ChatResponse(BaseModel):
    response: str

# WebSocket connection manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def send_message(self, message: str, websocket: WebSocket):
        await websocket.send_text(message)

manager = ConnectionManager()

def verify_signature(message: str, signature: str, address: str) -> bool:
    """Verify that the signature was created by the provided address."""
    try:
        # Create message hash
        message_hash = encode_defunct(text=message)
        
        # Recover the address from the signature
        recovered_address = w3.eth.account.recover_message(message_hash, signature=signature)
        
        # Convert addresses to checksum format for comparison
        checksum_recovered = w3.to_checksum_address(recovered_address)
        checksum_provided = w3.to_checksum_address(address)
        
        # Return True if the addresses match
        return checksum_recovered.lower() == checksum_provided.lower()
    except Exception as e:
        print(f"Error verifying signature: {e}")
        return False

@app.websocket("/ws/chat")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Receive message from client
            data = await websocket.receive_text()
            data = json.loads(data)
            user_message = data.get("message", "")
            signature = data.get("signature", "")
            address = data.get("address", "")
            
            if not user_message:
                continue
            
            # Verify signature if provided
            if signature and address:
                is_valid = verify_signature(user_message, signature, address)
                if not is_valid:
                    error_response = {
                        "type": "error",
                        "content": "Signature verification failed. Please ensure you're using the correct wallet."
                    }
                    await manager.send_message(json.dumps(error_response), websocket)
                    continue
            else:
                # If signature or address is missing, return error
                error_response = {
                    "type": "error",
                    "content": "Message must be signed with your wallet."
                }
                await manager.send_message(json.dumps(error_response), websocket)
                continue
                
            # Create config with thread ID for persistence
            config = {"configurable": {"thread_id": THREAD_ID}}
            
            # Process message with agent
            for chunk in agent.stream(
                {"messages": [HumanMessage(content=user_message)]}, 
                config
            ):
                if "agent" in chunk:
                    # First, check if there are tool_calls in the agent response
                    agent_message = chunk["agent"]["messages"][0]
                    tool_calls = agent_message.additional_kwargs.get("tool_calls", [])
                    
                    # If there are tool calls, send them to the client
                    if tool_calls:
                        for tool_call in tool_calls:
                            tool_type = tool_call.get("function", {}).get("name", "Unknown tool")
                            
                            # Extract arguments - could be a string or JSON
                            args = tool_call.get("function", {}).get("arguments", "{}")
                            try:
                                # Try to parse JSON arguments
                                args_dict = json.loads(args)
                                # For python_interpreter, we're interested in __arg1
                                if "__arg1" in args_dict:
                                    content = args_dict["__arg1"]
                                else:
                                    content = json.dumps(args_dict, indent=2)
                            except:
                                # If not JSON, use as is
                                content = args
                            
                            response = {
                                "type": "tool_call",
                                "tool": tool_type,
                                "content": content
                            }
                            await manager.send_message(json.dumps(response), websocket)
                    
                    # If there's actual content in the agent message, send it
                    if agent_message.content:
                        response = {
                            "type": "agent",
                            "content": agent_message.content
                        }
                        await manager.send_message(json.dumps(response), websocket)
                
                elif "tools" in chunk:
                    response = {
                        "type": "tool",
                        "content": chunk["tools"]["messages"][0].content
                    }
                    await manager.send_message(json.dumps(response), websocket)
    
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        error_response = {
            "type": "error",
            "content": f"An error occurred: {str(e)}"
        }
        await manager.send_message(json.dumps(error_response), websocket)
        manager.disconnect(websocket)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000) 