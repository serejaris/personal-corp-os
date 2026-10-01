#!/usr/bin/env python3
"""Validate the public skill repository contract."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO_SLUG = "serejaris/personal-corp-os"
REPO_URL = f"https://github.com/{REPO_SLUG}"
LEGACY_NAME = "ris" + "-claude-code"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def validate_json(path: Path) -> dict:
    try:
        return json.loads(read(path))
    except json.JSONDecodeError as exc:
        fail(f"{path.relative_to(ROOT)} is invalid JSON: {exc}")


def frontmatter(text: str, path: Path) -> str:
    if not text.startswith("---\n"):
        fail(f"{path.relative_to(ROOT)} must start with YAML frontmatter")
    end = text.find("\n---\n", 4)
    if end == -1:
        fail(f"{path.relative_to(ROOT)} must close YAML frontmatter")
    return text[4:end]


def has_frontmatter_key(block: str, key: str) -> bool:
    return re.search(rf"(?m)^{re.escape(key)}:\s*.+", block) is not None


def validate_simple_frontmatter(block: str, path: Path) -> None:
    fields: dict[str, str] = {}
    for line in block.splitlines():
        if not line or line.startswith(" ") or line.startswith("\t"):
            continue
        if ":" not in line:
            fail(f"{path.relative_to(ROOT)} frontmatter line is not a key/value pair: {line}")
        key, value = line.split(":", 1)
        fields[key] = value.strip()

    for key in ("name", "description"):
        if key not in fields or not fields[key]:
            fail(f"{path.relative_to(ROOT)} is missing {key}")

    description = fields["description"]
    if description not in {">", ">-", "|", "|-"} and ": " in description:
        fail(
            f"{path.relative_to(ROOT)} description must be quoted or use a block scalar "
            "when it contains ': '"
        )


def validate_skills() -> list[str]:
    skills_dir = ROOT / "skills"
    skill_names = sorted(path.name for path in skills_dir.iterdir() if path.is_dir())
    if not skill_names:
        fail("skills/ must contain at least one skill")

    for name in skill_names:
        skill_dir = skills_dir / name
        for filename in ("SKILL.md", "README.md", "README.ru.md"):
            path = skill_dir / filename
            if not path.exists():
                fail(f"{skill_dir.relative_to(ROOT)} is missing {filename}")

        skill_path = skill_dir / "SKILL.md"
        block = frontmatter(read(skill_path), skill_path)
        validate_simple_frontmatter(block, skill_path)
        if not has_frontmatter_key(block, "name"):
            fail(f"{skill_path.relative_to(ROOT)} is missing name")
        name_match = re.search(r"(?m)^name:\s*(.+?)\s*$", block)
        if name_match is None or name_match.group(1).strip() != name:
            fail(f"{skill_path.relative_to(ROOT)} name must match its folder name")
        if not has_frontmatter_key(block, "description"):
            fail(f"{skill_path.relative_to(ROOT)} is missing description")

    return skill_names


def validate_archived_skills(active_skill_names: list[str]) -> None:
    archive_dir = ROOT / "archive" / "skills"
    if not archive_dir.exists():
        return

    archived_names = sorted(path.name for path in archive_dir.iterdir() if path.is_dir())
    for name in archived_names:
        if name in active_skill_names:
            fail(f"archive/skills/{name} duplicates an active skill")
        skill_dir = archive_dir / name
        for filename in ("SKILL.md", "README.md", "README.ru.md"):
            path = skill_dir / filename
            if not path.exists():
                fail(f"{skill_dir.relative_to(ROOT)} is missing {filename}")
        block = frontmatter(read(skill_dir / "SKILL.md"), skill_dir / "SKILL.md")
        validate_simple_frontmatter(block, skill_dir / "SKILL.md")


def validate_readme_skill_links(skill_names: list[str]) -> None:
    for filename in ("README.md", "README.ru.md"):
        text = read(ROOT / filename)
        top = text[:1000]
        if "Claude Code" not in top or "Codex" not in top:
            fail(f"{filename} top intro must mention both Claude Code and Codex")
        if text.find("## Install") == -1 and text.find("## Установка") == -1:
            fail(f"{filename} must include install instructions near the top")
        first_skills_index = text.find("## Skills")
        install_index = text.find("## Install")
        if install_index == -1:
            install_index = text.find("## Установка")
        if first_skills_index != -1 and install_index > first_skills_index:
            fail(f"{filename} install instructions must appear before the skills list")
        required_snippets = [
            "claude plugin marketplace add serejaris/personal-corp-os",
            "claude plugin install personal-corp-os@personal-corp-os",
            "claude plugin details personal-corp-os",
            "codex plugin add personal-corp-os@personal-corp-os",
            "codex plugin marketplace add serejaris/personal-corp-os",
            "https://github.com/serejaris/personal-corp-os/tree/main/skills/cc-analytics",
            "Use Personal Corp skills to plan my week.",
        ]
        for snippet in required_snippets:
            if snippet not in text:
                fail(f"{filename} must include install snippet: {snippet}")
        if "```bash\n/plugin " in text:
            fail(f"{filename} must not present interactive /plugin commands as shell commands")
        for name in skill_names:
            if f"./skills/{name}/" not in text:
                fail(f"{filename} does not link to skills/{name}/")
        if "./skills/paperclip-api/" in text:
            fail(f"{filename} must not link archived paperclip-api as an active skill")
        if "./archive/skills/paperclip-api/" not in text:
            fail(f"{filename} must link archived paperclip-api")
        if REPO_SLUG not in text:
            fail(f"{filename} must include install instructions for {REPO_SLUG}")


def validate_plugin_metadata() -> None:
    plugin = validate_json(ROOT / ".codex-plugin" / "plugin.json")
    codex_marketplace = validate_json(ROOT / ".agents" / "plugins" / "marketplace.json")

    if plugin.get("name") != "personal-corp-os":
        fail(".codex-plugin/plugin.json name must be personal-corp-os")
    if plugin.get("homepage") != REPO_URL:
        fail(".codex-plugin/plugin.json homepage must use the canonical repo URL")
    if plugin.get("repository") != REPO_URL:
        fail(".codex-plugin/plugin.json repository must use the canonical repo URL")
    if plugin.get("license") != "MIT":
        fail(".codex-plugin/plugin.json license must be MIT")
    if plugin.get("skills") != "./skills/":
        fail(".codex-plugin/plugin.json skills must point to ./skills/")
    interface = plugin.get("interface")
    if not isinstance(interface, dict):
        fail(".codex-plugin/plugin.json must include interface metadata")
    for key in ("displayName", "shortDescription", "longDescription", "developerName", "category"):
        if not isinstance(interface.get(key), str) or not interface[key].strip():
            fail(f".codex-plugin/plugin.json interface.{key} is required")

    if codex_marketplace.get("name") != plugin.get("name"):
        fail(".agents/plugins/marketplace.json name must match plugin name")
    codex_plugins = codex_marketplace.get("plugins")
    if not isinstance(codex_plugins, list) or not codex_plugins:
        fail(".agents/plugins/marketplace.json must list at least one plugin")
    codex_entry = codex_plugins[0]
    if codex_entry.get("name") != plugin.get("name"):
        fail(".agents/plugins/marketplace.json plugin name must match plugin name")
    source = codex_entry.get("source")
    if not isinstance(source, dict) or source.get("source") != "local" or source.get("path") != "./plugins/personal-corp-os":
        fail(".agents/plugins/marketplace.json plugin source must point to ./plugins/personal-corp-os")
    plugin_link = ROOT / "plugins" / "personal-corp-os"
    if not plugin_link.is_symlink() or plugin_link.resolve() != ROOT:
        fail("plugins/personal-corp-os must be a symlink to the repo root for Codex marketplace discovery")
    policy = codex_entry.get("policy")
    if not isinstance(policy, dict) or policy.get("installation") != "AVAILABLE" or policy.get("authentication") != "ON_INSTALL":
        fail(".agents/plugins/marketplace.json plugin policy must be AVAILABLE/ON_INSTALL")

    claude_manifest_path = ROOT / ".claude-plugin" / "plugin.json"
    claude_marketplace_path = ROOT / ".claude-plugin" / "marketplace.json"
    if claude_manifest_path.exists() or claude_marketplace_path.exists():
        claude_plugin = validate_json(claude_manifest_path)
        claude_marketplace = validate_json(claude_marketplace_path)
        # Claude Code and Codex accept different manifest shapes. Keep shared
        # identity fields in sync and validate schema-specific fields separately.
        for key in ("name", "version", "homepage", "repository", "license"):
            if claude_plugin.get(key) != plugin.get(key):
                fail(f".claude-plugin/plugin.json {key} must match .codex-plugin/plugin.json")
        if claude_marketplace.get("name") != plugin.get("name"):
            fail(".claude-plugin/marketplace.json name must match plugin name")
        if not isinstance(claude_marketplace.get("description"), str) or not claude_marketplace["description"].strip():
            fail(".claude-plugin/marketplace.json description is required")
        plugins = claude_marketplace.get("plugins")
        if not isinstance(plugins, list) or not plugins:
            fail(".claude-plugin/marketplace.json must list at least one plugin")
        if plugins[0].get("name") != plugin.get("name"):
            fail(".claude-plugin/marketplace.json plugin name must match plugin name")
        if "category" in claude_plugin:
            fail(".claude-plugin/plugin.json category is ignored by Claude Code; put it in marketplace.json")
        if plugins[0].get("category") != "productivity":
            fail(".claude-plugin/marketplace.json plugin category must be productivity")


def validate_public_hygiene() -> None:
    required = [
        "LICENSE",
        "AGENTS.md",
        "README.md",
        "README.ru.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "CODE_OF_CONDUCT.md",
        "archive/skills/paperclip-api/SKILL.md",
        ".codex-plugin/plugin.json",
        ".agents/plugins/marketplace.json",
        "plugins/personal-corp-os",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/dependabot.yml",
        ".github/ISSUE_TEMPLATE/bug_report.yml",
        ".github/ISSUE_TEMPLATE/skill_request.yml",
        ".github/workflows/validate.yml",
    ]
    for rel in required:
        if not (ROOT / rel).exists():
            fail(f"missing required public repo file: {rel}")

    for path in ROOT.rglob("*"):
        if ".git" in path.parts or not path.is_file():
            continue
        if path.suffix in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf"}:
            continue
        text = read(path)
        if LEGACY_NAME in text:
            fail(f"{path.relative_to(ROOT)} still contains legacy repo name {LEGACY_NAME}")


def validate_manager_distribution() -> None:
    manager = ROOT / "skills" / "manager"
    allowed = {
        "SKILL.md", "README.md", "README.ru.md", "assets/illustration.png",
        "agents/openai.yaml",
        "references/crm.md", "references/mistakes.md", "references/modes.md",
        "references/output.md", "references/parent-epic.md", "references/read-mode.md",
        "references/search.md", "references/templates.md", "references/titles.md",
        "references/w-labels.md", "references/write-mode.md",
    }
    for path in manager.rglob("*"):
        if not path.is_file():
            continue
        if path.relative_to(manager).as_posix() not in allowed:
            fail("manager contains an unreviewed distribution file")
        if path.suffix == ".png":
            continue
        text = read(path)
        patterns = (
            r"/Users/[^/\s]+/", r"~/Documents/", r"PVT(?:I|SSF)?_",
            r"github\.com/(?!your-github-handle(?:/|$))[^/\s]+/",
            r"(?i)\bsereja" + r"ris\b", r"process-logs/",
        )
        if any(re.search(pattern, text) for pattern in patterns):
            fail("manager contains workspace-specific distribution data")


def main() -> None:
    skill_names = validate_skills()
    validate_archived_skills(skill_names)
    validate_readme_skill_links(skill_names)
    validate_plugin_metadata()
    validate_public_hygiene()
    validate_manager_distribution()
    print(f"OK: validated {len(skill_names)} skills and public repo metadata")


if __name__ == "__main__":
    main()
