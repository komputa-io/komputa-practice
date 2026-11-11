""".NET: the weekly refresh and the Features guard."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest
from test_template import render

# (l2) The .NET refresh moves a GlobalPackageReference and leaves the SDK alone.

STUB_DOTNET_REFRESH = r"""#!/usr/bin/env bash
# Records each dotnet call. Like dotnet-outdated 4.8, an outdated run without
# --no-restore falls back to dotnet add, which refuses a GlobalPackageReference.
printf '%s\n' "$*" >>"$DOTNET_LOG"
case "$1" in
  --version) echo 10.0.100 ;;
  --list-sdks) printf '9.0.300 [%s]\n10.0.100 [%s]\n' "$SDK_ROOT" "$SDK_ROOT" ;;
  restore)
    # NuGetAudit's restore failure names each package with a known advisory.
    if [[ "$*" == restore && -n "${STUB_ADVISORY-}" ]]; then
      echo "/r/App.csproj : error NU1903: Warning As Error: Package '$STUB_ADVISORY' 13.6.4 has a known high severity vulnerability, https://github.com/advisories/GHSA-0000"
      exit 1
    fi
    ;;
  outdated)
    if [[ " $* " != *' --no-restore '* ]] && grep -q '<GlobalPackageReference' Directory.Packages.props; then
      echo 'An error occurred while upgrading demo' >&2
      exit 3
    fi
    ;;
esac
# The advisory check's plain restore runs first; only the final restore counts as "restore".
[[ "$*" == restore || "$1" != "${STUB_TAMPER_ON-}" ]] || printf '<!-- rewritten -->\n' >>"$SDK_ROOT/10.0.100/NuGet.targets"
exit 0
"""


def _dotnet_refresh(
    tmp_path: Path, **env_extra: str
) -> tuple[subprocess.CompletedProcess[str], list[str]]:
    """Runs the .NET refresh of a fresh render with a recording dotnet."""
    out = render(tmp_path / "d", ["dotnet"])
    assert "<GlobalPackageReference" in (out / "Directory.Packages.props").read_text()
    sdk = tmp_path / "sdk"
    (sdk / "10.0.100/Sdks/Microsoft.NET.Sdk/targets").mkdir(parents=True)
    (sdk / "10.0.100/NuGet.targets").write_text("<Project />\n")
    (sdk / "10.0.100/Sdks/Microsoft.NET.Sdk/targets/Microsoft.NET.Sdk.props").write_text(
        "<Project />\n"
    )
    stub = tmp_path / "stub"
    stub.mkdir()
    (stub / "dotnet").write_text(STUB_DOTNET_REFRESH)
    (stub / "dotnet").chmod(0o755)
    log = tmp_path / "dotnet.log"
    log.write_text("")
    env = {
        **os.environ,
        "PATH": f"{stub}:{os.environ['PATH']}",
        "DOTNET_LOG": str(log),
        "SDK_ROOT": str(sdk),
        **env_extra,
    }
    done = subprocess.run(
        [str(out / "scripts/update-deps.sh"), "--refresh-only", "--only", "dotnet"],
        cwd=out,
        capture_output=True,
        text=True,
        env=env,
    )
    return done, log.read_text().splitlines()


def test_the_dotnet_refresh_moves_a_global_package_reference(tmp_path):
    done, calls = _dotnet_refresh(tmp_path)
    assert done.returncode == 0, done.stdout + done.stderr
    outdated = [c for c in calls if c.startswith("outdated")]
    assert outdated == ["outdated --version-lock Major --older-than 7 --upgrade --no-restore"]
    assert "restore --force-evaluate" in calls


def test_the_dotnet_refresh_takes_a_security_fix_without_the_wait(tmp_path):
    done, calls = _dotnet_refresh(tmp_path, STUB_ADVISORY="Aspire.Hosting")
    assert done.returncode == 0, done.stdout + done.stderr
    outdated = [c for c in calls if c.startswith("outdated")]
    assert outdated == [
        "outdated --version-lock Major --include Aspire.Hosting --upgrade --no-restore",
        "outdated --version-lock Major --older-than 7 --upgrade --no-restore",
    ]
    assert "Aspire.Hosting has a known advisory" in done.stderr


@pytest.mark.parametrize(("step", "restored"), [("outdated", False), ("restore", True)])
def test_the_dotnet_refresh_fails_when_the_sdk_files_change(tmp_path, step, restored):
    done, calls = _dotnet_refresh(tmp_path, STUB_TAMPER_ON=step)
    assert done.returncode == 1
    assert "update-deps: the refresh changed these SDK files: " in done.stderr
    assert "10.0.100/NuGet.targets" in done.stderr
    # A broken NuGet.targets is caught before the restore that it would break.
    assert ("restore --force-evaluate" in calls) == restored


# (l3) A Features project stays host-neutral: the build refuses ASP.NET Core in it.


def _dotnet_sdk() -> bool:
    try:
        sdks = subprocess.run(
            ["dotnet", "--list-sdks"], capture_output=True, text=True, check=False
        )
    except FileNotFoundError:
        return False
    return bool(sdks.stdout.strip())


@pytest.mark.skipif(not _dotnet_sdk(), reason="needs a .NET SDK")
def test_a_features_project_may_not_reference_aspnet_core(tmp_path):
    out = render(tmp_path / "f", ["dotnet"])
    project = out / "src/Demo.Features"
    project.mkdir(parents=True)
    (project / "Marker.cs").write_text("namespace Demo.Features;\n\npublic static class Marker;\n")
    csproj = project / "Demo.Features.csproj"
    body = '<Project Sdk="{sdk}"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Library</OutputType></PropertyGroup></Project>\n'

    def build() -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["dotnet", "build", str(csproj)], cwd=out, capture_output=True, text=True, check=False
        )

    csproj.write_text(body.format(sdk="Microsoft.NET.Sdk.Web"))
    refused = build()
    assert refused.returncode != 0
    assert "Demo.Features holds the use cases that every host calls" in refused.stdout

    csproj.write_text(body.format(sdk="Microsoft.NET.Sdk"))
    (project / "packages.lock.json").unlink(missing_ok=True)
    built = build()
    assert built.returncode == 0, built.stdout


# (l4) A Domain project stays pure: the build refuses I/O and project references in it.


@pytest.mark.skipif(not _dotnet_sdk(), reason="needs a .NET SDK")
def test_a_domain_project_may_not_reference_io_or_another_project(tmp_path):
    out = render(tmp_path / "d", ["dotnet"])
    props = out / "Directory.Packages.props"
    props.write_text(
        props.read_text().replace(
            "</Project>",
            '  <ItemGroup><PackageVersion Include="Microsoft.EntityFrameworkCore" Version="10.0.0" /></ItemGroup>\n</Project>',
        )
    )
    for name in ("Demo.Domain", "Demo.Other"):
        (out / "src" / name).mkdir(parents=True)
        (out / "src" / name / "Marker.cs").write_text(
            f"namespace {name};\n\npublic static class Marker;\n"
        )
    (out / "src/Demo.Other/Demo.Other.csproj").write_text(
        '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>\n'
    )
    csproj = out / "src/Demo.Domain/Demo.Domain.csproj"
    shape = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup><ItemGroup>{refs}</ItemGroup></Project>\n'

    def build() -> subprocess.CompletedProcess[str]:
        (csproj.parent / "packages.lock.json").unlink(missing_ok=True)
        return subprocess.run(
            ["dotnet", "build", str(csproj)], cwd=out, capture_output=True, text=True, check=False
        )

    for refs in (
        '<PackageReference Include="Microsoft.EntityFrameworkCore" />',
        '<ProjectReference Include="../Demo.Other/Demo.Other.csproj" />',
    ):
        csproj.write_text(shape.format(refs=refs))
        refused = build()
        assert refused.returncode != 0, refs
        assert (
            "Demo.Domain holds the entities, IDs, value types and pure rules" in refused.stdout
        ), refs

    csproj.write_text(shape.format(refs=""))
    built = build()
    assert built.returncode == 0, built.stdout
