# AI Video API & MCP Quick Reference

Краткий справочник по API и MCP для видеогенерации. Полный разбор подписок и настройки — в [`references/providers.md`](./providers.md).

## Поддерживаемые провайдеры

### 1. xAI Grok Imagine Video 1.5
- **Endpoint:** `https://api.x.ai/v1/videos/generations` (или через Fal.ai / Renderful)
- **Аутентификация:** `XAI_API_KEY` или OAuth JWT из SuperGrok Heavy (`~/.grok/auth.json`)
- **Разрешения:** 480p, 720p, 1080p
- **Длительность:** до 15 секунд
- **Ключевая фича:** нативное синхронное аудио (звук окружения, музыка, реплики)

### 2. Fal.ai MCP (Kling, Luma Ray 2, Wan 2.1, Minimax)
- **Hosted MCP URL:** `https://mcp.fal.ai/mcp`
- **Аутентификация:** `Authorization: Bearer $FAL_KEY`
- **Доступные инструменты:** `search_models`, `submit_job`, `check_job`, `download_asset`
- **Формат запуска:** асинхронная очередь (submit → poll / webhook → download)

### 3. Runway Gen-3
- **Hosted MCP URL:** `https://mcp.runway.team`
- **Direct API:** `api.runwayml.com/v1/image_to_video`
- **Аутентификация:** `Authorization: Bearer $RUNWAY_API_KEY`
- **Длительность:** 5s / 10s

## Общий жизненный цикл генерации видео

1. **Submit (POST):** Отправка структурированного промпта, разрешения, соотношения сторон (16:9, 9:16) и длительности.
2. **Queue & Status (GET):** Статусы: `queued` → `in_progress` → `completed` / `failed`. Опрос обычно раз в 5–15 секунд.
3. **Download:** Загрузка `.mp4` на локальный диск или в облачное хранилище (ссылки обычно истекают через 1–24 часа).
