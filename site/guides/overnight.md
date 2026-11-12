---
title: Run a session overnight
description: Put a long session on the watch, so a timer nudges it when it goes idle and alerts you when it needs you.
sidebar:
  order: 4
---

Use this guide when a session must keep working while nobody watches it, for example overnight. The watcher nudges the session when it goes idle with work left, asks it for a handoff when its context grows large, and alerts you once when only you can go on. [The watcher](/explanation/the-watcher) explains what one pass does and why it is safe to leave running.

## Before you start

- The session runs in an `hc` terminal (herdr). The watcher reads and nudges sessions through `hc`.
- Linux with systemd user timers.
- The program has its go and its defaults. See [Run large work as a program](/guides/large-work).

## Steps

1. **Install the timer once.** From the practice clone:

   ```sh
   cd ~/Code/komputa-practice
   watcher/watcherctl install            # a dry run: it prints what it would write
   watcher/watcherctl install --apply    # writes practice-watch.service and .timer
   watcher/watcherctl enable             # a pass every 5 minutes, now and after each login
   ```

2. **Put the session on the watch.** Run this from inside the session's own `hc` terminal, or name the terminal:

   ```sh
   ~/Code/komputa-practice/watcher/practice-watch on       # or: ... on t7
   ~/Code/komputa-practice/watcher/practice-watch status   # what is watched
   ```

3. **Leave it.** Each pass reads every terminal labelled `watch=on`. A session that has gone idle with work left gets one nudge. A session that is blocked, out of nudges or ended raises one alert.

4. **In the morning, take it off the watch:**

   ```sh
   ~/Code/komputa-practice/watcher/practice-watch off
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
