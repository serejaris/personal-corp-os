# board.jq — таблица эпика для gh_issue.sh board.
# Вход: эпик с subIssues (см. запрос в cmd_board). Аргумент: --argjson pnum <номер Project>, -1 = доски нет.
# Выход: блок между <!-- board:start --> и <!-- board:end -->.
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
def pstatus: ([.projectItems.nodes[] | select(.project.number == $pnum) | .status.name] | first // "");
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
    "🟢 сделано, на проверке · 🟡 в работе · ⚪ ждёт · 🔴 блокирует другую задачу",
    (if ($closed | length) > 0 then "", "Закрыто (\($closed | length)): \([$closed[] | short($home)] | join(", "))" else empty end),
    (if ($imgs | length) > 0 then "", "### Как выглядит", "", ($imgs[] | .h, .imgs[], "") else empty end),
    "<!-- board:end -->" ] | join("\n")
