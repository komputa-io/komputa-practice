#!/usr/bin/env python3
"""The judge behind hooks/block-test-weakening.sh. It reads a Claude Code PreToolUse payload on stdin.

It refuses (exit 2, one BLOCKED line on stderr) a call that deletes or weakens a test (issue #77).
Held:
  - Bash, delete: `rm`, `git rm`, `unlink`, `shred`, `find -delete`, `find -exec rm`; `mv` or `git mv` of a
    test path away (a rename to a new test path is not away). HERDR_TEST_PRUNE=1 lets these through.
  - Bash, overwrite or edit in place: `truncate`; a redirection that truncates an existing test file (`>`, `: >`,
    `cat /dev/null >`, `>|`, `&>`, `2>`; `>>` stays allowed); `cp`, `mv` or `git mv` onto an existing test file;
    `tee` without `-a`; `sed -i`; `perl -i`; `git checkout -- <test>`; `git restore <test>` (`--staged` alone is
    fine). HERDR_TEST_PRUNE=1 does not let these through, because the new content can hold a skip.
  - Write, Edit and MultiEdit on a test file: an empty result; a rise in skip or xfail markers or in commented
    asserts. A Write is compared with the file's current text, and a new file with a marker counts as a rise.
    HERDR_TEST_PRUNE=1 lets an empty result through, never a skip.
  - `$(...)`, a backtick, `bash -c` and `cd` are followed. The command text is never run.
NOT held, because text cannot decide them: `xargs rm`, `rm $VAR`, `rm $(echo path)`, `eval`,
`python -c "os.remove(...)"`, `rsync --delete`, `rm -rf .`, `rm -rf *`, `git clean`, a hard `git reset`,
`git checkout -- .` (these remove tests as a side effect); an assert changed to `assert True`, a deleted assert
line, a test file rewritten to one trivial test, `if False:` around a test; a skip set in a config file or
with `pytest.importorskip`; a new test file made by a redirection or `tee` (its content is not visible).
The reviewer template's break-the-behaviour check is the layer for those.
A test path is a path with a `tests` folder, or a file named `test_*`, `*_test.*`, `*.test.*` or `*.spec.*`
(any letter case), by its own name or by the real path behind a symlink. A Bash command may touch a path that
is under a `__pycache__`, `.pytest_cache`, `node_modules`, `build` or `dist` folder, a `*.pyc`, `*.log` or
`*.txt` file, or a path outside the git tree of the call.
A value of HERDR_TEST_PRUNE set inside the command text does not count: the gate reads its own environment.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import shlex
import sys
from pathlib import Path

TEST_NAMES = ("test_*", "*_test.*", "*.test.*", "*.spec.*")
SKIP_DIRS = {"__pycache__", ".pytest_cache", "node_modules", "build", "dist"}
JUNK_SUFFIXES = (".pyc", ".log", ".txt")
SEGMENT_BREAKS = {";", "&&", "||", "|", "&", "\n", "(", ")", ";;", "|&"}
WRAPPERS = {"sudo", "env", "command", "nohup", "exec", "time", "nice", "setsid", "builtin", "doas"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
DELETERS = {"rm", "unlink", "shred"}
SKIP = re.compile(
    r"@?pytest\.mark\.(?:skip|skipif|xfail)\b|\bpytest\.(?:skip|xfail)\(|\bunittest\.skip\w*"
    r"|\bself\.skipTest\(|\bxfail\b|\.skip\(|\.skipIf\(|\.todo\(|\bx(?:it|describe|test)\("
    r"|\bt\.Skip(?:f|Now)?\(|#\[ignore\]|@Disabled\b|@Ignore\b|\[(?:Skip|Ignore)\b"
)
COMMENTED_ASSERT = re.compile(
    r"^\s*(?:#|//|--)\s*(?:assert\b|expect\(|self\.assert\w*|Assert\.\w+|require\.\w+|t\.(?:Fatal|Error)\w*)",
    re.MULTILINE,
)
INNER = re.compile(r"\$\(([^()]*)\)|`([^`]*)`")
SCRIPT_FLAG = re.compile(r"^-[A-Za-z]*[eEf]$|^--(?:expression|file)$")
IN_PLACE = re.compile(r"^-[A-Za-z]*i|^--in-place")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([^\s'\"<>;&|()]+)\1")
MAX_FILE = 5_000_000
NEWLINE = "\n"
ROOT = ""

Hit = tuple[str, str]  # ("delete" or "write", the path the command touches)


def refuse(kind: str, what: str, advice: str) -> None:
    what = re.sub(r"\s+", " ", what)
    what = what[:117] + "..." if len(what) > 120 else what
    print(f"BLOCKED [test gate: {kind}]: {what}. {advice}", file=sys.stderr)
    sys.exit(2)


DELETE_ADVICE = (
    "A worker never deletes or weakens a test to get green: fix the code, or ask the lead. A reviewed prune "
    "starts the pruning worker with HERDR_TEST_PRUNE=1."
)
WRITE_ADVICE = (
    "A worker changes a test with the Edit tool, which checks for a skip or an emptied file: fix the code, "
    "or ask the lead."
)
SKIP_ADVICE = "A worker never skips or comments out a test to get green: fix the code or the test."


def prune() -> bool:
    return os.environ.get("HERDR_TEST_PRUNE") == "1"


def split_path(path: str) -> list[str]:
    return [p.lower() for p in path.replace("\\", "/").split("/") if p]


def is_test_name(path: str) -> bool:
    parts = split_path(path)
    return bool(parts) and (
        "tests" in parts[:-1] or any(fnmatch.fnmatchcase(parts[-1], n) for n in TEST_NAMES)
    )


def is_test_target(path: str) -> bool:
    """For a delete: the folder `tests` itself counts too."""
    return is_test_name(path) or "tests" in split_path(path)


def tree_root(cwd: str) -> str:
    here = Path(os.path.realpath(cwd))
    for d in (here, *here.parents):
        if (d / ".git").exists():
            return str(d)
    return str(here)


def exempt(path: str) -> bool:
    """A Bash command may touch these: build output, caches, notes, and anything outside the git tree."""
    p = os.path.normpath(path)
    if p.lower().endswith(JUNK_SUFFIXES):
        return True
    if os.path.isabs(p):
        rel = os.path.relpath(p, ROOT) if ROOT else p
        if rel == ".." or rel.startswith(".." + os.sep):
            return True
    else:
        rel = p
    return any(c in SKIP_DIRS for c in rel.replace("\\", "/").split("/"))


def judge_path(word: str, cwd: str, whole: bool) -> bool:
    joined = os.path.normpath(os.path.join(cwd, word))
    check = is_test_target if whole else is_test_name
    return any(check(p) and not exempt(p) for p in (joined, os.path.realpath(joined)))


def existing_test_file(word: str, cwd: str) -> bool:
    joined = os.path.normpath(os.path.join(cwd, word))
    return judge_path(word, cwd, False) and os.path.isfile(joined)


def positionals(words: list[str]) -> list[str]:
    out: list[str] = []
    options = True
    for w in words:
        if options and w == "--":
            options = False
        elif options and w.startswith("-") and w != "-":
            continue
        else:
            out.append(w)
    return out


def delete_targets(words: list[str]) -> list[str]:
    return positionals(words)


def first_match(targets: list[str], cwd: str, test) -> str:
    return next((t for t in targets if test(t, cwd)), "")


def whole_test(word: str, cwd: str) -> bool:
    return judge_path(word, cwd, True)


def file_test(word: str, cwd: str) -> bool:
    return judge_path(word, cwd, False)


def move_hit(words: list[str], cwd: str, pruning: bool) -> Hit | None:
    """`mv` and `git mv`: onto an existing test file always counts; away from a test counts unless pruning."""
    args = positionals(words)
    if len(args) < 2:
        return None
    *sources, dest = args
    if existing_test_file(dest, cwd):
        return ("write", dest)
    if pruning:
        return None
    for s in sources:
        if whole_test(s, cwd) and not (
            file_test(dest, cwd) and not os.path.exists(os.path.join(cwd, dest))
        ):
            return ("delete", s)
    return None


def in_place_files(cmd: str, words: list[str]) -> list[str]:
    """The files of `sed -i` or `perl -i`, or none when the command does not edit in place."""
    flags = [w for w in words if w.startswith("-") and w != "--"]
    if not any(IN_PLACE.match(f) for f in flags):
        return []
    files: list[str] = []
    skip = False
    scripted = False
    options = True
    for w in words:
        if skip:
            skip = False
        elif options and w == "--":
            options = False
        elif options and w.startswith("-") and w != "-":
            if SCRIPT_FLAG.match(w):
                skip = "=" not in w
                scripted = True
        else:
            files.append(w)
    if cmd == "sed" and not scripted and files:
        files = files[1:]
    return files


def git_hit(rest: list[str], cwd: str, pruning: bool) -> Hit | None:
    while rest and rest[0].startswith("-"):
        if rest[0] == "-C" and len(rest) > 1:
            cwd = os.path.normpath(os.path.join(cwd, rest[1]))
            rest = rest[2:]
        elif rest[0] == "-c" and len(rest) > 1:
            rest = rest[2:]
        else:
            rest = rest[1:]
    if not rest:
        return None
    sub, args = rest[0], rest[1:]
    if sub == "rm":
        if pruning:
            return None
        t = first_match(delete_targets(args), cwd, whole_test)
        return ("delete", t) if t else None
    if sub == "mv":
        return move_hit(args, cwd, pruning)
    if sub == "checkout" and "--" in args:
        t = first_match(args[args.index("--") + 1 :], cwd, whole_test)
        return ("write", t) if t else None
    if sub == "restore":
        staged_only = any(a in ("--staged", "-S") for a in args) and not any(
            a in ("--worktree", "-W") for a in args
        )
        if staged_only:
            return None
        values: list[str] = []
        skip = False
        for a in args:
            if skip:
                skip = False
            elif a in ("--source", "-s"):
                skip = True
            elif not a.startswith("-"):
                values.append(a)
        t = first_match(values, cwd, whole_test)
        return ("write", t) if t else None
    return None


def analyze_segment(
    words: list[str], cwd: str, depth: int, pruning: bool
) -> tuple[str, Hit | None]:
    """Return (cwd for later segments, the refused path or None)."""
    while words and (re.match(r"^[A-Za-z_]\w*=", words[0]) or words[0] in WRAPPERS):
        words = words[1:]
        while words and words[0].startswith("-") and words[0] != "--":
            words = words[1:]
    if not words:
        return cwd, None
    cmd, rest = os.path.basename(words[0]), words[1:]
    if cmd == "cd" and rest:
        return os.path.normpath(os.path.join(cwd, rest[-1])), None
    if cmd in DELETERS:
        t = "" if pruning else first_match(delete_targets(rest), cwd, whole_test)
        return cwd, ("delete", t) if t else None
    if cmd == "git":
        return cwd, git_hit(rest, cwd, pruning)
    if cmd == "find":
        t = "" if pruning else find_target(rest, cwd)
        return cwd, ("delete", t) if t else None
    if cmd == "truncate":
        t = first_match(positionals(rest), cwd, existing_test_file)
        return cwd, ("write", t) if t else None
    if cmd in ("mv", "cp"):
        if cmd == "mv":
            return cwd, move_hit(rest, cwd, pruning)
        args = positionals(rest)
        return cwd, ("write", args[-1]) if len(args) > 1 and existing_test_file(
            args[-1], cwd
        ) else None
    if cmd == "tee":
        append = any(
            w == "--append" or re.match(r"^-[A-Za-z]*a", w) for w in rest if w.startswith("-")
        )
        t = "" if append else first_match(positionals(rest), cwd, existing_test_file)
        return cwd, ("write", t) if t else None
    if cmd in ("sed", "perl"):
        t = first_match(in_place_files(cmd, rest), cwd, file_test)
        return cwd, ("write", t) if t else None
    if cmd in SHELLS and "-c" in rest and rest.index("-c") + 1 < len(rest):
        return cwd, first_refused(rest[rest.index("-c") + 1], cwd, depth + 1, pruning)
    return cwd, None


def find_target(words: list[str], cwd: str) -> str:
    deleting = "-delete" in words or any(
        w in ("-exec", "-execdir")
        and i + 1 < len(words)
        and os.path.basename(words[i + 1]) in DELETERS
        for i, w in enumerate(words)
    )
    if not deleting:
        return ""
    roots = []
    for w in words:
        if w.startswith("-") or w in ("(", "!"):
            break
        roots.append(w)
    names = [words[i + 1] for i, w in enumerate(words[:-1]) if w in ("-name", "-iname", "-path")]
    if names and all(exempt(n) for n in names):
        return ""
    for w in roots + names:
        if judge_path(w, cwd, True):
            return w
    return ""


def redirect_targets(command: str) -> list[str]:
    """The words after an unquoted `>`, `>|` or `&>` (not `>>`, not `>&2`). Quotes and heredoc bodies are skipped."""
    out: list[str] = []
    n, i, quote = len(command), 0, ""
    pending: list[str] = []
    while i < n:
        c = command[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 1
            elif c == quote:
                quote = ""
            i += 1
        elif c == "\\":
            i += 2
        elif c in "'\"":
            quote = c
            i += 1
        elif c == NEWLINE and pending:
            i += 1
            for delim in pending:
                while i < n:
                    end = command.find(NEWLINE, i)
                    end = n if end < 0 else end
                    line = command[i:end].strip("\t")
                    i = end + 1
                    if line == delim:
                        break
            pending = []
        elif command.startswith("<<", i) and not command.startswith("<<<", i):
            m = HEREDOC.match(command, i)
            if m:
                pending.append(m.group(2))
                i = m.end()
            else:
                i += 2
        elif c == ">":
            if command.startswith(">>", i):
                i += 2
                continue
            if i > 0 and command[i - 1] == "<":
                i += 1
                continue
            j = i + 1
            if command.startswith("&", j):
                if j + 1 < n and (command[j + 1].isdigit() or command[j + 1] == "-"):
                    i = j + 1
                    continue
                j += 1
            elif command.startswith("|", j):
                j += 1
            while j < n and command[j] in " \t":
                j += 1
            word, q = "", ""
            while j < n:
                ch = command[j]
                if q:
                    if ch == q:
                        q = ""
                    else:
                        word += ch
                elif ch in "'\"":
                    q = ch
                elif ch == "\\" and j + 1 < n:
                    j += 1
                    word += command[j]
                elif ch in " \t\n;&|()<>":
                    break
                else:
                    word += ch
                j += 1
            if word:
                out.append(word)
            i = j
        else:
            i += 1
    return out


def redirect_hit(command: str, cwds: set[str]) -> Hit | None:
    for t in redirect_targets(command):
        if any(existing_test_file(t, cwd) for cwd in cwds):
            return ("write", t)
    return None


def first_refused(command: str, cwd: str, depth: int = 0, pruning: bool = False) -> Hit | None:
    """The first test path that `command` would delete or overwrite, or None. The text is parsed, never run."""
    if depth > 3:
        return None
    for m in INNER.finditer(command):
        hit = first_refused(m.group(1) or m.group(2) or "", cwd, depth + 1, pruning)
        if hit:
            return hit
    try:
        lex = shlex.shlex(command, posix=True, punctuation_chars=";()|&\n")
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        t = "" if pruning else fallback(command, cwd)
        return ("delete", t) if t else redirect_hit(command, {cwd})
    seen = {cwd}
    words: list[str] = []
    for tok in [*tokens, "\n"]:
        if tok in SEGMENT_BREAKS:
            if words:
                cwd, hit = analyze_segment(words, cwd, depth, pruning)
                seen.add(cwd)
                if hit:
                    return hit
            words = []
        else:
            words.append(tok)
    return redirect_hit(command, seen)


def fallback(command: str, cwd: str) -> str:
    """The text has an unbalanced quote (often a heredoc). Judge each line that starts with a delete."""
    for line in command.split(NEWLINE):
        m = re.match(r"^\s*(?:\S+=\S*\s+)*(?:sudo\s+)?(?:rm|unlink|git\s+rm)\b(.*)$", line)
        if m:
            for t in delete_targets(m.group(1).split()):
                if judge_path(t.strip("'\""), cwd, True):
                    return t
    return ""


def bash(payload: dict, cwd: str) -> None:
    command = payload.get("tool_input", {}).get("command")
    if not isinstance(command, str):
        return
    hit = first_refused(command, cwd, pruning=prune())
    if not hit:
        return
    kind, target = hit
    if kind == "delete":
        refuse("deletes a test", f"the command removes or moves {target}", DELETE_ADVICE)
    refuse(
        "changes a test by shell",
        f"the command overwrites or edits {target} in place",
        WRITE_ADVICE,
    )


def count(rx: re.Pattern[str], text: str) -> int:
    return len(rx.findall(text))


def check_edit(old: str, new: str, path: str, verb: str = "edit") -> None:
    if count(SKIP, new) > count(SKIP, old):
        refuse("skips a test", f"the {verb} adds a skip or xfail to {path}", SKIP_ADVICE)
    if count(COMMENTED_ASSERT, new) > count(COMMENTED_ASSERT, old):
        refuse(
            "comments out an assert", f"the {verb} comments out an assert in {path}", SKIP_ADVICE
        )


def file_text(path: str) -> str | None:
    try:
        p = Path(path)
        if not p.is_file() or p.stat().st_size > MAX_FILE:
            return None
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def write(args: dict, path: str, real: str) -> None:
    content = args.get("content")
    if not isinstance(content, str):
        return
    if not content.strip() and not prune():
        refuse("empties a test file", f"the write leaves {path} empty", DELETE_ADVICE)
    before = file_text(real)
    if before is None and os.path.exists(real):
        return
    check_edit(before or "", content, path, "write")


def write_or_edit(payload: dict, cwd: str) -> None:
    tool = payload["tool_name"]
    args = payload.get("tool_input", {})
    path = args.get("file_path")
    if not isinstance(path, str) or not path:
        return
    full = os.path.normpath(os.path.join(cwd, path))
    if not (is_test_name(full) or is_test_name(os.path.realpath(full))):
        return
    if tool == "Write":
        write(args, path, os.path.realpath(full))
        return
    edits = args.get("edits") if tool == "MultiEdit" else [args]
    if not isinstance(edits, list):
        return
    text = file_text(os.path.realpath(full))
    before = text
    for e in edits:
        if not isinstance(e, dict):
            continue
        old, new = e.get("old_string"), e.get("new_string")
        if not isinstance(old, str) or not isinstance(new, str):
            continue
        check_edit(old, new, path)
        if text is not None and old in text:
            text = text.replace(old, new)
    if (
        before is not None
        and text is not None
        and before.strip()
        and not text.strip()
        and not prune()
    ):
        refuse("empties a test file", f"the edit leaves {path} empty", DELETE_ADVICE)


def main() -> None:
    global ROOT
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8", errors="replace"))
    except ValueError:
        payload = None
    if not isinstance(payload, dict):
        refuse("malformed payload", "not JSON", "The hook cannot read the call, so it refuses it.")
    cwd = payload.get("cwd")
    cwd = cwd if isinstance(cwd, str) and cwd else os.getcwd()
    ROOT = tree_root(cwd)
    tool = payload.get("tool_name")
    if tool == "Bash":
        bash(payload, cwd)
    elif tool in ("Write", "Edit", "MultiEdit"):
        write_or_edit(payload, cwd)


if __name__ == "__main__":
    main()
