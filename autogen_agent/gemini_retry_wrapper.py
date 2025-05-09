# filename: gemini_retry_wrapper.py
"""
GeminiRetryWrapper
──────────────────
Works with pyautogen ≤ 0.8**and** ≥ 0.9

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
import sys, logging, random, time, re, os, itertools
from importlib import import_module
from typing import Any, Dict, List
import tiktoken # Added for token counting

# ── basic logging ────────────────────────────────────────────────────────────
_LOG = logging.getLogger("GeminiRetryWrapper")
_LOG.setLevel(logging.INFO)          # change to DEBUG for very chatty output


# --- Custom Exception ---
class EmptyApiResponseError(Exception):
    """Raised when the Gemini API returns a response without expected content (e.g., no candidates)."""
    pass
# --- End Custom Exception ---


# ── token limits ───────────────────────────────────────────────────────────
# Gemini’s absolute cap is 1 048 576 tokens.  We keep a small safety margin
# so the real request can never trip the hard ceiling even if our estimate
# is a bit low.
HARD_TOKEN_LIMIT = 1_048_576
SAFETY_MARGIN     = 8_192            # ≈ 8 k head-room
MAX_TOTAL_TOKENS  = HARD_TOKEN_LIMIT - SAFETY_MARGIN   # 1 040 384
try:
    # Using cl100k_base as a general-purpose tokenizer suitable for recent models
    tokenizer = tiktoken.get_encoding("cl100k_base")
    _LOG.info("✅ tiktoken tokenizer (cl100k_base) initialized for context pruning.")
except Exception:
    _LOG.warning("⚠️ tiktoken cl100k_base not found, falling back to gpt-2. Token estimation might be less accurate.")
    try:
        tokenizer = tiktoken.get_encoding("gpt2")
        _LOG.info("✅ tiktoken tokenizer (gpt2 fallback) initialized for context pruning.")
    except Exception:
        _LOG.error("❌ Failed to initialize tiktoken tokenizer. Context pruning disabled.")
        tokenizer = None

def _estimate_tokens(messages: List[Dict[str, Any]]) -> int:
    """Estimates token count for a list of messages using tiktoken."""
    if not tokenizer:
        return 0 # Pruning disabled if tokenizer failed

    num_tokens = 0
    for message in messages:
        # Approximation based on OpenAI cookbooks: Add tokens for role/name and content
        # ~4 tokens per message for overhead (role, separators, etc.)
        num_tokens += 4
        for key, value in message.items():
            if isinstance(value, str):
                try:
                    encoded = tokenizer.encode(value)
                    num_tokens += len(encoded)
                except Exception as e:
                    # Log encoding errors but continue estimation
                    _LOG.debug(f"tiktoken encoding failed for value fragment: '{value[:50]}...' Error: {e}")
            # Add handling here if messages contain non-string parts that need token counting
    num_tokens += 2 # Add a few tokens for the final assistant prompt start approximation
    return num_tokens
# --- End Tokenizer Setup ---


# -------------------------------------------------------------------------
# Find the Gemini client class regardless of Autogen version
# -------------------------------------------------------------------------
_CANDIDATES = [
    "autogen.provider.google.gemini",   # ≥ 0.9
    "autogen.oai.gemini",               # ≤ 0.8
]
BaseGemini = None
for path in _CANDIDATES:
    try:
        _mod = import_module(path)
    except ModuleNotFoundError:
        continue
    for _name in ("GeminiClient", "Gemini", "GoogleGemini"):
        BaseGemini = getattr(_mod, _name, None)
        if BaseGemini:
            gemini_mod = _mod      # remember which module worked
            break
    if BaseGemini:
        break
if BaseGemini is None:
    raise ImportError("❌  Could not locate Gemini client class in Autogen")

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
        self._tokenizer = tokenizer # Store tokenizer instance if needed later

    # ── helpers ──────────────────────────────────────────────────────────────
    def _switch_key(self, key: str) -> None:
        """Hot‑swap the API key inside both wrapper *and* underlying client."""
        self.api_key = key
        if hasattr(self, "client"):      # autogen ≥ 0.2.40
            self.client.api_key = key
        elif hasattr(self, "_client"):   # autogen ≤ 0.2.39
            self._client.api_key = key
        _LOG.info("🔑  using Gemini key ****%s", key[-4:])
    
    # --- override cost to survive models that omit cost -------------------
    def cost(self, response: Any):  # type: ignore[override]
        """Return 0 if the model does not provide cost information."""
        if response is None:
            return 0.0
        return getattr(response, "cost", 0.0)

    # ── main override: retry loop ────────────────────────────────────────────
    def create(self, params: Dict[str, Any]):   # type: ignore[override]
        # --- Add logging before the call for potential debugging ---
        _LOG.debug(f"Calling Gemini API with params: {params}") # Keep commented unless debugging

        start = time.time()
        attempt = 0
        backoff = self.BASE_BACKOFF
        failures_on_key = 0

        # First one-off prune before we enter the retry loop
        self._aggressive_prune(params)

        while True:
            # Prune again on *every* retry – our previous estimate might have
            # been too low.
            self._aggressive_prune(params)
            if time.time() - start > self.MAX_TOTAL_SECONDS:
                _LOG.error(f"⏰ GeminiRetryWrapper: Exceeded MAX_TOTAL_SECONDS ({self.MAX_TOTAL_SECONDS}s). Giving up.")
                raise RuntimeError(
                    f"GeminiRetryWrapper: gave up after "
                    f"{(time.time() - start) / 3600:.1f} h of continuous failures"
                )

            try:
                response = super().create(params)
                # ── NEW: guard against empty responses ────────────────────
                if response is None:
                    raise EmptyApiResponseError(
                        "Gemini API returned an empty response (None)."
                    )                # --- Add logging after the call ---
                # _LOG.debug(f"Received Gemini API response: {response}") # Keep commented unless debugging
                return response

            except IndexError as idx_exc:
                # Specifically catch IndexError: list index out of range
                msg = str(idx_exc)
                if "list index out of range" in msg:
                    _LOG.error(
                        f"🚨 Gemini API returned empty/unexpected response (IndexError): {msg}. "
                        f"This request will not be retried.",
                        exc_info=True # Include traceback in log
                    )
                    # Raise custom error instead of retrying
                    raise EmptyApiResponseError(
                        "Gemini API returned no valid candidates or content for this request."
                    ) from idx_exc
                else:
                    # If it's a different IndexError, treat as unexpected and raise
                    _LOG.error(f"❌ Unexpected IndexError encountered: {idx_exc}", exc_info=True)
                    raise idx_exc

            except Exception as exc:  # Catch other exceptions for retries
                msg = str(exc)
                # Check only for standard retriable HTTP codes now
                is_http_retriable = (
                    "429" in msg or "quota" in msg or
                    any(code in msg for code in ("500", "502", "503", "504"))
                )

                if not is_http_retriable:
                    _LOG.error(f"❌ Non-retriable error encountered: {exc}", exc_info=True)
                    raise exc # Re-raise non-retriable errors immediately

                # --- Retry logic for HTTP 429/5xx errors ---
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

    # --- helper ---------------------------------------------------------------
    def _aggressive_prune(self, params: Dict[str, Any]) -> None:
        """Remove oldest user/assistant turns (never the system prompt)
        until the conversation fits under MAX_TOTAL_TOKENS."""
        if not (self._tokenizer and "messages" in params):
            return

        messages = params["messages"]
        if not (messages and isinstance(messages, list)):
            return

        is_system_first = messages[0].get("role") == "system"
        prune_from = 1 if is_system_first else 0

        while _estimate_tokens(messages) > MAX_TOTAL_TOKENS and len(messages) > prune_from + 1:
            del messages[prune_from]
        params["messages"] = messages

        # Log when we had to chop something
        if _estimate_tokens(messages) > MAX_TOTAL_TOKENS:
            _LOG.error(
                "🚨 Even after pruning, token estimate %d exceeds %d. "
                "Request will probably fail.",
                _estimate_tokens(messages), MAX_TOTAL_TOKENS,
            )

        else:
            _LOG.debug(
                "✂️  After pruning conversation is %d tokens (limit %d).",
                _estimate_tokens(messages), MAX_TOTAL_TOKENS,
            )

def _retarget_stale_refs(replacement):
    for mod in list(sys.modules.values()):
        if not mod:
            continue
        for attr in ("GeminiClient", "Gemini", "GoogleGemini"):
            if getattr(mod, attr, None) is BaseGemini:
                setattr(mod, attr, replacement)

_retarget_stale_refs(GeminiRetryWrapper)          # for already‑imported refs
for attr in ("GeminiClient", "Gemini", "GoogleGemini"):
    setattr(gemini_mod, attr, GeminiRetryWrapper) # for future imports

# utility so the Discord bot can surface long‑running failure notices
def send_discord_system_message(message: str) -> None:  # noqa: D401
    """This will be monkey‑patched by autogen_discord_bot.py at runtime."""
    _LOG.error("[SYSTEM‑MSG] %s", message)
