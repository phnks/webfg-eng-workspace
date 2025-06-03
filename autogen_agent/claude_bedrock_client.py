# filename: claude_bedrock_client.py
"""
Claude Bedrock Client
────────────────────
Implements a client for AWS Bedrock Claude models that follows the AutoGen client interface.
Supports all Claude models available in AWS Bedrock with separate AWS credentials for Bedrock access.
"""

from __future__ import annotations
import json
import logging
import os
import re
import time
from typing import Any, Dict, List, Optional, Union

import boto3
from botocore.exceptions import ClientError, BotoCoreError

# Set up logging
_LOG = logging.getLogger("ClaudeBedrockClient")

class ClaudeBedrockClient:
    """
    AWS Bedrock Claude client that implements the AutoGen LLM client interface.
    Uses separate AWS credentials for Bedrock access, independent of project AWS credentials.
    """

    # Claude model IDs available in AWS Bedrock
    MODEL_IDS = {
        "claude-3-haiku": "anthropic.claude-3-haiku-20240307-v1:0",
        "claude-3-sonnet": "anthropic.claude-3-sonnet-20240229-v1:0", 
        "claude-3-opus": "anthropic.claude-3-opus-20240229-v1:0",
        "claude-3-5-sonnet": "anthropic.claude-3-5-sonnet-20240620-v1:0",
        "claude-3-5-sonnet-v2": "anthropic.claude-3-5-sonnet-20241022-v2:0",
        "claude-opus-4": "anthropic.claude-opus-4-20250514-v1:0",
        # Add new models as they become available
    }

    def __init__(
        self,
        model: str = "claude-opus-4",
        api_key: Optional[str] = None,  # Not used but kept for interface compatibility
        **kwargs
    ):
        """
        Initialize Claude Bedrock client.
        
        Args:
            model: Claude model name (e.g., "claude-opus-4", "claude-3-sonnet")
            api_key: Not used (kept for AutoGen compatibility)
            **kwargs: Additional parameters
        """
        self.model = model
        self._setup_bedrock_client()
        
        # Get full model ID from model name
        if model in self.MODEL_IDS:
            self.model_id = self.MODEL_IDS[model]
        else:
            # If it's already a full model ID, use it directly
            if model.startswith("anthropic.claude"):
                self.model_id = model
            else:
                # Default to Claude Opus 4
                _LOG.warning(f"Unknown model '{model}', defaulting to claude-opus-4")
                self.model_id = self.MODEL_IDS["claude-opus-4"]
        
        _LOG.info(f"✅ Claude Bedrock client initialized with model: {model} -> {self.model_id}")

    def _setup_bedrock_client(self):
        """Set up AWS Bedrock client using separate credentials."""
        try:
            # Use separate AWS credentials for Bedrock access
            bedrock_access_key = os.getenv("BEDROCK_AWS_ACCESS_KEY_ID")
            bedrock_secret_key = os.getenv("BEDROCK_AWS_SECRET_ACCESS_KEY")
            bedrock_region = os.getenv("BEDROCK_AWS_REGION", "us-west-2")
            
            if not bedrock_access_key or not bedrock_secret_key:
                # Fallback to default AWS credentials if Bedrock-specific ones aren't set
                _LOG.warning("⚠️ BEDROCK_AWS_ACCESS_KEY_ID or BEDROCK_AWS_SECRET_ACCESS_KEY not set. "
                           "Falling back to default AWS credentials.")
                self.bedrock_runtime = boto3.client("bedrock-runtime", region_name=bedrock_region)
            else:
                self.bedrock_runtime = boto3.client(
                    "bedrock-runtime",
                    aws_access_key_id=bedrock_access_key,
                    aws_secret_access_key=bedrock_secret_key,
                    region_name=bedrock_region
                )
                
            # Test the connection
            self._test_connection()
            _LOG.info("✅ AWS Bedrock client initialized successfully")
            
        except Exception as e:
            _LOG.error(f"❌ Failed to initialize AWS Bedrock client: {e}")
            raise RuntimeError(f"Failed to initialize AWS Bedrock client: {e}")

    def _test_connection(self):
        """Test the Bedrock connection by listing available models."""
        try:
            # Try to list foundation models to test connection
            response = self.bedrock_runtime.list_foundation_models()
            claude_models = [
                model for model in response.get("modelSummaries", [])
                if "claude" in model.get("modelId", "").lower()
            ]
            _LOG.debug(f"Found {len(claude_models)} Claude models in Bedrock")
        except Exception as e:
            _LOG.error(f"Bedrock connection test failed: {e}")
            raise

    def create(self, params: Dict[str, Any]) -> Any:
        """
        Create a chat completion using Claude via AWS Bedrock.
        
        Args:
            params: Parameters including messages, temperature, etc.
            
        Returns:
            Response in AutoGen-compatible format
        """
        try:
            messages = params.get("messages", [])
            temperature = params.get("temperature", 0.7)
            max_tokens = params.get("max_tokens", 4000)
            
            # Convert messages to Claude format
            claude_messages = self._convert_messages(messages)
            
            # Prepare request body for Bedrock
            request_body = {
                "anthropic_version": "bedrock-2023-05-31",
                "messages": claude_messages,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "top_k": 250,
                "top_p": 0.999,
                "stop_sequences": []
            }
            
            # Add system message if present
            system_message = self._extract_system_message(messages)
            if system_message:
                request_body["system"] = system_message
            
            _LOG.debug(f"Invoking Claude model {self.model_id}")
            
            # Call Bedrock
            response = self.bedrock_runtime.invoke_model(
                modelId=self.model_id,
                contentType="application/json",
                accept="application/json", 
                body=json.dumps(request_body)
            )
            
            # Parse response
            response_body = json.loads(response["body"].read())
            
            # Convert to AutoGen format
            return self._convert_response(response_body)
            
        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "Unknown")
            error_message = e.response.get("Error", {}).get("Message", str(e))
            _LOG.error(f"❌ AWS Bedrock error ({error_code}): {error_message}")
            raise RuntimeError(f"AWS Bedrock error ({error_code}): {error_message}")
            
        except Exception as e:
            _LOG.error(f"❌ Claude Bedrock client error: {e}")
            raise RuntimeError(f"Claude Bedrock client error: {e}")

    def _convert_messages(self, messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Convert AutoGen messages to Claude format."""
        claude_messages = []
        
        for msg in messages:
            role = msg.get("role", "")
            content = msg.get("content", "")
            
            # Skip system messages (handled separately)
            if role == "system":
                continue
                
            # Map roles
            if role == "assistant":
                claude_role = "assistant"
            elif role == "user":
                claude_role = "user"
            else:
                # Default unknown roles to user
                claude_role = "user"
            
            # Format content
            if isinstance(content, str):
                claude_content = [{"type": "text", "text": content}]
            else:
                # If content is already in Claude format, use as-is
                claude_content = content
            
            claude_messages.append({
                "role": claude_role,
                "content": claude_content
            })
        
        return claude_messages

    def _extract_system_message(self, messages: List[Dict[str, Any]]) -> Optional[str]:
        """Extract system message from messages list."""
        for msg in messages:
            if msg.get("role") == "system":
                return msg.get("content", "")
        return None

    def _convert_response(self, response_body: Dict[str, Any]) -> Dict[str, Any]:
        """Convert Claude response to AutoGen format."""
        try:
            # Extract content from Claude response
            content_blocks = response_body.get("content", [])
            if not content_blocks:
                raise ValueError("No content in Claude response")
                
            # Combine all text content
            text_content = ""
            for block in content_blocks:
                if block.get("type") == "text":
                    text_content += block.get("text", "")
            
            # Create AutoGen-compatible response
            autogen_response = {
                "choices": [{
                    "message": {
                        "role": "assistant",
                        "content": text_content
                    },
                    "finish_reason": self._map_stop_reason(response_body.get("stop_reason"))
                }],
                "model": self.model,
                "usage": {
                    "prompt_tokens": response_body.get("usage", {}).get("input_tokens", 0),
                    "completion_tokens": response_body.get("usage", {}).get("output_tokens", 0),
                    "total_tokens": (
                        response_body.get("usage", {}).get("input_tokens", 0) +
                        response_body.get("usage", {}).get("output_tokens", 0)
                    )
                }
            }
            
            return autogen_response
            
        except Exception as e:
            _LOG.error(f"❌ Error converting Claude response: {e}")
            raise ValueError(f"Error converting Claude response: {e}")

    def _map_stop_reason(self, stop_reason: Optional[str]) -> str:
        """Map Claude stop reason to OpenAI format."""
        mapping = {
            "end_turn": "stop",
            "max_tokens": "length",
            "stop_sequence": "stop"
        }
        return mapping.get(stop_reason, "stop")

    def cost(self, response: Any) -> float:
        """Calculate cost for the response (placeholder for now)."""
        # AWS Bedrock pricing varies by model and token count
        # This is a placeholder - you can implement actual cost calculation
        return 0.0

    @property
    def api_key(self) -> str:
        """Return a placeholder API key for compatibility."""
        return "bedrock-claude-key"

    @api_key.setter
    def api_key(self, value: str):
        """API key setter for compatibility (no-op for Bedrock)."""
        pass