# filename: autogen_discord_bot.py
from __future__ import annotations
import asyncio, builtins, logging, os, re, shlex, signal, subprocess, sys, textwrap
from pathlib import Path
from typing import List

builtins.input = lambda _="": ""
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stderr,
)
_LOG = logging.getLogger("discord‑bot")

from dotenv import load_dotenv; load_dotenv()

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

if USE_GEMINI:
    from gemini_retry_wrapper import GeminiRetryWrapper  # noqa: F401
    import autogen.oai.gemini as _gm
    _gm.GeminiClient = _gm.Gemini = GeminiRetryWrapper
    GeminiRetryWrapper._KEYS = GEMINI_API_KEYS

import autogen
from autogen.coding import LocalCommandLineCodeExecutor
import discord

BASE_DIR = Path(__file__).resolve().parent
WORK_DIR = BASE_DIR / "agent_workspace"
WORK_DIR.mkdir(exist_ok=True)

executor = LocalCommandLineCodeExecutor(work_dir=str(WORK_DIR), timeout=300)

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
    name="assistant",
    llm_config=llm_config,
    system_message=textwrap.dedent(
        """
        You are an autonomous coding‑assistant running inside a Discord bot.
        You have full shell access in `agent_workspace/` (read / write / exec).

        • ALWAYS run real commands – never simulate.
        • If you need a long‑running server, start it with:
              nohup <command> >server.log 2>&1 & disown

        Wrap code in ``` … ``` with “# filename: …” on the first line.
        When the entire task is finished output exactly:

            TERMINATE
        """
    ).strip(),
)

user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",
    max_consecutive_auto_reply=0,          # ← stop the blank echoes
    default_auto_reply="TERMINATE",        # ← belt‑and‑braces
    is_termination_msg=lambda m: (
        m.get("content", "").strip().upper() in {"TERMINATE", "TASK COMPLETE", "DONE"}
    ),
    code_execution_config={"executor": executor},
)

intents = discord.Intents.default()
intents.message_content = True
bot = discord.Client(intents=intents)

_channel_locks: dict[int, asyncio.Lock] = {}
_current_tasks: dict[int, asyncio.Task] = {}
_spawned_pids: set[int] = set()

_SERVER_PATTERNS = [
    re.compile(r"python3?\s+-m\s+http\.server\s+\d+", re.I),
    re.compile(r"flask\s+run\b", re.I),
    re.compile(r"node\s+\S+\.js\b", re.I),
    re.compile(r"(npm|pnpm|yarn)\s+(run\s+)?start\b", re.I),
]

def _spawn_daemon(cmd: str) -> int:
    proc = subprocess.Popen(
        shlex.split(cmd.split("&")[0].strip()),
        cwd=WORK_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    _spawned_pids.add(proc.pid)
    _LOG.info("🌐 spawned daemon: %s  (pid %d)", cmd, proc.pid)
    return proc.pid

def _strip_server_lines(script: str) -> tuple[str, list[str]]:
    kept, spawned = [], []
    for line in script.splitlines():
        if any(p.search(line) for p in _SERVER_PATTERNS):
            spawned.append(line)
        else:
            kept.append(line)
    return "\n".join(kept) + "\n", spawned

def _run_all() -> list[str]:
    results: list[str] = []

    for path in WORK_DIR.glob("*.sh"):
        cleaned, to_spawn = _strip_server_lines(path.read_text())
        if to_spawn:
            path.write_text(cleaned)
            for cmd in to_spawn:
                pid = _spawn_daemon(cmd)
                results.append(f"🌐 Started background server “{cmd.strip()}” (pid {pid})")

    for path in WORK_DIR.iterdir():
        fname = path.name
        try:
            if fname.endswith(".sh"):
                out = subprocess.check_output(["bash", str(path)],
                                              cwd=WORK_DIR, stderr=subprocess.STDOUT, timeout=30)
                results.append(f"✅ {fname} exited 0\n{out.decode() or '(no output)'}")
            elif fname.endswith(".py") and fname != "server.py":
                out = subprocess.check_output([sys.executable, str(path)],
                                              cwd=WORK_DIR, stderr=subprocess.STDOUT, timeout=30)
                results.append(f"✅ {fname} exited 0\n{out.decode() or '(no output)'}")
            elif fname == "server.py":
                pid = _spawn_daemon(f"python3 {fname}")
                results.append(f"🌐 Started server.py (pid {pid})")
        except subprocess.TimeoutExpired:
            results.append(f"⏱️  {fname} timed‑out after 30 s")
        except subprocess.CalledProcessError as exc:
            results.append(f"❌ {fname} exited {exc.returncode}\n{exc.output.decode()}")
    return results

def _last_assistant_content(history: list[dict]) -> str:
    for msg in reversed(history):
        if msg.get("name") == "assistant" and msg.get("content", "").strip():
            return msg["content"]
    return ""

async def _send_long_msg(channel: discord.abc.Messageable, text: str) -> None:
    for chunk in [text[i:i+1900] for i in range(0, len(text), 1900)]:
        await channel.send(chunk)

async def _handle_request(channel: discord.abc.Messageable, content: str) -> None:
    lock = _channel_locks.setdefault(channel.id, asyncio.Lock())
    async with lock:
        try:
            await channel.typing()

            header = textwrap.dedent(
                """
                Your name is **Homonculus**.
                You have full shell access in this sandbox VM (`agent_workspace/`).

                • read / write / exec any file
                • run any CLI command (non‑interactive)
                • If you need a long‑running server use
                    `nohup … >server.log 2>&1 & disown`

                NEVER simulate commands – **always** run them for real.
                Wrap code in triple‑back‑ticks, first line `# filename: …`
                When the task is complete output **TERMINATE**.
                """
            ).strip()

            first_msg = f"{header}\n\n{content}"

            loop = asyncio.get_running_loop()
            chat_result = await loop.run_in_executor(
                None,
                lambda: user_proxy.initiate_chat(
                    assistant, message=first_msg, clear_history=True
                )
            )

            pattern = re.compile(r"```(?:\w+)?\s*\n# filename: ([^\n]+)\n(.*?)```", re.DOTALL)
            files_written = False
            assistant_msgs = [m["content"] for m in chat_result.chat_history if m["name"] == "assistant"]
            for m in pattern.finditer("\n".join(assistant_msgs)):
                fname, code = m.group(1).strip(), m.group(2)
                path = WORK_DIR / fname
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(code)
                files_written = True

            if files_written:
                exec_out = await loop.run_in_executor(None, _run_all)
                if exec_out:
                    user_proxy.send("Execution results:\n" + "\n\n".join(exec_out),
                                    recipient=assistant)
            # grab the last *non‑empty* assistant message so we never forward
            # the blank echo that UserProxy may add at the tail of history
            reply = _last_assistant_content(chat_result.chat_history)

            if not reply.strip():
                reply = "⚠️  No reply generated (empty turn filtered)."

            await _send_long_msg(channel, reply)

        except asyncio.CancelledError:
            await channel.send("🚫  Task cancelled.")
            raise
        except Exception as exc:
            _LOG.error("Error in handler: %s", exc, exc_info=True)
            await channel.send(f"⚠️  Internal error: {exc}")

@bot.event
async def on_ready():
    print(f"✅ Logged in as {bot.user} (discord {discord.__version__})  "
          f"AutoGen {autogen.__version__}")

@bot.event
async def on_message(message: discord.Message):
    if message.author == bot.user:
        return

    if message.content.strip().lower() in {"!cancel", "!abort"}:
        task = _current_tasks.get(message.channel.id)
        if task and not task.done():
            task.cancel()
            await message.channel.send("🚫  Current task cancelled.")
        else:
            await message.channel.send("⚠️  No running task to cancel.")
        return

    lock = _channel_locks.setdefault(message.channel.id, asyncio.Lock())
    if lock.locked():
        await message.channel.send("⏳ Busy – please wait or type **!cancel**.")
        return

    task = asyncio.create_task(_handle_request(message.channel, message.content))
    _current_tasks[message.channel.id] = task
    task.add_done_callback(lambda _: _current_tasks.pop(message.channel.id, None))

if __name__ == "__main__":
    bot.run(DISCORD_BOT_TOKEN)
