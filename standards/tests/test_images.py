"""The weekly refresh moves container image digests, at least seven days old."""

from __future__ import annotations

import json
import subprocess

from test_template import _refreshable, git, refresh

OLD, AGED, FRESH = "sha256:" + "a" * 64, "sha256:" + "b" * 64, "sha256:" + "c" * 64
# skopeo: the tag aged:1 now names an image built long ago, fresh:2 one built today.
STUB_SKOPEO = f"""#!/usr/bin/env bash
case "$*" in
  *docker://ghcr.io/acme/aged:1) printf '{{\\n  "Digest": "{AGED}",\\n  "Created": "2020-01-01T00:00:00Z"\\n}}\\n' ;;
  *docker://fresh:2) printf '{{"Digest": "{FRESH}", "Created": "%s"}}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ;;
  # A reproducible build's epoch date, and a date six days 23 hours old written at UTC-12.
  *docker://epoch:1) printf '{{"Digest": "{FRESH}", "Created": "1970-01-01T00:00:00Z"}}' ;;
  *docker://offset:1) printf '{{"Digest": "{FRESH}", "Created": "%s"}}' "$(TZ=Etc/GMT+12 date -d '-7 days +1 hour' +%Y-%m-%dT%H:%M:%S-12:00)" ;;
  *) exit 1 ;;
esac
"""
COMPOSE = f"""services:
  a:
    image: ghcr.io/acme/aged:1@{OLD} # keep this comment
  b:
    image: mirror.test/ghcr.io/acme/aged:1@{OLD}
  c:
    image: fresh:2@{OLD}
  d:
    image: gone:3@{OLD}
  e:
    image: postgres:17
  f:
    image: epoch:1@{OLD}
  g:
    image: offset:1@{OLD}
"""
# A OneDev buildspec escapes @ as @@; the moved digest keeps the escape.
BUILDSPEC = f"""jobs:
- name: test
  services:
  - image: ghcr.io/acme/aged:1@@{OLD}
"""
CSHARP = """var db = builder.AddPostgres("db").WithImageTag("17");
var sso = builder.AddContainer("sso", "x").WithImageSHA256("abc");
var pg = new PostgreSqlBuilder("postgres:17").Build();
"""


def test_the_refresh_moves_only_a_digest_older_than_seven_days_and_names_the_rest(tmp_path):
    out, log, env = _refreshable(tmp_path)
    (tmp_path / "stub/skopeo").write_text(STUB_SKOPEO)
    (tmp_path / "stub/skopeo").chmod(0o755)
    (out / "compose.yml").write_text(COMPOSE)
    (out / "Program.cs").write_text(CSHARP)
    (out / ".onedev-buildspec.yml").write_text(BUILDSPEC)
    git(out, "add", "-A")

    done = subprocess.run(
        [str(out / "scripts/update-deps.sh"), "--refresh-only", "--only", "images"],
        cwd=out,
        capture_output=True,
        text=True,
        env=env,
    )
    assert done.returncode == 0, done.stdout + done.stderr
    # Only the digest of aged:1 moves; the mirror's same digest is a different image.
    assert (out / "compose.yml").read_text() == COMPOSE.replace(
        f"image: ghcr.io/acme/aged:1@{OLD}", f"image: ghcr.io/acme/aged:1@{AGED}"
    )
    assert (out / "Program.cs").read_text() == CSHARP
    assert (out / ".onedev-buildspec.yml").read_text() == BUILDSPEC.replace(f"@@{OLD}", f"@@{AGED}")
    for line in (
        f"ghcr.io/acme/aged:1 moves from {OLD} to {AGED}",
        f"fresh:2 stays at {OLD}: {FRESH} is under seven days old",
        f"epoch:1 stays at {OLD}: {FRESH} has no build date, or one before 2000",
        f"offset:1 stays at {OLD}: {FRESH} is under seven days old",
        f"gone:3 stays at {OLD}: the lookup failed",
        f"mirror.test/ghcr.io/acme/aged:1 stays at {OLD}: the lookup failed",
        "compose.yml:11: postgres:17 is a tag with no digest",
        "Program.cs:1: 17 is a tag with no digest",
        "Program.cs:2: a digest with no tag beside it",
        "Program.cs:3: postgres:17 is a tag with no digest",
    ):
        assert f"update-deps: images: {line}" in done.stdout, done.stdout

    published = refresh(out, env)
    assert published.returncode == 0, published.stdout + published.stderr
    desc = json.loads((log / "body").read_text())["description"]
    pins = desc.split("\n\n## Image pins\n\n")[1]
    assert f"- ghcr.io/acme/aged:1 moves from {OLD} to {AGED}\n" in pins
    assert f"- fresh:2 stays at {OLD}: {FRESH} is under seven days old" in pins
