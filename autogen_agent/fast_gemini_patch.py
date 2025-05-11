# fast_gemini_patch.py  –  works with both google‑generativeai & google‑genai
import importlib, time, logging, functools, types

_LOG = logging.getLogger("fast‑gemini")

def _find_target():
    """
    Returns (target_object, attribute_name) for the generate‑content entry‑point
    used by the installed SDK – regardless of package name or version.
    """
    # ---- candidates ordered by likelihood ---------------------------------
    LOOKUP = [
        ("google_genai.models",                   "GenerativeModel", "generate_content"),
        ("google.generativeai",                   "GenerativeModel", "generate_content"),
        ("google.generativeai.generative_models", None, "_batch_generate_content"),
        ("google_genai.generative_models",        None, "_batch_generate_content"),
        ("google_genai.models",                   None, "_batch_generate_content"),
    ]
    for mod_path, cls_name, attr in LOOKUP:
        try:
            mod = importlib.import_module(mod_path)
        except ModuleNotFoundError:
            continue

        target = getattr(mod, cls_name, None) if cls_name else mod
        if target and hasattr(target, attr):
            return target, attr

    raise ImportError("fast_gemini_patch: could not locate a "
                      "generate‑content entry‑point – unknown SDK version")

def _apply():
    target, attr = _find_target()
    orig = getattr(target, attr)

    # idempotent – don’t double wrap on reload
    if getattr(orig, "_fast_patch_applied", False):
        return

    @functools.wraps(orig)
    def wrapper(*args, **kw):
        gc = kw.setdefault("generation_config", {})
        gc.setdefault("candidate_count", 1)      # 8 → 1  (≈ 8× faster)
        gc.setdefault("max_output_tokens", 2048)
        kw.setdefault("stream", True)

        t0 = time.perf_counter()
        _LOG.info("⏱️  Gemini call ‑‑ start")
        resp = orig(*args, **kw)
        _LOG.info("⏱️  Gemini call finished in %.2f s",
                  time.perf_counter() - t0)
        return resp

    wrapper._fast_patch_applied = True
    setattr(target, attr, wrapper)

    # pretty log
    where = f"{target.__module__}.{attr}" if isinstance(target, types.ModuleType) \
           else f"{target}.{attr}"
    _LOG.info("✅ Patched %s", where)

_apply()
