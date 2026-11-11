"""Rust: the gate section, the weekly refresh and CI."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest
from test_template import _repo, git, render, run_gate, steps

STUB_CARGO = """#!/usr/bin/env bash
# Records each call with its folder. A dry-run update names three crates that
# could move. The update of "puller" brings the new "fresh" with it.
printf '%s: %s\\n' "${PWD##*/}" "$*" >>"$CARGO_LOG"
if [[ "$*" == "update --dry-run" ]]; then
  printf '    Updating crates.io index\\n    Updating aged v1.0.0 -> v1.0.1\\n' >&2
  printf '    Updating fresh v2.0.0 -> v2.1.0\\n    Updating puller v3.0.0 -> v3.0.1\\n' >&2
fi
if [[ "$*" == *"--package puller@"* ]]; then
  printf 'name = "fresh"\\nversion = "2.1.0"\\n' >>Cargo.lock
fi
"""
# crates.io: "aged" was published long ago, "fresh" today.
STUB_CRATES = """#!/usr/bin/env bash
case "$*" in
  *crates/aged/1.0.1 | *crates/puller/3.0.1) printf '{"version":{"created_at":"2020-01-01T00:00:00.000000Z"}}' ;;
  *crates/fresh/2.1.0) printf '{"version":{"created_at":"%s"}}' "$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)" ;;
  *) exit 22 ;;
esac
"""
# Stands in for rustfmt on stdin: two spaces become one.
STUB_RUSTFMT = "#!/bin/sh\nexec sed 's/  */ /g'\n"


def _rust(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path]:
    out = render(tmp_path / "p", ["rust"], rust_dir="engine", rust_version="1.90.0")
    _repo(out)
    stub = tmp_path / "stub"
    stub.mkdir()
    for name, body in (("cargo", STUB_CARGO), ("curl", STUB_CRATES), ("rustfmt", STUB_RUSTFMT)):
        (stub / name).write_text(body)
        (stub / name).chmod(0o755)
    log = tmp_path / "cargo.log"
    log.touch()
    monkeypatch.setenv("PATH", f"{stub}:{os.environ['PATH']}")
    monkeypatch.setenv("CARGO_LOG", str(log))
    return out, log


def test_the_rust_gate_runs_fmt_clippy_deny_and_tests_in_the_project_folder(tmp_path, monkeypatch):
    out, log = _rust(tmp_path, monkeypatch)
    git(out, "add", "-A")
    gate = run_gate(out, "--only", "rust")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert log.read_text().splitlines() == [
        "engine: fmt --all --check",
        "engine: clippy --locked --all-targets -- -D warnings",
        "engine: deny --locked check",
        "engine: test --locked",
    ]
    # The fast gate formats each staged .rs file on its own.
    source = out / "engine/src/lib.rs"
    source.parent.mkdir()
    source.write_text("fn  a() {}\n")
    git(out, "add", "-A")
    gate = run_gate(out, "--fast", "--only", "rust")
    assert gate.returncode == 1 and "src/lib.rs" in gate.stderr, gate.stdout + gate.stderr
    source.write_text("fn a() {}\n")
    git(out, "add", "-A")
    assert run_gate(out, "--fast", "--only", "rust").returncode == 0


def test_the_rust_refresh_takes_only_a_version_older_than_seven_days(tmp_path, monkeypatch):
    out, log = _rust(tmp_path, monkeypatch)
    lock = out / "engine/Cargo.lock"
    before = "".join(
        f'[[package]]\nname = "{n}"\nversion = "{v}"\n\n'
        for n, v in (("aged", "1.0.0"), ("fresh", "2.0.0"), ("puller", "3.0.0"))
    )
    lock.write_text(before)
    done = subprocess.run(
        [str(out / "scripts/update-deps.sh"), "--refresh-only", "--only", "rust"],
        cwd=out, capture_output=True, text=True,
    )  # fmt: skip
    assert done.returncode == 0, done.stdout + done.stderr
    assert log.read_text().splitlines() == [
        "engine: update --dry-run",
        "engine: update --package aged@1.0.0 --precise 1.0.1",
        "engine: update --package puller@3.0.0 --precise 3.0.1",
    ]
    assert "fresh stays at 2.0.0" in done.stdout
    # The update of puller brought the new fresh with it, so it is undone.
    assert "puller stays at 3.0.0: 3.0.1 needs fresh 2.1.0" in done.stdout
    assert lock.read_text() == before


def test_ci_gives_rust_its_own_image_with_the_pinned_tools(tmp_path, monkeypatch):
    out, _ = _rust(tmp_path, monkeypatch)
    gate = {s["name"]: s for s in steps(out / ".onedev-buildspec.yml", "CI")}
    assert gate["Gate Rust"]["image"] == "rust:1.90.0-bookworm"
    commands = gate["Gate Rust"]["interpreter"]["commands"]
    assert "scripts/install-cargo-deny.sh" in commands and "scripts/gate.sh --only rust" in commands
    assert 'channel = "1.90.0"' in (out / "engine/rust-toolchain.toml").read_text()
