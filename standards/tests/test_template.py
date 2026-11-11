"""Render every bundle combination and check what each one produces.

The template must never ship a file that fails its own rules, so rendered
scripts go through shellcheck and shfmt here too.
"""

from __future__ import annotations

import json
import os
import tomllib
import subprocess
import time
import xml.etree.ElementTree as ET
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
    ".onedev/pull-request-template.md",
    ".onedev-buildspec.yml",
    ".githooks/pre-commit",
    "scripts/gate.sh",
    "scripts/gate.md",
    "scripts/update-deps.sh",
    ".secrets.baseline",
]


# A cold uvx start can pass the default 5 s. A test that sets
# gate_budget_reason itself gets the answers it names, and the defaults for the rest.
SLOW_BUDGETS = {
    "gate_budget_reason": "the tests start uvx cold",
    "gate_fast_budget": 60,
}


PROFILE = {"tenants_now": "one", "tenants_later": "one", "users_now": "one", "users_later": "one"}
# What an environment file gives every repo (instances/example.yml).
INSTANCE = {"vault_command": "vault-read"}


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
    for f in COMMON_FILES:
        assert (out / f).is_file(), f
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
        out / ".githooks/pre-commit",
        *out.glob("scripts/install-cargo-deny.sh"),
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
    git(main, "worktree", "add", "-q", str(wt))
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
    git(main, "worktree", "add", "-q", str(wt))
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


@pytest.mark.parametrize(
    ("name", "refused"),
    [("notes.md", True), ("uv.lock", False), ("pkg/fixtures/data.json", False)],
)
def test_the_fast_gate_refuses_a_new_file_over_the_token_cap(tmp_path, name, refused):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    (out / name).parent.mkdir(parents=True, exist_ok=True)
    (out / name).write_text("x" * 20_004 + "\n")
    git(out, "add", name)
    gate = run_gate(out, "--fast")
    assert (gate.returncode == 1) is refused, gate.stdout + gate.stderr
    if refused:
        assert f"gate: {name} is 5002 tokens (bytes / 4); its limit is 5000" in gate.stderr


def test_a_listed_large_file_may_shrink_and_never_grow(tmp_path):
    out = render(tmp_path / "p", ["shell"])
    _repo(out)
    big, listed = out / "big.md", out / ".gate-size-baseline"
    big.write_text("x" * 40_000)
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "init")
    assert run_scoped(out, "--size-baseline").returncode == 0
    assert listed.read_text() == "10000 big.md\n"
    for size, passes, line in (
        (40_004, False, "10000 big.md\n"),
        (30_000, True, "7500 big.md\n"),
        (100, True, ""),
    ):
        big.write_text("x" * size)
        git(out, "add", "-A")
        gate = run_gate(out, "--fast")
        assert (gate.returncode == 0) is passes, (size, gate.stdout + gate.stderr)
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
  if [[ "$prev" == --data-binary && "$a" == @- ]]; then cat >"$log/body"; fi
  [[ "$a" == http* ]] && url=$a
  prev=$a
done
case "$url" in
  */~api/projects/ids/team/demo) printf '%s' "${STUB_ID-42}" ;;
  */~api/repositories/*/default-branch) printf '%s' "${STUB_BASE-main}" ;;
  */~api/pulls) printf '1987' ;;
  # OneDev pretty-prints, one field per line, a space before each colon.
  */~api/pulls/1987) printf '{\n  "id" : 1987,\n  "number" : 7,\n  "numberScopeId" : 42\n}\n' ;;
  *) exit 22 ;;
esac
"""


def _refreshable(tmp_path: Path) -> tuple[Path, Path, dict[str, str]]:
    out = render(tmp_path / "p", ["shell"])
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
    assert branch.startswith("chore/update-deps-")
    assert git(out, "ls-remote", "origin", branch) != ""
    body = json.loads((log / "body").read_text())
    assert body["targetProjectId"] == body["sourceProjectId"] == 42
    assert (body["targetBranch"], body["sourceBranch"]) == ("main", branch)
    assert body["title"] == "chore(deps): refresh dependencies within their ranges"
    assert body["description"].startswith("## Why\n\nThe weekly refresh")
    assert "## Verification" in body["description"]
    assert f"opened PR #7 from {branch}" in done.stdout


def test_the_refresh_keeps_the_token_off_every_command_line(tmp_path):
    out, log, env = _refreshable(tmp_path)
    assert refresh(out, env).returncode == 0
    args = (log / "args").read_text()
    assert "s3cret-token" not in args
    assert args.count("--max-time 30") == 4
    headers = (log / "headers").read_text().splitlines()
    assert headers.count("Authorization: Bearer s3cret-token") == 4


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
    assert f"update-deps: {message}\n" in done.stderr
    assert not (log / "body").exists()


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
    git(out, "checkout", "-q", "-b", "feat")
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
    git(out, "checkout", "-q", "-b", "feat")
    return out


def test_a_section_over_its_budget_fails_and_names_its_slowest_step(tmp_path):
    out = _slow_local(tmp_path, 2, gate_fast_budget=1, gate_budget_reason="")
    gate = run_gate(out, "--fast", "--only", "local")
    assert gate.returncode == 1, gate.stdout + gate.stderr
    assert "gate: the local section took 2 s; its fast budget is 1 s" in gate.stderr
    assert "its slowest steps:" in gate.stderr and "gate.local.sh" in gate.stderr
    assert "gate_budget_reason" in gate.stderr
    assert (out / ".gate/fast.local").read_text() == "2\n"


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
    git(out, "checkout", "-q", "-b", "feat")
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
