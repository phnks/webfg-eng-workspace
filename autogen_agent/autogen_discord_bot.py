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
        'model': 'gpt-4', # Or another model like gpt-3.5-turbo
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
   max_consecutive_auto_reply=5,
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

                # Define a function to capture the last message
                last_message_content = None
                def capture_last_message_hook(recipient, messages, sender, config):
                    nonlocal last_message_content
                    if messages and isinstance(messages, list):
                         # Get the last message dictionary
                        last_msg = messages[-1]
                        # Extract content, handle potential None or missing 'content'
                        content = last_msg.get('content')
                        if content:
                            last_message_content = str(content).strip()
                        else:
                             # Handle cases where content might be missing or different structure
                            last_message_content = f"Received a message structure without standard content: {last_msg}"
                    elif isinstance(messages, str): # Sometimes messages might be simple strings
                        last_message_content = messages.strip()

                    print(f"DEBUG: Hook captured message from {sender.name}: {last_message_content}") # Debug print
                    return False, None # Return False to continue the conversation, None indicates no reply from hook


                # Register the hook - this might capture intermediate messages too.
                # A better approach might be needed depending on AutoGen's flow.
                # Let's try registering it on the user_proxy to see what it gets before termination.
                user_proxy.register_reply(
                    [autogen.Agent, None], # Triggered by messages from any agent or termination
                    reply_func=capture_last_message_hook,
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
                if last_message_content:
                    print(f"Sending response to Discord: {last_message_content}")
                    # Discord has a message length limit (2000 characters)
                    if len(last_message_content) > 2000:
                        await message.channel.send("The response is too long to display completely.")
                        # Send in chunks or as a file if needed
                        parts = [last_message_content[i:i+1990] for i in range(0, len(last_message_content), 1990)]
                        for part in parts:
                            await message.channel.send(f"```{part}```") # Send as code block for readability
                    else:
                        await message.channel.send(last_message_content)
                else:
                    print("No response captured from AutoGen.")
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
