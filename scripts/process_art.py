#!/usr/bin/env python3
"""Art intake pipeline for Hexstead.

Drop raw generated images into art_inbox/ named by their TARGET (extension
ignored, any of png/jpg/webp), e.g.:

    art_inbox/tile_forest.png
    art_inbox/bandit.jpg
    art_inbox/lm_watchtower.webp

Then run:  python3 scripts/process_art.py

For each file it:
  1. figures out the destination + size from the name,
  2. strips the background (rembg) ONLY for assets that need transparency,
  3. resizes to the target size,
  4. writes the finished PNG into assets/images/... ready for the next build.
"""
import io
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
INBOX = ROOT / "art_inbox"
OUT = ROOT / "assets" / "images"

# name -> (relative destination, size, needs_transparency)
TARGETS = {
    **{f"tile_{t}": (f"tiles/tile_{t}.png", 512, False)
       for t in ["forest", "field", "hill", "mountain", "desert"]},
    "bandit": ("bandit.png", 256, True),
    "bg_menu": ("ui/bg_menu.png", None, False),
    "panel_bg": ("ui/panel_bg.png", 256, False),
    **{f"lm_{l}": (f"landmarks/lm_{l}.png", 256, True)
       for l in ["high_roller", "trade_post", "cheap_claims", "bandit_ward",
                 "granary", "lumber_mill", "deep_mine", "kiln", "cathedral",
                 "market_hall", "watchtower", "keep"]},
    **{r: (f"resources/{r}.png", 128, True)
       for r in ["wood", "grain", "brick", "stone"]},
    **{f"art_{c}": (f"cards/art_{c}.png", 384, True)
       for c in ["second_chance", "omen", "drought", "charter", "cutpurse",
                 "bounty", "banish", "brigand", "harvest", "tithe"]},
}


def process(path: Path) -> None:
    name = path.stem
    if name not in TARGETS:
        print(f"  SKIP {path.name}: unknown target "
              f"(expected one of: {', '.join(sorted(TARGETS)[:6])}, ...)")
        return
    rel, size, transparent = TARGETS[name]
    img = Image.open(path).convert("RGBA")

    if transparent:
        from rembg import remove
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        img = Image.open(io.BytesIO(remove(buf.getvalue()))).convert("RGBA")
        # Trim to content so sprites center nicely, keep a small margin.
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)
            side = max(img.width, img.height)
            pad = int(side * 0.06)
            canvas = Image.new("RGBA", (side + 2 * pad, side + 2 * pad),
                               (0, 0, 0, 0))
            canvas.paste(img, ((canvas.width - img.width) // 2,
                               (canvas.height - img.height) // 2))
            img = canvas

    if size:
        img = img.resize((size, size), Image.LANCZOS)

    dest = OUT / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest)
    print(f"  OK   {path.name} -> {dest.relative_to(ROOT)}"
          f" ({'transparent' if transparent else 'opaque'})")


def main() -> None:
    INBOX.mkdir(exist_ok=True)
    files = [p for p in INBOX.iterdir()
             if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}]
    if not files:
        print(f"Nothing in {INBOX.relative_to(ROOT)}/ - drop images named "
              "after their target (e.g. tile_forest.png) and rerun.")
        sys.exit(0)
    print(f"Processing {len(files)} file(s):")
    for path in sorted(files):
        process(path)
    print("Done. Rebuild the app to see them.")


if __name__ == "__main__":
    main()
