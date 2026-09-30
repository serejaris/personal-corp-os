# make-landing

[![en](https://img.shields.io/badge/lang-en-blue.svg)](README.md)
[![ru](https://img.shields.io/badge/lang-ru-green.svg)](README.ru.md)

Create several distinct landing, hero, cover or slide designs and choose from working previews. Each variant has its own visual reference and author, a complete design.md frozen with UTC and SHA-256 before code, and browser or export evidence.

```text
/make-landing
```

Or ask for “design options”, “several landing variants to choose from”, or a “redesign”. Specify the surface and number of variants; otherwise the skill asks for the count.

1. Lock the shared content and assign distinct references through a direction matrix.
2. Run one author per variant using Codex CLI by default, with subagents as fallback.
3. Write and freeze the full concept, implement, verify and capture the result.
4. Open the adjacent gallery and receive images in chat as each variant finishes.
5. Choose winners, mix their strongest elements in a second round, then move your selection into the project canon.

The human makes the selection. Original concepts remain unchanged; amendments record later decisions. Web captures default to 1440×900, with separate narrow-layout checks. Covers and slides use the requested output dimensions. CLI availability and the project's preview/export tools determine which execution and QA steps can run; record any limitations.

From this skill directory, with a variant folder containing design.md:

```sh
python3 scripts/freeze_concept.py freeze <variant-directory>
python3 scripts/freeze_concept.py verify <variant-directory>
```

Install through the repository's [plugin instructions](../../README.md), or copy the entire make-landing folder into your harness's skills directory. The Russian workflow is in [SKILL.md](SKILL.md); the [author role](references/author.md) and [design template](references/design-template.md) are bundled. Maintained in this repository under the [MIT license](../../LICENSE); report security concerns through [SECURITY.md](../../SECURITY.md).
