# filename: autogen_discord_bot.py
"""
Discord × AutoGen bridge — fully‑autonomous coding agent
────────────────────────────────────────────────────────
* Gemini retry/key‑rotation via gemini_retry_wrapper.py
* Executes code written to agent_workspace/
* Non‑blocking asyncio loop

Changelog (2025‑04‑18)
─────────────────────
• Stop “empty‑loop” yet keep auto‑termination:
    – `UserProxyAgent.default_auto_reply` stays "TERMINATE"
    – _but_ we now ignore any assistant message whose content is exactly
      "TERMINATE" when deciding what to send back to Discord.
• `_last_assistant_content()` now also recognises `role=="assistant"`.
• Small tidy‑ups.
"""

# ── std‑lib / logging setup ──────────────────────────────────────────────
import builtins, os, sys, asyncio, subprocess, re, traceback, textwrap, logging

builtins.input = lambda prompt="": ""      # LLM must never block on stdin
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stderr,
)

# ── environment ─────────────────────────────────────────────────────────
from dotenv import load_dotenv; load_dotenv()

DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
USE_GEMINI        = os.getenv("USE_GEMINI", "false").lower() == "true"
OPENAI_API_KEY    = os.getenv("OPENAI_API_KEY")

GEMINI_API_KEYS: list[str] = (
    [k.strip() for k in os.getenv("GEMINI_API_KEYS", "").split(",") if k.strip()]
    or ([os.getenv("GEMINI_API_KEY").strip()] if os.getenv("GEMINI_API_KEY") else [])
)

if not DISCORD_BOT_TOKEN:
    sys.exit("❌  DISCORD_BOT_TOKEN missing in .env")
if USE_GEMINI and not GEMINI_API_KEYS:
    sys.exit("❌  USE_GEMINI=true but no Gemini key(s) provided")
if not USE_GEMINI and not OPENAI_API_KEY:
    sys.exit("❌  Neither OPENAI_API_KEY nor USE_GEMINI=true provided")

# ── patch Gemini with retry / rotation BEFORE importing Autogen ──────────
if USE_GEMINI:
    from gemini_retry_wrapper import GeminiRetryWrapper  # noqa: F401
    import autogen.oai.gemini as _gm
    _gm.GeminiClient = _gm.Gemini = GeminiRetryWrapper
    GeminiRetryWrapper._KEYS = GEMINI_API_KEYS

# ── third‑party imports ─────────────────────────────────────────────────
import autogen
from autogen.coding import LocalCommandLineCodeExecutor
import discord

# ── LLM config ──────────────────────────────────────────────────────────
llm_config = {
    "temperature": 0.7,
    "cache_seed": None,
    "config_list": [
        {
            "model": "gemini-2.5-pro-exp-03-25" if USE_GEMINI else "gpt-3.5-turbo",
            "api_key": GEMINI_API_KEYS[0] if USE_GEMINI else OPENAI_API_KEY,
            "api_type": "google" if USE_GEMINI else "openai",
        }
    ],
}

# ── workspace & executor ────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WORK_DIR = os.path.join(BASE_DIR, "agent_workspace")
os.makedirs(WORK_DIR, exist_ok=True)

executor = LocalCommandLineCodeExecutor(work_dir=WORK_DIR, timeout=300)

# ── AutoGen agents ───────────────────────────────────────────────────────
assistant = autogen.AssistantAgent(
    name="assistant",
    llm_config=llm_config,
    system_message=textwrap.dedent(
        """
        You are an autonomous coding‑assistant running inside a Discord bot.
        You have full shell access in `agent_workspace/` (read / write / exec).
        ALWAYS run real commands – never simulate.

        Wrap code in ``` with “# filename: …” on the first line.
        When the task is finished output exactly:

            TERMINATE
        """
    ).strip(),
)

user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",             # allow multi‑step loops
    default_auto_reply="TERMINATE",       # prevent empty messages
    max_consecutive_auto_reply=10,
    is_termination_msg=lambda m: (
        not m.get("content", "").strip()  # blank ⇒ terminate
        or m.get("content", "").strip().upper() in {"TERMINATE", "DONE", "TASK COMPLETE"}
    ),
    code_execution_config={"executor": executor},
)

# ── Discord glue ─────────────────────────────────────────────────────────
intents = discord.Intents.default()
intents.message_content = True
bot = discord.Client(intents=intents)
_channel_locks: dict[int, asyncio.Lock] = {}

async def _send_long_msg(channel: discord.TextChannel, text: str) -> None:
    for chunk in [text[i:i+1900] for i in range(0, len(text), 1900)]:
        await channel.send(chunk)


def _run_all() -> list[str]:
    """Execute every *.sh / *.py written by the LLM and capture output."""
    results: list[str] = []
    for fname in sorted(os.listdir(WORK_DIR)):
        path = os.path.join(WORK_DIR, fname)
        try:
            if fname.endswith(".sh"):
                out = subprocess.check_output(["bash", path], cwd=WORK_DIR,
                                              stderr=subprocess.STDOUT, timeout=30)
                results.append(f"✅ {fname} exited 0\n{out.decode() or '(no output)'}")
            elif fname.endswith(".py") and fname != "server.py":
                out = subprocess.check_output([sys.executable, path], cwd=WORK_DIR,
                                              stderr=subprocess.STDOUT, timeout=30)
                results.append(f"✅ {fname} exited 0\n{out.decode() or '(no output)'}")
            elif fname == "server.py":
                proc = subprocess.Popen([sys.executable, path], cwd=WORK_DIR)
                results.append(f"🌐 Started server.py (pid {proc.pid})")
        except subprocess.TimeoutExpired:
            results.append(f"⏱️  {fname} timed‑out after 30 s")
        except subprocess.CalledProcessError as exc:
            results.append(f"❌ {fname} exited {exc.returncode}\n{exc.output.decode()}")
    return results


def _last_assistant_content(history: list[dict]) -> str:
    """Return the last non‑empty assistant message that is *not* only TERMINATE."""
    for m in reversed(history):
        if (
            (m.get("name") == "assistant" or m.get("role") == "assistant")
            and (content := m.get("content", "").strip())
            and content.upper() != "TERMINATE"  # skip pure termination ack
        ):
            return content
    return ""

# ── Discord events ───────────────────────────────────────────────────────
@bot.event
async def on_ready():
    print(f"✅ Logged in as {bot.user} (discord {discord.__version__})  "
          f"AutoGen {autogen.__version__}")

@bot.event
async def on_message(msg: discord.Message):
    if msg.author == bot.user or not msg.content.strip():
        return

    lock = _channel_locks.setdefault(msg.channel.id, asyncio.Lock())
    if lock.locked():
        await msg.channel.send("⏳ Busy – please wait for the current task.")
        return

    async with lock:
        try:
            await msg.channel.typing()

            system_header = textwrap.dedent(
                """
                Your name is **Homonculus**.
                You have full shell access in this sandbox VM (`agent_workspace/`).

                • read / write / exec any file
                • run any CLI command (non‑interactive)

                NEVER simulate commands – **always** run them for real.

                Code block rules
                ────────────────
                * wrap code in triple‑back‑ticks
                * first line inside block:  `# filename: …`

                When the task is complete output the single word **TERMINATE**.
                """
            ).strip()

            first_message = f"{system_header}\n\n{msg.content}"

            loop = asyncio.get_running_loop()
            chat_result = await loop.run_in_executor(
                None,
                lambda: user_proxy.initiate_chat(
                    assistant, message=first_message, clear_history=True
                ),
            )

            # write any files emitted by the assistant
            assistant_msgs = [
                m["content"] for m in chat_result.chat_history
                if (m.get("name") == "assistant" or m.get("role") == "assistant")
            ]
            patt = re.compile(r"```(?:\w+)?\s*\n# filename: ([^\n]+)\n(.*?)```",
                              re.DOTALL)
            wrote = False
            for m_ in patt.finditer("\n".join(assistant_msgs)):
                fname, code = m_.group(1).strip(), m_.group(2)
                fpath = os.path.join(WORK_DIR, fname)
                os.makedirs(os.path.dirname(fpath), exist_ok=True)
                with open(fpath, "w", encoding="utf‑8") as f:
                    f.write(code)
                wrote = True

            if wrote:
                exec_out = await loop.run_in_executor(None, _run_all)
                if exec_out:
                    user_proxy.send("Execution results:\n" + "\n\n".join(exec_out),
                                    recipient=assistant)

            reply = _last_assistant_content(chat_result.chat_history)
            if reply:
                await _send_long_msg(msg.channel, reply)
            else:
                await msg.channel.send("⚠️  No assistant reply (only TERMINATE).")

        except Exception as exc:
            traceback.print_exc()
            await msg.channel.send(f"⚠️  Internal error: {exc}")

# ── run the bot ───────────────────────────────────────────────────────────
if __name__ == "__main__":
    bot.run(DISCORD_BOT_TOKEN)
