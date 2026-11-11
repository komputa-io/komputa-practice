# Context economics: where the tokens go when agents run as workers

This page records what we measured on one real project, what we learned from it, and what we changed in this practice because of it. The rules themselves live in `rules/working-rules.md` and `skills/herdr/SKILL.md`. This page explains why they say what they say.

## The project

A desktop and web app, built over six days by a lead agent session that wrote briefs and ran hc workers in Herdr panes. The work had milestones (a layout engine, a file round trip, a document model), then a cloud service, a live co-editing core and a browser head. Opus did the algorithms, parsers, security and fix work. Sonnet did the feature and UI slices. Every worker ran with `--effort high`.

We measured every session from its Claude Code transcript (`~/.claude/projects/<project>*/*.jsonl`): each assistant message carries a `usage` block with `input_tokens`, `output_tokens`, `cache_read_input_tokens` and `cache_creation_input_tokens`.

## What we measured

| Who | Model | Turns | Cache reads | Output | Average context per turn |
|---|---|---|---|---|---|
| Workers | Opus | 17,907 | 3,510 M | 19.6 M | 196k |
| Workers | Sonnet | 5,195 | 786 M | 4.6 M | 151k |
| Lead | Opus | 4,590 | 1,299 M | 3.3 M | 283k |

- 155 sessions. 42 of them ended above 280k context.
- About 5.6 billion tokens were read again from the cache. About 28 million tokens were output. Output is under 1% of the tokens processed.

## What we learned

1. **The cost is the context that each turn reads again, not the output.** Every turn sends the whole conversation again. A turn at 280k costs about as much to read as a turn at 30k costs fourteen times over. So the size of the context that a session carries decides its cost far more than how much it writes.
2. **Effort is not the lever.** Effort changes how much a model thinks and writes. That is the small part of the bill. A higher effort also fills the context faster, which makes the expensive part bigger and makes a worker reach its cap sooner. We kept `high`.
3. **Big briefs cost twice.** A brief with four or more deliverables drove a worker to the 300k cap. It stopped with `PARTIAL`, and a second worker started by reading the first worker's report and the code again. A brief sized to finish under about 200k avoids both the high context and the second start.
4. **The lead was the outlier.** A worker has a brief and a cap, so it ends. The lead had neither. It ran for many hours, so its average context per turn (283k) was the highest of all, and it was about a quarter of all cache reads.
5. **Waiting in the foreground is expensive.** The lead waited for workers with `hc wait --children any --timeout 580` in a loop, and for CI with check-ins. `hc wait` returns on every timeout and on every status change (a worker going idle while its tests run counts). Each return was a lead turn, and each turn read about 280k again, to learn that nothing had happened.
6. **The model split was right.** The slices that went to Opus (a network-facing parser, a convergence algorithm, auth, a live server room) found and fixed real high-severity defects before anything went live. The Sonnet slices passed in one part or stopped only at the cap. Keep strong models where a mistake is expensive, and use the cheaper model for features.

## What we changed

| Change | Where | How it works |
|---|---|---|
| Size briefs to finish under about 200k: about two deliverables, or three only when each one is small; split bigger jobs into parts on one branch | `rules/working-rules.md`, `skills/herdr/SKILL.md` "Brief" | The lead writes part a, merges or stacks it, then writes part b from part a's report. 300k stays as the hard cap. |
| A budget for the lead: write a handoff at about 250k | `rules/working-rules.md`; `skills/herdr/scripts/budget-watch` | `budget-watch` now also reads the lead's own `ctx` from its screen (`hc read --lines 8 "$HC_TERMINAL_ID"`) and sends the lead one message when it passes the lead cap (third argument, default 250). The lead writes a handoff at the next quiet point; a fresh lead starts near 30k. |
| Wait out of context | `skills/herdr/scripts/wait-event`; `skills/herdr/SKILL.md` "Wait" | The lead runs `wait-event` as a background command. It loops `hc wait` itself and ends with one line only when a worker sends a message, exits, errors or is blocked on a prompt. Timeouts and plain status changes do not end it. `--until '<command>' --every <s>` also ends it when a command exits 0, for example a CI check. The lead wakes once per real event. |

`wait-event` reads the JSON that `hc wait` prints: a top-level `from` is a message; a child with an `exit_code`, a `blocked` or `error` status, or an exit reason is an event. With no live child, `hc wait` returns at once, so the script sleeps for `--every` seconds before it asks again. Its tests (`skills/herdr/scripts/tests/test_wait_event.py`) play a sequence of `hc wait` answers through a stub `hc` and check where it stops.

## How we judge the two-deliverable size

The first version of the rule said two or three deliverables. On the day it went in, the lead saw briefs with three full deliverables reach the 300k cap, and it moved to about two in its next briefs. A worker costs about 100k before it builds anything: 57k at its first turn and about 100k by its tenth. So each split also has a cost, and too small a brief wastes context too.

The baseline is the 28 worker sessions that started after the lead moved to about two. It is not a clean test of two deliverables: some of those briefs still held three to six work items.

| Measure | Baseline (28 sessions) |
|---|---|
| Median peak context | 272k |
| Sessions that peaked at 280k or more | 9 (32%) |
| Sessions that reported `PARTIAL` at the context cap | 7 (25%) |
| Brief under 4 KB: sessions at 280k or more | 0 of 12 |
| Brief of 4 KB or more: sessions at 280k or more | 9 of 16 |

Judge the rule after the next 20 worker sessions on a project that starts with it. Count the work items in each brief first, and leave out a brief that broke the rule.

- **Keep it** when 2 or fewer of the 20 report `PARTIAL` at the context cap, and 3 or fewer peak at 280k or more.
- **Go back to two or three** when the median peak is under 150k and one job needs more workers than the same size of job did before. The briefs are then too small, and the extra start-up cost is the waste.
- **Replace it** when the briefs keep to the rule and the cap rate stays near 25%. The count is then the wrong measure. Look next at brief size and at the start-up context.

## How to measure your own project

Sum the `usage` blocks of your sessions. A short Python script is enough:

```python
import glob, json

reads = out = turns = 0
for f in glob.glob("<home>/.claude/projects/<project-folder>*/*.jsonl"):
    for line in open(f, errors="ignore"):
        try:
            m = json.loads(line).get("message") or {}
        except ValueError:
            continue
        u = m.get("usage") if isinstance(m, dict) else None
        if u:
            turns += 1
            reads += u.get("cache_read_input_tokens", 0)
            out += u.get("output_tokens", 0)
print(turns, reads / turns, out)  # turns, average context per turn, output
```

Split it by directory (the lead's project folder against the worktrees' folders) and by `message.model` to see who carries the context. The number to watch is the average context per turn.
