---
name: it-ram-doctor
description: >-
  Process tails that hold memory for nothing: finds them and, on the owner's word, kills them. Use on "slow", "swap", "low memory", "kill the tails", "clean up memory", "ram doctor", and after closing heavy apps.
---

# it-ram-doctor

The snapshot only reads; step 4 kills, and only on the owner's word.

## When memory is short

"13 of 16 GB used" and the swap size do not show load: macOS keeps memory busy with cache and compression, and swap does not shrink until a reboot. Memory is short when any of these holds:

- pressure: `sysctl kern.memorystatus_vm_pressure_level` is 4 or stays at 2 for long ([threshold](https://github.com/anthropics/claude-code/issues/73834): on Apple silicon 2 appears under ordinary compression); `memory_pressure | tail -1` shows less than 25–30% free;
- `Swapouts` in `vm_stat` grow between two readings a minute apart;
- swap grows three readings in a row.

No signs: clean only on a direct request. Measure a process by `top -o mem` or `footprint`; `ps` understates the compressed part.

## Procedure

1. **Snapshot.** From the skill root:

   ```bash
   bash scripts/tails-macos.sh                                                     # local
   ssh -o BatchMode=yes -o ConnectTimeout=8 <alias> 'bash -s' < scripts/tails-<os>.sh   # remote
   ```

   Keep the script's summary as the "before" and take the top of `top -o mem`: the table omits launchd services (on Linux, `.service` units), system processes, Claude.app and children of active sessions, and one live job (a local whisper run, 9 GB) can outweigh all the tails. Done when you hold the table, the summary and the top of `top`.

2. **Decide.** The "Action" column sets what to do with a class (the script prints the Russian labels shown):

   | Class | What it is | Action |
   |---|---|---|
   | `claude-сессия` (claude session) | Claude Code CLI, bundled with Desktop or standalone | kill if a tail |
   | `хвост закрытого приложения` (closed-app tail) | processes of `X.app` with PPID 1 while `X` is not running, and everything under them | kill |
   | `сирота` (orphan) | a worker with PPID 1: omp/bun, Chrome for Testing, npx/MCP, grok/codex; duplicates marked | kill |
   | `dev-сервер` (dev server) | `http.server`, vite, `npm run dev` without a parent, older than a day | ask |
   | `зомби` (zombie) | STAT Z older than a minute | its parent reaps it: name the parent |

   The script does not know session activity: match the id from the row against `list_sessions`. A tail is a session with `lastActivityAt` older than 12 h, not `isRunning`, with no work going on. Id "не найдена" (not found) and sessions on a remote machine (`list_sessions` does not know them): ask. Done when every row has an action and every claude row has a verdict: tail, live or ask.

3. **Show.** The table to the owner: row, action, what dies with it. Before killing a claude process, name its dev servers and ports from the "dies with it" column. "Kill" and "clean up" go straight to step 4; "slow" and "swap" wait for the word. Done when the owner sees the table and the word is received or not needed.

4. **Kill.** Only rows that passed step 2, in bash with an array, with a check and a follow-up KILL:

   ```bash
   # bash -c: in zsh `kill $pids` with a string silently kills nothing
   bash -c 'pids=(111 222 333); kill -TERM "${pids[@]}"; sleep 4
     for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && kill -KILL "$p"; done'
   ```

   - Idle claude sessions ignore SIGTERM: the KILL pass is required.
   - A dev server started with `&` inside a session outlives it as an orphan: check the port with `lsof -iTCP:<port> -sTCP:LISTEN`.

   Done when no pid from the array answers `kill -0` and the ports of killed dev servers are free.

5. **Verify.** Run the script again. Report to the owner: pressure and the candidates' RSS before and after; swap does not shrink until a reboot, so it is not the measure. A killed claude session stays in the app's list and comes back on the next message. Killing the CLI does not free the memory of Desktop's renderer and main processes: that needs an app restart, on the owner's word, after checking it will not interrupt needed work, with another reading. Done when the run shows no killed candidates and "before" and "after" are named.

## Off limits

- the current session, active and `isRunning` claude sessions;
- launchd services;
- Claude.app.
