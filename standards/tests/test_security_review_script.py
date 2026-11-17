"""Run the rendered security-review.sh with fake strix, claude, uvx, docker and git binaries.

Each test holds one high risk from the PR 379 review: the LLM key left on disk, a budget that
cannot bind, findings published with the key in them, and Bash in the Claude run.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest
from test_template import git, render

KEY = "sk-test-0123456789"
FAKE = """#!/usr/bin/env bash
case "$(basename "$0")" in
  uvx) # a fake strix: saves the key in $HOME the way the real one does, and leaks it on request
    mkdir -p "$HOME/.strix" strix_runs/r1
    printf '{"LLM_API_KEY":"%s"}' "$LLM_API_KEY" >"$HOME/.strix/cli-config.json"
    printf '%s\\n' "$HOME" >"$FAKE_LOG.strixhome"
    echo '[]' >strix_runs/r1/vulnerabilities.json
    [[ -z "${FAKE_LEAK:-}" ]] || printf '%s' "$LLM_API_KEY" >strix_runs/r1/leak.txt ;;
  claude) # a fake claude: records its arguments and environment
    printf '%s\\n' "$@" >"$FAKE_LOG.claude-args"
    env >"$FAKE_LOG.claude-env" ;;
  git) # the skill clone is faked; every other call is real git
    if [[ "$*" == *" clone "* ]]; then mkdir -p "${@: -1}/skills/security-audit"; exit 0; fi
    if [[ "$*" == *"checkout -q"* ]]; then exit 0; fi
    if [[ "$*" == *"/skill rev-parse HEAD"* ]]; then
      . "$FAKE_PIN"; echo "$CLOUDFLARE_SKILL_COMMIT"; exit 0
    fi
    exec "$REAL_GIT" "$@" ;;
esac
"""


def project(tmp_path: Path) -> tuple[Path, dict[str, str]]:
    out = render(tmp_path / "p", ["shell"], security_review=True, kind="service")
    (out / "docs").mkdir(exist_ok=True)
    (out / "docs/architecture.md").write_text("threat model\n")
    git(out, "add", "-A")
    git(out, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--no-verify", "-m", "x")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name in ("uvx", "claude", "git"):
        (bin_dir / name).write_text(FAKE)
        (bin_dir / name).chmod(0o755)
    home = tmp_path / "home"
    home.mkdir()
    env = {
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "HOME": str(home),
        "SECURITY_LLM_KEY": KEY,
        "SECURITY_LLM_BASE": "https://api.anthropic.com",
        "SECURITY_REF": "main",
        "ODEV_TOKEN": "odev-secret",
        "FAKE_LOG": str(tmp_path / "log"),
        "FAKE_PIN": str(out / "scripts/security.pin"),
        "REAL_GIT": subprocess.run(["which", "git"], capture_output=True, text=True).stdout.strip(),
    }
    return out, env


def review(out: Path, env: dict[str, str], *extra: str, **more: str):
    return subprocess.run(
        ["scripts/security-review.sh", "--apply", "--budget", "10", *extra],
        cwd=out,
        capture_output=True,
        text=True,
        env={**env, **more},
    )


def test_strix_keeps_its_saved_key_inside_the_work_folder(tmp_path):
    out, env = project(tmp_path)
    done = review(out, env, "--tool", "strix")
    assert done.returncode == 0, done.stderr
    assert not (Path(env["HOME"]) / ".strix").exists()
    strix_home = Path(env["FAKE_LOG"] + ".strixhome").read_text().strip()
    assert strix_home != env["HOME"] and not Path(strix_home).exists()  # removed at the end


@pytest.mark.parametrize(
    "extra", [{"SECURITY_LLM_MODEL": "text"}, {"SECURITY_LLM_BASE": "https://litellm.example"}]
)
def test_a_model_that_strix_cannot_price_is_refused(tmp_path, extra):
    out, env = project(tmp_path)
    refused = review(out, env, "--tool", "strix", **extra)
    assert refused.returncode == 1 and (
        "claude-" in refused.stderr or "anthropic.com" in refused.stderr
    )
    assert not Path(env["FAKE_LOG"] + ".strixhome").exists()


def test_findings_are_deleted_when_the_key_is_found_in_the_output(tmp_path):
    out, env = project(tmp_path)
    failed = review(out, env, "--tool", "strix", FAKE_LEAK="1")
    assert failed.returncode == 1 and "key was found" in failed.stderr
    assert not (out / "security-review-out/findings.json").exists()
    assert KEY not in failed.stderr and KEY not in failed.stdout


def test_claude_gets_only_the_validators_in_bash_and_no_forge_token(tmp_path):
    out, env = project(tmp_path)
    done = review(out, env, "--tool", "cloudflare")
    assert done.returncode == 0, done.stderr
    args = Path(env["FAKE_LOG"] + ".claude-args").read_text().splitlines()
    assert "Bash" not in args and any(a.startswith("Bash(node ") and "validate-" in a for a in args)
    assert all(a.startswith("Bash(node ") for a in args if a.startswith("Bash"))
    claude_env = Path(env["FAKE_LOG"] + ".claude-env").read_text()
    assert "ODEV_TOKEN" not in claude_env and "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1" in claude_env
    # The scrub knows ANTHROPIC_API_KEY only: the job's own name for the key must be gone.
    assert "SECURITY_LLM_KEY=" not in claude_env
    # Writes only to the output folder, so no planted script can match the validator rule.
    assert "Write" not in args and "Edit" not in args
    edits = [a for a in args if a.startswith("Edit(")]
    assert (
        len(edits) == 1
        and edits[0].startswith("Edit(//")
        and edits[0].endswith("/raw/cloudflare/**)")
    )
