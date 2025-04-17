# filename: autogen_discord_bot.py
import builtins, os, sys, re, asyncio, subprocess, traceback, textwrap
from dotenv import load_dotenv
load_dotenv()
builtins.input = lambda prompt="": ""

DISCORD_BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")
OPENAI_API_KEY    = os.getenv("OPENAI_API_KEY")
GEMINI_API_KEY    = os.getenv("GEMINI_API_KEY")
USE_GEMINI        = os.getenv("USE_GEMINI", "false").lower() == "true"

if not DISCORD_BOT_TOKEN:
    sys.exit("❌  DISCORD_BOT_TOKEN missing")
if USE_GEMINI and not GEMINI_API_KEY:
    sys.exit("❌  GEMINI_API_KEY missing")
if not USE_GEMINI and not OPENAI_API_KEY:
    sys.exit("❌  OPENAI_API_KEY missing")

import discord, autogen
from autogen.coding import LocalCommandLineCodeExecutor

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WORK_DIR = os.path.join(BASE_DIR, "agent_workspace")
os.makedirs(WORK_DIR, exist_ok=True)

executor = LocalCommandLineCodeExecutor(timeout=600, work_dir=WORK_DIR)

llm_config = {
    "cache_seed": None,
    "temperature": 0.2,
    "config_list": [{
        "api_type": "google" if USE_GEMINI else "openai",
        "api_key":  GEMINI_API_KEY if USE_GEMINI else OPENAI_API_KEY,
        "model":    "gemini-1.5-pro" if USE_GEMINI else "gpt-3.5-turbo",
    }],
}

PREFIX = textwrap.dedent("""
    Your name is **Homonculus**.
    You have full shell access in this sandbox VM (folder `agent_workspace/`).

    • read / write / exec any file
    • run any CLI command (non‑interactive)

    NEVER simulate commands – always run them for real.

    Code block rules
    ────────────────
    * wrap code in triple‑back‑ticks
    * first line inside block:  # filename: …

    Finish every reply with the single word **TERMINATE**.
""").strip()

assistant = autogen.AssistantAgent(
    name="assistant",
    llm_config=llm_config,
    system_message=PREFIX if not USE_GEMINI else autogen.AssistantAgent.DEFAULT_SYSTEM_MESSAGE,
)

user_proxy = autogen.UserProxyAgent(
    name="user_proxy",
    human_input_mode="NEVER",
    max_consecutive_auto_reply=1,
    is_termination_msg=lambda m: str(m.get("content","")).strip().endswith("TERMINATE"),
    code_execution_config={"executor": executor},
)

# ---------- helpers -------------------------------------------------------- #
def _extract_and_write(texts):
    pat = re.compile(r"```(?:\w+)?\s*\n# filename:\s*([^\n]+)\n(.*?)```", re.DOTALL)
    written=[]
    for txt in texts:
        for m in pat.finditer(txt):
            fname, code = m.group(1).strip(), m.group(2)
            path = os.path.join(WORK_DIR, fname)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path,"w",encoding="utf-8") as f: f.write(code)
            written.append(fname)
    return written

def _run_all():
    res=[]
    for fname in sorted(os.listdir(WORK_DIR)):
        path=os.path.join(WORK_DIR,fname)
        if fname.endswith(".py"):
            bg = fname in {"serve.py","server.py","http_server.py"}
            if bg:
                p=subprocess.Popen([sys.executable,path],cwd=WORK_DIR,
                                   stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
                res.append(f"▶️  Started {fname} (pid {p.pid})")
            else:
                try:
                    out=subprocess.check_output([sys.executable,path],cwd=WORK_DIR,
                                                stderr=subprocess.STDOUT,text=True,timeout=300)
                    res.append(f"✅ {fname} exited 0\n{out.strip()}")
                except subprocess.CalledProcessError as e:
                    res.append(f"❌ {fname} exited {e.returncode}\n{e.output}")
        elif fname.endswith(".sh"):
            try:
                out=subprocess.check_output(["bash",path],cwd=WORK_DIR,
                                            stderr=subprocess.STDOUT,text=True,timeout=300)
                res.append(f"✅ {fname} exited 0\n{out.strip()}")
            except subprocess.CalledProcessError as e:
                res.append(f"❌ {fname} exited {e.returncode}\n{e.output}")
    return res

def _autogen_turn(prompt:str):
    if USE_GEMINI:
        prompt = PREFIX+"\n\n"+prompt
    result=user_proxy.initiate_chat(assistant,message=prompt,clear_history=False)
    texts=[m.get("content","") for m in result.chat_history if isinstance(m,dict) and m.get("name")=="assistant"]
    return texts

# ---------- discord bot ---------------------------------------------------- #
intents=discord.Intents.default(); intents.message_content=True
bot=discord.Client(intents=intents)
locks:dict[int,asyncio.Lock]={}

@bot.event
async def on_ready(): print(f"✅ Logged in as {bot.user}")

@bot.event
async def on_message(msg:discord.Message):
    if msg.author==bot.user: return
    lock=locks.setdefault(msg.channel.id,asyncio.Lock())
    async with lock:
        async with msg.channel.typing():
            try:
                loop=asyncio.get_running_loop()
                assistant_txts = await loop.run_in_executor(None,_autogen_turn,msg.content)
                written=_extract_and_write(assistant_txts)
                exec_res=_run_all()
                if exec_res:
                    # ---- FIXED call (positional message argument) ---- #
                    user_proxy.send(
                        recipient=assistant,
                        message="Execution results:\n" + "\n\n".join(exec_res)
                    )
                last=assistant_txts[-1].rstrip().removesuffix("TERMINATE").strip()
                parts=[last or "*(no reply)*"]
                if written: parts.append("📄 Files written: "+", ".join(written))
                if exec_res: parts.append("🖥️  Execution results:\n"+ "\n\n".join(exec_res))
                reply="\n\n".join(parts)

                if len(reply)>1990:
                    await msg.channel.send("*(response split)*")
                    for i in range(0,len(reply),1990):
                        await msg.channel.send(f"```{reply[i:i+1990]}```")
                else:
                    await msg.channel.send(reply)
            except Exception as e:
                traceback.print_exc()
                await msg.channel.send(f"❌ Error: {e}")

if __name__=="__main__":
    discord.utils.setup_logging()
    bot.run(DISCORD_BOT_TOKEN)
