#!/usr/bin/env python3
"""Run the ASR variants of a benchmark task, one after another.

    python3 asr.py --task task.json --out runs/<name> [--only id1,id2] [--force]

For every variant writes runs/<name>/asr/<id>/:
    transcript.txt   plain text the engine returned
    raw.json         full engine response (words, timings, speakers, usage)
    meta.json        engine, model, wall_s, cpu_s, audio_s, status, error, usage

Engines (field "engine" of a variant):
    elevenlabs       ElevenLabs Speech to Text (Scribe). "keyterms": true sends the
                     task terms list as the keyterms field. Credits used are read from
                     /v1/user/subscription before and after the call.
    openai_compat    POST <base_url>/audio/transcriptions (OpenAI-compatible server:
                     self-hosted GigaAM, speaches, vLLM, a cloud endpoint).
    faster_whisper   Whisper on the local CPU through faster-whisper (CTranslate2).
    openrouter_audio chat completions with input_audio chunks (models with audio input
                     on OpenRouter or any OpenAI-compatible chat endpoint).

Keys are read from env only (names in the variant: "key_env"); values are never logged.
Variants run sequentially so wall time and CPU time are not shared between engines.
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import Meter, audio_seconds, load_task, read_json, secret, task_path, utc_now, write_json  # noqa: E402

KEYLIKE = re.compile(r"[A-Za-z0-9_\-]{24,}")


def redact(text: str) -> str:
    """Error bodies of some providers echo the key back: never keep long tokens."""
    return KEYLIKE.sub("***", text)[:400]


# --- terms -------------------------------------------------------------------

def load_keyterms(task: dict) -> list[str]:
    path = task_path(task, task.get("terms"))
    if not path:
        return []
    data = read_json(path)
    out, seen = [], set()
    for t in data.get("terms", []):
        if t.get("keyterm") is False:
            continue
        for k in t.get("keyterms") or [t.get("canon")]:
            k = " ".join(str(k or "").split())
            # Scribe limits: <50 chars, <=5 words, no <>{}[]\ ; up to 1000 terms
            if not k or k.lower() in seen or len(k) >= 50 or len(k.split()) > 5 or set(k) & set("<>{}[]\\"):
                continue
            seen.add(k.lower())
            out.append(k)
    return out[:1000]


# --- engines -----------------------------------------------------------------

def run_elevenlabs(v: dict, audio: Path, task: dict) -> tuple[str, dict, dict]:
    import httpx

    key = secret(v.get("key_env", "ELEVENLABS_API_KEY"))
    base = v.get("base_url", "https://api.elevenlabs.io/v1")
    headers = {"xi-api-key": key}

    def credits() -> int | None:
        try:
            r = httpx.get(f"{base}/user/subscription", headers=headers, timeout=30)
            return r.json().get("character_count") if r.status_code == 200 else None
        except httpx.HTTPError:
            return None

    data: dict = {
        "model_id": v.get("model", "scribe_v2"),
        "language_code": task.get("language", "ru"),
        "timestamps_granularity": "word",
        "diarize": "true",
    }
    keyterms = load_keyterms(task) if v.get("keyterms") else []
    if keyterms:
        data["keyterms"] = keyterms
    before = credits()
    with audio.open("rb") as fh, httpx.Client(timeout=httpx.Timeout(3600, connect=30)) as client:
        r = client.post(f"{base}/speech-to-text", headers=headers, data=data, files={"file": (audio.name, fh)})
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {redact(r.text)}")
    payload = r.json()
    after = credits()
    usage = {"keyterms": len(keyterms), "credits_before": before, "credits_after": after,
             "credits_used": (after - before) if before is not None and after is not None else None}
    return payload.get("text", ""), payload, usage


def run_openai_compat(v: dict, audio: Path, task: dict) -> tuple[str, dict, dict]:
    import httpx

    headers = {}
    if v.get("key_env"):
        headers["Authorization"] = f"Bearer {secret(v['key_env'])}"
    data = {"model": v["model"]}
    if v.get("send_language", True) and task.get("language"):
        data["language"] = task["language"]
    with audio.open("rb") as fh, httpx.Client(timeout=httpx.Timeout(float(v.get("timeout", 7200)), connect=30)) as client:
        r = client.post(v["base_url"].rstrip("/") + "/audio/transcriptions", headers=headers,
                        data=data, files={"file": (audio.name, fh)})
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {redact(r.text)}")
    payload = r.json()
    return payload.get("text", ""), payload, {}


def run_faster_whisper(v: dict, audio: Path, task: dict) -> tuple[str, dict, dict]:
    from faster_whisper import WhisperModel

    model = WhisperModel(v.get("model", "large-v3-turbo"), device="cpu",
                         compute_type=v.get("compute_type", "int8"), cpu_threads=int(v.get("threads", 8)))
    prompt = None
    if v.get("terms_prompt"):
        prompt = ", ".join(load_keyterms(task))[:800]
    # Decode with ffmpeg ourselves: faster-whisper's PyAV path breaks on some av releases.
    import numpy as np

    pcm = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(audio), "-ac", "1", "-ar", "16000",
                          "-f", "s16le", "-"], capture_output=True, check=True).stdout
    samples = np.frombuffer(pcm, np.int16).astype(np.float32) / 32768.0
    segments, info = model.transcribe(samples, language=task.get("language", "ru"),
                                      beam_size=int(v.get("beam_size", 5)), vad_filter=bool(v.get("vad", True)),
                                      initial_prompt=prompt)
    segs = [{"start": round(s.start, 2), "end": round(s.end, 2), "text": s.text.strip()} for s in segments]
    text = " ".join(s["text"] for s in segs)
    return text, {"language": info.language, "duration": info.duration, "segments": segs}, {"terms_prompt": bool(prompt)}


def run_openrouter_audio(v: dict, audio: Path, task: dict) -> tuple[str, dict, dict]:
    import httpx

    key = secret(v.get("key_env", "OPENROUTER_API_KEY"))
    base = v.get("base_url", "https://openrouter.ai/api/v1").rstrip("/")
    minutes = float(v.get("chunk_minutes", 10))
    prompt = v.get("prompt") or (
        "Transcribe this audio verbatim in its original language. Output only the transcript text, "
        "no comments, no timestamps, no speaker labels.")
    if v.get("terms_prompt"):
        prompt += " Spelling of names and terms: " + ", ".join(load_keyterms(task))
    texts, calls = [], []
    with tempfile.TemporaryDirectory() as td:
        pattern = Path(td) / "chunk-%03d.mp3"
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(audio), "-ac", "1",
                        "-ar", "16000", "-b:a", "48k", "-f", "segment", "-segment_time", str(int(minutes * 60)),
                        str(pattern)], check=True)
        for chunk in sorted(Path(td).glob("chunk-*.mp3")):
            body = {
                "model": v["model"],
                "messages": [{"role": "user", "content": [
                    {"type": "text", "text": prompt},
                    {"type": "input_audio", "input_audio": {"data": base64.b64encode(chunk.read_bytes()).decode(),
                                                            "format": "mp3"}},
                ]}],
                "temperature": 0,
                "usage": {"include": True},
            }
            r = httpx.post(f"{base}/chat/completions", headers={"Authorization": f"Bearer {key}"}, json=body,
                           timeout=httpx.Timeout(1800, connect=30))
            if r.status_code != 200:
                raise RuntimeError(f"{chunk.name}: HTTP {r.status_code}: {redact(r.text)}")
            p = r.json()
            texts.append((p["choices"][0]["message"].get("content") or "").strip())
            calls.append({"chunk": chunk.name, "usage": p.get("usage", {}), "model": p.get("model")})
    usage = {"calls": len(calls),
             "prompt_tokens": sum(c["usage"].get("prompt_tokens", 0) for c in calls),
             "completion_tokens": sum(c["usage"].get("completion_tokens", 0) for c in calls),
             "cost_usd_reported": round(sum(float(c["usage"].get("cost") or 0) for c in calls), 6)}
    return "\n".join(texts), {"calls": calls}, usage


ENGINES = {
    "elevenlabs": run_elevenlabs,
    "openai_compat": run_openai_compat,
    "faster_whisper": run_faster_whisper,
    "openrouter_audio": run_openrouter_audio,
}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--task", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--only", help="comma-separated variant ids")
    ap.add_argument("--force", action="store_true", help="rerun variants that already have status ok")
    args = ap.parse_args()

    task = load_task(args.task)
    audio = task_path(task, task["audio"])
    audio_s = audio_seconds(audio)
    only = set(args.only.split(",")) if args.only else None
    for v in task.get("asr", []):
        if only and v["id"] not in only:
            continue
        if v.get("skip"):
            continue
        out = args.out / "asr" / v["id"]
        meta_path = out / "meta.json"
        if meta_path.exists() and read_json(meta_path).get("status") == "ok" and not args.force:
            print(f"{v['id']}: already ok, skip")
            continue
        out.mkdir(parents=True, exist_ok=True)
        meta = {"id": v["id"], "engine": v["engine"], "model": v.get("model"), "audio_s": round(audio_s, 1),
                "started_at": utc_now(), "variant": {k: val for k, val in v.items() if k != "prompt"}}
        print(f"{v['id']}: start", flush=True)
        try:
            with Meter() as m:
                text, raw, usage = ENGINES[v["engine"]](v, audio, task)
            (out / "transcript.txt").write_text(text.strip() + "\n", encoding="utf-8")
            write_json(out / "raw.json", raw)
            meta.update(status="ok", wall_s=m.wall_s, cpu_s=m.cpu_s, usage=usage, chars=len(text))
        except Exception as exc:  # one failed engine must not stop the others
            meta.update(status="error", error=redact(f"{type(exc).__name__}: {exc}"),
                        trace=redact(traceback.format_exc().splitlines()[-1]))
        meta["finished_at"] = utc_now()
        write_json(meta_path, meta)
        print(f"{v['id']}: {meta['status']} {meta.get('wall_s', '')}s {meta.get('error', '')}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
