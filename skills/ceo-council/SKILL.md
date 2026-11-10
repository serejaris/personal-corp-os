---
name: ceo-council
description: Use when needing strategic project analysis from multiple independent expert perspectives. Triggers on business decisions, growth strategy, product direction, competitive analysis, "совет директоров", or any situation where diverse opinions reduce blind spots. Hired experts are stored in the HQ and come back on the next run.
---

# CEO Council — Independent Strategic Analysis

Launch parallel sub-agents as isolated experts. Each expert is a **real, well-known person** (Paul Graham, Alex Hormozi, Pieter Levels, Naval Ravikant, Steve Jobs, Eliyahu Goldratt…) and analyzes the same project data strictly through their published philosophy and mental models. No coordination between experts — isolation produces genuine diversity of opinion. Then synthesize consensus and disagreements.

Experts the user likes are **hired**: saved as persona files in the HQ and offered first on every next run.

## Critical: How to Launch Experts

**MUST use the Task tool** with `subagent_type: "general-purpose"` and `model: "opus"` (or `inherit`).

```
Task(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "<expert prompt with persona + data>",
  description: "Paul Graham analysis"
)
```

**DO NOT** use bash, shell scripts, or background commands to launch experts. They will fail.

Launch all experts in a **single message with multiple Task tool calls** for true parallelism.

## Where Hired Experts Live

One folder, one file per expert:

```
council/
  README.md            # roster: name, lens, hired date, sessions count
  paul-graham.md       # persona file
  paul-graham.svg      # portrait
  alex-hormozi.md
  alex-hormozi.svg
  sessions/
    2026-11-10.md      # synthesis of each session
```

- Default location: `council/` in the root of the HQ (the folder with `me.md` / `AGENTS.md` / `CLAUDE.md` of the user's headquarters).
- Not in an HQ: `council/` in the current project root. The user may name another folder; then use it and write that path into the project's `AGENTS.md` / `CLAUDE.md` in one line so the next run finds it.
- If the folder is in git, commit new or updated persona files with the session.

Persona file format:

```markdown
---
name: Paul Graham
slug: paul-graham
hired: 2026-11-10
sessions: 1
portrait: paul-graham.svg
---

## Lens
One sentence: through what he looks at any plan.

## Mental models
- 3–6 named models / principles he is known for

## Sources
- Books, essays, talks the persona is built from (titles, links). Optional: notes from a book the user gave.

## Instruction
How to behave in the council: "be ruthless about non-core work", "demand unit economics", "ask what users said".

## Past advice
- 2026-11-10 — one line of what he recommended and whether it worked (filled after sessions)
```

## Step 0: Load the Roster

1. Find `council/` (see above). Read `council/README.md` and all persona files.
2. If there are hired experts — they are the **default options** in Step 2. Show each with its lens and last advice.
3. If the folder does not exist — skip to Step 1, it is created at Step 7.

## Step 1: Scan Project Context & Propose Personas

Before suggesting experts, understand the project:

1. Read `CLAUDE.md` / `AGENTS.md` (or `README.md` if absent), `me.md` if the HQ has one
2. Scan `.claude/rules/` for domain context
3. Glance at top-level file structure and current plans / tasks

Then **propose 4–6 REAL PEOPLE tailored to THIS project's stage, challenges and goals** — in addition to the hired ones. Each must be a well-known figure with a published philosophy and track record; that is what lets the model play them well. If the user asks for "new ones" — propose only people who are not in the roster.

| Focus | Real personas (examples, don't copy blindly) |
|---|---|
| Early product, PMF | Paul Graham, Pieter Levels, Rob Fitzpatrick |
| Offer, pricing, sales | Alex Hormozi, Chris Voss, Donald Trump (negotiation) |
| Leverage, solo business | Naval Ravikant, Sahil Lavingia, Justin Welsh |
| Product taste | Steve Jobs, Dieter Rams, Julie Zhuo |
| Operations, bottlenecks | Eliyahu Goldratt, Andy Grove, Keith Rabois |
| Education, cohorts | Wes Kao, Maven founders, Seth Godin |
| Engineering discipline | Robert C. Martin (Uncle Bob), Kent Beck, John Carmack |

## Step 2: Assemble the Council

**MANDATORY: Ask the user before proceeding.** Do not pick experts yourself.

Use `AskUserQuestion` with `multiSelect: true`:
- Hired experts first (marked "в штабе"), then 4–6 new proposals with their lens and why they fit
- User can always pick "Other" to name anyone (e.g. "давай Илона Маска и Будду")
- **Minimum 2 experts.** If the user picks 1, suggest one more for productive disagreement

## Step 3: Gather Current Data

Collect project state to feed all experts:

- Key metrics / money / data files found during the scan
- Strategy, plans, calendar load, product ladder
- Recent decisions (git log --oneline -10)
- Previous sessions in `council/sessions/`

**Skip** vanity metrics (stars, clones, traffic). **All experts receive identical data.** Prepare the data block once.

## Step 4: Generate Expert Prompts

For each expert, build the prompt from the persona file (hired) or from your proposal (new) plus the SAME data block:

```
You are [NAME]. Think strictly through your published philosophy:
[Lens + Mental models + Instruction from the persona file]

Your past advice to this user: [Past advice, if any]

The question: [user's question / goal, e.g. "plan of actions for the next two months"]

Data:
[CURRENT PROJECT DATA — identical for all experts]

Answer as [NAME] would: concrete, opinionated, with the 3 actions you'd take first.
Respond in the same language as the data provided.
```

## Step 5: Execute

Launch ALL selected experts in **one message** using multiple Task tool calls. Wait for all results.

## Step 6: Synthesize

**Do not skip this step.** The synthesis is the value of the council.

```markdown
# Council Session: [DATE]

## Question
## Council Members
## [Expert 1] — key findings
## [Expert 2] — key findings
## Consensus
## Disagreements
| Expert | Position | Argument |
## Plan
[If the user asked for a plan: steps by week, owner, how we measure]
## Decisions
_To be filled after discussion._
```

Save to `council/sessions/[DATE].md`. If the user asked for HTML — also render it as an HTML page next to it and open in the browser.

## Step 7: Hire

After the synthesis ask once (`AskUserQuestion`, multiSelect): **"Кого оставить в совете?"**

- For every chosen new expert — create `council/<slug>.md` by the format above, add a row to `council/README.md`.
- For every hired expert who took part — increment `sessions`, append one line to `Past advice`.
- The user may say "обогати персону книгой X" — read the source and add notes under `Sources`.
- Draw a portrait for every new hire: `council/<slug>.svg`, the person's lens shown with simple shapes by the `visual-grammar` skill (https://github.com/serejaris/visual-grammar), not a face. No skill — a plain SVG with the name and one shape for the lens.
- Commit `council/` if it is in git.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Starting from scratch every run | Step 0: read `council/` and offer hired experts first |
| Picking experts without asking the user | ALWAYS use AskUserQuestion first |
| Fictional roles ("Head of Growth") | Use real people with published philosophies |
| Using bash to launch experts | ONLY the Task tool |
| Giving experts different data | One data block, pasted into all prompts |
| Too many experts | 3–4 is optimal for signal-to-noise |
| Skipping synthesis or hiring | Synthesis is the value; Step 7 makes the council persistent |
