# filename: autogen_discord_bot.py
from __future__ import annotations
import asyncio, builtins, logging, os, re, shlex, subprocess, sys, textwrap, getpass
from pathlib import Path
from typing import List, Dict, Any

# ── basic setup ──────────────────────────────────────────────────────────────
builtins.input = lambda *_: ""  # prevent stdin blocking
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stderr,
)
_LOG = logging.getLogger("discord-bot")

from dotenv import load_dotenv; load_dotenv()

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

# ---------------------------------------------------------------------------
# 3) Gemini retry wrapper
# ---------------------------------------------------------------------------
if USE_GEMINI:
    from gemini_retry_wrapper import GeminiRetryWrapper
    import autogen.oai.gemini as _gm
    _gm.GeminiClient = _gm.Gemini = GeminiRetryWrapper
    GeminiRetryWrapper._KEYS = GEMINI_API_KEYS

# ---------------------------------------------------------------------------
# 4) Autogen / Discord imports
# ---------------------------------------------------------------------------
import autogen
from autogen.coding import LocalCommandLineCodeExecutor, CodeBlock
import discord

executor = LocalCommandLineCodeExecutor(work_dir=str(HOME_DIR), timeout=300)

# ---------------------------------------------------------------------------
# 6) LLM config
# ---------------------------------------------------------------------------
llm_config = {
    "temperature": 0.7,
    "cache_seed": None,
    "config_list": [{
        "model": "gemini-2.5-flash-preview-04-17" if USE_GEMINI else "gpt-3.5-turbo",
        "api_key": GEMINI_API_KEYS[0] if USE_GEMINI else OPENAI_API_KEY,
        "api_type": "google" if USE_GEMINI else "openai",
    }],
}
assistant = autogen.AssistantAgent(
    name=BOT_USER,
    llm_config=llm_config,
    system_message=textwrap.dedent(f"""
        You are **{BOT_USER}**, an autonomous coding-assistant running in a Discord bot.
        Working directory: `{HOME_DIR}`, you have full access via sudo.

        • ALWAYS run real commands.
        • For servers, use: nohup <cmd> >server.log 2>&1 & disown
        • Wrap shell code in ```bash ...```.
        • Never put sample output in backticks.
        • Prefix commands with sudo if needed.
        • Reply exactly **TERMINATE** when done.
    """).strip(),
)
user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",
    max_consecutive_auto_reply=500,
    default_auto_reply="TERMINATE",
    is_termination_msg=lambda m: m.get("content", "").strip().upper() in {"TERMINATE", "DONE"},
    code_execution_config={"executor": executor},
)

# ---------------------------------------------------------------------------
# 7) Discord glue
# ---------------------------------------------------------------------------
intents = discord.Intents.default()
intents.message_content = True
bot = discord.Client(intents=intents)

_channel_locks: Dict[int, asyncio.Lock] = {}
_current_tasks: Dict[int, asyncio.Task] = {}
_spawned_pids: set[int] = set()

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
# 8) background server patterns & spawn helper
# ---------------------------------------------------------------------------
_SERVER_PATTERNS = [
    re.compile(r"python3? -m http\.server \d+", re.I),
    re.compile(r"flask run\b", re.I),
    re.compile(r"node \S+\.js\b", re.I),
    re.compile(r"(npm|pnpm|yarn) (run )?start\b", re.I),
]

def _spawn_daemon(cmd: str) -> int:
    proc = subprocess.Popen(
        SUDO + shlex.split(cmd.split("&")[0].strip()),
        cwd="/",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    _spawned_pids.add(proc.pid)
    _LOG.info("🌐 spawned daemon: %s  (pid %d)", cmd, proc.pid)
    return proc.pid

# ---------------------------------------------------------------------------
# 9) slash-commands
# ---------------------------------------------------------------------------
def _handle_host_cmd(cmd: str, args: List[str]) -> tuple[str, str]:
    if cmd == "status":
        out = _run("/usr/local/bin/status_agent.sh").decode(); return ("Agent status", out or "(no output)")
    if cmd == "restart":
        out = _run("/usr/local/bin/restart_agent.sh").decode(); return ("Agent restarted", out or "(no output)")
    if cmd == "stop":
        out = _run("/usr/local/bin/stop_agent.sh").decode(); return ("Agent stopped", out or "(no output)")
    if cmd == "logs":
        n = int(args[0]) if args else 50
        out = _run(["tail", "-n", str(n), f"{AGENT_HOME}/agent.log"]).decode()
        return (f"Last {n} log lines", out or "(empty)")
    if cmd == "interrupt": return ("", "")
    raise ValueError(cmd)

# ---------------------------------------------------------------------------
# 10) main request handler
# ---------------------------------------------------------------------------
async def _handle_request(ch: discord.abc.Messageable, content: str):
    lock = _channel_locks.setdefault(ch.id, asyncio.Lock())
    async with lock:
        try:
            await ch.typing()
            header = textwrap.dedent(f"""
                You are **{BOT_USER}**, an autonomous coding-assistant running in a Discord bot.
                Working directory: `{HOME_DIR}`, you have full access via sudo.

                • ALWAYS run real commands.
                • For servers, use: nohup <cmd> >server.log 2>&1 & disown
                • Wrap shell code in ```bash ...```.
                • Never put sample output in backticks.
                • Prefix commands with sudo if needed.
                • Reply exactly **TERMINATE** when done.
            """).strip()
            loop = asyncio.get_running_loop()
            chat_result = await loop.run_in_executor(
                None,
                lambda: user_proxy.initiate_chat(
                    assistant,
                    message=f"{header}\n\n{content}",
                    clear_history=False,
                )
            )
            # process execution results automatically included by executor
            # send only last assistant content without codeblocks
            last = None
            for msg in reversed(chat_result.chat_history):
                if msg.get("name") == BOT_USER and msg.get("content","").strip():
                    last = msg["content"].strip(); break
            if not last:
                await ch.send("⚠️ No reply generated.")
                return
            cleaned = re.sub(r"```.*?```", "", last, flags=re.DOTALL).strip()
            await ch.send(cleaned)
        except asyncio.CancelledError:
            await ch.send("🚫 Task cancelled."); raise
        except Exception as exc:
            _LOG.error("Handler error: %s", exc, exc_info=True)
            await ch.send(f"⚠️ Internal error: {exc}")

# ---------------------------------------------------------------------------
# 11) Discord event handlers
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
            await _send_long(msg.channel, f"**{title}**\n```\n{out}\n```")
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
# 12) run the bot
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    bot.run(DISCORD_BOT_TOKEN)
