# filename: gemini_retry_wrapper.py
"""
GeminiRetryWrapper
──────────────────
Works with autogen ≤ 0.2.39 (“Gemini”) **and** ≥ 0.2.40 (“GeminiClient”).

Adds
• exponential‑and‑jitter back‑off for 429 / 5xx
• honours Google’s `retry_delay`
• automatic API‑key rotation (round‑robin) from $GEMINI_API_KEYS
• global wall‑clock cut‑off (default 8 h)

On import we *surgically replace* every already‑cached reference
to the original Gemini class across **all** loaded modules, so the
wrapper is guaranteed to be used.
"""

from __future__ import annotations
import os, sys, time, random, re, logging, itertools
from importlib import import_module
from typing import Any, Dict, List

# ── basic logging ────────────────────────────────────────────────────────────
_LOG = logging.getLogger("GeminiRetryWrapper")
_LOG.setLevel(logging.INFO)          # change to DEBUG for very chatty output

# ── grab the original Gemini class regardless of Autogen version ─────────────
gemini_mod = import_module("autogen.oai.gemini")
BaseGemini = (
    getattr(gemini_mod, "GeminiClient", None)
    or getattr(gemini_mod, "Gemini", None)
)
if BaseGemini is None:  # pragma: no cover
    raise ImportError("Could not locate Gemini / GeminiClient in Autogen")

# ── helper: parse Google’s explicit retry delay (if present) ─────────────────
_RE_DELAY = re.compile(r"retry_delay\s*{\s*seconds:\s*(\d+)", re.I)
def _extract_retry_delay(msg: str) -> int | None:
    m = _RE_DELAY.search(msg)
    return int(m.group(1)) if m else None

# ─────────────────────────────────────────────────────────────────────────────
class GeminiRetryWrapper(BaseGemini):                    # noqa: N801
    """Drop‑in replacement with robust retrying & key cycling."""

    # defaults (override from the outside if you like)
    MAX_TOTAL_SECONDS = 8 * 60 * 60        # 8 h overall budget
    BASE_BACKOFF      = 1.0                # seconds
    MAX_BACKOFF       = 300                # 5 min cap
    KEY_ROTATE_EVERY  = 3                  # failures per key before rotating

    # key‑pool shared by *all* instances
    _KEYS: List[str] = []
    _key_cycle = None

    # ── life‑cycle ───────────────────────────────────────────────────────────
    def __init__(self, *args: Any, **kw: Any):
        """
        Accepts the same kwargs the original class does.
        The passed‑in `api_key` is ignored – keys are injected automatically.
        """
        super().__init__(*args, **kw)

        # initialise key‑pool once
        if not GeminiRetryWrapper._KEYS:
            env_keys = os.getenv("GEMINI_API_KEYS", "")
            if env_keys:
                GeminiRetryWrapper._KEYS = [k.strip() for k in env_keys.split(",") if k.strip()]
        if not GeminiRetryWrapper._KEYS:
            single_key = os.getenv("GEMINI_API_KEY") or kw.get("api_key")
            if single_key:
                GeminiRetryWrapper._KEYS = [single_key]

        if not GeminiRetryWrapper._KEYS:      # pragma: no cover
            raise RuntimeError("GeminiRetryWrapper: no API keys provided")

        if GeminiRetryWrapper._key_cycle is None:
            GeminiRetryWrapper._key_cycle = itertools.cycle(GeminiRetryWrapper._KEYS)

        self._switch_key(next(GeminiRetryWrapper._key_cycle))

    # ── helpers ──────────────────────────────────────────────────────────────
    def _switch_key(self, key: str) -> None:
        """Hot‑swap the API key inside both wrapper *and* underlying client."""
        self.api_key = key
        if hasattr(self, "client"):      # autogen ≥ 0.2.40
            self.client.api_key = key
        elif hasattr(self, "_client"):   # autogen ≤ 0.2.39
            self._client.api_key = key
        _LOG.info("🔑  using Gemini key ****%s", key[-4:])

    # ── main override: retry loop ────────────────────────────────────────────
    def create(self, params: Dict[str, Any]):   # type: ignore[override]
        start = time.time()
        attempt = 0
        backoff = self.BASE_BACKOFF
        failures_on_key = 0

        while True:
            if time.time() - start > self.MAX_TOTAL_SECONDS:
                raise RuntimeError(
                    f"GeminiRetryWrapper: gave up after "
                    f"{(time.time() - start) / 3600:.1f} h of continuous failures"
                )

            try:
                return super().create(params)

            except Exception as exc:  # broad – we filter below
                msg = str(exc)
                retriable = (
                    "429" in msg or "quota" in msg or
                    any(code in msg for code in ("500", "502", "503", "504"))
                )
                if not retriable:
                    raise      # bubble‐up non‑quota errors immediately

                attempt += 1
                failures_on_key += 1

                delay = _extract_retry_delay(msg)
                if delay is None:
                    delay = min(backoff, self.MAX_BACKOFF)
                    backoff = min(backoff * 2, self.MAX_BACKOFF)
                    delay *= random.uniform(1.0, 1.3)   # jitter

                _LOG.warning(
                    "⏳  retry #%d in %.1f s – %s",
                    attempt, delay, msg.splitlines()[0][:120]
                )
                time.sleep(delay)

                if (
                    failures_on_key >= self.KEY_ROTATE_EVERY
                    and len(self._KEYS) > 1
                ):
                    self._switch_key(next(GeminiRetryWrapper._key_cycle))
                    failures_on_key = 0

# ── global hot‑patch: swap EVERY stale reference in already‑loaded modules ──
def _retarget_stale_refs() -> None:
    for mod in list(sys.modules.values()):
        if not mod:
            continue
        try:
            if getattr(mod, "GeminiClient", None) is BaseGemini:
                setattr(mod, "GeminiClient", GeminiRetryWrapper)
            if getattr(mod, "Gemini", None) is BaseGemini:
                setattr(mod, "Gemini", GeminiRetryWrapper)
        except Exception:   # some modules are silly – just skip
            continue

_retarget_stale_refs()

# also replace the symbols inside the *defining* module
setattr(gemini_mod, "GeminiClient", GeminiRetryWrapper)
setattr(gemini_mod, "Gemini", GeminiRetryWrapper)

# utility so the Discord bot can surface long‑running failure notices
def send_discord_system_message(message: str) -> None:  # noqa: D401
    """This will be monkey‑patched by autogen_discord_bot.py at runtime."""
    _LOG.error("[SYSTEM‑MSG] %s", message)
