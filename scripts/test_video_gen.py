#!/usr/bin/env python3
"""Tests for ai-video CLI prompt generator."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "skills" / "ai-video" / "scripts" / "video_gen.py"


def test_cli_execution() -> None:
    cmd = [
        sys.executable,
        str(SCRIPT),
        "Cyberpunk street",
        "--camera", "slow dolly-in 50mm",
        "--action", "hovercar passes",
        "--format", "grok",
        "--json",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    payload = json.loads(res.stdout)
    assert payload["provider_format"] == "grok"
    assert "Cyberpunk street" in payload["formatted_prompt"]
    assert "Action: hovercar passes" in payload["formatted_prompt"]
    assert "Camera: slow dolly-in 50mm" in payload["formatted_prompt"]


def test_runway_format() -> None:
    cmd = [
        sys.executable,
        str(SCRIPT),
        "Ocean waves",
        "--camera", "wide shot 24mm",
        "--action", "waves crash on rocks",
        "--format", "runway",
        "--json",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    payload = json.loads(res.stdout)
    assert payload["provider_format"] == "runway"
    assert "wide shot 24mm." in payload["formatted_prompt"]
    assert "waves crash on rocks." in payload["formatted_prompt"]


def main() -> None:
    test_cli_execution()
    test_runway_format()
    print("OK: ai-video CLI tests passed")


if __name__ == "__main__":
    main()
