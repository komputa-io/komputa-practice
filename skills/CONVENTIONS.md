# Conventions for the house skills

Each skill here is a folder with a `SKILL.md` in the Agent Skills format.
A house skill holds our own rules: `house-architecture`, `house-dotnet` and the
rest. Every one follows these rules:

- **Precedence is general.** It says "where any other installed skill says
  otherwise, this skill wins", and "a repo's `CLAUDE.md` or an ADR wins over
  this skill for that repo". It never lists which skills it beats.
- **Each rule is complete on its own.** Where another skill covers a principle,
  state the principle in one line, then point at the skill. The rule must still
  hold when that skill is not installed.
- **Name another skill only as a pointer or a difference**, written in
  backticks as `plugin:skill` (for example `pstack:no-comments`) or
  `house-<name>`. A difference names what the other skill's examples show and
  what to write instead.
- **Check that each named skill is still installed** before you push a house
  skill, and after a plugin update.
- **A rule that holds for every caller goes in `SKILL.md`, worded for every
  caller.** An agent opens a reference only when its task looks like that
  reference's topic, so a general rule written in `endpoints.md` never reaches
  a page, a job or a CLI. A reference holds the mechanics for one context.
- **No process steps.** The workflow skill owns how a design, fix or review
  proceeds. A house skill gives only the rules that apply at that moment.
- Do not start a line with "Override:". The skillshare audit reads it as a
  prompt injection.

**When a language gets a house skill.** Only when both are true:

1. We write it in at least one active repo.
2. It has about five or more rules of our own that installed skills and
   linters do not already give, each from a real correction or incident.

Until then, `house-architecture` and the language's standard tools carry it.
The first Rust project, for example, runs on `house-architecture`, clippy and
rustfmt; after it, count the rules it produced. A language used in one repo
only gets a project-scoped skill (`project-skills.tsv`), not a global one.
Frameworks and libraries (React, Next.js, EF Core, Aspire) are sections in
their language's house skill, never skills of their own. Where a vendor ships
an official skill, install it and keep only our differences in the house skill.
