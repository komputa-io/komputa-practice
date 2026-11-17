---
title: Run a session overnight
description: Put a long session on the watch, so a timer nudges it when it goes idle and alerts you when it needs you.
sidebar:
  order: 4
---

Use this guide when a session must keep working while nobody watches it, for example overnight. The watcher nudges the session when it goes idle with work left, hands it over to a fresh session when its context grows large, and alerts you once when only you can go on. [The watcher](/explanation/the-watcher) explains what one pass does and why it is safe to leave running.

## Before you start

- The session runs in an `hc` terminal (herdr). The watcher reads and nudges sessions through `hc`.
- Linux with systemd user timers.
- The program has its go and its defaults. See [Run large work as a program](/guides/large-work).

## Steps

1. **Install the timer once.** It runs the watcher from the release export, so run the Sitrep Live workstation install first (see [Running services](/explanation/running-services)). Then, from the practice clone:

   ```sh
   cd ~/Code/komputa-practice
   watcher/watcherctl install            # a dry run: it prints what it would write
   watcher/watcherctl install --apply    # writes practice-watch.service and .timer, and turns on linger
   watcher/watcherctl enable             # a pass every 5 minutes, now and after each login
   ```

2. **Check the session is on the watch.** Each pass puts every top-level agent session in `hc` on the watch by itself and marks it the lead (`lead=1`), unless it is labelled `watch=off`. To put one back after `off`, run this from inside its own `hc` terminal, or name the terminal:

   ```sh
   ~/Code/komputa-practice/watcher/practice-watch on       # or: ... on t7
   ~/Code/komputa-practice/watcher/practice-watch status   # what is watched
   ```

3. **Leave it.** Each pass reads every terminal labelled `watch=on`. A session that has gone idle with work left gets one nudge. A session that is blocked, out of nudges or ended raises one alert. When a session's context passes 250k tokens, it writes a handoff and starts a fresh session from it, in the same tab. The fresh session takes over the watch and the `lead=1` label. The old session comes off the watch, and the watcher closes it after 3 idle hours. What it last said stays in its transcript.

4. **In the morning, find the lead and ask it what happened.** After a night of handovers, the lead is often not the session you started:

   ```sh
   hc ls --label lead=1    # the current lead
   ```

   Ask that session what ran overnight and what waits on you. Then take it off the watch:

   ```sh
   ~/Code/komputa-practice/watcher/practice-watch off <lead terminal>
   ```

## Check it worked

```sh
watcher/watcherctl status
```

It shows the timer, its last passes and the watched sessions.

## Stop or remove it

```sh
watcher/watcherctl disable            # stops the timer
watcher/watcherctl uninstall --apply  # removes the service and the timer
```

## Next steps

- [The watcher](/explanation/the-watcher): what one pass does, its settings, and why it never types over you.
- [Run large work as a program](/guides/large-work): plans, handoffs and the go.
