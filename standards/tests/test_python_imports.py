"""Python: the full gate holds the repo's import contracts."""

from __future__ import annotations

import subprocess

from test_template import _python_tested, git, run_gate

CONTRACT = """[importlinter]
root_package = app

[importlinter:contract:domain-is-pure]
name = The domain imports no data access
type = forbidden
source_modules = app.domain
forbidden_modules = app.store
"""


def test_the_full_gate_fails_a_broken_import_contract(tmp_path):
    out = _python_tested(tmp_path)
    subprocess.run(["uv", "add", "-q", "--dev", "import-linter"], cwd=out, check=True)
    (out / ".importlinter").write_text(CONTRACT)
    (out / "app/store.py").write_text("ROWS: list[int] = []\n")
    (out / "app/domain.py").write_text("from app.store import ROWS\n\nCOUNT = len(ROWS)\n")
    git(out, "add", "-A")
    git(out, "commit", "-q", "--no-verify", "-m", "a domain that reads the store")
    broken = run_gate(out, "--only", "python")
    assert broken.returncode != 0
    assert "The domain imports no data access BROKEN" in broken.stdout + broken.stderr

    (out / "app/domain.py").write_text("COUNT = 0\n")
    git(out, "commit", "-q", "--no-verify", "-am", "a pure domain")
    kept = run_gate(out, "--only", "python")
    assert kept.returncode == 0, kept.stdout + kept.stderr
