# Hexstead - AI Art Generation Guide (v2)

The game is fully playable with placeholders. **Any PNG you drop into
`assets/images/` at the paths below is picked up automatically on the next
build; anything missing keeps its placeholder.** Generate in any order -
partial art always works.

Easiest route: drop raws into `art_inbox/` named EXACTLY after their
target (e.g. `tile_forest.png`, not `forest.png` - wrong names are
skipped) and run `python3 scripts/process_art.py` - it strips backgrounds
where needed, resizes, and places files for you.

## Style prompt prefix (use verbatim on EVERY asset for consistency)

> Cozy medieval storybook game asset, flat vector illustration style, soft
> rounded shapes, warm autumn palette (moss green, wheat gold, terracotta,
> slate blue, cream), gentle top-left lighting, subtle texture, no text,
> no watermark, centered subject, transparent background, PNG.

For full-bleed assets (tiles, `bg_menu`) drop "centered subject,
transparent background" from the prefix - they must fill the frame.

Tips: generate one asset you love first (the forest tile - done), then feed
it back as a style reference (`--sref` / image prompt) for every other
batch. Generate at the listed size or larger and downscale. Tiles are drawn
clipped to a hexagon, so fill the whole square frame edge to edge (corners
get cropped by the hex mask).

## Lessons from the forest tile (apply to all remaining tiles)

The first attempt failed by being a *texture* (dozens of small trees, no
hierarchy); the keeper prompt asked for a *tile*. What made the difference:

- **Name a small odd count** ("seven large trees") - a count stops
  Midjourney from tiling the whole frame with repeated elements.
- **Few, large, simple shapes on a plain ground** - append "large simple
  shapes, minimal detail, uncluttered, mobile game map tile".
- **One focal resource element** ("a single small pile of three cut logs")
  placed lower-middle, not at the frame edge (the hex mask clips corners
  and edges).
- **`--style raw --stylize 50`** - default stylize is what pushed v1 into
  ornate autumn-pattern territory.
- **Value contrast beats detail** - canopies only read at board scale
  because dark shadow greens sit against bright highlights. Reject
  candidates where elements match the ground value.
- **Watch palette drift** - v1 invented cream/white and rust-red trees;
  off-palette colors are the most visible thing at small sizes.
- **Squint test before accepting**: downscale to 64px and hex-mask (or
  just squint at a thumbnail). Tiles render ~64-96px on the board; if it
  turns to noise there, reroll.
- Board rendering adds a cream rim + drop shadow around every tile, so the
  art needs no border of its own.

## Priority 1 - the board (biggest visual win)

| File | Size | Prompt subject |
|---|---|---|
| `tiles/tile_forest.png` | 512x512 | DONE - seven large stylized pine and oak trees with big simple rounded canopies on a plain moss green ground, a single small pile of three cut logs at the front center, seen from above at a slight angle |
| `tiles/tile_field.png` | 512x512 | DONE - five large simple golden wheat patches on a plain wheat-gold ground, a single small haystack at the front center, seen from above at a slight angle |
| `tiles/tile_hill.png` | 512x512 | DONE - three large soft rolling terracotta clay mounds on a plain warm ground, a single small stack of red bricks at the front center, seen from above at a slight angle |
| `tiles/tile_mountain.png` | 512x512 | DONE - three large simple grey stone peaks with snow caps on a plain slate ground, a single small pile of stone blocks at the front center, seen from above at a slight angle |
| `tiles/tile_desert.png` | 512x512 | DONE - three large smooth sand dunes on a plain cream ground, a single green cactus at the front center, seen from above at a slight angle |

Append to every tile subject: "large simple shapes, minimal detail,
uncluttered, mobile game map tile --style raw --stylize 50" and use the
forest tile as the style reference.

Note: each tile must read as its resource at a glance (logs / wheat /
bricks / stone) - the tile art replaces both the terrain color AND the
resource icon.

### The bandit token (not a tile)

| File | Size | Prompt subject |
|---|---|---|
| `bandit.png` | 256x256 | DONE - cheeky hooded bandit figure with a loot sack, mischievous not scary |

It lives at `assets/images/bandit.png`, not under `tiles/`, and it is a
centered subject on a transparent background - do NOT append the tile
suffix or drop the "centered subject, transparent background" prefix.

## Priority 2 - identity

| File | Size | Prompt subject |
|---|---|---|
| `ui/bg_menu.png` | 1536x2048 | distant cozy medieval valley with hex-patterned farmland at dawn (no transparency) |
| App icon (replaces `ios/Runner/Assets.xcassets/AppIcon.appiconset/`) | 1024x1024 | DONE - single forest hex tile with an ivory die leaning on it (no transparency, fills canvas) |

App icon: drop the raw as `art_inbox/app_icon.png` and run `python3 scripts/make_app_icon.py` - it composites a clean vector die over the AI die and regenerates the iOS iconset + web icons.

## Priority 3 - the shop (art shows as card watermark, auto-wired)

All 256x256, `landmarks/lm_<id>.png`:

| File | Subject |
|---|---|
| `lm_high_roller.png` | medieval gambling hall with a dice sign |
| `lm_trade_post.png` | market stall with brass scales |
| `lm_cheap_claims.png` | surveyor's tripod and rolled maps |
| `lm_bandit_ward.png` | stone boundary marker with a warding rune |
| `lm_granary.png` | round grain silo |
| `lm_lumber_mill.png` | water-wheel sawmill |
| `lm_deep_mine.png` | timber mine entrance with an ore cart |
| `lm_kiln.png` | brick kiln with smoke |
| `lm_cathedral.png` | small stone cathedral with rose window |
| `lm_market_hall.png` | timber-framed market hall |
| `lm_watchtower.png` | stone watchtower with banner |
| `lm_keep.png` | squat castle keep |

## Priority 4 - polish (slots exist, wiring is trivial when files land)

| File | Size | Subject |
|---|---|---|
| `cards/art_<card_id>.png` x10 | 384x384 | DONE - see the subject list below |
| `ui/panel_bg.png` | 256x256 | parchment panel with darkened wood border (9-slice) |

Card arts - how they are used: each one shows as a 0.18-opacity watermark
bleeding off the bottom-right of the card face (`ActionCardFace` in
`lib/widgets/card_fan_overlay.dart`, so both the hand fan and the bot-play
reveal get it). At that opacity the brief is silhouette-first: one bold
subject, minimal internal detail, no background scene, and palette
accuracy barely matters. Gotcha that cost us a batch: inbox files must be
named `art_<card_id>.png` (e.g. `art_tithe.png`), NOT the bare card id -
`process_art.py` silently skips anything else.

Card subjects as actually generated (the first draft of this list asked
for scenes - "cracked dry field", "festival table piled with produce" -
which mush into grey at watermark opacity; these single-object versions
replaced them):

| id | Subject |
|---|---|
| `second_chance` | two dice mid-tumble, one above the other |
| `omen` | a single hand, index finger tipping one die |
| `drought` | one drooping withered wheat stalk over a cracked ground shard |
| `charter` | a half-unrolled scroll with one oversized wax seal |
| `cutpurse` | a coin pouch with its drawstring cut, one hand closing on it |
| `bounty` | a wooden crate overflowing with goods |
| `banish` | an upright broom crossed with a tumbling empty hood |
| `brigand` | a single hooded figure in profile, sneaking, one large mass |
| `harvest` | one overflowing cornucopia |
| `tithe` | a large open ledger with a stack of coins on it |

Prefix used, palette deliberately scoped to the scene so it cannot bleed
into the subject: "one single bold subject filling the frame, strong
readable silhouette, minimal internal detail, no background scene, no
ground line".

## Priority 5 - text icons (resources and the secret task)

These five replace emoji sitting inline in text - the HUD counters, claim
and upgrade price tags, the shop cost line, the trade chips, the secret
task chip - so they render at 14-20px. Wiring is live
(`lib/widgets/resource_icon.dart`): whichever files land show up on every
screen at once, anything missing keeps its emoji.

| File | Size | Prompt subject |
|---|---|---|
| `resources/wood.png` | 128x128 | a small stack of three cut logs |
| `resources/grain.png` | 128x128 | a tied golden wheat sheaf |
| `resources/brick.png` | 128x128 | a small stack of terracotta bricks |
| `resources/stone.png` | 128x128 | a pile of rounded gray stone blocks |
| `ui/icon_task.png` | 128x128 | a rolled parchment scroll with a red wax seal |

Use the style prefix verbatim, then append: "one object, bold simple
silhouette, two or three flat shapes only, no internal detail, icon that
reads at 16 pixels".

At this size the shape is the whole asset. An earlier batch failed on
color, not drawing: brick against terracotta and stone against slate blue
blurred into their own chips, so push each icon clearly lighter or darker
than the palette midtone. Squint test: downscale to 16px - if it stops
being nameable, reroll.

## Priority 6 - endgame backgrounds

Two full-bleed backdrops for the scoreboard, one per outcome. Wiring is live
(`lib/screens/game_over_screen.dart`): whichever file lands shows up under a
dark top-to-bottom scrim (0.65 -> 0.45), and a missing one leaves the flat
green background it has today.

| File | Size | Prompt subject |
|---|---|---|
| `ui/bg_victory.png` | 1536x2048 | hex-patterned valley at golden sunrise with banners flying from a hilltop keep (no transparency) |
| `ui/bg_defeat.png` | 1536x2048 | the same valley at cold dusk, empty fields under a grey sky, one lit window (no transparency) |

Like `bg_menu`, drop "centered subject, transparent background" from the
style prefix - these fill the frame. Keep both dim and low-contrast: the
scoreboard's white text sits right on top, and the scrim only carries art
that is already quiet. Compose for the middle third being covered, so put
the interest near the top and bottom edges.

Already looking good and NOT needing art: dice (drawn), number tokens
(drawn), card frames (drawn), player colors (drawn).
