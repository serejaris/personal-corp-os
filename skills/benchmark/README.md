# Benchmark Skill

A skill for choosing engines and models for an agent pipeline by measurement on your own input.

## Problem

A price page says how much a model costs per token or per hour; it does not say how many mistakes it makes on your meetings, how long a run takes, or what an hour of your recordings costs end to end. Comparing «by feel» on a laptop mixes timing with everything else running there and leaves no numbers to show.

## Solution

- One task file lists the variants: ASR engines, the author model for notes, the judge model
- Scripts run the variants one by one in an isolated container, keys only from a root-only env file
- Every LLM variant runs in the same harness (Claude Code headless); only the model changes
- Metrics: time, cost per hour of input in USD and RUB with price source and date, WER/CER and course-term accuracy for ASR, code checks and a judge of a different model for LLM steps
- Output: `results.json`, `results.csv`, one static analytics page without transcript text

## Installation

```bash
cp -r skills/benchmark ~/.claude/skills/
```

On the benchmark container: `ffmpeg`, Python venv with `httpx jiwer faster-whisper`, Node and `@anthropic-ai/claude-code`.

## Quick Reference

### Triggers

| Phrase | Language |
|--------|----------|
| "бенчмарк", "сравни движки", "сколько стоит час записи" | RU |
| "benchmark the pipeline", "compare ASR engines" | EN |

### Commands

| Step | Command |
|------|---------|
| ASR variants | `python3 scripts/asr.py --task task.json --out runs/<name>` |
| LLM variants | `python3 scripts/llm.py --task task.json --out runs/<name> --stage author` |
| Judges elsewhere | `python3 scripts/llm.py ... --stage judge` |
| Score | `python3 scripts/score.py --task task.json --out runs/<name> --prices prices.json` |
| Page | `python3 scripts/report.py --results runs/<name>/results.json --out report.html` |

### Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Rules, steps, metrics, bias checklist |
| `task.example.json` | Task with every engine type |
| `prices.example.json` | Price table with sources, checked 2026-09-30 |
| `examples/adapter_example.py` | Minimal LLM adapter: author, checks, judge |

## License

MIT
