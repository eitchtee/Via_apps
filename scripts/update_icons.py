"""Copy the Via branding into this app. Dev-only: `python scripts/update_icons.py`.

The icons come from ../Via/branding (see its README; build.py there regenerates them). Files are
copied as-is, never rescaled: each variant is already sized for its platform. The only thing
built here is the Windows .ico files, which pack the existing exact-size PNGs.
"""

import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT.parent / "Via" / "branding" / "png"
ASSETS = ROOT / "assets" / "icon"
RES = ROOT / "android" / "app" / "src" / "main" / "res"


def copy(name: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(BRANDING / name, target)


def ico(names: list[str], target: Path) -> None:
    images = [Image.open(BRANDING / n).convert("RGBA") for n in names]
    images.sort(key=lambda i: i.width)
    largest = images[-1]
    largest.save(target, sizes=[i.size for i in images], append_images=images[:-1])


# In-app logo, Windows toast icon.
copy("app-icon-256.png", ASSETS / "app-icon-256.png")

# Windows: executable icon and tray icon (heavier mark at small sizes).
small = ["app-icon-small-16.png", "app-icon-small-32.png", "app-icon-small-48.png"]
ico(small + ["app-icon-64.png", "app-icon-128.png", "app-icon-256.png"], ROOT / "windows/runner/resources/app_icon.ico")
ico(small, ASSETS / "tray.ico")

# Android adaptive launcher icon (minSdk 29, so no legacy PNG icons are needed).
copy("android-foreground-1024.png", RES / "drawable-nodpi/ic_launcher_foreground.png")
copy("android-monochrome-1024.png", RES / "drawable-nodpi/ic_launcher_monochrome.png")

# Android notification small icon: white on transparent.
for px, density in [(24, "mdpi"), (36, "hdpi"), (48, "xhdpi"), (72, "xxhdpi"), (96, "xxxhdpi")]:
    copy(f"mark-white-{px}.png", RES / f"drawable-{density}/ic_notification.png")
