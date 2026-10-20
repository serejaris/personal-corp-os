# personal-corp-os

Collection of Claude Code customizations: skills, statusline, hooks.

## Critical Rules

**ALWAYS update BOTH READMEs when releasing:**
- README.md (English) and README.ru.md (Russian)
- Adding/removing skills → update skills list in both READMEs
- Adding/removing any component → update corresponding section in both READMEs
- Release without README updates = incomplete release
- Public repo hygiene changes must keep `SECURITY.md`, `CODE_OF_CONDUCT.md`,
  issue templates, plugin metadata, and `scripts/validate_repo.py` aligned.

## Never

- Never delete skills directories without explicit confirmation
- Never push to main without running through release checklist
- Never modify SKILL.md frontmatter (name, description) without updating both READMEs
- Never create GitHub issues/labels in this public repo with private data

## Structure

| Path | Purpose |
|------|---------|
| `skills/` | Reusable skill templates |
| `archive/skills/` | Historical skills kept for reference; not active plugin skills |
| `statusline/` | Custom statusline scripts |
| `hooks/` | Pre/post command hooks |
| `plugins/<mod>/` | Claude Code mods (function hooks): own `plugin.json` with version, `README.md`, `README.ru.md`, tests; listed in `.claude-plugin/marketplace.json` |

## Skill Structure

Each skill folder must contain:
- `SKILL.md` — main skill file (required)
- `README.md` — English documentation
- `README.ru.md` — Russian documentation

Optional: additional templates, configs in the same folder.

## Versioning

| Change | Version | Example |
|--------|---------|---------|
| New skill/component | MINOR | 1.5.0 → 1.6.0 |
| Update existing skill | PATCH | 1.5.0 → 1.5.1 |
| Bug fix, docs | PATCH | 1.5.0 → 1.5.1 |

READMEs update only when skills list changes (add/remove).

## Release Checklist

1. Update CHANGELOG.md
2. Update READMEs (only if skills list changed)
3. Run `python3 scripts/validate_repo.py`
4. Run `claude plugin validate .claude-plugin/marketplace.json`
5. For each mod in `plugins/`: `claude plugin validate plugins/<mod>` and `claude plugin test plugins/<mod>`; a changed mod gets a new version in its `plugin.json` and its marketplace entry
6. Run `claude plugin tag --dry-run --force .`
7. Run a clean Codex install smoke:
   `tmp_home=$(mktemp -d); HOME="$tmp_home" codex plugin marketplace add .; HOME="$tmp_home" codex plugin add personal-corp-os@personal-corp-os; rm -rf "$tmp_home"`
8. Run `git diff --check`
9. Commit: `docs: update changelog for vX.Y.Z`
10. Tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
11. Push: `git push && git push --tags`
12. GitHub release via `gh release create`
