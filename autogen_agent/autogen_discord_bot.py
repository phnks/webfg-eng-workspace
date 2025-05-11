# filename: autogen_discord_bot.py
from __future__ import annotations

import logging, builtins, sys
builtins.input = lambda *_: ""  # prevent stdin blocking
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stderr,
)
_LOG = logging.getLogger("discord-bot")

import google.genai as _sdk          # makes the SDK + the alias appear
sys.modules["google_genai"] = _sdk   # (defensive if init ever changes)
import fast_gemini_patch               # prints “✅ Patched …”

import asyncio, time, os, re, shlex, subprocess, textwrap, getpass, platform, random
from pathlib import Path
from typing import List, Dict, Any
import prompts.system as system_prompt_module
import prompts.webfgapp as webfg_app_prompt_module
import autogen

from dotenv import load_dotenv; load_dotenv()

# -- Verify crucial Git/GH tokens are loaded --
_GIT_USERNAME = os.getenv("GIT_USERNAME")
_GIT_TOKEN = os.getenv("GIT_TOKEN")
_GH_TOKEN = os.getenv("GH_TOKEN")

if not all([_GIT_USERNAME, _GIT_TOKEN, _GH_TOKEN]):
    _LOG.warning("⚠️ Git/GitHub environment variables (GIT_USERNAME, GIT_TOKEN, GH_TOKEN) not fully set. Git/GH operations might fail. Ensure they are in the .env file.")
else:
    _LOG.info("✅ Git/GitHub environment variables loaded.")

# -- Load AWS credentials --
_AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
_AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
_AWS_REGION = os.getenv("AWS_REGION")
_AWS_ACCOUNT_ID = os.getenv("AWS_ACCOUNT_ID")

if not all([_AWS_ACCESS_KEY_ID, _AWS_SECRET_ACCESS_KEY, _AWS_REGION, _AWS_ACCOUNT_ID]):
    _LOG.warning("⚠️ AWS environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_ACCOUNT_ID) not fully set. AWS operations might fail. Ensure they are in the .env file.")
else:
    _LOG.info("✅ AWS environment variables loaded.")

# ---------------------------------------------------------------------------
# 1) dynamic user/assistant name & workspace
# ---------------------------------------------------------------------------
BOT_USER = os.getenv("BOT_USER") or getpass.getuser()
HOME_DIR = Path(os.path.expanduser(f"~{BOT_USER}"))
if not HOME_DIR.exists():
    sys.exit(f"❌ HOME directory for '{BOT_USER}' not found: {HOME_DIR}")

# ---------------------------------------------------------------------------
# 2) tokens & keys
# ---------------------------------------------------------------------------
AGENT_HOME = os.getenv("AGENT_HOME")
DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
USE_GEMINI = os.getenv("USE_GEMINI", "false").lower() == "true"
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GEMINI_API_KEYS: List[str] = [k.strip() for k in os.getenv("GEMINI_API_KEYS", "").split(",") if k.strip()]
if not DISCORD_BOT_TOKEN:
    sys.exit("❌ DISCORD_BOT_TOKEN missing in .env")
if USE_GEMINI and not GEMINI_API_KEYS:
    sys.exit("❌ USE_GEMINI=true but no Gemini key(s) provided")
if not USE_GEMINI and not OPENAI_API_KEY:
    sys.exit("❌ Neither OPENAI_API_KEY nor USE_GEMINI=true provided")

if not AGENT_HOME:
    sys.exit("❌ AGENT_HOME is not set in the environment (.env) — "
             "can’t locate tools.sh")

# ---------------------------------------------------------------------------
# 3) Gemini retry wrapper
# ---------------------------------------------------------------------------
MAX_RECOVERY_ATTEMPTS = 3 # Total attempts: 1 initial + (MAX_RECOVERY_ATTEMPTS - 1) retries

#import autogen.provider.google.genai_client as _ag_gc
#from gemini_retry_wrapper import GeminiRetryWrapper as _GRW
#_ag_gc.GeminiClient = _ag_gc.Gemini = _GRW

#if hasattr(_ag_gc, "_client") and isinstance(_ag_gc._client, _ag_gc.GeminiClient):
#    _ag_gc._client.__class__ = _GRW

# ---------------------------------------------------------------------------
# 4) Autogen / Discord imports
# ---------------------------------------------------------------------------
from autogen.coding import LocalCommandLineCodeExecutor, CodeBlock
from autogen.coding.base import CommandLineCodeResult # Try importing from base
import discord

# --- Monkey-patching to disable command sanitization ---
# Define a function that does nothing, matching the original signature
def _disabled_sanitize_command(lang: str, code: str) -> None:
    """Replacement for sanitize_command that does nothing."""
    pass

# Replace the static method on the original class
# WARNING: This is a global change and carries risks if the library updates
# or if other parts of the code unexpectedly rely on the original sanitization.
LocalCommandLineCodeExecutor.sanitize_command = _disabled_sanitize_command
_LOG.warning("⚠️ Monkey-patched LocalCommandLineCodeExecutor.sanitize_command to disable safety checks.")
# --- End Monkey-patching ---

# ---------------------------------------------------------------------------
# 5) Enhanced Executor with Logging
# ---------------------------------------------------------------------------
# --- add this helper inside your module (keep log object) -------------------
def _run_large_bash(code: str, work_dir: Path, timeout: int) -> CommandLineCodeResult:
    """
    Write long bash code to a temp file and execute it to bypass ARG_MAX.
    Returns a CommandLineCodeResult compatible with AutoGen.
    """
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".sh", dir=work_dir) as fh:
        fh.write(textwrap.dedent(code))
        tmp_script = Path(fh.name)
    os.chmod(tmp_script, 0o755)

    proc = subprocess.run(
        ["bash", str(tmp_script)],
        cwd=work_dir,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    # cleanup if you like: tmp_script.unlink(missing_ok=True)
    return CommandLineCodeResult(
        exit_code=proc.returncode,
        output=proc.stdout + proc.stderr,
    )
# ---------------------------------------------------------------------------

class EnhancedLocalExecutor(LocalCommandLineCodeExecutor):
    ARG_MAX_SAFETY = 1_500_000        # bytes – stay below kernel limit
    # No longer need the sanitize_command override here, as the base class is patched.
    # Expanded list of common languages
    KNOWN_LANGUAGES = {
        # Shells
        "bash", "shell", "sh", "zsh", "ksh", "fish",
        # Scripting
        "python", "python3", "py",
        "javascript", "js", "nodejs", "node",
        "typescript", "ts",
        "ruby", "rb",
        "perl", "pl",
        "php",
        "lua",
        "groovy",
        # PowerShell
        "powershell", "pwsh", "ps1",
        # Web
        "html", "htm",
        "css",
        "json",
        "yaml", "yml",
        "xml",
        # Compiled
        "c", "cpp", "c++",
        "java",
        "csharp", "cs",
        "go", "golang",
        "rust", "rs",
        "swift",
        "kotlin", "kt",
        "scala",
        "objective-c", "objc",
        # Data/DB
        "sql",
        "r",
        # Other
        "makefile",
        "dockerfile",
        "markdown", "md",
        "text", "txt", "", # Allow empty language tag as plain text/default shell
        # Add any other languages frequently encountered by the agent
    }

    HEARTBEAT_SEC = 10               # how often to print a dot
    ARG_MAX_SAFETY = 1_500_000

    def _wrap_with_heartbeat(self, script: str) -> str:
        """
        Prefix a bash script with a background heartbeat that prints one dot
        every HEARTBEAT_SEC seconds until the script exits.
        """
        return textwrap.dedent(f"""
            # ---- auto‑heartbeat injected by EnhancedLocalExecutor ----
            ( while true; do printf '.'; sleep {self.HEARTBEAT_SEC}; done ) &
            __HB_PID=$!
            trap 'kill "$__HB_PID" 2>/dev/null' EXIT
            # ----------------------------------------------------------
            {script}
        """)


    def execute_code_blocks(self, code_blocks: List[CodeBlock]) -> CommandLineCodeResult:
        """Executes code blocks with enhanced logging and unknown language handling."""
        log_messages = []
        exit_codes = []
        outputs = []
        for block in code_blocks:
            language = block.language.lower()
            code = block.code

            _LOG.debug(f"Attempting execution for language '{language}':\n---\n{code}\n---")

            if language not in self.KNOWN_LANGUAGES:
                # Format the skip message to include the command clearly for the agent output
                skip_output = f"Skipped command (unknown language '{language}'):\n```\n{code}\n```"
                _LOG.warning(skip_output)
                # Append a non-zero exit code and the formatted skip message as output
                exit_codes.append(1) # Indicate failure/skip
                outputs.append(skip_output) # Add formatted skip message to outputs
                log_messages.append(skip_output) # Also log it
                continue # Skip to the next block

            # Execute known language block using the parent method for a single block
            # This assumes the parent method can handle a list with one item.
            try:
                if language in {"bash", "shell", "sh"}:
                    code = self._wrap_with_heartbeat(code)
                if language in {"bash", "shell", "sh"} and len(code.encode()) > self.ARG_MAX_SAFETY:
                    _LOG.info("Large bash snippet detected – executing via temp script to avoid ARG_MAX")
                    return _run_large_bash(code, self.work_dir, self.timeout)
                # We call the super method with a list containing only the current block
                # single_block_result: CommandLineCodeResult = super().execute_code_blocks([block])
                single_block_result: CommandLineCodeResult = super().execute_code_blocks(
                    [CodeBlock(language=block.language, code=code)]
                )
                _LOG.debug(f"Execution result (Exit Code {single_block_result.exit_code}):\n---\n{single_block_result.output}\n---")
                exit_codes.append(single_block_result.exit_code)
                # Prepend the executed code to the output for the agent
                formatted_output = f"Executed command:\n```\n{code}\n```\nOutput:\n{single_block_result.output}"
                outputs.append(formatted_output)
                # Assuming log file path might be in the result, or construct one if needed
                # For simplicity, we'll just use the output as the log message here.
                # Update log message to use 'language'
                log_messages.append(f"Executed {language} block. Exit Code: {single_block_result.exit_code}\nOutput:\n{single_block_result.output}") # Keep log simple
            except Exception as e:
                # Update error message to use 'language' and include code for agent output
                error_output = f"Error executing command:\n```\n{code}\n```\nError:\n{e}"
                _LOG.error(f"Error executing {language} block: {e}\nCode:\n---\n{code}\n---", exc_info=True) # Keep detailed log
                exit_codes.append(1) # Indicate failure
                outputs.append(error_output) # Add formatted error to outputs
                log_messages.append(error_output) # Also log it


        # Combine results. We need to decide how to aggregate exit codes.
        # Let's return 0 only if all blocks succeeded (exit code 0).
        final_exit_code = 0
        if any(ec != 0 for ec in exit_codes):
            final_exit_code = 1 # Or perhaps the first non-zero exit code? Let's use 1 for simplicity.

        # Combine outputs and log messages
        final_output = "\n---\n".join(outputs)
        # The original CommandLineCodeResult might have a specific log file.
        # We are creating a synthetic result here. Adjust if the actual class structure differs.
        # Let's assume log_file_path isn't strictly needed or can be None.
        return CommandLineCodeResult(exit_code=final_exit_code, output=final_output) # Removed log_file_path


# Set timeout to a very large value (e.g., 24 hours) instead of None to avoid TypeError
# This effectively disables the timeout for practical purposes.
_24_HOURS_IN_SECONDS = 24 * 60 * 60
executor = EnhancedLocalExecutor(work_dir=str(HOME_DIR), timeout=_24_HOURS_IN_SECONDS)
executor.max_output_len = None          # None = no truncation

# --- Determine OS and Shell for System Prompt ---
OS_NAME = platform.system()
DEFAULT_SHELL = os.environ.get('SHELL', '/bin/bash' if OS_NAME != "Windows" else "cmd.exe")
os.environ["BASH_ENV"] = str(AGENT_HOME + "/tools.sh")

base_system_prompt = textwrap.dedent(system_prompt_module.SYSTEM_PROMPT(
    BOT_USER, str(HOME_DIR), DEFAULT_SHELL, OS_NAME
)).strip()
_LOG.info("✅ Loaded system prompt with, BOT_USER=" + BOT_USER + " HOME_DIR=" + str(HOME_DIR) + " DEFAULT_SHELL=" + DEFAULT_SHELL + " OS_NAME=" + OS_NAME)

header = textwrap.dedent(webfg_app_prompt_module.WEBFG_APP_PROMPT()).strip()

# ---------------------------------------------------------------------------
# 6) LLM config
# ---------------------------------------------------------------------------
def only_assistant_can_end(msg: dict) -> bool:
    """
    Return True only when the *assistant* sends TERMINATE or DONE.
    """
    return (
        msg.get("name") == BOT_USER           # assistant’s name
        and msg.get("content", "").strip().upper() in {"TERMINATE", "DONE"}
    )

llm_config = {
    "temperature": 0.7,
    "cache_seed": None,
    "config_list": [{
        "model": "gemini-2.5-pro-exp-03-25" if USE_GEMINI else "gpt-3.5-turbo",
        "api_key": random.choice(GEMINI_API_KEYS) if USE_GEMINI else OPENAI_API_KEY,
        "api_type": "google" if USE_GEMINI else "openai"
    }],
}
assistant = autogen.AssistantAgent(
    name=BOT_USER,
    llm_config=llm_config,
    system_message=base_system_prompt + "\\n\\n" + header,
)

user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",
    max_consecutive_auto_reply=500,
    is_termination_msg=only_assistant_can_end,
    code_execution_config={"executor": executor},
)

def _smart_auto_reply(messages, sender, config):
    """
    If the last assistant message contains code, tell the proxy
    to CONTINUE; otherwise stop so the human can answer.
    """
    last = messages[-1]
    has_code = bool(re.search(r"```[\\s\\S]+?```", last.get("content", "")))
    return "CONTINUE" if has_code else "TERMINATE"

def _debug_hook(messages, sender, cfg):
    if sender == assistant:
        _LOG.debug("🗨️  assistant turn (%d chars)",
                   len(messages[-1]['content'] or ""))
    return _smart_auto_reply(messages, sender, cfg)

user_proxy.register_reply([assistant], _debug_hook)

# ---------------------------------------------------------------------------
# 7) Discord glue
# ---------------------------------------------------------------------------
intents = discord.Intents.default()
intents.message_content = True
bot = discord.Client(intents=intents)

_channel_locks: Dict[int, asyncio.Lock] = {}
_current_tasks: Dict[int, asyncio.Task] = {}

async def _send_long(ch: discord.abc.Messageable, txt: str):
    for chunk in [txt[i:i+1900] for i in range(0, len(txt), 1900)]:
        await ch.send(chunk)

RUN_AS_ROOT = os.geteuid() == 0
# Use plain 'sudo' instead of 'sudo -n' to avoid potential non-interactive failures,
# assuming passwordless sudo is configured or the script runs as root.
SUDO: list[str] = [] if RUN_AS_ROOT else ["sudo"]

def _run(cmd: list[str] | str, **kw):
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)
    return subprocess.check_output(SUDO + cmd, **kw)

# ---------------------------------------------------------------------------
# 8) slash-commands
# ---------------------------------------------------------------------------
def _handle_host_cmd(cmd: str, args: List[str]) -> tuple[str, str]:
    if cmd == "status":
        out = _run("/usr/local/bin/status_agent.sh").decode(); return ("Agent status", out or "(no output)")
    if cmd == "restart":
        out = _run("/usr/local/bin/restart_agent.sh").decode(); return ("Agent restarted", out or "(no output)")
    if cmd == "stop":
        out = _run("/usr/local/bin/stop_agent.sh").decode(); return ("Agent stopped", out or "(no output)")
    if cmd == "logs":
        n = 50
        if args:
            try:
                n = int(args[0])
                if n <= 0:
                    n = 50
            except ValueError:
                pass
        out = _run(["/usr/local/bin/get_logs.sh", str(n)]).decode()
        return (f"Last {n} log lines", out or "(no output)")
    if cmd == "interrupt": return ("", "")
    raise ValueError(cmd)

# ---------------------------------------------------------------------------
# 9) Result Processing Helper & Main Request Handler
# ---------------------------------------------------------------------------
async def _process_and_send_result(ch: discord.abc.Messageable, chat_result: Any):
    """Processes the chat result and sends the final message to Discord."""
    if not chat_result:
         _LOG.error("Internal state error: _process_and_send_result called with no chat result.")
         await ch.send("⚠️ Internal state error: Processing failed due to missing chat result.")
         return

    # Process execution results automatically included by executor
    # Send only last assistant content without codeblocks
    last = None
    for msg in reversed(chat_result.chat_history):
        if msg.get("name") == BOT_USER and msg.get("content","").strip():
            last = msg["content"].strip(); break
    if not last:
         _LOG.warning("No reply content generated by assistant in the final result.")
         await ch.send("⚠️ No reply generated by the agent.")
         return

    cleaned = re.sub(r"```.*?```", "", last, flags=re.DOTALL).strip()
    # Use _send_long to handle potential long messages and avoid Discord 2000 char limit
    if cleaned: # Only send if there's content after cleaning
         await _send_long(ch, cleaned)
    else:
         # If cleaning removed everything (e.g., response was only code blocks), send a notification.
         _LOG.info("Agent response contained only code blocks (executed, not displayed).")
         await ch.send("ℹ️ Agent response contained only code blocks (executed, not displayed). Task likely completed.")


async def _handle_request(ch: discord.abc.Messageable, original_content: str):
    lock = _channel_locks.setdefault(ch.id, asyncio.Lock())
    async with lock:
        loop = asyncio.get_running_loop()
        current_content = original_content

        for attempt in range(1, MAX_RECOVERY_ATTEMPTS + 1):
            _LOG.info(f"Attempt {attempt}/{MAX_RECOVERY_ATTEMPTS} for original request: {original_content[:70]}...")
            if attempt > 1:
                _LOG.info(f"Retry attempt {attempt} using content: {current_content[:150]}...")

            try:
                await ch.typing()
                _LOG.info(f"Calling user_proxy.initiate_chat (attempt {attempt})...")
                chat_result = await loop.run_in_executor(
                    None,
                    lambda: user_proxy.initiate_chat(
                        assistant,
                        message=current_content,
                        clear_history=False,
                    )
                )
                _LOG.info(f"Initiate_chat completed successfully on attempt {attempt}.")
                await _process_and_send_result(ch, chat_result)
                return # SUCCESS: Exit function

            except asyncio.CancelledError:
                _LOG.info(f"Task cancelled by user during attempt {attempt}.")
                await ch.send("🚫 Task cancelled.")
                return # CANCELLED: Exit function

            except RuntimeError as rt_exc:
                error_message = str(rt_exc)
                _LOG.warning(f"RuntimeError on attempt {attempt}/{MAX_RECOVERY_ATTEMPTS}: {error_message[:200]}")

                if attempt >= MAX_RECOVERY_ATTEMPTS:
                    _LOG.error(f"Max recovery attempts ({MAX_RECOVERY_ATTEMPTS}) reached. Failing permanently. Last error: {rt_exc}")
                    await ch.send(f"⚠️ All {MAX_RECOVERY_ATTEMPTS} attempts failed. Last error: {error_message[:500]}")
                    return # FAILED PERMANENTLY: Exit function

                recovered_for_next_attempt = False

                # A) Gemini “list index out of range”
                if "Google GenAI exception occurred" in error_message and "list index out of range" in error_message:
                    _LOG.error(f"Attempt {attempt} (list index out of range). Preparing for retry {attempt + 1}.")
                    #await ch.send(f"⚠️ AI model error (attempt {attempt}/{MAX_RECOVERY_ATTEMPTS}). Retrying...")
                    current_content = (
                        "The previous attempt failed due to an internal API error (invalid/empty response structure). "
                        "Please process the original request again, trying a different approach or simplifying the response structure if possible, "
                        "while still aiming to fulfill the user's goal.\n"
                        f"Original request was: {original_content}"
                    )
                    recovered_for_next_attempt = True
                
                # B) "API key not valid"
                elif "Google GenAI exception occurred" in error_message and "API key not valid" in error_message:
                    _LOG.error(f"Attempt {attempt} (API key not valid). Preparing for retry {attempt + 1}.")
                    
                    if USE_GEMINI and GEMINI_API_KEYS:
                        if len(GEMINI_API_KEYS) <= 1:
                            _LOG.warning(f"Attempt {attempt}: Only one or zero Gemini API keys configured. Cannot switch to a different key.")
                            await ch.send(f"⚠️ AI API key error (attempt {attempt}/{MAX_RECOVERY_ATTEMPTS}). Only one key available, cannot switch. This error may persist.")
                            # Not setting recovered_for_next_attempt = True, so it will fall to unhandled.
                        else: # More than one key available
                            #await ch.send(f"⚠️ AI API key error (attempt {attempt}/{MAX_RECOVERY_ATTEMPTS}). Retrying with new key...")
                            current_api_key_in_config = assistant.llm_config.get("config_list", [{}])[0].get("api_key")
                            other_keys = [k for k in GEMINI_API_KEYS if k != current_api_key_in_config]
                            
                            if not other_keys: 
                                _LOG.error(f"Logic error in API key selection for attempt {attempt + 1}. No other keys found despite multiple total keys ({len(GEMINI_API_KEYS)} total, current: ...{current_api_key_in_config[-4:]}).")
                                await ch.send("⚠️ Internal error during API key switch. Cannot retry this way.")
                            else:
                                new_api_key = random.choice(other_keys)
                                if assistant.llm_config.get("config_list") and isinstance(assistant.llm_config["config_list"], list) and assistant.llm_config["config_list"]:
                                    assistant.llm_config["config_list"][0]["api_key"] = new_api_key
                                    _LOG.info(f"Switched to new Gemini API key for attempt {attempt + 1}: ...{new_api_key[-4:] if len(new_api_key) >= 4 else '****'}")
                                    current_content = (
                                        "The previous attempt failed due to an API key validation error. "
                                        "A new API key has been selected. Please process the original request again.\n"
                                        f"Original request was: {original_content}"
                                    )
                                    recovered_for_next_attempt = True
                                else:
                                    _LOG.error("Cannot update API key for attempt {attempt + 1}: llm_config['config_list'] is missing or invalid.")
                                    await ch.send("⚠️ Internal configuration error: Could not switch API key for retry.")
                    else: 
                        _LOG.warning(f"Attempt {attempt}: Cannot retry with new Gemini key: Not using Gemini or no API keys available.")
                        await ch.send("⚠️ Cannot attempt API key recovery: Gemini not in use or no API keys configured.")

                # C) Gemini global-context hard limit
                elif (re.search(r"400.*input token count \(\d+\) exceeds the maximum.*allowed \(\d+\)", error_message, re.IGNORECASE | re.DOTALL) or
                      re.search(r"input token count \(\d+\) exceeds", error_message, re.IGNORECASE)):
                    _LOG.info(f"Attempt {attempt} (Token limit error). Preparing for retry {attempt + 1} with pruning.")
                    
                    if USE_GEMINI:
                        #await ch.send(
                        #    f"⚠️ Conversation too large for Gemini (attempt {attempt}/{MAX_RECOVERY_ATTEMPTS}). "
                        #    "Pruning and retrying..."
                        #)
                        try:
                            # _grw should be available from top-level import if USE_GEMINI is true
                            current_max_tokens = getattr(_grw, 'MAX_TOTAL_TOKENS', 1000000) # Default if not set
                            _grw.MAX_TOTAL_TOKENS = max(256_000, int(current_max_tokens * 0.8))
                            _LOG.info(f"Tightened Gemini token budget for attempt {attempt + 1}. New MAX_TOTAL_TOKENS: {_grw.MAX_TOTAL_TOKENS}")
                            current_content = original_content 
                            recovered_for_next_attempt = True
                        except NameError: 
                            _LOG.error("gemini_retry_wrapper module (_grw) not found, though USE_GEMINI is true. Cannot adjust token budget.")
                            await ch.send("⚠️ Internal error: Could not adjust token budget (module not found).")
                        except AttributeError:
                            _LOG.error("gemini_retry_wrapper does not have MAX_TOTAL_TOKENS attribute.")
                            await ch.send("⚠️ Internal error: Could not adjust token budget (attribute missing).")
                    else: 
                        _LOG.warning(f"Attempt {attempt}: Token limit error for non-Gemini model. No specific recovery for this. Error: {error_message[:100]}")
                        await ch.send(f"⚠️ Conversation too large for AI model. No specific pruning defined for this model.")
                        # For non-Gemini, no specific recovery, will fall through to D.

                if recovered_for_next_attempt:
                    _LOG.info(f"Proceeding to attempt {attempt + 1} after applying recovery strategy for: {error_message[:70]}...")
                    continue # To the next iteration of the for loop

                # D) Unhandled RuntimeError (no specific recovery path taken or path failed internally)
                _LOG.error(f"Unhandled RuntimeError on attempt {attempt} (no recovery path taken or path failed): {rt_exc}", exc_info=True)
                await ch.send(f"⚠️ An unhandled AI error occurred on attempt {attempt}: {error_message[:500]}. Stopping retries for this error type.")
                return # FAILED (unhandled specific error or failed recovery path): Exit function

            except Exception as exc: 
                _LOG.error(f"Unhandled Exception in handler on attempt {attempt}: {exc}", exc_info=True)
                await ch.send(f"⚠️ An unexpected internal error occurred (attempt {attempt}): {str(exc)[:500]}")
                return # FAILED (unexpected general error): Exit function
        
        _LOG.error(f"Exited retry loop for {original_content[:50]} without success or explicit failure. This indicates a logic flaw if MAX_RECOVERY_ATTEMPTS > 0.")
        await ch.send("⚠️ An unexpected issue occurred with the retry logic. Please report this.")

# ---------------------------------------------------------------------------
# 10) Discord event handlers
# ---------------------------------------------------------------------------
@bot.event
async def on_ready():
    print(f"✅ Logged in as {bot.user} (discord {discord.__version__}) – HOME={HOME_DIR}")

@bot.event
async def on_message(msg: discord.Message):
    if msg.author == bot.user: return
    # slash commands
    if msg.content.startswith("/"):
        parts = msg.content[1:].split(); cmd, args = parts[0].lower(), parts[1:]
        if cmd == "interrupt":
            t = _current_tasks.get(msg.channel.id)
            if t and not t.done(): t.cancel(); await msg.channel.send("🚫 Current task cancelled.")
            else: await msg.channel.send("⚠️ No running task.")
            return
        try:
            title, out = _handle_host_cmd(cmd, args)
            await _send_long(msg.channel, f"**{title}**\n```{out}```")
        except Exception as e:
            await msg.channel.send(f"⚠️ {e}")
        return
    # normal interaction
    lock = _channel_locks.setdefault(msg.channel.id, asyncio.Lock())
    if lock.locked():
        await msg.channel.send("⏳ Busy – type /interrupt.")
        return
    task = asyncio.create_task(_handle_request(msg.channel, msg.content))
    _current_tasks[msg.channel.id] = task
    task.add_done_callback(lambda t: _current_tasks.pop(msg.channel.id, None))

# ---------------------------------------------------------------------------
# 11) run the bot
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    bot.run(DISCORD_BOT_TOKEN)
