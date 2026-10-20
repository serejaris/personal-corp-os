---
name: it-ram-doctor
description: Finds and, on the owner's word, kills process tails that hold a machine's memory for nothing — idle Claude Code desktop sessions, leftovers of closed apps, orphaned workers, zombies. Use on "memory", "swap", "laptop is slow", "zombie processes", "kill the tails", "clean up memory", "ram doctor", and after closing heavy apps.
---

# it-ram-doctor

An active skill: it kills processes, so the snapshot and the kill are separate steps. The snapshot script only reads.

Typical picture on a 16 GB Mac: a few gigabytes held by Claude Code desktop sessions idle for days (30–400 MB each, dozens of them), a daemon of a closed app still running its workers, duplicate worker brokers, a Chrome for Testing left by puppeteer. A background `npm run dev` started inside a session dies together with that session.

## When memory is really short

"13 of 16 GB used" and the Swap Used size mean nothing by themselves: macOS keeps memory busy with cache and compression, and swap does not shrink after memory is freed until a reboot. Shortage shows by three signs:

- pressure is yellow or red: `sysctl kern.memorystatus_vm_pressure_level` above 1, `memory_pressure` shows less than 25–30% free;
- `Swapouts` in `vm_stat` grow before your eyes (two readings a minute apart);
- swap grows three readings in a row.

Measure a process by `top -o mem` or `footprint`: `ps` (RSS) does not see the compressed part and understates it. Look at the top of `top -o mem` before cleaning: one live job (a local whisper transcription, a model load) can hold more than all the tails together, and the script does not list children of active sessions.

## Procedure

1. **Snapshot.** From the skill root:

   ```bash
   bash scripts/tails-macos.sh                                                     # local
   ssh -o BatchMode=yes -o ConnectTimeout=8 <alias> 'bash -s' < scripts/tails-<os>.sh   # remote
   ```

   The script reads only, never calls sudo, kills nothing. It prints a table of candidates and a summary: total RSS, swap, memory pressure. Keep the summary: it is the "before" for step 5. It skips launchd gui-domain services (on Linux, processes in `.service` units), system processes, Claude.app, the current shell and its ancestors; the current claude session is named on a separate line. It prints no process environment, only session ids. Output is in Russian; the class labels are:

   | Class | What it is |
   |---|---|
   | `claude-сессия` (claude session) | a Claude Code CLI process: bundled with Desktop (including the version/hash path) or standalone; session id when present, folder, child processes and dev servers with ports |
   | `хвост закрытого приложения` (closed-app tail) | a process from `/Applications/X.app` with PPID 1 while the main binary `X` is not running, and everything under it |
   | `сирота` (orphan) | a worker with PPID 1: omp/bun, Chrome for Testing / puppeteer, npx/MCP servers, grok/codex without a parent; duplicates are marked |
   | `dev-сервер` (dev server) | `http.server`, vite, `npm run dev` without a parent, older than a day |
   | `зомби` (zombie) | STAT Z older than a minute, with a parent: holds no memory, its parent reaps it |

2. **Decide on claude sessions.** The script does not know activity. In the Claude desktop app call `list_sessions` and match by id: a session is a tail if its `lastActivityAt` is older than 12 h, it is not the current one, not `isRunning`, and no work is going on in it. Leave the other claude sessions alone.

3. **Show or kill.**
   - On the owner's "kill", "clean up" — without another question: claude-session tails from step 2, closed-app tails, orphans.
   - Dev servers and anything unclear — show as a table and ask.
   - Never: the current session, active and running sessions, launchd services, Claude.app.
   - Before killing a claude process, name its child dev servers and ports from the "dies with it" column: they die with it.
   - Zombies are not killed: if one lingers, name its parent to the owner.

4. **Kill** — in bash with an array, with a check and a follow-up KILL:

   ```bash
   bash -c 'pids=(111 222 333); kill -TERM "${pids[@]}"; sleep 4
     for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && kill -KILL "$p"; done'
   ```

   Pitfalls:
   - in zsh `kill $pids` with a string does not split words, kill gets one string and silently kills nothing;
   - idle claude sessions often ignore SIGTERM, so the KILL pass is not optional;
   - a dev server started with `&` inside a session can outlive the killed session as an orphan: check its port with `lsof -iTCP:<port> -sTCP:LISTEN` after the kill.

5. **Verify.** Run the script again: no killed candidates left. Report swap and memory pressure before and after to the owner.

A killed claude session stays in the app's list: its process comes back on the next message in it. Ending the CLI does not free the memory of the Desktop renderer/utility processes. Restarting the whole app is fine after checking it does not interrupt needed work; confirm the effect with another reading.
