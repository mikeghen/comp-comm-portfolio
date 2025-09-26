"""Event listener service for MessageManager contract events."""

import asyncio
import logging
import json
from typing import Optional, Callable, Any, Dict
from web3 import Web3
from web3.exceptions import Web3Exception
from web3.contract import Contract
from compound_assistant.config.contracts import (
    MESSAGE_MANAGER_ABI,
    get_contract_address,
    get_rpc_url
)

logger = logging.getLogger(__name__)


class MessageEventListener:
    """Listens for MessagePaid events and processes them."""
    
    def __init__(
        self,
        network_id: int,
        private_key: str,
        message_processor: Callable[[Dict[str, Any]], None],
        websocket_broadcaster: Optional[Callable[[str], None]] = None
    ):
        self.network_id = network_id
        self.private_key = private_key
        self.message_processor = message_processor
        self.websocket_broadcaster = websocket_broadcaster
        self.w3: Optional[Web3] = None
        self.contract: Optional[Contract] = None
        self.account = None
        self.running = False
        
    async def initialize(self):
        """Initialize Web3 connection and contract."""
        try:
            rpc_url = get_rpc_url(self.network_id)
            if not rpc_url:
                raise ValueError(f"No RPC URL configured for network {self.network_id}")
            
            logger.info(f"Connecting to network {self.network_id} at {rpc_url}")
            self.w3 = Web3(Web3.HTTPProvider(rpc_url))
            
            if not self.w3.is_connected():
                raise ConnectionError(f"Failed to connect to {rpc_url}")
            
            # Initialize account for making transactions
            self.account = self.w3.eth.account.from_key(self.private_key)
            logger.info(f"Initialized account: {self.account.address}")
            
            # Get contract
            contract_address = get_contract_address(self.network_id, "MESSAGE_MANAGER")
            if contract_address == "0x0000000000000000000000000000000000000000":
                raise ValueError(f"MessageManager contract address not configured for network {self.network_id}")
            
            self.contract = self.w3.eth.contract(
                address=contract_address,
                abi=MESSAGE_MANAGER_ABI
            )
            
            logger.info(f"Initialized MessageManager contract at {contract_address}")
            
        except Exception as e:
            logger.error(f"Failed to initialize event listener: {e}")
            raise
    
    async def start_listening(self):
        """Start listening for MessagePaid events."""
        if not self.w3 or not self.contract:
            await self.initialize()
        
        self.running = True
        logger.info("Starting event listener for MessagePaid events...")
        
        # Create event filter for MessagePaid events
        try:
            event_filter = self.contract.events.MessagePaid.create_filter(fromBlock='latest')
            
            while self.running:
                try:
                    # Poll for new events
                    new_events = event_filter.get_new_entries()
                    
                    for event in new_events:
                        await self._handle_message_paid_event(event)
                    
                    # Sleep to avoid excessive polling
                    await asyncio.sleep(5)
                    
                except Exception as e:
                    logger.error(f"Error polling for events: {e}")
                    await asyncio.sleep(10)  # Wait longer on error
                    
        except Exception as e:
            logger.error(f"Failed to start event listener: {e}")
            raise
    
    async def _handle_message_paid_event(self, event):
        """Handle a MessagePaid event."""
        try:
            # Extract event data
            sig_hash = event.args.sigHash.hex()
            payer = event.args.payer
            message_uri = event.args.messageURI
            message_hash = event.args.messageHash.hex()
            user_mint = event.args.userMint
            dev_mint = event.args.devMint
            
            logger.info(f"Received MessagePaid event - sigHash: {sig_hash}, payer: {payer}")
            
            # Process the message
            message_data = {
                'sigHash': sig_hash,
                'payer': payer,
                'messageURI': message_uri,
                'messageHash': message_hash,
                'userMint': user_mint,
                'devMint': dev_mint,
                'blockNumber': event.blockNumber,
                'transactionHash': event.transactionHash.hex()
            }
            
            # Call the message processor
            await self._process_paid_message(message_data)
            
        except Exception as e:
            logger.error(f"Error handling MessagePaid event: {e}")
    
    async def _process_paid_message(self, message_data: Dict[str, Any]):
        """Process a paid message and call markMessageProcessed."""
        try:
            sig_hash_bytes = bytes.fromhex(message_data['sigHash'].replace('0x', ''))
            
            # Extract the actual message from messageURI
            # For now, we'll assume messageURI contains the message text
            # In a real implementation, this might be an IPFS hash or URL
            message_text = message_data['messageURI']
            
            logger.info(f"Processing paid message: {message_text[:100]}...")
            
            # Process the message using the existing message processor
            # We need to simulate the message processing that normally happens via WebSocket
            response_data = await self._simulate_agent_processing(message_text, message_data['payer'])
            
            # Mark message as processed on-chain
            await self._mark_message_processed(sig_hash_bytes)
            
            # Broadcast response if we have a broadcaster
            if self.websocket_broadcaster and response_data:
                await self._broadcast_response(response_data, message_data)
                
            logger.info(f"Successfully processed message with sigHash: {message_data['sigHash']}")
            
        except Exception as e:
            logger.error(f"Error processing paid message: {e}")
    
    async def _simulate_agent_processing(self, message_text: str, payer: str) -> Optional[str]:
        """Simulate processing the message through the agent."""
        try:
            # This would call the same agent processing logic used in the WebSocket handler
            # For now, return a simple response
            # TODO: Integrate with the actual agent processing from server.py
            
            logger.info(f"Agent processing message from {payer}: {message_text}")
            
            # Call the message processor if available
            if self.message_processor:
                result = await asyncio.to_thread(self.message_processor, {
                    'message': message_text,
                    'payer': payer
                })
                return result
            
            return f"Processed message: {message_text[:50]}..."
            
        except Exception as e:
            logger.error(f"Error in agent processing: {e}")
            return None
    
    async def _mark_message_processed(self, sig_hash_bytes: bytes):
        """Call markMessageProcessed on the contract."""
        try:
            # Build transaction
            function_call = self.contract.functions.markMessageProcessed(sig_hash_bytes)
            
            # Get transaction details
            gas_estimate = function_call.estimate_gas({'from': self.account.address})
            gas_price = self.w3.eth.gas_price
            
            transaction = function_call.build_transaction({
                'from': self.account.address,
                'gas': gas_estimate,
                'gasPrice': gas_price,
                'nonce': self.w3.eth.get_transaction_count(self.account.address),
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.private_key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.rawTransaction)
            
            # Wait for transaction confirmation
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            if receipt.status == 1:
                logger.info(f"Successfully marked message as processed. TX: {tx_hash.hex()}")
            else:
                logger.error(f"Transaction failed: {tx_hash.hex()}")
                
        except Exception as e:
            logger.error(f"Error marking message as processed: {e}")
            raise
    
    async def _broadcast_response(self, response_data: str, message_data: Dict[str, Any]):
        """Broadcast the agent response to connected WebSocket clients."""
        if not self.websocket_broadcaster:
            return
            
        try:
            broadcast_data = {
                "type": "agent",
                "content": response_data,
                "payer": message_data['payer'],
                "sigHash": message_data['sigHash'],
                "source": "event_driven"
            }
            
            await asyncio.to_thread(self.websocket_broadcaster, json.dumps(broadcast_data))
            
        except Exception as e:
            logger.error(f"Error broadcasting response: {e}")
    
    def stop(self):
        """Stop the event listener."""
        self.running = False
        logger.info("Stopping event listener...")