"""Event listener for blockchain events."""

import asyncio
import logging
from typing import Callable, Optional, Any, Dict
from web3 import Web3
from web3.exceptions import BlockNotFound, TransactionNotFound

from compound_assistant.contracts.message_manager import MessageManagerContract

logger = logging.getLogger(__name__)


class EventListener:
    """Event listener for MessageManager contract events."""
    
    def __init__(self, w3: Web3, contract_address: str):
        """Initialize event listener.
        
        Args:
            w3: Web3 instance
            contract_address: Address of the MessageManager contract
        """
        self.w3 = w3
        self.contract = MessageManagerContract(w3, contract_address)
        self.is_listening = False
        self._event_handlers: Dict[str, Callable] = {}
        
    def add_event_handler(self, event_name: str, handler: Callable):
        """Add an event handler for a specific event.
        
        Args:
            event_name: Name of the event to handle
            handler: Callable to handle the event
        """
        self._event_handlers[event_name] = handler
        logger.info(f"📝 Added handler for {event_name} events")
    
    async def start_listening(self, poll_interval: float = 2.0):
        """Start listening for MessagePaid events.
        
        Args:
            poll_interval: How often to poll for new events (in seconds)
        """
        if self.is_listening:
            logger.warning("⚠️ Event listener is already running")
            return
        
        logger.info("🎧 Starting to listen for MessagePaid events...")
        self.is_listening = True
        
        # Create event filter
        try:
            event_filter = self.contract.create_event_filter(from_block="latest")
            logger.info("✅ Event filter created successfully")
        except Exception as e:
            logger.error(f"❌ Failed to create event filter: {e}")
            self.is_listening = False
            return
        
        # Main event listening loop
        while self.is_listening:
            try:
                # Get new events
                new_events = event_filter.get_new_entries()
                
                if new_events:
                    logger.info(f"📨 Found {len(new_events)} new MessagePaid events")
                
                for event in new_events:
                    await self._handle_message_paid_event(event)
                
                # Wait before next poll
                await asyncio.sleep(poll_interval)
                
            except BlockNotFound:
                logger.warning("⚠️ Block not found, retrying...")
                await asyncio.sleep(poll_interval)
                continue
            except Exception as e:
                logger.error(f"❌ Error in event listening loop: {e}")
                # Try to reconnect or handle gracefully
                await asyncio.sleep(poll_interval * 2)  # Wait longer on error
    
    async def _handle_message_paid_event(self, event: Any):
        """Handle a MessagePaid event.
        
        Args:
            event: The event object from Web3
        """
        try:
            # Extract event data (ensure 0x-prefixed hex string)
            raw_hash = event['args']['messageHash']
            message_hash = Web3.to_hex(raw_hash) if isinstance(raw_hash, (bytes, bytearray)) else (raw_hash if str(raw_hash).startswith("0x") else f"0x{raw_hash}")
            payer = event['args']['payer']
            user_mint = event['args']['userMint']
            dev_mint = event['args']['devMint']
            
            logger.info(f"💰 MessagePaid event received:")
            logger.info(f"   📋 Message Hash: {message_hash}")
            logger.info(f"   👤 Payer: {payer}")
            logger.info(f"   🪙 User Mint: {user_mint}")
            logger.info(f"   💼 Dev Mint: {dev_mint}")
            
            # Check if we have a handler for MessagePaid events
            if "MessagePaid" in self._event_handlers:
                handler = self._event_handlers["MessagePaid"]
                await handler({
                    "messageHash": message_hash,
                    "payer": payer,
                    "userMint": user_mint,
                    "devMint": dev_mint,
                    "blockNumber": event['blockNumber'],
                    "transactionHash": event['transactionHash'].hex()
                })
            else:
                logger.warning("⚠️ No handler registered for MessagePaid events")
                
        except Exception as e:
            logger.error(f"❌ Error handling MessagePaid event: {e}")
            logger.error(f"Event data: {event}")
    
    def stop_listening(self):
        """Stop listening for events."""
        if self.is_listening:
            logger.info("🛑 Stopping event listener...")
            self.is_listening = False
        else:
            logger.info("ℹ️ Event listener is not currently running")
    
    async def get_message_content(self, message_hash: str) -> Optional[str]:
        """Get message content from the contract.
        
        Args:
            message_hash: Hash of the message to retrieve
            
        Returns:
            Message content if found, None otherwise
        """
        try:
            message = self.contract.get_paid_message(message_hash)
            if message:
                logger.info(f"📖 Retrieved message content for hash {message_hash}")
                return message
            else:
                logger.warning(f"⚠️ No message found for hash {message_hash}")
                return None
        except Exception as e:
            logger.error(f"❌ Error retrieving message for hash {message_hash}: {e}")
            return None
    
    async def mark_message_processed(self, message_hash: str, agent_address: str) -> bool:
        """Mark a message as processed on the contract.
        
        Args:
            message_hash: Hash of the message to mark as processed
            agent_address: Address of the agent account
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Get the private key for signing
            import os
            private_key = os.getenv("PRIVATE_KEY")
            if not private_key:
                logger.error("❌ PRIVATE_KEY not found in environment variables")
                return False
            
            # Build transaction
            tx = self.contract.mark_message_processed(message_hash, agent_address)
            
            # Sign and send transaction
            signed_tx = self.w3.eth.account.sign_transaction(tx, private_key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_tx.raw_transaction)
            
            logger.info(f"📤 Sent markMessageProcessed transaction: {tx_hash.hex()}")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
            
            if receipt.status == 1:
                logger.info(f"✅ Message {message_hash} marked as processed successfully")
                return True
            else:
                logger.error(f"❌ Transaction failed for message {message_hash}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Error marking message {message_hash} as processed: {e}")
            return False
