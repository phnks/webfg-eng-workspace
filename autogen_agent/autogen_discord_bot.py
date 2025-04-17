# Add this patch at the very top of your script
import builtins
builtins.input = lambda prompt="": ""

from functools import partial

import autogen
import discord
import autogen
import discord
import os
import asyncio
from dotenv import load_dotenv
import json # Import json for parsing potential code blocks
import traceback # Import traceback for error logging
# Removed GoogleGeminiClient import and registration as it's likely handled internally in 0.2.x

from autogen.coding import LocalCommandLineCodeExecutor

# Load environment variables
load_dotenv()
DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# Read USE_GEMINI, default to False (string comparison)
USE_GEMINI = os.getenv("USE_GEMINI", "false").lower() == "true"

# --- Basic Input Validation ---
if not DISCORD_BOT_TOKEN:
    print("Error: DISCORD_BOT_TOKEN not found in .env file.")
    exit(1)

if USE_GEMINI:
    print("Gemini mode enabled via USE_GEMINI flag.")
    if not GEMINI_API_KEY:
        print("Error: USE_GEMINI is true, but GEMINI_API_KEY not found in .env file.")
        exit(1)
else:
    print("OpenAI mode enabled (USE_GEMINI is false or not set).")
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
llm_config = {
    "cache_seed": None, # Disabled caching to prevent stale states
    "temperature": 0.7,
}

if USE_GEMINI:
    config_list = [
        {
            "model": "gemini-1.5-pro", # Using gemini-1.5-pro as requested
            #"model": "gemini-2.5-pro-exp-03-25",
            "api_key": GEMINI_API_KEY,
            "api_type": "google"
        }
    ]
    # Gemini doesn't use system_message in the same way, handle it later
    assistant_system_message = ""
    # Prepend the intended system message to the user prompt later
    # Also add instruction to save code blocks with filenames
    gemini_initial_prompt_prefix = (
        "You are a helpful AI assistant. Respond to the user's query. When generating code (like HTML, Python, etc.), "
        "embed it in a markdown code block and **always** include a filename comment like '# filename: your_filename.ext' "
        "on the first line inside the block. After providing your answer, please conclude by outputting 'TERMINATE' on a new line."
    )
    print("Using Gemini config list.")
else:
    config_list = [
        {
            'model': 'gpt-3.5-turbo',
            'api_key': OPENAI_API_KEY,
        }
    ]
    # Add instruction to save code blocks with filenames for OpenAI too
    assistant_system_message = "You are a helpful AI assistant. Respond to the user's query. When generating code (like HTML, Python, etc.), embed it in a markdown code block and **always** include a filename comment like '# filename: your_filename.ext' on the first line inside the block."
    gemini_initial_prompt_prefix = "" # No prefix needed for OpenAI
    print("Using OpenAI config list.")

llm_config["config_list"] = config_list

import os, sys
# make WORK_DIR sit right next to this script
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WORK_DIR = os.path.join(BASE_DIR, "agent_workspace")
os.makedirs(WORK_DIR, exist_ok=True)

executor = LocalCommandLineCodeExecutor(
    timeout=300,        # allow up to 5 minutes per block
    work_dir=WORK_DIR,  # full read/write/exec in here
)

# 3) Assistant: use the built‑in DEFAULT_SYSTEM_MESSAGE which teaches it
#    how to write code blocks, name files, use print(), and terminate.
assistant = autogen.AssistantAgent(
    name="assistant",
    llm_config=llm_config,
    system_message=autogen.AssistantAgent.DEFAULT_SYSTEM_MESSAGE
)

# 4) UserProxy: fully autonomous, executing any code blocks the assistant emits
user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",
    max_consecutive_auto_reply=1,
    is_termination_msg=lambda m: m.get("content", "").strip().endswith("TERMINATE"),
    code_execution_config={"executor": executor},
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
    print(f'AutoGen version: {autogen.__version__}')
    print(f'Using {"Gemini" if USE_GEMINI else "OpenAI"} models.')
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
                # --- Prepare Initial Message ---
                initial_message = message.content
                if USE_GEMINI and gemini_initial_prompt_prefix:
                    initial_message = gemini_initial_prompt_prefix + initial_message
                    print(f"Prepended Gemini prefix. Full initial message: {initial_message}")

                # --- Initiate AutoGen Chat Asynchronously ---
                print(f"Initiating AutoGen chat in executor...")
                loop = asyncio.get_event_loop()

                print("Sending prompt payload:", initial_message)
                chat_result = await loop.run_in_executor(
                    None,
                    lambda: user_proxy.initiate_chat(
                        assistant,
                        message=initial_message,   # ✅ correct kwarg
                        clear_history=True         # ✅ correct kwarg
                    )
                )
                print("AutoGen chat finished.")

                # ——————————————— WRITE OUT ANY CODE BLOCKS ———————————————
                import re
                # gather all assistant replies
                assistant_texts = []
                for msg in chat_result.chat_history:
                    if isinstance(msg, dict) and msg.get("name") == assistant.name:
                        assistant_texts.append(msg.get("content", ""))

                # find ``` blocks with "# filename: ..." and write them
                files_written = []
                pattern = re.compile(
                    r"```(?:\w+)?\s*\n# filename: ([^\n]+)\n(.*?)```",
                    re.DOTALL
                )
                for text in assistant_texts:
                    for m in pattern.finditer(text):
                        fname = m.group(1).strip()
                        code  = m.group(2)
                        fpath = os.path.join(WORK_DIR, fname)
                        with open(fpath, "w", encoding="utf-8") as f:
                            f.write(code)
                        files_written.append(fname)

                # prep the executed_outputs list with a note if we wrote files
                import subprocess
                executed_outputs = []
                if files_written:
                    executed_outputs.append(f"Wrote files: {', '.join(files_written)}")

                # ——————————————— RUN ANY FILES THAT LANDED IN WORK_DIR ———————————————
                # ——————————————————————————————————————————————————————
                # 👷  Post‑processing: actually run any files the executor created
                import subprocess
                executed_outputs = []
                for fname in sorted(os.listdir(WORK_DIR)):
                    fpath = os.path.join(WORK_DIR, fname)
                    # Python files: run non‑blocking for server.py, blocking otherwise
                    if fname.endswith(".py"):
                        if fname == "server.py":
                            # start your HTTP server in the background
                            proc = subprocess.Popen(
                                [sys.executable, fpath],
                                cwd=WORK_DIR,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL,
                            )
                            executed_outputs.append(f"Started `{fname}` as background process (pid {proc.pid})")
                        else:
                            out = subprocess.check_output(
                                [sys.executable, fpath],
                                cwd=WORK_DIR,
                                stderr=subprocess.STDOUT,
                            )
                            executed_outputs.append(f"Output of `{fname}`:\n{out.decode().strip()}")

                    # Shell scripts: run them to completion
                    elif fname.endswith(".sh"):
                        out = subprocess.check_output(
                            ["bash", fpath],
                            cwd=WORK_DIR,
                            stderr=subprocess.STDOUT,
                        )
                        executed_outputs.append(f"Output of `{fname}`:\n{out.decode().strip()}")

                # tack the results onto the end of the assistant’s final_response
                final_response = ""
                if executed_outputs:
                    final_response += "\n\n**Execution results:**\n" + "\n\n".join(executed_outputs)
                # ——————————————————————————————————————————————————————
                # --- Extract Final Response (and check for saved file) ---
                final_response = "Sorry, I couldn't generate a response for that." # Default
                if chat_result and chat_result.chat_history:
                    print(f"DEBUG: Chat history length: {len(chat_result.chat_history)}") # Debug history length
                    # Find the last message from the assistant
                    for i, msg in enumerate(reversed(chat_result.chat_history)):
                        print(f"DEBUG: Checking message {-i-1}: type={type(msg)}, content={msg}") # Debug each message
                        # Ensure msg is a dictionary before using .get()
                        if isinstance(msg, dict):
                            # Check if the message role is 'user' (assistant's reply) or name matches
                            is_assistant_msg = (msg.get('role') == 'user' or msg.get('name') == assistant.name)
                            print(f"DEBUG: Message {-i-1} is_assistant_msg: {is_assistant_msg}") # Debug role/name check

                            if is_assistant_msg:
                                 content = msg.get('content')
                                 print(f"DEBUG: Message {-i-1} content: {content}") # Debug content
                                 if content:
                                     # Ensure content is a string before processing
                                     content_str = str(content).strip()

                                     # If the response is just TERMINATE, skip and look at the previous one
                                     if content_str == "TERMINATE" and len(chat_result.chat_history) > (i + 1):
                                         print(f"DEBUG: Skipping TERMINATE message.")
                                         continue # Look at the message before TERMINATE

                                     # Check if the content indicates a file was saved
                                     # Look for patterns like "Saved file:", "Code saved to", etc.
                                     # Or check if the user_proxy executed code successfully
                                     file_saved = False
                                     if "exitcode: 0" in content_str and "# filename:" in content_str:
                                         # Extract filename if possible (simple parsing)
                                         try:
                                             filename_line = next(line for line in content_str.splitlines() if line.strip().startswith("# filename:"))
                                             filename = filename_line.split(":", 1)[1].strip()
                                             saved_file_path = os.path.join("autogen_agent", "coding", filename) # Construct expected path
                                             if os.path.exists(saved_file_path):
                                                 final_response = f"Successfully created the file `{filename}` in the coding directory."
                                                 file_saved = True
                                                 print(f"Confirmed file saved: {saved_file_path}")
                                             else:
                                                 print(f"Code execution reported success, but file not found at: {saved_file_path}")
                                                 # Fall back to using the content string
                                                 final_response = content_str
                                         except Exception as parse_ex:
                                             print(f"DEBUG: Error parsing filename from content: {parse_ex}")
                                             final_response = content_str # Fallback
                                     else:
                                          # If no file saving detected, process content as before
                                          # Remove code block fences if present
                                          if content_str.startswith("```") and content_str.endswith("```"):
                                              # Find the first newline and the last newline
                                              first_newline = content_str.find('\n')
                                              last_newline = content_str.rfind('\n')
                                              if first_newline != -1 and last_newline != -1 and last_newline > first_newline:
                                                  # Check if there's a filename comment
                                                  potential_filename_line = content_str[first_newline+1:].splitlines()[0]
                                                  if potential_filename_line.strip().startswith("# filename:"):
                                                      # If it's just code block with filename, report success
                                                      filename = potential_filename_line.split(":", 1)[1].strip()
                                                      final_response = f"Generated code for `{filename}`." # Assume it should have been saved
                                                  else:
                                                      final_response = content_str[first_newline+1:last_newline].strip()
                                              else: # Fallback if structure is unexpected (e.g., ```text```)
                                                  lines = content_str.splitlines()
                                                  if len(lines) > 2:
                                                      final_response = "\n".join(lines[1:-1]).strip()
                                                  else:
                                                      final_response = content_str.replace("```", "").strip()
                                          else:
                                              final_response = content_str # Use the content directly

                                     if not file_saved: # Only print if we didn't confirm file save
                                         print(f"Extracted final response: '{final_response}'")
                                     break # Found the last relevant message
                        else:
                            print(f"DEBUG: Message {-i-1} is not a dictionary.")

                    # If loop finishes without break (no suitable message found after checks)
                    if final_response == "Sorry, I couldn't generate a response for that.": # Check if default is still set
                         print("Could not find a suitable final message from the assistant in chat history.")
                         # Optionally, use the summary if available and it's a string
                         if chat_result.summary and isinstance(chat_result.summary, str):
                             final_response = chat_result.summary
                             print(f"Using chat summary as fallback response: '{final_response}'")
                         elif chat_result.summary:
                             print(f"Chat summary is not a string: {type(chat_result.summary)}")


                else:
                     print("Chat result object or chat_history attribute was empty/None.")


                # --- Send Response Back to Discord ---
                if final_response:
                    print(f"Attempting to send final response to Discord channel {message.channel.id}: '{final_response}'")
                    # Discord has a message length limit (2000 characters)
                    if len(final_response) > 2000:
                        print(f"Response length ({len(final_response)}) exceeds 2000 chars. Sending preamble.")
                        await message.channel.send("The response is too long to display completely.")
                        # Send in chunks or as a file if needed
                        parts = [final_response[i:i+1990] for i in range(0, len(final_response), 1990)]
                        for i, part in enumerate(parts):
                            print(f"Sending part {i+1}/{len(parts)} of long response.")
                            await message.channel.send(f"```{part}```") # Send as code block for readability
                    else:
                        print(f"Sending short response (length {len(final_response)}).")
                        await message.channel.send(final_response)
                    print("Finished sending response to Discord.")
                else:
                    # This case should be less likely now with the default message
                    print("Final response variable was empty or None.")
                    await message.channel.send("Sorry, I couldn't generate a response for that.")

        except Exception as e:
            print(f"An error occurred during chat processing: {e}")
            # traceback is now imported at the top
            traceback.print_exc() # Print full traceback for debugging
            await message.channel.send(f"An error occurred while processing your request: {e}")
        finally:
            # Ensure lock is released even if errors occur (though `async with` handles this)
            pass # Lock is released automatically by `async with`


# --- Run the Bot ---
if __name__ == "__main__":
    # Check necessary keys based on mode
    keys_present = False
    if USE_GEMINI:
        if DISCORD_BOT_TOKEN and GEMINI_API_KEY:
            keys_present = True
    else:
        if DISCORD_BOT_TOKEN and OPENAI_API_KEY:
            keys_present = True

    if keys_present:
        print("Starting Discord bot...")
        try:
            client.run(DISCORD_BOT_TOKEN)
        except discord.errors.LoginFailure:
            print("Error: Failed to log in. Check your DISCORD_BOT_TOKEN.")
        except Exception as e:
            print(f"An unexpected error occurred while running the bot: {e}")
            import traceback
            traceback.print_exc()
    else:
        print("Bot cannot start due to missing API keys in .env file for the selected mode.")
