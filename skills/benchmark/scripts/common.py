"""Shared helpers for the benchmark scripts: task config, JSON io, timing, prices."""

from __future__ import annotations

import datetime as dt
import json
import os
import resource
import time
from pathlib import Path


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path: Path | str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write_json(path: Path | str, data) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_task(path: Path | str) -> dict:
    """Task config. Relative paths inside it resolve against the config's folder."""
    path = Path(path).resolve()
    task = read_json(path)
    task["_dir"] = str(path.parent)
    return task


def task_path(task: dict, value: str | None) -> Path | None:
    if not value:
        return None
    p = Path(os.path.expandvars(os.path.expanduser(value)))
    return p if p.is_absolute() else Path(task["_dir"]) / p


class Meter:
    """Wall clock plus CPU seconds of this process and its finished children."""

    def __enter__(self):
        self.t0 = time.monotonic()
        self.r0 = self._cpu()
        return self

    def __exit__(self, *exc):
        self.wall_s = round(time.monotonic() - self.t0, 2)
        self.cpu_s = round(self._cpu() - self.r0, 2)
        return False

    @staticmethod
    def _cpu() -> float:
        s = resource.getrusage(resource.RUSAGE_SELF)
        c = resource.getrusage(resource.RUSAGE_CHILDREN)
        return s.ru_utime + s.ru_stime + c.ru_utime + c.ru_stime


def audio_seconds(path: Path) -> float:
    import subprocess

    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return float(out)


def secret(env_name: str) -> str:
    value = os.environ.get(env_name, "").strip()
    if not value:
        raise KeyError(f"env {env_name} is not set")
    return value
