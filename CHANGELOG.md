# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **make-3d** skill — builds 3D variants in isolated scene copies, presents matching image sheets for human selection, and transfers the chosen model to the canon; bilingual READMEs.
- **make-landing** skill — reference-led 2D design variants with full concepts frozen before code, independent authors, browser checks, a gallery, human selection and a second round mixing winners; bilingual READMEs.
- **benchmark** skill — runs pipeline variants (ASR engines, the model that writes notes, the judge model) one by one in an isolated container; measures time, cost per hour of input in USD and RUB with price source and date, WER/CER and term accuracy for ASR, code checks and a judge of a different model for LLM steps; writes results.json/csv and a static analytics page; bilingual READMEs.

### Changed
- **parallel-design-variants** became **make-landing**, merging reference-anchored variants with the frozen-concept workflow and bundled author role.

## [5.1.0] - 2026-09-29

### Added
- **corp-new** skill — creates a new HQ department (rules file, skills folder, private repository, two-way link with the HQ); installs the HQ from agent-starter if missing; bilingual READMEs.
- **harness** skill — one header sets the agent's working mode for the session: role (executor, orchestrator, critic), subagent model, effort, subagent limit; bilingual READMEs.

### Changed
- **manager** defaults to orchestrator + critic at low effort with up to 3 subagents when no `/harness` header is given.

## [5.0.1] - 2026-09-17

### Fixed
- Restore the configurable public manager skill and remove workspace-specific references, templates, and process logs from its distribution.
- Validate the manager package boundary to prevent personal workspace material from being bundled again.

## [5.0.0] - 2026-08-22

### Removed
- **BREAKING** — removed the **design-minimal** skill from the public plugin. Use **html-draft** for standalone HTML diagrams and visual planning artifacts.

## [4.0.1] - 2026-08-18

### Added
- **weekly-planning** now ships a deterministic ISO-week generator and a standalone living plan: seven visible days, real-time multi-zone clocks, Area-colored cards, a non-duplicating Area Explorer, and week-scoped Wealth habit state in localStorage.
- Department `daily`, `planning`, and `retro` skills share marker, Area goal, and full-week mutation contracts.
- Public regression checks cover W34/W35/W53 transitions, seven-day rendering, and 14 browser-local habit controls.

### Changed
- **weekly-retro** adds fact-first Area Interviews and an explicit `Area Goals` handoff to planning.
- Bilingual docs describe the complete `retro → planning → daily` rhythm and point setup to `corp-doctor`.

## [4.0.0] - 2026-08-06

### Changed
- **BREAKING** — `corp-init`, `corp-new` and `task-routing` merged into one skill, **corp-doctor**. It opens with a menu and waits for an explicit choice: diagnose, repair, new department, route a task, build from scratch. The founder never used a separate init step, and three skills for one loop meant guessing which one to call.
- The skill catalogue in both READMEs is grouped instead of listed flat: system rhythm, from intent to tasks, product work, design and media, agent orchestration, docs and rules, operations.
- Russian README rewritten against the editorial voice rules of the content department: em dashes cut from 18 to 2, guillemets replaced with straight quotes, antithesis constructions and negation-led openings removed.

### Removed
- `corp-init`, `corp-new`, `task-routing`. Their behaviour lives in `corp-doctor`.

## [3.0.0] - 2026-08-06

### Changed
- **BREAKING** — repository, plugin, and marketplace renamed from `personal-corp-skills` to `personal-corp-os`. GitHub redirects the old repository URLs, but the plugin identifier changed: remove the installed `personal-corp-skills` plugin and install `personal-corp-os@personal-corp-os`. Historical entries below keep the old name because that is what those releases shipped as.
- README now opens with the framework instead of the install steps: the bottleneck problem, the route from a written task to department memory, the weekly rhythm, departments, a 30-minute first step, and a six-skill table that maps each skill to its link in the route. The flat catalogue moved below as **All skills** and is no longer nested under Telegram skills. Same structure in `README.ru.md`.
- **project-init** renamed to **corp-init** and rewritten around the current Personal Corp operating model: HQ index + daily task files, `AGENTS.md` first, `manager` issue invariants, corp-* owner map, GitHub Projects, and repair/audit mode.
- **manager** public docs/spec updated for the current operating cycle: `AGENTS.md` preferred, `corp-init` bootstrap, `weekly-planning` / `weekly-retro` preserved as separate rituals, and closed issues now require active day/week plan cleanup.

### Fixed
- `scripts/validate_repo.py` passes again after failing since 2026-07-19: the `fable-ruki-agenty` description is now a block scalar, and `to-prd` / `to-issues` got their missing English READMEs.

## [2.2.0] - 2026-07-01

### Added
- **fable-ruki-agenty** skill — manually-invoked orchestration mode: Fable writes self-sufficient specs into GitHub issue bodies and dispatches ready tasks to Sonnet subagents; never writes code itself; bilingual READMEs.
- **grill-me** skill — relentless one-question-at-a-time interview about a plan until shared understanding; every fork becomes an explicit decision with a recommendation; bilingual READMEs.
- **idea** skill — fast capture of a single voiced idea into a provenance-tracked folder (one folder per idea) with semantic dedup against an index and an optional GitHub Project mirror; bilingual READMEs.
- **parallel-design-variants** skill — parallel design bake-off: one spec doc fans out N divergent directions (each anchored to a distinct visual reference) to subagents in parallel, collects them in a gallery, picks winners (optionally by audience vote), then runs a second round that mixes the winning styles; bilingual READMEs.

## [2.1.1] - 2026-06-17

### Fixed
- **manager** skill — eliminate recurring `gh` command failures on clean runs:
  - GraphQL examples now pipe into a separate `jq` (`... | jq -r '(.data // {}) | ...'`) instead of the `--jq` flag. Root cause: when a GraphQL response carries an `errors` array (one failed alias or a fully broken query), `gh api graphql` ignores `--jq` and dumps the raw body, so the `(.data // {})` guard never ran and downstream parsing hit `KeyError: 'data'`. The pipe form runs the guard on the raw body — live aliases print, a total failure yields empty output with no crash.
  - Issue search no longer hardcodes `--state open` / `state:open` (which silently dropped closed issues). To cover both states, omit the state qualifier — one call / one alias returns open and closed together; `--state all` is documented as invalid.
  - Added the missing `(.labels.nodes // [])` null-guard to the canonical Project-evidence jq.

## [2.1.0] - 2026-06-15

### Changed
- **manager** skill — major update porting the evolved canonical issues-and-Projects workflow, kept generalized and config-driven:
  - Iron invariants expanded from 3 to 6 — added **Project placement**, **Project-visible parent** (visible root epic in the Project view with a non-empty status lane), and a mandatory **work-record comment** on real session work.
  - New **GitHub Projects integration** config block and a **Project status sync (write mode)** section (set touched issues to `In progress`, surface Project drift).
  - **Title convention replaced**: domain prefixes (`product:`, `ops:` …) removed; new formula `{object} — {action} ({when})` with type metadata living in labels / parent-tree / Projects; old prefixed titles accepted as legacy aliases. The `Issue title domains` config concept is retired.
  - Added **batched GraphQL** for cross-repo search (3+ keys, REST rate-limit avoidance) and live Project-state reads, with null-guards and partial-error handling; `--limit 1000` Project snapshots; parallel `gh` reads in pre-flight.
  - Added **commit↔issue linkage** (`refs`/`closes` trailer + short SHAs in `## Updates`), **Definition of Done** (verifiable body), **aggregate parent** classification with a parent-type taxonomy, strict **Related** body-section rules with live-verify, W-label fast-path, dated-issue W-label, and a **task drift guard** in pre-flight.
  - READMEs (EN + RU) and the SKILL.md frontmatter description updated to match the expanded invariants and capabilities.

## [2.0.0] - 2026-06-06

### Added
- **pm-prd** skill — structured PRD generation with B2C/B2B/internal/platform branching and 10-point quality checklist
- **pm-user-stories** skill — Epic → User Stories with INVEST validation, Given-When-Then AC, and Story Map output
- **pm-competitive** skill — competitor feature matrix, SWOT, Porter's Five Forces, and differentiation strategy
- **pm-feedback** skill — feedback classification, theme clustering, sentiment/NPS analysis, Top-10 pain ranking
- **pm-brainstorm** skill — SCAMPER / How Might We ideation with Impact/Effort screening
- **pm-metrics** skill — product metrics review with North Star decomposition, funnel/retention diagnostics, OKR alignment
- **pm-roadmap** skill — Now/Next/Later roadmap updates with delay attribution and scope-cut framework
- Bilingual READMEs and illustrations for all new PM skills
- Public repository hygiene: `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue
  templates, Dependabot config, validation workflow, and
  `scripts/validate_repo.py`.
- Skill README illustrations for every published skill, using deliberately clumsy MS Paint-style generated assets.

### Changed
- **prioritize** renamed to **pm-prioritize** — folder, frontmatter, install paths, README tables; `/prioritize` kept as alias trigger
- Moved `paperclip-api` from active skills to `archive/skills/paperclip-api`.
- Renamed public skill identifiers `ris-manager` → `manager` and
  `ris-prioritize` → `prioritize` (superseded in 2.0.0 by `pm-prioritize`).
- Moved Claude Code, Codex, and single-skill installation guidance to the top
  of both READMEs.
- Added a Codex marketplace manifest at `.agents/plugins/marketplace.json`.
- Added `plugins/personal-corp-skills` as a repository-root symlink so Codex
  marketplace discovery can install the root plugin through the expected
  `./plugins/<plugin-name>` path.
- Added current `.codex-plugin/plugin.json` metadata while keeping
  `.claude-plugin` metadata for Claude Code compatibility.
- Renamed **ris-draft** to **html-draft** across skill folder, docs, and invocation examples.
- Added **Product Management Skills** section to both READMEs with workflow diagram.

### Removed
- Active skill path `skills/prioritize/` — replaced by `skills/pm-prioritize/`

## [1.20.0] - 2026-06-01

### Added
- **art-director** skill - iterative visual style search for media assets
  - Coordinates branch prompts, process logs, generated or collected assets, HTML previews, and decision graphs
  - Adds iteration-cluster rules for selected, rejected, shown, and output nodes
  - Includes privacy gates for private chats, screenshots, auth material, billing records, customer records, infrastructure details, non-public repository links, and unsafe source material
  - Includes bilingual docs (README.md + README.ru.md), public-safe snippets, and a starter HTML template

## [1.19.0] - 2026-06-01

### Added
- **corp-new** skill — create or verify a private `corp-*` department repository and register it in an HQ Markdown file
  - Resolves configurable GitHub owner, workspace root, HQ file, repo prefix, and department identity
  - Adds preflight, dry-run summary, safe sync, and HQ row verification gates
  - Preserves existing folders and dirty worktrees; avoids force pushes, resets, deletions, and archive edits
  - Includes bilingual docs (README.md + README.ru.md) and public-safe placeholders

## [1.18.0] - 2026-06-01

### Added
- **tg-bot-ops** skill — public Telegram bot and Telegram-to-agent gateway operations playbook
  - Diagnoses webhook vs polling setup, update delivery, privacy mode, and forum topic routing
  - Includes a reusable Hermes-compatible gateway checklist with all infrastructure details placeholdered
  - Adds safety gates for bot tokens, `.env`, raw logs, private DMs, and production restarts
  - Includes bilingual docs (README.md + README.ru.md) and public-safe incident reporting format

## [1.17.0] - 2026-06-01

### Added
- **design-minimal** skill — create one standalone minimal HTML page for dashboards, briefs, handouts, maps, and internal reports
  - Tailwind CDN only, system fonts, fixed desktop-oriented layout
  - No custom component CSS, responsive variants, gradients, shadows, rounded corners, icons, or external fonts
  - Includes an explicit language rule: visible UI follows the user's language, technical identifiers stay copyable
  - Bilingual docs (README.md + README.ru.md)

## [1.16.0] - 2026-05-22

### Added
- **meeting-copilot** skill — live meeting dashboard for prepare/update/close workflows
  - Creates local HTML dashboards for calls
  - Uses transcript delta processing for live updates
  - Extracts questions, topic progress, decisions, risks, action items, and follow-up drafts
  - Includes privacy rules for sanitized public exports
- **ris-draft** skill — generate one self-contained HTML page with a technical diagram in flat engineering blueprint style
  - Strict visual rules: flat, outlined, monochrome, system fonts, Tailwind v4 browser CDN, and D3 v7 CDN
  - Supports four diagram types: architecture, system flow, technical spec sheet, component map
  - Complete HTML document ready to open in a browser
  - Bilingual docs (README.md + README.ru.md, Russian default)

## [1.15.1] - 2026-03-29

### Fixed
- CHANGELOG compare links for v1.12–v1.15 and Unreleased pointer
- README.ru.md synced with English structure (tables, removed Coming Soon sections)
- Added missing paperclip-api/README.ru.md

### Removed
- Empty placeholder directories: hooks/, prompts/, workflows/

### Added
- "Never" safety section in CLAUDE.md

## [1.15.0] - 2026-03-29

### Added
- **product-data-audit** skill — deep product/business audit with interactive HTML visualization
  - 12-section report: ecosystem diagram, decision map, data systems, bottlenecks, implementation contours
  - 18-artifact checklist (OKR, CLAUDE.md, metric definitions, decision log, escalation rules)
  - Structured facts: claim + metric pills + source reference
  - 35+ English-to-Russian terminology mappings
  - Swiss Precision HTML theme (Cormorant Garamond + IBM Plex Mono)
  - Tested with 6 subagents, 2 REFACTOR rounds

### Changed
- README restructured: skills as tables, removed Coming Soon sections, simplified installation

## [1.14.0] - 2026-03-27

### Added
- **paperclip-api** skill — manage Paperclip AI agent companies via CLI and REST API
  - Full CLI reference: issues, agents, approvals, companies, context profiles
  - REST API endpoints with curl examples for all operations
  - Agent instruction files: direct markdown editing in `~/.paperclip/`
  - Recipes: create & assign tasks, switch agent language, bulk-approve hires
  - Links to official docs (docs.paperclip.ing)

## [1.13.0] - 2026-03-26

### Added
- **task-routing** skill — route issues to the correct repo via CLAUDE.md routing config
  - Reads routing patterns created by `project-init`
  - Matches task keywords to target repo
  - Checks duplicates across repos and unified project
  - Respects W-label lifecycle (never creates, only uses existing)
  - Part of Personal Corp framework: project-init → task-routing → weekly-planning/retro

### Removed
- **macos-fixer** — low value, not reusable
- **api-digest** — incomplete, references non-existent files
- **git-workflow-manager** — duplicates global CLAUDE.md rules
- **project-release** — hardcoded to this repo, release rules moved to global config
- **agent-teams** — superseded by built-in Claude Code agent capabilities
- **opencode-config** — too niche (OpenCode CLI only)
- **gemini-tmux-orchestration** — too niche, mixed language

## [1.12.0] - 2026-03-25

### Added
- **Personal Corp Framework** — a system for running a business as one person with AI agents
  - **project-init** skill — guided interview → GitHub Project + labels + CLAUDE.md config
  - **weekly-planning** skill — retro findings + backlog → prioritized outcomes with Eisenhower matrix
  - **weekly-retro** skill — structured retrospective: data gathering, founder interview, issue creation

## [1.11.0] - 2026-02-23

### Added
- **ceo-council** skill for independent strategic analysis
  - Parallel Opus sub-agents as C-level experts (CFO, CPO, CTO, etc.)
  - Auto-generates roles tailored to project domain
  - Isolation-based analysis: each expert works independently
  - Synthesis with consensus, disagreements, and decisions

## [1.10.0] - 2026-02-05

### Added
- **agent-teams** skill for orchestrating multiple autonomous agents
  - Shared task lists and direct inter-agent messaging
  - Teams vs subagents decision flowchart
  - Full lifecycle: spawn, assign, monitor, shutdown
  - Best practices for task sizing, file ownership, spawn prompts

## [1.9.0] - 2026-02-02

### Changed
- **statusline** rewritten with OAuth API rate limits
  - Shows 5-hour and weekly usage percentage (remaining)
  - Countdown timer to 5-hour limit reset
  - Cached API calls (2 min TTL)
  - Removed ccusage/bun dependency
  - Renamed from `token-counter.sh` to `statusline.sh`

## [1.8.0] - 2026-01-16

### Added
- **cc-analytics** skill for Claude Code usage statistics
  - Parse `~/.claude/history.jsonl` for prompts and projects
  - Git integration for commit counts and remote URLs
  - Terminal-style HTML report with ASCII aesthetics

## [1.7.0] - 2026-01-11

### Added
- **gh-issues** skill for GitHub Issues management via CLI
  - Full `gh issue` command reference with JSON/jq patterns
  - AI session context storage in issue comments
  - Task workflow with labels (backlog → in-progress → done)
  - Context template for seamless handoff
- **opencode-config** skill for OpenCode CLI configuration
  - Config locations and priorities
  - Custom provider setup with OpenAI-compatible APIs
  - Mode-specific model configuration
- **readme-generator** skill for human-focused README creation
  - Research-first approach with best practices
  - Project type-specific sections
  - Writing style guidelines

## [1.6.0] - 2026-01-02

### Added
- **project-release** skill for consistent release workflow
  - Pre-release validation checklist
  - Version determination rules (MINOR/PATCH)
  - Files decision matrix
  - Step-by-step release workflow
  - Post-release verification

## [1.5.1] - 2026-01-01

### Changed
- **claude-md-writer** skill updated with 2026 best practices:
  - 3-Tier Documentation System
  - Updated size limits (CLAUDE.md < 200, rules < 500)
  - Glob patterns for conditional rules
  - Memory hierarchy table
- Added README.md and README.ru.md for claude-md-writer skill

### Added
- Skill Structure requirements in CLAUDE.md
- Versioning rules in CLAUDE.md

## [1.5.0] - 2025-12-27

### Added
- **claude-md-writer** skill for creating CLAUDE.md files following Anthropic best practices
- **macos-fixer** skill for macOS diagnostics and memory optimization

## [1.4.0] - 2025-12-17

### Added
- **git-workflow-manager** skill for consistent commits, versioning, and releases
- `CHANGELOG.md` with full version history
- `CONTRIBUTING.md` with conventions and guidelines
- `.github/release.yml` for auto-generated release notes
- `.github/PULL_REQUEST_TEMPLATE.md` for PR consistency

## [1.3.0] - 2025-12-17

### Added
- **gemini-tmux-orchestration** skill for delegating tasks to Gemini CLI agent via tmux
  - Status markers for detecting Gemini state
  - Smart polling instead of fixed sleep
  - Loop detection handling
  - Custom commands support

## [1.2.1] - 2025-12-16

### Changed
- Refactored api-digest skill into multiple files (progressive disclosure)
  - `SKILL.md` — instructions with file references
  - `fetch.sh` — isolated credentials script
  - `output-template.md` — customizable output format

## [1.2.0] - 2025-12-16

### Added
- **api-digest** skill template for fetching raw API data and generating digests
  - Support for any REST API with configurable auth
  - Customizable output template
  - Zero backend LLM costs

## [1.1.0] - 2025-12-16

### Changed
- Improved context usage calculation in statusline
  - Now uses `current_usage` object for accurate tracking
  - Includes cache_creation and cache_read tokens

## [1.0.0] - 2025-12-15

### Added
- Initial release
- Custom statusline with cost tracking, context usage, git branch
- Basic repository structure

[Unreleased]: https://github.com/serejaris/personal-corp-skills/compare/v1.20.0...HEAD
[1.20.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.19.0...v1.20.0
[1.19.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.18.0...v1.19.0
[1.18.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.17.0...v1.18.0
[1.17.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.15.1...v1.17.0
[1.16.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.15.1...485a46c
[1.15.1]: https://github.com/serejaris/personal-corp-skills/compare/v1.15.0...v1.15.1
[1.15.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.14.0...v1.15.0
[1.14.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.13.0...v1.14.0
[1.13.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.12.0...v1.13.0
[1.12.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.10.0...v1.11.0
[1.10.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.5.1...v1.6.0
[1.5.1]: https://github.com/serejaris/personal-corp-skills/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/serejaris/personal-corp-skills/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/serejaris/personal-corp-skills/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/serejaris/personal-corp-skills/releases/tag/v1.0.0
