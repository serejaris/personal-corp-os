# daily-retro (experimental)

Every evening your agents' own logs answer two questions: what got done today and what was left half-done. Reads Claude Code and Codex session logs on your machine, adds git state of every touched repo, lists the tails and closes them the way the manager skill does.

Experimental: not part of the plugin's active skills. Install by copying:

```bash
cp -R experimental/skills/daily-retro ~/.claude/skills/daily-retro
```

Try it: `python3 ~/.claude/skills/daily-retro/scripts/collect.py` prints today's digest. Then `/daily-retro` in your HQ writes `retro/daily/<date>.md`. To run it every evening, use a template from `automation/`.
