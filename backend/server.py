"""API server for the Compound Assistant."""

import os
import sys
import json
import logging
import asyncio
from typing import List, Dict, Any
from urllib.parse import urlparse
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage
from eth_account.messages import encode_defunct
from web3 import Web3

from compound_assistant import create_agent
from compound_assistant.blockchain import Web3Client, EventListener
from compound_assistant.event_handlers import MessageEventHandler
from compound_assistant.config.blockchain import BlockchainConfig

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

# Environment detection
ENVIRONMENT = os.getenv("ENVIRONMENT", "development").lower()
IS_PRODUCTION = ENVIRONMENT == "production"

# Configure allowed origins based on environment
if IS_PRODUCTION:
    ALLOWED_ORIGINS = [
        "https://compcomm.club",
        "https://www.compcomm.club"
    ]
    print(f"🔒 Production mode: CORS restricted to {ALLOWED_ORIGINS}")
else:
    ALLOWED_ORIGINS = [
        "http://localhost:3000",
        "http://127.0.0.1:3000"
    ]
    print(f"🔧 Development mode: CORS restricted to {ALLOWED_ORIGINS}")

# Create FastAPI app
app = FastAPI(title="Compound Assistant API")

# Add CORS middleware with environment-specific origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Initialize blockchain components first
print("🔗 Initializing blockchain connections...")

# Validate blockchain configuration
if not BlockchainConfig.validate_config():
    print("❌ Blockchain configuration is invalid!")
    BlockchainConfig.print_config_requirements()
    sys.exit(1)

# Initialize Web3 client
try:
    web3_client = Web3Client(BlockchainConfig.get_rpc_url())
    print("✅ Web3 client initialized successfully!")
except Exception as e:
    print(f"❌ Failed to initialize Web3 client: {e}")
    BlockchainConfig.print_config_requirements()
    sys.exit(1)

# Create the agent with the existing Web3 client
print("🚀 Starting Compound Assistant server...")
print("📡 Creating agent and loading tools...")
agent = create_agent(web3_client=web3_client)
print("✅ Agent created successfully!")

# Thread ID for persistence
THREAD_ID = "Compound Assistant"

# Initialize event listener
try:
    contract_address = BlockchainConfig.get_message_manager_address()
    event_listener = EventListener(web3_client.get_web3(), contract_address)
    print(f"✅ Event listener initialized for contract: {contract_address}")
except Exception as e:
    print(f"❌ Failed to initialize event listener: {e}")
    sys.exit(1)

# Initialize Web3 for legacy signature verification (keeping for backward compatibility)
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
        try:
            print(f"🔌 Active WebSocket connections: {len(self.active_connections)}")
        except Exception:
            pass

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        try:
            print(f"🔌 Active WebSocket connections: {len(self.active_connections)}")
        except Exception:
            pass

    async def send_message(self, message: str, websocket: WebSocket):
        await websocket.send_text(message)

manager = ConnectionManager()

# Initialize message event handler
message_handler = MessageEventHandler(agent, event_listener, manager)
event_listener.add_event_handler("MessagePaid", message_handler.handle_message_paid_event)

# Health check endpoint for Docker and monitoring
@app.get("/healthy")
async def health_check():
    """
    Health check endpoint for Docker containers and load balancers.
    Returns basic system status and connectivity information.
    """
    try:
        # Check if Web3 client is connected
        blockchain_connected = web3_client.is_connected() if web3_client else False
        
        # Check if event listener is active
        listener_active = blockchain_listener_task and not blockchain_listener_task.done() if blockchain_listener_task else False
        
        # Get current block number if connected
        current_block = None
        if blockchain_connected:
            try:
                current_block = web3_client.get_web3().eth.block_number
            except Exception:
                current_block = None
        
        # Determine overall health status
        is_healthy = blockchain_connected and bool(contract_address)
        
        health_data = {
            "status": "healthy" if is_healthy else "degraded",
            "timestamp": asyncio.get_event_loop().time(),
            "blockchain_connected": blockchain_connected,
            "event_listener_active": listener_active,
            "contract_address": contract_address,
            "current_block": current_block,
            "active_websocket_connections": len(manager.active_connections),
            "environment": ENVIRONMENT
        }
        
        # Return 200 if healthy, 503 if degraded
        status_code = 200 if is_healthy else 503
        return health_data
        
    except Exception as e:
        # Return error status if health check itself fails
        return {
            "status": "unhealthy",
            "timestamp": asyncio.get_event_loop().time(),
            "error": str(e),
            "environment": ENVIRONMENT
        }

# Global variable to track if blockchain listener is running
blockchain_listener_task = None

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
    print("💬 New WebSocket connection established and validated")
    
    # Start blockchain listener if not already running
    global blockchain_listener_task
    if blockchain_listener_task is None or blockchain_listener_task.done():
        print("🎧 Starting blockchain event listener...")
        blockchain_listener_task = asyncio.create_task(
            event_listener.start_listening(BlockchainConfig.get_event_poll_interval())
        )
        print("✅ Blockchain event listener started")
    
    try:
        # Send welcome message
        welcome_message = {
            "type": "system",
            "content": "🔗 Connected to Compound Assistant. Listening for blockchain events..."
        }
        await manager.send_message(json.dumps(welcome_message), websocket)
        
        # Keep connection alive and handle any client messages
        while True:
            try:
                # Wait for messages with a timeout to allow for periodic checks
                data = await asyncio.wait_for(websocket.receive_text(), timeout=10.0)
                
                # Parse client message
                try:
                    message_data = json.loads(data)
                    message_type = message_data.get("type", "")
                    
                    if message_type == "ping":
                        # Respond to ping with pong
                        pong_response = {
                            "type": "pong",
                            "timestamp": message_data.get("timestamp")
                        }
                        await manager.send_message(json.dumps(pong_response), websocket)
                    
                    elif message_type == "status":
                        # Send status information
                        status_response = {
                            "type": "status",
                            "blockchain_connected": web3_client.is_connected(),
                            "event_listener_active": blockchain_listener_task and not blockchain_listener_task.done(),
                            "contract_address": contract_address,
                            "current_block": web3_client.get_web3().eth.block_number if web3_client.is_connected() else None
                        }
                        await manager.send_message(json.dumps(status_response), websocket)
                    
                    else:
                        # For other message types, send info about blockchain-only processing
                        info_response = {
                            "type": "info",
                            "content": "This assistant now processes messages from blockchain events only. "
                                     "To interact with the assistant, please pay for a message using the MessageManager contract."
                        }
                        await manager.send_message(json.dumps(info_response), websocket)
                        
                except json.JSONDecodeError:
                    error_response = {
                        "type": "error",
                        "content": "Invalid JSON message format"
                    }
                    await manager.send_message(json.dumps(error_response), websocket)
                    
            except asyncio.TimeoutError:
                # Timeout is normal, just continue the loop
                continue
            except WebSocketDisconnect:
                break
            except Exception as e:
                logger.error(f"Error handling WebSocket message: {e}")
                break
    
    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        error_response = {
            "type": "error",
            "content": f"An error occurred: {str(e)}"
        }
        try:
            await manager.send_message(json.dumps(error_response), websocket)
        except:
            pass  # WebSocket might already be closed
    finally:
        manager.disconnect(websocket)
        print("💔 WebSocket connection closed")

# Cleanup handler for graceful shutdown
@app.on_event("shutdown")
async def shutdown_event():
    """Handle graceful shutdown of the application."""
    global blockchain_listener_task
    
    print("🛑 Shutting down Compound Assistant server...")
    
    # Stop blockchain event listener
    if blockchain_listener_task and not blockchain_listener_task.done():
        print("🔇 Stopping blockchain event listener...")
        event_listener.stop_listening()
        try:
            await asyncio.wait_for(blockchain_listener_task, timeout=5.0)
            print("✅ Blockchain event listener stopped")
        except asyncio.TimeoutError:
            print("⚠️ Blockchain event listener shutdown timeout")
            blockchain_listener_task.cancel()
    
    print("👋 Compound Assistant server shutdown complete")

if __name__ == "__main__":
    import uvicorn
    print("🌐 Starting server on http://0.0.0.0:8000")
    print("📝 Server will listen for MessagePaid events from the blockchain")
    print(f"📋 Contract Address: {contract_address}")
    print(f"🔗 RPC URL: {BlockchainConfig.get_rpc_url()}")
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