"""Handler for MessagePaid events."""

import json
import logging
from typing import Dict, Any, List, Optional
from langchain_core.messages import HumanMessage

logger = logging.getLogger(__name__)


class MessageEventHandler:
    """Handles MessagePaid events and processes messages with the agent."""
    
    def __init__(self, agent, event_listener, websocket_manager=None):
        """Initialize the message event handler.
        
        Args:
            agent: The LangChain agent for processing messages
            event_listener: EventListener instance for blockchain interactions
            websocket_manager: Optional WebSocket manager for broadcasting responses
        """
        self.agent = agent
        self.event_listener = event_listener
        self.websocket_manager = websocket_manager
        self.thread_id = "Compound Assistant"
        
    async def handle_message_paid_event(self, event_data: Dict[str, Any]):
        """Handle a MessagePaid event.
        
        Args:
            event_data: Event data containing messageHash, payer, etc.
        """
        message_hash = event_data["messageHash"]
        payer = event_data["payer"]
        
        logger.info(f"🎯 Processing MessagePaid event for hash: {message_hash}")
        logger.info(f"👤 Payer: {payer}")
        
        try:
            # Step 1: Get the message content from the contract
            message_content = await self.event_listener.get_message_content(message_hash)
            
            if not message_content:
                logger.error(f"❌ No message content found for hash: {message_hash}")
                return await self._mark_processed_and_notify(message_hash, error="Message content not found")
            
            logger.info(f"📨 Retrieved message: {message_content[:100]}{'...' if len(message_content) > 100 else ''}")
            
            # Step 2: Process the message with the agent
            await self._process_message_with_agent(message_content, message_hash, payer)
            
        except Exception as e:
            logger.error(f"❌ Error processing MessagePaid event {message_hash}: {e}")
            await self._mark_processed_and_notify(message_hash, error=str(e))
    
    async def _process_message_with_agent(self, message_content: str, message_hash: str, payer: str):
        """Process the message content with the agent.
        
        Args:
            message_content: The message content to process
            message_hash: Hash of the message
            payer: Address of the message payer
        """
        try:
            # Create config with thread ID for persistence
            config = {"configurable": {"thread_id": self.thread_id}}
            
            # Send initial processing notification
            await self._broadcast_to_websockets({
                "type": "message_received",
                "messageHash": message_hash,
                "payer": payer,
                "content": message_content
            })
            
            logger.info(f"🤖 Starting agent processing for message: {message_hash}")
            
            # Process message with agent using the same logic as before
            response_sent = False
            for chunk in self.agent.stream(
                {"messages": [HumanMessage(content=message_content)]}, 
                config
            ):
                if "agent" in chunk:
                    # Handle agent responses
                    agent_message = chunk["agent"]["messages"][0]
                    tool_calls = agent_message.additional_kwargs.get("tool_calls", [])
                    
                    # Send tool calls to clients
                    if tool_calls:
                        for tool_call in tool_calls:
                            tool_type = tool_call.get("function", {}).get("name", "Unknown tool")
                            
                            # Extract arguments
                            args = tool_call.get("function", {}).get("arguments", "{}")
                            try:
                                args_dict = json.loads(args)
                                if "__arg1" in args_dict:
                                    content = args_dict["__arg1"]
                                else:
                                    content = json.dumps(args_dict, indent=2)
                            except:
                                content = args
                            
                            await self._broadcast_to_websockets({
                                "type": "tool_call",
                                "messageHash": message_hash,
                                "tool": tool_type,
                                "content": content
                            })
                    
                    # Send agent response
                    if agent_message.content:
                        await self._broadcast_to_websockets({
                            "type": "agent",
                            "messageHash": message_hash,
                            "content": agent_message.content
                        })
                        response_sent = True
                
                elif "tools" in chunk:
                    # Send tool results
                    await self._broadcast_to_websockets({
                        "type": "tool",
                        "messageHash": message_hash,
                        "content": chunk["tools"]["messages"][0].content
                    })
            
            logger.info(f"✅ Agent processing completed for message: {message_hash}")
            
            # Mark as processed regardless of success or failure
            await self._mark_processed_and_notify(message_hash, success=True)
            
        except Exception as e:
            logger.error(f"❌ Error in agent processing for message {message_hash}: {e}")
            await self._mark_processed_and_notify(message_hash, error=str(e))
    
    async def _mark_processed_and_notify(self, message_hash: str, success: bool = False, error: Optional[str] = None):
        """Mark message as processed on the blockchain and notify clients.
        
        Args:
            message_hash: Hash of the message to mark as processed
            success: Whether processing was successful
            error: Error message if processing failed
        """
        try:
            # Get agent address
            agent_address = self.event_listener.w3.eth.default_account
            if not agent_address:
                # Try to get from environment
                import os
                private_key = os.getenv("PRIVATE_KEY")
                if private_key:
                    account = self.event_listener.w3.eth.account.from_key(private_key)
                    agent_address = account.address
                else:
                    logger.error("❌ No agent address available for marking message as processed")
                    return
            
            # Mark message as processed on the blockchain
            processed = await self.event_listener.mark_message_processed(message_hash, agent_address)
            
            # Notify clients about completion
            notification = {
                "type": "processing_complete",
                "messageHash": message_hash,
                "success": success,
                "markedProcessed": processed
            }
            
            if error:
                notification["error"] = error
            
            await self._broadcast_to_websockets(notification)
            
            if processed:
                logger.info(f"✅ Message {message_hash} marked as processed on blockchain")
            else:
                logger.error(f"❌ Failed to mark message {message_hash} as processed on blockchain")
                
        except Exception as e:
            logger.error(f"❌ Error marking message {message_hash} as processed: {e}")
    
    async def _broadcast_to_websockets(self, message: Dict[str, Any]):
        """Broadcast a message to all connected WebSocket clients.
        
        Args:
            message: Message to broadcast
        """
        if self.websocket_manager:
            try:
                message_json = json.dumps(message)
                # Broadcast to all connected clients
                for websocket in self.websocket_manager.active_connections:
                    try:
                        await self.websocket_manager.send_message(message_json, websocket)
                    except Exception as e:
                        logger.warning(f"⚠️ Failed to send message to WebSocket client: {e}")
            except Exception as e:
                logger.error(f"❌ Error broadcasting to WebSockets: {e}")
        else:
            logger.debug("🔇 No WebSocket manager available for broadcasting")
