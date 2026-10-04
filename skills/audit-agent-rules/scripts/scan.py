#!/usr/bin/env python3
"""Measure agent rules files and the skill catalog of a folder. Read-only.

Usage: python3 scan.py [FOLDER] [--project-only]
  FOLDER          default: current folder
  --project-only  skip user-level skill folders in the home directory
Prints a Markdown summary for the audit-agent-rules skill.
"""
import os
import re
import subprocess
import sys
from itertools import combinations
from pathlib import Path

LINE_LIMIT = 200          # Anthropic: target under 200 lines per rules file
CODEX_CHAIN_LIMIT = 32768  # Codex project_doc_max_bytes, UTF-8 bytes for the whole chain
CODEX_SKILLS_LIMIT = 8000  # Codex start list: 2% of context or 8000 chars if unknown
CLAUDE_DESC_LIMIT = 1536   # Claude Code truncates description + when_to_use in the listing
LONG_LINE_BYTES = 400
SKIP_DIRS = {".git", "node_modules", "__pycache__", "venv", ".venv", "worktrees"}
SKIP_PAIRS = {(".claude", "skills"), (".agents", "skills"), (".codex", "skills")}


def skipped(parts):
    return bool(set(parts) & SKIP_DIRS) or any(p in SKIP_PAIRS for p in zip(parts, parts[1:]))

HISTORY = re.compile(
    r"\b(19|20)\d\d-\d\d-\d\d\b|\b\d\d\.\d\d\.(19|20)?\d\d\b|(?<![\w/])#\d{2,}\b|"
    r"\b(решил[аи]?|решение от|договорились|созвон|слово (владельца|founder)|раньше было|"
    r"decided|we agreed|used to)\b", re.I)
STEP = re.compile(r"^\s*(\d+[.)]|шаг \d+|step \d+)\s", re.I)
TRIGGER = re.compile(r"\b(use (when|for|on|it|this|after|before)|when |triggers?|когда|триггер|по фраз|"
                     r"применять|использовать|брать|вызывать)", re.I)
STOP = set("""a an and are as at be by for from if in into is it of on or the to use when with
this that your you via any all also only not без для и в во на по с со из к о об от что как это
или не но когда скилл skill skills use""".split())


def run(cmd, cwd):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def git_root(folder):
    out = run(["git", "rev-parse", "--show-toplevel"], folder)
    return Path(out.strip()).resolve() if out else None


def list_files(folder, names):
    """Files with given names under folder; respects .gitignore inside a git repo."""
    out = run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], folder)
    found = []
    if out is not None:
        for rel in out.splitlines():
            p = folder / rel
            if p.name in names and not skipped(Path(rel).parts[:-1]):
                found.append(p)
    else:
        for dirpath, dirnames, filenames in os.walk(folder):
            base = Path(dirpath).relative_to(folder).parts
            dirnames[:] = [d for d in dirnames if not skipped(base + (d,))
                           and (not d.startswith(".") or d == ".claude")]
            found += [Path(dirpath) / f for f in filenames if f in names]
    return sorted(set(found))


def size(p):
    data = p.read_bytes()
    return data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0), len(data)


def rel(p, base):
    home = Path.home().resolve()
    try:
        r = str(p.relative_to(base)) or "."
        return "~/" + r if base == home else r
    except ValueError:
        return str(p).replace(str(home), "~")


def hints(path):
    """Line numbers that look like history, procedure steps, code or overlong lines."""
    h = {"история": [], "шаги": [], "код": [], "длинная строка": []}
    in_code = False
    run_start, run_len = None, 0
    for i, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if line.strip().startswith("```"):
            in_code = not in_code
            h["код"].append(i)
            continue
        if in_code:
            continue
        if HISTORY.search(line):
            h["история"].append(i)
        if len(line.encode()) > LONG_LINE_BYTES:
            h["длинная строка"].append(i)
        if STEP.match(line):
            run_start, run_len = (run_start or i), run_len + 1
        else:
            if run_len >= 3:
                h["шаги"].append(f"{run_start}-{i - 1}")
            run_start, run_len = None, 0
    if run_len >= 3:
        h["шаги"].append(f"{run_start}-…")
    return {k: v for k, v in h.items() if v}


def fmt_lines(items, limit=12):
    items = [str(x) for x in items]
    return ", ".join(items[:limit]) + (f" и ещё {len(items) - limit}" if len(items) > limit else "")


def frontmatter(text):
    m = re.match(r"---\s*\n(.*?)\n---", text, re.S)
    if not m:
        return {}
    fields, key, buf = {}, None, []
    for line in m.group(1).splitlines():
        km = re.match(r"^([A-Za-z_-]+):\s*(.*)$", line)
        if km and not line.startswith((" ", "\t")):
            if key:
                fields[key] = " ".join(buf).strip()
            key, val = km.group(1), km.group(2).strip()
            buf = [] if val in (">", "|", ">-", "|-") else [val]
        elif key:
            buf.append(line.strip())
    if key:
        fields[key] = " ".join(buf).strip()
    return {k: v.strip().strip("'\"") for k, v in fields.items()}


def words(text):
    return {w for w in re.findall(r"[a-zа-яё0-9-]{4,}", text.lower()) if w not in STOP}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    folder = Path(args[0] if args else ".").expanduser().resolve()
    home = Path.home().resolve()
    root = git_root(folder) or folder
    print(f"# Замер правил: {folder.name}\n")
    print(f"Папка: `{rel(folder, home)}`; корень цепочки Codex: `{rel(root, home)}`\n")

    # 1. Rules files
    files = list_files(folder, {"AGENTS.md", "CLAUDE.md", "CLAUDE.local.md"})
    print("## Файлы правил\n")
    print("| Файл | Строк | Байт | Отметка |\n|---|---|---|---|")
    agents = []
    for p in files:
        if p.is_symlink():
            target = os.readlink(p)
            print(f"| `{rel(p, folder)}` | | | симлинк на `{target}` |")
            continue
        lines, nbytes = size(p)
        mark = []
        if lines > LINE_LIMIT:
            mark.append(f"больше {LINE_LIMIT} строк")
        if nbytes > CODEX_CHAIN_LIMIT:
            mark.append("больше 32 KiB")
        if p.name == "AGENTS.md":
            agents.append(p)
        print(f"| `{rel(p, folder)}` | {lines} | {nbytes} | {'; '.join(mark)} |")
    print()

    # 2. Two sets of rules: CLAUDE.md next to or above AGENTS.md, .claude/rules
    print("## CLAUDE.md и .claude/rules\n")
    notes = []
    for p in files:
        if p.name == "AGENTS.md" or p.is_symlink():
            continue
        text = p.read_text(encoding="utf-8", errors="replace").strip()
        sibling = p.parent / "AGENTS.md"
        if text in ("@AGENTS.md", ""):
            continue
        if sibling.exists() and sibling.read_text(encoding="utf-8", errors="replace").strip() == text:
            notes.append(f"- `{rel(p, folder)}` — копия `AGENTS.md`: сейчас совпадает, но разойдётся при первой правке. "
                         "Замени симлинком или удали.")
            continue
        if sibling.exists():
            notes.append(f"- `{rel(p, folder)}` — свой текст рядом с `AGENTS.md`: Claude Code читает его, "
                         "остальные агенты читают `AGENTS.md`.")
        else:
            notes.append(f"- `{rel(p, folder)}` — без `AGENTS.md` рядом: Codex и Cursor этих правил не видят.")
    parent = folder.parent
    while parent != parent.parent and (parent == home or home in parent.parents):
        for name in ("CLAUDE.md", "CLAUDE.local.md"):
            q = parent / name
            if q.exists() and q.stat().st_size > 0:
                notes.append(f"- `{rel(q, home)}` выше папки: Claude Code возьмёт его вместо `AGENTS.md`.")
        parent = parent.parent
    for d in sorted({folder / ".claude" / "rules"} | {f.parent / ".claude" / "rules" for f in files}):
        if d.is_dir():
            n = len(list(d.glob("*.md")))
            notes.append(f"- `{rel(d, folder)}/` ({n} файлов) — читает только Claude Code.")
    print("\n".join(notes) if notes else "Нет.")
    print()

    # 3. Codex chains
    print("## Цепочки Codex (32 768 байт на цепочку)\n")
    above = []
    d = folder
    while d != root and root in d.parents:
        d = d.parent
        if (d / "AGENTS.md").is_file():
            above.insert(0, d / "AGENTS.md")
    worst = []
    for p in agents:
        chain = above + [a for a in agents if a.parent == p.parent or a.parent in p.parents]
        chain.sort(key=lambda a: len(a.parts))
        total = sum(size(a)[1] for a in chain)
        worst.append((total, p, chain))
    worst.sort(key=lambda x: -x[0])
    print("| Папка старта | Файлов в цепочке | Байт | Статус |\n|---|---|---|---|")
    for total, p, chain in worst[:8]:
        status = "обрезается" if total > CODEX_CHAIN_LIMIT else f"запас {CODEX_CHAIN_LIMIT - total}"
        if total > CODEX_CHAIN_LIMIT:
            acc = 0
            for a in chain:
                b = a.read_bytes()
                if acc + len(b) > CODEX_CHAIN_LIMIT:
                    cut_line = b[:CODEX_CHAIN_LIMIT - acc].count(b"\n") + 1
                    status += f": `{rel(a, folder)}` со строки {cut_line}"
                    lost = chain[chain.index(a) + 1:]
                    if lost:
                        status += "; не читается: " + ", ".join(f"`{rel(x, folder)}`" for x in lost)
                    break
                acc += len(b)
        print(f"| `{rel(p.parent, folder)}` | {len(chain)} | {total} | {status} |")
    print()

    # 4. Routes from the root to nested AGENTS.md
    print("## Маршруты к вложенным AGENTS.md\n")
    root_file = folder / "AGENTS.md"
    texts = {a: a.read_text(encoding="utf-8", errors="replace") for a in agents}

    def mentioned(child, parent_file):
        r = child.parent.relative_to(parent_file.parent).as_posix()
        text = texts[parent_file]
        tail = re.escape(r.split("/")[-1] + "/AGENTS.md")
        return f"{r}/AGENTS.md" in text or re.search(r"(?<![\w./-])" + tail, text) is not None

    routed = {root_file} if root_file in texts else set()
    for a in sorted(agents, key=lambda x: len(x.parts)):
        if a == root_file:
            continue
        if any(b in routed and b.parent in a.parents and mentioned(a, b) for b in agents if b != a):
            routed.add(a)
    missing = [a for a in agents if a not in routed]
    if not root_file.exists():
        print("В корне папки нет `AGENTS.md`.")
    for a in missing:
        print(f"- `{rel(a, folder)}`: из корня маршрута нет")
    if not missing:
        print("Все вложенные файлы найдены по маршрутам.")
    print()

    # 5. Line hints
    print("## Подсказки по строкам (проверить глазами)\n")
    for p in agents + [f for f in files if f.name != "AGENTS.md" and not f.is_symlink()]:
        h = hints(p)
        if h:
            print(f"- `{rel(p, folder)}`: " + "; ".join(f"{k}: {fmt_lines(v)}" for k, v in h.items()))
    print()

    # 6. Skill catalog
    print("## Каталог скиллов\n")
    sources = []
    d = folder
    while True:
        sources += [(d / ".agents" / "skills", "Codex"), (d / ".claude" / "skills", "Claude Code")]
        if d == root or root not in d.parents:
            break
        d = d.parent
    if "--project-only" not in sys.argv:
        sources += [(home / ".agents" / "skills", "Codex"), (home / ".codex" / "skills", "Codex"),
                    (home / ".claude" / "skills", "Claude Code")]
    seen, skills, broken, per_src = {}, [], [], {}
    for src, harness in sources:
        if not src.is_dir():
            continue
        per_src[src] = sum(1 for sd in src.iterdir() if (sd / "SKILL.md").is_file())
        for sd in sorted(src.iterdir()):
            sk = sd / "SKILL.md"
            if sd.is_symlink() and not sd.exists():
                broken.append(rel(sd, home))
                continue
            if not sk.is_file():
                continue
            fm = frontmatter(sk.read_text(encoding="utf-8", errors="replace"))
            real = sk.resolve()
            desc = fm.get("description", "")
            entry = seen.get(real)
            if entry:
                entry["harness"].add(harness)
                continue
            entry = {"name": fm.get("name", sd.name), "desc": desc, "when": fm.get("when_to_use", ""),
                     "path": rel(sk, home), "harness": {harness}, "dir": rel(src, home),
                     "manual": fm.get("disable-model-invocation", "").lower() == "true"}
            seen[real] = entry
            skills.append(entry)
    print("| Папка скиллов | Агент | Скиллов |\n|---|---|---|")
    for src, harness in sources:
        if src in per_src:
            print(f"| `{rel(src, home)}` | {harness} | {per_src[src]} |")
    print()
    by_name = {}
    for s in skills:
        by_name.setdefault(s["name"], []).append(s)
    dups = {n: v for n, v in by_name.items() if len(v) > 1}
    if dups:
        print("Один скилл лежит в нескольких копиях (агент видит обе, правка одной не доходит до другой):\n")
        for n, v in sorted(dups.items()):
            print(f"- `{n}`: " + ", ".join(f"`{s['path']}`" for s in v))
        print()
    codex = [s for s in skills if "Codex" in s["harness"] and not s["manual"]]
    claude = [s for s in skills if "Claude Code" in s["harness"] and not s["manual"]]
    codex_total = sum(len(s["name"]) + len(s["desc"]) + len(s["path"]) for s in codex)
    claude_total = sum(len(s["name"]) + len(s["desc"]) + len(s["when"]) for s in claude)
    verdict = ("больше ориентира: Codex сократит описания, а при большом переборе часть скиллов выпадет"
               if codex_total > CODEX_SKILLS_LIMIT else "в пределах")
    print(f"- Codex: скиллов {len(codex)}, имя + описание + путь = {codex_total} символов. "
          f"Бюджет стартового списка 2% окна модели, {CODEX_SKILLS_LIMIT} символов, если окно неизвестно: {verdict}.")
    print(f"- Claude Code: скиллов {len(claude)} из этих папок, имя + описание = {claude_total} символов. "
          "Скиллы плагинов сюда не входят.")
    codex_only = [s for s in codex if "Claude Code" not in s["harness"]]
    if codex_only:
        print(f"- Только в папках Codex (`.agents/skills`, `.codex/skills`): {len(codex_only)}. "
              "Claude Code их не видит; если человек работает в Claude Code, нужна ссылка из `.claude/skills`.")
    if broken:
        print(f"- Битые ссылки на скиллы: {', '.join(f'`{b}`' for b in broken)}")
    print()
    bad = []
    for s in skills:
        issues = []
        if not s["desc"]:
            issues.append("нет описания")
        else:
            if len(s["desc"]) + len(s["when"]) > CLAUDE_DESC_LIMIT:
                issues.append(f"{len(s['desc'])} символов, Claude Code обрежет после {CLAUDE_DESC_LIMIT}")
            if not TRIGGER.search(s["desc"] + " " + s["when"]) and not s["manual"]:
                issues.append("не сказано, когда брать")
        if issues:
            bad.append(f"| `{s['name']}` | `{s['path']}` | {'; '.join(issues)} |")
    print("Описания с проблемами:\n")
    print("| Скилл | Файл | Что не так |\n|---|---|---|\n" + "\n".join(bad) if bad else "Нет.")
    print()
    pairs, seen_pairs = [], set()
    for a, b in combinations([s for s in skills if s["desc"]], 2):
        key = frozenset((a["name"], b["name"]))
        if len(key) < 2 or key in seen_pairs:
            continue
        seen_pairs.add(key)
        wa, wb = words(a["desc"] + " " + a["when"]), words(b["desc"] + " " + b["when"])
        if wa and wb:
            score = len(wa & wb) / len(wa | wb)
            if score >= 0.25:
                pairs.append((score, a["name"], b["name"], sorted(wa & wb)[:8]))
    pairs.sort(reverse=True)
    print("Похожие описания (кандидаты на пересечение, проверить глазами):\n")
    if pairs:
        print("| Скилл A | Скилл B | Сходство | Общие слова |\n|---|---|---|---|")
        for score, a, b, common in pairs[:15]:
            print(f"| `{a}` | `{b}` | {score:.2f} | {', '.join(common)} |")
    else:
        print("Нет.")
    print()

    # 7. Routes that lead nowhere
    print("## Маршруты в никуда (проверить глазами)\n")
    names = {s["name"] for s in skills}
    dead = []
    for a in agents:
        for i, line in enumerate(texts[a].splitlines(), 1):
            for tok in re.findall(r"`([^`\s]+)`", line):
                if re.search(r"[*<>{}$|]|NN|ГГГГ|YYYY|^https?:|^~|^\.\./\.\.", tok):
                    continue
                t = tok.split("#")[0].split(":")[0].rstrip("/")
                if "/" in t:
                    bases = (a.parent, folder, root, root.parent)
                    if not any((base / t).exists() for base in bases):
                        dead.append(f"`{rel(a, folder)}:{i}` путь `{tok}`")
            for sk in re.findall(r"скилл\w*\s+`([\w:-]+)`|skill\s+`([\w:-]+)`", line, re.I):
                sk = sk[0] or sk[1]
                if sk and sk.split(":")[-1] not in names and ":" not in sk:
                    dead.append(f"`{rel(a, folder)}:{i}` скилл `{sk}` не найден в папках скиллов")
    print("\n".join(f"- {d}" for d in dead[:40]) if dead else "Нет.")
    if len(dead) > 40:
        print(f"- и ещё {len(dead) - 40}")
    if dead:
        print("\nПути ищутся от папки файла и от корня; скиллы плагинов сканер не видит.")


if __name__ == "__main__":
    main()
