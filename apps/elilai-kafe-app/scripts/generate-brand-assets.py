#!/usr/bin/env python3
"""Regenerate Android/iOS launcher + splash assets from official ELIlai Kafe images.

Sources (copied into assets-src/):
  priv/static/images/elilai-kafe/app-icon-512.png
  priv/static/images/elilai-kafe/elilai-kafe-logo.jpg

Does not alter the official logo artwork beyond resize/composite on Ivory.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC_ICON = ROOT / "assets-src" / "app-icon-512.png"
SRC_LOGO = ROOT / "assets-src" / "elilai-kafe-logo.jpg"
IVORY = "#F4EFE3"

ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_APPICON = ROOT / "ios" / "App" / "App" / "Assets.xcassets" / "AppIcon.appiconset"
IOS_SPLASH = ROOT / "ios" / "App" / "App" / "Assets.xcassets" / "Splash.imageset"


def convert(*args: str) -> None:
    subprocess.check_call(["magick", *args])


def main() -> None:
    if not SRC_ICON.exists() or not SRC_LOGO.exists():
        raise SystemExit(
            "Missing assets-src images. Copy from priv/static/images/elilai-kafe/ first."
        )

    fg = ROOT / "assets-src" / "ic_launcher_foreground_1080.png"
    logo_640 = ROOT / "assets-src" / "logo_640.png"
    convert(str(SRC_LOGO), "-resize", "640x640", f"PNG32:{logo_640}")
    convert(
        "-size",
        "1080x1080",
        "xc:none",
        str(logo_640),
        "-gravity",
        "center",
        "-composite",
        f"PNG32:{fg}",
    )

    densities = {
        "mdpi": 108,
        "hdpi": 162,
        "xhdpi": 216,
        "xxhdpi": 324,
        "xxxhdpi": 432,
    }
    for name, size in densities.items():
        out_fg = ANDROID_RES / f"mipmap-{name}" / "ic_launcher_foreground.png"
        convert(str(fg), "-resize", f"{size}x{size}", str(out_fg))
        legacy = ANDROID_RES / f"mipmap-{name}" / "ic_launcher.png"
        round_icon = ANDROID_RES / f"mipmap-{name}" / "ic_launcher_round.png"
        logo_size = int(size * 0.72)
        tmp_logo = ROOT / "assets-src" / f"tmp_logo_{size}.png"
        convert(str(SRC_LOGO), "-resize", f"{logo_size}x{logo_size}", f"PNG32:{tmp_logo}")
        convert(
            "-size",
            f"{size}x{size}",
            f"xc:{IVORY}",
            str(tmp_logo),
            "-gravity",
            "center",
            "-composite",
            str(legacy),
        )
        shutil.copy(legacy, round_icon)

    splash_icon = ANDROID_RES / "drawable" / "splash_icon.png"
    convert(str(SRC_LOGO), "-resize", "576x576", f"PNG32:{splash_icon}")

    splash_sizes = {
        "drawable": (480, 800),
        "drawable-port-mdpi": (320, 480),
        "drawable-port-hdpi": (480, 800),
        "drawable-port-xhdpi": (720, 1280),
        "drawable-port-xxhdpi": (1080, 1920),
        "drawable-port-xxxhdpi": (1440, 2560),
        "drawable-land-mdpi": (480, 320),
        "drawable-land-hdpi": (800, 480),
        "drawable-land-xhdpi": (1280, 720),
        "drawable-land-xxhdpi": (1920, 1080),
        "drawable-land-xxxhdpi": (2560, 1440),
    }
    for folder, (w, h) in splash_sizes.items():
        out_dir = ANDROID_RES / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        logo_dim = int(min(w, h) * 0.36)
        tmp = ROOT / "assets-src" / f"splash_logo_{w}x{h}.png"
        convert(str(SRC_LOGO), "-resize", f"{logo_dim}x{logo_dim}", f"PNG32:{tmp}")
        convert(
            "-size",
            f"{w}x{h}",
            f"xc:{IVORY}",
            str(tmp),
            "-gravity",
            "center",
            "-composite",
            str(out_dir / "splash.png"),
        )

    ios_icon = IOS_APPICON / "AppIcon-512@2x.png"
    convert(str(SRC_ICON), "-resize", "1024x1024", str(ios_icon))

    ios_splash = IOS_SPLASH / "splash-2732x2732.png"
    ios_logo = ROOT / "assets-src" / "ios_splash_logo.png"
    convert(str(SRC_LOGO), "-resize", "900x900", f"PNG32:{ios_logo}")
    convert(
        "-size",
        "2732x2732",
        f"xc:{IVORY}",
        str(ios_logo),
        "-gravity",
        "center",
        "-composite",
        str(ios_splash),
    )
    shutil.copy(ios_splash, IOS_SPLASH / "splash-2732x2732-1.png")
    shutil.copy(ios_splash, IOS_SPLASH / "splash-2732x2732-2.png")
    print("ELIlai Kafe brand assets regenerated.")


if __name__ == "__main__":
    main()
