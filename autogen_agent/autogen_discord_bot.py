import autogen
import discord
import os
import asyncio
import traceback # Ensure traceback is imported once
import logging
from dotenv import load_dotenv
# Removed duplicate imports
# from gemini_client_wrapper import GeminiClientWrapper # Removed custom wrapper import
import pprint # For pretty printing dicts
# Using official Autogen Google Gemini integration

# Configure logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()
DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
USE_GEMINI_STR = os.getenv("USE_GEMINI", "false").lower()
USE_GEMINI = USE_GEMINI_STR == "true"

logger.debug(f"USE_GEMINI evaluated to: {USE_GEMINI}")

# --- Basic Input Validation ---
if not DISCORD_BOT_TOKEN:
    logger.error("Error: DISCORD_BOT_TOKEN not found.")
    exit(1)
if USE_GEMINI and not GEMINI_API_KEY:
    logger.error("Error: USE_GEMINI is true, but GEMINI_API_KEY not found.")
    exit(1)
if not USE_GEMINI and not OPENAI_API_KEY:
    logger.error("Error: USE_GEMINI is false, but OPENAI_API_KEY not found.")
    exit(1)

# --- LLM Configuration Selection ---
# Define all potential configurations in a list, similar to OAI_CONFIG_LIST structure
# Ensure API keys are present before defining the list
all_configs = []
if OPENAI_API_KEY:
    all_configs.append({
        'model': 'gpt-3.5-turbo',
        'api_key': OPENAI_API_KEY,
        # 'api_type': 'openai' # Optional, default is openai
    })
if GEMINI_API_KEY:
    all_configs.append({
        'model': 'gemini-1.5-pro-latest', # Or 'gemini-pro' based on availability/preference
        'api_key': GEMINI_API_KEY,
        'api_type': 'google'
    })
# Add other models like vision or dalle if needed in the future

# Select the appropriate config list based on the USE_GEMINI flag
final_config_list = []
if USE_GEMINI:
    logger.info("Selecting Gemini LLM config.")
    gemini_config = next((config for config in all_configs if config.get('api_type') == 'google'), None)
    if not gemini_config:
        logger.error("USE_GEMINI is true, but no Gemini configuration found in all_configs!")
        exit(1)
    final_config_list = [gemini_config] # Use ONLY the Gemini config
    llm_config = {
        "config_list": final_config_list,
        "cache_seed": 43, # Consistent seed for caching
        "temperature": 0.7,
    }
    logger.debug(f"Using Gemini LLM config:\n{pprint.pformat(llm_config)}")
else:
    logger.info("Selecting OpenAI LLM config.")
    openai_config = next((config for config in all_configs if config.get('api_type', 'openai') == 'openai'), None)
    if not openai_config:
        logger.error("USE_GEMINI is false, but no OpenAI configuration found in all_configs!")
        exit(1)
    final_config_list = [openai_config] # Use ONLY the OpenAI config
    llm_config = {
        "config_list": final_config_list,
        "cache_seed": 42, # Consistent seed for caching
        "temperature": 0.7,
    }
    logger.debug(f"Using OpenAI LLM config:\n{pprint.pformat(llm_config)}")


# --- AutoGen Agents Initialization ---
assistant = None
user_proxy = None

try:
    logger.info(f"Initializing AssistantAgent with config: {llm_config}")
    assistant = autogen.AssistantAgent(
        name="assistant",
        llm_config=llm_config, # Pass the chosen config
        system_message="You are a helpful AI assistant. Generate code or text as requested. If the request involves creating a file (like HTML), provide the complete code within a single markdown code block (e.g., ```html ... ```). The user proxy agent will handle saving the file and terminating the conversation."
    )
    logger.info(f"AssistantAgent initialized successfully using config: {llm_config}")
    # No need to register client separately when using api_type='google'

except Exception as e:
    logger.error(f"Error initializing AssistantAgent or registering client: {e}")
    traceback.print_exc()
    exit(1)

try:
    logger.info("Initializing UserProxyAgent.")
    user_proxy = autogen.UserProxyAgent(
       name="user_proxy",
       human_input_mode="NEVER",
       max_consecutive_auto_reply=8,
       is_termination_msg=lambda x: x.get("content", "").rstrip() == "TERMINATE",
       code_execution_config={
           "work_dir": "coding",
           "use_docker": False, # IMPORTANT: Ensure this is False if not using Docker
       },
       # Corrected system message to focus on saving, not executing HTML
       system_message="""You are a user proxy agent. Your primary goal is to save code provided by the assistant to a file.
When you receive a message containing a single markdown code block (e.g., ```<language> ... ```) from the assistant:
1. Extract the complete code content within the block (inside the ```). Ignore the language tag (like ```html).
2. Determine an appropriate filename. If the language tag is 'html' or the content looks like HTML, use 'congrats_esther.html'. Otherwise, default to 'output.txt'.
3. Ensure the './coding/' directory exists. You can use a shell command like `mkdir -p coding`.
4. **Save the extracted code to the file** in the './coding/' directory using the determined filename. Use a shell command suitable for saving multi-line text, like `printf '%s' "[code_content]" > ./coding/[filename]`. Make sure to handle potential special characters in the code content correctly within the shell command.
5. After successfully saving the file, reply with ONLY the confirmation message: "Code saved to ./coding/[filename]". Do NOT add any other text or explanations.
6. **IMPORTANT:** After sending the confirmation message, reply with ONLY the word TERMINATE in your *next* message to end the conversation."""
    )
    logger.info("UserProxyAgent initialized successfully.")
except Exception as e:
    logger.error(f"Error initializing UserProxyAgent: {e}")
    traceback.print_exc()
    exit(1)


# --- Discord Bot Setup ---
# Add necessary intents for receiving messages in guilds and DMs
intents = discord.Intents.default()
intents.message_content = True
intents.guilds = True # Recommended for general bot functionality
intents.dm_messages = True # Explicitly allow DM messages
client = discord.Client(intents=intents)
channel_locks = {}

@client.event
async def on_ready():
    logger.info(f'Logged in as {client.user}')
    logger.info('------')
    logger.info(f'Discord.py version: {discord.__version__}')
    logger.info('Bot is ready and listening for messages.')

@client.event
async def on_message(message):
    # Log immediately upon receiving a message, before any checks
    logger.info(f"on_message triggered by {message.author} in channel {message.channel.id} (type: {message.channel.type})")

    if message.author == client.user:
        logger.debug("Ignoring message from self.")
        return

    # Log after self-check
    logger.info(f"Processing message from {message.author} in #{message.channel}: {message.content}")

    lock = channel_locks.get(message.channel.id)
    if lock is None:
        logger.debug(f"Creating new lock for channel {message.channel.id}")
        lock = asyncio.Lock()
        channel_locks[message.channel.id] = lock

    if lock.locked():
        logger.warning(f"Lock already held for channel {message.channel.id}, skipping message.")
        await message.channel.send("Processing another request...")
        return

    logger.debug(f"Acquiring lock for channel {message.channel.id}")
    async with lock:
        logger.debug(f"Lock acquired for channel {message.channel.id}")
        current_assistant = assistant
        current_user_proxy = user_proxy
        if not current_assistant or not current_user_proxy:
             logger.error("Agents not initialized properly.")
             await message.channel.send("Agents not ready.")
             return # Lock released automatically by async with

        # Log the client type being used for this chat
        logger.info(f"Initiating chat with assistant client type: {type(current_assistant.client)}, id: {id(current_assistant.client)}")

        try:
            logger.debug("Entering typing context manager.")
            async with message.channel.typing():
                logger.debug("Inside typing context manager.")
                first_assistant_message_captured = None
                last_proxy_confirmation = None

                # Ensure the hook handles potential non-dict messages gracefully
                def capture_messages_hook(recipient, messages, sender, config):
                    nonlocal first_assistant_message_captured, last_proxy_confirmation
                    logger.debug(f"Capture hook called. Sender: {sender.name}, Recipient: {recipient.name}")
                    if not isinstance(messages, list) or not messages:
                        logger.debug("Hook received empty or non-list messages.")
                        return False, None
                    current_msg = messages[-1]
                    logger.debug(f"Hook processing message: {current_msg}")
                    # Check if current_msg is a dict before using .get()
                    content = ""
                    if isinstance(current_msg, dict):
                        content = str(current_msg.get("content", "")).strip()
                    elif isinstance(current_msg, str): # Handle plain string messages if they occur
                        content = current_msg.strip()
                    else:
                        logger.warning(f"Hook received unexpected message type: {type(current_msg)}")
                        return False, None # Skip processing if type is unknown

                    if sender.name == current_assistant.name and first_assistant_message_captured is None and content:
                        first_assistant_message_captured = content; logger.debug(f"Hook captured FIRST message from {sender.name}: {content[:100]}...")
                    elif sender.name == current_user_proxy.name and content and "Code saved to" in content:
                         last_proxy_confirmation = content; logger.debug(f"Hook captured PROXY confirmation: {content}")
                    elif content: logger.debug(f"Hook saw message from {sender.name}: {content[:100]}...")
                    return False, None

                proxy_hook_key = f"proxy_hook_{message.id}"; assistant_hook_key = f"assistant_hook_{message.id}"
                logger.debug(f"Registering reply hooks: {proxy_hook_key}, {assistant_hook_key}")
                current_user_proxy.register_reply(proxy_hook_key, reply_func=capture_messages_hook, config={})
                current_assistant.register_reply(assistant_hook_key, reply_func=capture_messages_hook, config={})
                logger.info("Registered reply hooks.")

                logger.info(f"Initiating AutoGen chat for: {message.content}")
                await current_user_proxy.a_initiate_chat(current_assistant, message=message.content, clear_history=True)
                logger.info(f"AutoGen chat finished.")

                logger.debug(f"Deregistering reply hooks: {proxy_hook_key}, {assistant_hook_key}")
                current_user_proxy.deregister_reply(proxy_hook_key); current_assistant.deregister_reply(assistant_hook_key)
                logger.info("Deregistered reply hook(s).")

                final_response_to_send = last_proxy_confirmation if last_proxy_confirmation else first_assistant_message_captured
                if final_response_to_send:
                    logger.info(f"Sending final response to Discord: '{final_response_to_send[:100]}...'")
                    if len(final_response_to_send) > 2000:
                        logger.debug("Response > 2000 chars, sending in parts.")
                        await message.channel.send("Response too long, sending in parts...")
                        parts = [final_response_to_send[i:i+1990] for i in range(0, len(final_response_to_send), 1990)]
                        for i, part in enumerate(parts): await message.channel.send(f"```{part}```")
                    else:
                        logger.debug("Sending response as single message.")
                        await message.channel.send(final_response_to_send)
                    logger.info("Finished sending response.")
                else:
                    logger.warning("No valid response captured to send.")
                    await message.channel.send("Sorry, no response generated.")

        except Exception as e:
            logger.error(f"Error in on_message during chat execution: {e}")
            traceback.print_exc()
            try:
                await message.channel.send(f"An error occurred: {e}")
            except Exception as send_error:
                logger.error(f"Failed to send error to Discord: {send_error}")
        finally:
            logger.debug(f"Releasing lock for channel {message.channel.id}")
            # Lock released automatically by async with

# --- Run the Bot ---
if __name__ == "__main__":
    coding_dir = "coding"
    if not os.path.exists(coding_dir):
        try:
            os.makedirs(coding_dir)
            logger.info(f"Created ./{coding_dir} directory.")
        except OSError as e:
            logger.error(f"Error creating directory ./{coding_dir}: {e}")
            exit(1)

    logger.info("Starting Discord bot...")
    try:
        client.run(DISCORD_BOT_TOKEN)
    except Exception as e:
        logger.critical(f"Discord client run failed: {e}")
        traceback.print_exc()
