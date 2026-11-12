"""Render each diagram in docs/ to a light and a dark PNG for the docs site.

    python3 scripts/docs-figures.py docs/quality-funnel.html [...]

For docs/<name>.html it writes docs/<name>.png and docs/<name>-dark.png at
twice the size of the SVG's viewBox. It takes the page's <style> and its one
<svg>, so the PNG holds the diagram only, not the page title. The dark PNG
swaps each Komputa light colour for its dark one (the komputa diagram
profile); text with class "on-accent" sits on the orange fill and keeps its
dark ink. It runs headless Chromium (CHROMIUM, default /usr/bin/chromium),
which needs the network for the Google fonts the pages name. Look at each
PNG, then list it in .scrub-binary-ok.
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

LIGHT_TO_DARK = {
    "F4F3EF": "111111",  # paper
    "FFFFFF": "1C1C1B",  # paper-2, surface
    "111111": "F4F3EF",  # ink
    "5E5E5A": "A3A39E",  # muted, soft
    "DDDBD5": "2E2E2C",  # rule
    "8A8883": "6B6A66",  # rule-solid
    "C2410C": "FF5A1F",  # accent-text
}
ON_ACCENT = ".on-accent { fill: #111111 !important; }"
SCALE = 2


def _dark(text: str) -> str:
    pattern = re.compile("#(" + "|".join(LIGHT_TO_DARK) + r")\b", re.IGNORECASE)
    return pattern.sub(lambda m: "#" + LIGHT_TO_DARK[m.group(1).upper()], text)


def _page(source: str, *, dark: bool) -> tuple[str, int, int]:
    style = re.search(r"<style>(.*?)</style>", source, re.DOTALL)
    svg = re.search(r"<svg\b.*?</svg>", source, re.DOTALL)
    if style is None or svg is None:
        raise SystemExit("docs-figures: the page needs one <style> and one <svg>")
    box = re.search(r'viewBox="0 0 (\d+) (\d+)"', svg.group(0))
    if box is None:
        raise SystemExit('docs-figures: the <svg> needs viewBox="0 0 <w> <h>"')
    width, height = int(box.group(1)), int(box.group(2))
    fonts = "".join(re.findall(r'<link href="https://fonts[^"]+" rel="stylesheet">', source))
    # The page's own body and svg layout (padding, flex centring) would move the diagram.
    css = style.group(1) + (
        f"\nbody {{ margin: 0; padding: 0; display: block; min-height: 0; }}\nsvg {{ width: {width}px; min-width: 0; }}"
    )
    body = svg.group(0)
    if dark:
        css, body = _dark(css) + "\n" + ON_ACCENT, _dark(body)
    return (
        f"<!DOCTYPE html><html><head>{fonts}<style>{css}</style></head><body>{body}</body></html>",
        width,
        height,
    )


def _render(html: str, *, width: int, height: int, out: Path) -> None:
    chromium = os.environ.get("CHROMIUM", "/usr/bin/chromium")
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "page.html"
        page.write_text(html, encoding="utf-8")
        subprocess.run(
            [
                chromium,
                "--headless=new",
                "--no-first-run",
                "--disable-gpu",
                "--hide-scrollbars",
                f"--user-data-dir={tmp}/profile",
                f"--force-device-scale-factor={SCALE}",
                f"--window-size={width},{height}",
                "--virtual-time-budget=5000",
                f"--screenshot={out.resolve()}",
                page.as_uri(),
            ],
            check=True,
            capture_output=True,
            timeout=120,
        )
    print(f"docs-figures: wrote {out}")


def main(paths: list[str]) -> None:
    if not paths:
        raise SystemExit(__doc__)
    for name in paths:
        source_path = Path(name)
        source = source_path.read_text(encoding="utf-8")
        for dark, suffix in ((False, ""), (True, "-dark")):
            html, width, height = _page(source, dark=dark)
            _render(
                html,
                width=width,
                height=height,
                out=source_path.with_name(f"{source_path.stem}{suffix}.png"),
            )


if __name__ == "__main__":
    main(sys.argv[1:])
