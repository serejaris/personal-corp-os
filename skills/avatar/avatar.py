#!/usr/bin/env python3
"""Скилл avatar: агент делает себе голову робота из набора деталей и входит в живой класс урока (pc3live.py join).

Только стандартная библиотека Python 3.8+. Запись робота хранится в штабе, в stack/avatars.json (как у скилла
pc-avatar), ключ харнес/семейство модели. Робот не меняется, пока человек не попросит сделать его заново.
Голова: палитра и глаза, их модель выбирает по характеру. Компания модели и лента: по себе, это стикер
с логотипом на теле и лента с именем модели на лбу.

  python3 avatar.py start --harness claude-code --tape "opus 5.5"
      есть запись: печатает её; нет: печатает, из чего выбирать
  python3 avatar.py go --harness claude-code --company anthropic --tape "opus 5.5" --color clay-light --eyes pill
      проверяет выбор, сохраняет робота, кладёт в штаб превью avatar/robot.html и открывает его в браузере (--no-open: не открывать)
      и печатает код робота для pc3live.py join
  python3 avatar.py check <код>     разобрать код: запись или причина отказа
  python3 avatar.py code --harness codex --company openai --color mint --eyes visor --tape gpt-5.5
                                    собрать код без штаба (демо релея)
  python3 avatar.py inventory [--json]   что уйдёт на парту на уроке: только имена из штаба
  python3 avatar.py kit             весь набор деталей

Код робота (передаётся серверу урока в pc3live.py join --code; до 64 знаков A-Z a-z 0-9 _ -), версия 2:
  b H P E K C лента
  b: версия 2; H P E K: номера харнеса, палитры, глаз, компании в наборе (base36); C: контрольный знак;
  лента: 1-12 знаков, a-z 0-9, пробел пишется _, точка D, дефис как есть.
"""
import argparse
import json
import re
import sys
import webbrowser
from datetime import date
from pathlib import Path

# ---8<--- набор: генерирует live/sync.mjs из src/avatar/kit.json, руками не править
BOT = 'pc3_avatar_bot'
HARNESSES = ['claude-code', 'codex', 'cursor', 'antigravity', 'hermes', 'openclaw', 'chatgpt', 'grok']
PALETTES = [('clay-light', 'глина'), ('oat', 'овёс'), ('mist', 'туман'), ('lilac', 'сирень'), ('butter', 'масло'), ('mint', 'мята'), ('brick', 'кирпич'), ('sky', 'небо'), ('plum', 'слива'), ('night', 'ночь')]
EYES = [('pill', 'пилюли', 'два вертикальных бруска, глаза семьи роботов'), ('dot', 'точки', 'две круглые точки'), ('wide', 'щёлки', 'две горизонтальные щёлки, спокойный взгляд'), ('ring', 'кольца', 'два полых кольца, любопытный взгляд'), ('slant', 'прищур', 'бруски с наклоном к переносице, сосредоточенный взгляд'), ('visor', 'визор', 'одна полоса во весь экран')]
COMPANIES = [('anthropic', 'Anthropic', 'claude: opus, sonnet, haiku'), ('openai', 'OpenAI', 'gpt, o3, codex'), ('google', 'Google', 'gemini, gemma'), ('xai', 'xAI', 'grok'), ('deepseek', 'DeepSeek', 'deepseek'), ('zhipu', 'Zhipu (Z.ai)', 'glm'), ('moonshot', 'Moonshot AI', 'kimi'), ('mistral', 'Mistral AI', 'mistral, codestral, devstral'), ('alibaba', 'Alibaba', 'qwen'), ('meta', 'Meta', 'llama'), ('other', 'другая', 'любая другая модель: стикер с первой буквой ленты')]
# ---8<--- конец набора

VERSION = 'b'
MARK = '<!--ROBOT-->'   # место кода робота в robot.html (write_preview)
B36 = '0123456789abcdefghijklmnopqrstuvwxyz'
TAPE_MAX = 12
PAL_IDS = [p[0] for p in PALETTES]
EYE_IDS = [e[0] for e in EYES]
CO_IDS = [c[0] for c in COMPANIES]
_TAPE_RE = re.compile(r'[a-z0-9 .-]{1,%d}' % TAPE_MAX)
_ENC = {' ': '_', '.': 'D'}
_DEC = {'_': ' ', 'D': '.'}

class CodeError(ValueError):
    """Код или запись не проходят правила набора; текст ошибки это причина для человека."""

def norm_tape(tape):
    """Лента: строчные, пробелы схлопнуты. Бросает CodeError, если знаки не те или длина не 1-12."""
    t = ' '.join(str(tape or '').lower().split())
    if not _TAPE_RE.fullmatch(t):
        raise CodeError('лента: 1–12 знаков, латиница, цифры, пробел, точка, дефис')
    return t

def family_of(tape):
    """Семейство модели для ключа записи: первое слово ленты без версии (opus 5.5 даёт opus, gpt-5.5 даёт gpt)."""
    words = str(tape or '').strip().lower().split()
    word = words[0] if words else 'model'
    return re.sub(r'[-_.]?v?\d[\w.]*$', '', word) or 'model'

def _check(body):
    h = 7
    for ch in body:
        h = (h * 31 + ord(ch)) % 1679616
    return B36[h % 36]

def validate(harness, company, color, eyes, tape):
    """Проверка записи по набору. Возвращает нормализованную ленту; иначе CodeError."""
    if harness not in HARNESSES:
        raise CodeError('харнес %s не из набора: %s' % (harness, ', '.join(HARNESSES)))
    for kind, ids, v in (('компания', CO_IDS, company), ('палитра', PAL_IDS, color), ('глаза', EYE_IDS, eyes)):
        if v not in ids:
            raise CodeError('%s %s не из набора: %s' % (kind, v, ', '.join(ids)))
    return norm_tape(tape)

def encode(harness, company, color, eyes, tape):
    """Запись в код прибытия. Бросает CodeError, если деталь не из набора или лента не та."""
    t = validate(harness, company, color, eyes, tape)
    head = VERSION + B36[HARNESSES.index(harness)] + B36[PAL_IDS.index(color)] + B36[EYE_IDS.index(eyes)] + B36[CO_IDS.index(company)]
    body = ''.join(_ENC.get(ch, ch) for ch in t)
    return head + _check(head + body) + body

def decode(code):
    """Код в {'harness', 'key', 'record': {company, head: {color, eyes}, tape}}. Битый код: CodeError."""
    c = str(code or '').strip()
    if not c:
        raise CodeError('нет кода')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', c):
        raise CodeError('код битый: чужие знаки')
    if c[0] != VERSION:
        raise CodeError('код другой версии, обнови скилл avatar')
    if len(c) < 7 or len(c) > 6 + TAPE_MAX:
        raise CodeError('код битый: не та длина')
    digits = []
    for ch in c[1:5]:
        if ch not in B36:
            raise CodeError('код битый')
        digits.append(B36.index(ch))
    hi, pi, ei, ki = digits
    if hi >= len(HARNESSES) or pi >= len(PALETTES) or ei >= len(EYES) or ki >= len(COMPANIES):
        raise CodeError('код битый: номер детали вне набора')
    body = c[6:]
    if _check(c[:5] + body) != c[5]:
        raise CodeError('код битый: не сходится контрольный знак')
    if not re.fullmatch(r'[a-z0-9_D-]+', body):
        raise CodeError('код битый: лента')
    tape = ''.join(_DEC.get(ch, ch) for ch in body)
    harness, company, color, eyes = HARNESSES[hi], CO_IDS[ki], PAL_IDS[pi], EYE_IDS[ei]
    if validate(harness, company, color, eyes, tape) != tape:
        raise CodeError('код битый: лента')
    return {'harness': harness, 'key': '%s/%s' % (harness, family_of(tape)),
            'record': {'company': company, 'head': {'color': color, 'eyes': eyes}, 'tape': tape}}

def link(code):
    return 'https://t.me/%s?start=%s' % (BOT, code)

# ───────── штаб: stack/avatars.json ─────────

def find_hq(arg):
    if arg:
        return Path(arg).expanduser().resolve()
    here = Path(__file__).resolve()
    # скилл лежит в штабе: <штаб>/.agents/skills/avatar/avatar.py (или .claude/skills)
    if len(here.parents) > 3 and here.parents[1].name == 'skills' and here.parents[2].name in ('.agents', '.claude', '.codex'):
        if here.parents[3] != Path.home():  # скилл в домашней папке (общий для всех проектов): штаб это текущая папка
            return here.parents[3]
    return Path.cwd()

def load_avatars(hq):
    f = hq / 'stack' / 'avatars.json'
    if not f.exists():
        return {}
    try:
        data = json.loads(f.read_text(encoding='utf-8'))
    except ValueError:
        sys.exit('stack/avatars.json не читается как JSON: поправь файл и запусти снова')
    return data if isinstance(data, dict) else {}

def save_avatars(hq, data):
    d = hq / 'stack'
    d.mkdir(parents=True, exist_ok=True)
    lines = ['  %s: %s' % (json.dumps(k, ensure_ascii=False), json.dumps(v, ensure_ascii=False)) for k, v in data.items()]
    (d / 'avatars.json').write_text('{\n' + ',\n'.join(lines) + '\n}\n', encoding='utf-8')

def record_line(key, rec):
    h = rec.get('head') or {}
    return '%s: компания %s, палитра %s, глаза %s, лента %s' % (key, rec.get('company', '?'), h.get('color', '?'), h.get('eyes', '?'), rec.get('tape', ''))

def print_kit():
    print('Палитры (--color): ' + ', '.join('%s %s' % (p[0], p[1]) for p in PALETTES))
    print('Глаза (--eyes):')
    for e in EYES:
        print('  %s (%s): %s' % (e[0], e[1], e[2]))
    print('Компания твоей модели (--company), стикер с логотипом на теле:')
    for c in COMPANIES:
        print('  %s: %s, модели %s' % (c[0], c[1], c[2]))

def key_of(harness, tape):
    if harness not in HARNESSES:
        sys.exit('харнес %s не из набора: %s' % (harness, ', '.join(HARNESSES)))
    try:
        t = norm_tape(tape)
    except CodeError as e:
        sys.exit(str(e))
    return '%s/%s' % (harness, family_of(t)), t

def cmd_start(a):
    hq = find_hq(a.hq)
    key, tape = key_of(a.harness, a.tape)
    rec = load_avatars(hq).get(key)
    if isinstance(rec, dict) and isinstance(rec.get('head'), dict) and rec.get('company') in CO_IDS:
        print('Робот уже есть, голова не меняется, пока человек не попросит сделать её заново:')
        print(record_line(key, rec))
        print('Дальше сразу: python3 %s go --harness %s --company %s --tape "%s"' % (sys.argv[0], a.harness, rec['company'], tape))
        return
    print('Робота %s ещё нет. Выбери голову по характеру (палитра и глаза) и компанию своей модели.' % key)
    print_kit()
    print('Дальше: python3 %s go --harness %s --company <компания> --tape "%s" --color <палитра> --eyes <глаза>' % (sys.argv[0], a.harness, tape))

def cmd_go(a):
    hq = find_hq(a.hq)
    key, tape = key_of(a.harness, a.tape)
    data = load_avatars(hq)
    old = data.get(key) if isinstance(data.get(key), dict) else {}
    head = dict(old.get('head') or {})
    head = {k: head[k] for k in ('color', 'eyes') if k in head}
    for k in ('color', 'eyes'):
        if getattr(a, k):
            head[k] = getattr(a, k)
    company = a.company or old.get('company')
    if not company or 'color' not in head or 'eyes' not in head:
        sys.exit('Нужны --company, --color и --eyes: робота %s ещё нет. Варианты: python3 %s kit' % (key, sys.argv[0]))
    try:
        code = encode(a.harness, company, head['color'], head['eyes'], tape)
        back = decode(code)
    except CodeError as e:
        sys.exit('Не собрал код: %s' % e)
    assert back['key'] == key and back['record']['head'] == head
    rec = {'company': company, 'head': head, 'tape': tape, 'made': old.get('made') or date.today().isoformat()}
    changed = rec != old
    data[key] = rec
    save_avatars(hq, data)
    print(record_line(key, rec))
    print('%s: %s' % ('Записано' if changed else 'Без изменений', hq / 'stack' / 'avatars.json'))
    print('Код: ' + code)
    page = write_preview(hq, code)
    if page:
        print('Превью: %s (открывается двойным кликом, сервер и интернет не нужны)' % page)
        if not a.no_open:
            webbrowser.open(page.as_uri())
    else:
        print('Превью нет: рядом со скриптом нет robot.html, поставь скилл папкой по ссылке')
    live = Path(__file__).with_name('pc3live.py')
    print('На урок: python3 %s join "<ссылка входа с экрана урока>" --name "<имя человека>" --code "%s"' % (live, code))


def write_preview(hq, code):
    """Страница-превью робота в штабе: avatar/robot.html, плеер robot.html рядом со скриптом плюс код робота."""
    src = Path(__file__).with_name('robot.html')
    if not src.exists():
        return None
    html = src.read_text(encoding='utf-8')
    if MARK not in html:
        sys.exit('robot.html без метки %s: поставь скилл заново' % MARK)
    page = hq / 'avatar' / 'robot.html'
    page.parent.mkdir(parents=True, exist_ok=True)
    page.write_text(html.replace(MARK, '<script>window.ROBOT = %s;</script>' % json.dumps({'code': code}), 1), encoding='utf-8')
    return page

# ───────── парта на уроке: только имена из штаба ─────────

SKIP = {'avatar', 'node_modules', '__pycache__', 'venv', '.venv'}


def _names(pairs, n):
    out = []
    for x in pairs:
        x = str(x).strip()
        if x and x not in out:
            out.append(x[:40])
    return out[:n]


def collect_inventory(hq):
    """Имена для парты на уроке: файлы и папки верхнего уровня штаба, скиллы, MCP-серверы, отделы. Без путей и содержимого."""
    files = []
    for p in sorted(hq.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower())):
        if p.name.startswith('.') or p.name in SKIP:
            continue
        files.append(p.name + ('/' if p.is_dir() else ''))
    skills = []
    for d in ('.agents/skills', '.claude/skills'):
        root = hq / d
        if root.is_dir():
            skills += [p.name for p in sorted(root.iterdir()) if p.is_dir() and not p.name.startswith('.')]
    mcp = []
    try:
        mcp += list((json.loads((hq / '.mcp.json').read_text(encoding='utf-8')).get('mcpServers') or {}).keys())
    except (OSError, ValueError, AttributeError):
        pass
    try:
        cfg = json.loads((Path.home() / '.claude.json').read_text(encoding='utf-8'))
        mcp += list((cfg.get('mcpServers') or {}).keys())
        mcp += list(((cfg.get('projects') or {}).get(str(hq)) or {}).get('mcpServers', {}).keys())
    except (OSError, ValueError, AttributeError):
        pass
    try:
        mcp += re.findall(r'^\[mcp_servers\.([A-Za-z0-9_-]+)\]', (Path.home() / '.codex' / 'config.toml').read_text(encoding='utf-8'), re.M)
    except OSError:
        pass
    depts = []
    for rules in ('AGENTS.md', 'CLAUDE.md'):
        try:
            text = (hq / rules).read_text(encoding='utf-8')
        except OSError:
            continue
        for m in re.findall(r'\.\./([A-Za-z0-9_.-]+)', text):
            if (hq.parent / m).is_dir():
                depts.append(m)
    return {'files': _names(files, 40), 'skills': _names(skills, 40), 'mcp': _names(mcp, 16), 'depts': _names(depts, 12)}


def cmd_inventory(a):
    inv = collect_inventory(find_hq(a.hq))
    if a.json:
        print(json.dumps(inv, ensure_ascii=False))
        return
    print('На парту на экране урока уйдут только эти имена (без путей и содержимого):')
    for k, label in (('files', 'файлы и папки штаба'), ('skills', 'скиллы'), ('mcp', 'MCP-серверы'), ('depts', 'отделы')):
        print('  %s: %s' % (label, ', '.join(inv[k]) or 'нет'))
    print('JSON для входа: python3 %s inventory --json' % sys.argv[0])


def cmd_check(a):
    try:
        print(json.dumps(decode(a.code), ensure_ascii=False))
    except CodeError as e:
        print('отказ: %s' % e)
        sys.exit(1)

def cmd_code(a):
    try:
        print(encode(a.harness, a.company, a.color, a.eyes, a.tape))
    except CodeError as e:
        print('отказ: %s' % e)
        sys.exit(1)

def main(argv=None):
    p = argparse.ArgumentParser(description='Аватар агента: голова из набора и ссылка прибытия на урок')
    sub = p.add_subparsers(dest='cmd', required=True)
    for name in ('start', 'go'):
        s = sub.add_parser(name)
        s.add_argument('--harness', required=True, help=', '.join(HARNESSES))
        s.add_argument('--tape', required=True, help='имя модели с версией, строчными: "opus 5.5"')
        s.add_argument('--hq', help='папка штаба (по умолчанию штаб, в котором лежит скилл, иначе текущая папка)')
        if name == 'go':
            s.add_argument('--company', help=', '.join(CO_IDS))
            s.add_argument('--color')
            s.add_argument('--eyes')
            s.add_argument('--no-open', action='store_true', help='не открывать превью робота в браузере')
    c = sub.add_parser('check')
    c.add_argument('code')
    e = sub.add_parser('code', help='собрать код без штаба (демо и проверки)')
    for k in ('harness', 'company', 'color', 'eyes', 'tape'):
        e.add_argument('--' + k, required=True)
    sub.add_parser('kit')
    i = sub.add_parser('inventory', help='что уйдёт на парту: имена файлов, скиллов, MCP-серверов и отделов штаба')
    i.add_argument('--hq')
    i.add_argument('--json', action='store_true', help='одной строкой JSON для pc3live.py join --json -')
    a = p.parse_args(argv)
    {'start': cmd_start, 'go': cmd_go, 'check': cmd_check, 'code': cmd_code, 'inventory': cmd_inventory, 'kit': lambda _: print_kit()}[a.cmd](a)

if __name__ == '__main__':
    main()
