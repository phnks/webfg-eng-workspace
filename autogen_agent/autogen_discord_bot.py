# filename: autogen_discord_bot.py
"""
Discord × AutoGen bridge — fully‑autonomous coding agent
─────────────────────────────────────────────────────────
* The assistant can read / write / exec anything inside  agent_workspace/
* All CLI commands are run for real; their stdout/err is returned to the LLM
* The event‑loop never blocks (heavy work is off‑loaded to a worker thread)
"""

# ── monkey‑patch input so the LLM can’t hang waiting for stdin ────────────────
import builtins, os, sys, asyncio, subprocess, re, traceback
builtins.input = lambda prompt="": ""

from functools import partial
from dotenv import load_dotenv
import autogen
from autogen.coding import LocalCommandLineCodeExecutor
import discord

# ── env & basic checks ────────────────────────────────────────────────────────
load_dotenv()
DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
OPENAI_API_KEY   = os.getenv("OPENAI_API_KEY")
GEMINI_API_KEY   = os.getenv("GEMINI_API_KEY")
USE_GEMINI       = os.getenv("USE_GEMINI", "false").lower() == "true"

if not DISCORD_BOT_TOKEN:
    sys.exit("DISCORD_BOT_TOKEN missing in .env")

if USE_GEMINI and not GEMINI_API_KEY:
    sys.exit("GEMINI_API_KEY missing while USE_GEMINI=true")
if not USE_GEMINI and not OPENAI_API_KEY:
    sys.exit("OPENAI_API_KEY missing; set USE_GEMINI=true to use Gemini")

# ── LLM config ────────────────────────────────────────────────────────────────
llm_config = {
    "temperature": 0.7,
    "cache_seed": None,
    "config_list": [
        {
            "model": "gemini-2.5-pro-exp-03-25" if USE_GEMINI else "gpt-3.5-turbo",
            "api_key": GEMINI_API_KEY if USE_GEMINI else OPENAI_API_KEY,
            "api_type": "google"         if USE_GEMINI else "openai",
        }
    ]
}

# ── workspace & executor ──────────────────────────────────────────────────────
BASE_DIR  = os.path.dirname(os.path.abspath(__file__))
WORK_DIR  = os.path.join(BASE_DIR, "agent_workspace")
os.makedirs(WORK_DIR, exist_ok=True)

executor = LocalCommandLineCodeExecutor(
    work_dir=WORK_DIR,
    timeout=300,        # 5‑minute cap per code block
)

# ── AutoGen agents ────────────────────────────────────────────────────────────
assistant = autogen.AssistantAgent(
    name="assistant",
    llm_config=llm_config,
    system_message=autogen.AssistantAgent.DEFAULT_SYSTEM_MESSAGE
)

user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",
    max_consecutive_auto_reply=10,        # allow multi‑step iterations
    is_termination_msg=lambda m: m.get("content", "").strip() in
        {"TERMINATE", "TASK COMPLETE", "DONE"},
    code_execution_config={"executor": executor},
)

# ── Discord setup ─────────────────────────────────────────────────────────────
intents = discord.Intents.default()
intents.message_content = True
bot = discord.Client(intents=intents)

channel_locks = {}          # only one task at a time per channel

# ── helper: run all generated *.sh / *.py files and collect outputs ───────────
def _run_all():
    exec_out = []
    # run *.sh first (they often start servers)
    for fname in sorted(os.listdir(WORK_DIR)):
        path = os.path.join(WORK_DIR, fname)
        try:
            if fname.endswith(".sh"):
                out = subprocess.check_output(
                    ["bash", path],
                    cwd=WORK_DIR,
                    stderr=subprocess.STDOUT,
                    timeout=30,            # safety – no infinite loops
                )
                exec_out.append(f"✅ {fname} exited 0\n{out.decode() or '(no output)'}")
            elif fname.endswith(".py") and fname != "server.py":
                out = subprocess.check_output(
                    [sys.executable, path],
                    cwd=WORK_DIR,
                    stderr=subprocess.STDOUT,
                    timeout=30,
                )
                exec_out.append(f"✅ {fname} exited 0\n{out.decode() or '(no output)'}")
            elif fname == "server.py":
                proc = subprocess.Popen([sys.executable, path], cwd=WORK_DIR)
                exec_out.append(f"🌐 Started server.py (pid {proc.pid})")
        except subprocess.TimeoutExpired:
            exec_out.append(f"⏱️  {fname} timed‑out after 30 s")
        except subprocess.CalledProcessError as e:
            exec_out.append(f"❌ {fname} exited {e.returncode}\n{e.output.decode()}")
    return exec_out

# ── Discord events ────────────────────────────────────────────────────────────
@bot.event
async def on_ready():
    print(f"✅ Logged in as {bot.user} ({discord.__version__=})  AutoGen {autogen.__version__}")

@bot.event
async def on_message(msg: discord.Message):
    if msg.author == bot.user:        # ignore self
        return

    lock = channel_locks.setdefault(msg.channel.id, asyncio.Lock())
    if lock.locked():
        await msg.channel.send("Busy with the previous task – please wait.")
        return

    async with lock:
        try:
            await msg.channel.typing()

            # build the first prompt the assistant sees
            system_header = (
                "Your name is **Homonculus**.\n"
                "You have full shell access in this sandbox VM (`agent_workspace/`).\n\n"
                "• read / write / exec any file\n"
                "• run any CLI command (non‑interactive)\n\n"
                "NEVER simulate commands – **always** run them for real.\n\n"
                "Code block rules\n"
                "────────────────\n"
                "* wrap code in triple‑back‑ticks\n"
                "* first line inside block:  `# filename: …`\n\n"
                "When the entire task is complete output the single word **TERMINATE**."
            )

            first_message = f"{system_header}\n\n{msg.content}"

            # ── run AutoGen dialogue in a worker thread so Discord loop stays alive
            loop = asyncio.get_running_loop()
            chat_result = await loop.run_in_executor(
                None,
                lambda: user_proxy.initiate_chat(
                    assistant,
                    message=first_message,
                    clear_history=True
                )
            )

            # ── write any files the assistant produced ───────────────────────
            files_created = []
            pattern = re.compile(r"```(?:\w+)?\s*\n# filename: ([^\n]+)\n(.*?)```", re.DOTALL)
            for m in pattern.finditer("\n".join(
                m["content"] for m in chat_result.chat_history if m["name"] == "assistant"
            )):
                fname, code = m.group(1).strip(), m.group(2)
                fpath = os.path.join(WORK_DIR, fname)
                os.makedirs(os.path.dirname(fpath), exist_ok=True)
                with open(fpath, "w", encoding="utf-8") as f:
                    f.write(code)
                files_created.append(fname)

            # ── execute them (in worker thread too) ─────────────────────────
            exec_out = await loop.run_in_executor(None, _run_all)

            # ── send execution results back into the AutoGen conversation ──
            if exec_out:
                user_proxy.send(assistant, "Execution results:\n" + "\n\n".join(exec_out))

            # ── last assistant message (after possible follow‑up) ───────────
            final_reply = chat_result.chat_history[-1]["content"]
            if len(final_reply) > 1900:
                # split long reply into chunks
                for chunk in [final_reply[i:i+1900] for i in range(0, len(final_reply), 1900)]:
                    await msg.channel.send(chunk)
            else:
                await msg.channel.send(final_reply)

        except Exception as e:
            traceback.print_exc()
            await msg.channel.send(f"⚠️  Internal error: {e}")

# ── run the bot ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    bot.run(DISCORD_BOT_TOKEN)
