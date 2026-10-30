#!/usr/bin/env bash
set -uo pipefail

show_help() {
  cat <<'EOF'
gh_issue.sh <подкоманда> [флаги]       каждая подкоманда печатает в stdout ОДНУ строку JSON

  read  <ref>...                                  1 вызов на 20 issues
  create --repo O/R --title T --body-file F --week W --parent <ref> [--status S]
         [--harness H --model M --folder D --session ID --session-url U | --no-origin]
  ensure <ref> --week W [--parent <ref>] [--status S] [--replace-parent]
  comment <ref> --body-file F [--image-url URL]...
  shot  <ref> --image shot.png [--dir shots]  картинка в ветку shots (SHOTS_BRANCH), ссылка по SHA коммита
  now   <ref> (--text T | --text-file F)
  close <ref> --proof-file F [--reason completed|not_planned]
  block <ref-A> --by <ref-B>                      A ждёт B
  board <epic-ref>                                таблица детей в «## Сейчас» эпика

Общие флаги (в любом месте строки): --dry-run (мутации не шлёт, печатает их в stderr), --force, --help.
<ref> = owner/repo#N или ссылка вида <github>/owner/repo/issues/N.
Status: Backlog | Ready | In progress | In review | Done.

Конфиг (Project, поле Status, опции статусов) — JSON, пример: config.example.json рядом со скиллом.
Где ищется: $MANAGER_CONFIG → <папка скилла>/config.json → ${XDG_CONFIG_HOME:-~/.config}/manager/config.json.
Переменные окружения перекрывают конфиг: MANAGER_PROJECT_ID, MANAGER_PROJECT_NUMBER, MANAGER_STATUS_FIELD_ID,
MANAGER_STATUS_OPTIONS (JSON {"Backlog":"id",…}).
Без Project работают read, comment, shot, now, close, block, board; ensure и create ставят метку,
исполнителя и эпика, а место на доске пропускают с предупреждением.
EOF
}

command -v jq >/dev/null || { echo '{"ok":false,"result":"usage","error":"нужен jq"}'; exit 2; }

EMITTED=0
TMP=$(mktemp -d) || { echo '{"ok":false,"result":"error","error":"mktemp не сработал"}'; exit 1; }
on_exit() {
  local rc=$?
  rm -rf "$TMP"
  if [ "$EMITTED" != 1 ]; then
    printf '{"ok":false,"result":"error","error":"скрипт завершился без итога (код %s)"}\n' "$rc"
    [ "$rc" != 0 ] || exit 1
  fi
}
trap on_exit EXIT

CMD=""; CALLS=0; DRY=0; FORCE=0; HELP=0; RATE_REMAINING=null; DRY_REQS=0
ACTIONS='[]'; SKIPPED='[]'; WARNS='[]'; EXTRA='{}'

jpush() { jq -c --arg s "$2" '. + [$s]' <<<"$1"; }
act()  { ACTIONS=$(jpush "$ACTIONS" "$1"); }
skip() { SKIPPED=$(jpush "$SKIPPED" "$1"); }
warn() { WARNS=$(jpush "$WARNS" "$1"); }
extra() { EXTRA=$(jq -c --arg k "$1" --argjson v "$2" '. + {($k): $v}' <<<"$EXTRA"); }
jstr() { jq -cn --arg s "$1" '$s'; }

emit() {
  jq -cn --arg cmd "$CMD" --argjson ok "$1" --arg result "$2" \
    --argjson actions "$ACTIONS" --argjson skipped "$SKIPPED" --argjson warnings "$WARNS" \
    --argjson calls "$CALLS" --argjson rate "$RATE_REMAINING" --argjson dry "$DRY" --argjson extra "$EXTRA" \
    '{ok:$ok, cmd:$cmd, result:$result} + $extra
     + {actions:$actions, skipped:$skipped, warnings:$warnings, api_calls:$calls, rate_remaining:$rate}
     + (if $dry == 1 then {dry_run:true} else {} end)'
  EMITTED=1
}
die()   { extra error "$(jstr "$1")"; emit false error; exit 1; }
usage() { extra error "$(jstr "$1")"; emit false usage; exit 2; }
finish() { if [ "$DRY" = 1 ]; then emit true dry-run; else emit true "${1:-done}"; fi; }
noop()   { skip "$1"; extra message '"ничего не нужно"'; emit true noop; }

need_val()  { case "${2-}" in ""|--*) usage "флаг $1 без значения" ;; esac; }
need_file() { [ -f "$1" ] && [ -r "$1" ] || usage "нет файла: $1"; }

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)
CFG_FILE=""
for c in "${MANAGER_CONFIG:-}" "$SKILL_DIR/config.json" "${XDG_CONFIG_HOME:-$HOME/.config}/manager/config.json"; do
  if [ -n "$c" ] && [ -f "$c" ]; then CFG_FILE="$c"; break; fi
done
CFG='{}'
if [ -n "$CFG_FILE" ]; then
  CFG=$(jq -c . "$CFG_FILE" 2>/dev/null) || usage "конфиг manager не читается как JSON: $CFG_FILE"
fi
cfg() { jq -r "$1 // empty" <<<"$CFG"; }
P_ID="${MANAGER_PROJECT_ID:-$(cfg .project.id)}"
P_NUM="${MANAGER_PROJECT_NUMBER:-$(cfg .project.number)}"
P_STATUS_FIELD="${MANAGER_STATUS_FIELD_ID:-$(cfg .project.status_field_id)}"
STATUS_OPTS="${MANAGER_STATUS_OPTIONS:-$(jq -c '.project.status_options // {}' <<<"$CFG")}"
WEEK_LABEL_COLOR="${MANAGER_WEEK_LABEL_COLOR:-$(cfg .week_label_color)}"; WEEK_LABEL_COLOR="${WEEK_LABEL_COLOR:-0E8A16}"
GH_WEB="${MANAGER_GITHUB_WEB:-https://github.com}"
[[ "$P_NUM" =~ ^[0-9]+$ ]] || P_NUM=-1
case "$P_ID$P_STATUS_FIELD" in *"<"*) P_ID="" ;; esac
HAS_PROJECT=0; [ -n "$P_ID" ] && [ -n "$P_STATUS_FIELD" ] && [ "$P_NUM" != -1 ] && HAS_PROJECT=1
RATE_MIN="${GH_ISSUE_RATE_MIN:-200}"
BATCH=20

STATUSES=(Backlog Ready "In progress" "In review" Done)
status_rank() {
  local i=0 s
  for s in "${STATUSES[@]}"; do [ "$s" = "$1" ] && { echo "$i"; return; }; i=$((i+1)); done
  echo -1
}
status_opt() {
  [ "$(status_rank "$1")" -ge 0 ] || return 0
  jq -r --arg s "$1" '.[$s] // empty' <<<"$STATUS_OPTS" 2>/dev/null
}
check_status() {
  [ "$(status_rank "$1")" -ge 0 ] || usage "Status: Backlog | Ready | In progress | In review | Done"
  [ "$HAS_PROJECT" != 1 ] || [ -n "$(status_opt "$1")" ] \
    || usage "нет id опции «$1» в project.status_options конфига: gh project field-list N --owner OWNER --format json"
}

check_parent_cap() {
  [ "$2" -lt 100 ] || die "у родителя $1 уже $2 sub-issues (лимит 100, закрытые считаются): references/parent-epic.md § «Полный эпик»"
  [ "$2" -lt 90 ] || warn "у родителя $1 $2 sub-issues из 100: пора ревью по § «Полный эпик» в references/parent-epic.md"
}

trim_json() { jq -Rs 'sub("^\\s+";"") | sub("\\s+$";"")'; }
has_comment() {
  jq -e --argjson b "$(trim_json <<<"$2")" \
    '[.comments.nodes[].body | sub("^\\s+";"") | sub("\\s+$";"")] | index($b) != null' >/dev/null <<<"$1"
}

gqlstr() { jq -rn --arg s "$1" '$s|@json'; }

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

parse_ref() {
  local s="$1"
  s="${s#"$GH_WEB"/}"; s="${s/\/issues\//#}"
  [[ "$s" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$ ]] || return 1
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
}
check_ref() { parse_ref "$1" >/dev/null || usage "плохая ссылка на issue: '$1' (нужно owner/repo#N)"; }
norm_ref() { local o r n; read -r o r n <<<"$(parse_ref "$1")"; echo "$o/$r#$n"; }
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
  parent_on_project: (if .parent then ([.parent.projectItems.nodes[] | select(.project.number==$pnum)] | length > 0) else null end),
  sub_issues: "\(.subIssuesSummary.completed)/\(.subIssuesSummary.total)",
  blocked_by: .issueDependenciesSummary.blockedBy,
  project: ([.projectItems.nodes[] | select(.project.number==$pnum) | {item: .id, status: (.status.name // null)}] | first),
  other_projects: [.projectItems.nodes[] | select(.project.number!=$pnum) | "#\(.project.number):\(.status.name // "пусто")"],
  last_comment: (.comments.nodes | last | if . == null then null else
    {author: (.author.login // "ghost"), at: .createdAt, text: (.body | gsub("\\s+";" ") | .[0:160])} end)
};'

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

replace_now() {
  jq -j --arg t "$2" '
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
body_of() { jq -j '.body // ""' <<<"$1"; printf x; }

read_one() {
  local o r n; read -r o r n <<<"$(parse_ref "$1")"
  gql "$QHEAD t: $(repo_alias "$o" "$r") { issue(number:$n) { ...F } } } $FRAG" \
      "$(jq -cn --argjson nc "$2" --argjson b "$3" '{nc:$nc, withBody:$b}')"
  T=$(jq -c '.data.t.issue // null' <<<"$RESP")
  [ "$T" != null ] || die "issue $o/$r#$n не найден: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
  extra ref "$(jstr "$o/$r#$n")"
}

cmd_read() {
  [ $# -gt 0 ] || usage "read: нужен хотя бы один owner/repo#N"
  local a; for a in "$@"; do case "$a" in -*) usage "read: неизвестный флаг $a" ;; esac; check_ref "$a"; done
  local all='[]' errs='[]' refs=("$@") i start q chunk o r n
  start=0
  while [ "$start" -lt "${#refs[@]}" ]; do
    q="$QHEAD"; chunk=()
    for ((i=start; i<start+BATCH && i<${#refs[@]}; i++)); do
      read -r o r n <<<"$(parse_ref "${refs[$i]}")"; chunk+=("$o/$r#$n")
      q+=" i$i: $(repo_alias "$o" "$r") { issue(number:$n) { ...F } }"
    done
    q+=" } $FRAG"
    gql "$q" '{"nc":1,"withBody":false}'
    [ "$(jq -r '.data // empty | type' <<<"$RESP")" = object ] \
      || die "read: пустой ответ: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
    for ((i=start; i<start+BATCH && i<${#refs[@]}; i++)); do
      if jq -e --arg a "i$i" '.data[$a].issue != null' >/dev/null <<<"$RESP"; then
        all=$(jq -c --arg a "i$i" --argjson acc "$all" --argjson pnum "$P_NUM" "$SUMM"' $acc + [.data[$a].issue | summ]' <<<"$RESP")
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

ensure_core() {
  local ref="$1" week="$2" pref="$3" status="$4" replace="$5"
  local q T issue_id repo_id state lbl_id viewer_id has_week n_assignees cur_parent item cur_status
  local pid="" ptotal=0 pstate="" m1="" m2="" need_lbl2=0 need_st2=0 opt o r n tref
  read -r o r n <<<"$(parse_ref "$ref")"; tref="$o/$r#$n"
  q="$QHEAD viewer { id login }
    t: $(repo_alias "$o" "$r") { issue(number:$n) { ...F } lbl: label(name:$(gqlstr "$week")) { id } }"
  if [ -n "$pref" ]; then
    read -r o r n <<<"$(parse_ref "$pref")"; pref="$o/$r#$n"
    [ "$pref" != "$tref" ] || usage "issue не может быть родителем самому себе"
    q+=" p: $(repo_alias "$o" "$r") { issue(number:$n) { id state subIssuesSummary { total } } }"
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
  item=$(jq -r --argjson pnum "$P_NUM" '[.projectItems.nodes[] | select(.project.number==$pnum)][0].id // empty' <<<"$T")
  cur_status=$(jq -r --argjson pnum "$P_NUM" '[.projectItems.nodes[] | select(.project.number==$pnum)][0].status.name // empty' <<<"$T")
  extra ref "$(jstr "$tref")"
  [ "$state" = OPEN ] || warn "issue закрыт: статус доски не трогаю"

  if [ "$has_week" = true ]; then skip "label $week уже есть"
  elif [ -n "$lbl_id" ]; then
    m1+=" l: addLabelsToLabelable(input:{labelableId:$(gqlstr "$issue_id"), labelIds:[$(gqlstr "$lbl_id")]}) { clientMutationId }"
    act "label $week"
  else
    m1+=" cl: createLabel(input:{repositoryId:$(gqlstr "$repo_id"), name:$(gqlstr "$week"), color:\"$WEEK_LABEL_COLOR\"}) { label { id } }"
    need_lbl2=1; act "создана метка $week в репо + label $week"
  fi
  if [ "$n_assignees" -gt 0 ]; then skip "assignee уже есть"
  else
    m1+=" a: addAssigneesToAssignable(input:{assignableId:$(gqlstr "$issue_id"), assigneeIds:[$(gqlstr "$viewer_id")]}) { clientMutationId }"
    act "assignee @me"
  fi
  if [ -n "$pref" ]; then
    pid=$(jq -r '.data.p.issue.id // empty' <<<"$RESP")
    [ -n "$pid" ] || die "родитель $pref не найден"
    ptotal=$(jq -r '.data.p.issue.subIssuesSummary.total' <<<"$RESP"); pstate=$(jq -r '.data.p.issue.state' <<<"$RESP")
    if [ "$cur_parent" = "$pref" ]; then skip "parent $pref уже стоит"
    elif [ -n "$cur_parent" ] && [ "$replace" != 1 ]; then
      warn "parent уже другой: $cur_parent; оставил его. Сменить: --replace-parent"
    else
      check_parent_cap "$pref" "$ptotal"
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
  if [ "$HAS_PROJECT" != 1 ]; then
    warn "Project не настроен (config.example.json): место на доске и Status пропущены"
  elif [ -n "$item" ]; then skip "на доске #$P_NUM уже есть"
  else
    m1+=" pa: addProjectV2ItemById(input:{projectId:\"$P_ID\", contentId:$(gqlstr "$issue_id")}) { item { id } }"
    act "добавлен в Project #$P_NUM"
  fi
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
  if [ "$HAS_PROJECT" = 1 ] && [ -z "$pref" ] && [ -n "$cur_parent" ] \
     && [ "$(jq -r --argjson pnum "$P_NUM" '[.parent.projectItems.nodes[] | select(.project.number==$pnum)] | length' <<<"$T")" = 0 ]; then
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
    --week) need_val "$@"; week="$2"; shift 2 ;; --parent) need_val "$@"; parent="$2"; shift 2 ;;
    --status) need_val "$@"; status="$2"; shift 2 ;; --replace-parent) replace=1; shift ;;
    -*) usage "ensure: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$week" ] || usage "ensure <owner/repo#N> --week W44 [--parent owner/repo#N] [--status \"In progress\"]"
  check_ref "$ref"; [ -z "$parent" ] || check_ref "$parent"
  [ -z "$status" ] || check_status "$status"
  ensure_core "$ref" "$week" "$parent" "$status" "$replace"
  if [ "$ACTIONS" = '[]' ]; then extra message '"ничего не нужно"'; emit true noop; else finish; fi
}

cmd_create() {
  local repo="" title="" body_file="" week="" parent="" status="Backlog" q dup body ro rr po pr pn
  local o_harness="" o_model="" o_folder="" o_session="" o_url="" no_origin=0 trailer
  while [ $# -gt 0 ]; do case "$1" in
    --repo) need_val "$@"; repo="$2"; shift 2 ;; --title) need_val "$@"; title="$2"; shift 2 ;;
    --body-file) need_val "$@"; body_file="$2"; shift 2 ;; --week) need_val "$@"; week="$2"; shift 2 ;;
    --parent) need_val "$@"; parent="$2"; shift 2 ;; --status) need_val "$@"; status="$2"; shift 2 ;;
    --harness) need_val "$@"; o_harness="$2"; shift 2 ;; --model) need_val "$@"; o_model="$2"; shift 2 ;;
    --folder) need_val "$@"; o_folder="$2"; shift 2 ;; --session) need_val "$@"; o_session="$2"; shift 2 ;;
    --session-url) need_val "$@"; o_url="$2"; shift 2 ;; --no-origin) no_origin=1; shift ;;
    *) usage "create: неизвестный аргумент $1" ;; esac; done
  [ -n "$repo" ] && [ -n "$title" ] && [ -n "$body_file" ] && [ -n "$week" ] && [ -n "$parent" ] \
    || usage "create --repo owner/repo --title T --body-file F --week W44 --parent owner/repo#N [--status S]"
  [[ "$repo" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]] || usage "--repo: нужно owner/repo"
  ro="${BASH_REMATCH[1]}"; rr="${BASH_REMATCH[2]}"
  check_ref "$parent"; check_status "$status"; need_file "$body_file"
  body=$(cat "$body_file")
  if [ "$no_origin" != 1 ]; then
    trailer=$(origin_trailer "$o_harness" "$o_model" "$o_folder" "$o_session" "$o_url")
    if [ -n "$trailer" ]; then body="$body"$'\n\n'"$trailer"; extra origin "$(jstr "$trailer")"; fi
  fi
  read -r po pr pn <<<"$(parse_ref "$parent")"; parent="$po/$pr#$pn"
  local stitle; stitle=$(tr -d '"' <<<"$title")
  q="query { rateLimit { remaining resetAt cost } viewer { id }
    r: $(repo_alias "$ro" "$rr") { id lbl: label(name:$(gqlstr "$week")) { id } }
    p: $(repo_alias "$po" "$pr") { issue(number:$pn) { id state subIssuesSummary { total }
         subIssues(first:100) { nodes { number title state repository { nameWithOwner } } } } }
    dup: search(type:ISSUE, first:20, query:$(gqlstr "repo:$repo is:issue in:title \"$stitle\"")) {
         nodes { ... on Issue { number title state repository { nameWithOwner } } } }
  }"
  gql "$q"
  [ "$(jq -r '.data.r.id // empty' <<<"$RESP")" != "" ] || die "репо $repo не найдено"
  local pid ptotal repo_id lbl_id viewer_id
  pid=$(jq -r '.data.p.issue.id // empty' <<<"$RESP"); [ -n "$pid" ] || die "родитель $parent не найден"
  ptotal=$(jq -r '.data.p.issue.subIssuesSummary.total' <<<"$RESP")
  repo_id=$(jq -r '.data.r.id' <<<"$RESP"); lbl_id=$(jq -r '.data.r.lbl.id // empty' <<<"$RESP")
  viewer_id=$(jq -r '.data.viewer.id' <<<"$RESP")
  dup=$(jq -r --arg t "$title" --arg repo "$repo" '
    [ (.data.dup.nodes[]?, .data.p.issue.subIssues.nodes[]?)
      | select(.title != null and .title == $t and .state == "OPEN" and .repository.nameWithOwner == $repo)
      | "\(.repository.nameWithOwner)#\(.number)" ] | first // empty' <<<"$RESP")
  if [ -n "$dup" ] && [ "$FORCE" != 1 ]; then
    warn "открытый issue с таким заголовком уже есть: $dup — довожу его через ensure, новый не создаю"
    ensure_core "$dup" "$week" "$parent" "$status" 0
    extra created false
    finish exists; return 0
  fi
  check_parent_cap "$parent" "$ptotal"

  local m1="" labels="" vars pids=""
  if [ -n "$lbl_id" ]; then labels="labelIds:[$(gqlstr "$lbl_id")],"
  else m1+=" cl: createLabel(input:{repositoryId:$(gqlstr "$repo_id"), name:$(gqlstr "$week"), color:\"$WEEK_LABEL_COLOR\"}) { label { id } }"
       act "создана метка $week в репо"; fi
  [ "$HAS_PROJECT" = 1 ] && pids="projectV2Ids:[\"$P_ID\"]"
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
    new_item=$(jq -r --argjson pnum "$P_NUM" '[.data.ci.issue.projectItems.nodes[] | select(.project.number==$pnum)][0].id // empty' <<<"$RESP")
    new_lbl=$(jq -r '.data.cl.label.id // empty' <<<"$RESP")
    extra ref "$(jstr "$repo#$num")"; extra url "$(jq -c '.data.ci.issue.url' <<<"$RESP")"
  fi
  [ -z "$lbl_id" ] && m2+=" l: addLabelsToLabelable(input:{labelableId:$(gqlstr "$new_id"), labelIds:[$(gqlstr "$new_lbl")]}) { clientMutationId }"
  if [ "$HAS_PROJECT" = 1 ]; then
    if [ -z "$new_item" ]; then
      gql "mutation { pa: addProjectV2ItemById(input:{projectId:\"$P_ID\", contentId:$(gqlstr "$new_id")}) { item { id } } }" '' write
      new_item=$(jq -r '.data.pa.item.id // empty' <<<"$RESP")
      [ "$DRY" = 1 ] && new_item="<id карточки>"
    fi
    m2+=" st: updateProjectV2ItemFieldValue(input:{projectId:\"$P_ID\", itemId:$(gqlstr "$new_item"), fieldId:\"$P_STATUS_FIELD\", value:{singleSelectOptionId:\"$(status_opt "$status")\"}}) { projectV2Item { id } }"
    act "Status → $status"
  fi
  [ -z "$m2" ] || gql "mutation { $m2 }" '' write
  [ "$DRY" = 1 ] || extra created true
  finish
}

cmd_shot() {
  local ref="" src="" dir="" o r n ext base name path="" branch sha_remote sha_local commit url
  while [ $# -gt 0 ]; do case "$1" in
    --image) need_val "$@"; src="$2"; shift 2 ;; --dir) need_val "$@"; dir="${2%/}"; shift 2 ;;
    -*) usage "shot: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$src" ] || usage "shot <owner/repo#N> --image shot.png [--dir shots]"
  check_ref "$ref"; need_file "$src"
  ext=$(tr 'A-Z' 'a-z' <<<"${src##*.}")
  case "$ext" in png|jpg|jpeg|gif|webp) ;; *) usage "картинка должна быть png/jpg/gif/webp: $src" ;; esac
  read -r o r n <<<"$(parse_ref "$ref")"
  extra ref "$(jstr "$o/$r#$n")"
  base=$(basename "$src" ".${src##*.}" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)
  name="$(date +%F)-$n-${base:-shot}.$ext"
  path="${dir:-shots}/$name"
  extra path "$(jstr "$path")"

  CALLS=$((CALLS+1))
  branch="${SHOTS_BRANCH:-shots}"
  if ! gh api "repos/$o/$r/git/ref/heads/$branch" >/dev/null 2>&1; then
    local def base_sha
    def=$(gh api "repos/$o/$r" 2>"$TMP/err" | jq -r '.default_branch // empty' 2>/dev/null)
    [ -n "$def" ] || die "не прочитал репо $o/$r: $(head -c 200 "$TMP/err" | tr '\n' ' ')"
    base_sha=$(gh api "repos/$o/$r/git/ref/heads/$def" | jq -r '.object.sha')
    if [ "$DRY" = 1 ]; then act "ветка $branch от $def (не выполнено: dry-run)"
    else gh api -X POST "repos/$o/$r/git/refs" -f ref="refs/heads/$branch" -f sha="$base_sha" >/dev/null || die "не создал ветку $branch в $o/$r"
      act "создана ветка $branch от $def"; fi
  fi
  CALLS=$((CALLS+1))
  sha_remote=$(gh api "repos/$o/$r/contents/$path?ref=$branch" 2>/dev/null | jq -r '.sha // empty' 2>/dev/null)
  sha_local=$(git hash-object "$src")
  if [ "$sha_remote" = "$sha_local" ]; then
    CALLS=$((CALLS+1))
    commit=$(gh api "repos/$o/$r/commits?path=$path&sha=$branch&per_page=1" 2>/dev/null | jq -r '.[0].sha // empty' 2>/dev/null)
    skip "картинка $path уже в $branch"
  elif [ "$DRY" = 1 ]; then
    act "картинка → $path (Contents API в $branch, не выполнено: dry-run)"; finish; return 0
  else
    { printf '{"message":%s,"branch":%s,' "$(gqlstr "docs: screenshot for $o/$r#$n")" "$(gqlstr "$branch")"
      [ -z "$sha_remote" ] || printf '"sha":%s,' "$(gqlstr "$sha_remote")"
      printf '"content":"'; base64 <"$src" | tr -d '\n'; printf '"}'; } >"$TMP/put.json"
    CALLS=$((CALLS+1))
    commit=$(gh api -X PUT "repos/$o/$r/contents/$path" --input "$TMP/put.json" 2>"$TMP/err" | jq -r '.commit.sha // empty' 2>/dev/null)
    [ -n "$commit" ] || die "Contents API PUT $path: $(head -c 200 "$TMP/err" | tr '\n' ' ')"
    act "картинка закоммичена через Contents API: $path в $branch (${commit:0:7})"
  fi
  [ -n "$commit" ] || die "не узнал SHA коммита с картинкой $path"
  url="$GH_WEB/$o/$r/blob/$commit/$path?raw=true"
  extra sha "$(jstr "$commit")"; extra url "$(jstr "$url")"
  extra markdown "$(jstr "![${base:-shot}]($url)")"
  emit true "$( [ "$ACTIONS" = '[]' ] && echo noop || echo done )"
}

cmd_comment() {
  local ref="" f="" body vars id urls=() u alt
  while [ $# -gt 0 ]; do case "$1" in
    --body-file) need_val "$@"; f="$2"; shift 2 ;; --image-url) need_val "$@"; urls+=("$2"); shift 2 ;;
    --image|--image-dir) usage "comment не кладёт картинки в репо: сначала gh_issue.sh shot REF --image F, потом comment --image-url <url из shot>" ;;
    -*) usage "comment: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$f" ] || usage "comment <owner/repo#N> --body-file F [--image-url URL ...]"
  check_ref "$ref"; need_file "$f"
  body=$(cat "$f")
  for u in ${urls[@]+"${urls[@]}"}; do
    alt="${u%%\?*}"; alt="${alt##*/}"; alt="${alt%.*}"
    body="$body"$'\n\n'"![${alt}](${u})"
  done
  read_one "$ref" 30 false
  if [ "$FORCE" != 1 ] && has_comment "$T" "$body"; then noop "такой комментарий уже есть среди последних 30"; return 0; fi
  id=$(jq -r '.id' <<<"$T")
  vars=$(jq -cn --arg id "$id" --arg b "$body" '{id:$id, b:$b}')
  gql 'mutation($id:ID!, $b:String!) { c: addComment(input:{subjectId:$id, body:$b}) { commentEdge { node { url } } } }' "$vars" write
  act "комментарий добавлен"
  [ "$DRY" = 1 ] || extra url "$(jq -c '.data.c.commentEdge.node.url' <<<"$RESP")"
  finish
}

cmd_now() {
  local ref="" text="" tfile="" newbody vars
  while [ $# -gt 0 ]; do case "$1" in
    --text) need_val "$@"; text="$2"; shift 2 ;; --text-file) need_val "$@"; tfile="$2"; shift 2 ;;
    -*) usage "now: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  if [ -n "$tfile" ]; then need_file "$tfile"; text=$(cat "$tfile"); fi
  [ -n "$ref" ] && [ -n "$text" ] || usage "now <owner/repo#N> --text \"...\" (или --text-file F)"
  check_ref "$ref"
  read_one "$ref" 1 true
  local blk; blk=$(jq -r '(.body // "") | (capture("(?<b><!-- board:start -->[\\s\\S]*<!-- board:end -->)").b // "")' <<<"$T")
  [ -z "$blk" ] || text="$text"$'\n\n'"$blk"
  newbody=$(replace_now "$T" "$text"); newbody="${newbody%x}"
  if [ "${newbody}x" = "$(body_of "$T")" ]; then noop "## Сейчас уже такой"; return 0; fi
  vars=$(jq -cn --arg id "$(jq -r '.id' <<<"$T")" --arg b "$newbody" '{id:$id, b:$b}')
  gql 'mutation($id:ID!, $b:String!) { u: updateIssue(input:{id:$id, body:$b}) { issue { id } } }' "$vars" write
  act "## Сейчас обновлён"
  finish
}

cmd_close() {
  local ref="" f="" reason=COMPLETED proof id state has_proof=false m vars open_subs
  while [ $# -gt 0 ]; do case "$1" in
    --proof-file) need_val "$@"; f="$2"; shift 2 ;;
    --reason) need_val "$@"
              case "$2" in completed) reason=COMPLETED ;; not_planned) reason=NOT_PLANNED ;;
              *) usage "--reason: completed | not_planned" ;; esac; shift 2 ;;
    -*) usage "close: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] && [ -n "$f" ] || usage "close <owner/repo#N> --proof-file F [--reason completed|not_planned]"
  check_ref "$ref"; need_file "$f"
  proof=$(cat "$f")
  grep -q "Proof" <<<"$proof" || usage "в файле Proof нет слова «Proof»: шаблон references/templates.md § «Proof при закрытии»"
  read_one "$ref" 30 true
  id=$(jq -r '.id' <<<"$T"); state=$(jq -r '.state' <<<"$T")
  ! has_comment "$T" "$proof" || has_proof=true
  open_subs=$(jq -r '.subIssuesSummary.total - .subIssuesSummary.completed' <<<"$T")
  if [ "$state" = OPEN ] && [ "$open_subs" -gt 0 ] && [ "$FORCE" != 1 ]; then
    die "открытых sub-issues: $open_subs. Закрой их или вынеси; закрыть всё равно: --force"
  fi
  if jq -e '(.body // "") | test("(?m)^##\\s+Открыто")' >/dev/null <<<"$T"; then
    warn "в теле есть секция «Открыто»: по инварианту 8 её переносят в отдельный issue до закрытия"
  fi
  if [ "$state" != OPEN ] && [ "$has_proof" = true ]; then noop "issue уже закрыт, Proof в таймлайне есть"; return 0; fi
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
  if [ "$DRY" = 1 ]; then finish; return 0; fi
  read_one "$ref" 5 false
  [ "$(jq -r '.state' <<<"$T")" = CLOSED ] || die "после closeIssue issue не закрыт"
  has_comment "$T" "$proof" || die "Proof не найден в последних комментариях после закрытия"
  act "проверено: CLOSED, Proof в таймлайне"
  emit true done
}

cmd_board() {
  local ref="" q E block lead newbody vars o r n
  while [ $# -gt 0 ]; do case "$1" in
    -*) usage "board: неизвестный флаг $1" ;; *) ref="$1"; shift ;; esac; done
  [ -n "$ref" ] || usage "board <owner/repo#epic>"
  check_ref "$ref"
  [ -f "$SCRIPT_DIR/board.jq" ] || usage "нет $SCRIPT_DIR/board.jq рядом со скриптом"
  read -r o r n <<<"$(parse_ref "$ref")"
  q="query { rateLimit { remaining resetAt cost }
    t: $(repo_alias "$o" "$r") { issue(number:$n) { id body repository { nameWithOwner }
      subIssuesSummary { total completed }
      subIssues(first:100) { nodes { number title state repository { nameWithOwner } body
        issueDependenciesSummary { blocking }
        blockedBy(first:5) { nodes { number state repository { nameWithOwner } } }
        projectItems(first:10) { nodes { project { number }
          status: fieldValueByName(name:\"Status\") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
        comments(last:15) { nodes { body } } } } } } }"
  gql "$q"
  E=$(jq -c '.data.t.issue // null' <<<"$RESP")
  [ "$E" != null ] || die "эпик $o/$r#$n не найден: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
  extra ref "$(jstr "$o/$r#$n")"
  [ "$(jq -r '.subIssuesSummary.total' <<<"$E")" -gt 0 ] || die "у $o/$r#$n нет sub-issues: это не эпик"
  block=$(jq -r --argjson pnum "$P_NUM" -f "$SCRIPT_DIR/board.jq" <<<"$E")
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
  if [ "${newbody}x" = "$(body_of "$E")" ]; then noop "таблица эпика уже актуальна"; return 0; fi
  [ "$DRY" != 1 ] || { printf '%s\n' "$block" >&2; }
  vars=$(jq -cn --arg id "$(jq -r '.id' <<<"$E")" --arg b "$newbody" '{id:$id, b:$b}')
  gql 'mutation($id:ID!, $b:String!) { u: updateIssue(input:{id:$id, body:$b}) { issue { id } } }' "$vars" write
  act "## Сейчас эпика пересобран"
  finish
}

cmd_block() {
  local a="" b="" q aid bid ao ar an bo br bn
  while [ $# -gt 0 ]; do case "$1" in
    --by) need_val "$@"; b="$2"; shift 2 ;;
    -*) usage "block: неизвестный флаг $1" ;; *) a="$1"; shift ;; esac; done
  [ -n "$a" ] && [ -n "$b" ] || usage "block <owner/repo#A> --by <owner/repo#B>  (A ждёт B)"
  check_ref "$a"; check_ref "$b"
  read -r ao ar an <<<"$(parse_ref "$a")"; a="$ao/$ar#$an"
  read -r bo br bn <<<"$(parse_ref "$b")"; b="$bo/$br#$bn"
  [ "$a" != "$b" ] || usage "issue не может ждать сам себя"
  q="query { rateLimit { remaining resetAt }
    a: $(repo_alias "$ao" "$ar") { issue(number:$an) { id
       blockedBy(first:100) { nodes { number repository { nameWithOwner } } } } }
    b: $(repo_alias "$bo" "$br") { issue(number:$bn) { id } } }"
  gql "$q"
  aid=$(jq -r '.data.a.issue.id // empty' <<<"$RESP"); bid=$(jq -r '.data.b.issue.id // empty' <<<"$RESP")
  if [ -z "$aid" ] || [ -z "$bid" ]; then
    if jq -e '[.errors[]?.message | test("blockedBy")] | any' >/dev/null <<<"$RESP"; then
      die "issue dependencies API недоступен: запиши «Зависит от: $b» строкой в тело $a"
    fi
    die "issue не найден: $(jq -r '[.errors[]?.message]|join("; ")' <<<"$RESP")"
  fi
  extra ref "$(jstr "$a")"
  if jq -e --arg b "$b" '[.data.a.issue.blockedBy.nodes[] | "\(.repository.nameWithOwner)#\(.number)"] | index($b) != null' >/dev/null <<<"$RESP"; then
    noop "$a уже ждёт $b"; return 0
  fi
  local vars; vars=$(jq -cn --arg a "$aid" --arg b "$bid" '{a:$a, b:$b}')
  gql 'mutation($a:ID!, $b:ID!) { d: addBlockedBy(input:{issueId:$a, blockingIssueId:$b}) { issue { number } } }' "$vars" write
  act "$a ждёт $b"
  finish
}

ARGS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;; --force) FORCE=1 ;; -h|--help) HELP=1 ;;
    *) if [ -z "$CMD" ] && [ "${a#-}" = "$a" ]; then CMD="$a"; else ARGS+=("$a"); fi ;;
  esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}
if [ "$HELP" = 1 ] || [ -z "$CMD" ] || [ "$CMD" = help ]; then show_help >&2; CMD=help; emit true help; exit 0; fi
command -v gh >/dev/null || usage "нужен gh"
case "$CMD" in
  read) cmd_read "$@" ;; create) cmd_create "$@" ;; ensure) cmd_ensure "$@" ;;
  comment) cmd_comment "$@" ;; shot) cmd_shot "$@" ;; now) cmd_now "$@" ;; close) cmd_close "$@" ;;
  block) cmd_block "$@" ;; board) cmd_board "$@" ;;
  *) usage "неизвестная подкоманда: $CMD (read|create|ensure|comment|shot|now|close|block|board)" ;;
esac
