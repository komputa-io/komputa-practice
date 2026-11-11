---
title: The quality funnel
description: Five layers that catch a mistake, and the rule to catch each one at the highest layer.
---

![A funnel of five layers that catch mistakes: codebase, static analysis, verification, prose and human review, with an arrow that moves each lesson up.](/figures/quality-funnel.png)

Catch each mistake as high in the funnel as you can. A higher layer works when nobody reads it. A lower layer depends on a reader.

| Layer | What it is | Why it holds |
|---|---|---|
| 1. Codebase | Good API design, architecture, refactoring. | The mistake cannot be written. |
| 2. Static analysis | Lints, types, compilers, tests, CI, hooks. | A machine refuses the mistake. |
| 3. Verification | Formal proofs and runs of the real artifact. | A run shows that the change works. |
| 4. Prose | Rules, skills, `AGENTS.md`. | Nothing fails when an agent skips them, so keep them for judgment calls. |
| 5. Human review | The operator's time. | It is the smallest layer. Keep it for what only a person can decide. |

## The rule

When a mistake gets through, or the operator corrects an agent:

1. Fix the mistake.
2. Add its defence at the highest layer that can hold it.

Before you add a rule or a skill line, try each layer above prose. Say which layer you chose and why no higher layer can hold it.

Before you ask the operator to review, run every check from the layers above. Do not hand over a mistake that a machine could have caught.

The [rules page](/reference/rules) has a table of what holds each rule. A row in that table is a rule that moved up the funnel.
