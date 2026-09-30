---
name: benchmark
description: >-
  Use when choosing between engines or models for an agent pipeline and the
  answer must come from measurement on your own data, not from marketing pages:
  speech recognition for meeting recordings, the model that turns a transcript
  into notes, the critic model that checks it. Runs every variant in an
  isolated container, measures time, cost per hour of input (USD and RUB, with
  price source and date) and quality (WER/CER and course terms for ASR; code
  checks plus a judge of a different model for LLM steps), writes
  results.json/csv and one static analytics page. Triggers on "бенчмарк",
  "сравни движки", "сколько стоит час записи", "какую модель взять для
  пайплайна", "benchmark the pipeline", "compare ASR engines".
---

# Benchmark

Measure a pipeline on your own input before you pick an engine. One task file lists the variants; the scripts run them one by one in an isolated container and write numbers you can defend: time, cost per hour of input with a dated price source, quality against a reference.

Shape of a pipeline this skill knows:

`input (recording) → ASR engine → transcript → author model (notes, chapters) → code checks → judge model`

Each arrow is a slot. A variant fills one slot and keeps the rest fixed.

## When to use

- «ElevenLabs, Whisper or a Russian engine: what does an hour of our meetings cost and who makes fewer mistakes»;
- «move the notes step from Claude to GLM: does quality hold»;
- before a pipeline goes unattended: pick the critic that finds the most real problems.

Not for: load testing, latency SLOs of a live service, model evals on public datasets.

## Rules

1. **Isolation.** Run in a dedicated container (LXC/VM), not on a laptop and not next to production: the timing is clean and the keys live only there. Egress: provider APIs; private network closed except the services the task needs (for example a self-hosted ASR).
2. **Keys only from env.** The container gets a root-only env file; scripts read variable names from the task and never print values. Error bodies are redacted (some providers echo the key back).
3. **Same harness for every model.** LLM steps run through `claude -p` (Claude Code headless) against Anthropic-compatible endpoints; only the model changes. Tools, prompt, permissions stay the same.
4. **Judge is never the author's model.** `llm.py` refuses such a variant.
5. **No answer leaks.** The author must not see the published result of the same input (a «form reference» that is the answer itself). Give it a sibling of the same kind.
6. **Prices carry source and date.** `prices.json`: every item has `source` and `checked`; FX from the central bank of the day. A number without a source does not go into the report.
7. **What was not run is a row too.** Missing key, no balance, provider closed to new clients: write the reason and the list price, do not drop the row.
8. **Private input stays private.** Transcripts and recordings go to a private repo; the analytics page shows only aggregate numbers.

## Steps

1. **Task file** (`task.example.json`): input audio, language, terms list, reference transcript, ASR variants, LLM variants with judges, `not_run` rows with reasons.
2. **Container.** Create it by your infra rules (the section «Container» below). Install `ffmpeg`, Python venv with `httpx jiwer faster-whisper`, Node and `@anthropic-ai/claude-code`. Put keys into `/etc/bench.env` (root 600) through a pipe from your secret store.
3. **ASR:** `python3 scripts/asr.py --task task.json --out runs/<name>` (engines run sequentially; ElevenLabs credits are read before and after).
4. **LLM:** write an adapter for your pipeline (contract in `scripts/llm.py`), then
   `python3 scripts/llm.py --task task.json --out runs/<name> --stage author` on the container and
   `--stage judge` where the judge's key lives (a subscription login on another machine is fine: the judge only reads files).
5. **Score:** `python3 scripts/score.py --task task.json --out runs/<name> --prices prices.json`.
6. **Page:** `python3 scripts/report.py --results runs/<name>/results.json --out report.html --notes notes.md`.
7. **Method note** next to the results: input, reference origin, what was not run and why, known biases.

## Engines and providers

| Slot | Engine key | Tested | Needs |
|---|---|---|---|
| ASR | `elevenlabs` (Scribe, optional keyterms) | yes | `ELEVENLABS_API_KEY` |
| ASR | `openai_compat` (`/v1/audio/transcriptions`: self-hosted GigaAM, speaches, cloud) | yes | server URL, optional key |
| ASR | `faster_whisper` (CPU, int8) | yes | model download once |
| ASR | `openrouter_audio` (chat with `input_audio`, chunked) | request path only | `OPENROUTER_API_KEY` with balance |
| LLM | `zai` (GLM via `api.z.ai/api/anthropic`) | yes | `ZAI_API_KEY` |
| LLM | `anthropic-local` (the login on this machine) | yes | Claude Code logged in |
| LLM | `openrouter`, `deepseek`, `anthropic-api`, `anthropic-oauth` | not yet | key with balance |

Yandex SpeechKit and SaluteSpeech have no adapter yet: add one to `ENGINES` in `asr.py` (input: audio path, output: text, raw response, usage) when you have a key.

## Metrics

ASR (against the reference, after lower case, `ё→е`, punctuation and speaker tags removed):

- `wer`, `cer`: word and character error rate;
- `wer_termnorm`: WER after known term distortions are fixed in both texts;
- `term_accuracy`: share of term mentions written canonically, canon / (canon + known distortions), no reference needed;
- `term_recall`: canonical term mentions vs. the reference;
- `asr_pairwise_wer`: engines against each other, independent of the reference;
- `rtf`: wall time / audio time.

LLM: code checks before and after the fix round, fix rounds, judges' verdicts with critical / major / minor counts, tokens, turns, wall time.

Cost per hour of input: list price (`api_price`), tokens × list price (`tokens`), provider-reported cost (`reported`), or the CPU-seconds share of your server's month (`server_share`) for self-hosted engines.

## Bias checklist (write it into the method note)

- Where the reference came from. A reference made by engine X favours X in WER; say so and read `term_accuracy` and pairwise WER next to it.
- Numbers: engines write «65» or «шестьдесят пять»; WER counts both as errors.
- Self-hosted time depends on the host's load at run time; note CPU threads and neighbours.
- One recording is one sample. Treat differences under a couple of WER points as noise.

## Container

The skill does not create infrastructure. Follow your infra rules; minimum:

- a separate container for benchmarks, not a production or user container;
- no inbound exposure; no SSH if the host can exec into it;
- outbound: internet for APIs; private networks closed except named services;
- keys in a root-only env file, services started with `EnvironmentFile=`, run as an unprivileged user;
- CPU weight below production neighbours (for example `cpuunits` lower than default).

## Files

- `scripts/asr.py`, `scripts/llm.py`, `scripts/claude_step.py`, `scripts/score.py`, `scripts/report.py`, `scripts/common.py`
- `task.example.json`: a task with every engine type
- `prices.example.json`: price table with sources, checked 2026-09-30
- `examples/adapter_example.py`: a minimal LLM adapter (author → checks → one fix → judge); run end to end with GLM-5.3-Flash as author and GLM-5.3 as judge
