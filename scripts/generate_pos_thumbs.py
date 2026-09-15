#!/usr/bin/env python3
"""Generate POS WebP thumbnails from CoffeeSpot menu image maps.

Reads unique image paths from lib/espreso/menu.ex (@product_images and
@category_images), then writes 360px max-edge WebP (~q75) files to:

  priv/static/images/coffeespot/pos-thumbs/<stem>.webp

Full-size sources under priv/static/images/coffeespot/ are never modified.

Usage (from repo root):

  python3 scripts/generate_pos_thumbs.py

Requires: cwebp (preferred) or ImageMagick `magick`.

When product photos change:
  1. Update the source image under priv/static/images/coffeespot/
  2. Re-run this script
  3. Bump Menu @pos_thumb_vsn (e.g. pos1 -> pos2) so tablets fetch fresh thumbs
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MENU_EX = ROOT / "lib" / "espreso" / "menu.ex"
STATIC = ROOT / "priv" / "static"
OUT_DIR = STATIC / "images" / "coffeespot" / "pos-thumbs"
MAX_EDGE = 360
WEBP_QUALITY = 75


def extract_image_paths(menu_source: str) -> list[str]:
    """Collect unique /images/coffeespot/... paths from the image maps."""
    product_block = menu_source.split("@product_images %{", 1)[1].split(
        "@category_images %{", 1
    )[0]
    category_block = menu_source.split("@category_images %{", 1)[1].split(
        "@product_descriptions %{", 1
    )[0]
    paths = re.findall(r'"(/images/coffeespot/[^"]+)"', product_block + category_block)
    # Preserve stable order while uniquing
    seen: set[str] = set()
    ordered: list[str] = []
    for path in paths:
        if path not in seen:
            seen.add(path)
            ordered.append(path)
    return ordered


def encode_webp(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    cwebp = shutil.which("cwebp")
    if cwebp:
        # -resize WIDTH 0 keeps aspect; for tall images width=360 is enough.
        # For wide images, cwebp may exceed max edge on height — use magick first if needed.
        # Prefer magick resize then cwebp for deterministic max-edge.
        pass

    magick = shutil.which("magick") or shutil.which("convert")
    if not magick and not cwebp:
        raise SystemExit("Need cwebp and/or ImageMagick (magick) on PATH")

    # Always resize with magick to enforce max edge, then encode WebP.
    if magick:
        tmp = dest.with_suffix(".tmp.png")
        try:
            subprocess.check_call(
                [
                    magick,
                    str(src),
                    "-resize",
                    f"{MAX_EDGE}x{MAX_EDGE}>",
                    "-strip",
                    str(tmp),
                ]
            )
            if cwebp:
                subprocess.check_call(
                    [
                        cwebp,
                        "-quiet",
                        "-q",
                        str(WEBP_QUALITY),
                        str(tmp),
                        "-o",
                        str(dest),
                    ]
                )
            else:
                subprocess.check_call(
                    [
                        magick,
                        str(tmp),
                        "-quality",
                        str(WEBP_QUALITY),
                        str(dest),
                    ]
                )
        finally:
            if tmp.exists():
                tmp.unlink()
        return

    # cwebp-only fallback (width-based resize)
    subprocess.check_call(
        [
            cwebp,
            "-quiet",
            "-q",
            str(WEBP_QUALITY),
            "-resize",
            str(MAX_EDGE),
            "0",
            str(src),
            "-o",
            str(dest),
        ]
    )


def main() -> int:
    if not MENU_EX.is_file():
        print(f"Missing {MENU_EX}", file=sys.stderr)
        return 1

    paths = extract_image_paths(MENU_EX.read_text(encoding="utf-8"))
    if not paths:
        print("No image paths found in menu.ex", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    total_bytes = 0
    missing: list[str] = []

    for web_path in paths:
        rel = web_path.lstrip("/")
        src = STATIC / rel
        if not src.is_file():
            missing.append(web_path)
            continue
        stem = Path(rel).stem
        dest = OUT_DIR / f"{stem}.webp"
        encode_webp(src, dest)
        written += 1
        total_bytes += dest.stat().st_size
        print(f"ok  {dest.relative_to(ROOT)} ({dest.stat().st_size} bytes)")

    print(f"\nWrote {written} thumbnails to {OUT_DIR.relative_to(ROOT)}")
    print(f"Total size: {total_bytes / 1024:.1f} KB ({total_bytes / 1024 / 1024:.2f} MB)")

    if missing:
        print("\nMissing sources:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
