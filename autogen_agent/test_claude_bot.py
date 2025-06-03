#!/usr/bin/env python3
"""
Test script to verify the AutoGen bot works with Claude without Docker.
This creates a minimal test environment.
"""

import os
import sys
import tempfile
from pathlib import Path

# Create a temporary home directory for the test bot
temp_home = tempfile.mkdtemp(prefix="testbot_")
os.makedirs(temp_home, exist_ok=True)

# Set up environment variables
os.environ["MODEL_PROVIDER"] = "claude"
os.environ["MODEL_NAME"] = "claude-3-5-sonnet-v2"
os.environ["BOT_USER"] = os.environ.get("USER", "testbot")  # Use current user
os.environ["AGENT_HOME"] = str(Path(__file__).parent)

# Load environment from .env file
from dotenv import load_dotenv
load_dotenv()

print("🤖 Testing AutoGen Bot with Claude")
print("=" * 50)
print(f"MODEL_PROVIDER: {os.environ.get('MODEL_PROVIDER')}")
print(f"MODEL_NAME: {os.environ.get('MODEL_NAME')}")
print(f"BEDROCK_AWS_ACCESS_KEY_ID: {os.environ.get('BEDROCK_AWS_ACCESS_KEY_ID', '')[:8]}...")
print(f"Test home directory: {temp_home}")
print()

try:
    # Import the configuration function
    from autogen_discord_bot import create_llm_config, ClaudeBedrockClient
    
    print("✅ Imports successful")
    
    # Create LLM config
    llm_config = create_llm_config()
    print(f"✅ LLM config created for model: {llm_config['config_list'][0]['model']}")
    
    # Test Claude client directly
    print("\n📝 Testing direct Claude API call...")
    client = ClaudeBedrockClient(model=llm_config['config_list'][0]['model'])
    
    test_params = {
        "messages": [
            {"role": "system", "content": "You are a helpful AI assistant."},
            {"role": "user", "content": "Say 'Claude is working!' if you can hear me."}
        ],
        "temperature": 0.7,
        "max_tokens": 50
    }
    
    response = client.create(test_params)
    
    if "choices" in response and response["choices"]:
        content = response["choices"][0]["message"]["content"]
        print(f"🤖 Claude response: {content}")
        print("✅ Claude integration is working!")
    else:
        print("❌ Unexpected response format")
        print(response)
        
    # Test AutoGen integration
    print("\n🔧 Testing AutoGen Assistant...")
    import autogen
    
    # Create a simple test assistant
    assistant = autogen.AssistantAgent(
        name="test_assistant",
        llm_config=llm_config,
        system_message="You are a helpful AI assistant using Claude."
    )
    
    # Create user proxy with minimal config
    user_proxy = autogen.UserProxyAgent(
        name="test_user",
        human_input_mode="NEVER",
        max_consecutive_auto_reply=1,
        is_termination_msg=lambda x: True,  # Terminate after one response
        code_execution_config=False  # Disable code execution for this test
    )
    
    print("✅ AutoGen agents created")
    
    # Test a simple conversation
    print("\n💬 Testing AutoGen conversation...")
    result = user_proxy.initiate_chat(
        assistant,
        message="Please respond with 'AutoGen with Claude is working!' if you receive this.",
        clear_history=True
    )
    
    print("✅ AutoGen conversation completed")
    
    # Clean up temp directory
    import shutil
    shutil.rmtree(temp_home, ignore_errors=True)
    
    print("\n🎉 All tests passed! The bot is ready to use with Claude.")
    print("\nTo run the full bot:")
    print("1. Make sure Discord bot token is configured")
    print("2. Run: ./start_agent.sh")
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()
    
    # Clean up
    import shutil
    shutil.rmtree(temp_home, ignore_errors=True)
    sys.exit(1)