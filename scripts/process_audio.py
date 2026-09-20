#!/usr/bin/env python3
"""Audio intake pipeline for Hexstead.

Drop raw generated audio into audio_inbox/ named by its TARGET (extension
ignored, any of wav/mp3/m4a), e.g.:

    audio_inbox/music_menu.wav
    audio_inbox/sfx_dice_roll.mp3

Then run:  python3 scripts/process_audio.py

For each file it:
  1. checks the name against the target table,
  2. transcodes to AAC/m4a and normalizes loudness (music quieter than SFX,
     so a one-shot always cuts through the loop underneath it),
  3. writes the finished file into assets/audio/ ready for the next build.

Needs ffmpeg (brew install ffmpeg). Without it, an input that is already
.m4a is copied through unchanged and everything else is skipped.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INBOX = ROOT / "audio_inbox"
OUT = ROOT / "assets" / "audio"

# Integrated loudness per kind: music sits under the ceremony sounds.
MUSIC_LUFS = -16
SFX_LUFS = -14

# name -> loudness target
TARGETS = {
    "music_menu": MUSIC_LUFS,
    "music_game": MUSIC_LUFS,
    **{f"sfx_{s}": SFX_LUFS
       for s in ["dice_roll", "card_play", "claim", "upgrade", "production",
                 "bandit", "match_point", "victory", "defeat", "ui_tap",
                 "tile_tap"]},
}

HAVE_FFMPEG = shutil.which("ffmpeg") is not None


def process(path: Path) -> None:
    name = path.stem
    if name not in TARGETS:
        print(f"  SKIP {path.name}: unknown target "
              f"(expected one of: {', '.join(sorted(TARGETS)[:4])}, ...)")
        return
    lufs = TARGETS[name]
    dest = OUT / f"{name}.m4a"
    dest.parent.mkdir(parents=True, exist_ok=True)

    if not HAVE_FFMPEG:
        if path.suffix.lower() == ".m4a":
            shutil.copyfile(path, dest)
            print(f"  OK   {path.name} -> {dest.relative_to(ROOT)}"
                  " (copied, NOT normalized - install ffmpeg)")
        else:
            print(f"  SKIP {path.name}: needs ffmpeg to convert to m4a "
                  "(brew install ffmpeg)")
        return

    result = subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(path),
            # -vn: generated mp3s often embed cover art as a video stream,
            # which the m4a muxer refuses to write.
            "-vn",
            "-af", f"loudnorm=I={lufs}:TP=-1.5:LRA=11",
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100",
            str(dest),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"  SKIP {path.name}: ffmpeg failed - "
              f"{result.stderr.strip().splitlines()[-1] if result.stderr.strip() else 'no output'}")
        return
    print(f"  OK   {path.name} -> {dest.relative_to(ROOT)} ({lufs} LUFS)")


def main() -> None:
    INBOX.mkdir(exist_ok=True)
    files = [p for p in INBOX.iterdir()
             if p.suffix.lower() in {".wav", ".mp3", ".m4a"}]
    if not files:
        print(f"Nothing in {INBOX.relative_to(ROOT)}/ - drop audio named "
              "after its target (e.g. music_menu.wav) and rerun.")
        sys.exit(0)
    if not HAVE_FFMPEG:
        print("ffmpeg not found - install it (brew install ffmpeg) for "
              "conversion and loudness normalization.")
    print(f"Processing {len(files)} file(s):")
    for path in sorted(files):
        process(path)
    print("Done. Rebuild the app to hear them.")


if __name__ == "__main__":
    main()
