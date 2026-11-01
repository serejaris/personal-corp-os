---
name: ai-video
description: "AI video director, prompt engineer, and universal connector. Formats structured prompts (camera moves, lighting, pacing, native audio for Grok) and coordinates video generation across providers (xAI Grok Video, Fal.ai MCP, Runway MCP, Kling, Luma, Wan) via API, MCP, or web subscriptions. Use on 'video', 'AI video', 'generate video', 'video prompt', 'grok video', 'runway', 'kling', 'luma', 'wan', 'mcp video'."
---

# AI Video Generation & Director Skill

Structures, scripts, directs, and routes short AI video clips (product teasers, marketing spots, cinematic shots, UI demos, animations). Coordinates prompt engineering across modern video generation engines (xAI Grok Video, Kling, Runway, Luma, Wan 2.1) and provides a universal connector for MCP tools, direct APIs, and web subscription workflows.

> [!NOTE]
> Подробное руководство по подключению через API, подписку (SuperGrok, Kling, Runway) или MCP (Fal.ai, Runway) вынесено в отдельный документ: [`references/providers.md`](./references/providers.md).

## When to use
- Написать структурированный промпт для генератора видео с точным контролем камеры, света, действия и тайминга.
- Сгенерировать видеоклип через доступный провайдер (xAI Grok, Runway, Kling, Luma через Fal.ai MCP или API).
- Сделать раскадровку для серии связанных шотов (multi-shot sequence).
- Сделать ремикс или вариацию существующего кадра с сохранением инвариантов (камера, композиция, свет).
- Подготовить спецификацию аудиодорожки и диалогов (для движков с нативным звуком, например Grok Imagine Video).

## Connector Architecture (Как скилл подключается к генераторам)

Скилл работает на 3 уровнях интеграции:

1. **Level 1 — Режиссура и промптинг (Zero-config, любой Web UI):**
   * Работает без API-ключей.
   * Формирует готовый выверенный промпт под выбранный сервис:
     * `video_gen.py --format grok` — включает блок сцены, камеры, аудио и реплик.
     * `video_gen.py --format runway` — оптимизирует под cinematic prompt conventions Runway Gen-3.
     * `video_gen.py --format kling` / `wan` — плотное описание физики и динамики.
     * `video_gen.py --format luma` — разметка траектории камеры и ключевых кадров.
   * Пользователь может сразу вставить промпт в веб-интерфейс (Grok UI, Kling Web, Runway ML, Luma Dream Machine).

2. **Level 2 — Автономный агент через MCP (Model Context Protocol):**
   * Если в настройках харнеса подключен `fal-ai` MCP или `runway` MCP, агент может самостоятельно вызывать генерацию:
     * **Fal.ai MCP:** `https://mcp.fal.ai/mcp` (доступ к Kling, Luma Ray 2, Wan 2.1, Minimax).
     * **Runway MCP:** `https://mcp.runway.team` (Runway Gen-3 Alpha/Turbo).
   * Агент отправляет задачу в очередь, проверяет статус и сохраняет полученный `.mp4`.

3. **Level 3 — Прямой CLI / API (Скрипты и пайплайны):**
   * Скрипт `scripts/video_gen.py` принимает переменные окружения (`XAI_API_KEY`, `FAL_KEY`, `RUNWAY_API_KEY`).
   * Позволяет делать пакетную генерацию (`batch`) или проверять валидность через `--dry-run`.

---

## Workflow

1. **Определить цель и провайдера:**
   * Нужен ли звук в кадре? → **xAI Grok Video 1.5** (нативный звук и диалоги).
   * Нужна кинематографичность и сложные пролёты камеры? → **Runway Gen-3** или **Luma Ray 2**.
   * Нужна реалистичная динамика людей/хореография? → **Kling AI**.
   * Нужна локальная модель или открытые веса? → **Alibaba Wan 2.1**.
2. **Собрать параметры шота:**
   * Промпт, целевое соотношение сторон (16:9, 9:16, 1:1), хронометраж (обычно 4–10 сек), референсное изображение (image-to-video при наличии).
3. **Аугментировать промпт по канону режиссуры:**
   * Не пишите абстрактные описания («красивое видео»). Опишите: объект, свет, объектив/камеру, одно конкретное движение и палитру.
4. **Сформировать спецификацию:**
   * Запустить `scripts/video_gen.py` с флагами (`--scene`, `--camera`, `--action`, etc.) или подготовить файл промпта.
5. **Выполнить генерацию:**
   * Либо через MCP-инструмент (если активен);
   * Либо через CLI (`scripts/video_gen.py`);
   * Либо выдать структурированный промпт пользователю для веб-интерфейса.

---

## Prompt Augmentation Template (Шаблон промпта)

Используйте этот шаблон для сборки спецификации кадра:

```text
Use case: <где будет использован шот: тизер, рилс, эксплейнер, UI demo>
Primary request: <главная мысль запроса пользователя>
Scene/background: <локация, время суток, атмосфера, погода>
Subject: <главный объект или персонаж, материалы, текстура>
Action: <ОДНО четкое действие за время клипа>
Camera: <тип плана, фокусное расстояние, движение: static wide, slow dolly-in, 30-degree orbit, pan right>
Lighting/mood: <характер света: soft key, rim light, moody dawn, neon glow>
Color palette: <3-5 опорных цветов>
Style/format: <film 35mm, crisp digital, natural grain, minimal 3D>
Timing/beats: <ритм: 0-2s действие, 2-4s акцент>
Audio (для Grok): <шум окружения, эффекты, музыкальный фон>
Dialogue (если есть):
- Speaker: "Короткая фраза."
Constraints: <чего избегать: no text, no logos, avoid jitter, smooth motion>
```

---

## Режиссерские правила (Prompting Best Practices)

1. **Один шот — одно действие + одно движение камеры:**
   * Попытка уместить три действия в один 5-секундный ролик всегда приводит к каше и галлюцинациям физики.
2. **Язык оператора вместо прилагательных:**
   * Вместо «красивый закат» пишите: `golden hour, low-angle 50mm lens, subtle lens flare, soft atmospheric haze`.
3. **Фиксация камеры для UI и надписей:**
   * Если в кадре есть интерфейс или текст, камера должна быть строго зафиксирована (`locked-off, straight-on, no camera shake`), иначе текст поплывёт.
4. **Инварианты при ремиксах:**
   * При изменении кадра явно указывайте, что остаётся неизменным (`same shot framing, same camera dolly, change only lighting to warm sunset`).
5. **Спецификация звука для Grok Video:**
   * Если генерация идёт через xAI Grok, звук генерируется синхронно — указывайте звуковые детали в блоке `Audio:` и `Dialogue:`.

---

## Файловая карта скилла

* **[`references/providers.md`](./references/providers.md)** — **главный справочник**: всё про подключение xAI Grok (SuperGrok vs API), Fal.ai MCP, Runway MCP, Kling, Luma, Wan 2.1, цены и форматы.
* **[`references/cinematic-shots.md`](./references/cinematic-shots.md)** — пресеты планов (dolly, orbit, crane, lateral move, macro).
* **[`references/prompting.md`](./references/prompting.md)** — углубленные принципы написания промптов для видеогенераторов.
* **[`references/sample-prompts.md`](./references/sample-prompts.md)** — готовые образцы промптов (тизер продукта, мобильный UI, детальный шот, реклама).
* **[`references/social-ads.md`](./references/social-ads.md)** — структура вертикальных рекламных роликов (крючок, проблема, демонстрация, CTA).
* **[`references/troubleshooting.md`](./references/troubleshooting.md)** — решение типовых проблем (мерцание, мыло, деформация объектов).
* **[`scripts/video_gen.py`](./scripts/video_gen.py)** — универсальный скрипт форматирования и генерации.
