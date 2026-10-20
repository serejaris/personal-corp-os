#!/bin/bash
# Снимок описи устройства на Linux (systemd): только чтение, права не повышаются.
# Вывод: разделы шаблона ../template.md, черновик для devices/<устройство>.md.
# Удалённо: ssh -o BatchMode=yes -o ConnectTimeout=8 <алиас> 'bash -s' < snapshot-linux.sh

TODAY=$(date +%Y-%m-%d)
NOT_CHECKED=""

nc_add() { NOT_CHECKED="${NOT_CHECKED}- $1 - не проверено ${TODAY}: $2
"; }

has() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n## %s\n\nПроверено: %s (snapshot-linux.sh)\n\n' "$1" "$TODAY"; }
t10() { timeout 10 "$@" 2>/dev/null; }

snapshot() {
  host=$(hostnamectl --static 2>/dev/null || hostname)
  printf '# Снимок описи: %s\n\n' "$host"
  printf 'Снято: %s, ' "$TODAY"
  if [ -n "$SSH_CONNECTION" ]; then printf 'по SSH, '; else printf 'локально, '; fi
  printf 'пользователь `%s`, права не повышались. Черновик: перенести изменившееся в devices/<устройство>.md.\n' "$(id -un)"

  section "Шапка"
  echo "- имя хоста: \`$host\` (mDNS \`$host.local\`)"

  section "Система"
  # hostnamectl целиком не печатаем: в нём Machine ID и Boot ID.
  vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
  model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
  echo "- модель: ${vendor:-?} ${model:-?}"
  echo "- процессор: $(lscpu 2>/dev/null | awk -F: '/^Model name/ {gsub(/^ +/,"",$2); print $2; exit}'), ядер: $(nproc)"
  echo "- память: $(awk '/^MemTotal/ {printf "%d GB", $2/1048576 + 0.5}' /proc/meminfo)"
  echo "- ОС: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-?}"), ядро \`$(uname -r)\`"

  section "Ресурсы"
  echo "- RAM: $(awk '/^MemTotal/ {printf "%d GB", $2/1048576 + 0.5}' /proc/meminfo)"
  awk '/^SwapTotal/ {t=$2} END { if (t == 0) print "- своп: нет"; else printf "- своп: есть, порядок %d GB\n", t/1048576 + 0.5 }' /proc/meminfo
  df -h / 2>/dev/null | awk 'NR==2 {printf "- диск рабочего тома: размер %s, занято %s\n", $2, $5}'
  if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then echo "- питание: батарея есть"; else echo "- питание: батареи нет"; fi

  section "Сеть"
  iface=$(ip route show default 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="dev") {print $(i+1); exit}}')
  gw=$(ip route show default 2>/dev/null | awk '{print $3; exit}')
  if [ -n "$iface" ]; then
    if [ -d "/sys/class/net/$iface/wireless" ]; then kind="Wi-Fi"; else kind="провод или другое"; fi
    echo "- связь: $kind \`$iface\`"
    echo "- адрес: \`$(ip -4 -br addr show "$iface" 2>/dev/null | awk '{print $3}' | cut -d/ -f1)\` (текущий, $TODAY)"
    echo "- шлюз: \`$gw\`"
  else
    echo "- маршрута по умолчанию нет: устройство вне сети"
  fi
  echo "- имя Wi-Fi: в опись не пишется"
  if getent hosts "$host.local" >/dev/null 2>&1; then
    echo "- mDNS-имя: \`$host.local\` разрешается"
  else
    echo "- mDNS-имя: \`$host.local\` не разрешается (нужны avahi-daemon и nss-mdns)"
  fi
  vpn=$(ip -br link 2>/dev/null | awk '$1 ~ /^(wg|tun|tailscale|zt)/ {print $1}' | paste -sd ',' - | sed 's/,/, /g')
  echo "- VPN-интерфейсы: ${vpn:-нет}"

  section "Доступы"
  echo "- sshd: $(systemctl is-active sshd 2>/dev/null || systemctl is-active ssh 2>/dev/null)"
  ports=$(ss -tlnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}' | grep -E '^(22|5900|5901|3389)$' | sort -un | paste -sd ',' - | sed 's/,/, /g')
  echo "- слушают порты входа (22 SSH, 5900 и 5901 VNC, 3389 RDP): ${ports:-ни один}"
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
  echo "- linger (user-службы без входа): $(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)"
  for u in ufw nftables firewalld; do
    [ "$(systemctl is-active "$u" 2>/dev/null)" = active ] && echo "- firewall: служба $u активна"
  done
  nc_add "правила firewall" "ufw status и nft list ruleset требуют root"

  section "Агенты и инструменты"
  for d in "$HOME/.local/bin" "$HOME/.npm-global/bin" "$HOME/.bun/bin" "$HOME/.cargo/bin"; do
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
  for c in git gh node python3 uv docker ffmpeg; do has "$c" && tools="$tools $c"; done
  echo "- ключевые CLI:${tools:- нет}"

  section "Фоновые службы"
  systemctl --user list-units --type=service --state=running --no-legend --plain 2>/dev/null | awk '{printf "- user: %s - запущена\n", $1}'
  systemctl --user list-timers --no-legend --plain 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i ~ /\.timer$/) {printf "- user-таймер: %s\n", $i; break}}'
  failed=$(systemctl list-units --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | paste -sd ',' - | sed 's/,/, /g')
  echo "- упавшие юниты: ${failed:-нет}"

  section "Роли"
  echo "- скрипт роли не снимает: ссылка на отдел-владелец остаётся из текущей описи"

  section "Не проверено"
  printf '%s' "$NOT_CHECKED"
}

# Фильтр: MAC, UUID и строки с идентификаторами и секретами в вывод не попадают.
redact() {
  sed -E 's/([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}/<скрыто>/g; s/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<скрыто>/g' |
    grep -v -i -E 'serial|uuid|udid|bssid|ssid:|machine id|boot id|passw|token|secret|api.?key|private key'
}

snapshot 2>/dev/null | redact
