---
title: The watcher
description: How one small timer keeps a long agent session going while nobody watches it, for example overnight.
---

A long session sometimes stops with work left: it ends a turn on a question,
or waits out a usage limit, and nobody is there to say "carry on". The
watcher is the one process that notices. It is `watcher/practice-watch`, run
every 5 minutes by a systemd user timer.

There is one watcher, and it stays one. When we need to watch for another
event, it becomes one more case in the same pass, not a second script or a
second timer.

## Use it

To install it and put a session on the watch, follow [Run a session overnight](/guides/overnight).

## What one pass does

The pass reads each terminal that carries the label `watch=on` from `hc`,
and does one thing with each.

| The session is | The pass |
|---|---|
| working | does nothing |
| idle or done for less than 30 minutes | does nothing |
| idle or done for longer | sends a nudge |
| blocked on a prompt | alerts you, once |
| out of nudges (12) | alerts you, once, and stops nudging |
| ended | alerts you, once |
| live, not blocked, with a context past 250k | asks it, once, for a handoff and a handover (in place of a nudge) |

A nudge is one message, typed into the session through `hc send`:

> [practice-watch] This session has been idle for 40 minutes, and it is on the
> watch for unattended work (nudge 1 of 12). If work remains, carry on with the
> plan: take the default on any reversible question and say which one you
> took. If only the operator can decide what comes next, say why and run: hc
> label t7 watch=waits. If the work is finished, run: hc label t7 watch=

So the session answers for itself. `watch=waits` holds the nudges until you
run `practice-watch on` again; an empty `watch=` takes it off the watch.

An alert is a line in the journal (`journalctl --user -u
practice-watch.service`). Set `WATCH_ALERT_CMD` to also send it somewhere you
will see it: the command gets the text as its one argument.

## Settings

The service reads `~/.config/practice-watch.env` when it exists:

| Setting | Default | What it sets |
|---|---|---|
| `WATCH_QUIET_MIN` | 30 | Minutes idle before a nudge, and so the time between nudges |
| `WATCH_MAX_NUDGES` | 12 | Nudges before the watcher gives up and alerts. `practice-watch on` resets the count |
| `WATCH_ALERT_CMD` | none | A command that gets each alert as `$1` |
| `WATCH_CALL_TIMEOUT` | 30 | Seconds for each `hc` call and the alert command; a send gets four times that |

With the defaults, a session that waits out a usage limit is nudged every
half hour for six hours, then you hear about it.

## Why it is safe to leave running

- **It keeps no files.** The watch, the nudge count and the last alert are
  labels on the session's own `hc` terminal, so they end with the terminal.
- **It never types over you.** `hc send` waits while a person has a
  half-typed message in the box, and it never types into a blocked prompt.
- **It tells you once.** Each alert is keyed on the state and the time it
  began, so a session blocked all night is one alert, not a hundred.
- **It gives up.** After `WATCH_MAX_NUDGES` nudges it stops and tells you.
  A nudge that does not go through is not counted.
- **It decides nothing when `hc` is down.** The pass prints one line and
  waits for the next one.
- **Two passes never overlap.** One `flock` holds the pass, and each call
  has a timeout.
- **A dry run is the default.** `practice-watch pass` prints what it would
  do; only the timer passes `--apply`.

## Handover

When a session's context passes 250k (`WATCH_CTX_K`), the pass asks it to
write a handoff at its next quiet point and then run:

```sh
practice-watch handover <handoff file> <terminal> --apply
```

That starts a fresh session in the same folder, space and tab, with the same
`claude` command and the handoff as its first message, and puts it on the
watch. The old session comes off the watch and stays open; close it when you
choose. Without `--apply`, `handover` prints what it would do.

## Where it came from

Until 10 November 2026 the practice ran unattended leads and workers, and
kept them alive with two timers: `resume-tick`, which started a new lead
from its handoff when the old one went quiet, and `watch-tick`, which told
each lead about green pull requests and idle workers. Both are in
`archive/herdr/`. The watcher keeps their best rules: tell each finding
once, never send into a half-typed message, cap the tries, wait when `hc`
does not answer, never overlap, and time out every call. It drops what the
one-session practice does not need: launch records, program stores and
restarting a lead.

The tests are `watcher/practice-watch.test.sh`. `scripts/check.sh` runs them
with the rest.
