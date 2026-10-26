# Contributing

Thanks for your interest in contributing! This document outlines conventions and guidelines.

## Commit Conventions

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <description>

[optional body]
```

### Types

| Type | Description | Version Bump |
|------|-------------|--------------|
| `feat` | New feature | MINOR (1.x.0) |
| `fix` | Bug fix | PATCH (1.0.x) |
| `docs` | Documentation only | — |
| `refactor` | Code change (no feature/fix) | — |
| `chore` | Maintenance tasks | — |

**Breaking changes:** Add `!` after type → `feat!: breaking change` → MAJOR (x.0.0)

### Examples

```bash
feat: add gemini-tmux-orchestration skill
fix: correct context calculation in statusline
docs: update README with installation steps
refactor: split skill into multiple files
chore: update dependencies
```

## Versioning

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (x.0.0) — breaking changes
- **MINOR** (1.x.0) — new features, backward compatible
- **PATCH** (1.0.x) — bug fixes, backward compatible

## Pull Requests

1. Fork the repository
2. Create feature branch: `git checkout -b feat/my-feature`
3. Follow commit conventions
4. Update `CHANGELOG.md` under `[Unreleased]`
5. Run repository validation:

```bash
python3 scripts/validate_repo.py
claude plugin validate .claude-plugin/marketplace.json
claude plugin tag --dry-run --force .
git diff --check
```

6. Submit PR with clear description

## Adding Skills

### Structure

```
skills/
  skill-name/
    SKILL.md        # Required: main skill file
    *.sh, *.md      # Optional: supporting files
```

### SKILL.md Format

```yaml
---
name: skill-name
description: Use when [trigger conditions] - [what it does]
---

# Skill Name

## Overview
Core principle in 1-2 sentences.

## Quick Reference
Table of common commands/patterns.

## Workflow
Step-by-step guide.

## Common Mistakes
What goes wrong + fixes.
```

### Checklist

- [ ] SKILL.md with proper frontmatter
- [ ] Added to main README.md skills list
- [ ] Entry in CHANGELOG.md under `[Unreleased]`
- [ ] `python3 scripts/validate_repo.py` passes

## Releases

### Title Format

```
v1.2.0 — Short Description
```

### Release Notes Template

```markdown
## What's New

### Feature Name
Brief description of what was added/changed.

**Key points:**
- Point 1
- Point 2

### Installation
\`\`\`bash
cp -r skills/name ~/.claude/skills/
\`\`\`

---

**Full Changelog**: https://github.com/.../compare/vPREV...vNEW
```

## Code Style

- Use English for code and comments
- Documentation in both English and Russian
- Prefer shell scripts for simple automation
- Keep skills focused and single-purpose

## Questions?

Open an issue or reach out on [Telegram](https://t.me/ris_ai).

## Security

Do not include real credentials, private URLs, personal data, or customer data in
issues, pull requests, examples, fixtures, screenshots, or release notes. Report
security concerns privately using [SECURITY.md](SECURITY.md).
