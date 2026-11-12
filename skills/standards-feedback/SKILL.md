---
name: standards-feedback
description: "Turn review findings into changes to the house standards. Use after reviewing a PR or at the end of a slice, when a finding might be a gap in the rules and not only in the code: 'what should change in the standards', 'should this go in the house rules', 'feed this back', 'is this project specific or a standards problem', 'the agent did X again'. For each finding it decides where the fix belongs (the repo, a house skill, or a guard in the project template) and opens the PRs. Works with or without pstack. Not for reviewing the code itself (house-architecture, 'When you review'), or for lessons about how an agent session ran (pstack:reflect)."
metadata:
  author: "Komputa"
  version: "1.0"
---

# Standards feedback

A finding that a house rule should have prevented is a defect in the
standards, not only in the code. Fix it where it starts, so the next repo and
the next agent do not repeat it.

## 1. List the findings

Take them from the operator's review, the PR's review comments, the fix
rounds, and the gate and CI failures of the change. One line each: what was
wrong, and the file and line where it shows.

## 2. Sort each finding

Read the house skills that cover it (`house-architecture`, the language's
`house-*`, `house-otel`, `house-delivery`) and the repo's `CLAUDE.md`. Then put
the finding in exactly one row.

| Kind | Sign | Where the fix goes |
|---|---|---|
| Project | Only this repo's facts or choices are wrong | A fix or an issue in the repo. No standards change |
| Missing | No rule covers it | A rule in the house skill, in komputa-practice `skills/` |
| Unclear or contradicting | Two rules disagree, or one reads two ways | One rule, reworded, in komputa-practice `skills/`; delete the other wording |
| Too deep | The rule is only in a `references/` file, or worded for one kind of caller | Move it into `SKILL.md`, worded for every caller (`skills/CONVENTIONS.md`) |
| Not enforced | The rule exists, the agent read it, and broke it anyway | A guard in the project template (komputa-practice `template/`): a build check, a gate step or a lint rule |
| Missing input | The rule needs a fact the repo never declared (for example the project profile) | A question in the template (`copier.yml`) and a line in the seeded `CLAUDE.md` |

Prefer a guard to more words. A rule that a tool can check gets the check, and
the rule then names it. More text is the fix only when no tool can check it.

## 3. Propose, then open the PRs

Show the operator one table: each finding, its kind, the change, and the repo.
Say which findings are project only, so nothing silently changes the
standards. Then open one PR per repo, on a branch from `main`, through the
repo's forge CLI, named in its `CLAUDE.md`:

- komputa-practice `skills/`: the house skill wording. Each rule complete on its
  own, with no framework named (`skills/CONVENTIONS.md`).
- komputa-practice `template/`: the guard, with a test that it fails on the mistake and
  passes on the fix, and the repo's own rendered copy kept in step.

Each PR's "Why" names the repo and the finding that showed the gap. Merge only
on the operator's word.

## 4. Close the loop

After the merge: pull, run `skillshare sync`, and run `copier update` in the
repo that showed the gap, so the guard holds there too. Tell the agent still
working in that repo what changed.

## Which repo owns what

komputa-practice holds the rules (`skills/`) and the project template
(`template/`), which connects a repo to them and holds the guards. A repo's
`CLAUDE.md` holds its own facts. The machine's own config repo holds the
machine. `site/explanation/how-it-fits.md` is the map.
