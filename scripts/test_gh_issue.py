#!/usr/bin/env python3
"""Behavior checks for skills/manager/scripts/gh_issue.sh against a fake `gh`.

Every run must print exactly one line of valid JSON on stdout, errors included.
GH_ISSUE_SCRIPT points the checks at another copy of the script (the private one, for example).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
FIXTURES = ROOT / "scripts" / "fixtures" / "gh_issue"
SCRIPT = Path(os.environ.get("GH_ISSUE_SCRIPT", ROOT / "skills" / "manager" / "scripts" / "gh_issue.sh"))
REPO = "your-github-handle/app"
# 1x1 transparent PNG
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


class Sandbox:
    def __init__(self, temp: Path) -> None:
        self.dir = temp
        self.state = temp / "state.json"
        shutil.copy(FIXTURES / "state.json", self.state)
        bin_dir = temp / "bin"
        bin_dir.mkdir()
        shutil.copy(FIXTURES / "gh", bin_dir / "gh")
        (bin_dir / "gh").chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "FAKE_GH_STATE": str(self.state),
            "MANAGER_CONFIG": str(FIXTURES / "config.json"),
            "GIT_CEILING_DIRECTORIES": str(temp.parent),
        }
        for key in ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CODEX_THREAD_ID", "CODEX_SESSION_ID",
                    "HERMES_SESSION_ID", "ANTHROPIC_MODEL", "MANAGER_PROJECT_ID", "MANAGER_PROJECT_NUMBER",
                    "MANAGER_STATUS_FIELD_ID", "MANAGER_STATUS_OPTIONS", "MANAGER_CLONE_ROOTS",
                    "MANAGER_GITHUB_WEB"):
            self.env.pop(key, None)

    def file(self, name: str, text: str) -> str:
        path = self.dir / name
        path.write_text(text, encoding="utf-8")
        return str(path)

    def run(self, *args: str, code: int | None = 0) -> tuple[dict, str]:
        proc = subprocess.run(["bash", str(SCRIPT), *args], cwd=self.dir, env=self.env,
                              capture_output=True, text=True, timeout=60)
        lines = proc.stdout.splitlines()
        label = " ".join(args)[:90]
        require(len(lines) == 1, f"{label}: want one stdout line, got {len(lines)}: {proc.stdout!r} {proc.stderr[-300:]!r}")
        try:
            out = json.loads(lines[0])
        except json.JSONDecodeError as exc:
            raise AssertionError(f"{label}: stdout is not JSON: {lines[0]!r}") from exc
        require(isinstance(out, dict) and "ok" in out and "result" in out, f"{label}: JSON lacks ok/result")
        if code is not None:
            require(proc.returncode == code, f"{label}: exit {proc.returncode}, want {code}: {lines[0]}")
        return out, proc.stderr

    def issue(self, number: int) -> dict:
        return json.loads(self.state.read_text(encoding="utf-8"))["issues"][f"{REPO}#{number}"]

    def files(self) -> dict:
        return json.loads(self.state.read_text(encoding="utf-8"))["repos"][REPO]["files"]


def usage_error(box: Sandbox, args: tuple[str, ...], needle: str) -> None:
    out, _ = box.run(*args, code=2)
    require(out["ok"] is False and out["result"] == "usage", f"{args}: want usage error, got {out}")
    require(needle in out.get("error", ""), f"{args}: error {out.get('error')!r} lacks {needle!r}")


def check_errors(box: Sandbox) -> None:
    body = box.file("body.md", "Тело задачи.\n")
    missing = str(box.dir / "missing.md")
    cases = [
        (("read", "not-a-ref"), "плохая ссылка"),
        (("read",), "нужен хотя бы один"),
        (("ensure", f"{REPO}#12", "--week"), "без значения"),
        (("ensure", f"{REPO}#12", "--week", "W44", "--parent", "--dry-run"), "без значения"),
        (("ensure", f"{REPO}#12", "--week", "W44", "--status", "Doing"), "Status"),
        (("create", "--repo", REPO, "--title", "T", "--body-file", missing, "--week", "W44",
          "--parent", f"{REPO}#11"), "нет файла"),
        (("create", "--repo", REPO, "--title"), "без значения"),
        (("comment", f"{REPO}#12", "--body-file", missing), "нет файла"),
        (("comment", f"{REPO}#12", "--body-file", body, "--image", "x.png"), "shot"),
        (("comment", f"{REPO}#12", "--body-file", body, "--image-url"), "без значения"),
        (("comment", "app#12", "--body-file", body), "плохая ссылка"),
        (("now", f"{REPO}#12", "--text-file", missing), "нет файла"),
        (("now", f"{REPO}#12", "--text"), "без значения"),
        (("close", f"{REPO}#16", "--proof-file", missing), "нет файла"),
        (("close", f"{REPO}#16", "--proof-file", body), "Proof"),
        (("close", f"{REPO}#16", "--proof-file", body, "--reason", "later"), "--reason"),
        (("block", f"{REPO}#15", "--by"), "без значения"),
        (("block", f"{REPO}#15", "--by", "nope"), "плохая ссылка"),
        (("board",), "board"),
        (("shot", f"{REPO}#12", "--image", missing), "нет файла"),
        (("shot", f"{REPO}#12", "--image", body), "png"),
        (("shot", f"{REPO}#12", "--image"), "без значения"),
        (("shot", f"{REPO}#12", "--image", body, "--dir"), "без значения"),
        (("launch",), "неизвестная подкоманда"),
    ]
    for args, needle in cases:
        usage_error(box, args, needle)
    out, _ = box.run("read", f"{REPO}#99", code=1)
    require(out["result"] == "partial" and out["errors"][0]["ref"] == f"{REPO}#99", "missing issue must be a partial read")


def check_read_ensure_create(box: Sandbox) -> None:
    out, _ = box.run("--help")
    require(out["ok"] is True and out["result"] == "help", "help must print one JSON line")
    out, _ = box.run("read", f"{REPO}#12", f"https://github.com/{REPO}/issues/15")
    refs = [i["ref"] for i in out["issues"]]
    require(refs == [f"{REPO}#12", f"{REPO}#15"], f"read refs: {refs}")
    require(out["issues"][0]["project"]["status"] == "In review", "read must report the Project status")

    out, _ = box.run("ensure", f"{REPO}#12", "--week", "W44", "--parent", f"{REPO}#11", "--status", "In review")
    require(out["result"] == "noop" and out["actions"] == [], f"ensure on a synced issue must be noop: {out}")
    out, _ = box.run("--dry-run", "ensure", f"{REPO}#12", "--week", "W44", "--status", "Ready")
    require(any("не понижаю" in w for w in out["warnings"]), "ensure must not lower In review without --force")

    body = box.file("body.md", "Письмо после входа.\n")
    out, _ = box.run("create", "--repo", REPO, "--title", "Send welcome email", "--body-file", body,
                     "--week", "W44", "--parent", f"{REPO}#11", "--status", "In progress")
    require(out["result"] == "exists" and out["created"] is False and out["ref"] == f"{REPO}#13",
            f"create must find the duplicate: {out}")
    out, _ = box.run("create", "--repo", REPO, "--title", "Password reset", "--body-file", body,
                     "--week", "W44", "--parent", f"{REPO}#11", "--status", "Ready", "--no-origin")
    require(out["result"] == "done" and out["created"] is True, f"create must create a new issue: {out}")
    require(box.issue(21)["parent"] == f"{REPO}#11", "new issue must sit under its epic")


def check_comment_now_close_block(box: Sandbox) -> None:
    work = box.file("work.md", "Письмо уходит после входа.\n")
    url = f"https://github.com/{REPO}/blob/{'a' * 40}/docs/shots/welcome.png?raw=true"
    out, _ = box.run("comment", f"{REPO}#13", "--body-file", work, "--image-url", url)
    require(out["result"] == "done", f"comment: {out}")
    require(f"![welcome]({url})" in box.issue(13)["comments"][-1]["body"], "comment must embed --image-url")
    out, _ = box.run("comment", f"{REPO}#13", "--body-file", work, "--image-url", url)
    require(out["result"] == "noop", "repeated comment must be noop")

    out, _ = box.run("now", f"{REPO}#13", "--text", "Где: `feat/welcome-email`\nЖдёт: ревью")
    require(out["result"] == "done" and "Ждёт: ревью" in box.issue(13)["body"], f"now: {out}")
    out, _ = box.run("now", f"{REPO}#13", "--text", "Где: `feat/welcome-email`\nЖдёт: ревью")
    require(out["result"] == "noop", f"repeated now must be noop: {out}")

    proof = box.file("proof.md", "## Proof\n\nЭпик закрыт.\n")
    out, _ = box.run("close", f"{REPO}#11", "--proof-file", proof, code=1)
    require(out["result"] == "error" and "открытых sub-issues" in out["error"], f"close with open children: {out}")
    require(box.issue(11)["state"] == "OPEN", "epic with open children must stay open")
    out, _ = box.run("close", f"{REPO}#16", "--proof-file", proof)
    require(out["result"] == "done" and box.issue(16)["state"] == "CLOSED", f"close: {out}")
    out, _ = box.run("close", f"{REPO}#16", "--proof-file", proof)
    require(out["result"] == "noop", "closing again must be noop")

    out, _ = box.run("block", f"{REPO}#15", "--by", f"{REPO}#14")
    require(out["result"] == "noop", "existing dependency must be noop")


def check_board(box: Sandbox) -> tuple[str, str]:
    out, table = box.run("--dry-run", "board", f"{REPO}#11")
    require(out["result"] == "dry-run" and out["children"] == {"open": 4, "closed": 1}, f"board dry-run: {out}")
    require("| 🟢 | #12 Add sign-in page |" in table and "| 🔴 | #14 Billing settings |" in table, "board table rows")
    require("после #14" in table, "board must show the blocker in «Ждёт»")
    out, _ = box.run("board", f"{REPO}#11")
    require(out["result"] == "done" and "<!-- board:start -->" in box.issue(11)["body"], f"board: {out}")
    require(box.issue(11)["body"].startswith("Цель:"), "board must keep the body above «## Сейчас»")
    out, _ = box.run("board", f"{REPO}#11")
    require(out["result"] == "noop", "board twice must be noop")
    read, _ = box.run("read", f"{REPO}#12", f"{REPO}#13")
    return json.dumps(read, ensure_ascii=False), table


def check_shot(box: Sandbox) -> None:
    image = box.dir / "Sign In.png"
    image.write_bytes(PNG)
    out, _ = box.run("--dry-run", "shot", f"{REPO}#12", "--image", str(image))
    require(out["result"] == "dry-run" and box.files() == {}, "shot --dry-run must not commit")
    out, _ = box.run("shot", f"{REPO}#12", "--image", str(image))
    path = f"docs/shots/{date.today().isoformat()}-12-sign-in.png"
    commit = box.files()[path]["commit"]
    require(out["result"] == "done" and out["path"] == path and out["sha"] == commit, f"shot: {out}")
    want = f"https://github.com/{REPO}/blob/{commit}/{path}?raw=true"
    require(out["url"] == want and re.fullmatch(r"[0-9a-f]{40}", out["sha"]), f"shot url by commit SHA: {out['url']}")
    require(out["markdown"] == f"![sign-in]({want})", "shot markdown")
    require(any("Contents API" in a for a in out["actions"]), "shot must name the commit in actions")
    out, _ = box.run("shot", f"{REPO}#12", "--image", str(image))
    require(out["result"] == "noop" and out["url"] == want, f"repeated shot must reuse the commit: {out}")


def main() -> None:
    require(shutil.which("jq") is not None, "jq is required")
    with tempfile.TemporaryDirectory() as temp:
        base = Path(temp)
        for name, check in (("errors", check_errors), ("read", check_read_ensure_create),
                            ("write", check_comment_now_close_block), ("shot", check_shot)):
            work = base / name
            work.mkdir()
            check(Sandbox(work))
        work = base / "board"
        work.mkdir()
        read, table = check_board(Sandbox(work))
    if "--show" in sys.argv:
        print(read)
        print(table)
    print(f"OK: gh_issue.sh one JSON line per run, ensure noop, create dedup, close guard, board, shot by SHA ({SCRIPT.name})")


if __name__ == "__main__":
    main()
