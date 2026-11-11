# Archive

This folder holds work that the practice no longer runs. `scripts/check.sh` skips it. Only the scrub check reads it,
because that check reads every file in the repo.

## herdr (archived 10 November 2026)

`herdr/scripts/` and `herdr/units/` kept unattended leads and workers alive in Herdr:

- the launchers (`start-lead`, `start-worker`);
- the watchers (`budget-watch`, `stall-watch`, `stack-watch`, `watch-tick`);
- the wait and report helpers (`wait-event`, `safe-send`, `finish-worker`, `worker-report`);
- the resume service (`resume-tick`, `resume-check`, `resume-program`) and two systemd user timers.

`herdr/scripts/tests/` holds their tests. `herdr/waiting-and-watchers.md` is the docs-site page that described them.

Why: the operator now works in one session, so none of these scripts ran. Their tests waited on real clocks, and the
pytest step took about 150 seconds of each check (issue #86).

The files are as they were on `main` at `4618e11`: moved, not edited. Each script finds the others by its own folder,
so they still run from here.

- Run the tests: `uv run --no-project --with pytest python -m pytest -q archive/herdr/scripts/tests`.
- Bring a script back when a measurement shows that it helps more than it costs. Move it to `skills/herdr/scripts/`
  with `git mv`, add the pytest step to `scripts/check.sh` again, and restore the lines that name it in
  `skills/herdr/SKILL.md` and `rules/working-rules.md` from the commit before this move.
- `herdr/scripts/check-tools-only` is the one script that a live document names (`docs/tools-only.md`). It has no part
  in running workers.
- The branch `fix/86-test-time` holds an unmerged change that makes these tests wait on events, not on real time.

Do not delete this folder before 10 February 2027, and then only when the operator says so.
