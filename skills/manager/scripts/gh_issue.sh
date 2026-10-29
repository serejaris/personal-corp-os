#!/usr/bin/env bash
# gh_issue.sh — единственная точка записи manager в GitHub issues.
# Зависимости: gh (авторизованный), jq. Совместим с bash 3.2 (macOS).
#
# Подкоманды (каждая печатает в stdout ОДНУ строку JSON-итога):
#   read  <ref>...                                  1 вызов на 20 issues
#   create --repo O/R --title T --body-file F --week W --parent <ref> [--status S]
#          [--harness H --model M --folder D --session ID --session-url U | --no-origin]
#   ensure <ref> --week W [--parent <ref>] [--status S] [--replace-parent]
#   comment <ref> --body-file F [--image shot.png]... [--image-dir DIR]
#   now   <ref> (--text T | --text-file F)
#   close <ref> --proof-file F [--reason completed|not_planned]
#   block <ref-A> --by <ref-B>                      A ждёт B
#   board <epic-ref>                                таблица детей в «## Сейчас» эпика
# Общие флаги: --dry-run (мутации не шлёт, печатает их в stderr), --force.
# <ref> = owner/repo#N или ссылка вида <github>/owner/repo/issues/N
#
# Настройка (Project, поле Status, опции статусов) — JSON-конфиг, пример: config.example.json рядом со скиллом.
# Где ищется конфиг: $MANAGER_CONFIG → <папка скилла>/config.json → ${XDG_CONFIG_HOME:-~/.config}/manager/config.json.
# Переменные окружения перекрывают конфиг: MANAGER_PROJECT_ID, MANAGER_PROJECT_NUMBER, MANAGER_STATUS_FIELD_ID,
# MANAGER_STATUS_OPTIONS (JSON {"Backlog":"id",…}), MANAGER_CLONE_ROOTS (папки клонов через «:»).
# Без Project скрипт работает: read, comment, now, close, block, board; ensure и create ставят метку,
# исполнителя и эпика, а место на доске пропускают с предупреждением.
#
# Код выхода: 0 — ok (в том числе "result":"noop"), 1 — ошибка API или инварианта, 2 — ошибка вызова.
# Грабли, зашитые проверками:
#   - gh api graphql при errors игнорирует --jq → ответ разбирается через jq целиком;
#   - rate limit: каждое чтение берёт rateLimit; остаток < GH_ISSUE_RATE_MIN (200) → стоп;
#   - gh project item-list обрезает доску → не используется, Project читается через issue.projectItems;
#   - gh issue close --comment молча ничего не пишет на закрытом → close сам проверяет state и Proof в таймлайне;
#   - у родителя максимум 100 sub-issues (закрытые тоже считаются) → ≥100 стоп, ≥90 предупреждение.
set -uo pipefail

command -v jq >/dev/null || { echo '{"ok":false,"result":"usage","error":"нужен jq"}'; exit 2; }

# --- конфиг: Project, поле Status, опции статусов (config.example.json) ---
SKILL_DIR=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
CFG_FILE=""
for c in "${MANAGER_CONFIG:-}" "$SKILL_DIR/config.json" "${XDG_CONFIG_HOME:-$HOME/.config}/manager/config.json"; do
  if [ -n "$c" ] && [ -f "$c" ]; then CFG_FILE="$c"; break; fi
done
CFG='{}'
if [ -n "$CFG_FILE" ]; then
  CFG=$(jq -c . "$CFG_FILE" 2>/dev/null) \
    || { echo '{"ok":false,"result":"usage","error":"конфиг manager не читается как JSON"}'; exit 2; }
fi
cfg() { jq -r "$1 // empty" <<<"$CFG"; }
P_ID="${MANAGER_PROJECT_ID:-$(cfg .project.id)}"
P_NUM="${MANAGER_PROJECT_NUMBER:-$(cfg .project.number)}"
P_STATUS_FIELD="${MANAGER_STATUS_FIELD_ID:-$(cfg .project.status_field_id)}"
STATUS_OPTS="${MANAGER_STATUS_OPTIONS:-$(jq -c '.project.status_options // {}' <<<"$CFG")}"
CLONE_ROOTS="${MANAGER_CLONE_ROOTS:-$(jq -r '(.clone_roots // []) | join(":")' <<<"$CFG")}"
WEEK_LABEL_COLOR="${MANAGER_WEEK_LABEL_COLOR:-$(cfg .week_label_color)}"; WEEK_LABEL_COLOR="${WEEK_LABEL_COLOR:-0E8A16}"
GH_WEB="${MANAGER_GITHUB_WEB:-https://github.com}"
[[ "$P_NUM" =~ ^[0-9]+$ ]] || P_NUM=-1   # номер Project нужен для фильтра карточек; -1 = доски нет
case "$P_ID$P_STATUS_FIELD" in *"<"*) P_ID="" ;; esac   # заглушки из config.example.json = доска не настроена
HAS_PROJECT=0; [ -n "$P_ID" ] && [ -n "$P_STATUS_FIELD" ] && [ "$P_NUM" != -1 ] && HAS_PROJECT=1
RATE_MIN="${GH_ISSUE_RATE_MIN:-200}"
BATCH=20

status_opt() {
  case "$1" in Backlog|Ready|"In progress"|"In review"|Done) ;; *) echo ""; return ;; esac
  jq -r --arg s "$1" '.[$s] // empty' <<<"$STATUS_OPTS" 2>/dev/null
}
status_known() { case "$1" in Backlog|Ready|"In progress"|"In review"|Done) return 0 ;; *) return 1 ;; esac; }
# check_status <S>: имя из пяти колонок; при настроенной доске у него должен быть id опции в конфиге
check_status() {
  status_known "$1" || usage "Status: Backlog | Ready | In progress | In review | Done"
  [ "$HAS_PROJECT" != 1 ] || [ -n "$(status_opt "$1")" ] \
    || usage "нет id опции «$1» в project.status_options конфига: gh project field-list N --owner OWNER --format json"
}
status_rank() {
  case "$1" in
    Backlog) echo 0 ;; Ready) echo 1 ;; "In progress") echo 2 ;; "In review") echo 3 ;; Done) echo 4 ;; *) echo -1 ;;
  esac
}

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
CMD="${1:-}"; [ $# -gt 0 ] && shift
CALLS=0; DRY=0; FORCE=0; RATE_REMAINING=null; DRY_REQS=0
ACTIONS='[]'; SKIPPED='[]'; WARNS='[]'; EXTRA='{}'

jpush() { jq -c --arg s "$2" '. + [$s]' <<<"$1"; }
act()  { ACTIONS=$(jpush "$ACTIONS" "$1"); }
skip() { SKIPPED=$(jpush "$SKIPPED" "$1"); }
warn() { WARNS=$(jpush "$WARNS" "$1"); }
extra() { EXTRA=$(jq -c --arg k "$1" --argjson v "$2" '. + {($k): $v}' <<<"$EXTRA"); }

emit() { # $1 = ok(true|false)  $2 = result
  jq -cn --arg cmd "$CMD" --argjson ok "$1" --arg result "$2" \
    --argjson actions "$ACTIONS" --argjson skipped "$SKIPPED" --argjson warnings "$WARNS" \
    --argjson calls "$CALLS" --argjson rate "$RATE_REMAINING" --argjson dry "$DRY" --argjson extra "$EXTRA" \
    '{ok:$ok, cmd:$cmd, result:$result} + $extra
     + {actions:$actions, skipped:$skipped, warnings:$warnings, api_calls:$calls, rate_remaining:$rate}
     + (if $dry == 1 then {dry_run:true} else {} end)'
}
die()   { extra error "$(jq -cn --arg m "$1" '$m')"; emit false error; exit 1; }
usage() { extra error "$(jq -cn --arg m "$1" '$m')"; emit false usage; exit 2; }

gqlstr() { jq -rn --arg s "$1" '$s|@json'; }   # безопасный строковый литерал GraphQL

# gql <query> [vars-json] [read|write] → глобальная RESP
gql() {
  local q="$1" v="${2:-}" kind="${3:-read}" payload msg rem
  [ -n "$v" ] || v='{}'
  payload=$(jq -cn --arg q "$q" --argjson v "$v" '{query:$q, variables:$v}')
  if [ "$kind" = write ] && [ "$DRY" = 1 ]; then
    DRY_REQS=$((DRY_REQS+1))
    { echo "# --dry-run: мутация $DRY_REQS (не отправлена)"; jq -r '.query' <<<"$payload";
      jq -c '.variables' <<<"$payload"; } >&2
    RESP='{"data":null,"dry":true}'; return 0
  fi
  CALLS=$((CALLS+1))
  gh api graphql --input - <<<"$payload" >"$TMP/out" 2>"$TMP/err"
  RESP=$(cat "$TMP/out")
  if ! jq -e 'type=="object"' >/dev/null 2>&1 <<<"$RESP"; then
    die "gh api graphql: $(head -c 300 "$TMP/err" | tr '\n' ' ')"
  fi
  if jq -e '[.errors[]? | select(.type=="RATE_LIMITED")] | length > 0' >/dev/null <<<"$RESP" \
     || grep -qi "rate limit" "$TMP/err"; then
    die "rate limit GitHub: стоп, Project lane pending: rate limit"
  fi
  rem=$(jq -r '.data.rateLimit.remaining // empty' <<<"$RESP" 2>/dev/null)
  if [ -n "$rem" ]; then
    RATE_REMAINING=$rem
    if [ "$rem" -lt "$RATE_MIN" ]; then
      die "rate limit: осталось $rem очков (порог $RATE_MIN), сброс $(jq -r '.data.rateLimit.resetAt' <<<"$RESP")"
    fi
  fi
  if [ "$kind" = write ] && jq -e '(.errors // []) | length > 0' >/dev/null <<<"$RESP"; then
    msg=$(jq -r '[.errors[].message] | join("; ")' <<<"$RESP")
    die "мутация отклонена: $msg"
  fi
  return 0
}

# parse_ref <ref> → R_OWNER R_REPO R_NUM R_REF
parse_ref() {
  local s="$1"
  s="${s#"$GH_WEB"/}"; s="${s/\/issues\//#}"
  if [[ "$s" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$ ]]; then
    R_OWNER="${BASH_REMATCH[1]}"; R_REPO="${BASH_REMATCH[2]}"; R_NUM="${BASH_REMATCH[3]}"
    R_REF="$R_OWNER/$R_REPO#$R_NUM"
  else
    usage "плохая ссылка на issue: '$1' (нужно owner/repo#N)"
  fi
}
repo_alias() { echo "repository(owner:$(gqlstr "$1"), name:$(gqlstr "$2"))"; }

FRAG='fragment F on Issue {
  id number title state stateReason url
  body @include(if:$withBody)
  repository { id nameWithOwner }
  labels(first:50) { nodes { name } }
  assignees(first:10) { nodes { login } }
  parent { id number state repository { nameWithOwner }
    projectItems(first:20) { nodes { project { number } } } }
  subIssuesSummary { total completed }
  issueDependenciesSummary { blockedBy blocking }
  projectItems(first:20) { nodes { id project { number }
    status: fieldValueByName(name:"Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
  comments(last:$nc) { totalCount nodes { author { login } createdAt url body } }
}'
QHEAD='query($nc:Int!, $withBody:Boolean!) { rateLimit { remaining resetAt cost }'

SUMM='def summ: {
  ref: "\(.repository.nameWithOwner)#\(.number)", title, state,
  week: [.labels.nodes[].name | select(test("^W[0-9]+$"))],
  labels: [.labels.nodes[].name],
  assignees: [.assignees.nodes[].login],
  parent: (if .parent then "\(.parent.repository.nameWithOwner)#\(.parent.number)" else null end),
  parent_on_project: (if .parent then ([.parent.projectItems.nodes[] | select(.project.number=='"$P_NUM"')] | length > 0) else null end),
  sub_issues: "\(.subIssuesSummary.completed)/\(.subIssuesSummary.total)",
  blocked_by: .issueDependenciesSummary.blockedBy,
  project: ([.projectItems.nodes[] | select(.project.number=='"$P_NUM"') | {item: .id, status: (.status.name // null)}] | first),
  other_projects: [.projectItems.nodes[] | select(.project.number!='"$P_NUM"') | "#\(.project.number):\(.status.name // "пусто")"],
  last_comment: (.comments.nodes | last | if . == null then null else
    {author: (.author.login // "ghost"), at: .createdAt, text: (.body | gsub("\\s+";" ") | .[0:160])} end)
};'

file_text() { [ -f "$1" ] || usage "нет файла: $1"; cat "$1"; }
trim_json() { jq -Rs 'sub("^\\s+";"") | sub("\\s+$";"")'; }

# след агента (кто создал issue: харнес, модель, папка, сессия), его читают уведомления и аудит:
# <!-- origin: harness=…; model=…; folder=…; session=…; url=… --> ; пустые поля не пишутся
origin_clean() { printf '%s' "$1" | tr '\n' ' ' | sed -e 's/-->//g' -e 's/;//g' -e 's/^ *//' -e 's/ *$//'; }
origin_trailer() {
  local h="$1" m="$2" f="$3" s="$4" u="$5" parts="" k v
  if [ -z "$h" ]; then
    if [ "${CLAUDECODE:-}" = 1 ]; then h=claude-code
    elif [ -n "${CODEX_THREAD_ID:-}${CODEX_SESSION_ID:-}" ]; then h=codex
    elif [ -n "${HERMES_SESSION_ID:-}" ]; then h=hermes; fi
  fi
  [ -n "$s" ] || s="${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-${HERMES_SESSION_ID:-}}}}"
  [ -n "$m" ] || m="${ANTHROPIC_MODEL:-}"
  if [ -z "$f" ]; then f=$(git rev-parse --show-toplevel 2>/dev/null) && f=$(basename "$f") || f=""; fi
  for k in harness model folder session url; do
    case $k in harness) v="$h" ;; model) v="$m" ;; folder) v="$f" ;; session) v="$s" ;; url) v="$u" ;; esac
    v=$(origin_clean "$v"); [ -z "$v" ] || parts="${parts:+$parts; }$k=$v"
  done
  [ -z "$parts" ] || printf '<!-- origin: %s -->' "$parts"
}

# replace_now <issue-json с .body> <text> → новое тело в stdout (+ "x" в конце, срезать)
# Секция «## Сейчас» — до следующего заголовка # или ## вне блока кода; нет секции — дописать в конец.
replace_now() {
  jq -r --arg t "$2" '
    (.body // "") as $b | ($t | sub("\\s+$";"")) as $t | ($b | split("\n")) as $L
    | (reduce range(0; $L|length) as $i ({fence:false, s:null, e:null};
        $L[$i] as $l
        | if ($l | test("^\\s*(```|~~~)")) then .fence = (.fence | not)
          elif .fence then .
          elif .s == null and ($l | test("^##\\s+Сейчас\\s*:?\\s*$")) then .s = $i
          elif .s != null and .e == null and ($l | test("^#{1,2}\\s")) then .e = $i
          else . end)) as $x
    | if $x.s == null then ($b | sub("\\s+$";"")) + "\n\n## Сейчас\n\n" + $t + "\n"
      elif $x.e == null then ($L[0:$x.s] + ["## Сейчас", "", $t]) | join("\n") + "\n"
      else ($L[0:$x.s] + ["## Сейчас", "", $t, ""] + $L[$x.e:]) | join("\n") end' <<<"$1"
  printf x
}

# ---------- картинки для comment --image ----------
# remote_slug <git-dir> → owner/repo из origin
remote_slug() {
  git -C "$1" remote get-url origin 2>/dev/null \
    | sed -E -e 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##' -e 's#\.git$##'
}
# place_image <src> <owner> <repo> <num> <image-dir|""> → IMG_URL, IMG_PATH
place_image() {
  local src="$1" o="$2" r="$3" num="$4" idir="$5" ext base name top="" clone="" mode rel d cand path="" branch
  [ -f "$src" ] || usage "нет картинки: $src"
  ext="${src##*.}"; ext=$(tr 'A-Z' 'a-z' <<<"$ext")
  case "$ext" in png|jpg|jpeg|gif|webp) ;; *) usage "картинка должна быть png/jpg/gif/webp: $src" ;; esac
  base=$(basename "$src" ".${src##*.}" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)
  name="$(date +%F)-$num-${base:-shot}.$ext"
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$top" ] && [ "$(remote_slug "$top")" = "$o/$r" ]; then mode=branch; clone="$top"
  else
    mode=api
    # локальный клон ищется в папках clone_roots конфига: <root>/<repo> или <root>/<owner>/<repo>
    local root roots=()
    IFS=: read -r -a roots <<<"$CLONE_ROOTS"
    for root in ${roots[@]+"${roots[@]}"}; do
      root="${root/#\~/$HOME}"
      for d in "$root/$r" "$root/$o/$r"; do
        if [ -d "$d/.git" ] && [ "$(remote_slug "$d")" = "$o/$r" ]; then clone="$d"; break 2; fi
      done
    done
  fi
  # кандидаты папки: --image-dir; иначе docs/shots и docs/status от текущей папки вверх до корня репо
  local cands=()
  if [ -n "$idir" ]; then cands=("${idir%/}")
  else
    rel=""
    if [ "$mode" = branch ]; then rel=$(cd "$PWD" && git rev-parse --show-prefix 2>/dev/null); rel="${rel%/}"; fi
    while :; do
      cands+=("${rel:+$rel/}docs/shots" "${rel:+$rel/}docs/status")
      [ -n "$rel" ] || break
      case "$rel" in */*) rel="${rel%/*}" ;; *) rel="" ;; esac
    done
  fi
  for cand in "${cands[@]}"; do
    if [ -z "$clone" ] || ! git -C "$clone" check-ignore -q --no-index "$cand/$name" 2>/dev/null; then
      path="$cand/$name"; break
    fi
  done
  if [ -z "$path" ] && [ -z "$idir" ] && [ -n "$clone" ]; then
    # все кандидаты под .gitignore → первая уже отслеживаемая папка docs/shots или docs/status
    cand=$(git -C "$clone" ls-files | grep -E '(^|/)docs/(shots|status)/[^/]+$' | sed 's#/[^/]*$##' | sort -u | head -1)
    [ -z "$cand" ] || path="$cand/$name"
  fi
  [ -n "$path" ] || die "все пути для картинки под .gitignore (${cands[*]}): укажи --image-dir"
  [ -n "$clone" ] || warn "нет локального клона $o/$r: путь $path не проверен на .gitignore"
  if [ "$mode" = branch ]; then
    branch=$(git -C "$top" branch --show-current)
    [ -n "$branch" ] || die "detached HEAD в $top: картинку некуда коммитить"
    IMG_PATH="$path"; IMG_URL="$GH_WEB/$o/$r/blob/$branch/$path?raw=true"
    if [ "$DRY" = 1 ]; then act "картинка → $path (коммит в ветку $branch, не выполнен: dry-run)"; return 0; fi
    mkdir -p "$top/$(dirname "$path")"
    if [ -f "$top/$path" ] && cmp -s "$src" "$top/$path" && git -C "$top" ls-files --error-unmatch "$path" >/dev/null 2>&1 \
       && git -C "$top" diff --quiet HEAD -- "$path"; then
      skip "картинка $path уже в ветке $branch"
    else
      cp "$src" "$top/$path"
      git -C "$top" add -- "$path" \
        && git -C "$top" commit -q -m "docs: screenshot for $o/$r#$num" -m "refs $o/$r#$num" -- "$path" >/dev/null \
        || die "git commit картинки $path не прошёл"
      act "картинка закоммичена: $path в $branch"
    fi
    if ! git -C "$top" push -q origin HEAD 2>/dev/null; then
      git -C "$top" pull -q --rebase --autostash origin "$branch" 2>/dev/null && git -C "$top" push -q origin HEAD 2>/dev/null \
        || die "push картинки не прошёл (ветка $branch): ссылка была бы битой"
    fi
    return 0
  fi
  # api: коммит в ветку по умолчанию через Contents API
  CALLS=$((CALLS+1))
  branch=$(gh api "repos/$o/$r" --jq .default_branch 2>/dev/null) || die "не прочитал репо $o/$r"
  IMG_PATH="$path"; IMG_URL="$GH_WEB/$o/$r/blob/$branch/$path?raw=true"
  if [ "$DRY" = 1 ]; then act "картинка → $path (Contents API в $branch, не выполнено: dry-run)"; return 0; fi
  local sha_remote sha_local
  CALLS=$((CALLS+1))
  sha_remote=$(gh api "repos/$o/$r/contents/$path?ref=$branch" --jq .sha 2>/dev/null || true)
  sha_local=$(git hash-object "$src")
  if [ "$sha_remote" = "$sha_local" ]; then skip "картинка $path уже в $branch"; return 0; fi
  { printf '{"message":%s,"branch":%s,' "$(gqlstr "docs: screenshot for $o/$r#$num")" "$(gqlstr "$branch")"
    [ -z "$sha_remote" ] || printf '"sha":%s,' "$(gqlstr "$sha_remote")"
    printf '"content":"'; base64 -i "$src" | tr -d '\n'; printf '"}'; } >"$TMP/put.json"
  CALLS=$((CALLS+1))
  gh api -X PUT "repos/$o/$r/contents/$path" --input "$TMP/put.json" >/dev/null 2>"$TMP/err" \
    || die "Contents API PUT $path: $(head -c 200 "$TMP/err")"
  act "картинка закоммичена через API: $path в $branch"
}

# ---------------- read ----------------
cmd_read() {
  [ $# -gt 0 ] || usage "read: нужен хотя бы один owner/repo#N"
  local all='[]' errs='[]' refs=("$@") i start q chunk
  start=0
  while [ "$start" -lt "${#refs[@]}" ]; do
    q="$QHEAD"; chunk=()
    for ((i=start; i<start+BATCH && i<${#refs[@]}; i++)); do
      parse_ref "${refs[$i]}"; chunk+=("$R_REF")
      q+=" i$i: $(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$R_NUM) { ...F } }"
    done
    q+=" } $FRAG"
    gql "$q" '{"nc":1,"withBody":false}'
    [ "$(jq -r '.data // empty | type' <<<"$RESP")" = object ] \
      || die "read: пустой ответ: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
    for ((i=start; i<start+BATCH && i<${#refs[@]}; i++)); do
      if jq -e --arg a "i$i" '.data[$a].issue != null' >/dev/null <<<"$RESP"; then
        all=$(jq -c --arg a "i$i" --argjson acc "$all" "$SUMM"' $acc + [.data[$a].issue | summ]' <<<"$RESP")
      else
        errs=$(jq -c --arg a "i$i" --arg r "${chunk[$((i-start))]}" --argjson acc "$errs" \
          '$acc + [{ref:$r, error: ([.errors[]? | select(.path[0]==$a) | .message] | first // "не найден")}]' <<<"$RESP")
      fi
    done
    start=$((start+BATCH))
  done
  extra issues "$all"
  [ "$errs" = '[]' ] || extra errors "$errs"
  if [ "$errs" = '[]' ]; then emit true done; else emit false partial; exit 1; fi
}

# ------------- ensure (ядро, используется и create) -------------
# ensure_core <ref> <week> <parent-ref|""> <status|""> <replace-parent 0|1>
ensure_core() {
  local ref="$1" week="$2" pref="$3" status="$4" replace="$5"
  local q T issue_id repo_id state lbl_id viewer_id has_week n_assignees cur_parent item cur_status
  local pid="" ptotal=0 pstate="" m1="" m2="" need_lbl2=0 need_st2=0 opt
  parse_ref "$ref"; local tref="$R_REF"
  q="$QHEAD viewer { id login }
    t: $(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$R_NUM) { ...F } lbl: label(name:$(gqlstr "$week")) { id } }"
  if [ -n "$pref" ]; then
    parse_ref "$pref"; pref="$R_REF"
    [ "$pref" != "$tref" ] || usage "issue не может быть родителем самому себе"
    q+=" p: $(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$R_NUM) { id state subIssuesSummary { total } } }"
  fi
  q+=" } $FRAG"
  gql "$q" '{"nc":1,"withBody":false}'
  T=$(jq -c '.data.t.issue // null' <<<"$RESP")
  [ "$T" != null ] || die "issue $tref не найден: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
  issue_id=$(jq -r '.id' <<<"$T"); repo_id=$(jq -r '.repository.id' <<<"$T"); state=$(jq -r '.state' <<<"$T")
  lbl_id=$(jq -r '.data.t.lbl.id // empty' <<<"$RESP"); viewer_id=$(jq -r '.data.viewer.id' <<<"$RESP")
  has_week=$(jq -r --arg w "$week" '[.labels.nodes[].name] | index($w) != null' <<<"$T")
  n_assignees=$(jq -r '.assignees.nodes | length' <<<"$T")
  cur_parent=$(jq -r 'if .parent then "\(.parent.repository.nameWithOwner)#\(.parent.number)" else "" end' <<<"$T")
  item=$(jq -r '[.projectItems.nodes[] | select(.project.number=='"$P_NUM"')][0].id // empty' <<<"$T")
  cur_status=$(jq -r '[.projectItems.nodes[] | select(.project.number=='"$P_NUM"')][0].status.name // empty' <<<"$T")
  extra ref "$(jq -cn --arg r "$tref" '$r')"
  [ "$state" = OPEN ] || warn "issue закрыт: статус доски не трогаю"

  # 1. W-label
  if [ "$has_week" = true ]; then skip "label $week уже есть"
  elif [ -n "$lbl_id" ]; then
    m1+=" l: addLabelsToLabelable(input:{labelableId:$(gqlstr "$issue_id"), labelIds:[$(gqlstr "$lbl_id")]}) { clientMutationId }"
    act "label $week"
  else
    m1+=" cl: createLabel(input:{repositoryId:$(gqlstr "$repo_id"), name:$(gqlstr "$week"), color:\"$WEEK_LABEL_COLOR\"}) { label { id } }"
    need_lbl2=1; act "создана метка $week в репо + label $week"
  fi
  # 2. assignee: только если исполнителя нет
  if [ "$n_assignees" -gt 0 ]; then skip "assignee уже есть"
  else
    m1+=" a: addAssigneesToAssignable(input:{assignableId:$(gqlstr "$issue_id"), assigneeIds:[$(gqlstr "$viewer_id")]}) { clientMutationId }"
    act "assignee @me"
  fi
  # 3. parent
  if [ -n "$pref" ]; then
    pid=$(jq -r '.data.p.issue.id // empty' <<<"$RESP")
    [ -n "$pid" ] || die "родитель $pref не найден"
    ptotal=$(jq -r '.data.p.issue.subIssuesSummary.total' <<<"$RESP"); pstate=$(jq -r '.data.p.issue.state' <<<"$RESP")
    if [ "$cur_parent" = "$pref" ]; then skip "parent $pref уже стоит"
    elif [ -n "$cur_parent" ] && [ "$replace" != 1 ]; then
      warn "parent уже другой: $cur_parent; оставил его. Сменить: --replace-parent"
    else
      [ "$ptotal" -lt 100 ] || die "у родителя $pref уже $ptotal sub-issues (лимит 100, закрытые считаются): references/parent-epic.md § «Полный эпик»"
      [ "$ptotal" -lt 90 ] || warn "у родителя $pref $ptotal sub-issues из 100: пора ревью по § «Полный эпик» в references/parent-epic.md"
      [ "$pstate" = OPEN ] || warn "родитель $pref закрыт"
      local rp=false; [ "$replace" = 1 ] && rp=true
      m1+=" s: addSubIssue(input:{issueId:$(gqlstr "$pid"), subIssueId:$(gqlstr "$issue_id"), replaceParent:$rp}) { issue { number } }"
      act "parent $pref"
    fi
  elif [ -z "$cur_parent" ]; then
    warn "нет parent: укажи --parent owner/repo#N (инвариант 2)"
  else
    skip "parent $cur_parent уже стоит"
  fi
  # 4. Project #$P_NUM (только если доска настроена в конфиге)
  if [ "$HAS_PROJECT" != 1 ]; then
    warn "Project не настроен (config.example.json): место на доске и Status пропущены"
  elif [ -n "$item" ]; then skip "на доске #$P_NUM уже есть"
  else
    m1+=" pa: addProjectV2ItemById(input:{projectId:\"$P_ID\", contentId:$(gqlstr "$issue_id")}) { item { id } }"
    act "добавлен в Project #$P_NUM"
  fi
  # 5. Status
  if [ "$HAS_PROJECT" != 1 ] || [ "$state" != OPEN ]; then :
  elif [ -n "$status" ]; then
    opt=$(status_opt "$status")
    if [ "$cur_status" = "$status" ]; then skip "Status уже $status"
    elif [ "$(status_rank "$cur_status")" -ge 3 ] && [ "$(status_rank "$status")" -lt "$(status_rank "$cur_status")" ] && [ "$FORCE" != 1 ]; then
      warn "Status $cur_status не понижаю до $status без --force"
    elif [ -n "$item" ]; then
      m1+=" st: updateProjectV2ItemFieldValue(input:{projectId:\"$P_ID\", itemId:$(gqlstr "$item"), fieldId:\"$P_STATUS_FIELD\", value:{singleSelectOptionId:\"$opt\"}}) { projectV2Item { id } }"
      act "Status ${cur_status:-пусто} → $status"
    else
      need_st2=1; act "Status → $status"
    fi
  elif [ -z "$cur_status" ]; then
    warn "Status на доске #$P_NUM пуст: укажи --status"
  fi
  # 6. родитель виден на доске (инвариант 5) — только сообщаем
  if [ "$HAS_PROJECT" = 1 ] && [ -z "$pref" ] && [ -n "$cur_parent" ] && [ "$(jq -r '[.parent.projectItems.nodes[] | select(.project.number=='"$P_NUM"')] | length' <<<"$T")" = 0 ]; then
    warn "родитель $cur_parent не на доске #$P_NUM: прогони ensure для него"
  fi

  if [ -z "$m1" ] && [ "$need_st2" = 0 ]; then return 0; fi
  if [ -n "$m1" ]; then gql "mutation { $m1 }" '' write; fi
  if [ "$need_lbl2" = 1 ] || [ "$need_st2" = 1 ]; then
    local new_lbl new_item
    if [ "$DRY" = 1 ]; then new_lbl="<id метки из мутации 1>"; new_item="<id карточки из мутации 1>"
    else
      new_lbl=$(jq -r '.data.cl.label.id // empty' <<<"$RESP"); new_item=$(jq -r '.data.pa.item.id // empty' <<<"$RESP")
    fi
    [ "$need_lbl2" = 1 ] && m2+=" l: addLabelsToLabelable(input:{labelableId:$(gqlstr "$issue_id"), labelIds:[$(gqlstr "$new_lbl")]}) { clientMutationId }"
    [ "$need_st2" = 1 ] && m2+=" st: updateProjectV2ItemFieldValue(input:{projectId:\"$P_ID\", itemId:$(gqlstr "$new_item"), fieldId:\"$P_STATUS_FIELD\", value:{singleSelectOptionId:\"$(status_opt "$status")\"}}) { projectV2Item { id } }"
    gql "mutation { $m2 }" '' write
  fi
}

cmd_ensure() {
  local ref="" week="" parent="" status="" replace=0
  while [ $# -gt 0 ]; do case "$1" in
    --week) week="$2"; shift 2 ;; --parent) parent="$2"; shift 2 ;; --status) status="$2"; shift 2 ;;
    --replace-parent) replace=1; shift ;; --dry-run) DRY=1; shift ;; --force) FORCE=1; shift ;;
    -*) usage "ensure: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$week" ] || usage "ensure <owner/repo#N> --week W44 [--parent owner/repo#N] [--status \"In progress\"]"
  [ -z "$status" ] || check_status "$status"
  ensure_core "$ref" "$week" "$parent" "$status" "$replace"
  if [ "$ACTIONS" = '[]' ]; then extra message '"ничего не нужно"'; emit true noop
  elif [ "$DRY" = 1 ]; then emit true dry-run
  else emit true done; fi
}

# ---------------- create ----------------
cmd_create() {
  local repo="" title="" body_file="" week="" parent="" status="Backlog" q dup body ro rr pn
  local o_harness="" o_model="" o_folder="" o_session="" o_url="" no_origin=0 trailer
  while [ $# -gt 0 ]; do case "$1" in
    --repo) repo="$2"; shift 2 ;; --title) title="$2"; shift 2 ;; --body-file) body_file="$2"; shift 2 ;;
    --week) week="$2"; shift 2 ;; --parent) parent="$2"; shift 2 ;; --status) status="$2"; shift 2 ;;
    --harness) o_harness="$2"; shift 2 ;; --model) o_model="$2"; shift 2 ;; --folder) o_folder="$2"; shift 2 ;;
    --session) o_session="$2"; shift 2 ;; --session-url) o_url="$2"; shift 2 ;; --no-origin) no_origin=1; shift ;;
    --dry-run) DRY=1; shift ;; --force) FORCE=1; shift ;;
    *) usage "create: неизвестный аргумент $1" ;; esac; done
  [ -n "$repo" ] && [ -n "$title" ] && [ -n "$body_file" ] && [ -n "$week" ] && [ -n "$parent" ] \
    || usage "create --repo owner/repo --title T --body-file F --week W44 --parent owner/repo#N [--status S]"
  [[ "$repo" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]] || usage "--repo: нужно owner/repo"
  ro="${BASH_REMATCH[1]}"; rr="${BASH_REMATCH[2]}"
  check_status "$status"
  body=$(file_text "$body_file") || exit 2
  if [ "$no_origin" != 1 ]; then
    trailer=$(origin_trailer "$o_harness" "$o_model" "$o_folder" "$o_session" "$o_url")
    if [ -n "$trailer" ]; then body="$body"$'\n\n'"$trailer"; extra origin "$(jq -cn --arg t "$trailer" '$t')"; fi
  fi
  parse_ref "$parent"; parent="$R_REF"; pn="$R_NUM"
  local stitle; stitle=$(tr -d '"' <<<"$title")
  q="$QHEAD viewer { id }
    r: $(repo_alias "$ro" "$rr") { id lbl: label(name:$(gqlstr "$week")) { id } }
    p: $(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$pn) { id state subIssuesSummary { total }
         subIssues(first:100) { nodes { number title state repository { nameWithOwner } } } } }
    dup: search(type:ISSUE, first:20, query:$(gqlstr "repo:$repo is:issue in:title \"$stitle\"")) {
         nodes { ... on Issue { number title state repository { nameWithOwner } } } }
  }"
  gql "${q/\$nc:Int!, \$withBody:Boolean!/}" '' read
  [ "$(jq -r '.data.r.id // empty' <<<"$RESP")" != "" ] || die "репо $repo не найдено"
  local pid ptotal repo_id lbl_id viewer_id
  pid=$(jq -r '.data.p.issue.id // empty' <<<"$RESP"); [ -n "$pid" ] || die "родитель $parent не найден"
  ptotal=$(jq -r '.data.p.issue.subIssuesSummary.total' <<<"$RESP")
  repo_id=$(jq -r '.data.r.id' <<<"$RESP"); lbl_id=$(jq -r '.data.r.lbl.id // empty' <<<"$RESP")
  viewer_id=$(jq -r '.data.viewer.id' <<<"$RESP")
  # идемпотентность: открытый issue с тем же заголовком в репо или среди детей родителя → не создаём
  dup=$(jq -r --arg t "$title" --arg repo "$repo" '
    [ (.data.dup.nodes[]?, .data.p.issue.subIssues.nodes[]?)
      | select(.title != null and .title == $t and .state == "OPEN" and .repository.nameWithOwner == $repo)
      | "\(.repository.nameWithOwner)#\(.number)" ] | first // empty' <<<"$RESP")
  if [ -n "$dup" ] && [ "$FORCE" != 1 ]; then
    warn "открытый issue с таким заголовком уже есть: $dup — довожу его через ensure, новый не создаю"
    ensure_core "$dup" "$week" "$parent" "$status" 0
    extra created false
    if [ "$DRY" = 1 ]; then emit true dry-run; else emit true exists; fi
    return 0
  fi
  [ "$ptotal" -lt 100 ] || die "у родителя $parent уже $ptotal sub-issues (лимит 100): references/parent-epic.md § «Полный эпик»"
  [ "$ptotal" -lt 90 ] || warn "у родителя $parent $ptotal sub-issues из 100: пора ревью по § «Полный эпик» в references/parent-epic.md"

  local m1 labels="" vars
  m1=""
  if [ -n "$lbl_id" ]; then labels="labelIds:[$(gqlstr "$lbl_id")],"
  else m1+=" cl: createLabel(input:{repositoryId:$(gqlstr "$repo_id"), name:$(gqlstr "$week"), color:\"$WEEK_LABEL_COLOR\"}) { label { id } }"
       act "создана метка $week в репо"; fi
  local pids=""; [ "$HAS_PROJECT" = 1 ] && pids="projectV2Ids:[\"$P_ID\"]"
  m1+=" ci: createIssue(input:{repositoryId:$(gqlstr "$repo_id"), title:\$title, body:\$body, $labels
        assigneeIds:[$(gqlstr "$viewer_id")], parentIssueId:$(gqlstr "$pid") ${pids:+, $pids}}) {
        issue { id number url projectItems(first:5) { nodes { id project { number } } } } }"
  vars=$(jq -cn --arg title "$title" --arg body "$body" '{title:$title, body:$body}')
  gql "mutation(\$title:String!, \$body:String) { $m1 }" "$vars" write
  if [ "$HAS_PROJECT" = 1 ]; then act "создан issue (label $week, assignee @me, parent $parent, Project #$P_NUM)"
  else act "создан issue (label $week, assignee @me, parent $parent)"
       warn "Project не настроен (config.example.json): место на доске и Status пропущены"; fi
  local new_id new_item new_lbl num m2=""
  if [ "$DRY" = 1 ]; then new_id="<id нового issue>"; new_item="<id карточки>"; new_lbl="<id метки>"; num="?"
  else
    new_id=$(jq -r '.data.ci.issue.id' <<<"$RESP"); num=$(jq -r '.data.ci.issue.number' <<<"$RESP")
    new_item=$(jq -r '[.data.ci.issue.projectItems.nodes[] | select(.project.number=='"$P_NUM"')][0].id // empty' <<<"$RESP")
    new_lbl=$(jq -r '.data.cl.label.id // empty' <<<"$RESP")
    extra ref "$(jq -cn --arg r "$repo#$num" '$r')"; extra url "$(jq -c '.data.ci.issue.url' <<<"$RESP")"
  fi
  [ -z "$lbl_id" ] && m2+=" l: addLabelsToLabelable(input:{labelableId:$(gqlstr "$new_id"), labelIds:[$(gqlstr "$new_lbl")]}) { clientMutationId }"
  if [ "$HAS_PROJECT" = 1 ]; then
    if [ -z "$new_item" ]; then  # карточка не вернулась из createIssue — добавляем отдельно
      gql "mutation { pa: addProjectV2ItemById(input:{projectId:\"$P_ID\", contentId:$(gqlstr "$new_id")}) { item { id } } }" '' write
      new_item=$(jq -r '.data.pa.item.id // empty' <<<"$RESP")
      [ "$DRY" = 1 ] && new_item="<id карточки>"
    fi
    m2+=" st: updateProjectV2ItemFieldValue(input:{projectId:\"$P_ID\", itemId:$(gqlstr "$new_item"), fieldId:\"$P_STATUS_FIELD\", value:{singleSelectOptionId:\"$(status_opt "$status")\"}}) { projectV2Item { id } }"
    act "Status → $status"
  fi
  [ -z "$m2" ] || gql "mutation { $m2 }" '' write
  [ "$DRY" = 1 ] || extra created true
  if [ "$DRY" = 1 ]; then emit true dry-run; else emit true done; fi
}

# read_one <ref> <nc> <withBody> [extra-fields-inside-repository] → RESP, T
read_one() {
  parse_ref "$1"
  gql "$QHEAD t: $(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$R_NUM) { ...F } } } $FRAG" \
      "$(jq -cn --argjson nc "$2" --argjson b "$3" '{nc:$nc, withBody:$b}')"
  T=$(jq -c '.data.t.issue // null' <<<"$RESP")
  [ "$T" != null ] || die "issue $R_REF не найден: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
  extra ref "$(jq -cn --arg r "$R_REF" '$r')"
}

# ---------------- comment ----------------
cmd_comment() {
  local ref="" f="" body vars id idir="" imgs=() img
  while [ $# -gt 0 ]; do case "$1" in
    --body-file) f="$2"; shift 2 ;; --image) imgs+=("$2"); shift 2 ;; --image-dir) idir="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;; --force) FORCE=1; shift ;;
    -*) usage "comment: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$f" ] || usage "comment <owner/repo#N> --body-file F [--image shot.png ...] [--image-dir DIR]"
  body=$(file_text "$f") || exit 2
  read_one "$ref" 30 false
  if [ "${#imgs[@]}" -gt 0 ]; then
    local paths='[]' alt
    parse_ref "$ref"
    for img in "${imgs[@]}"; do
      place_image "$img" "$R_OWNER" "$R_REPO" "$R_NUM" "$idir"
      alt=$(basename "$img"); alt="${alt%.*}"
      body="$body"$'\n\n'"![${alt}](${IMG_URL})"
      paths=$(jq -c --arg p "$IMG_PATH" --arg u "$IMG_URL" '. + [{path:$p, url:$u}]' <<<"$paths")
    done
    extra images "$paths"
  fi
  if [ "$FORCE" != 1 ] && jq -e --argjson b "$(trim_json <<<"$body")" \
       '[.comments.nodes[].body | sub("^\\s+";"") | sub("\\s+$";"")] | index($b) != null' >/dev/null <<<"$T"; then
    skip "такой комментарий уже есть среди последних 30"; extra message '"ничего не нужно"'; emit true noop; return 0
  fi
  id=$(jq -r '.id' <<<"$T")
  vars=$(jq -cn --arg id "$id" --arg b "$body" '{id:$id, b:$b}')
  gql 'mutation($id:ID!, $b:String!) { c: addComment(input:{subjectId:$id, body:$b}) { commentEdge { node { url } } } }' "$vars" write
  act "комментарий добавлен"
  [ "$DRY" = 1 ] || extra url "$(jq -c '.data.c.commentEdge.node.url' <<<"$RESP")"
  if [ "$DRY" = 1 ]; then emit true dry-run; else emit true done; fi
}

# ---------------- now ----------------
cmd_now() {
  local ref="" text="" newbody vars
  while [ $# -gt 0 ]; do case "$1" in
    --text) text="$2"; shift 2 ;; --text-file) text=$(file_text "$2") || exit 2; shift 2 ;;
    --dry-run) DRY=1; shift ;; -*) usage "now: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$text" ] || usage "now <owner/repo#N> --text \"...\" (или --text-file F)"
  read_one "$ref" 1 true
  # таблица эпика (блок board) переживает замену текста
  local blk; blk=$(jq -r '(.body // "") | (capture("(?<b><!-- board:start -->[\\s\\S]*<!-- board:end -->)").b // "")' <<<"$T")
  [ -z "$blk" ] || text="$text"$'\n\n'"$blk"
  newbody=$(replace_now "$T" "$text"); newbody="${newbody%x}"
  if [ "$newbody" = "$(jq -r '.body // ""' <<<"$T")" ]; then
    skip "## Сейчас уже такой"; extra message '"ничего не нужно"'; emit true noop; return 0
  fi
  vars=$(jq -cn --arg id "$(jq -r '.id' <<<"$T")" --arg b "$newbody" '{id:$id, b:$b}')
  gql 'mutation($id:ID!, $b:String!) { u: updateIssue(input:{id:$id, body:$b}) { issue { id } } }' "$vars" write
  act "## Сейчас обновлён"
  if [ "$DRY" = 1 ]; then emit true dry-run; else emit true done; fi
}

# ---------------- close ----------------
cmd_close() {
  local ref="" f="" reason=COMPLETED proof id state has_proof m vars open_subs
  while [ $# -gt 0 ]; do case "$1" in
    --proof-file) f="$2"; shift 2 ;;
    --reason) case "$2" in completed) reason=COMPLETED ;; not_planned) reason=NOT_PLANNED ;;
              *) usage "--reason: completed | not_planned" ;; esac; shift 2 ;;
    --dry-run) DRY=1; shift ;; --force) FORCE=1; shift ;;
    -*) usage "close: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$f" ] || usage "close <owner/repo#N> --proof-file F [--reason completed|not_planned]"
  proof=$(file_text "$f") || exit 2
  grep -q "Proof" <<<"$proof" || usage "в файле Proof нет слова «Proof»: шаблон references/templates.md § «Proof при закрытии»"
  read_one "$ref" 30 true
  id=$(jq -r '.id' <<<"$T"); state=$(jq -r '.state' <<<"$T")
  has_proof=$(jq -r --argjson b "$(trim_json <<<"$proof")" \
    '[.comments.nodes[].body | sub("^\\s+";"") | sub("\\s+$";"")] | index($b) != null' <<<"$T")
  open_subs=$(jq -r '.subIssuesSummary.total - .subIssuesSummary.completed' <<<"$T")
  if [ "$state" = OPEN ] && [ "$open_subs" -gt 0 ] && [ "$FORCE" != 1 ]; then
    die "открытых sub-issues: $open_subs. Закрой их или вынеси; закрыть всё равно: --force"
  fi
  if jq -e '(.body // "") | test("(?m)^##\\s+Открыто")' >/dev/null <<<"$T"; then
    warn "в теле есть секция «Открыто»: по инварианту 8 её переносят в отдельный issue до закрытия"
  fi
  if [ "$state" != OPEN ] && [ "$has_proof" = true ]; then
    skip "issue уже закрыт, Proof в таймлайне есть"; extra message '"ничего не нужно"'; emit true noop; return 0
  fi
  m=""
  if [ "$has_proof" = true ]; then skip "Proof уже в таймлайне"
  else m+=' c: addComment(input:{subjectId:$id, body:$b}) { clientMutationId }'; act "Proof-комментарий"; fi
  if [ "$state" = OPEN ]; then
    m+=" x: closeIssue(input:{issueId:\$id, stateReason:$reason}) { issue { state } }"; act "закрыт ($reason)"
  else
    warn "issue был закрыт без Proof: Proof добавлен постфактум, issue не переоткрывал"
  fi
  vars=$(jq -cn --arg id "$id" --arg b "$proof" '{id:$id, b:$b}')
  gql "mutation(\$id:ID!, \$b:String!) { $m }" "$vars" write
  if [ "$DRY" = 1 ]; then emit true dry-run; return 0; fi
  # проверка: issue закрыт и Proof в таймлайне
  read_one "$ref" 5 false
  if [ "$(jq -r '.state' <<<"$T")" != CLOSED ]; then die "после closeIssue issue не закрыт"; fi
  jq -e --argjson b "$(trim_json <<<"$proof")" \
    '[.comments.nodes[].body | sub("^\\s+";"") | sub("\\s+$";"")] | index($b) != null' >/dev/null <<<"$T" \
    || die "Proof не найден в последних комментариях после закрытия"
  act "проверено: CLOSED, Proof в таймлайне"
  emit true done
}

# ---------------- board ----------------
# Пересобирает в теле эпика блок между <!-- board:start --> и <!-- board:end --> внутри «## Сейчас»:
# таблица открытых детей + «Как выглядит» (последняя картинка из комментариев каждого ребёнка).
# Текст секции до блока (вводный абзац руками) сохраняется; остальное тело не трогается.
BOARD_JQ='
def short($home): if .repository.nameWithOwner == $home then "#\(.number)"
                  else "\(.repository.nameWithOwner | split("/")[1])#\(.number)" end;
def section($b): ($b | split("\n")) as $L
  | ([range(0; $L|length) | select($L[.] | test("^##\\s+Сейчас"))] | first) as $s
  | if $s == null then [] else
      ($L[$s+1:] | (map(test("^#{1,2}\\s")) | index(true)) as $e | if $e == null then . else .[0:$e] end) end;
def now_text: section(.body // "") | join("\n");
def field($k): (now_text | split("\n") | map(select(test("^\\s*[-*]?\\s*\\**\($k)\\**\\s*:"; "i")))
               | first // "" | sub("^\\s*[-*]?\\s*\\**[^:]+:\\**\\s*"; ""));
def branch: ([(now_text, (.comments.nodes[].body))
              | scan("(?:feat|fix|preview|chore|refactor)/[A-Za-z0-9._/-]*[A-Za-z0-9]")] | last // "");
def waits_phrase: [scan("[Жж]д[её]т:?\\s+([^.\\n|]{1,140})") | .[0]] | last // "";
def pstatus: ([.projectItems.nodes[] | select(.project.number=='"$P_NUM"') | .status.name] | first // "");
def icon: if pstatus == "In review" or pstatus == "Done" then "🟢"
          elif (.issueDependenciesSummary.blocking // 0) > 0 then "🔴"
          elif pstatus == "In progress" then "🟡" else "⚪" end;
def rank: {"🟢":0,"🟡":1,"⚪":2,"🔴":3}[icon];
def cell: gsub("\\|"; "\\|") | gsub("\n"; " ") | sub("\\s+$"; "");
def nz: if . == "" then null else . end;
def lastimg: ([.comments.nodes[].body | scan("!\\[[^\\]]*\\]\\([^)]+\\)")] | last);
def refs_of: [scan("(?:[A-Za-z0-9_.-]+)?#[0-9]+")];
# группы «подпись + картинки» из текущей секции эпика: кандидат на сохранение
def old_groups: section(.body // "")
  | reduce .[] as $l ([]; if ($l | test("^\\*\\*.+\\*\\*")) then . + [{h: $l, imgs: []}]
      elif ($l | test("^!\\[")) and length > 0 then .[-1].imgs += [$l] else . end)
  | map(select(.imgs | length > 0));
.repository.nameWithOwner as $home
| [.subIssues.nodes[] | select(.state == "OPEN")] as $open
| [.subIssues.nodes[] | select(.state != "OPEN")] as $closed
| [.subIssues.nodes[] | select(lastimg != null) | {h: "**\(short($home)) \(.title | cell)**", imgs: [lastimg], ref: short($home)}] as $new
| ($new | map(.ref)) as $newrefs
| [old_groups[] | select((.h | refs_of) as $r | ($r | length) == 0 or ([$r[] | select(. as $x | $newrefs | index($x))] | length) == 0)] as $kept
| ($new + $kept) as $imgs
| [ "<!-- board:start -->", "",
    "| | Задача | Где | Ждёт |", "|---|---|---|---|",
    ( $open | sort_by(rank, .number)[]
      | ((field("Где") | nz) // (branch | nz | values | "`\(.)`") // "") as $where
      | ((field("Ждёт") | nz) // (now_text | waits_phrase | nz)
         // ([.blockedBy.nodes[] | select(.state == "OPEN") | short($home)] | if length > 0 then "после " + join(", ") else null end)
         // ((.comments.nodes | last | .body // "") | waits_phrase | nz) // "—") as $wait
      | "| \(icon) | \(short($home)) \(.title | cell) | \($where | cell) | \($wait | cell) |" ),
    "",
    "🟢 сделано, на приёмке · 🟡 в работе · ⚪ ждёт · 🔴 блокирует другую задачу",
    (if ($closed | length) > 0 then "", "Закрыто (\($closed | length)): \([$closed[] | short($home)] | join(", "))" else empty end),
    (if ($imgs | length) > 0 then "", "### Как выглядит", "", ($imgs[] | .h, .imgs[], "") else empty end),
    "<!-- board:end -->" ] | join("\n")'

cmd_board() {
  local ref="" q E block lead newbody vars
  while [ $# -gt 0 ]; do case "$1" in
    --dry-run) DRY=1; shift ;; -*) usage "board: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] || usage "board <owner/repo#epic>"
  parse_ref "$ref"
  q="query { rateLimit { remaining resetAt cost }
    t: $(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$R_NUM) { id body repository { nameWithOwner }
      subIssuesSummary { total completed }
      subIssues(first:100) { nodes { number title state repository { nameWithOwner } body
        issueDependenciesSummary { blocking }
        blockedBy(first:5) { nodes { number state repository { nameWithOwner } } }
        projectItems(first:10) { nodes { project { number }
          status: fieldValueByName(name:\"Status\") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
        comments(last:15) { nodes { body } } } } } } }"
  gql "$q"
  E=$(jq -c '.data.t.issue // null' <<<"$RESP")
  [ "$E" != null ] || die "эпик $R_REF не найден: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
  extra ref "$(jq -cn --arg r "$R_REF" '$r')"
  [ "$(jq -r '.subIssuesSummary.total' <<<"$E")" -gt 0 ] || die "у $R_REF нет sub-issues: это не эпик"
  block=$(jq -r "$BOARD_JQ" <<<"$E")
  # вводный текст секции до блока сохраняем; блока нет — берём текст секции до первой таблицы или ###
  lead=$(jq -r '
    (.body // "") as $b
    | if ($b | test("<!-- board:start -->")) then
        ($b | capture("##\\s+Сейчас[^\n]*\n(?<l>[\\s\\S]*?)<!-- board:start -->").l // "")
      else
        ($b | split("\n")) as $L
        | ([range(0; $L|length) | select($L[.] | test("^##\\s+Сейчас"))] | first) as $s
        | if $s == null then "" else
            ($L[$s+1:] | (map(test("^(#{1,3}\\s|\\|)")) | index(true)) as $e
             | (if $e == null then . else .[0:$e] end) | join("\n")) end
      end | sub("^\\s+";"") | sub("\\s+$";"")' <<<"$E")
  newbody=$(replace_now "$E" "${lead:+$lead$'\n\n'}$block"); newbody="${newbody%x}"
  extra children "$(jq -c '{open: ([.subIssues.nodes[] | select(.state=="OPEN")] | length), closed: ([.subIssues.nodes[] | select(.state!="OPEN")] | length)}' <<<"$E")"
  if [ "$newbody" = "$(jq -r '.body // ""' <<<"$E")" ]; then
    skip "таблица эпика уже актуальна"; extra message '"ничего не нужно"'; emit true noop; return 0
  fi
  [ "$DRY" != 1 ] || { printf '%s\n' "$block" >&2; }
  vars=$(jq -cn --arg id "$(jq -r '.id' <<<"$E")" --arg b "$newbody" '{id:$id, b:$b}')
  gql 'mutation($id:ID!, $b:String!) { u: updateIssue(input:{id:$id, body:$b}) { issue { id } } }' "$vars" write
  act "## Сейчас эпика пересобран"
  if [ "$DRY" = 1 ]; then emit true dry-run; else emit true done; fi
}

# ---------------- block ----------------
cmd_block() {
  local a="" b="" q aid bid
  while [ $# -gt 0 ]; do case "$1" in
    --by) b="$2"; shift 2 ;; --dry-run) DRY=1; shift ;;
    -*) usage "block: неизвестный флаг $1" ;; *) a="$1"; shift ;; esac; done
  [ -n "$a" ] && [ -n "$b" ] || usage "block <owner/repo#A> --by <owner/repo#B>  (A ждёт B)"
  parse_ref "$b"; b="$R_REF"; local bq; bq="$(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$R_NUM) { id } }"
  parse_ref "$a"; a="$R_REF"
  [ "$a" != "$b" ] || usage "issue не может ждать сам себя"
  q="query { rateLimit { remaining resetAt }
    a: $(repo_alias "$R_OWNER" "$R_REPO") { issue(number:$R_NUM) { id
       blockedBy(first:100) { nodes { number repository { nameWithOwner } } } } }
    b: $bq }"
  gql "$q"
  aid=$(jq -r '.data.a.issue.id // empty' <<<"$RESP"); bid=$(jq -r '.data.b.issue.id // empty' <<<"$RESP")
  if [ -z "$aid" ] || [ -z "$bid" ]; then
    if jq -e '[.errors[]?.message | test("blockedBy")] | any' >/dev/null <<<"$RESP"; then
      die "issue dependencies API недоступен: запиши «Зависит от: $b» строкой в тело $a"
    fi
    die "issue не найден: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
  fi
  extra ref "$(jq -cn --arg r "$a" '$r')"
  if jq -e --arg b "$b" '[.data.a.issue.blockedBy.nodes[] | "\(.repository.nameWithOwner)#\(.number)"] | index($b) != null' >/dev/null <<<"$RESP"; then
    skip "$a уже ждёт $b"; extra message '"ничего не нужно"'; emit true noop; return 0
  fi
  local vars; vars=$(jq -cn --arg a "$aid" --arg b "$bid" '{a:$a, b:$b}')
  gql 'mutation($a:ID!, $b:ID!) { d: addBlockedBy(input:{issueId:$a, blockingIssueId:$b}) { issue { number } } }' "$vars" write
  act "$a ждёт $b"
  if [ "$DRY" = 1 ]; then emit true dry-run; else emit true done; fi
}

command -v jq >/dev/null || { echo '{"ok":false,"result":"usage","error":"нужен jq"}'; exit 2; }
command -v gh >/dev/null || { echo '{"ok":false,"result":"usage","error":"нужен gh"}'; exit 2; }
case "$CMD" in
  read) cmd_read "$@" ;; create) cmd_create "$@" ;; ensure) cmd_ensure "$@" ;;
  comment) cmd_comment "$@" ;; now) cmd_now "$@" ;; close) cmd_close "$@" ;; block) cmd_block "$@" ;;
  board) cmd_board "$@" ;;
  ""|-h|--help|help) sed -n '2,31p' "$0" >&2; exit 0 ;;
  *) usage "неизвестная подкоманда: $CMD (read|create|ensure|comment|now|close|block|board)" ;;
esac
