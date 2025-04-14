import autogen
import discord
import os
import asyncio
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# --- Basic Input Validation ---
if not DISCORD_BOT_TOKEN:
    print("Error: DISCORD_BOT_TOKEN not found in .env file.")
    exit(1)
if not OPENAI_API_KEY:
    print("Error: OPENAI_API_KEY not found in .env file.")
    # AutoGen might still work with a local model if configured,
    # but for OpenAI integration, this is needed.
    # We'll proceed but log a warning.
    print("Warning: OPENAI_API_KEY not found. OpenAI features will be unavailable unless configured otherwise.")
    # For now, let's assume we need OpenAI and exit if not found for simplicity in this initial setup.
    # If you have a different LLM config, adjust this check.
    exit(1)


# --- AutoGen Configuration ---
config_list = [
    {
        'model': 'gpt-3.5-turbo', # Changed from gpt-4 as per user request
        'api_key': OPENAI_API_KEY,
    }
]

llm_config = {
    "config_list": config_list,
    "cache_seed": 42, # Use None for no caching
    "temperature": 0.7,
}

# --- AutoGen Agents ---
# Assistant Agent: The AI that performs tasks
assistant = autogen.AssistantAgent(
    name="assistant",
    llm_config=llm_config,
    system_message="You are a helpful AI assistant. Respond to the user's query."
)

# User Proxy Agent: Represents the user, initiates chat, and can execute code
# We need a way to capture the final response to send back to Discord.
# We'll modify how the chat is initiated or use a custom agent later if needed.
# For now, the Discord bot will handle getting the response.
user_proxy = autogen.UserProxyAgent(
   name="user_proxy",
   human_input_mode="NEVER", # No human intervention needed in this setup
   max_consecutive_auto_reply=8, # Increased from 5
   is_termination_msg=lambda x: x.get("content", "").rstrip().endswith("TERMINATE"),
   code_execution_config=False, # Disable code execution for safety unless needed
   # llm_config=llm_config, # Optional: User proxy can also use LLM
   # system_message="""Reply TERMINATE if the task has been solved at full satisfaction. Otherwise, reply CONTINUE, or the reason why the task is not solved yet."""
)


# --- Discord Bot Setup ---
intents = discord.Intents.default()
intents.message_content = True # Enable message content intent
client = discord.Client(intents=intents)

# Dictionary to store active conversations per channel
# Key: channel_id, Value: asyncio.Lock to prevent concurrent processing
channel_locks = {}

@client.event
async def on_ready():
    print(f'Logged in as {client.user}')
    print('------')
    print(f'Discord.py version: {discord.__version__}')
    print('Bot is ready and listening for messages.')

@client.event
async def on_message(message):
    # Ignore messages from the bot itself
    if message.author == client.user:
        return

    # Only respond to direct mentions or messages in specific channels (optional)
    # For simplicity, let's respond to any message in any channel the bot is in.
    # Add channel/mention checks here if needed.

    print(f"Received message from {message.author} in #{message.channel}: {message.content}")

    # --- Prevent Concurrent Processing per Channel ---
    lock = channel_locks.get(message.channel.id)
    if lock is None:
        lock = asyncio.Lock()
        channel_locks[message.channel.id] = lock

    if lock.locked():
        await message.channel.send("I'm currently processing another request in this channel. Please wait a moment.")
        return

    async with lock:
        try:
            # Show typing indicator
            async with message.channel.typing():
                # --- Initiate AutoGen Chat ---
                # We need a way to capture the response from the AutoGen conversation.
                # One way is to create a temporary custom agent or modify the user_proxy
                # to store the last message, or parse the chat history.

                # Let's try initiating the chat and capturing the last message.
                chat_history = [] # Store conversation history if needed

                # Define a function to capture the *first* assistant message
                # We need a flag or check within the scope of the on_message handler
                # to ensure we only capture the first relevant reply.
                # Let's reset this variable for each new Discord message received.
                first_assistant_message_captured = None

                def capture_first_assistant_message_hook(recipient, messages, sender, config):
                    nonlocal first_assistant_message_captured
                    # Only capture if it's from the assistant and we haven't captured one yet for this interaction
                    if sender.name == assistant.name and first_assistant_message_captured is None:
                        if messages and isinstance(messages, list):
                            # Get the last message dictionary (which is the current message being processed by the hook)
                            current_msg = messages[-1]
                            # Extract content, handle potential None or missing 'content'
                            content = current_msg.get('content')
                            if content:
                                first_assistant_message_captured = str(content).strip()
                                print(f"DEBUG: Hook captured FIRST message from {sender.name}: {first_assistant_message_captured}") # Debug print
                            else:
                                # Handle cases where content might be missing or different structure
                                first_assistant_message_captured = f"Received a message structure without standard content: {current_msg}"
                                print(f"DEBUG: Hook captured FIRST message structure (no content) from {sender.name}: {first_assistant_message_captured}") # Debug print
                        elif isinstance(messages, str): # Sometimes messages might be simple strings
                            first_assistant_message_captured = messages.strip()
                            print(f"DEBUG: Hook captured FIRST message (string) from {sender.name}: {first_assistant_message_captured}") # Debug print

                    # Still print subsequent messages for debugging, but don't overwrite the captured one
                    elif sender.name == assistant.name:
                         current_content = messages[-1].get('content') if isinstance(messages, list) else messages
                         print(f"DEBUG: Hook saw SUBSEQUENT message from {sender.name}: {str(current_content).strip()}")

                    return False, None # Return False to continue the conversation, None indicates no reply from hook


                # Register the hook - this might capture intermediate messages too.
                # A better approach might be needed depending on AutoGen's flow.
                # Let's try registering it on the user_proxy to see what it gets before termination.
                user_proxy.register_reply(
                    [autogen.Agent, None], # Triggered by messages from any agent or termination
                    reply_func=capture_first_assistant_message_hook, # Use the new hook function
                    config={}, # No specific config needed for this hook
                    reset_config=False, # Keep the hook registered
                )


                print(f"Initiating AutoGen chat for: {message.content}")
                # Initiate the chat between user_proxy and assistant
                user_proxy.initiate_chat(
                    assistant,
                    message=message.content,
                    # clear_history=True # Start fresh for each Discord message
                )
                print(f"AutoGen chat finished.")

                # Unregister hook after chat (optional, depends if you want it persistent)
                # user_proxy.reset() # Resets hooks and other state

                # --- Send Response Back to Discord ---
                # Use the variable that captured the *first* assistant message
                if first_assistant_message_captured:
                    print(f"Attempting to send final captured response to Discord channel {message.channel.id}: '{first_assistant_message_captured}'") # Use the correct variable
                    # Discord has a message length limit (2000 characters)
                    if len(first_assistant_message_captured) > 2000:
                        print(f"Response length ({len(first_assistant_message_captured)}) exceeds 2000 chars. Sending preamble.")
                        await message.channel.send("The response is too long to display completely.")
                        # Send in chunks or as a file if needed
                        parts = [first_assistant_message_captured[i:i+1990] for i in range(0, len(first_assistant_message_captured), 1990)]
                        for i, part in enumerate(parts):
                            print(f"Sending part {i+1}/{len(parts)} of long response.")
                            await message.channel.send(f"```{part}```") # Send as code block for readability
                    else:
                        print(f"Sending short response (length {len(first_assistant_message_captured)}).")
                        await message.channel.send(first_assistant_message_captured) # Use the correct variable
                    print("Finished sending response to Discord.")
                else:
                    print("No first assistant response captured from AutoGen hook to send.") # Updated log message
                    await message.channel.send("Sorry, I couldn't generate a response for that.")

        except Exception as e:
            print(f"An error occurred: {e}")
            await message.channel.send(f"An error occurred while processing your request: {e}")
        finally:
            # Ensure lock is released even if errors occur (though `async with` handles this)
            # Lock is automatically released by `async with`
            pass


# --- Run the Bot ---
if __name__ == "__main__":
    if DISCORD_BOT_TOKEN and OPENAI_API_KEY: # Only run if keys are present
        print("Starting Discord bot...")
        client.run(DISCORD_BOT_TOKEN)
    else:
        print("Bot cannot start due to missing API keys in .env file.")
