#!/usr/bin/env python3
"""Regenerates assets/images/app_icon_padded.png from app_logo.png.

app_logo.png is a plain white mark cropped tight to its own edges — used
directly as an app icon source it fills the canvas edge to edge with no
margin. This script re-crops it to its true bounding box, scales it down to
occupy ~55% of a square transparent canvas, and centers it, giving
flutter_launcher_icons (see the `flutter_launcher_icons:` block in
pubspec.yaml) a source with real breathing room for the iOS icon and
Android's legacy (pre-adaptive-icon) fallback.

Android's modern adaptive icon does NOT use this file — it insets the
original app_logo.png natively via adaptive_icon_foreground_inset, so
padding it here too would double the margin.

Run whenever app_logo.png changes:
    python3 tool/generate_app_icon_padded.py
    dart run flutter_launcher_icons
"""

from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE = REPO_ROOT / "assets/images/app_logo.png"
OUTPUT = REPO_ROOT / "assets/images/app_icon_padded.png"

CANVAS_SIZE = 1024
TARGET_FRACTION = 0.55  # fraction of the canvas' shorter side the mark fills


def main() -> None:
    src = Image.open(SOURCE).convert("RGBA")

    # Trim to the mark's actual bounding box first, so the padding below is
    # measured from the real glyph edges rather than any existing slack.
    mark = src.crop(src.getbbox())
    mark_w, mark_h = mark.size

    scale = (CANVAS_SIZE * TARGET_FRACTION) / max(mark_w, mark_h)
    new_w, new_h = round(mark_w * scale), round(mark_h * scale)
    mark_resized = mark.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    x, y = (CANVAS_SIZE - new_w) // 2, (CANVAS_SIZE - new_h) // 2
    canvas.paste(mark_resized, (x, y), mark_resized)
    canvas.save(OUTPUT)
    print(f"wrote {OUTPUT} — mark is {new_w}x{new_h} within a {CANVAS_SIZE} canvas")


if __name__ == "__main__":
    main()
