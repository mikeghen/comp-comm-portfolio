"""API server for the Compound Assistant."""

import os
import sys
import json
import logging
import asyncio
from typing import List, Dict, Any
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage
from eth_account.messages import encode_defunct
from web3 import Web3

from compound_assistant import create_agent

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

# MessageManager contract ABI - focused on events and functions we need
MESSAGE_MANAGER_ABI = [
    {
        "inputs": [
            {"name": "sigHash", "type": "bytes32"}
        ],
        "name": "markMessageProcessed",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "sigHash", "type": "bytes32"},
            {"indexed": True, "name": "payer", "type": "address"},
            {"indexed": False, "name": "messageURI", "type": "string"},
            {"indexed": False, "name": "messageHash", "type": "bytes32"},
            {"indexed": False, "name": "userMint", "type": "uint256"},
            {"indexed": False, "name": "devMint", "type": "uint256"}
        ],
        "name": "MessagePaid",
        "type": "event"
    },
    {
        "anonymous": False,
        "inputs": [
            {"indexed": True, "name": "sigHash", "type": "bytes32"},
            {"indexed": True, "name": "processor", "type": "address"}
        ],
        "name": "MessageProcessed",
        "type": "event"
    }
]

# Global variables for event listening
event_listening_task = None
w3_contract = None
agent_account = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan - startup and shutdown."""
    # Startup
    logger.info("Starting up server...")
    await start_event_listener()
    yield
    # Shutdown
    await stop_event_listener()

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
            logger.info("No active connections to broadcast to")
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
        
        logger.info(f"Broadcast message to {len(self.active_connections)} connections")

manager = ConnectionManager()

async def process_message_with_agent(user_message: str, payer_address: str = None) -> List[Dict[str, Any]]:
    """Process a message using the agent and return structured responses."""
    if not user_message:
        return []
    
    responses = []
    
    try:
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
                
                # If there are tool calls, add them to responses
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
                        
                        responses.append({
                            "type": "tool_call",
                            "tool": tool_type,
                            "content": content
                        })
                
                # If there's actual content in the agent message, add it
                if agent_message.content:
                    responses.append({
                        "type": "agent",
                        "content": agent_message.content
                    })
            
            elif "tools" in chunk:
                responses.append({
                    "type": "tool",
                    "content": chunk["tools"]["messages"][0].content
                })
    
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        responses.append({
            "type": "error",
            "content": f"An error occurred: {str(e)}"
        })
    
    return responses

async def start_event_listener():
    """Initialize and start the event listener for MessagePaid events."""
    global event_listening_task, w3_contract, agent_account
    
    try:
        # Get configuration from environment
        network_id = int(os.getenv("NETWORK_ID", "11155111"))
        private_key = os.getenv("PRIVATE_KEY", "")
        contract_address = os.getenv("MESSAGE_MANAGER_ADDRESS", "")
        
        if not private_key or private_key == "0x...":
            logger.warning("No private key configured, event listener disabled")
            return
            
        if not contract_address or contract_address == "0x0000000000000000000000000000000000000000":
            logger.warning("No MessageManager contract address configured, event listener disabled")
            return
        
        # Setup Web3 connection
        rpc_url = get_rpc_url(network_id)
        if not rpc_url:
            logger.error(f"No RPC URL for network {network_id}")
            return
            
        web3_instance = Web3(Web3.HTTPProvider(rpc_url))
        
        if not web3_instance.is_connected():
            logger.error(f"Failed to connect to {rpc_url}")
            return
            
        # Initialize agent account
        agent_account = web3_instance.eth.account.from_key(private_key)
        logger.info(f"Agent account: {agent_account.address}")
        
        # Initialize contract
        w3_contract = web3_instance.eth.contract(
            address=contract_address,
            abi=MESSAGE_MANAGER_ABI
        )
        
        logger.info(f"Connected to MessageManager at {contract_address} on network {network_id}")
        
        # Start event listening task
        event_listening_task = asyncio.create_task(listen_for_events(web3_instance))
        logger.info("Event listener started successfully")
        
    except Exception as e:
        logger.error(f"Failed to start event listener: {e}")

async def stop_event_listener():
    """Stop the event listener."""
    global event_listening_task
    
    if event_listening_task:
        event_listening_task.cancel()
        try:
            await event_listening_task
        except asyncio.CancelledError:
            pass
        logger.info("Event listener stopped")

def get_rpc_url(network_id: int) -> str:
    """Get RPC URL for the network."""
    rpc_urls = {
        11155111: "https://rpc.sepolia.org",  # Ethereum Sepolia
        84532: "https://sepolia.base.org",    # Base Sepolia  
        8453: "https://mainnet.base.org"      # Base Mainnet
    }
    return rpc_urls.get(network_id, "")

async def listen_for_events(web3_instance):
    """Listen for MessagePaid events and process them."""
    global w3_contract
    
    try:
        # Create event filter for MessagePaid events
        event_filter = w3_contract.events.MessagePaid.create_filter(fromBlock='latest')
        
        logger.info("Listening for MessagePaid events...")
        
        while True:
            try:
                # Poll for new events
                new_events = event_filter.get_new_entries()
                
                for event in new_events:
                    await handle_message_paid_event(event, web3_instance)
                
                # Sleep to avoid excessive polling
                await asyncio.sleep(5)
                
            except Exception as e:
                logger.error(f"Error polling for events: {e}")
                await asyncio.sleep(10)  # Wait longer on error
                
    except Exception as e:
        logger.error(f"Failed to listen for events: {e}")

async def handle_message_paid_event(event, web3_instance):
    """Handle a MessagePaid event by processing the message."""
    global w3_contract, agent_account
    
    try:
        # Extract event data
        sig_hash = event.args.sigHash
        payer = event.args.payer
        message_uri = event.args.messageURI
        message_hash = event.args.messageHash
        user_mint = event.args.userMint
        dev_mint = event.args.devMint
        
        logger.info(f"Received MessagePaid event - sigHash: {sig_hash.hex()}, payer: {payer}")
        logger.info(f"Message: {message_uri}")
        
        # Process the message using existing agent logic
        responses = await process_message_with_agent(message_uri, payer)
        
        # Mark message as processed on-chain
        await mark_message_processed(web3_instance, sig_hash)
        
        # Broadcast responses to all connected WebSocket clients
        for response in responses:
            # Add metadata for event-driven responses
            response['payer'] = payer
            response['sigHash'] = sig_hash.hex()
            response['source'] = 'blockchain_event'
            
            await manager.broadcast(json.dumps(response))
            
        logger.info(f"Successfully processed MessagePaid event for {payer}")
        
    except Exception as e:
        logger.error(f"Error handling MessagePaid event: {e}")

async def mark_message_processed(web3_instance, sig_hash):
    """Mark a message as processed on the MessageManager contract."""
    global w3_contract, agent_account
    
    try:
        # Build transaction
        function_call = w3_contract.functions.markMessageProcessed(sig_hash)
        
        # Get transaction details
        gas_estimate = function_call.estimate_gas({'from': agent_account.address})
        gas_price = web3_instance.eth.gas_price
        
        transaction = function_call.build_transaction({
            'from': agent_account.address,
            'gas': gas_estimate,
            'gasPrice': gas_price,
            'nonce': web3_instance.eth.get_transaction_count(agent_account.address),
        })
        
        # Sign and send transaction
        signed_txn = web3_instance.eth.account.sign_transaction(transaction, agent_account.key)
        tx_hash = web3_instance.eth.send_raw_transaction(signed_txn.rawTransaction)
        
        # Wait for transaction confirmation
        receipt = web3_instance.eth.wait_for_transaction_receipt(tx_hash)
        
        if receipt.status == 1:
            logger.info(f"Successfully marked message as processed. TX: {tx_hash.hex()}")
        else:
            logger.error(f"Transaction failed: {tx_hash.hex()}")
            
    except Exception as e:
        logger.error(f"Error marking message as processed: {e}")
        raise

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
                
            # Process message using the shared agent processing function
            responses = await process_message_with_agent(user_message, address)
            
            # Send all responses back to the WebSocket client
            for response in responses:
                response['source'] = 'websocket'
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