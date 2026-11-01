# CLI Reference (`scripts/video_gen.py`)

Универсальный CLI-скрипт для форматирования, аугментации промптов и подготовки спецификаций для AI-видеогенераторов.

## Возможности

- Форматирование под разные целевые платформы (`--format`):
  - `grok` — xAI Grok Imagine Video 1.5 (поддерживает блок аудио, звуковые эффекты и реплики).
  - `runway` — Runway Gen-3 (кинематографичный стиль с префиксами движения камеры).
  - `kling` — Kling AI 1.5/1.6 (высокая детализация движения и объектов).
  - `luma` — Luma Dream Machine / Ray 2 (маркеры движения камеры).
  - `wan` — Alibaba Wan 2.1 (физическая среда и свет).
  - `generic` — универсальная многострочная спецификация.
- Dry-run режим без внешних зависимостей (чистый Python 3).
- Экспорт в читаемый текст или машиночитаемый JSON (`--json`).

## Использование

```bash
# Базовый запуск с аугментацией под Grok (со звуком)
python scripts/video_gen.py "Futuristic neon city street" \
  --camera "low-angle slow dolly-in 35mm" \
  --action "hovercar speeds past in the rain" \
  --lighting "cyberpunk neon reflections on wet asphalt" \
  --audio "distant synthwave bass, heavy rain splashes, whoosh of hover engine" \
  --format grok

# Генерация под Runway Gen-3
python scripts/video_gen.py "Matte black camera on pedestal" \
  --camera "30-degree slow orbit 85mm" \
  --action "soft studio light rolls across the chassis" \
  --palette "charcoal, matte black, amber" \
  --format runway

# Вывод в JSON для передачи в пайплайн
python scripts/video_gen.py --prompt-file prompt.txt --format grok --json -o out/spec.json
```
