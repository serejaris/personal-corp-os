#!/bin/bash
# Снимок описи устройства на macOS: только чтение, права не повышаются.
# Вывод: разделы шаблона ../template.md, черновик для devices/<устройство>.md.
# Удалённо: ssh -o BatchMode=yes -o ConnectTimeout=8 <алиас> 'bash -s' < snapshot-macos.sh
# Совместим с bash 3.2 (системный bash macOS).

TODAY=$(date +%Y-%m-%d)
NOT_CHECKED=""

nc_add() { NOT_CHECKED="${NOT_CHECKED}- $1 - не проверено ${TODAY}: $2
"; }

has() { command -v "$1" >/dev/null 2>&1; }
gb() { awk -v b="$1" 'BEGIN{printf "%d GB", b/1073741824 + 0.5}'; }
section() { printf '\n## %s\n\nПроверено: %s (snapshot-macos.sh)\n\n' "$1" "$TODAY"; }
# Таймаут без coreutils: perl есть в любой macOS.
t10() { perl -e 'alarm shift; exec @ARGV' 10 "$@" 2>/dev/null; }

snapshot() {
  printf '# Снимок описи: %s\n\n' "$(scutil --get ComputerName 2>/dev/null)"
  printf 'Снято: %s, ' "$TODAY"
  if [ -n "$SSH_CONNECTION" ]; then printf 'по SSH, '; else printf 'локально, '; fi
  printf 'пользователь `%s`, права не повышались. Черновик: перенести изменившееся в devices/<устройство>.md.\n' "$(id -un)"

  section "Шапка"
  echo "- имя хоста: \`$(scutil --get LocalHostName 2>/dev/null)\` (mDNS \`$(scutil --get LocalHostName 2>/dev/null).local\`)"

  section "Система"
  echo "- модель: \`$(sysctl -n hw.model)\`"
  echo "- процессор: $(sysctl -n machdep.cpu.brand_string), ядер: $(sysctl -n hw.ncpu)"
  echo "- память: $(gb "$(sysctl -n hw.memsize)")"
  echo "- macOS \`$(sw_vers -productVersion)\`, ядро Darwin \`$(uname -r)\`"

  section "Ресурсы"
  echo "- RAM: $(gb "$(sysctl -n hw.memsize)")"
  sysctl -n vm.swapusage 2>/dev/null | awk '{ t=$3+0; if (t == 0) print "- своп: нет"; else printf "- своп: есть, порядок %d GB\n", t/1024 + 0.5 }'
  df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {printf "- диск рабочего тома: %d GB, занято %s\n", ($2/1048576)+0.5, $5}'
  if pmset -g batt 2>/dev/null | grep -q InternalBattery; then echo "- питание: батарея есть"; else echo "- питание: батареи нет"; fi

  section "Сеть"
  iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')
  gw=$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}')
  if [ -n "$iface" ]; then
    kind=$(networksetup -listallhardwareports 2>/dev/null | awk -v i="$iface" '/Hardware Port/ {p=$0; sub(/^Hardware Port: /,"",p)} $0 ~ "Device: "i"$" {print p}')
    echo "- связь: ${kind:-неизвестно} \`$iface\`"
    echo "- адрес: \`$(ipconfig getifaddr "$iface" 2>/dev/null)\` (текущий, ${TODAY})"
    echo "- шлюз: \`$gw\`"
  else
    echo "- маршрута по умолчанию нет: устройство вне сети"
  fi
  echo "- имя Wi-Fi: в опись не пишется"
  vpn=$(ls /Applications 2>/dev/null | grep -i -E 'tailscale|zerotier|wireguard|vpn' | sed 's/\.app$//' | paste -sd ',' - | sed 's/,/, /g')
  echo "- VPN-приложения: ${vpn:-нет}"

  section "Доступы"
  if nc -z localhost 22 2>/dev/null; then echo "- SSH на устройство: порт 22 принимает соединения"; else echo "- SSH на устройство: порт 22 закрыт (Remote Login выключен)"; fi
  if nc -z localhost 5900 2>/dev/null; then echo "- удалённый экран: порт 5900 принимает соединения"; else echo "- удалённый экран: порт 5900 закрыт"; fi
  echo "- пользователь: \`$(id -un)\`"
  if [ -f "$HOME/.ssh/authorized_keys" ]; then
    echo "- вход по ключу: строк в authorized_keys - $(grep -c -v -E '^[[:space:]]*(#|$)' "$HOME/.ssh/authorized_keys")"
  else
    echo "- authorized_keys: нет у этого пользователя"
  fi
  if [ -f "$HOME/.ssh/config" ]; then
    echo "- SSH-алиасы наружу: $(awk 'tolower($1)=="host" {for (i=2;i<=NF;i++) print $i}' "$HOME/.ssh/config" | grep -v '[*?!]' | sort -u | paste -sd ',' - | sed 's/,/, /g')"
  else
    echo "- SSH-алиасов наружу нет (~/.ssh/config отсутствует)"
  fi
  if has tmux; then echo "- tmux: есть"; else echo "- tmux: нет"; fi

  section "Разрешения"
  # sudo -n true ничего не запускает, а только проверяет, пустит ли система без пароля.
  if sudo -n true 2>/dev/null; then echo "- sudo без пароля: да"; else echo "- sudo без пароля: нет"; fi
  echo "- группы: $(id -Gn | sed 's/ /, /g')"
  echo "- шифрование диска: $(fdesetup status 2>/dev/null | head -1)"
  echo "- защита системы: $(csrutil status 2>/dev/null | sed 's/.*: //')"
  nc_add "разрешения macOS (камера, экран, полный доступ к диску)" "база TCC читается только при Full Disk Access у терминала"
  nc_add "правила firewall" "нужны права администратора"

  section "Агенты и инструменты"
  for d in "$HOME/.local/bin" "$HOME/.npm-global/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin" /opt/homebrew/bin; do
    [ -d "$d" ] && PATH="$PATH:$d"
  done
  for c in claude codex gemini opencode hermes; do
    p=$(command -v "$c" 2>/dev/null)
    [ -z "$p" ] && continue
    v=$(t10 "$c" --version | head -1)
    echo "- $c: \`$(echo "$p" | sed "s#^$HOME#~#")\`, версия ${v:-не ответила за 10 с}"
  done
  [ -f "$HOME/.claude/settings.json" ] && echo "- Claude Code: настройки \`~/.claude/settings.json\`"
  [ -f "$HOME/.codex/config.toml" ] && echo "- Codex: настройки \`~/.codex/config.toml\`"
  tools=""
  for c in git gh node python3 uv docker ffmpeg brew; do has "$c" && tools="$tools $c"; done
  echo "- ключевые CLI:${tools:- нет}"

  section "Фоновые службы"
  agents=$(ls "$HOME/Library/LaunchAgents" 2>/dev/null | sed 's/\.plist$//' | paste -sd ',' - | sed 's/,/, /g')
  echo "- свои LaunchAgents: ${agents:-нет}"
  if [ -n "$agents" ]; then
    launchctl list 2>/dev/null | awk 'NR>1 {print $3}' | grep -F -f <(ls "$HOME/Library/LaunchAgents" 2>/dev/null | sed 's/\.plist$//') | sed 's/^/- загружен: /'
  fi

  section "Роли"
  echo "- скрипт роли не снимает: ссылка на отдел-владелец остаётся из текущей описи"

  section "Не проверено"
  printf '%s' "$NOT_CHECKED"
}

# Фильтр: MAC, UUID и строки с идентификаторами и секретами в вывод не попадают.
redact() {
  sed -E 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/<скрыто>/g; s/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<скрыто>/g' |
    grep -v -i -E 'serial|uuid|udid|bssid|ssid:|passw|token|secret|api.?key|private key'
}

snapshot 2>/dev/null | redact
