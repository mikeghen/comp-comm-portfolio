"""API server for the Compound Assistant."""

import os
import sys
import json
import logging
import asyncio
from contextlib import asynccontextmanager
from typing import List, Dict, Any, Optional
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage
from eth_account.messages import encode_defunct
from web3 import Web3

from compound_assistant import create_agent
from compound_assistant.event_listener import MessageEventListener

# Configure logging to show print statements and debug info
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Force stdout to be unbuffered for immediate print output
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

# Load environment variables
load_dotenv()

# Create FastAPI app
app = FastAPI(title="Compound Assistant API", lifespan=lifespan)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins like "http://localhost:3000"
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create the agent
print("🚀 Starting Compound Assistant server...")
print("📡 Creating agent and loading tools...")
agent = create_agent()
print("✅ Agent created successfully!")

# Thread ID for persistence
THREAD_ID = "Compound Assistant"

# Initialize Web3 for signature verification
w3 = Web3()

# Global event listener
event_listener: Optional[MessageEventListener] = None

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
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def send_message(self, message: str, websocket: WebSocket):
        try:
            await websocket.send_text(message)
        except Exception as e:
            logger.error(f"Error sending message to websocket: {e}")
            self.disconnect(websocket)
    
    async def broadcast(self, message: str):
        """Broadcast message to all connected clients."""
        if not self.active_connections:
            return
            
        # Send to all connections, removing failed ones
        failed_connections = []
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception as e:
                logger.error(f"Failed to broadcast to connection: {e}")
                failed_connections.append(connection)
        
        # Remove failed connections
        for connection in failed_connections:
            self.disconnect(connection)

manager = ConnectionManager()

async def process_agent_message(message_data: Dict[str, Any]) -> Optional[str]:
    """Process a message through the agent (used by event listener)."""
    try:
        user_message = message_data.get('message', '')
        payer = message_data.get('payer', '')
        
        if not user_message:
            return None
        
        logger.info(f"Processing agent message from event: {user_message[:50]}...")
        
        # Create config with thread ID for persistence
        config = {"configurable": {"thread_id": THREAD_ID}}
        
        # Process message with agent
        response_content = []
        
        for chunk in agent.stream(
            {"messages": [HumanMessage(content=user_message)]}, 
            config
        ):
            if "agent" in chunk:
                agent_message = chunk["agent"]["messages"][0]
                if agent_message.content:
                    response_content.append(agent_message.content)
            elif "tools" in chunk:
                tool_response = chunk["tools"]["messages"][0].content
                response_content.append(f"Tool result: {tool_response}")
        
        return "\n".join(response_content) if response_content else "Message processed successfully."
        
    except Exception as e:
        logger.error(f"Error processing agent message: {e}")
        return f"Error processing message: {str(e)}"

async def broadcast_message(message: str):
    """Broadcast a message to all WebSocket connections."""
    await manager.broadcast(message)

async def initialize_event_listener():
    """Initialize and start the event listener."""
    global event_listener
    
    try:
        network_id = int(os.getenv("NETWORK_ID", "11155111"))
        private_key = os.getenv("PRIVATE_KEY", "")
        
        if not private_key or private_key == "0x...":
            logger.warning("No private key configured, event listener disabled")
            return
            
        logger.info(f"Initializing event listener for network {network_id}")
        
        event_listener = MessageEventListener(
            network_id=network_id,
            private_key=private_key,
            message_processor=process_agent_message,
            websocket_broadcaster=broadcast_message
        )
        
        # Start listening in background
        asyncio.create_task(event_listener.start_listening())
        logger.info("Event listener started successfully")
        
    except Exception as e:
        logger.error(f"Failed to initialize event listener: {e}")
        logger.warning("Event listener disabled due to initialization error")

from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan."""
    # Startup
    logger.info("Starting up server...")
    await initialize_event_listener()
    yield
    # Shutdown
    global event_listener
    if event_listener:
        event_listener.stop()
        logger.info("Event listener stopped")

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
    print("💬 New WebSocket connection established")
    try:
        while True:
            # Receive message from client
            data = await websocket.receive_text()
            data = json.loads(data)
            user_message = data.get("message", "")
            signature = data.get("signature", "")
            address = data.get("address", "")
            
            print(f"📩 Received message from {address[:8]}...{address[-6:] if address else 'unknown'}: {user_message[:50]}{'...' if len(user_message) > 50 else ''}")
            
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
    print("🌐 Starting server on http://0.0.0.0:8000")
    print("📝 Print statements and debug output should now be visible!")
    
    # Configure uvicorn to show all output and disable buffering
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=8000,
        log_level="info",
        access_log=True,
        use_colors=True
    ) 