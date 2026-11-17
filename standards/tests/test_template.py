"""Render every bundle combination and check what each one produces.

The template must never ship a file that fails its own rules, so rendered
scripts go through shellcheck and shfmt here too.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import tomllib
import subprocess
import time
import xml.etree.ElementTree as ET
from datetime import UTC, datetime
from pathlib import Path

import pytest
import yaml
from copier import run_copy

# The repo root, where copier.yml is: the template's own tests live in standards/.
TEMPLATE = Path(__file__).resolve().parent.parent.parent

COMBOS = {
    "python": ["python"],
    "dotnet": ["dotnet"],
    "typescript": ["typescript"],
    "shell": ["shell"],
    "rust": ["rust"],
    "everything": ["dotnet", "python", "typescript", "shell"],
    "subfolders": ["dotnet", "python", "typescript", "shell"],
}

# Answers beyond the languages, per combination.
EXTRA: dict[str, dict[str, object]] = {
    "subfolders": {
        "python_dir": "tools/py",
        "dotnet_dir": "backend",
        "node_dir": "frontend",
        "shell_exclude": [".ralph", "archive"],
    },
}

# The answer that names each bundle's project folder.
BUNDLE_DIR = {
    "python": "python_dir",
    "dotnet": "dotnet_dir",
    "typescript": "node_dir",
    "rust": "rust_dir",
}

BUNDLE_FILES = {
    "python": [
        "ruff.toml",
        "pyrightconfig.json",
        "pytest.toml",
        "uv.toml",
        "pyproject.toml",
        "uv.lock",
    ],
    "dotnet": [
        "Directory.Build.props",
        "Directory.Packages.props",
        "nuget.config",
        "global.json",
        ".config/dotnet-tools.json",
        "tests/.editorconfig",
    ],
    "typescript": [".npmrc", ".prettierrc.json", "tsconfig.json", "eslint.config.mjs"],
    "rust": ["deny.toml", "rust-toolchain.toml"],
}

COMMON_FILES = [
    "CLAUDE.md",
    "CONTEXT.md",
    "README.md",
    "docs/adr/README.md",
    ".editorconfig",
    ".gitignore",
    ".shellcheckrc",
    ".copier-answers.yml",
    ".githooks/pre-commit",
    "scripts/gate.sh",
    "scripts/gate.md",
    "scripts/update-deps.sh",
    "scripts/deslop-pr.sh",
    "scripts/deslop-comment.sh",
    "scripts/deslop-decisions.sh",
    "scripts/deslop-issues.sh",
    "scripts/deslop.pin",
    ".deslop.toml",
    ".secrets.baseline",
]

# What each forge adds; a render has its own forge's files and no other's.
FORGE_FILES = {
    "onedev": [
        ".onedev/pull-request-template.md",
        ".onedev-buildspec.yml",
        "scripts/forge/onedev.sh",
    ],
    "github": [
        ".github/pull_request_template.md",
        ".github/ISSUE_TEMPLATE/issue.md",
        ".github/workflows/gate.yml",
        ".github/workflows/deslop-nightly.yml",
        ".github/workflows/update-deps.yml",
        "scripts/forge/github.sh",
    ],
}


# A cold uvx start can pass the default 5 s. A test that sets
# gate_budget_reason itself gets the answers it names, and the defaults for the rest.
SLOW_BUDGETS = {
    "gate_budget_reason": "the tests start uvx cold",
    "gate_fast_budget": 60,
}


PROFILE = {"tenants_now": "one", "tenants_later": "one", "users_now": "one", "users_later": "one"}
# What an environment file gives every repo (instances/example.yml).
INSTANCE = {"vault_command": "vault-read", "forge": "onedev"}


def render(dest: Path, languages: list[str], **extra: object) -> Path:
    run_copy(
        str(TEMPLATE),
        dest,
        data={
            "project_name": "demo",
            "description": "A demo project",
            "kind": "cli",
            "languages": languages,
            **PROFILE,
            **INSTANCE,
            **({} if "gate_budget_reason" in extra else SLOW_BUDGETS),
            **extra,
        },
        defaults=True,
        unsafe=True,
        vcs_ref="HEAD",
        quiet=True,
    )
    return dest


def render_combo(tmp_path: Path, name: str) -> Path:
    return render(tmp_path / name, COMBOS[name], **EXTRA.get(name, {}))


@pytest.mark.parametrize("name", COMBOS)
def test_each_combination_has_the_common_files_and_only_its_own_bundles(tmp_path, name):
    out = render_combo(tmp_path, name)
    for f in COMMON_FILES + FORGE_FILES["onedev"]:
        assert (out / f).is_file(), f
    for f in FORGE_FILES["github"]:
        assert not (out / f).exists(), f
    for bundle, files in BUNDLE_FILES.items():
        folder = out / str(EXTRA.get(name, {}).get(BUNDLE_DIR[bundle], "."))
        for f in files:
            assert (folder / f).exists() == (bundle in COMBOS[name]), (bundle, f)


@pytest.mark.parametrize("name", COMBOS)
def test_rendered_scripts_pass_shellcheck_and_shfmt(tmp_path, name):
    out = render_combo(tmp_path, name)
    scripts = [
        out / "scripts/gate.sh",
        out / "scripts/update-deps.sh",
        out / "scripts/deslop-pr.sh",
        out / "scripts/deslop-comment.sh",
        out / "scripts/deslop-decisions.sh",
        out / "scripts/deslop-issues.sh",
        out / ".githooks/pre-commit",
        *out.glob("scripts/install-cargo-deny.sh"),
        *out.glob("scripts/forge/*.sh"),
    ]
    subprocess.run(
        ["shellcheck", "--rcfile", str(out / ".shellcheckrc"), *map(str, scripts)], check=True
    )
    subprocess.run(["shfmt", "-d", "-i", "2", "-ci", "-bn", *map(str, scripts)], check=True)


@pytest.mark.parametrize("name", COMBOS)
def test_rendered_config_files_parse(tmp_path, name):
    out = render_combo(tmp_path, name)
    for f in ("pyrightconfig.json", "tsconfig.json", "global.json", ".config/dotnet-tools.json"):
        for found in out.rglob(f):
            json.loads(found.read_text())
    for f in ("deny.toml", "rust-toolchain.toml"):
        for found in out.rglob(f):
            tomllib.loads(found.read_text())
    for found in out.rglob("nuget.config"):
        ET.parse(found)
    yaml.load((out / ".onedev-buildspec.yml").read_text(), Loader=SpecLoader)


def test_a_new_project_gets_the_hooks_switched_on(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    path = subprocess.run(
        ["git", "-C", str(out), "config", "core.hooksPath"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    assert path == ".githooks"


def test_the_next_config_appears_only_for_a_nextjs_front_end(tmp_path):
    assert not (render(tmp_path / "a", ["typescript"], nextjs=False) / "next.config.ts").exists()
    assert (render(tmp_path / "b", ["typescript"], nextjs=True) / "next.config.ts").exists()


def test_the_pre_commit_hook_stays_inside_its_time_budget(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    (out / "hello.sh").write_text('#!/usr/bin/env bash\nset -Eeuo pipefail\nprintf "%s\\n" hi\n')
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    hook = [str(out / ".githooks/pre-commit")]
    subprocess.run(hook, cwd=out, check=True, capture_output=True)  # warm the uvx cache
    # The best of three runs: one slow run on a loaded runner is not a slow hook (issue #41).
    took = []
    for _ in range(3):
        started = time.monotonic()
        subprocess.run(hook, cwd=out, check=True, capture_output=True)
        took.append(time.monotonic() - started)
    assert min(took) < 5, took


def test_adrs_can_live_outside_a_published_docs_folder(tmp_path):
    out = render(tmp_path / "p", ["python"], adr_dir="design/adr")
    assert (out / "design/adr/README.md").is_file()
    assert not (out / "docs").exists()
    assert "`design/adr/`" in (out / "CLAUDE.md").read_text()


def test_the_spec_reads_secrets_only_when_a_step_runs(tmp_path):
    """OneDev rejects the whole spec, CI job included, when a field it checks on
    push names a secret the project has not set. A step's envVars are read only
    when it runs, so a new repo gets CI before anyone sets the weekly job's."""
    spec = (render(tmp_path / "p", ["python"]) / ".onedev-buildspec.yml").read_text()
    refs = [line.strip() for line in spec.splitlines() if "@secret:" in line]
    assert refs and "accessTokenSecret" not in spec
    assert all(line.startswith("value: '@secret:") for line in refs), refs


def test_trusting_a_green_ci_build_splits_ci_and_reads_the_secret_only_on_main(tmp_path):
    out = render(tmp_path / "p", ["shell"], trust_green_ci=True)
    spec = out / ".onedev-buildspec.yml"
    names = {j["name"] for j in yaml.load(spec.read_text(), Loader=SpecLoader)["jobs"]}
    assert {"CI", "CI on main"} <= names
    pr = " ".join(s["name"] for s in steps(spec, "CI"))
    main = " ".join(s["name"] for s in steps(spec, "CI on main"))
    assert "Trust a green CI build" in main and "Trust a green CI build" not in pr
    default = render(tmp_path / "q", ["shell"]) / ".onedev-buildspec.yml"
    assert "CI on main" not in default.read_text()


def test_the_trust_step_trusts_only_a_green_ci_build_of_the_same_tree(tmp_path):
    out = render(tmp_path / "p", ["shell"], trust_green_ci=True)
    step = {s["name"]: s for s in steps(out / ".onedev-buildspec.yml", "CI on main")}[
        "Trust a green CI build"
    ]
    script = tmp_path / "trust.sh"
    script.write_text(
        step["interpreter"]["commands"]
        .replace("@project_path@", "demo")
        .replace("@server_url@", "https://od.invalid")
    )
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "curl").write_text(
        '#!/bin/sh\ncat >/dev/null\n[ "$FAKE_CURL" = fail ] && exit 22\ncat "$FAKE_CURL"\n'
    )
    (bin_dir / "curl").chmod(0o755)
    tree = "a" * 40
    good = {
        "jobName": "CI",
        "status": "SUCCESSFUL",
        "version": tree,
        "number": 3,
        "commitHash": "abcdef123",
    }
    cases = {
        "good": ([good], tree, True),
        "other tree": ([{**good, "version": "b" * 40}], tree, False),
        "other job": ([{**good, "jobName": "Deploy"}], tree, False),
        "failed": ([{**good, "status": "FAILED"}], tree, False),
        "running": ([{**good, "status": "RUNNING"}], tree, False),
        "no build": ([], tree, False),
        "bad json": ("not json", tree, False),
        "api error": ("fail", tree, False),
        "empty tree": ([good], "", False),
    }
    for name, (body, recorded, trusted) in cases.items():
        work = tmp_path / name.replace(" ", "-")
        (work / ".git").mkdir(parents=True)
        (work / ".git/ci-tree").write_text(recorded)
        reply = work / "reply.json"
        reply.write_text(body if isinstance(body, str) else json.dumps(body))
        env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "ONEDEV_TOKEN": "t"}
        env["FAKE_CURL"] = "fail" if body == "fail" else str(reply)
        run = subprocess.run(
            ["bash", str(script)], cwd=work, env=env, capture_output=True, text=True
        )
        assert run.returncode == 0, (name, run.stderr)
        assert "Traceback" not in run.stderr, name
        assert (work / ".git/ci-trusted").exists() is trusted, name
    work = tmp_path / "no-token"
    (work / ".git").mkdir(parents=True)
    (work / ".git/ci-tree").write_text(tree)
    env = {k: v for k, v in os.environ.items() if k != "ONEDEV_TOKEN"}
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    env["FAKE_CURL"] = str(tmp_path / "good" / "reply.json")
    run = subprocess.run(["bash", str(script)], cwd=work, env=env, capture_output=True, text=True)
    assert run.returncode == 0 and not (work / ".git/ci-trusted").exists()


def test_the_full_gate_passes_in_a_new_python_repo_with_no_tests(tmp_path):
    out = render(tmp_path / "p", ["python"])
    _repo(out)
    git(out, "add", "-A")
    gate = run_gate(out, "--only", "python")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "gate: python: pytest collected no tests" in gate.stdout


def test_a_new_python_project_is_locked_with_its_dev_tools(tmp_path):
    out = render(tmp_path / "p", ["python"])
    lock = (out / "uv.lock").read_text()
    for tool in ("ruff", "pyright", "pytest", "pytest-socket", "pytest-xdist"):
        assert f'name = "{tool}"' in lock, tool


def test_an_existing_pyproject_is_left_alone(tmp_path):
    dest = tmp_path / "p"
    dest.mkdir()
    (dest / "pyproject.toml").write_text('[project]\nname = "mine"\n')
    out = render(dest, ["python"])
    assert (out / "pyproject.toml").read_text() == '[project]\nname = "mine"\n'


def test_python_build_metadata_is_ignored(tmp_path):
    out = render(tmp_path / "p", ["python"])
    assert "*.egg-info/" in (out / ".gitignore").read_text().splitlines()


class SpecLoader(yaml.SafeLoader):
    """Reads a OneDev build spec: each !Tag becomes a plain mapping."""


SpecLoader.add_multi_constructor(
    "!", lambda loader, _tag, node: loader.construct_mapping(node, deep=True)
)


def steps(spec_path: Path, job: str) -> list[dict]:
    spec = yaml.load(spec_path.read_text(), Loader=SpecLoader)
    found = [j for j in spec["jobs"] if j["name"] == job]
    assert found, job
    return [s for s in found[0]["steps"] if "commands" in s.get("interpreter", {})]


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=True
    ).stdout.strip()


def config(repo: Path, *args: str) -> str:
    """One git config value, or "" when it is not set."""
    return subprocess.run(
        ["git", "-C", str(repo), "config", *args], capture_output=True, text=True
    ).stdout.strip()


def test_a_linked_worktree_gets_the_hooks_for_itself_only(tmp_path, capfd):
    main = tmp_path / "main"
    main.mkdir()
    git(main, "init", "-q", "-b", "main")
    git(
        main,
        "-c",
        "user.name=t",
        "-c",
        "user.email=t@t",
        "commit",
        "-q",
        "--allow-empty",
        "-m",
        "start",
    )
    wt = tmp_path / "wt"
    git(main, "worktree", "add", "-q", "-b", "feat/wt", str(wt))
    capfd.readouterr()
    render(wt, ["shell"])
    # git config --worktree fails until the task turns worktreeConfig on; that
    # "fatal:" line only alarms whoever adopts the template.
    assert "fatal:" not in "".join(capfd.readouterr())
    assert config(main, "--local", "--get", "core.hooksPath") == ""
    assert config(main, "--get", "core.hooksPath") == ""
    assert config(wt, "--worktree", "--get", "core.hooksPath") == ".githooks"
    assert config(wt, "--get", "core.hooksPath") == ".githooks"


# A stand-in for npx --no-install that fails on a path that does not exist.
FAKE_NPX = """#!/usr/bin/env bash
for a in "$@"; do
  [[ "$a" != *.* || "$a" == -* || -e "$a" ]] || { printf 'npx: no file %s\\n' "$a"; exit 1; }
done
"""


@pytest.mark.parametrize(
    ("language", "answer", "source"),
    [
        ("python", {"python_dir": "app"}, "app/ok.py"),
        ("typescript", {"node_dir": "web"}, "web/ok.ts"),
    ],
)
def test_the_pre_commit_hook_passes_in_a_linked_worktree_with_a_project_folder(
    tmp_path, language, answer, source
):
    main = tmp_path / "main"
    main.mkdir()
    git(main, "init", "-q", "-b", "main")
    _repo(main)
    git(main, "commit", "-q", "--allow-empty", "-m", "start")
    wt = tmp_path / "wt"
    git(main, "worktree", "add", "-q", "-b", "feat/wt", str(wt))
    render(wt, [language, "shell"], **answer)
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "--no-verify", "-m", "init")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "npx").write_text(FAKE_NPX)
    (bin_dir / "npx").chmod(0o755)
    (wt / source).write_text("x = 1\n" if language == "python" else "export const x = 1;\n")
    git(wt, "add", source)
    env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
    commit = subprocess.run(
        ["git", "-C", str(wt), "commit", "-q", "-m", "add a source file"],
        capture_output=True,
        text=True,
        env=env,
    )
    assert commit.returncode == 0, commit.stdout + commit.stderr


def test_an_existing_hooks_path_is_left_alone_with_a_note(tmp_path, capfd):
    dest = tmp_path / "p"
    dest.mkdir()
    git(dest, "init", "-q", "-b", "main")
    git(dest, "config", "core.hooksPath", ".husky")
    render(dest, ["shell"])
    assert config(dest, "--get", "core.hooksPath") == ".husky"
    assert "core.hooksPath is already '.husky'; left alone" in capfd.readouterr().out


PRIVATE = {
    "private_index": "http://h/python-packages/~pypi/simple/",
    "private_packages": ["comfyui-core", "hevy-core"],
}


def test_a_private_index_pins_its_packages_and_exempts_them_from_the_cooldown(tmp_path):
    out = render(tmp_path / "p", ["python"], **PRIVATE)
    uv = tomllib.loads((out / "uv.toml").read_text())
    assert uv["exclude-newer"] == "7 days"
    assert uv["exclude-newer-package"] == {"comfyui-core": False, "hevy-core": False}
    tool = tomllib.loads((out / "pyproject.toml").read_text())["tool"]["uv"]
    assert tool["index"] == [
        {"name": "python-packages", "url": PRIVATE["private_index"], "explicit": True}
    ]
    assert tool["sources"] == {
        "comfyui-core": {"index": "python-packages"},
        "hevy-core": {"index": "python-packages"},
    }
    # uv accepts the pair: the seeding task locked it.
    assert (out / "uv.lock").is_file()


def test_a_private_index_login_comes_from_job_secrets_in_ci_and_the_weekly_job(tmp_path):
    spec = (render(tmp_path / "p", ["python"], **PRIVATE) / ".onedev-buildspec.yml").read_text()
    for var, secret in (
        ("UV_INDEX_PYTHON_PACKAGES_USERNAME", "PKG_USER"),
        ("UV_INDEX_PYTHON_PACKAGES_PASSWORD", "PKG_TOKEN"),
    ):
        lines = spec.splitlines()
        at = [i for i, line in enumerate(lines) if line.strip() == f"- name: {var}"]
        assert len(at) == 2, var  # the gate step and the weekly refresh step
        for i in at:
            assert lines[i + 1].strip() == f"value: '@secret:{secret}@'"


def test_no_private_index_means_no_package_secrets(tmp_path):
    out = render(tmp_path / "p", ["python"])
    assert "PKG_" not in (out / ".onedev-buildspec.yml").read_text()
    assert "exclude-newer-package" not in (out / "uv.toml").read_text().replace(
        "# Let a security fix through with: exclude-newer-package", ""
    )
    assert "tool.uv" not in (out / "pyproject.toml").read_text()


def _repo(out: Path) -> None:
    for args in (["config", "user.email", "t@t"], ["config", "user.name", "t"]):
        subprocess.run(["git", "-C", str(out), *args], check=True)


def test_the_gate_shell_checks_only_files_whose_shebang_names_a_shell(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "bin").mkdir()
    (out / "bin/pytool").write_text("#!/usr/bin/env python3\nprint([x for x in [1]])\n")
    (out / "bin/shtool").write_text('#!/usr/bin/env bash\nset -eu\necho "$1"\n')
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    gate = run_gate(out)
    assert gate.returncode == 0, gate.stdout + gate.stderr


def test_the_gate_refuses_a_branch_not_named_kind_slash_name(tmp_path, monkeypatch):
    monkeypatch.delenv("GITHUB_HEAD_REF", raising=False)
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    for branch, mode, ok in (
        ("sitrep-live/fresh-sign-in", "--fast", False),
        ("fix/312-spec-drift", "--fast", True),
        ("Feature/X", "--full", False),
        ("dependabot/npm/vite-8", "--full", True),
    ):
        git(out, "switch", "-q", "-c", branch)
        gate = run_gate(out, mode)
        assert (gate.returncode == 0) == ok, (branch, gate.stdout + gate.stderr)
        assert ("is not <kind>/<name>" in gate.stderr) != ok, branch
    # In CI the checkout is a detached merge preview: GITHUB_HEAD_REF names the branch.
    git(out, "switch", "-q", "--detach")
    monkeypatch.setenv("GITHUB_HEAD_REF", "template/deslop")
    assert run_gate(out, "--only", "shell").returncode != 0


def test_the_fast_gate_refuses_a_staged_file_with_more_changes_on_disk(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    script = out / "hello.sh"
    script.write_text('#!/usr/bin/env bash\necho  "staged, with a format error"\n')
    git(out, "add", "hello.sh")
    script.write_text('#!/usr/bin/env bash\necho "clean on disk"\n')
    gate = run_gate(out, "--fast")
    assert gate.returncode == 1, gate.stdout + gate.stderr
    assert "staged, with more changes on disk: hello.sh" in gate.stderr
    git(out, "add", "hello.sh")
    assert run_gate(out, "--fast").returncode == 0


ASK_FOR_ISSUE = "Open a refactor issue on the forge at high priority"


@pytest.mark.parametrize(
    ("name", "counted"),
    [
        ("query.sql", True),
        ("bin/tool", True),
        ("notes.md", False),
        ("cv/cv.html", False),
        ("uv.lock", False),
        ("pkg/fixtures/data.json", False),
    ],
)
def test_the_fast_gate_allows_a_new_file_over_the_token_cap_and_asks_for_an_issue(
    tmp_path, name, counted
):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / name).parent.mkdir(parents=True, exist_ok=True)
    # Source code counts, a #! script with no extension too; documents never do.
    head = "#!/bin/sh\n" if name == "bin/tool" else ""
    (out / name).write_text(head + "x" * (20_004 - len(head)) + "\n")
    git(out, "add", name)
    gate = run_gate(out, "--fast")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert (ASK_FOR_ISSUE in gate.stderr) is counted, gate.stderr
    if counted:
        assert f"gate: {name} is 5002 tokens (bytes / 4); its limit is 5000" in gate.stderr
        assert (out / ".gate-size-baseline").read_text() == f"5002 {name}\n"


def test_a_listed_large_file_asks_again_only_when_it_grows(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    big, listed = out / "big.sql", out / ".gate-size-baseline"
    big.write_text("x" * 40_000)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    assert run_scoped(out, "--size-baseline").returncode == 0
    assert listed.read_text() == "10000 big.sql\n"
    for size, asks, line in (
        (40_004, True, "10001 big.sql\n"),
        (40_000, False, "10001 big.sql\n"),
        (30_000, False, "7500 big.sql\n"),
        (100, False, ""),
    ):
        big.write_text("x" * size)
        git(out, "add", "-A")
        gate = run_gate(out, "--fast")
        assert gate.returncode == 0, (size, gate.stdout + gate.stderr)
        assert (ASK_FOR_ISSUE in gate.stderr) is asks, (size, gate.stderr)
        assert listed.read_text() == line
    assert (
        "its limit is 10000" not in gate.stderr
        and git(out, "status", "--porcelain", ".gate-size-baseline")[:1] in "AM"
    )


def test_the_fast_gate_stages_a_baseline_whose_line_numbers_moved(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "conf.txt").write_text('token = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    scan = subprocess.run(
        [
            "uvx",
            "--quiet",
            "--exclude-newer",
            "7 days",
            "--from",
            "detect-secrets",
            "detect-secrets",
            "scan",
        ],
        cwd=out,
        capture_output=True,
        text=True,
        check=True,
    )
    (out / ".secrets.baseline").write_text(scan.stdout)
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(out), "commit", "-qm", "init"], check=True)
    (out / "conf.txt").write_text('# a\n# b\ntoken = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    subprocess.run(["git", "-C", str(out), "add", "conf.txt"], check=True)
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--fast"], cwd=out, capture_output=True, text=True
    )
    assert gate.returncode == 0, gate.stdout + gate.stderr
    staged = subprocess.run(
        ["git", "-C", str(out), "diff", "--cached", "--name-only"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    assert ".secrets.baseline" in staged


def test_the_ci_gate_fails_on_a_key_committed_with_no_verify(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    git(out, "add", "-A")
    git(out, "commit", "-qm", "init")
    (out / "conf.txt").write_text('token = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "plant a key")
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--full"],
        cwd=out,
        capture_output=True,
        text=True,
        env={**os.environ, "CI": "1", "GATE_BASE": "HEAD~1"},
    )
    assert gate.returncode != 0 and "possible secret" in gate.stderr, gate.stdout + gate.stderr


def test_the_ci_gate_fails_on_a_key_added_and_removed_in_the_branch(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    git(out, "add", "-A")
    git(out, "commit", "-qm", "init")
    (out / "clé.txt").write_text('token = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "plant a key")
    git(out, "rm", "-q", "clé.txt")
    git(out, "commit", "-q", "--no-verify", "-m", "remove it")
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--full"],
        cwd=out,
        capture_output=True,
        text=True,
        env={**os.environ, "CI": "1", "GATE_BASE": "HEAD~2"},
    )
    assert gate.returncode != 0 and "possible secret" in gate.stderr, gate.stdout + gate.stderr


def test_the_ci_gate_passes_a_branch_whose_commit_refreshed_the_baseline(tmp_path):
    # The fast gate stages .secrets.baseline when a known finding's line moves. The full gate
    # scans a copy of the baseline, so it must not also scan the real file as a changed one:
    # detect-secrets reads its hashes as new secrets, and every such branch failed CI.
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "conf.txt").write_text('token = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    git(out, "add", "-A")
    scan = subprocess.run(
        [
            "uvx",
            "--quiet",
            "--exclude-newer",
            "7 days",
            "--from",
            "detect-secrets",
            "detect-secrets",
            "scan",
        ],
        cwd=out,
        capture_output=True,
        text=True,
        check=True,
    )
    (out / ".secrets.baseline").write_text(scan.stdout)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    (out / "conf.txt").write_text('# a\n# b\ntoken = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    git(out, "add", "conf.txt")
    fast = run_gate(out, "--fast")
    assert (
        fast.returncode == 0
        and ".secrets.baseline" in git(out, "diff", "--cached", "--name-only").split()
    ), fast.stderr
    git(out, "commit", "-q", "--no-verify", "-m", "move the known key")
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--full"],
        cwd=out,
        capture_output=True,
        text=True,
        env={**os.environ, "CI": "1", "GATE_BASE": "HEAD~1"},
    )
    assert gate.returncode == 0, gate.stdout + gate.stderr


def run_gate(out: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """Run the gate. Without a mode flag it runs in full, as CI does; run_scoped has the bare command."""
    if not {"--full", "--fast"} & set(args):
        args = ("--full", *args)
    return run_scoped(out, *args)


def run_scoped(out: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(out / "scripts/gate.sh"), *args], cwd=out, capture_output=True, text=True
    )


# (a) The repo-owned extension: the one place for a repo's own checks.


def test_the_gate_runs_the_repo_extension_in_every_mode(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "scripts/gate.local.sh").write_text(
        '#!/usr/bin/env bash\nset -Eeuo pipefail\nprintf "%s\\n" "$1" >>"$(pwd)/ran.txt"\n'
    )
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    for args in ((), ("--fast",), ("--only", "local"), ("--only", "shell")):
        gate = run_gate(out, *args)
        assert gate.returncode == 0, gate.stdout + gate.stderr
    # From the repo root, with the mode; --only shell leaves it out.
    assert (out / "ran.txt").read_text().split() == ["full", "fast", "full"]


def test_a_failing_extension_fails_the_gate(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "scripts/gate.local.sh").write_text("#!/usr/bin/env bash\nexit 3\n")
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    assert run_gate(out).returncode != 0
    assert run_gate(out, "--fast").returncode != 0


def test_an_older_repo_gets_the_pointer_to_the_gate_instructions_once(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    assert "Read `scripts/gate.md` first" in (out / "CLAUDE.md").read_text()
    assert "| `scripts/gate.sh --full` |" in (out / "scripts/gate.md").read_text()
    # An older repo: its own CLAUDE.md, seeded before the template had the file.
    mine = "# mine\n\nMy own text.\n"
    (out / "CLAUDE.md").write_text(mine)
    render(out, ["shell"])
    text = (out / "CLAUDE.md").read_text()
    assert text.startswith(mine) and text.count("Read `scripts/gate.md` first") == 1
    render(out, ["shell"])
    assert (out / "CLAUDE.md").read_text() == text


def test_no_extension_means_nothing_extra_to_run(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    assert not (out / "scripts/gate.local.sh").exists()
    gate = run_gate(out, "--only", "local")
    assert gate.returncode == 0, gate.stderr
    assert "no scripts/gate.local.sh" in gate.stdout


OLD_GATE = '#!/usr/bin/env bash\nset -Eeuo pipefail\necho "old checks"\n'
OLD_GATE_LINE = (
    "gate: app/gate.sh is a second gate script; fold its checks into"
    " scripts/gate.local.sh and remove it (called from: .onedev-buildspec.yml)\n"
)


@pytest.mark.parametrize("name", COMBOS)
def test_a_rendered_repo_has_one_gate(tmp_path, name):
    out = render_combo(tmp_path, name)
    _repo(out)
    git(out, "add", "-A")
    assert "scripts/gate.sh" in git(out, "ls-files")
    gate = run_gate(out, "--only", "shell")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "second gate script" not in gate.stderr


def test_the_gate_fails_until_an_old_gate_is_folded_in_and_removed(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "app").mkdir()
    (out / "app/gate.sh").write_text(OLD_GATE)
    spec = out / ".onedev-buildspec.yml"
    spec.write_text(spec.read_text() + "# also runs app/gate.sh\n")
    git(out, "add", "-A")
    for args in ((), ("--fast",)):
        gate = run_gate(out, *args)
        assert gate.returncode == 1, args
        assert OLD_GATE_LINE in gate.stderr, (args, gate.stderr)
    # The pre-commit hook refuses it too; commit it as an older repo would have.
    git(out, "commit", "-qm", "init", "--no-verify")
    git(out, "mv", "app/gate.sh", "scripts/gate.local.sh")
    for args in ((), ("--fast",)):
        gate = run_gate(out, *args)
        assert gate.returncode == 0, (args, gate.stdout + gate.stderr)


def test_a_root_old_gate_names_only_the_configs_that_call_it(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    for name in ("gate.sh", "ci.sh", "check.sh"):
        (out / name).write_text(OLD_GATE)
    spec = out / ".onedev-buildspec.yml"
    spec.write_text(spec.read_text() + "# also runs ./ci.sh\n")
    git(out, "add", "-A")
    gate = run_gate(out, "--only", "shell")
    assert gate.returncode == 1
    lines = sorted(line for line in gate.stderr.splitlines() if "second gate script" in line)
    fold = "is a second gate script; fold its checks into scripts/gate.local.sh and remove it"
    assert lines == [
        f"gate: check.sh {fold}",
        f"gate: ci.sh {fold} (called from: .onedev-buildspec.yml)",
        f"gate: gate.sh {fold}",
    ]


def test_a_plain_file_with_a_gate_name_passes(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    for path in ("docs/ci", ".github/ci", "docs/v1.2/check"):
        (out / path).parent.mkdir(parents=True, exist_ok=True)
        (out / path).write_text("How CI runs: see scripts/gate.sh.\n")
    git(out, "add", "-A")
    for args in ((), ("--fast",)):
        gate = run_gate(out, *args)
        assert gate.returncode == 0, (args, gate.stdout + gate.stderr)
    (out / "docs/check").write_text(OLD_GATE)
    git(out, "add", "-A")
    gate = run_gate(out, "--only", "shell")
    assert "gate: docs/check is a second gate script" in gate.stderr


def test_only_scripts_gate_ps1_may_twin_the_gate(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "scripts/gate.ps1").write_text("Write-Output 'twin'\n")
    git(out, "add", "-A")
    gate = run_gate(out, "--only", "shell")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    (out / "app").mkdir()
    (out / "Scripts").mkdir()
    (out / "Scripts/Gate.ps1").write_text("Write-Output 'not the twin'\n")
    for name in ("gate.ps1", "Gate.ps1", "CI.ps1", "CI.sh"):
        (out / "app" / name).write_text("Write-Output 'old'\n")
    git(out, "add", "-A")
    gate = run_gate(out, "--only", "shell")
    assert gate.returncode == 1
    flagged = sorted(
        line.split()[1] for line in gate.stderr.splitlines() if "second gate script" in line
    )
    assert flagged == [
        "Scripts/Gate.ps1",
        "app/CI.ps1",
        "app/CI.sh",
        "app/Gate.ps1",
        "app/gate.ps1",
    ]


def test_a_second_gate_is_named_even_when_it_fails_lint(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "check.sh").write_text("#!/usr/bin/env bash\nif [ $1 ]; then\n      echo $1\nfi\n")
    git(out, "add", "-A")
    for args in ((), ("--fast",)):
        gate = run_gate(out, *args)
        assert gate.returncode == 1, args
        assert "gate: check.sh is a second gate script" in gate.stderr, (args, gate.stderr)


def test_the_fast_gate_sees_a_staged_rename_to_a_gate_name(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "build.sh").write_text(OLD_GATE)
    git(out, "add", "-A")
    git(out, "commit", "-qm", "init")
    git(out, "mv", "build.sh", "quality.sh")
    gate = run_gate(out, "--fast")
    assert gate.returncode == 1
    assert "gate: quality.sh is a second gate script" in gate.stderr


def test_a_gate_script_in_test_fixtures_passes(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    for d in (
        "evals/coding-rules/fixtures/a/scripts",
        "tests",
        "pkg/testdata",
        "pkg/test",
        "spec",
        "web/__fixtures__",
    ):
        (out / d).mkdir(parents=True)
        (out / d / "gate.sh").write_text(OLD_GATE)
    git(out, "add", "-A")
    for args in ((), ("--fast",)):
        gate = run_gate(out, *args)
        assert gate.returncode == 0, (args, gate.stdout + gate.stderr)
        assert "second gate script" not in gate.stderr


def test_an_old_gate_in_an_excluded_folder_passes(tmp_path):
    out = render(tmp_path / "p", ["shell"], shell_exclude=["vendor"])
    _repo(out)
    (out / "vendor").mkdir()
    (out / "vendor/check.sh").write_text(OLD_GATE)
    git(out, "add", "-A")
    for args in ((), ("--fast",)):
        gate = run_gate(out, *args)
        assert gate.returncode == 0, (args, gate.stdout + gate.stderr)


# (b) Projects in subfolders, and one CI step per toolchain image.


def test_only_rejects_a_section_the_repo_does_not_have(tmp_path):
    out = render(tmp_path / "p", ["python", "shell"])
    for args in (("--only", "dotnet"), ("--only",), ("--bogus",)):
        gate = run_gate(out, *args)
        assert gate.returncode == 2, args
        assert "sections: python shell local" in gate.stderr


def test_the_fast_gate_checks_python_in_its_project_folder(tmp_path):
    out = render(tmp_path / "p", ["python"], python_dir="app")
    _repo(out)
    assert (out / "app/uv.lock").is_file() and not (out / "uv.lock").exists()
    (out / "app/ok.py").write_text("x = 1\n")
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    gate = run_gate(out, "--fast", "--only", "python")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    # A staged file that ruff.toml excludes is not checked (issue #29).
    ruff = out / "app/ruff.toml"
    ruff.write_text(ruff.read_text().replace('["*.md"]', '["*.md", "vendored/**"]'))
    (out / "app/vendored").mkdir()
    (out / "app/vendored/old.py").write_text("x=[1,\n2]\n")
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    gate = run_gate(out, "--fast", "--only", "python")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    (out / "app/bad.py").write_text("x=[1,\n2]\n")
    subprocess.run(["git", "-C", str(out), "add", "app/bad.py"], check=True)
    gate = run_gate(out, "--fast", "--only", "python")
    assert gate.returncode != 0
    assert "bad.py" in gate.stdout + gate.stderr


def test_the_gate_and_refresh_run_each_language_in_its_folder(tmp_path):
    out = render_combo(tmp_path, "subfolders")
    gate = (out / "scripts/gate.sh").read_text()
    for line in ("python_dir='tools/py'", "dotnet_dir='backend'", "node_dir='frontend'"):
        assert line in gate
    deps = (out / "scripts/update-deps.sh").read_text()
    for d in ("tools/py", "backend", "frontend"):
        assert f"cd '{d}'" in deps


def test_ci_runs_each_language_in_its_own_image_when_there_are_several(tmp_path):
    out = render_combo(tmp_path, "subfolders")
    gate = {s["name"]: s for s in steps(out / ".onedev-buildspec.yml", "CI")}
    assert list(gate) == ["Gate Python", "Gate .NET", "Gate TypeScript", "Gate shell and local"]
    assert gate["Gate .NET"]["image"].startswith("mcr.microsoft.com/dotnet/sdk")
    assert gate["Gate TypeScript"]["image"].startswith("node:")
    assert "scripts/gate.sh --only dotnet" in gate["Gate .NET"]["interpreter"]["commands"]
    ts = gate["Gate TypeScript"]["interpreter"]["commands"]
    assert "(cd 'frontend' && npm ci" in ts and "scripts/gate.sh --only typescript" in ts
    assert "--only shell --only local" in gate["Gate shell and local"]["interpreter"]["commands"]
    weekly = [s["name"] for s in steps(out / ".onedev-buildspec.yml", "Update dependencies")]
    assert weekly == [
        "Refresh Python",
        "Refresh .NET",
        "Refresh TypeScript",
        "Refresh image pins",
        "Open a PR",
    ]


def test_ci_runs_the_whole_gate_in_one_step_when_one_image_has_every_tool(tmp_path):
    out = render(tmp_path / "p", ["python", "shell"])
    gate = steps(out / ".onedev-buildspec.yml", "CI")
    assert [s["name"] for s in gate] == ["Gate"]
    assert gate[0]["interpreter"]["commands"].strip().endswith("scripts/gate.sh --full")


def test_a_project_folder_must_stay_inside_the_repo(tmp_path):
    for bad in ("../x", "/abs", "x/", "./x"):
        with pytest.raises(ValueError):
            render(tmp_path / bad.replace("/", "_"), ["python"], python_dir=bad)


# (c) .NET: the test runner, lock files and a private feed are choices.


def test_only_the_mtp_runner_sets_a_test_runner_in_global_json(tmp_path):
    mtp = json.loads((render(tmp_path / "a", ["dotnet"]) / "global.json").read_text())
    assert mtp["test"] == {"runner": "Microsoft.Testing.Platform"}
    vstest = render(tmp_path / "b", ["dotnet"], dotnet_test_runner="vstest")
    assert "test" not in json.loads((vstest / "global.json").read_text())


def test_nuget_lock_files_are_optional(tmp_path):
    on = render(tmp_path / "a", ["dotnet"])
    assert "RestorePackagesWithLockFile" in (on / "Directory.Build.props").read_text()
    assert "dotnet restore --locked-mode" in (on / "scripts/gate.sh").read_text()
    off = render(tmp_path / "b", ["dotnet"], dotnet_lock_files=False)
    assert "RestorePackagesWithLockFile" not in (off / "Directory.Build.props").read_text()
    assert "--locked-mode" not in (off / "scripts/gate.sh").read_text()


def test_no_private_nuget_feed_by_default(tmp_path):
    out = render(tmp_path / "p", ["dotnet"])
    keys = [a.get("key") for a in ET.parse(out / "nuget.config").iter("add")]
    assert keys == ["nuget.org"]
    assert "NUGET_" not in (out / ".onedev-buildspec.yml").read_text()


def test_a_private_nuget_feed_maps_its_packages_and_reads_its_login_from_the_environment(
    tmp_path,
):
    out = render(
        tmp_path / "p",
        ["dotnet"],
        nuget_feed="https://nuget.pkg.github.com/owner/index.json",
        nuget_feed_name="github-owner",
        nuget_feed_packages=["Cleipnir.*"],
    )
    root = ET.parse(out / "nuget.config").getroot()
    sources = {a.get("key"): a.get("value") for a in root.iterfind("packageSources/add")}
    assert sources["github-owner"] == "https://nuget.pkg.github.com/owner/index.json"
    creds = {a.get("key"): a.get("value") for a in root.iter("add") if a.get("key") != "nuget.org"}
    assert creds["Username"] == "%NUGET_GITHUB_OWNER_USERNAME%"
    assert creds["ClearTextPassword"] == "%NUGET_GITHUB_OWNER_PASSWORD%"
    mapping = {
        s.get("key"): [p.get("pattern") for p in s]
        for s in root.iterfind("packageSourceMapping/packageSource")
    }
    assert mapping == {"github-owner": ["Cleipnir.*"], "nuget.org": ["*"]}
    for job, name in (("CI", "Gate .NET"), ("Update dependencies", "Refresh .NET")):
        step = {s["name"]: s for s in steps(out / ".onedev-buildspec.yml", job)}[name]
        env = {e["name"]: e["value"] for e in step["envVars"]}
        assert env == {
            "NUGET_GITHUB_OWNER_USERNAME": "@secret:NUGET_USER@",
            "NUGET_GITHUB_OWNER_PASSWORD": "@secret:NUGET_TOKEN@",
        }


# (d) TypeScript: approved install scripts, and no typed lint on plain JS.


def test_approved_install_scripts_go_in_npmrc(tmp_path):
    out = render(tmp_path / "a", ["typescript"], npm_allow_scripts=["sharp", "protobufjs"])
    lines = (out / ".npmrc").read_text().splitlines()
    assert "strict-allow-scripts=true" in lines and "allow-scripts=sharp,protobufjs" in lines
    none = (render(tmp_path / "b", ["typescript"]) / ".npmrc").read_text().splitlines()
    assert not [x for x in none if x.startswith("allow-scripts=")]


def test_eslint_does_not_type_check_plain_javascript(tmp_path):
    text = (render(tmp_path / "p", ["typescript"]) / "eslint.config.mjs").read_text()
    assert (
        '    files: ["**/*.{js,mjs,cjs}"],\n    extends: [tseslint.configs.disableTypeChecked],'
        in text
    )


# (e) Vendored shell scripts stay out of shellcheck and shfmt.


def test_the_gate_skips_excluded_shell_folders(tmp_path):
    bad = "#!/usr/bin/env bash\nif [ $1 ]; then\n      echo $1\nfi\n"
    for name, exclude, ok in (("a", [], False), ("b", [".ralph", "archive"], True)):
        out = render(tmp_path / name, ["shell"], shell_exclude=exclude)
        _repo(out)
        for d in (".ralph", "archive/old"):
            (out / d).mkdir(parents=True)
            (out / d / "run.sh").write_text(bad)
        subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
        for args in ((), ("--fast",)):
            gate = run_gate(out, *args)
            assert (gate.returncode == 0) == ok, (name, args, gate.stdout + gate.stderr)


# (g) The fast gate copes with a baseline that is untracked or missing.


def test_the_fast_gate_stages_an_untracked_baseline_whose_line_numbers_moved(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "conf.txt").write_text('token = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    subprocess.run(["git", "-C", str(out), "add", "conf.txt"], check=True)  # scan reads the index
    scan = subprocess.run(
        ["uvx", "--quiet", "--exclude-newer", "7 days", "--from", "detect-secrets"]
        + ["detect-secrets", "scan"],
        cwd=out,
        capture_output=True,
        text=True,
        check=True,
    )
    (out / ".secrets.baseline").write_text(scan.stdout)
    (out / "conf.txt").write_text('# a\ntoken = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    subprocess.run(["git", "-C", str(out), "add", "conf.txt"], check=True)
    gate = run_gate(out, "--fast")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert ".secrets.baseline" in git(out, "diff", "--cached", "--name-only").split()


def test_the_fast_gate_without_a_baseline_still_scans_and_says_how_to_make_one(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    os.remove(out / ".secrets.baseline")
    (out / "clean.txt").write_text("nothing here\n")
    subprocess.run(["git", "-C", str(out), "add", "clean.txt"], check=True)
    gate = run_gate(out, "--fast")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "no .secrets.baseline" in gate.stderr and "detect-secrets scan" in gate.stderr
    (out / "conf.txt").write_text('token = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    subprocess.run(["git", "-C", str(out), "add", "conf.txt"], check=True)
    assert run_gate(out, "--fast").returncode != 0


def test_the_fast_gate_keeps_the_line_patterns_the_baseline_adds(tmp_path):
    """--exclude-lines on the command line replaces the baseline's line filter,
    so a pattern a repo adds to .secrets.baseline must still skip its lines."""
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    baseline = json.loads((out / ".secrets.baseline").read_text())
    for f in baseline["filters_used"]:
        if f["path"] == "detect_secrets.filters.regex.should_exclude_line":
            # detect-secrets reads YAML as `key: "value"`, with no indent.
            f["pattern"].append(r'^\s*commit: "?[0-9a-f]{40}"?$')
    (out / ".secrets.baseline").write_text(json.dumps(baseline, indent=2) + "\n")
    pins = "pins:\n  a:\n    commit: dac13bb87468fe9d74a040d862720f6cc17a9565\n"
    (out / "pins.yaml").write_text(pins + "    ref: '@secret:DEMO_TOKEN@'\n")
    subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
    gate = run_gate(out, "--fast")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    (out / "pins.yaml").write_text(pins + "    token: 8b5a790caef530d7884440a6aa55c8911bf117be\n")
    subprocess.run(["git", "-C", str(out), "add", "pins.yaml"], check=True)
    assert run_gate(out, "--fast").returncode != 0


# (j) The full gate skips a clean tree that already passed it.


def _counting(tmp_path: Path, script: str = "") -> Path:
    """A committed shell render whose extension counts its runs outside the tree."""
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "scripts/gate.local.sh").write_text(
        "#!/usr/bin/env bash\nset -Eeuo pipefail\n"
        'printf "%s\\n" "$1" >>"$(git rev-parse --git-common-dir)/runs"\n' + script
    )
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    return out


def runs(out: Path) -> int:
    f = out / ".git/runs"
    return len(f.read_text().split()) if f.exists() else 0


def test_a_second_full_gate_on_the_same_clean_tree_runs_nothing(tmp_path):
    out = _counting(tmp_path)
    assert run_gate(out).returncode == 0
    again = run_gate(out)
    assert again.returncode == 0, again.stdout + again.stderr
    assert runs(out) == 1
    tree = git(out, "rev-parse", "HEAD^{tree}")
    assert again.stdout == (
        f"gate: tree {tree} already passed shell local; nothing changed."
        " Delete .git/gate-passed to run it again\n"
    )


def test_a_new_tree_runs_the_full_gate_again(tmp_path):
    out = _counting(tmp_path)
    assert run_gate(out).returncode == 0
    (out / "README.md").write_text("changed\n")
    assert run_gate(out).returncode == 0  # dirty: runs, and records nothing
    assert run_gate(out).returncode == 0
    git(out, "commit", "-q", "--no-verify", "-am", "readme")
    assert run_gate(out).returncode == 0  # a new clean tree: runs, then records
    assert run_gate(out).returncode == 0
    assert runs(out) == 4


def test_an_untracked_file_runs_the_full_gate_again(tmp_path):
    out = _counting(tmp_path)
    assert run_gate(out).returncode == 0
    # ruff . and pytest read an untracked Python file, so it is part of the tree.
    (out / "new.py").write_text("x = 1\n")
    assert run_gate(out).returncode == 0
    assert run_gate(out).returncode == 0
    assert runs(out) == 3


def test_other_sections_are_not_covered_by_an_earlier_pass(tmp_path):
    out = _counting(tmp_path)
    assert run_gate(out, "--only", "local").returncode == 0
    assert run_gate(out).returncode == 0
    assert run_gate(out, "--only", "local").returncode == 0
    assert runs(out) == 3


def test_a_failed_full_gate_records_nothing(tmp_path):
    out = _counting(tmp_path, 'test -f "$(git rev-parse --git-common-dir)/ok"\n')
    assert run_gate(out).returncode != 0
    (out / ".git/ok").touch()
    assert run_gate(out).returncode == 0
    assert run_gate(out).returncode == 0
    assert runs(out) == 2


def test_a_tree_that_changes_during_the_run_is_not_recorded(tmp_path):
    out = _counting(tmp_path, 'printf "x\\n" >>README.md\n')
    assert run_gate(out).returncode == 0
    git(out, "checkout", "-q", "README.md")
    assert run_gate(out).returncode == 0
    assert runs(out) == 2


def test_the_fast_gate_never_skips_a_passed_tree(tmp_path):
    out = _counting(tmp_path)
    assert run_gate(out).returncode == 0  # the full run records the stamp
    for _ in range(2):
        assert run_gate(out, "--fast").returncode == 0
    assert runs(out) == 3  # full, fast, fast


# (k) Tests run in parallel when the repo locks pytest-xdist.


def _python_tested(tmp_path: Path, **extra: object) -> Path:
    out = render(tmp_path / "p", ["python"], **extra)
    _repo(out)
    files = {
        "conftest.py": "",
        "app/__init__.py": "",
        "app/calc.py": "def add(a: int, b: int) -> int:\n    return a + b\n",
        "tests/test_math.py": (
            "from app.calc import add\n\n\ndef test_add() -> None:\n    assert add(1, 2) == 3\n"
        ),
    }
    for name, text in files.items():
        (out / name).parent.mkdir(parents=True, exist_ok=True)
        (out / name).write_text(text)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    return out


def test_the_full_gate_runs_tests_in_parallel_when_xdist_is_locked(tmp_path):
    out = _python_tested(tmp_path)
    gate = run_gate(out, "--only", "python")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "workers [1 item]" in gate.stdout


def test_the_full_gate_runs_tests_serially_without_xdist(tmp_path):
    out = _python_tested(tmp_path)
    subprocess.run(["uv", "remove", "-q", "--dev", "pytest-xdist"], cwd=out, check=True)
    git(out, "commit", "-q", "--no-verify", "-am", "no xdist")
    gate = run_gate(out, "--only", "python")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "workers" not in gate.stdout
    assert "tests/test_math.py ." in gate.stdout


# (l) The weekly refresh opens its PR through the OneDev API, with curl.

STUB_CURL = r"""#!/usr/bin/env bash
# Records each call and answers like OneDev. Reads -H @file and @- bodies.
log=$STUB_LOG
printf 'ARGS' >>"$log/args"; printf ' %q' "$@" >>"$log/args"; printf '\n' >>"$log/args"
url=
prev=
for a in "$@"; do
  if [[ "$prev" == -H && "$a" == @* ]]; then cat "${a#@}" >>"$log/headers"; fi
  if [[ "$prev" == --data-binary && "$a" == @- ]]; then cat >"$log/body"; cp "$log/body" "$log/body.$(basename "${*: -1}")"; fi
  [[ "$a" == http* ]] && url=$a
  [[ "$a" == -G ]] && listing=1
  prev=$a
done
case "$url" in
  */~api/projects/ids/team/demo) printf '%s' "${STUB_ID-42}" ;;
  */~api/repositories/*/default-branch) printf '%s' "${STUB_BASE-main}" ;;
  */~api/pulls) if [[ -n "${listing-}" ]]; then
      [[ -z "${STUB_LIST_FAIL-}" ]] || exit 22
      # A second listing is the one after the PR opened.
      if [[ -e "$log/listed" && -n "${STUB_OPEN_AFTER-}" ]]; then printf '%s' "$STUB_OPEN_AFTER"
      else printf '%s' "${STUB_OPEN-[]}"; fi
      : >"$log/listed"
    else printf '1987'; fi ;;
  */~api/pulls/1007) printf '{\n  "id" : 1007,\n  "buildCommitHash" : "%s"\n}\n' "${STUB_BUILT-}" ;;
  */~api/pulls/1007/current-builds) printf '[ {\n"jobName" : "CI",\n"commitHash" : "%s",\n"status" : "%s",\n"stepExecutions" : {\n"status" : "FAILED"\n}\n} ]\n' "${STUB_BUILT-}" "${STUB_CI-SUCCESSFUL}" ;;
  */~api/pulls/*/title | */~api/pulls/*/description | */~api/pulls/*/discard | */~api/pulls/*/merge) ;;
  */~api/repositories/42/branches/*) ;;
  # OneDev pretty-prints, one field per line, a space before each colon.
  */~api/pulls/1987) printf '{\n  "id" : 1987,\n  "number" : 7,\n  "numberScopeId" : 42\n}\n' ;;
  *) exit 22 ;;
esac
"""


STUB_GH = r"""#!/usr/bin/env bash
# Records each call and answers like gh.
printf '%s\0' "$@" >>"$STUB_LOG/gh"
[[ "$1 $2" == "pr create" ]] && printf 'https://github.test/team/demo/pull/7\n'
[[ "$1 $2" == "repo view" ]] && printf 'main\n'
[[ "$1" == api ]] && printf '%s\n' "${STUB_REQUIRED-2}"
[[ "$1 $2" == "workflow list" ]] && printf 'gate\n'
if [[ "$1 $2" == "pr list" ]]; then
  [[ -z "${STUB_LIST_FAIL-}" ]] || exit 1
  printf '%s' "${STUB_OPEN-}"
fi
exit 0
"""


def _refreshable(tmp_path: Path, forge: str = "onedev") -> tuple[Path, Path, dict[str, str]]:
    out = render(tmp_path / "p", ["shell"], forge=forge)
    _repo(out)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    origin = tmp_path / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
    git(out, "remote", "add", "origin", str(origin))
    git(out, "push", "-q", "--no-verify", "origin", "main")
    (out / "README.md").write_text("refreshed\n")
    stub = tmp_path / "stub"
    stub.mkdir()
    (stub / "curl").write_text(STUB_CURL)
    (stub / "curl").chmod(0o755)
    (stub / "gh").write_text(STUB_GH)
    (stub / "gh").chmod(0o755)
    log = tmp_path / "log"
    log.mkdir()
    env = {
        **os.environ,
        "PATH": f"{stub}:{os.environ['PATH']}",
        "STUB_LOG": str(log),
        "ODEV_HOST": "http://forge.test",
        "ODEV_PROJECT": "team/demo",
        "ODEV_TOKEN": "s3cret-token",
    }
    return out, log, env


def refresh(out: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(out / "scripts/update-deps.sh"), "--publish-only"],
        cwd=out,
        capture_output=True,
        text=True,
        env=env,
    )


def test_the_refresh_opens_its_pr_through_the_onedev_api(tmp_path):
    out, log, env = _refreshable(tmp_path)
    done = refresh(out, env)
    assert done.returncode == 0, done.stdout + done.stderr
    branch = git(out, "branch", "--show-current")
    assert branch == "chore/deps-weekly"
    assert git(out, "ls-remote", "origin", branch) != ""
    body = json.loads((log / "body").read_text())
    assert body["targetProjectId"] == body["sourceProjectId"] == 42
    assert (body["targetBranch"], body["sourceBranch"]) == ("main", branch)
    assert body["title"] == "chore(deps): refresh dependencies within their ranges"
    assert body["description"].startswith("## Why\n\nThe weekly refresh")
    assert "## Verification" in body["description"]
    assert body["mergeStrategy"] == "CREATE_MERGE_COMMIT"
    assert f"PR #7 from {branch}" in done.stdout


def _open_pr(number: int, branch: str) -> str:
    """One PR as OneDev prints it: its own fields at four spaces, the number after the branch."""
    return (
        f'  {{\n    "id" : {number + 1000},\n    "status" : "OPEN",\n    "targetBranch" : "main",\n'
        f'    "sourceBranch" : "{branch}",\n    "submitTimeGroups" : {{\n      "day" : 1\n    }},\n'
        f'    "number" : {number},\n    "commentCount" : 0,\n    "targetProjectId" : 42\n  }}'
    )


OPEN_UPDATE_PRS = (
    "[\n"
    + _open_pr(5, "feat/x")
    + ",\n"
    + _open_pr(9, "chore/deps-weekly")
    + ",\n"
    + _open_pr(4, "chore/update-deps-2026-11-09")
    + "\n]"
)
OPEN_CREATED = "[\n" + _open_pr(7, "chore/deps-weekly") + "\n]"
GITHUB_UPDATE_PRS = "9 chore/deps-weekly\n4 chore/update-deps-2026-11-09\n"
OPEN_OTHER_PRS = "[\n" + _open_pr(5, "feat/x") + "\n]"


@pytest.mark.parametrize(
    ("forge", "open_pr"), [("onedev", OPEN_UPDATE_PRS), ("github", GITHUB_UPDATE_PRS)]
)
def test_a_second_run_updates_the_one_pr_and_closes_an_old_style_one(tmp_path, forge, open_pr):
    out, log, env = _refreshable(tmp_path, forge=forge)
    done = refresh(out, {**env, "STUB_OPEN": open_pr})
    assert done.returncode == 0, done.stdout + done.stderr
    assert "PR #9 from chore/deps-weekly" in done.stdout
    if forge == "onedev":
        urls = (log / "args").read_text()
        assert "pulls/1009/title" in urls and "pulls/1009/description" in urls
        assert "pulls/1004/discard" in urls and "pulls/1987" not in urls
        assert "Replaced by #9" in (log / "body.discard").read_text()
    else:
        calls = (log / "gh").read_text().split("\0")
        assert "create" not in calls
        assert calls[calls.index("edit") - 1 :][:3] == ["pr", "edit", "9"]
        assert calls[calls.index("close") - 1 :][:3] == ["pr", "close", "4"]


@pytest.mark.parametrize("forge", ["onedev", "github"])
def test_the_refresh_stops_when_it_cannot_list_the_open_prs(tmp_path, forge):
    out, _, env = _refreshable(tmp_path, forge=forge)
    done = refresh(out, {**env, "STUB_LIST_FAIL": "1"})
    assert done.returncode == 1
    assert "forge: could not list the open PRs" in done.stderr
    assert git(out, "branch", "--show-current") == "main"


def test_an_open_pr_that_is_not_an_update_does_not_stop_the_refresh(tmp_path):
    out, log, env = _refreshable(tmp_path)
    done = refresh(out, {**env, "STUB_OPEN": OPEN_OTHER_PRS})
    assert done.returncode == 0, done.stdout + done.stderr
    query = (log / "args").read_text()
    assert 'query=\\"Target\\ Project\\"\\ is\\ \\"team/demo\\"\\ and\\ open' in query


def test_the_refresh_keeps_the_token_off_every_command_line(tmp_path):
    out, log, env = _refreshable(tmp_path)
    assert refresh(out, env).returncode == 0
    args = (log / "args").read_text()
    assert "s3cret-token" not in args
    assert args.count("--max-time 30") == 5
    headers = (log / "headers").read_text().splitlines()
    assert headers.count("Authorization: Bearer s3cret-token") == 5


def test_the_refresh_needs_its_onedev_settings_before_it_pushes(tmp_path):
    out, log, env = _refreshable(tmp_path)
    del env["ODEV_TOKEN"]
    done = refresh(out, env)
    assert done.returncode == 1
    assert "ODEV_HOST, ODEV_PROJECT and ODEV_TOKEN" in done.stderr
    assert git(out, "branch", "--show-current") == "main"
    assert not (log / "args").exists()


def test_the_weekly_job_builds_nothing_to_open_its_pr(tmp_path):
    for name in ("python", "subfolders"):
        out = render_combo(tmp_path, name)
        weekly = steps(out / ".onedev-buildspec.yml", "Update dependencies")
        commands = "\n".join(s["interpreter"]["commands"] for s in weekly)
        assert "Build odev" not in [s["name"] for s in weekly], name
        assert "odev " not in commands and ".git/bin" not in commands, name
        assert "golang" not in (out / ".onedev-buildspec.yml").read_text(), name


@pytest.mark.parametrize(
    ("answer", "message"),
    [
        ({"STUB_ID": "0"}, "OneDev has no project team/demo"),
        ({"STUB_ID": '{"error": "x"}'}, "OneDev has no project team/demo"),
        ({"STUB_BASE": ""}, "OneDev gave no usable default branch for team/demo"),
        ({"STUB_BASE": 'ma"in'}, "OneDev gave no usable default branch for team/demo"),
    ],
)
def test_the_refresh_refuses_an_answer_it_cannot_use(tmp_path, answer, message):
    out, log, env = _refreshable(tmp_path)
    done = refresh(out, {**env, **answer})
    assert done.returncode == 1
    assert f"forge: {message}\n" in done.stderr
    assert not (log / "body").exists()


def test_a_github_repo_gets_the_github_files_and_no_onedev_ones(tmp_path):
    out = render(tmp_path / "p", ["shell"], forge="github")
    for f in FORGE_FILES["github"]:
        assert (out / f).is_file(), f
    for f in FORGE_FILES["onedev"]:
        assert not (out / f).exists(), f
    assert "`gh`" in (out / "CLAUDE.md").read_text()
    assert "odev" not in (out / "CLAUDE.md").read_text()
    script = str(out / "scripts/forge/github.sh")
    subprocess.run(["shellcheck", "--rcfile", str(out / ".shellcheckrc"), script], check=True)
    subprocess.run(["shfmt", "-d", "-i", "2", "-ci", "-bn", script], check=True)


def test_github_ci_runs_the_whole_gate_in_one_job_when_one_image_has_every_tool(tmp_path):
    out = render(tmp_path / "p", ["python", "shell"], forge="github")
    jobs = yaml.safe_load((out / ".github/workflows/gate.yml").read_text())["jobs"]
    jobs.pop("deslop")
    assert list(jobs) == ["gate"]
    assert jobs["gate"]["container"].startswith("ghcr.io/astral-sh/uv:python")
    assert jobs["gate"]["steps"][-1]["run"] == "scripts/gate.sh --full"
    assert "env" not in jobs["gate"]


def test_github_ci_runs_each_language_in_its_own_job_with_its_logins(tmp_path):
    out = render(
        tmp_path / "p", COMBOS["subfolders"], forge="github", **EXTRA["subfolders"], **PRIVATE
    )
    jobs = yaml.safe_load((out / ".github/workflows/gate.yml").read_text())["jobs"]
    jobs.pop("deslop")
    assert [j["name"] for j in jobs.values()] == [
        "Gate Python",
        "Gate .NET",
        "Gate TypeScript",
        "Gate shell and local",
    ]
    runs = {k: [s["run"] for s in j["steps"] if "run" in s] for k, j in jobs.items()}
    assert jobs["gate-dotnet"]["container"].startswith("mcr.microsoft.com/dotnet/sdk")
    assert runs["gate-dotnet"][-1] == "scripts/gate.sh --only dotnet"
    assert runs["gate-typescript"][-2:] == [
        "cd 'frontend' && npm ci --no-audit --no-fund",
        "scripts/gate.sh --only typescript",
    ]
    assert runs["gate-shell"][-1] == "scripts/gate.sh --only shell --only local"
    assert set(jobs["gate-python"]["env"].values()) == {
        "${{ secrets.PKG_USER }}",
        "${{ secrets.PKG_TOKEN }}",
    }


def test_the_refresh_opens_its_pr_through_gh_on_github(tmp_path):
    out, log, env = _refreshable(tmp_path, forge="github")
    done = refresh(out, env)
    assert done.returncode == 0, done.stdout + done.stderr
    branch = git(out, "branch", "--show-current")
    assert git(out, "ls-remote", "origin", branch) != ""
    calls = (log / "gh").read_text().split("\0")
    create = calls[calls.index("create") - 1 :]
    assert create[:4] == ["pr", "create", "--head", branch]
    assert (
        create[create.index("--title") + 1]
        == "chore(deps): refresh dependencies within their ranges"
    )
    body = create[create.index("--body") + 1]
    assert body.startswith("## Why\n\nThe weekly refresh")
    assert "A person merges this PR when CI is green" in body
    assert f"PR https://github.test/team/demo/pull/7 from {branch}" in done.stdout


DIGEST = "sha256:" + "a" * 64
DIGEST2 = "sha256:" + "b" * 64


def _merge_set(log: Path) -> bool:
    return "--auto" in (log / "gh").read_text().split("\0")


@pytest.mark.parametrize(
    ("changed", "merges"),
    [
        ({"uv.lock": "x\n"}, True),
        ({"uv.lock": "x\n", "web/package.json": "{}\n", "web/package-lock.json": "{}\n"}, True),
        ({"scripts/deslop.pin": "version=9\n", ".config/dotnet-tools.json": "{}\n"}, True),
        ({"ci.yml": f"image: a:1@@{DIGEST2}\n"}, True),
        ({"uv.lock": "x\n", "src/app.py": "print()\n"}, False),
        ({"README.md": "refreshed\n"}, False),
        ({"ci.yml": f"image: a:2@@{DIGEST2}\n"}, False),
        ({"tools/dotnet-tools.json": "{}\n"}, False),
        ({"src/new.py": "print()\n"}, False),
        ({"ci.yml": f"-- note\nimage: a:2@@{DIGEST2}\n"}, False),
    ],
)
def test_a_pr_merges_itself_only_when_every_changed_file_is_a_dependency_file(
    tmp_path, changed, merges
):
    out, log, env = _refreshable(tmp_path, forge="github")
    git(out, "reset", "-q", "--hard")
    (out / "ci.yml").write_text(f"image: a:1@@{DIGEST}\n")
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "base")
    git(out, "push", "-q", "--no-verify", "origin", "main")
    for name, text in changed.items():
        (out / name).parent.mkdir(parents=True, exist_ok=True)
        (out / name).write_text(text)
    done = refresh(out, env)
    assert done.returncode == 0, done.stdout + done.stderr
    assert _merge_set(log) is merges
    if not merges:
        assert "A person merges this PR" in (log / "gh").read_text()


def test_the_github_refresh_sets_the_merge_on_the_head_the_gate_ran_on(tmp_path):
    out, log, env = _refreshable(tmp_path, forge="github")
    git(out, "reset", "-q", "--hard")
    (out / "uv.lock").write_text("x\n")
    git(out, "add", "-A")
    done = refresh(out, env)
    assert done.returncode == 0, done.stdout + done.stderr
    calls = (log / "gh").read_text().split("\0")
    assert calls[calls.index("run") - 1 :][:5] == [
        "workflow",
        "run",
        "gate.yml",
        "--ref",
        "chore/deps-weekly",
    ]
    merge = calls[calls.index("merge") - 1 :][:7]
    assert merge == [
        "pr",
        "merge",
        "7",
        "--auto",
        "--merge",
        "--match-head-commit",
        git(out, "rev-parse", "HEAD"),
    ]


def test_no_merge_is_set_when_github_requires_no_checks(tmp_path):
    out, log, env = _refreshable(tmp_path, forge="github")
    git(out, "reset", "-q", "--hard")
    (out / "uv.lock").write_text("x\n")
    done = refresh(out, {**env, "STUB_REQUIRED": "0"})
    assert done.returncode == 0, done.stdout + done.stderr
    assert "a person merges it" in done.stderr
    assert not _merge_set(log)


def _ready_to_merge(tmp_path: Path, moved: bool):
    """A published dependency PR, CI green on its merge preview; the branch moves after when asked."""
    out, log, env = _refreshable(tmp_path)
    git(out, "reset", "-q", "--hard")
    (out / "uv.lock").write_text("x\n")
    assert refresh(out, env).returncode == 0
    tip = git(out, "rev-parse", "HEAD")
    git(out, "switch", "-q", "main")
    preview = git(out, "commit-tree", f"{tip}^{{tree}}", "-p", "main", "-p", tip, "-m", "preview")
    git(out, "push", "-q", "--no-verify", "origin", f"{preview}:refs/pulls/7/merge")
    if moved:
        git(out, "switch", "-q", "chore/deps-weekly")
        (out / "uv.lock").write_text("y\n")
        git(out, "commit", "-qam", "late", "--no-verify")
        git(out, "push", "-q", "--no-verify", "origin", "chore/deps-weekly")
        git(out, "switch", "-q", "main")
    env |= {"STUB_OPEN": OPEN_CREATED, "STUB_BUILT": preview}
    (log / "args").unlink()
    return out, log, env


@pytest.mark.parametrize("moved", [False, True])
def test_onedev_merges_a_green_dependency_pr_only_while_its_head_is_the_one_ci_passed(
    tmp_path, moved
):
    out, log, env = _ready_to_merge(tmp_path, moved)
    done = subprocess.run(
        [str(out / "scripts/update-deps.sh"), "--merge-ready"],
        cwd=out,
        capture_output=True,
        text=True,
        env=env,
    )
    assert done.returncode == 0, done.stdout + done.stderr
    urls = (log / "args").read_text()
    assert ("pulls/1007/merge" in urls and "-X DELETE" in urls) is not moved
    assert moved is ("moved after CI" in done.stdout)


def test_the_github_refresh_runs_one_at_a_time_and_never_cancels_a_running_one(tmp_path):
    out = render(tmp_path / "p", ["shell"], forge="github")
    wf = yaml.safe_load((out / ".github/workflows/update-deps.yml").read_text())
    assert wf["concurrency"] == {"group": "update-deps", "cancel-in-progress": False}


@pytest.mark.parametrize("languages", [["shell"], ["python", "typescript"]])
def test_the_github_refresh_runs_weekly_in_the_gate_images_and_only_the_last_job_writes(
    tmp_path, languages
):
    out = render(tmp_path / "p", languages, forge="github", schedule_slot=0)
    wf = yaml.safe_load((out / ".github/workflows/update-deps.yml").read_text())
    gate = yaml.safe_load((out / ".github/workflows/gate.yml").read_text())["jobs"]
    assert wf[True]["schedule"] == [{"cron": "0 4 * * 1"}] and "workflow_dispatch" in wf[True]
    assert wf["permissions"] == {"contents": "read"}
    jobs = wf["jobs"]
    assert jobs["open-pr"]["permissions"] == {
        "contents": "write",
        "pull-requests": "write",
        "actions": "write",
    }
    assert (
        "workflow_dispatch"
        in yaml.safe_load((out / ".github/workflows/gate.yml").read_text())[True]
    )
    images = {j["container"] for j in jobs.values() if "container" in j}
    assert images <= {j["container"] for j in gate.values() if "container" in j}
    assert set(jobs["open-pr"]["needs"]) == set(jobs) - {"open-pr"}
    last = " ".join(s.get("run", "") for s in jobs["open-pr"]["steps"])
    assert "update-deps.sh --publish-only" in last
    refresh = " ".join(s.get("run", "") for s in jobs[next(iter(jobs))]["steps"])
    assert "git add -A" in refresh and "diff --cached" in refresh  # a new lockfile travels


def test_the_full_gate_runs_without_git_and_records_nothing(tmp_path):
    """CI images may lack git; the tree skip is an optimisation, not a need."""
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "scripts/gate.local.sh").write_text(
        '#!/usr/bin/env bash\nset -Eeuo pipefail\nprintf "%s\\n" "$1" >>"$(pwd)/ran.txt"\n'
    )
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    stub = tmp_path / "stub"
    stub.mkdir()
    (stub / "git").write_text("#!/usr/bin/env bash\nexit 127\n")
    (stub / "git").chmod(0o755)
    env = {**os.environ, "PATH": f"{stub}:{os.environ['PATH']}"}
    for _ in range(2):
        gate = subprocess.run(
            [str(out / "scripts/gate.sh"), "--only", "local"],
            cwd=out,
            capture_output=True,
            text=True,
            env=env,
        )
        assert gate.returncode == 0, gate.stdout + gate.stderr
        assert gate.stdout.endswith("gate: every check passed\n")
    assert (out / "ran.txt").read_text().split() == ["full", "full"]
    assert not (out / ".git/gate-passed").exists()


# (m) The bare gate checks only the sections that the diff touches.


def _scoped(tmp_path: Path, languages: list[str] | None = None, **extra: object) -> Path:
    """A committed repo on main whose extension counts its runs, then a branch."""
    out = render(tmp_path / "p", languages or ["shell"], **extra)
    _repo(out)
    (out / "scripts/gate.local.sh").write_text(
        "#!/usr/bin/env bash\nset -Eeuo pipefail\n"
        'printf "%s\\n" "$1" >>"$(git rev-parse --git-common-dir)/runs"\n'
    )
    (out / "scripts/gate.local.sh").chmod(0o755)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    git(out, "checkout", "-q", "-b", "feat/x")
    return out


def _commit_file(out: Path, name: str, text: str = "x\n") -> None:
    (out / name).parent.mkdir(parents=True, exist_ok=True)
    (out / name).write_text(text)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", f"change {name}")


def test_the_bare_gate_runs_no_section_for_a_docs_change(tmp_path):
    out = _scoped(tmp_path)
    _commit_file(out, "docs/notes.md", "notes\n")
    gate = run_scoped(out)
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "gate: scope: no section; 1 changed path(s) since main are docs." in gate.stdout
    assert runs(out) == 0


def test_ci_with_only_skips_an_untouched_section_but_keeps_shell_and_local(tmp_path):
    out = _scoped(tmp_path, ["python", "shell"])
    _commit_file(out, "docs/notes.md", "notes\n")
    env = {**os.environ, "CI": "1", "GATE_BASE": "main"}

    def gate(*args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(out / "scripts/gate.sh"), *args], cwd=out, capture_output=True, text=True, env=env
        )

    skipped = gate("--only", "python")
    assert skipped.returncode == 0, skipped.stdout + skipped.stderr
    assert "gate: scope: no section;" in skipped.stdout
    kept = gate("--only", "shell", "--only", "local")
    assert kept.returncode == 0, kept.stdout + kept.stderr
    assert "gate: scope: shell local (1 changed path(s) since main)." in kept.stdout
    assert (out / ".git/runs").read_text().split() == ["full"]


def test_ci_scopes_a_merge_preview_by_its_first_parent(tmp_path):
    out = _scoped(tmp_path, ["python", "shell"])
    _commit_file(out, "docs/notes.md", "notes\n")
    git(out, "checkout", "-q", "--detach", "main")
    git(out, "merge", "-q", "--no-ff", "--no-verify", "-m", "preview", "feat/x")
    git(out, "branch", "-q", "-D", "main", "feat/x")
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--only", "python"],
        cwd=out,
        capture_output=True,
        text=True,
        env={**os.environ, "CI": "1"},
    )
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "gate: scope: no section; 1 changed path(s) since HEAD^1" in gate.stdout


def test_ci_runs_a_touched_section_when_head_parent_is_not_the_base(tmp_path):
    out = _scoped(tmp_path, ["python", "shell"])
    _commit_file(out, "app.py", "x = 1\n")
    git(out, "checkout", "-q", "main")
    _commit_file(out, "docs/other.md", "other\n")
    git(out, "checkout", "-q", "feat/x")
    git(out, "merge", "-q", "--no-verify", "-m", "merge main into feat", "main")
    env = {**os.environ, "CI": "1", "GATE_BASE": "main"}
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--only", "python"],
        cwd=out,
        capture_output=True,
        text=True,
        env=env,
    )
    assert "gate: scope: python" in gate.stdout, gate.stdout + gate.stderr


def test_an_edit_to_the_gate_script_scopes_to_every_section(tmp_path):
    out = _scoped(tmp_path, ["python", "shell"])
    _commit_file(out, "scripts/gate.sh", (out / "scripts/gate.sh").read_text() + "\n# edit\n")
    env = {**os.environ, "CI": "1", "GATE_BASE": "main"}
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--only", "python", "--only", "shell"],
        cwd=out,
        capture_output=True,
        text=True,
        env=env,
    )
    assert "gate: scope: python shell (" in gate.stdout, gate.stdout + gate.stderr


def test_a_failed_target_fetch_makes_the_ci_gate_run_every_section(tmp_path):
    out = render(tmp_path / "p", ["python", "typescript"])
    step = {s["name"]: s for s in steps(out / ".onedev-buildspec.yml", "CI")}["Gate Python"]
    script = tmp_path / "step.sh"
    script.write_text(step["interpreter"]["commands"])
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "git").write_text('#!/bin/sh\n[ "$FETCH" = ok ]\n')
    (bin_dir / "git").chmod(0o755)
    work = tmp_path / "w"
    (work / "scripts").mkdir(parents=True)
    (work / "scripts/gate.sh").write_text('#!/bin/sh\necho "gate $*"\n')
    (work / "scripts/gate.sh").chmod(0o755)
    for fetch, full in (("ok", False), ("fail", True)):
        env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "FETCH": fetch}
        run = subprocess.run(["sh", str(script)], cwd=work, env=env, capture_output=True, text=True)
        assert run.returncode == 0, run.stderr
        assert ("gate --only python --full" in run.stdout) is full, (fetch, run.stdout)
        assert "gate --only python" in run.stdout or full


def test_the_bare_gate_runs_the_section_of_a_changed_script_in_full(tmp_path):
    out = _scoped(tmp_path)
    _commit_file(out, "bin/tool", '#!/usr/bin/env bash\nset -eu\necho "$1"\n')
    gate = run_scoped(out)
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "gate: scope: shell local (1 changed path(s) since main)." in gate.stdout
    assert "gate: passed shell local; run scripts/gate.sh --full before a PR" in gate.stdout
    assert (out / ".git/runs").read_text().split() == ["full"]


def test_the_bare_gate_skips_the_other_languages_sections(tmp_path):
    out = _scoped(tmp_path, ["python", "shell"])
    # The shell section would fail on this file, the Python section on none.
    _commit_file(out, "bad.sh", "echo $unquoted\n")
    _commit_file(out, "app/__init__.py", "")
    git(out, "reset", "-q", "--hard", "HEAD~1")
    gate = run_scoped(out)
    assert gate.returncode != 0
    assert "gate: scope: shell local" in gate.stdout
    assert "ruff" not in gate.stdout + gate.stderr


def test_the_bare_gate_runs_every_section_for_a_path_with_no_mapping(tmp_path):
    out = _scoped(tmp_path)
    _commit_file(out, "data/rows.csv", "a,b\n")
    gate = run_scoped(out)
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "gate: scope: every section, because no section covers data/rows.csv" in gate.stdout
    assert "passed shell local" not in gate.stdout
    assert "gate: every check passed" in gate.stdout


def test_a_docs_change_beside_an_unmapped_one_still_runs_every_section(tmp_path):
    out = _scoped(tmp_path)
    _commit_file(out, "README.md", "r\n")
    _commit_file(out, ".editorconfig", "root = true\n")
    gate = run_scoped(out)
    assert "every section, because no section covers .editorconfig" in gate.stdout


def test_the_bare_gate_runs_every_section_when_nothing_changed(tmp_path):
    out = _scoped(tmp_path)
    gate = run_scoped(out)
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "gate: scope: every section, because nothing changed since main" in gate.stdout
    assert runs(out) == 1


def test_the_bare_gate_runs_every_section_without_a_merge_base(tmp_path):
    out = _scoped(tmp_path)
    _commit_file(out, "docs/notes.md", "notes\n")
    env = {**os.environ, "GATE_BASE": "no-such-branch"}
    gate = subprocess.run(
        [str(out / "scripts/gate.sh")], cwd=out, capture_output=True, text=True, env=env
    )
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "every section, because there is no merge base with no-such-branch" in gate.stdout
    assert runs(out) == 1


def test_full_and_a_ci_variable_run_every_section_for_a_docs_change(tmp_path):
    out = _scoped(tmp_path)
    _commit_file(out, "docs/notes.md", "notes\n")
    assert run_scoped(out, "--full").returncode == 0
    assert runs(out) == 1
    git(out, "commit", "-q", "--allow-empty", "--no-verify", "-m", "new tree")
    (out / "more.txt").write_text("x\n")
    env = {**os.environ, "CI": "true"}
    gate = subprocess.run(
        [str(out / "scripts/gate.sh")], cwd=out, capture_output=True, text=True, env=env
    )
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "scope:" not in gate.stdout
    assert runs(out) == 2


def test_a_bare_run_that_names_sections_checks_those_in_full(tmp_path):
    out = _scoped(tmp_path)
    _commit_file(out, "docs/notes.md", "notes\n")
    gate = run_scoped(out, "--only", "local")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "scope:" not in gate.stdout
    assert runs(out) == 1


def test_full_does_not_combine_with_the_other_modes(tmp_path):
    out = _scoped(tmp_path)
    assert run_scoped(out, "--full", "--fast").returncode == 2
    assert run_scoped(out, "--fast", "--full").returncode == 2
    # The changed tier is retired (issue #46): its flag is a usage error.
    assert run_scoped(out, "--changed").returncode == 2


def test_the_ci_job_runs_the_full_gate(tmp_path):
    out = render(tmp_path / "p", ["python"])
    commands = "\n".join(
        s["interpreter"]["commands"] for s in steps(out / ".onedev-buildspec.yml", "CI")
    )
    assert "scripts/gate.sh --full" in commands


# (n) A section over its budget fails the gate.


def _slow_local(tmp_path: Path, seconds: int, **extra: object) -> Path:
    out = render(tmp_path / "p", ["shell"], **extra)
    _repo(out)
    (out / "scripts/gate.local.sh").write_text(
        f"#!/usr/bin/env bash\nset -Eeuo pipefail\nsleep {seconds}\n"
    )
    (out / "scripts/gate.local.sh").chmod(0o755)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    git(out, "checkout", "-q", "-b", "feat/x")
    return out


def test_a_section_over_its_budget_fails_and_names_its_slowest_step(tmp_path):
    out = _slow_local(tmp_path, 2, gate_fast_budget=1, gate_budget_reason="")
    gate = run_gate(out, "--fast", "--only", "local")
    assert gate.returncode == 1, gate.stdout + gate.stderr
    # The step sleeps 2 s; a slow machine reports 3 s or more, so the test reads the bound, not one value.
    took = re.search(r"gate: the local section took (\d+) s; its fast budget is 1 s", gate.stderr)
    assert took and int(took.group(1)) >= 2, gate.stderr
    assert "its slowest steps:" in gate.stderr and "gate.local.sh" in gate.stderr
    assert "gate_budget_reason" in gate.stderr
    assert int((out / ".gate/fast.local").read_text()) == int(took.group(1))


def test_a_section_inside_its_budget_passes_and_leaves_the_tree_clean(tmp_path):
    out = _slow_local(tmp_path, 1, gate_full_budget=30)
    gate = run_gate(out, "--full", "--only", "local")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert 1 <= int((out / ".gate/full.local").read_text()) <= 5
    assert git(out, "status", "--porcelain") == ""


def test_the_full_budget_is_off_until_a_project_sets_it(tmp_path):
    out = _slow_local(tmp_path, 2)
    assert run_gate(out, "--full", "--only", "local").returncode == 0
    out = _slow_local(tmp_path / "set", 2, gate_full_budget=1)
    gate = run_gate(out, "--full", "--only", "local")
    assert gate.returncode == 1
    assert "its full budget is 1 s" in gate.stderr


def test_a_python_section_over_its_budget_leaves_pytest_to_name_its_slowest_tests(tmp_path):
    out = _python_tested(tmp_path, gate_full_budget=1)
    (out / "tests/test_slow.py").write_text(
        "import time\n\n\ndef test_slow_one() -> None:\n    time.sleep(2)\n"
    )
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "slow")
    gate = run_gate(out, "--full", "--only", "python")
    assert gate.returncode == 1, gate.stdout + gate.stderr
    assert "test_slow.py::test_slow_one" in gate.stdout
    assert "gate: the python section took" in gate.stderr
    assert '"slowest durations" list' in gate.stderr


def test_a_budget_above_the_default_needs_a_written_reason(tmp_path):
    with pytest.raises(ValueError, match="needs a reason"):
        render(tmp_path / "a", ["shell"], gate_fast_budget=60, gate_budget_reason="")
    with pytest.raises(ValueError, match="needs a reason"):
        render(tmp_path / "b", ["shell"], gate_fast_budget=6, gate_budget_reason="  ")
    out = render(
        tmp_path / "c", ["shell"], gate_fast_budget=60, gate_budget_reason="a big test suite"
    )
    answers = yaml.safe_load((out / ".copier-answers.yml").read_text())
    assert answers["gate_fast_budget"] == 60
    assert answers["gate_budget_reason"] == "a big test suite"
    assert "fast 60" in (out / "scripts/gate.sh").read_text()


def test_the_defaults_are_the_issue_budgets(tmp_path):
    out = render(tmp_path / "p", ["shell"], gate_fast_budget=5, gate_budget_reason="")
    assert "fast 5, full none" in (out / "scripts/gate.sh").read_text()


# (o) The gate prints source lines against test lines and never fails on them.


def test_the_gate_prints_source_lines_against_test_lines_and_never_fails(tmp_path):
    out = _python_tested(tmp_path, test_folders=["spec"])
    git(out, "checkout", "-q", "-b", "feat/x")
    (out / "app/new.py").write_text("A = 1\nB = 2\n")
    (out / "tests/test_new.py").write_text("".join(f"T{i} = {i}\n" for i in range(6)))
    (out / "spec").mkdir()
    (out / "spec/case.py").write_text("X = 1\n")
    (out / "README.md").write_text("docs\n" * 9)
    git(out, "add", "-A")
    gate = run_gate(out, "--full", "--only", "python")
    assert gate.returncode == 0, gate.stdout + gate.stderr
    assert "gate: test lines: +2 source, +7 test against" in gate.stdout
    assert "(3.50 test lines for each source line)" in gate.stdout
    assert not (out / ".gate/test-budget").exists()
    fast = run_gate(out, "--fast", "--only", "python")
    assert "test lines" not in fast.stdout


def test_a_bad_test_folder_answer_is_refused(tmp_path):
    for i, bad in enumerate(
        (
            {"test_folders": "spec"},
            {"test_folders": ["../x"]},
            {"test_folders": ["/abs"]},
            {"test_folders": [3]},
        )
    ):
        with pytest.raises(ValueError):
            render(tmp_path / str(i), ["python"], **bad)


# --- The Deslop PR check

DESLOP_SCRIPTS = TEMPLATE / "template/scripts"
CLUSTER = {
    "id": "c1a2",
    "kind": "nearly_identical",
    "mass": 90,
    "intersects_diff": True,
    "occurrences": [
        {"path": "new.ts", "start_line": 1, "end_line": 9, "in_diff": True},
        {"path": "old.ts", "start_line": 5, "end_line": 13, "in_diff": False},
    ],
}


def _report(tmp_path: Path, clusters: list[dict]) -> Path:
    f = tmp_path / "report.json"
    f.write_text(
        json.dumps({"clusters": clusters, "metrics": {"diff": {"duplication_percent": 12.34}}})
    )
    return f


def _comment(
    tmp_path: Path, *args: str, gh_list: str = ""
) -> tuple[subprocess.CompletedProcess[str], str]:
    stub = tmp_path / "stub"
    stub.mkdir(parents=True, exist_ok=True)
    # gh answers a listing with gh_list; any other call is logged with its stdin.
    (stub / "gh").write_text(
        '#!/usr/bin/env bash\nif [[ " $* " == *" --paginate "* ]]; then echo "$GH_LIST"; exit 0; fi\n'
        'echo "gh $*" >>"$STUB_LOG"; cat >>"$STUB_LOG"\n'
    )
    (stub / "gh").chmod(0o755)
    log = tmp_path / "gh.log"
    env = {
        **os.environ,
        "PATH": f"{stub}:{os.environ['PATH']}",
        "GH_LIST": gh_list,
        "STUB_LOG": str(log),
        "GH_TOKEN": "s3cret-token",
        "GITHUB_REPOSITORY": "o/r",
    }
    done = subprocess.run(
        [str(DESLOP_SCRIPTS / "deslop-comment.sh"), *args], capture_output=True, text=True, env=env
    )
    assert "s3cret-token" not in done.stdout + done.stderr
    return done, log.read_text() if log.exists() else ""


def test_the_comment_names_each_duplicate_and_where_its_twin_is(tmp_path):
    done, _ = _comment(tmp_path, "--report", str(_report(tmp_path, [CLUSTER])))
    assert done.returncode == 0, done.stderr
    assert done.stdout.startswith(
        "<!-- deslop-pr -->\n**Deslop:** This PR adds 1 duplicate (12.3% of its added lines)."
    )
    assert (
        "1. **nearly identical** `c1a2`: new `new.ts:1-9`; existing copy `old.ts:5-13`"
        in done.stdout
    )
    assert "keep it with a line `<cluster id> keep <reason>` in `.deslop-decisions`" in done.stdout
    assert "dry run" in done.stdout


def test_the_comment_edits_its_earlier_comment_instead_of_adding_one(tmp_path):
    report = str(_report(tmp_path, [CLUSTER]))
    args = ("--report", report, "--forge", "github", "--pr", "7", "--post")
    done, log = _comment(tmp_path, *args, gh_list="42")
    assert done.returncode == 0, done.stderr
    assert "gh api -X PATCH repos/o/r/issues/comments/42 -F body=@-" in log
    assert "POST" not in log
    done, log = _comment(tmp_path / "fresh", *args)
    assert "gh api -X POST repos/o/r/issues/7/comments" in log


def test_with_no_duplicates_it_updates_an_old_comment_but_posts_no_new_one(tmp_path):
    args = ("--report", str(_report(tmp_path, [])), "--forge", "github", "--pr", "7", "--post")
    _, log = _comment(tmp_path, *args)
    assert log == ""
    _, log = _comment(tmp_path / "old", *args, gh_list="42")
    assert "No new duplicates." in log


def _decisions(tmp_path: Path, clusters: list[dict], kept: str) -> subprocess.CompletedProcess[str]:
    (tmp_path / ".deslop-decisions").write_text(kept)
    return subprocess.run(
        [str(DESLOP_SCRIPTS / "deslop-decisions.sh"), "--report", str(_report(tmp_path, clusters))],
        cwd=tmp_path,
        capture_output=True,
        text=True,
    )


def test_a_duplicate_the_pr_adds_holds_the_merge_until_it_is_fixed_or_kept(tmp_path):
    old = {**CLUSTER, "id": "old9", "intersects_diff": False}
    held = _decisions(tmp_path, [CLUSTER, old], "")
    assert held.returncode == 3
    assert "c1a2  nearly identical  new.ts:1-9" in held.stderr and "old9" not in held.stderr
    kept = _decisions(
        tmp_path, [CLUSTER, old], "# kept on purpose\nc1a2 keep the parsers will diverge\n"
    )
    assert kept.returncode == 0, kept.stderr
    fixed = _decisions(tmp_path, [old], "")
    assert fixed.returncode == 0, fixed.stderr


def test_a_keep_line_with_no_reason_is_refused(tmp_path):
    done = _decisions(tmp_path, [CLUSTER], "c1a2 keep\n")
    assert done.returncode == 1 and "line 1 is not" in done.stderr


def _deslop_release(tmp_path: Path, exit_code: int) -> dict[str, str]:
    """A fake release tarball, a pin for it, and the env that points the script at both."""
    pkg = tmp_path / "pkg/deslop-0.40.1-linux-x64"
    pkg.mkdir(parents=True)
    (pkg / "deslop").write_text(
        f'#!/usr/bin/env bash\necho "$@" >"$STUB_LOG"\n'
        'while [ $# -gt 0 ]; do [ "$1" = --diff ] && { iconv -f utf-8 -t utf-8 "$2" >/dev/null || exit 2; }; shift; done\n'
        f"exit {exit_code}\n"
    )
    (pkg / "deslop").chmod(0o755)
    rel = tmp_path / "rel/v0.40.1"
    rel.mkdir(parents=True)
    tar = rel / "deslop-0.40.1-linux-x64.tar.gz"
    subprocess.run(["tar", "-czf", str(tar), "-C", str(tmp_path / "pkg"), "."], check=True)
    return {
        **os.environ,
        "DESLOP_DOWNLOAD_BASE": f"file://{tmp_path}/rel",
        "STUB_LOG": str(tmp_path / "argv"),
    }


def _deslop_pr(
    tmp_path: Path, sha: str = "", exit_code: int = 0, latin1: bool = False
) -> subprocess.CompletedProcess[str]:
    env = _deslop_release(tmp_path, exit_code)
    tar = tmp_path / "rel/v0.40.1/deslop-0.40.1-linux-x64.tar.gz"
    sha = sha or hashlib.sha256(tar.read_bytes()).hexdigest()
    repo = tmp_path / "repo"
    shutil.copytree(DESLOP_SCRIPTS, repo / "scripts", ignore=shutil.ignore_patterns("forge"))
    (repo / "scripts/deslop.pin").write_text(f"version=0.40.1\nsha256={sha}\n")
    subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
    _repo(repo)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "--no-verify", "-m", "init")
    if latin1:
        git(repo, "checkout", "-q", "-b", "feat/x")
        (repo / "fixture.txt").write_bytes(b"caf\xe9\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "--no-verify", "-m", "fixture")
    return subprocess.run(
        [str(repo / "scripts/deslop-pr.sh"), "main" if latin1 else "HEAD"],
        cwd=repo,
        capture_output=True,
        text=True,
        env=env,
    )


def test_the_pr_check_scans_only_the_diff_and_never_fails_over_a_finding(tmp_path):
    done = _deslop_pr(tmp_path)
    assert done.returncode == 0, done.stderr
    argv = (tmp_path / "argv").read_text()
    assert "--only-changed --no-incremental" in argv and "--no-fail-over" in argv


def test_a_diff_with_a_latin1_line_still_scans(tmp_path):
    done = _deslop_pr(tmp_path, latin1=True)
    assert done.returncode == 0, done.stderr


def test_a_wrong_checksum_or_a_deslop_crash_fails_the_check(tmp_path):
    wrong = _deslop_pr(tmp_path / "a", "0" * 64)
    assert wrong.returncode == 1 and "does not match the checksum" in wrong.stderr
    crash = _deslop_pr(tmp_path / "b", exit_code=7)
    assert crash.returncode == 1 and "Deslop crashed (exit 7)" in crash.stderr


@pytest.mark.parametrize("forge", ["github", "onedev"])
def test_ci_runs_the_deslop_check_on_pull_requests_with_the_pinned_release(tmp_path, forge):
    out = render(tmp_path / "p", ["shell"], forge=forge, deslop_fail_over="10")
    ci = (
        out / (".github/workflows/gate.yml" if forge == "github" else ".onedev-buildspec.yml")
    ).read_text()
    assert (
        "scripts/deslop-pr.sh" in ci
        and "--fail-over 10" in ci
        and "scripts/deslop-comment.sh" in ci
        and "scripts/deslop-decisions.sh --report .deslop-pr/deslop-report.json" in ci
    )
    pin = (out / "scripts/deslop.pin").read_text()
    assert pin == (DESLOP_SCRIPTS / "deslop.pin").read_text()
    assert "version=0.42.0\n" in pin and "sha256=a06b7f63" in pin and "min_age_days=0\n" in pin
    if forge == "github":
        jobs = yaml.safe_load(ci)["jobs"]
        assert jobs["deslop"]["permissions"]["pull-requests"] == "write"
        assert [j for j in jobs if "permissions" in jobs[j]] == ["deslop"]
    else:
        assert "@secret:ONEDEV_COMMENT_TOKEN@" in ci


STUB_ODEV_CURL = r"""#!/usr/bin/env bash
# Answers OneDev's REST calls; logs each call's argv and body (never the header).
url=${*: -1}
case "$url" in
  */pulls/9/comments) echo "$COMMENTS" ;;
  */~api/pulls) [[ "$*" == *'"Target Project" is'* ]] && echo '[{"id": 9}]' || exit 22 ;;
  */users/me) echo '{"id": 3}' ;;
  *) echo "curl $*" >>"$STUB_LOG"; cat >>"$STUB_LOG" ;;
esac
"""


def _onedev_comment(tmp_path: Path, comments: str) -> tuple[subprocess.CompletedProcess[str], str]:
    stub = tmp_path / "stub"
    stub.mkdir(parents=True)
    (stub / "curl").write_text(STUB_ODEV_CURL)
    (stub / "curl").chmod(0o755)
    log = tmp_path / "curl.log"
    env = {
        **os.environ,
        "PATH": f"{stub}:{os.environ['PATH']}",
        "COMMENTS": comments,
        "STUB_LOG": str(log),
        "ODEV_HOST": "http://forge.test",
        "ODEV_PROJECT": "team/demo",
        "ODEV_TOKEN": "s3cret-token",
    }
    args = [
        "--report",
        str(_report(tmp_path, [CLUSTER])),
        "--forge",
        "onedev",
        "--pr",
        "7",
        "--post",
    ]
    done = subprocess.run(
        [str(DESLOP_SCRIPTS / "deslop-comment.sh"), *args], capture_output=True, text=True, env=env
    )
    text = log.read_text() if log.exists() else ""
    assert "s3cret-token" not in done.stdout + done.stderr + text
    return done, text


def test_on_onedev_the_comment_is_edited_with_a_bare_body_or_added_with_a_user(tmp_path):
    done, log = _onedev_comment(
        tmp_path / "a", '[{"id": 5, "content": "<!-- deslop-pr -->\\nold"}]'
    )
    assert done.returncode == 0, done.stderr
    assert "-X POST" in log and "/~api/pull-request-comments/5" in log
    assert "\n<!-- deslop-pr -->\n**Deslop:** This PR adds 1 duplicate" in log
    done, log = _onedev_comment(tmp_path / "b", "[]")
    assert done.returncode == 0, done.stderr
    assert '"requestId": 9' in log and '"userId": 3' in log and "pull-request-comments/" not in log


def _deslop_refresh(
    tmp_path: Path, published: str, pin_age: str | None, sha256: str | None
) -> tuple[subprocess.CompletedProcess[str], str, str]:
    """update-deps' Deslop section against a stub release v0.42.1, published then."""
    out = render(tmp_path / "p", ["shell"], forge="github")
    pin = out / "scripts/deslop.pin"
    text = pin.read_text().replace("min_age_days=0\n", "")
    pin.write_text(text + (f"min_age_days={pin_age}\n" if pin_age is not None else ""))
    stub = tmp_path / "stub"
    stub.mkdir()
    release = (
        '    "tag_name": "v0.42.1",\\n    "draft": false,\\n    "prerelease": false,\\n'
        f'    "published_at": "{published}",\\n'
    )
    sum_line = (
        f"printf '{sha256}  deslop-0.42.1-linux-x64.tar.gz\\n'; exit 0" if sha256 else "exit 22"
    )
    (stub / "curl").write_text(
        "#!/usr/bin/env bash\n"
        f"if [[ \" $* \" == *releases\\?* ]]; then printf '{release}'; exit 0; fi\n"
        f'if [[ " $* " == *.sha256* ]]; then {sum_line}; fi\nexit 22\n'
    )
    (stub / "curl").chmod(0o755)
    env = {**os.environ, "PATH": f"{stub}:{os.environ['PATH']}"}
    before = pin.read_text()
    done = subprocess.run(
        [str(out / "scripts/update-deps.sh"), "--refresh-only", "--only", "deslop"],
        cwd=out, capture_output=True, text=True, env=env,
    )  # fmt: skip
    return done, before, pin.read_text()


def test_the_deps_refresh_keeps_the_pin_when_the_release_has_no_checksum(tmp_path):
    done, before, after = _deslop_refresh(tmp_path, "2020-01-01T00:00:00Z", "0", None)
    assert "Deslop stays at 0.42.0: no checksum for 0.42.1" in done.stdout
    assert after == before


def test_deslop_takes_a_release_at_once_with_min_age_zero_and_waits_seven_days_without_it(tmp_path):
    today = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    sha = "b" * 64
    done, _, after = _deslop_refresh(tmp_path / "zero", today, "0", sha)
    assert "Deslop moves from 0.42.0 to 0.42.1" in done.stdout, done.stdout + done.stderr
    assert (
        "version=0.42.1\n" in after and f"sha256={sha}\n" in after and "min_age_days=0\n" in after
    )
    done, before, after = _deslop_refresh(tmp_path / "default", today, None, sha)
    assert after == before, done.stdout


def _cl(cid: str, mass: int, kind: str = "nearly_identical") -> dict:
    return {"id": cid, "kind": kind, "mass": mass, "occurrences": [
        {"path": f"{cid}.py", "start_line": 1, "end_line": 2},
        {"path": "b.py", "start_line": 5, "end_line": 6},
    ]}  # fmt: skip


STUB_GH_ISSUES = """#!/usr/bin/env bash
if [[ " $* " == *" --paginate "* ]]; then [[ "$*" == *state=all* ]] && echo "$GH_LIST" || echo "[]"; exit 0; fi
echo "gh $*" >>"$STUB_LOG"; [[ " $* " == *" body=@- "* ]] && { cat >>"$STUB_LOG"; echo >>"$STUB_LOG"; }; exit 0
"""
STUB_ONEDEV_ISSUES = """#!/usr/bin/env bash
url=${*: -1}
case "$url" in
  */projects/ids/*) echo 7 ;;
  *) if [[ "$*" == *" -G "* ]]; then echo "$GH_LIST"; else
       body=$(cat)
       if [[ -n "${NO_TRIAGE:-}" && "$body" == *Triage* ]]; then exit 22; fi
       if [[ -n "${NO_TRACKING:-}" && "$body" == *'"Type"'* ]]; then exit 22; fi
       printf 'curl %s\\n%s\\n' "$*" "$body" >>"$STUB_LOG"
     fi ;;
esac
"""


def _nightly(tmp_path, clusters, prev=None, listed="[]", forge="github", emb=False):
    """Runs deslop-issues.sh --post against stub gh/curl; returns the log and the new state."""
    stub = tmp_path / "stub"
    stub.mkdir(parents=True)
    tool = "gh" if forge == "github" else "curl"
    (stub / tool).write_text(STUB_GH_ISSUES if forge == "github" else STUB_ONEDEV_ISSUES)
    (stub / tool).chmod(0o755)
    rep = tmp_path / "r.json"
    rep.write_text(json.dumps({"clusters": clusters, "embedding_provenance": {} if emb else None,
        "metrics": {"duplication_percent": 2.34, "duplicated_loc": 5, "analysed_loc": 200}}))  # fmt: skip
    state = tmp_path / "state/s.json"
    if prev is not None:
        state.parent.mkdir()
        state.write_text(json.dumps({"runs": [], "clusters": prev}))
    log = tmp_path / "log"
    env = {**os.environ, "PATH": f"{stub}:{os.environ['PATH']}", "GH_LIST": listed, "STUB_LOG": str(log),
        "GH_TOKEN": "s3cret-token", "GITHUB_REPOSITORY": "o/r", "ODEV_HOST": "http://forge.test",
        "ODEV_PROJECT": "team/demo", "ODEV_TOKEN": "s3cret-token"}  # fmt: skip
    done = subprocess.run([str(DESLOP_SCRIPTS / "deslop-issues.sh"), "--report", str(rep), "--state", str(state),
        "--forge", forge, "--sha", "abcdef1234", "--post"], capture_output=True, text=True, env=env)  # fmt: skip
    text = log.read_text() if log.exists() else ""
    assert done.returncode == 0, done.stderr
    assert "s3cret-token" not in done.stdout + done.stderr + text
    return text, json.loads(state.read_text())


def _marked(num, marker, state="open"):
    return {"number": num, "state": state, "body": f"<!-- {marker} -->\nx"}


def test_the_first_nightly_run_files_no_cluster_issue_but_records_the_baseline(tmp_path):
    log, state = _nightly(tmp_path, [_cl("aa", 90), _cl("bb", 80)])
    assert log.count("gh api -X POST repos/o/r/issues ") == 1 and "title=Deslop nightly" in log
    assert "labels[]=tracking" in log and "needs-triage" not in log
    assert "Baseline recorded: 2 clusters" in log and set(state["clusters"]) == {"aa", "bb"}


def test_three_new_clusters_out_of_five_file_three_issues_largest_first(tmp_path):
    cl = [_cl("c1", 10), _cl("c2", 50), _cl("c3", 40), _cl("c4", 30), _cl("old", 99)]
    log, state = _nightly(tmp_path, cl, prev={"old": "nearly_identical"})
    titles = [ln for ln in log.splitlines() if "title=Duplicate code" in ln]
    assert [t.split("cluster ")[1][:2] for t in titles] == ["c2", "c3", "c4"]
    assert (
        all("labels[]=needs-triage" in t for t in titles) and "<!-- deslop-cluster: c2 -->" in log
    )
    assert "c1.py" not in log and len(state["runs"]) == 1


def test_a_cluster_with_an_issue_open_or_closed_by_a_person_is_not_filed_again(tmp_path):
    listed = json.dumps(
        [_marked(4, "deslop-cluster: c1"), _marked(5, "deslop-cluster: c2", "closed")]
    )
    log, _ = _nightly(tmp_path, [_cl("c1", 9), _cl("c2", 8), _cl("c3", 7), _cl("old", 1)],
        prev={"old": "identical"}, listed=listed)  # fmt: skip
    assert log.count("title=Duplicate code") == 1 and "cluster c3" in log


def test_a_gone_cluster_is_commented_and_closed_and_the_standing_issue_is_edited(tmp_path):
    listed = json.dumps([_marked(4, "deslop-cluster: dead"), _marked(9, "deslop-nightly")])
    log, state = _nightly(
        tmp_path, [_cl("old", 5)], prev={"old": "identical", "dead": "identical"}, listed=listed
    )
    assert "gh api -X POST repos/o/r/issues/4/comments" in log and "Gone in abcdef1." in log
    assert "gh api -X PATCH repos/o/r/issues/4 -f state=closed" in log
    assert (
        "gh api -X PATCH repos/o/r/issues/9 -F body=@-" in log and "title=Deslop nightly" not in log
    )
    assert set(state["clusters"]) == {"old"}


def test_a_night_without_embeddings_does_not_close_behavioural_clusters(tmp_path):
    prev = {"bee": "same_behavior"}
    log, state = _nightly(
        tmp_path, [_cl("old", 5)], prev=prev, listed=json.dumps([_marked(4, "deslop-cluster: bee")])
    )
    assert "state=closed" not in log and "bee" in state["clusters"]
    small = [_cl("s1", 100, "same_behavior"), _cl("s2", 400, "same_behavior")]
    log, _ = _nightly(tmp_path / "e", small, prev={"x": "identical"}, emb=True)
    assert log.count("title=Duplicate code") == 1 and "cluster s2" in log


def test_on_onedev_issues_carry_the_triage_field_and_close_with_a_comment(tmp_path):
    listed = json.dumps(
        [{"id": 31, "state": "Open", "description": "<!-- deslop-cluster: dead -->"}]
    )
    log, _ = _nightly(tmp_path, [_cl("new1", 5), _cl("old", 1)], prev={"old": "identical", "dead": "identical"},
        listed=listed, forge="onedev")  # fmt: skip
    assert '"fields": {' in log and '"Triage": "needs-triage"' in log and '"projectId": 7' in log
    assert "/~api/issues/31/state-transitions" in log and '"comment": "Gone in abcdef1."' in log
    assert "/~api/issues/31/description" not in log and "/~api/issues/" in log
    assert (
        log.count('"Triage"') == 2
    )  # the cluster issue, and the standing one with Type: tracking too
    assert '"Type": "tracking"' in log and log.count('"Type"') == 1


def test_on_onedev_a_project_without_the_triage_field_still_gets_its_issues(tmp_path, monkeypatch):
    monkeypatch.setenv("NO_TRIAGE", "1")
    log, _ = _nightly(
        tmp_path, [_cl("new1", 5), _cl("old", 1)], prev={"old": "identical"}, forge="onedev"
    )
    assert "Duplicate code at new1.py:1" in log and '"Triage"' not in log


def test_on_onedev_a_refused_tracking_value_still_records_the_baseline_and_files_with_triage(
    tmp_path, monkeypatch
):
    monkeypatch.setenv("NO_TRACKING", "1")
    log, state = _nightly(tmp_path, [_cl("c1", 5)], forge="onedev")
    assert state["clusters"] == {"c1": "nearly_identical"}
    assert '"title": "Deslop nightly"' in log and '"Triage": "needs-triage"' in log
    assert '"Type"' not in log


def test_the_full_scan_has_no_diff_and_asks_for_embeddings_only_when_given_an_address(tmp_path):
    env = _deslop_release(tmp_path, 0)
    repo = tmp_path / "repo"
    shutil.copytree(DESLOP_SCRIPTS, repo / "scripts", ignore=shutil.ignore_patterns("forge"))
    tar = tmp_path / "rel/v0.40.1/deslop-0.40.1-linux-x64.tar.gz"
    (repo / "scripts/deslop.pin").write_text(
        f"version=0.40.1\nsha256={hashlib.sha256(tar.read_bytes()).hexdigest()}\n"
    )
    for extra, want in (([], False), (["--embeddings", "http://h:11434"], True)):
        done = subprocess.run(
            [str(repo / "scripts/deslop-pr.sh"), "--full", *extra],
            cwd=repo,
            env=env,
            capture_output=True,
            text=True,
        )
        argv = (tmp_path / "argv").read_text()
        assert done.returncode == 0 and "--diff" not in argv
        assert ("--embeddings required --embedding-endpoint http://h:11434" in argv) == want


@pytest.mark.parametrize("forge", ["github", "onedev"])
def test_the_nightly_job_runs_the_full_scan_and_files_issues_with_its_own_token(tmp_path, forge):
    out = render(
        tmp_path / "p",
        ["shell"],
        forge=forge,
        deslop_embeddings_endpoint="http://ollama.internal:11434",
        schedule_slot=30,
    )
    if forge == "github":
        wf = yaml.safe_load((out / ".github/workflows/deslop-nightly.yml").read_text())
        job = wf["jobs"]["deslop-nightly"]
        assert job["permissions"] == {"contents": "read", "issues": "write"}
        assert wf["permissions"] == {"contents": "read"} and wf[True]["schedule"]
        runs = " ".join(s["run"] for s in job["steps"] if "run" in s)
        assert "deslop-pr.sh --full" in runs and "--forge github" in runs
        assert "--embeddings" not in runs  # a hosted runner cannot reach the LAN
    else:
        ci = (out / ".onedev-buildspec.yml").read_text()
        assert (
            "@secret:ONEDEV_ISSUES_TOKEN@" in ci and "0 30 3 * * ?" in ci and "--forge onedev" in ci
        )
        assert "--full --embeddings http://ollama.internal:11434" in ci


# (s) Each project's scheduled jobs at its own slot, and the gate holds the pattern.


@pytest.mark.parametrize(
    ("slot", "nightly", "weekly"),
    [(0, (0, 1), (0, 4, "MON")), (13, (5, 2), (5, 4, "SUN")), (59, (55, 5), (40, 4, "THU"))],
)
def test_each_slot_gives_its_own_nightly_and_weekly_time(tmp_path, slot, nightly, weekly):
    (nm, nh), (wm, wh, day) = nightly, weekly
    onedev = render(tmp_path / "o", ["shell"], forge="onedev", schedule_slot=slot)
    spec = (onedev / ".onedev-buildspec.yml").read_text()
    assert f"cronExpression: 0 {nm} {nh} * * ?" in spec
    assert f"cronExpression: 0 {wm} {wh} ? * {day}" in spec
    assert f"cronExpression: 0 {wm} {(int(wh) + 3) % 24} * * ?" in spec  # the daily merge job
    github = render(tmp_path / "g", ["shell"], forge="github", schedule_slot=slot)
    flows = github / ".github/workflows"
    dow = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"].index(day)
    assert yaml.safe_load((flows / "deslop-nightly.yml").read_text())[True]["schedule"] == [
        {"cron": f"{nm} {nh} * * *"}
    ]
    assert yaml.safe_load((flows / "update-deps.yml").read_text())[True]["schedule"] == [
        {"cron": f"{wm} {wh} * * {dow}"}
    ]


def test_the_default_slot_comes_from_the_project_name(tmp_path):
    slots = {
        name: yaml.safe_load(
            (
                render(tmp_path / name, ["shell"], project_name=name) / ".copier-answers.yml"
            ).read_text()
        )["schedule_slot"]
        for name in ("tend", "garmin-core")
    }
    assert all(0 <= s <= 59 for s in slots.values()) and len(set(slots.values())) == 2


@pytest.mark.parametrize(
    ("forge", "drift"),
    [
        ("onedev", "drop the nightly"),
        ("onedev", "move the refresh"),
        ("onedev", "drop the decision check"),
        ("github", "drop the refresh"),
    ],
)
def test_the_full_gate_fails_when_the_ci_pattern_drifts(tmp_path, forge, drift):
    out = render(tmp_path / "p", ["shell"], forge=forge, schedule_slot=13)
    _repo(out)
    git(out, "add", "-A")
    assert run_gate(out, "--only", "shell").returncode == 0
    spec = out / ".onedev-buildspec.yml"
    if drift == "drop the nightly":
        spec.write_text(spec.read_text().replace("- name: Deslop nightly", "- name: Scan"))
    elif drift == "move the refresh":
        spec.write_text(spec.read_text().replace("0 5 4 ? * SUN", "0 0 4 ? * MON"))
    elif drift == "drop the decision check":
        spec.write_text(spec.read_text().replace("scripts/deslop-decisions.sh", "true"))
    else:
        (out / ".github/workflows/update-deps.yml").unlink()
    gate = run_gate(out, "--only", "shell")
    assert gate.returncode == 1, gate.stdout + gate.stderr
    assert "as the template seeds it (schedule_slot 13)" in gate.stderr


# (t) pstack, scoped by tier, in an app or a command-line tool.

PSTACK = "pstack@example-marketplace"


@pytest.mark.parametrize(
    ("kind", "plugin", "seeded"),
    [("app", PSTACK, True), ("cli", PSTACK, True), ("library", PSTACK, False), ("app", "", False)],
)
def test_an_app_or_cli_turns_pstack_on_scoped_by_tier(tmp_path, kind, plugin, seeded):
    out = render(tmp_path / "p", ["shell"], kind=kind, pstack_plugin=plugin)
    settings, mandate = out / ".claude/settings.json", out / ".claude/pstack-mandate.md"
    assert settings.exists() is seeded and mandate.exists() is seeded
    if seeded:
        data = json.loads(settings.read_text())
        assert data["enabledPlugins"] == {PSTACK: True}
        assert "pstack-mandate.md" in data["hooks"]["SessionStart"][0]["hooks"][0]["command"]
        assert "Tier 2" in mandate.read_text() and "without poteto-mode" in mandate.read_text()


def test_the_full_gate_fails_when_an_app_loses_its_pstack_hook(tmp_path):
    out = render(tmp_path / "p", ["shell"], kind="app", pstack_plugin=PSTACK)
    _repo(out)
    git(out, "add", "-A")
    assert run_gate(out, "--only", "shell").returncode == 0
    (out / ".claude/settings.json").write_text('{"enabledPlugins": {}}\n')
    gate = run_gate(out, "--only", "shell")
    assert gate.returncode == 1, gate.stdout + gate.stderr
    assert "needs pstack-mandate.md" in gate.stderr


SPEC_DROPS = [
    # (languages, answers, text to cut from the spec, job the message names)
    (["shell"], {}, "git fetch --quiet origin", "a job that pull requests run"),
    (["shell"], {}, "scripts/gate.sh --full", "a job that pull requests run"),
    (["shell"], {"trust_green_ci": True}, "Trust a green CI build", 'the job "CI on main"'),
]


def full_gate_in_ci(out: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(out / "scripts/gate.sh"), "--full"],
        cwd=out,
        capture_output=True,
        text=True,
        env={**os.environ, "CI": "1"},
    )


def test_the_full_gate_names_a_seeded_spec_line_that_a_project_lacks(tmp_path):
    for i, (langs, answers, cut, job) in enumerate(SPEC_DROPS):
        out = render(tmp_path / f"p{i}", langs, **answers)
        _repo(out)
        git(out, "add", "-A")
        if not answers and i == 0:
            seeded = full_gate_in_ci(out)
            assert seeded.returncode == 0, seeded.stdout + seeded.stderr
        spec = out / ".onedev-buildspec.yml"
        spec.write_text(spec.read_text().replace(cut, "removed"))
        gate = full_gate_in_ci(out)
        assert gate.returncode != 0, cut
        err = gate.stderr.replace("\\", "")
        assert f"needs {job} with" in err and cut.split()[0] in err, err


@pytest.mark.parametrize("langs", [["python"], ["dotnet", "python", "shell"]])
def test_every_gate_call_in_the_seeded_spec_has_a_drift_pattern(tmp_path, langs):
    """A template PR that adds a scripts/gate.sh call to the spec must add its pattern."""
    out = render(tmp_path / "p", langs, trust_green_ci=True)
    patterns = re.findall(
        r"^\s+['\"]([^|'\"]+)\|(.+?)['\"]$",
        (out / "scripts/gate.sh").read_text().split("pattern=(", 1)[1].split("\n    )", 1)[0],
        re.M,
    )
    spec = yaml.load((out / ".onedev-buildspec.yml").read_text(), Loader=SpecLoader)
    calls = [
        ("PR" if job["name"] == "CI" else job["name"], line.strip())
        for job in spec["jobs"]
        for step in job["steps"]
        for line in step.get("interpreter", {}).get("commands", "").splitlines()
        if "scripts/gate.sh" in line and not line.strip().startswith("#")
    ]
    assert calls
    for job, line in calls:
        # A pattern of its own: it matches this call and no other call of the job.
        own = [
            rx
            for j, rx in patterns
            if j == job
            and re.search(rx, line)
            and not any(re.search(rx, other) for o, other in calls if o == job and other != line)
        ]
        assert own, (job, line)


def test_a_default_branch_answer_names_the_branch_ci_runs_on(tmp_path, monkeypatch):
    out = render(tmp_path / "p", ["shell"], default_branch="master")
    spec = (out / ".onedev-buildspec.yml").read_text()
    assert "branches: master" in spec and "branches: main" not in spec
    assert "refs/heads/master:refs/remotes/origin/master" in spec
    gh = render(tmp_path / "g", ["shell"], forge="github", default_branch="master")
    assert "branches: [master]" in (gh / ".github/workflows/gate.yml").read_text()
    # The branch-name check lets a commit on the default branch through, whatever it is called.
    monkeypatch.delenv("GITHUB_HEAD_REF", raising=False)
    dev = render(tmp_path / "d", ["shell"], default_branch="develop")
    _repo(dev)
    assert git(dev, "branch", "--show-current").strip() == "develop"
    assert run_gate(dev, "--fast").returncode == 0


def test_the_ci_gate_passes_a_pull_request_that_changes_the_secret_baseline(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / "conf.txt").write_text('token = "AKIA' + 'IOSFODNN7EXAMPLE"\n')
    git(out, "add", "-A")
    scan = subprocess.run(
        [
            "uvx",
            "--quiet",
            "--exclude-newer",
            "7 days",
            "--from",
            "detect-secrets",
            "detect-secrets",
            "scan",
        ],
        cwd=out,
        capture_output=True,
        text=True,
        check=True,
    )
    (out / ".secrets.baseline").write_text(scan.stdout)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    (out / ".secrets.baseline").write_text(scan.stdout.replace("\n  ", "\n   ", 1))
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "touch the baseline")
    gate = subprocess.run(
        [str(out / "scripts/gate.sh"), "--full", "--only", "shell"],
        cwd=out,
        capture_output=True,
        text=True,
        env={**os.environ, "CI": "1", "GATE_BASE": "HEAD~1"},
    )
    assert gate.returncode == 0, gate.stdout + gate.stderr


def test_the_drift_check_takes_the_seeded_lines_in_any_job_that_pull_requests_run(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    git(out, "add", "-A")
    spec = out / ".onedev-buildspec.yml"
    seeded = spec.read_text()
    spec.write_text(seeded.replace("- name: CI\n", "- name: backend-test\n", 1))
    renamed = full_gate_in_ci(out)
    assert renamed.returncode == 0, renamed.stdout + renamed.stderr
    spec.write_text(seeded.replace("- !PullRequestUpdateTrigger", "- !BranchUpdateTrigger", 1))
    none = full_gate_in_ci(out)
    assert none.returncode != 0 and "needs a job that pull requests run with" in none.stderr
