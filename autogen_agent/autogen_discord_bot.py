# filename: autogen_discord_bot.py
from __future__ import annotations
import asyncio, builtins, logging, os, re, shlex, subprocess, sys, textwrap, getpass
from pathlib import Path
from typing import List, Dict

# ── basic setup ──────────────────────────────────────────────────────────────
builtins.input = lambda *_: ""                         # prevent stdin blocking
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stderr,
)
_LOG = logging.getLogger("discord‑bot")

from dotenv import load_dotenv; load_dotenv()

# ---------------------------------------------------------------------------
# 1)  dynamic user / assistant name & workspace
# ---------------------------------------------------------------------------
BOT_USER = os.getenv("BOT_USER") or getpass.getuser()           # e.g. anum / homonculus
HOME_DIR = Path(os.path.expanduser(f"~{BOT_USER}"))
if not HOME_DIR.exists():
    sys.exit(f"❌  HOME directory for '{BOT_USER}' not found: {HOME_DIR}")

# ---------------------------------------------------------------------------
# 2)  tokens & keys
# ---------------------------------------------------------------------------
AGENT_HOME = os.getenv("AGENT_HOME")
DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
USE_GEMINI        = os.getenv("USE_GEMINI", "false").lower() == "true"
OPENAI_API_KEY    = os.getenv("OPENAI_API_KEY")
GEMINI_API_KEYS: List[str] = (
    [k.strip() for k in os.getenv("GEMINI_API_KEYS", "").split(",") if k.strip()]
    or ([os.getenv("GEMINI_API_KEY").strip()] if os.getenv("GEMINI_API_KEY") else [])
)
if not DISCORD_BOT_TOKEN:
    sys.exit("❌  DISCORD_BOT_TOKEN missing in .env")
if USE_GEMINI and not GEMINI_API_KEYS:
    sys.exit("❌  USE_GEMINI=true but no Gemini key(s) provided")
if not USE_GEMINI and not OPENAI_API_KEY:
    sys.exit("❌  Neither OPENAI_API_KEY nor USE_GEMINI=true provided")

# ---------------------------------------------------------------------------
# 3)  Gemini retry wrapper
# ---------------------------------------------------------------------------
if USE_GEMINI:
    from gemini_retry_wrapper import GeminiRetryWrapper
    import autogen.oai.gemini as _gm
    _gm.GeminiClient = _gm.Gemini = GeminiRetryWrapper
    GeminiRetryWrapper._KEYS = GEMINI_API_KEYS

# ---------------------------------------------------------------------------
# 4)  Autogen / Discord imports
# ---------------------------------------------------------------------------
import autogen
from autogen.coding import LocalCommandLineCodeExecutor
import discord

# ---------------------------------------------------------------------------
# 5)  workspace & executor  (docker off where supported)
# ---------------------------------------------------------------------------
LocalCommandLineCodeExecutor.sanitize_command = staticmethod(lambda lang, code: code)
_EXECUTOR_KW: Dict[str, object] = dict(work_dir=str(HOME_DIR), timeout=300)
try:
    executor = LocalCommandLineCodeExecutor(**_EXECUTOR_KW, docker=False)
except TypeError:
    executor = LocalCommandLineCodeExecutor(**_EXECUTOR_KW)
    _LOG.warning("'docker' keyword not supported by this Autogen version – "
                 "container isolation already disabled by default.")

# ---------------------------------------------------------------------------
# 6)  LLM config
# ---------------------------------------------------------------------------
llm_config = {
    "temperature": 0.7,
    "cache_seed": None,
    "config_list": [
        {
            "model": "gemini-2.5-flash-preview-04-17" if USE_GEMINI else "gpt-3.5-turbo",
            "api_key": GEMINI_API_KEYS[0] if USE_GEMINI else OPENAI_API_KEY,
            "api_type": "google" if USE_GEMINI else "openai",
        }
    ],
}

assistant = autogen.AssistantAgent(
    name=BOT_USER,
    llm_config=llm_config,
    system_message=textwrap.dedent(
        f"""
        You are **{BOT_USER}**, an autonomous coding‑assistant running inside a Discord bot.
        Your working directory is `{HOME_DIR}` but you have root‑level access
        to the whole VM.

        • ALWAYS run real commands – never simulate.
        • For long‑running servers start them with
              nohup <cmd> >server.log 2>&1 & disown

        Wrap any code in ``` with “# filename: …” on the first line.
        When completely finished output exactly **TERMINATE**.
        """
    ).strip(),
)

user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",
    max_consecutive_auto_reply=5,          # ←‑‑ original cure
    default_auto_reply="TERMINATE",        # ←‑‑ belt‑and‑braces
    is_termination_msg=lambda m: (
        m.get("content", "").strip().upper() in {"TERMINATE", "TASK COMPLETE", "DONE"}
    ),
    code_execution_config={"executor": executor},
)

# ---------------------------------------------------------------------------
# 7)  Discord glue
# ---------------------------------------------------------------------------
intents = discord.Intents.default()
intents.message_content = True
bot = discord.Client(intents=intents)

_channel_locks: dict[int, asyncio.Lock] = {}
_current_tasks: dict[int, asyncio.Task] = {}
_spawned_pids: set[int] = set()

RUN_AS_ROOT = os.geteuid() == 0
SUDO: list[str] = [] if RUN_AS_ROOT else ["sudo", "-n"]

def _run(cmd: list[str] | str, **kw):
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)
    return subprocess.check_output(SUDO + cmd, **kw)

# ---------------------------------------------------------------------------
# 8)  background server handling (unchanged)
# ---------------------------------------------------------------------------
_SERVER_PATTERNS = [
    re.compile(r"python3?\s+-m\s+http\.server\s+\d+", re.I),
    re.compile(r"flask\s+run\b", re.I),
    re.compile(r"node\s+\S+\.js\b", re.I),
    re.compile(r"(npm|pnpm|yarn)\s+(run\s+)?start\b", re.I),
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
    _LOG.info("🌐 spawned daemon: %s  (pid %d)", cmd, proc.pid)
    return proc.pid

def _last_assistant_content(hist: List[dict]) -> str:
    for m in reversed(hist):
        if m.get("name") == BOT_USER and m.get("content", "").strip():
            return m["content"]
    return ""

async def _send_long(ch: discord.abc.Messageable, txt: str):
    for chunk in [txt[i:i+1900] for i in range(0, len(txt), 1900)]:
        await ch.send(chunk)

# ---------------------------------------------------------------------------
# 9)  host slash‑commands  (unchanged)
# ---------------------------------------------------------------------------
def _handle_host_cmd(cmd: str, args: List[str]) -> tuple[str, str]:
    if cmd == "status":
        out = _run("/usr/local/bin/status_agent.sh").decode()
        return ("Agent status", out or "(no output)")
    if cmd == "restart":
        out = _run("/usr/local/bin/restart_agent.sh").decode()
        return ("Agent restarted", out or "(no output)")
    if cmd == "stop":
        out = _run("/usr/local/bin/stop_agent.sh").decode()
        return ("Agent stopped", out or "(no output)")
    if cmd == "logs":
        n = int(args[0]) if args else 50
        out = _run(["tail", "-n", str(n), f"{AGENT_HOME}/agent.log"]).decode()
        return (f"Last {n} log lines", out or "(empty)")
    if cmd == "interrupt":
        return ("", "")
    raise ValueError(cmd)

# ---------------------------------------------------------------------------
# 10)  main request handler (unchanged)
# ---------------------------------------------------------------------------
async def _handle_request(ch: discord.abc.Messageable, content: str):
    lock = _channel_locks.setdefault(ch.id, asyncio.Lock())
    async with lock:
        try:
            await ch.typing()

            header = textwrap.dedent(
                f"""
                Your name is **{BOT_USER}**.
                You have full root shell on this VM (start dir `{HOME_DIR}`).

                • read / write / exec any file
                • run any CLI command
                • For servers:  nohup … >server.log 2>&1 & disown

                NEVER simulate commands – always run them.
                Wrap all code and all commands in triple‑back‑ticks 
                ALWAYS include: `# filename blah` on the first line if writing a file where blah is the filename you want
                ALWAYS include: `bash` on the first line if running a command, or whatever language you want to use
                NEVER include anything but executable code or commands inside the back ticks
                NEVER incude comments if you are running a command
                NEVER use triple-back-ticks unless you want to write code or run a command
                When finished the task with no errors write out **TERMINATE**.
                """
            ).strip()

            loop = asyncio.get_running_loop()
            chat_result = await loop.run_in_executor(
                None,
                lambda: user_proxy.initiate_chat(
                    assistant, message=f"{header}\n\n{content}", clear_history=False
                )
            )

            # ─── combined handler: run bash lines & write files in sequence ──────────
            #print ("Assistant messages: " + str(chat_result.chat_history))
            assistant_msgs = [m["content"] for m in chat_result.chat_history
                              if m["name"] == BOT_USER]
            combined = "\n".join(assistant_msgs)
            #print ("Combined messages: " + combined)
            # regex matches either a multi‑line bash block or a file block, preserving order
            block_pat = re.compile(
                # either a bash block or a file block
                r"```bash\s*\n(?P<bash>.*?)```"
                r"|```(?:\w+)?\s*\n# filename: (?P<fname>[^\n]+)\n(?P<file>.*?)```",
                re.IGNORECASE | re.DOTALL
            )
            results: List[str] = []
            for blk in block_pat.finditer(combined):
                if blk.group("fname"):
                    # it's a file block
                    fname = blk.group("fname").strip()
                    #print ("Found file to write: " + fname)
                    code = blk.group("file")
                    path = (HOME_DIR / fname).expanduser()
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(code)
                    results.append(f"💾 wrote file `{fname}`")

            # if any commands/files ran, send a single combined report
            if results:
                await loop.run_in_executor(
                    None,
                    lambda: user_proxy.send(
                        "Execution results:\n" + "\n\n".join(results),
                        recipient=assistant,
                    ),
                )


            # ─── if nothing to run/write, just forward the assistant's last message ───
            reply = _last_assistant_content(chat_result.chat_history) or \
                    "⚠️  No reply generated (empty turn filtered)."
            await _send_long(ch, reply)

        except asyncio.CancelledError:
            await ch.send("🚫  Task cancelled.")
            raise
        except Exception as exc:
            _LOG.error("Handler error: %s", exc, exc_info=True)
            await ch.send(f"⚠️  Internal error: {exc}")

# ---------------------------------------------------------------------------
# 11)  Discord event handlers (unchanged)
# ---------------------------------------------------------------------------
@bot.event
async def on_ready():
    print(f"✅ Logged in as {bot.user} (discord {discord.__version__})  "
          f"AutoGen {autogen.__version__} – HOME={HOME_DIR}")

@bot.event
async def on_message(msg: discord.Message):
    if msg.author == bot.user:
        return

    # Slash‑commands
    if msg.content.startswith("/"):
        parts = msg.content[1:].split()
        cmd, args = parts[0].lower(), parts[1:]

        if cmd == "interrupt":
            task = _current_tasks.get(msg.channel.id)
            if task and not task.done():
                task.cancel()
                await msg.channel.send("🚫  Current task cancelled.")
            else:
                await msg.channel.send("⚠️  No running task to cancel.")
            return

        try:
            title, output = _handle_host_cmd(cmd, args)
            await _send_long(msg.channel, f"**{title}**\n```\n{output}\n```")
        except ValueError:
            await msg.channel.send(f"⚠️  Unknown command: /{cmd}")
        except subprocess.CalledProcessError as exc:
            await _send_long(msg.channel,
                f"❌ command failed (exit {exc.returncode})\n```\n{exc.output.decode()}\n```")
        return

    # Normal assistant interaction
    lock = _channel_locks.setdefault(msg.channel.id, asyncio.Lock())
    if lock.locked():
        await msg.channel.send("⏳ Busy – please wait or type **/interrupt**.")
        return

    t = asyncio.create_task(_handle_request(msg.channel, msg.content))
    _current_tasks[msg.channel.id] = t
    t.add_done_callback(lambda *_:
        _current_tasks.pop(msg.channel.id, None))

# ---------------------------------------------------------------------------
# 12)  run the bot
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    bot.run(DISCORD_BOT_TOKEN)
