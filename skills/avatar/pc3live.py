#!/usr/bin/env python3
"""Клиент живого класса для скилла avatar: зовёт инструменты MCP-сервера урока по HTTP (JSON-RPC tools/call).

Нужен потому, что MCP-сервер, добавленный посреди сессии, виден агенту только после перезапуска харнеса, а робот
должен войти сразу. Сервер без сессий: каждый вызов — один POST на <сервер>/mcp. Только стандартная библиотека.

  python3 pc3live.py join <ссылка входа> --name Аня --code b0000Xopus_5D5   войти (или обновить своего робота)
  python3 pc3live.py start ["о чём задача"]                                    маячок горит: агент работает
  python3 pc3live.py end                                                        маячок гаснет
  python3 pc3live.py say "короткая фраза"                                       робот «говорит», до 80 знаков
  python3 pc3live.py status                                                     связь, сколько в классе
  python3 pc3live.py inventory --files "CLAUDE.md,me.md" --skills "hq,avatar" --mcp "pc3" --depts "corp-media"
  python3 pc3live.py inventory --json '{"files": ["CLAUDE.md"], "skills": ["hq"]}'   или --json - (JSON из stdin)
                                                                                парта: только имена, без путей
  join принимает те же --files/--skills/--mcp/--depts/--json: парта приходит вместе с роботом.
  python3 pc3live.py connect                                                    команды подключения MCP для Claude Code и Codex
  --quiet: для хуков харнеса — без вывода, ошибки глотаются, код выхода 0.

Состояние (адрес сервера, код урока, личный токен) — в ~/.pc3/live.json, права 600. Токен никому не показывать.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

STATE = Path(os.environ.get('PC3_LIVE_STATE') or Path.home() / '.pc3' / 'live.json')
TIMEOUT = float(os.environ.get('PC3_LIVE_TIMEOUT') or 8)
LINK = re.compile(r'^(https?://[^/\s]+)/j/([A-Za-z0-9]+)/?$')


class Fail(Exception):
    pass


def load():
    try:
        return json.loads(STATE.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def save(st):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix('.tmp')
    tmp.write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding='utf-8')
    os.chmod(tmp, 0o600)
    tmp.replace(STATE)


def http(url, body=None, accept='application/json'):
    data = json.dumps(body).encode('utf-8') if body is not None else None
    req = urllib.request.Request(url, data=data, headers={
        'Content-Type': 'application/json', 'Accept': accept, 'User-Agent': 'pc3live/1'})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        try:
            j = json.loads(e.read().decode('utf-8'))
        except ValueError:
            raise Fail('сервер ответил HTTP %s' % e.code) from None
        raise Fail((j.get('error') or {}).get('message') if isinstance(j.get('error'), dict) else j.get('error') or 'HTTP %s' % e.code) from None
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise Fail('нет связи с сервером урока: %s' % getattr(e, 'reason', e)) from None


def call(mcp, name, args):
    """Один вызов инструмента MCP; ответ инструмента — JSON в первом текстовом блоке."""
    j = http(mcp, {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': name, 'arguments': args}},
             accept='application/json, text/event-stream')
    if 'error' in j:
        raise Fail(j['error'].get('message', 'ошибка MCP'))
    res = j.get('result') or {}
    try:
        out = json.loads(res['content'][0]['text'])
    except (KeyError, IndexError, ValueError):
        raise Fail('непонятный ответ сервера') from None
    if res.get('isError') or not out.get('ok'):
        raise Fail(out.get('error') or 'отказ сервера')
    return out


def need(st):
    if not st.get('mcp') or not st.get('token'):
        raise Fail('робот ещё не в классе: сначала join <ссылка входа>')
    return st


INV_KEYS = ('files', 'skills', 'mcp', 'depts')


def inventory_of(opts):
    """--json '<объект>' | --json - (stdin) и/или --files a,b --skills … → {files, skills, mcp, depts} или None."""
    inv = {}
    raw = opts.get('json')
    if raw is not None:
        try:
            j = json.loads(sys.stdin.read() if raw == '-' else raw)
        except ValueError:
            raise Fail('--json: нужен JSON-объект {"files": [...], "skills": [...], "mcp": [...], "depts": [...]}') from None
        if not isinstance(j, dict):
            raise Fail('--json: нужен объект')
        inv.update({k: [str(x) for x in j.get(k) or [] if isinstance(x, (str, int, float))] for k in INV_KEYS if k in j})
    for k in INV_KEYS:
        if opts.get(k) is not None:
            inv[k] = [x.strip() for x in opts[k].split(',') if x.strip()]
    return inv or None


def inv_note(out):
    inv = out.get('inventory')
    if not inv:
        return ''
    n = ', '.join('%s %d' % (k, len(inv.get(k) or [])) for k in INV_KEYS)
    return ' Парта: %s%s.' % (n, '; отброшено %d' % out['dropped'] if out.get('dropped') else '')


def cmd_join(link, name, code, inventory=None):
    m = LINK.match(link.strip())
    if not m:
        raise Fail('ссылка входа выглядит так: https://<сервер>/j/<код урока>')
    base, lesson = m.group(1), m.group(2).lower()
    info = http('%s/j/%s?format=json' % (base, lesson))
    if not info.get('ok'):
        raise Fail(info.get('error') or 'код урока не тот')
    st = load()
    token = st.get('token') if st.get('mcp') == info['mcp'] else None
    args = dict(lesson=lesson, name=name, code=code, **({'inventory': inventory} if inventory else {}))
    try:
        out = call(info['mcp'], 'arrive', dict(args, **({'token': token} if token else {})))
    except Fail as e:
        if token and 'токен' in str(e):
            out = call(info['mcp'], 'arrive', args)
        else:
            raise
    save({'mcp': info['mcp'], 'link': info['link'], 'lesson': lesson, 'token': out['token'], 'id': out['id'], 'name': out['name']})
    return 'Робот «%s» %s. В классе роботов: %s.%s' % (
        out['name'], 'обновлён' if out.get('again') else 'вошёл в класс', out['class']['count'], inv_note(out))


def cmd_connect():
    st = load()
    mcp = st.get('mcp') or '<сервер>/mcp'
    return '\n'.join([
        'Claude Code: claude mcp add --transport http pc3 %s' % mcp,
        'Codex:       codex mcp add pc3 --url %s' % mcp,
        'После подключения перезапусти агента: инструменты pc3 появятся в новой сессии.'])


def main(argv):
    quiet = '--quiet' in argv
    argv = [a for a in argv if a != '--quiet']
    if not argv or argv[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    opts, pos = {}, []
    if cmd in ('join', 'inventory'):
        it = iter(rest)
        for a in it:
            if a in ('--name', '--code', '--json') + tuple('--' + k for k in INV_KEYS):
                opts[a[2:]] = next(it, '')
            else:
                pos.append(a)
    try:
        if cmd == 'join':
            if not pos or not opts.get('name') or not opts.get('code'):
                raise Fail('join <ссылка входа> --name <имя> --code <код аватара> [--files … --skills … --mcp … --depts … | --json …]')
            msg = cmd_join(pos[0], opts['name'], opts['code'], inventory_of(opts))
        elif cmd == 'inventory':
            st = need(load())
            inv = inventory_of(opts)
            if not inv:
                raise Fail('inventory --files a,b --skills c --mcp d --depts e  или  --json \'{...}\'')
            out = call(st['mcp'], 'inventory', {'token': st['token'], 'items': inv})
            msg = 'парта обновлена.%s' % inv_note(out)
        elif cmd == 'start':
            st = need(load())
            call(st['mcp'], 'work_start', {'token': st['token'], 'note': ' '.join(rest)[:300]})
            msg = 'маячок горит'
        elif cmd == 'end':
            st = need(load())
            out = call(st['mcp'], 'work_end', {'token': st['token']})
            msg = 'маячок погас, работа %s с' % round(out.get('seconds') or 0)
        elif cmd == 'say':
            st = need(load())
            out = call(st['mcp'], 'say', {'token': st['token'], 'text': ' '.join(rest)})
            msg = 'робот сказал: %s' % out['text']
        elif cmd == 'status':
            st = need(load())
            out = call(st['mcp'], 'status', {'token': st['token']})
            you = out.get('you') or {}
            msg = 'на связи: «%s», в классе %s, работают %s' % (you.get('name'), out['class']['count'], out['class']['working'])
        elif cmd == 'connect':
            msg = cmd_connect()
        else:
            raise Fail('команды: join, start, end, say, inventory, status, connect')
    except Fail as e:
        if not quiet:
            print('pc3live: %s' % e, file=sys.stderr)
        return 0 if quiet else 1
    if not quiet:
        print(msg)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
