#!/bin/bash
# Хвосты процессов на macOS: кандидаты, которые держат память впустую. Только чтение, без sudo, ничего не убивает.
# Вывод — markdown-таблица кандидатов и итог по памяти; решение и убийство — по ../SKILL.md.
# Удалённо: ssh -o BatchMode=yes -o ConnectTimeout=8 <алиас> 'bash -s' < tails-macos.sh
# Совместим с bash 3.2 (системный bash macOS).

TODAY=$(date '+%Y-%m-%d %H:%M')
ME=$(id -u)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/tails.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# Снимок процессов: поля отдельно от строки запуска (в путях бывают пробелы).
ps -axww -o pid=,ppid=,uid=,rss=,etime=,stat=,comm= >"$TMP/ps" 2>/dev/null
ps -axww -o pid=,args= >"$TMP/args" 2>/dev/null

# PID служб gui-домена: их держит сам launchd, это не хвосты.
launchctl print "gui/$ME" 2>/dev/null |
  awk '/^\tservices = \{/ {s=1; next} s && /^\t\}/ {exit} s && $1 ~ /^[0-9]+$/ && $1 > 0 {print $1}' >"$TMP/svc"

report() {
  printf '# Хвосты процессов: %s\n\n' "$(scutil --get ComputerName 2>/dev/null)"
  printf 'Снято: %s, ' "$TODAY"
  if [ -n "$SSH_CONNECTION" ]; then printf 'по SSH, '; else printf 'локально, '; fi
  printf 'пользователь `%s`, без sudo. Скрипт ничего не убивает.\n\n' "$(id -un)"

  awk -v SELF="$$" -v ME="$ME" -v TASK_HOME="$HOME" -v ARGS="$TMP/args" -v SVC="$TMP/svc" -v SUMF="$TMP/sum" '
  function secs(e,   d, n, p, s) { # [[dd-]hh:]mm:ss -> секунды
    d = 0; if (index(e, "-")) { d = substr(e, 1, index(e, "-") - 1); e = substr(e, index(e, "-") + 1) }
    n = split(e, p, ":"); s = 0
    if (n == 3) s = p[1]*3600 + p[2]*60 + p[3]; else if (n == 2) s = p[1]*60 + p[2]; else s = p[1]
    return d*86400 + s
  }
  function age(s) {
    if (s >= 86400) return int(s/86400) " д " int((s%86400)/3600) " ч"
    if (s >= 3600) return int(s/3600) " ч"
    return int(s/60) " мин"
  }
  function base(p,   n, a) { n = split(p, a, "/"); return a[n] }
  function tilde(p) { if (index(p, TASK_HOME) == 1) return "~" substr(p, length(TASK_HOME) + 1); return p }
  function isclaude(pid,   a, c) {
    a = args[pid]; c = comm[pid]
    # Desktop layouts with and without the content-hash directory, plus standalone CLI.
    return (c ~ /\/claude-code\/[^\/]+\/([^\/]+\/)?claude\.app\/Contents\/MacOS\/claude$/ ||
            a ~ /^([^ ]*\/)?claude( |$)/ || c ~ /\/\.local\/share\/claude\/versions\/[^\/ ]+$/)
  }
  function mdsafe(s) { gsub(/\|/, "/", s); gsub(/`/, "", s); return s }
  # Короткое имя: приложение или argv0 и первые аргументы.
  function short(pid,   a, n, w, i, s) {
    a = args[pid]
    if (match(a, /\/claude-code\/[^\/]+\//)) return "claude CLI " substr(a, RSTART + 13, RLENGTH - 14)
    if (match(a, /^\/Applications\/[^\/]+\.app\//)) {
      s = substr(a, 15, RLENGTH - 15)
      w = substr(a, RLENGTH + 1); sub(/ --.*/, "", w)
      return mdsafe(s ": " base(w) (index(a, " --") ? " …" : ""))
    }
    n = split(a, w, " "); s = base(w[1])
    for (i = 2; i <= n && i <= 4; i++) s = s " " tilde(w[i])
    if (n > 4) s = s " …"
    if (length(s) > 80) s = substr(s, 1, 77) "…"
    return mdsafe(s)
  }
  function isdev(pid,   a) {
    a = args[pid]
    return (a ~ /http\.server|(^|[\/ ])vite( |$)|npm run dev|pnpm (run )?dev|bun (run )?dev|next dev|astro dev|webpack.*serve/)
  }
  function ports(pid,   c, l, out) { # слушающие TCP-порты процесса
    out = ""; c = "lsof -nP -a -p " pid " -iTCP -sTCP:LISTEN -Fn 2>/dev/null"
    while ((c | getline l) > 0) if (l ~ /^n/) { sub(/.*:/, "", l); if (index(" " out " ", " " l " ") == 0) out = out (out ? " " : "") l }
    close(c); return out
  }
  function cwd(pid,   c, l, out) {
    out = ""; c = "lsof -a -p " pid " -d cwd -Fn 2>/dev/null"
    while ((c | getline l) > 0) if (l ~ /^n/) out = substr(l, 2)
    close(c); return out
  }
  function session(pid,   c, l, out) { # из окружения берём только id сессии, остальное не печатаем
    out = ""; c = "ps eww -o command= -p " pid " 2>/dev/null | tr \" \" \"\\n\" | grep \"^CLAUDE_CODE_HOST_SESSION_ID=\" | head -1"
    if ((c | getline l) > 0) { sub(/^CLAUDE_CODE_HOST_SESSION_ID=/, "", l); out = l }
    close(c); return out
  }
  function bundle_exe(app,   c, l) { # главный бинарник приложения по Info.plist
    if (app in exe_of) return exe_of[app]
    l = ""; c = "defaults read \"/Applications/" app ".app/Contents/Info\" CFBundleExecutable 2>/dev/null"
    c | getline l; close(c)
    if (l == "") l = app
    exe_of[app] = l; return l
  }
  # Все потомки pid: в список D через пробел.
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
  FILENAME == ARGS { p = $1; sub(/^ *[0-9]+ /, ""); args[p] = $0; next }
  {
    p = $1; ppid[p] = $2; uid[p] = $3; rss[p] = $4; et[p] = secs($5); st[p] = $6
    c = $0; sub(/^ *[0-9]+ +[0-9]+ +[0-9]+ +[0-9]+ +[^ ]+ +[^ ]+ +/, "", c); comm[p] = c
    pids[++np] = p
  }
  END {
    # Текущая оболочка и её предки (в т.ч. сессия, из которой запущен скрипт).
    x = SELF; while (x != "" && x != "0" && !(x in anc)) { anc[x] = 1; x = ppid[x] }
    for (i = 1; i <= np; i++) {
      p = pids[i]; a = args[p]
      if (a == "") a = comm[p]
      args[p] = a
      app = ""
      if (match(a, /^\/Applications\/[^\/]+\.app\//)) app = substr(a, 15, RLENGTH - 19)
      appof[p] = app
      if (app != "") running[a] = 1
      if (app != "" && (p in svc)) svcapp[app] = 1  # у приложения есть живая служба launchd: его помощники законны
      if (comm[p] ~ /^\//) running[comm[p]] = 1
      else if (comm[p] !~ /\//) running_name[comm[p]] = 1  # некоторые GUI-процессы дают только имя, например ZCode
    }
    for (i = 1; i <= np; i++) {
      p = pids[i]
      if (st[p] ~ /Z/) { if (et[p] >= 60) zomb[p] = 1; continue }  # моложе минуты — обычный переходный зомби (sshd и т.п.)
      if (uid[p] != ME || (p in anc) || (p in svc)) continue
      if (comm[p] ~ /^\/(System|usr\/libexec|usr\/sbin|sbin)\// || args[p] ~ /^\/(System|usr\/libexec|usr\/sbin|sbin)\//) continue
      if (appof[p] == "Claude") continue
      a = args[p]
      if (isclaude(p)) { claude[p] = 1; continue }
      app = appof[p]
      if (app != "") {
        # Корень хвоста — только у launchd (PPID 1): помощник под живым процессом (cua_node у codex) хвостом не считается.
        # Расширения .appex система поднимает без приложения — тоже не хвост.
        if (ppid[p] != 1 || (app in svcapp) || a ~ /\.appex\//) continue
        e = "/Applications/" app ".app/Contents/MacOS/" bundle_exe(app)
        alive = (bundle_exe(app) in running_name)
        for (r in running) if (r == e || index(r, e " ") == 1) { alive = 1; break }
        if (!alive) { tail[p] = app }
        continue
      }
      if (ppid[p] == 1) {
        if (base(comm[p]) ~ /^(omp|bun)$/ || a ~ /^([^ ]*\/)?(omp|bun)( |$)/) orphan[p] = "omp/bun-воркер"
        else if (a ~ /Chrome for Testing|\/puppeteer\/|ms-playwright\/|chrome-headless-shell/) orphan[p] = "Chrome for Testing / puppeteer"
        else if (a ~ /mcp|modelcontextprotocol|npm exec|(^|\/)npx /) orphan[p] = "MCP-сервер / npx"
        else if (a ~ /^([^ ]*\/)?(grok|codex)( |$|-)/) orphan[p] = "grok/codex без родителя"
        else if (isdev(p) && et[p] > 86400) dev[p] = 1
      }
    }

    print "| PID | RSS MB | возраст | класс | процесс | причина и что умрёт вместе |"
    print "|---|---|---|---|---|---|"

    # claude-сессии: решение об idle — агент по list_sessions.
    for (p in claude) {
      s = session(p); d = desc(p); n = split(d, dl, " "); kids = ""; krss = 0; devs = ""
      delete cnt
      for (j = 1; j <= n; j++) {
        k = dl[j]; krss += rss[k]
        if (isdev(k)) { pt = ports(k); devs = devs (devs ? "; " : "") short(k) (pt ? " порт " pt : "") }
        w = args[k]; split(w, ww, " "); b = base(ww[1])
        if (b ~ /^(node|python[0-9.]*|Python|bun|npm|npx)$/ && ww[2] != "") b = b " " base(ww[2])
        if (appof[k] != "") b = appof[k] ".app"
        else if (w ~ /Chrome for Testing/) b = "Chrome for Testing"
        cnt[b]++
      }
      for (b in cnt) kids = kids (kids ? ", " : "") mdsafe(b) (cnt[b] > 1 ? "×" cnt[b] : "")
      why = "сессия `" (s ? s : "не найдена") "` · cwd `" mdsafe(tilde(cwd(p))) "` · дочерних " n
      if (n) why = why " (" int(krss/1024 + 0.5) " MB): " kids
      if (devs != "") why = why " · **dev-серверы умрут вместе:** " devs
      row(p, "claude-сессия", why)
    }

    # Хвосты закрытых приложений и всё, что под ними.
    for (p in tail) {
      row(p, "хвост закрытого приложения", tail[p] ".app закрыто, главный бинарник `" bundle_exe(tail[p]) "` не запущен")
      d = desc(p); n = split(d, dl, " ")
      for (j = 1; j <= n; j++) if (!(dl[j] in anc)) row(dl[j], "хвост закрытого приложения", "внутри хвоста " tail[p] ".app (PID " p ")")
    }

    # Сироты: дубли по одинаковой строке запуска.
    for (p in orphan) dup[args[p]]++
    for (p in orphan) {
      why = orphan[p] ", PPID 1"
      if (dup[args[p]] > 1) why = why " · **дубль** (" dup[args[p]] " одинаковых)"
      row(p, "сирота", why)
      d = desc(p); n = split(d, dl, " ")
      for (j = 1; j <= n; j++) if (!(dl[j] in anc)) row(dl[j], "сирота", "внутри сироты PID " p)
    }

    for (p in dev) { pt = ports(p); row(p, "dev-сервер", "PPID 1, старше суток" (pt ? ", порт " pt : "") " — только показать, спросить") }

    for (p in zomb) {
      nz++; q = ppid[p]
      printf "| %s | 0 | %s | зомби | `%s` | родитель PID %s `%s` — память не держит, убирается родителем |\n", p, age(et[p]), short(p), q, short(q)
    }

    if (nrow + nz == 0) print "| — | — | — | — | — | кандидатов нет |"
    printf "%d %d\n", sum/1024 + 0.5, nrow + nz > SUMF
  }' "$TMP/svc" "$TMP/args" "$TMP/ps"

  # Текущая сессия исключена из таблицы, но названа: её не трогать.
  x=$$
  while [ -n "$x" ] && [ "$x" != "0" ] && [ "$x" != "1" ]; do
    a=$(ps -o args= -p "$x" 2>/dev/null)
    case "$a" in
      */claude-code/*/claude.app/Contents/MacOS/claude*|claude\ *|*/.local/bin/claude*|*/.local/share/claude/versions/*)
        s=$(ps eww -o command= -p "$x" 2>/dev/null | tr ' ' '\n' | grep '^CLAUDE_CODE_HOST_SESSION_ID=' | head -1 | sed 's/^CLAUDE_CODE_HOST_SESSION_ID=//')
        printf '\nТекущая сессия (исключена, не трогать): PID %s, `%s`.\n' "$x" "${s:-без id}"
        break ;;
    esac
    x=$(ps -o ppid= -p "$x" 2>/dev/null | tr -d ' ')
  done

  set -- $(cat "$TMP/sum" 2>/dev/null)
  printf '\n## Итог\n\n'
  echo "- кандидатов: ${2:-0}, их RSS вместе: ${1:-0} MB (без дочерних claude-сессий)"
  echo "- своп: $(sysctl -n vm.swapusage 2>/dev/null)"
  echo "- $(memory_pressure 2>/dev/null | tail -1)"
}

# Фильтр последней линии: MAC и UUID скрыты, кроме id сессии `local_<uuid>`; значения секретов в аргументах скрыты.
redact() {
  perl -pe 's/\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b/<скрыто>/g;
    s/(?<!local_)\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b/<скрыто>/g;
    s/((?:token|secret|passw\w*|api[_-]?key|auth)\w*[=: ]+)[^ |`]+/$1<скрыто>/gi'
}

report 2>/dev/null | redact
