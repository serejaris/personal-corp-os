# it-memory

Find and kill process tails that hold memory for nothing: idle Claude Code desktop sessions, leftovers of closed apps, orphaned workers, zombies. macOS and Linux.

## The problem it solves

A machine that runs many agent sessions slowly fills up: dozens of Claude Code sessions idle for days, a daemon of an app you closed, duplicate worker brokers, a forgotten dev server. Each takes 30–400 MB; together they push the machine into swap.

The skill splits the job in two:

1. A read-only script (`scripts/tails-macos.sh`, `scripts/tails-linux.sh`) lists candidates with their memory, age, class and what dies with them, plus swap and memory pressure. No sudo, no kills.
2. The agent decides with you: idle sessions (no activity for 12 h, not running) and closed-app tails go on your word; dev servers and anything unclear are asked about. Then it kills with a TERM → KILL pass and measures again.

It also explains when memory is really short (pressure level and growing swapouts) and when "15 GB of swap used" is just macOS keeping swap until reboot.

The script output is in Russian.

## Install (single skill)

```
https://github.com/serejaris/personal-corp-os/tree/main/skills/it-memory
```
