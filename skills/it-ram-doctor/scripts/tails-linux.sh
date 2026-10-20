#!/bin/bash
# Хвосты процессов на Linux (systemd): сироты-воркеры, долгие dev-серверы, зомби. Только чтение, без sudo, ничего не убивает.
# Вывод — markdown-таблица кандидатов и итог по памяти; решение и убийство — по ../SKILL.md.
# Удалённо: ssh -o BatchMode=yes -o ConnectTimeout=8 <алиас> 'bash -s' < tails-linux.sh

TODAY=$(date '+%Y-%m-%d %H:%M')
ME=$(id -u)
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

ps -eww -o pid=,ppid=,uid=,rss=,etimes=,stat=,args= >"$TMP/ps" 2>/dev/null

# Сироты переходят к launchd-аналогу: PID 1 или пользовательский `systemd --user`.
USYSD=$(pgrep -u "$ME" -x systemd 2>/dev/null | head -1)

# Процессы внутри .service-юнита держит systemd: это службы, не хвосты.
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  grep -q '\.service$' "$d/cgroup" 2>/dev/null && echo "$p"
done >"$TMP/svc"

report() {
  printf '# Хвосты процессов: %s\n\n' "$(hostnamectl --static 2>/dev/null || hostname)"
  printf 'Снято: %s, ' "$TODAY"
  if [ -n "$SSH_CONNECTION" ]; then printf 'по SSH, '; else printf 'локально, '; fi
  printf 'пользователь `%s`, без sudo. Скрипт ничего не убивает.\n\n' "$(id -un)"

  awk -v SELF="$$" -v ME="$ME" -v HOME="$HOME" -v USYSD="${USYSD:-1}" -v SVC="$TMP/svc" -v SUMF="$TMP/sum" '
  function age(s) {
    if (s >= 86400) return int(s/86400) " д " int((s%86400)/3600) " ч"
    if (s >= 3600) return int(s/3600) " ч"
    return int(s/60) " мин"
  }
  function base(p,   n, a) { n = split(p, a, "/"); return a[n] }
  function tilde(p) { if (index(p, HOME) == 1) return "~" substr(p, length(HOME) + 1); return p }
  function mdsafe(s) { gsub(/\|/, "/", s); gsub(/`/, "", s); return s }
  function short(pid,   n, w, i, s) {
    n = split(args[pid], w, " "); s = base(w[1])
    for (i = 2; i <= n && i <= 4; i++) s = s " " tilde(w[i])
    if (n > 4) s = s " …"
    if (length(s) > 80) s = substr(s, 1, 77) "…"
    return mdsafe(s)
  }
  function isdev(pid,   a) {
    a = args[pid]
    return (a ~ /http\.server|(^|[\/ ])vite( |$)|npm run dev|pnpm (run )?dev|bun (run )?dev|next dev|astro dev|webpack.*serve/)
  }
  function desc(pid,   q, h, t, x, c, out) {
    out = ""; q[1] = pid; h = 1; t = 1
    while (h <= t) { x = q[h++]; for (c in ppid) if (ppid[c] == x) { q[++t] = c; out = out " " c } }
    return out
  }
  function row(pid, cls, why) {
    if (pid in shown) return
    shown[pid] = 1; nrow++
    printf "| %s | %d | %s | %s | `%s` | %s |\n", pid, rss[pid]/1024 + 0.5, age(et[pid]), cls, short(pid), why
    sum += rss[pid]
  }

  FILENAME == SVC { svc[$1] = 1; next }
  {
    p = $1; ppid[p] = $2; uid[p] = $3; rss[p] = $4; et[p] = $5; st[p] = $6
    a = $0; sub(/^ *[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[^ ]+ +/, "", a); args[p] = a
    pids[++np] = p
  }
  END {
    x = SELF; while (x != "" && x != "0" && !(x in anc)) { anc[x] = 1; x = ppid[x] }
    for (i = 1; i <= np; i++) {
      p = pids[i]; a = args[p]
      if (st[p] ~ /Z/) { if (et[p] >= 60) zomb[p] = 1; continue }
      if (uid[p] != ME || (p in anc) || (p in svc)) continue
      if (ppid[p] != 1 && ppid[p] != USYSD) continue
      if (a ~ /omp|\.bun\/bin\/|(^|\/)bun /) orphan[p] = "omp/bun-воркер"
      else if (a ~ /[Cc]hrome for [Tt]esting|\/puppeteer\/|ms-playwright\/|chrome-headless-shell|--headless/) orphan[p] = "Chrome for Testing / puppeteer"
      else if (a ~ /mcp|modelcontextprotocol|npm exec|(^|\/)npx /) orphan[p] = "MCP-сервер / npx"
      else if (a ~ /^([^ ]*\/)?(grok|codex|claude)( |$|-)/) orphan[p] = "агентский CLI без родителя"
      else if (isdev(p) && et[p] > 86400) dev[p] = 1
    }

    print "| PID | RSS MB | возраст | класс | процесс | причина и что умрёт вместе |"
    print "|---|---|---|---|---|---|"

    for (p in orphan) dup[args[p]]++
    for (p in orphan) {
      why = orphan[p] ", родитель — " (ppid[p] == 1 ? "PID 1" : "systemd --user") ", вне .service-юнита"
      if (dup[args[p]] > 1) why = why " · **дубль** (" dup[args[p]] " одинаковых)"
      row(p, "сирота", why)
      d = desc(p); n = split(d, dl, " ")
      for (j = 1; j <= n; j++) if (!(dl[j] in anc)) row(dl[j], "сирота", "внутри сироты PID " p)
    }

    for (p in dev) row(p, "dev-сервер", "без родителя, старше суток — только показать, спросить")

    for (p in zomb) {
      nz++; q = ppid[p]
      printf "| %s | 0 | %s | зомби | `%s` | родитель PID %s `%s` — память не держит, убирается родителем |\n", p, age(et[p]), short(p), q, short(q)
    }

    if (nrow + nz == 0) print "| — | — | — | — | — | кандидатов нет |"
    printf "%d %d\n", sum/1024 + 0.5, nrow + nz > SUMF
  }' "$TMP/svc" "$TMP/ps"

  set -- $(cat "$TMP/sum" 2>/dev/null)
  printf '\n## Итог\n\n'
  echo "- кандидатов: ${2:-0}, их RSS вместе: ${1:-0} MB"
  free -m 2>/dev/null | awk '/^Mem:/ {printf "- память: всего %s MB, доступно %s MB\n", $2, $7} /^Swap:/ {printf "- своп: всего %s MB, занято %s MB\n", $2, $3}'
  [ -r /proc/pressure/memory ] && echo "- давление памяти (PSI): $(head -1 /proc/pressure/memory)"
}

redact() {
  perl -pe 's/\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/<скрыто>/g;
    s/\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b/<скрыто>/g;
    s/((?:token|secret|passw\w*|api[_-]?key|auth)\w*[=: ]+)[^ |`]+/$1<скрыто>/gi'
}

report 2>/dev/null | redact
