---
name: run-hexstead
description: Use when launching, running, driving, tapping, screenshotting, or visually verifying the Hexstead Flutter app on the iOS simulator.
---

# Running Hexstead on the iOS simulator

## Overview

Hexstead is a Flutter iOS app. Verifying UI work means getting it onto a
booted simulator, tapping through to the screen you changed, and looking
at a screenshot. Every command here is verified on this machine.

Several things fail silently if you improvise. They are marked **Gotcha**
- read them before burning a cycle on each.

## Is a session already running?

Check before launching - a live session is the normal case, and
relaunching throws away game state you may need.

```bash
pgrep -fl "flutter_tools.snapshot run" >/dev/null && echo "session live"
ls /tmp/hexstead-run/fifo 2>/dev/null   # default location
```

The FIFO may live elsewhere (sessions often use a scratchpad dir). To
find an unknown one:

```bash
lsof -c sleep 2>/dev/null | grep -i fifo     # the holder process holds it open
```

Set `S` to whichever directory holds `fifo` and `run.log`, then use `$S`
in every snippet below. **If a session is live, skip to Tapping.**

## Cold launch

`flutter run` hot reloads only from its own stdin. Background it without
a FIFO and you lose hot reload for the whole session.

```bash
S=/tmp/hexstead-run; mkdir -p $S
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
rm -f $S/fifo && mkfifo $S/fifo
sleep 86400 > $S/fifo & echo $! > $S/holder.pid   # holds FIFO open; else it EOFs
flutter run -d $UDID < $S/fifo > $S/run.log 2>&1 &
```

Wait for `Flutter run key commands` in `$S/run.log`. First iOS build
~1-2 min, later ~10s. Hot reload: `echo r > $S/fifo` (`R` = restart).

Teardown: `kill $(cat $S/holder.pid)` then `pkill -f "flutter_tools.snapshot run"`.

> **Gotcha - never hot reload through the Dart VM service.** Calling
> `reloadSources` on `http://127.0.0.1:<port>/<token>/` returns
> `"success":false, "Error while starting Kernel isolate task"`. The
> compiler belongs to the `flutter run` process. The FIFO is the only way in.

## Tapping with idb

```bash
export PATH="/opt/homebrew/bin:$PATH"    # idb_companion lives here
IDB=~/.local/idb-venv/bin/idb            # fb-idb is in a venv, NOT global
$IDB connect $UDID
$IDB ui tap --udid $UDID --duration 0.12 <X> <Y>
sleep 1                                  # let animations settle
```

> **Gotcha - taps need `--duration`.** A zero-duration tap does not
> register with Flutter's gesture recognizer. It fails silently and looks
> exactly like a mis-aimed tap. Always pass `--duration 0.12`.

> **Gotcha - idb takes POINTS, screenshots are PIXELS.** This device is
> 1206x2622 px but 402x874 pt. Divide screenshot coordinates by 3.

> **Gotcha - always settle ~1s after a tap** before screenshotting or
> tapping again. `ShopOverlay` scales in over 220ms; `CardFanOverlay`
> gates taps on a `settled` flag, so a card tapped too early is inert.

> **Gotcha - keep `fb-idb` out of the global env.** It needs
> `protobuf>=7`, which breaks a global `streamlit` (needs `<7`). Recreate
> with `python3 -m venv ~/.local/idb-venv && ~/.local/idb-venv/bin/pip install fb-idb`.
> Companion: `brew tap facebook/fb && brew install idb-companion` - it is
> NOT in brew core, and plain `brew install idb-companion` prints a
> warning and **exits 0 having installed nothing**.

Note the asymmetry: `simctl` accepts `booted`, `idb` requires `--udid`.

## Screenshot

```bash
xcrun simctl io booted screenshot $S/shot.png    # 2 stderr notes are normal, not errors
```

Downscale before viewing. **Use 700, not 420** - at 420 (193x420) you can
tell which screen is up but cannot read overlay titles or card text.

```python
from PIL import Image
im = Image.open('shot.png'); im.thumbnail((700, 700)); im.save('shot_s.png')
```

Crop to the region you changed when checking fine detail.

## Dismissing overlays

Every overlay (`shop`, `trade`, `settings`, `production`, `dice_roll`,
`bot_card`, `card_fan`) is a `Positioned.fill` dark scrim with
`onTap: onClose`. The inner panel has its own `GestureDetector(onTap: () {})`
that absorbs taps, so **tapping the panel does nothing** - aim at the
scrim well above the panel.

`200, 120` is a safe universal dismiss point. Do not use `200, 250`: the
shop panel's top edge is near y=256, leaving no margin.

## HUD buttons

Three circular buttons, `y = 715`:

| Button | X | Icon |
|---|---|---|
| Card fan | 264 | fan of cards |
| Shop | 316 | columned building |
| Trade | 368 | two arrows |

Spans are 242-286, 294-338, 346-390, so aim for the centers above.

> **These drift.** The HUD was rebuilt recently (`App: HUD rebuilt around
> the board`) and an earlier version of this table was stale enough that
> its "trade" value landed on the shop button's edge. Re-derive after any
> HUD change with the recipe below.

## Finding tap targets

Run these against the **full-res** PNG, never the downscaled copy - the
`//3` conversion is only valid at 1206x2622.

Primary green buttons (New Game, Begin, Start, Buy) are `(173, 210, 142)`:

```python
from PIL import Image
im = Image.open('shot.png').convert('RGB'); W, H = im.size; px = im.load()
xs, ys = [], []
for y in range(0, H, 3):
    for x in range(0, W, 3):
        r, g, b = px[x, y]
        if abs(r-173) < 14 and abs(g-210) < 14 and abs(b-142) < 14:
            xs.append(x); ys.append(y)
print('tap at', (min(xs)+max(xs))//6, (min(ys)+max(ys))//6)   # //6 = /2 then /3
```

Use tolerances (`abs(...) < 14`), not exclusive ranges - the green is
exactly 210, so `210 < g` matches nothing.

HUD chrome is warm tan on dark, not green. Scan one row and merge runs
(each button splits at its icon, so adjacent runs belong to one button):

```python
y = 715 * 3
runs, cur = [], None
for x in range(W):
    r, g, b = px[x, y]
    hit = r > 120 and g > 100 and b > 70 and r > b + 25
    if hit and cur is None: cur = x
    if not hit and cur is not None:
        if x - cur > 20: runs.append((cur, x))
        cur = None
# merge runs closer than ~20pt apart, then take each merged centre // 3
```

If several regions match, a single bbox centre falls *between* them.
Print the distinct bands before trusting any centre.

## Cold-start navigation

Points on a 402x874 screen:

| Step | Tap | Lands on |
|---|---|---|
| 1 | 200, 550 | New Game (menu) |
| 2 | 201, 624 | Begin (setup) |
| 3 | 201, 617 | Start (welcome card) |

Steps 1-3 are green buttons - prefer re-deriving with the green finder
over trusting these if the menu has changed.

## Offscreen alternative

To check layout without tapping, render a widget through the project's
golden infrastructure (`test/goldens/`, pattern in
`test/board_golden_test.dart`) with `--update-goldens`. Catches overflow
and structure but **not** appearance: goldens substitute a box font, so
real glyphs and emoji do not render. Overlay widgets are `Positioned.fill`
and must be wrapped in a `Stack` or they throw `StackParentData`.

## Common mistakes

| Symptom | Cause |
|---|---|
| Tap does nothing, coords look right | Missing `--duration 0.12` |
| Tap lands far off-screen | Used pixels not points (divide by 3) |
| Coordinates off by exactly 3x | Ran the finder on the downscaled PNG |
| Tap on an overlay does nothing | Hit the panel, which absorbs taps - aim at the scrim |
| Screenshot catches a half-drawn overlay | No settle delay after the tap |
| Hot reload succeeds, nothing changes | Went through the VM service, not the FIFO |
| `idb_companion: command not found` | `/opt/homebrew/bin` off PATH, or brew core "install" |
| Green finder returns nothing | Exclusive bounds instead of `abs() < tol` |
| Golden test throws `StackParentData` | Overlay not wrapped in a `Stack` |
