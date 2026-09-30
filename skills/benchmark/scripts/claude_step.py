"""One headless agent step (`claude -p`) against a chosen model provider.

Claude Code is the harness for every LLM variant, so the model is the only thing
that changes between variants: same tools, same prompt, same permissions.
Non-Anthropic models are reached through Anthropic-compatible endpoints.

    from claude_step import run_step
    res = run_step(prompt, cwd=Path("..."), provider="zai", model="glm-5.3",
                   log_dir=Path("logs"), name="canon")
    res -> {"ok", "wall_s", "num_turns", "usage": {...}, "model_usage": {...},
            "cost_usd_reported", "result", "error"}

Providers (keys come from env; values are never written to logs):
    zai              https://api.z.ai/api/anthropic        ZAI_API_KEY
    openrouter       https://openrouter.ai/api             OPENROUTER_API_KEY
    deepseek         https://api.deepseek.com/anthropic    DEEPSEEK_API_KEY
    anthropic-api    Anthropic API                         ANTHROPIC_API_KEY
    anthropic-oauth  Claude subscription setup-token       CLAUDE_CODE_OAUTH_TOKEN
    anthropic-local  the login already present on this machine (no key passed)
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

PROVIDERS = {
    "zai": {"base_url": "https://api.z.ai/api/anthropic", "token_env": "ZAI_API_KEY"},
    "openrouter": {"base_url": "https://openrouter.ai/api", "token_env": "OPENROUTER_API_KEY"},
    "deepseek": {"base_url": "https://api.deepseek.com/anthropic", "token_env": "DEEPSEEK_API_KEY"},
    "anthropic-api": {"api_key_env": "ANTHROPIC_API_KEY"},
    "anthropic-oauth": {"oauth_env": "CLAUDE_CODE_OAUTH_TOKEN"},
    "anthropic-local": {},
}

DEFAULT_DISALLOWED = ["Bash(git:*)", "Bash(gh:*)", "Bash(sudo:*)", "Bash(curl:*)", "Bash(wget:*)", "Bash(ssh:*)",
                      "WebFetch", "WebSearch"]


def provider_env(provider: str, model: str) -> dict:
    cfg = PROVIDERS[provider]
    keep = ("HOME", "LANG", "LC_ALL", "USER", "LOGNAME", "TERM", "TMPDIR")
    env = {k: os.environ[k] for k in keep if k in os.environ}
    env["PATH"] = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
    env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
    env["API_TIMEOUT_MS"] = "3000000"
    if "base_url" in cfg:
        env["ANTHROPIC_BASE_URL"] = cfg["base_url"]
        env["ANTHROPIC_AUTH_TOKEN"] = os.environ[cfg["token_env"]]
        env["ANTHROPIC_API_KEY"] = ""
        # background and sub-agent calls must hit the same model, or the variant is mixed
        for tier in ("OPUS", "SONNET", "HAIKU"):
            env[f"ANTHROPIC_DEFAULT_{tier}_MODEL"] = model
        env["CLAUDE_CODE_SUBAGENT_MODEL"] = model
    elif "api_key_env" in cfg:
        env["ANTHROPIC_API_KEY"] = os.environ[cfg["api_key_env"]]
    elif "oauth_env" in cfg:
        env["CLAUDE_CODE_OAUTH_TOKEN"] = os.environ[cfg["oauth_env"]]
    return env


def run_step(prompt: str, *, cwd: Path, provider: str, model: str, log_dir: Path, name: str,
             timeout: int = 3600, disallowed: list[str] | None = None, claude_bin: str | None = None) -> dict:
    claude = claude_bin or os.environ.get("BENCH_CLAUDE") or shutil.which("claude") or "claude"
    # --setting-sources project,local: the machine owner's user settings, user agents and user
    # CLAUDE.md stay out of the run (a user-defined subagent once joined a benchmark run).
    cmd = [claude, "-p", prompt, "--output-format", "json", "--permission-mode", "bypassPermissions",
           "--no-session-persistence", "--setting-sources", "project,local",
           "--disallowedTools", *(disallowed or DEFAULT_DISALLOWED)]
    if model and model != "default":
        cmd += ["--model", model]
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / f"{name}.prompt.md").write_text(prompt, encoding="utf-8")
    t0 = time.monotonic()
    try:
        p = subprocess.run(cmd, cwd=cwd, env=provider_env(provider, model), capture_output=True, text=True,
                           timeout=timeout)
        out, err, code = p.stdout, p.stderr, p.returncode
    except subprocess.TimeoutExpired as exc:
        out, err, code = (exc.stdout or b"").decode() if isinstance(exc.stdout, bytes) else (exc.stdout or ""), \
            f"timeout after {timeout}s", -1
    wall = round(time.monotonic() - t0, 2)
    (log_dir / f"{name}.stdout.json").write_text(out, encoding="utf-8")
    if err.strip():
        (log_dir / f"{name}.stderr.txt").write_text(err[-4000:], encoding="utf-8")
    res = {"name": name, "provider": provider, "model": model, "wall_s": wall, "exit": code, "ok": False}
    try:
        data = json.loads(out.strip().splitlines()[-1]) if out.strip() else {}
    except json.JSONDecodeError:
        data = {}
    mu = data.get("modelUsage") or {}
    # top-level "usage" covers the main thread only; modelUsage includes sub-agents
    totals = {"input_tokens": sum(m.get("inputTokens", 0) for m in mu.values()),
              "cache_creation_input_tokens": sum(m.get("cacheCreationInputTokens", 0) for m in mu.values()),
              "cache_read_input_tokens": sum(m.get("cacheReadInputTokens", 0) for m in mu.values()),
              "output_tokens": sum(m.get("outputTokens", 0) for m in mu.values())}
    res.update({
        "ok": code == 0 and not data.get("is_error", True),
        "num_turns": data.get("num_turns"),
        "duration_api_ms": data.get("duration_api_ms"),
        "usage": totals if mu else {k: data.get("usage", {}).get(k, 0) for k in
                                     ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")},
        "model_usage": mu,
        "subagents": (data.get("subagent_stats") or {}).get("by_type", {}),
        "cost_usd_reported": data.get("total_cost_usd"),
        "result": (data.get("result") or "")[-2000:],
        "error": None if code == 0 else (err or out)[-400:],
    })
    return res
