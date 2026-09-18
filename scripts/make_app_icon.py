#!/usr/bin/env python3
"""App icon builder for Hexstead.

Drop the raw generated icon art (square, cream background, forest hex tile
diorama with a die in the front center) at:

    art_inbox/app_icon.png

Then run:  python3 scripts/make_app_icon.py

The generator's die is always malformed, so this script draws a clean vector
die and composites it over the bad one, tight-crops the art so the subject
fills the frame, and writes out the full iOS iconset plus the web icons.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_inbox" / "app_icon.png"
IOS_ICONSET = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WEB = ROOT / "web"

# All pixel constants below were tuned against a 1220px-wide reference of the
# same artwork; everything scales by (source width / REF).
REF = 1220

# --- cube geometry -------------------------------------------------------
SS = 4  # supersample
yaw, pitch, roll = math.radians(20), math.radians(-20), math.radians(-3)


def rot(p):
    x, y, z = p
    # yaw around Y
    x, z = x * math.cos(yaw) + z * math.sin(yaw), -x * math.sin(yaw) + z * math.cos(yaw)
    # pitch around X
    y, z = y * math.cos(pitch) - z * math.sin(pitch), y * math.sin(pitch) + z * math.cos(pitch)
    # roll around Z
    x, y = x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll)
    return (x, y, z)


def face_pts(face):
    # face-local (u,v) in [-1,1] -> 3D on unit cube
    def to3d(u, v):
        if face == 'top':
            return (u, 1, v)
        if face == 'left':
            return (u, v, -1)  # front-left
        return (1, v, -u)      # front-right
    return to3d


IVORY_TOP = (248, 241, 222, 255)
IVORY_L = (236, 226, 199, 255)
IVORY_R = (219, 205, 172, 255)
PIP = (122, 74, 50, 255)
FACE_COLOR = {'top': IVORY_TOP, 'left': IVORY_L, 'right': IVORY_R}
PIPS = {'top': 1, 'left': 5, 'right': 3}
PIP_XY = {
    1: [(0, 0)],
    3: [(-.6, .6), (0, 0), (.6, -.6)],
    5: [(-.55, -.55), (.55, -.55), (0, 0), (-.55, .55), (.55, .55)],
}


def draw_die(size_px):
    S = size_px * SS
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    half = S * 0.30  # cube half-edge in px

    def proj(p):
        x, y, z = rot(p)
        return (S / 2 + x * half, S / 2 - y * half)

    for face in ['top', 'left', 'right']:
        f = face_pts(face)
        corners = [f(-1, -1), f(1, -1), f(1, 1), f(-1, 1)]
        poly = [proj(c) for c in corners]
        dr.polygon(poly, fill=FACE_COLOR[face])
        # rounded feel: stroke edges with same color, round joints
        dr.line(poly + [poly[0]], fill=FACE_COLOR[face], width=int(S * 0.045), joint='curve')
    for face in ['top', 'left', 'right']:
        f = face_pts(face)
        r = S * (0.062 if face == 'left' else 0.048)
        for (u, v) in PIP_XY[PIPS[face]]:
            cx, cy = proj(f(u * 0.78, v * 0.78))
            dr.ellipse([cx - r, cy - r, cx + r, cy + r], fill=PIP)
    return img.resize((size_px, size_px), Image.LANCZOS)


# --- composite + crop ----------------------------------------------------
# Fractions of the art, measured on the 1220px reference.
BLOB_CX_F, BLOB_CY_F = 655 / 1220, 715 / 1216
DIE_F = 300 / 1220
CROP_F = (150 / 1220, 140 / 1216, 1090 / 1220, 1080 / 1216)


def build_master() -> Image.Image:
    art = Image.open(SRC).convert('RGBA')
    assert art.width == art.height, f"source must be square, got {art.size}"
    W = art.width
    k = W / REF

    cx, cy = round(BLOB_CX_F * W), round(BLOB_CY_F * W)
    die_px = round(DIE_F * W)

    # soft shadow under the die
    shadow = Image.new('RGBA', art.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([cx - die_px * 0.52, cy + die_px * 0.18,
                cx + die_px * 0.52, cy + die_px * 0.46], fill=(50, 62, 34, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * k))
    art = Image.alpha_composite(art, shadow)

    die = draw_die(die_px)
    art.paste(die, (cx - die_px // 2, cy - die_px // 2), die)

    # tight square crop so the subject fills the icon frame
    left, top = round(CROP_F[0] * W), round(CROP_F[1] * W)
    side = round(CROP_F[2] * W) - left
    return art.crop((left, top, left + side, top + side))


# name -> pixel size
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def emit(master: Image.Image, dest: Path, size: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    master.resize((size, size), Image.LANCZOS).convert("RGB").save(dest)
    print(f"  OK   {dest.relative_to(ROOT)} ({size}x{size})")


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"missing {SRC.relative_to(ROOT)} - drop the raw art there first")
    master = build_master()
    print(f"Composited die + cropped master: {master.size[0]}x{master.size[1]}")

    print("iOS iconset:")
    for name, size in IOS_ICONS.items():
        emit(master, IOS_ICONSET / name, size)

    print("Web icons:")
    favicon = WEB / "favicon.png"
    fav_size = Image.open(favicon).size[0] if favicon.exists() else 16
    emit(master, favicon, fav_size)
    for name, size in [("Icon-192.png", 192), ("Icon-512.png", 512),
                       ("Icon-maskable-192.png", 192), ("Icon-maskable-512.png", 512)]:
        emit(master, WEB / "icons" / name, size)

    print("Done. Rebuild the app to see them.")


if __name__ == "__main__":
    main()
