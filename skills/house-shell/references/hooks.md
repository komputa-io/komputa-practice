# Claude Code and Codex hooks

The exit codes are in [bash.md](bash.md) (a hook never exits 2 for misuse), and
proof that a test harness can go red is in [gate.md](gate.md). Each rule here
was measured on a real session.

## Find the target from the command, then from `cwd`

A PreToolUse payload's `cwd` is the shell's folder before the command runs. It
follows a `cd` from an earlier call, but not one inside this command, so for
`cd X && git ...` or `git -C X ...` judge `X`, and use `cwd` only when the
command names no folder. Evidence: Claude Code 2.1.316, 2 Nov 2026.

## To change a tool call, deny it

PreToolUse `additionalContext` reaches the model next to the tool result, after
the call has run, and is capped at 10,000 characters. Only a deny acts before
the call. Evidence: Claude Code 2.1.316, 2 Nov 2026.

## A gate that cannot start fails open

A hook without its exec bit, or with a missing file, exits 126 or 127 as a
non-blocking error, and the tool call goes ahead. Set `"onFailure": "block"` on
every gate, and in tests run each hook by its path, never as `bash hook.sh`.
Evidence: Claude Code 2.1.316, 2 Nov 2026.

## A delete gate lets a session clear its own scratchpad

An `rm -rf` gate passes a target whose real path is inside
`<tmp>/claude-<uid>/<transcript-folder>/<session_id>/scratchpad`, built from
the payload's `session_id` and `transcript_path`, and refuses another session's
scratchpad. A gate that refuses this routine clean-up teaches agents to take
its exception. Evidence: incident 28 Sep 2026; layout confirmed on Claude Code
2.1.316, 2 Nov 2026.

## Under Codex, an edit is `apply_patch` with the patch in `tool_input.command`

`Write` and `Edit` matchers fire on it, but `content` and `new_string` are
empty, so a write gate parses the patch (`*** Add File:` and
`*** Update File:` headers) and judges only the `+` lines. Codex skips a new or
changed hook until it is trusted, so trust it before you count on it. Evidence:
Codex CLI 0.166.0, 2 Nov 2026.
