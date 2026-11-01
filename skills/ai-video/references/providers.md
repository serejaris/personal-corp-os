# Подключение AI-видеогенераторов: API, подписки и MCP

Справочник по подключению современных моделей генерации видео (состояние на 2026 год) через мультимодельный коннектор.

---

## 1. Матрица выбора: Подписка vs Direct API vs MCP

| Способ | Для чего подходит | Плюсы | Минусы |
|---|---|---|---|
| **MCP (Model Context Protocol)** | Автономная работа агентов в Claude Code / Codex / Antigravity | Агент сам запускает генерацию, проверяет очередь и забирает mp4 без переключения окон | Требует настройки MCP-сервера и API-ключа |
| **Direct API (pay-as-you-go)** | Скрипты автоматизации, бэкенды, CLI (`video_gen.py`) | Оплата ровно за секунды видео, гибкость параметров, пакетные прогоны | Нужен API-ключ, баланс в долларах, обработка webhook/poll |
| **Подписка (Web UI)** | Ручной монтаж, проверка идей, интерактивный просмотр | Фиксированная абонплата в месяц, удобный предпросмотр в браузере | Ручной перенос промптов из чата агента в браузер |

---

## 2. Провайдеры и подключение

### 1. xAI Grok Imagine Video (Grok Video 1.5)

xAI предоставляет генерацию видео с **нативным синхронным звуком** (звуковые эффекты, эмбиент и речь создаются в один проход с видеорядом).

* **Подписка (Web/App):**
  * Входит в тариф **SuperGrok** / SuperGrok Heavy.
  * Поверхности: веб-интерфейс `grok.com`, мобильные приложения X / Grok.
  * Пул: общий недельный пул SuperGrok Heavy.
* **API:**
  * Endpoint: `https://api.x.ai/v1/videos/generations` (или через шлюзы вроде Fal.ai / Renderful).
  * Авторизация: `XAI_API_KEY` или OAuth JWT из активной сессии `~/.grok/auth.json`.
  * Модели: `grok-imagine-video`, `grok-imagine-video-1.5`.
* **Характеристики:**
  * Разрешение: 480p, 720p, native 1080p.
  * Соотношения сторон: 16:9, 9:16, 1:1.
  * Длительность: до 15 секунд.
  * Главное преимущество: **встроенная звуковая дорожка** без необходимости подключать сторонний TTS/SFX.

---

### 2. Fal.ai MCP — Единый мультимодельный хаб

Fal.ai предоставляет официальный высокопроизводительный MCP-сервер с поддержкой более 1000 моделей медиа (Kling, Luma Ray 2, Wan 2.1, Minimax/Hailuo, CogVideoX).

* **Подключение MCP (Claude Code / Codex / Antigravity):**
  Добавить в конфигурацию MCP (`~/.claude/settings.json` или локальный конфиг):
  ```json
  {
    "mcpServers": {
      "fal-ai": {
        "url": "https://mcp.fal.ai/mcp",
        "headers": {
          "Authorization": "Bearer $FAL_KEY"
        }
      }
    }
  }
  ```
  *(Также поддерживается OAuth-реле `https://mcp.fal.ai/mcp-relay`)*.
* **Инструменты, доступные агенту через MCP:**
  * `search_models` — поиск актуальных видеомоделей;
  * `submit_job` — отправка промпта и параметров в очередь;
  * `check_job` — проверка статуса рендера;
  * `download_asset` — получение готового `.mp4`.
* **Модели в каталоге Fal:**
  * `fal-ai/kling-video/v1.6/pro` (Kling AI)
  * `fal-ai/luma-dream-machine/ray-2` (Luma Ray 2)
  * `fal-ai/wan/v2.1/t2v-14b` (Alibaba Wan 2.1)
  * `fal-ai/minimax-video` (Hailuo)
* **Тарификация:** Pay-as-you-go, списывается за секунду вычислений (в среднем $0.03 – $0.10 за клип в зависимости от разрешения и модели).

---

### 3. Runway (Gen-3 Alpha & Gen-3 Turbo)

Один из лидеров кинематографической генерации с развитым контролем камеры и движения.

* **Подключение MCP:**
  Официальный Hosted Streamable HTTP сервер:
  * URL: `https://mcp.runway.team`
  * Авторизация: `RUNWAY_API_KEY` в заголовке `Authorization: Bearer <KEY>`.
* **Подписка (Web):**
  * `runwayml.com`:
    * Standard: $12 / мес (625 кредитов)
    * Pro: $28 / мес (2250 кредитов)
    * Unlimited: $76 / мес (безлимитные генерации в relax mode)
* **Direct API:**
  * Host: `api.runwayml.com/v1/image_to_video`, `/v1/tasks`
  * Цены: Gen-3 Alpha Turbo ~$0.05/сек, Gen-3 Alpha ~$0.10/сек.
* **Фичи:** Motion Brush, Director Mode (управление панорамированием, приближением, креном), апскейлинг до 4K.

---

### 4. Kling AI (Kuaishou)

Лучшая модель для физики движения людей, сложных хореографий и динамичных сцен.

* **Подписка (Web):**
  * `klingai.com`: пакеты кредитов Standard (~$10/мес), Pro (~$37/мес), Premier (~$92/мес).
* **API:**
  * Официальный API: через китайскую платформу разработчиков Kling (`klingai.org`).
  * Рекомендуемый путь для агентов: через **Fal.ai MCP** (`fal-ai/kling-video/v1.6/pro`) или Replicate — избавляет от необходимости регистрироваться на отдельном китайском портале.
* **Характеристики:** клипы 5 или 10 секунд, 1080p, точное соблюдение физики тела и одежды.

---

### 5. Luma Dream Machine (Ray 1 & Ray 2)

Специализируется на кинематографичных пролётах камеры и интерполяции между ключевыми кадрами.

* **Подписка (Web):**
  * `lumalabs.ai/dream-machine`: бесплатный пул (30 генераций в месяц), Standard $24/мес, Plus $65/мес.
* **API:**
  * `api.lumalabs.ai` (или через Fal.ai `fal-ai/luma-dream-machine`).
* **Ключевая фича:** **Keyframing** — можно подать начальный кадр (Start Frame) и конечный кадр (End Frame), и модель сгенерирует плавный видеопереход между ними.

---

### 6. Alibaba Wan 2.1 (Qwen / Tongyi)

Открытое семейство моделей от Alibaba Cloud с высоким качеством детализации и текстур.

* **Подписка / Web:**
  * Model Studio Playground / Qwen Studio.
* **API:**
  * Alibaba Cloud Model Studio (DashScope API).
  * Доступно также через Fal.ai (`fal-ai/wan/v2.1/t2v-14b`).
* **Self-hosted (открытые веса):**
  * Wan2.1-T2V-14B (требует мощный GPU типа A100/H100)
  * Wan2.1-T2V-1.3B (легковесная версия, помещается в 12–16 ГБ VRAM).

---

### 7. Google Veo 2

* **API:** Google Cloud Vertex AI / Gemini API.
* **Web:** VideoFX (доступен в Google Labs).
* **Особенности:** глубина резкости, длинные стабильные планы, фотореализм.

---

## 3. Сводная таблица параметров и форматов

| Провайдер | Нативное аудио | Макс. длительность | Разрешения | Главный метод подключения для агента |
|---|---|---|---|---|
| **xAI Grok Video 1.5** | **Да (звук + речь)** | до 15 с | 480p, 720p, 1080p | Подписка SuperGrok / xAI API |
| **Runway Gen-3** | Нет (или фон) | 5 с / 10 с | 720p, 1080p, 4K upscale | Runway MCP (`https://mcp.runway.team`) |
| **Kling AI 1.6** | Нет | 5 с / 10 с | 720p, 1080p | Fal.ai MCP (`fal-ai/kling-video`) |
| **Luma Ray 2** | Нет | 5 с (с расширением) | 720p, 1080p | Fal.ai MCP / Luma API |
| **Wan 2.1 (Alibaba)** | Нет | 5 с | 720p, 1080p | QwenCloud API / Fal.ai MCP / Local |

---

## 4. Как скилл `ai-video` использует коннекторы

1. **Режим Zero-Config (без API-ключей):**
   * Агент структурирует промпт по режиссерскому канону (`references/cinematic-shots.md`, `references/prompting.md`).
   * Через CLI `video_gen.py --format [grok|runway|kling|luma]` генерируется готовый текст для вставки в Web UI (SuperGrok, Kling Web, Runway).
2. **Режим MCP (автономный):**
   * При наличии в конфиге сервера `fal-ai` или `runway`, агент отправляет задачу напрямую в MCP-инструмент.
3. **Режим Direct CLI:**
   * При экспорте `XAI_API_KEY`, `FAL_KEY` или `RUNWAY_API_KEY`, CLI `scripts/video_gen.py` может отправлять запрос напрямую и ожидать готовности файла.
