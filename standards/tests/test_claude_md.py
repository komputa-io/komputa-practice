"""The seeded CLAUDE.md: the house skills and the project profile."""

from __future__ import annotations

from test_template import PROFILE, render


def test_claude_md_names_the_house_skill_for_each_language(tmp_path):
    out = render(tmp_path / "p", ["python", "shell"])
    text = (out / "CLAUDE.md").read_text()
    assert "`house-python`" in text and "`house-shell`" in text
    assert "house-dotnet" not in text


def test_claude_md_declares_the_project_profile(tmp_path):
    out = render(tmp_path / "p", ["shell"], **{**PROFILE, "users_later": "many"})
    text = (out / "CLAUDE.md").read_text()
    assert (
        "- Tenants now: one\n- Tenants later: one\n- Users now: one\n- Users later: many\n" in text
    )
