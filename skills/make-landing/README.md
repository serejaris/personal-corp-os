# make-landing

[![en](https://img.shields.io/badge/lang-en-blue.svg)](README.md)
[![ru](https://img.shields.io/badge/lang-ru-green.svg)](README.ru.md)

Builds several distinct landing page, hero, cover or slide designs and lets you choose from working previews. Each variant gets its own visual reference and its own author. The author writes a complete concept in design.md and freezes it before any code, with a UTC timestamp and a SHA-256 hash. Every variant is checked in a browser or through export.

```text
/make-landing
```

Or ask for “design options”, “several landing variants to choose from”, or a “redesign”. Say what you are designing (landing page, cover, slides) and how many variants you want; if you skip the number, the skill asks.

1. Locks the shared content in a brief and gives each variant a different reference through a direction matrix: a table that sets each variant's direction.
2. Assigns one author per variant: Codex CLI by default, a subagent if Codex CLI is unavailable.
3. The author writes and freezes the full concept, then builds the variant, checks it and takes screenshots.
4. Opens a gallery next to the variants. Each variant's images arrive in chat as soon as it is done.
5. You pick the winners. A second round mixes their strongest elements, then the skill moves your pick into the main version of the project.

Original concepts stay unchanged; later decisions go into amendments. Web screenshots default to 1440×900, and narrow layouts are checked separately. Covers and slides use the size you asked for. Which build and QA steps can run depends on whether the CLI and the project's preview and export tools are available; whatever could not run goes into the report.

To freeze a concept and verify the freeze, run these from the skill directory once the variant folder has a design.md:

```sh
python3 scripts/freeze_concept.py freeze <variant-directory>
python3 scripts/freeze_concept.py verify <variant-directory>
```

Install through the repository's [plugin instructions](../../README.md), or copy the whole make-landing folder into your harness's skills directory. Bundled: the workflow in [SKILL.md](SKILL.md) (in Russian), the [author role](references/author.md) and the [design template](references/design-template.md). Maintained in this repository under the [MIT license](../../LICENSE). Report security issues through [SECURITY.md](../../SECURITY.md).
