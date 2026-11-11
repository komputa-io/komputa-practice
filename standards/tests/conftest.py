import pytest


@pytest.fixture(autouse=True)
def _no_inherited_gate_environment(monkeypatch):
    """A rendered repo in a temp folder must not see the caller's gate environment.

    A caller may export GATE_BASE; CI sets CI, which makes the bare gate run in full.
    """
    monkeypatch.delenv("GATE_BASE", raising=False)
    monkeypatch.delenv("CI", raising=False)
