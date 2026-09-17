# Hexstead - AI Art Generation Guide (v2)

The game is fully playable with placeholders. **Any PNG you drop into
`assets/images/` at the paths below is picked up automatically on the next
build; anything missing keeps its placeholder.** Generate in any order -
partial art always works.

## Style prompt prefix (use verbatim on EVERY asset for consistency)

> Cozy medieval storybook game asset, flat vector illustration style, soft
> rounded shapes, warm autumn palette (moss green, wheat gold, terracotta,
> slate blue, cream), gentle top-left lighting, subtle texture, no text,
> no watermark, centered subject, transparent background, PNG.

Tips: generate one asset you love first (the forest tile), then feed it back
as a style reference for every other batch. Generate at the listed size or
larger and downscale. Tiles are drawn clipped to a hexagon, so fill the
whole square frame edge to edge (corners get cropped by the hex mask).

## Priority 1 - the board (biggest visual win)

| File | Size | Prompt subject |
|---|---|---|
| `tiles/tile_forest.png` | 512x512 | dense pine and oak forest seen from above at a slight angle, scattered cut logs |
| `tiles/tile_field.png` | 512x512 | golden wheat field with haystacks, top-down slight angle |
| `tiles/tile_hill.png` | 512x512 | rolling clay hills with a small brick kiln and stacked bricks |
| `tiles/tile_mountain.png` | 512x512 | grey stone peaks with snow caps and boulders |
| `tiles/tile_desert.png` | 512x512 | sandy dunes, single cactus, bleached bones |
| `bandit.png` | 256x256 | cheeky hooded bandit figure with a loot sack, mischievous not scary |

Note: each tile must read as its resource at a glance (logs / wheat /
bricks / stone) - the tile art replaces both the terrain color AND the
resource icon.

## Priority 2 - identity

| File | Size | Prompt subject |
|---|---|---|
| `ui/bg_menu.png` | 1536x2048 | distant cozy medieval valley with hex-patterned farmland at dawn (no transparency) |
| App icon (replaces `ios/Runner/Assets.xcassets/AppIcon.appiconset/`) | 1024x1024 | single forest hex tile with an ivory die leaning on it (no transparency, fills canvas) |

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
| `resources/wood.png` `grain.png` `brick.png` `stone.png` | 128x128 | icons: stacked logs / wheat sheaf / clay bricks / stone blocks (for the HUD) |
| `cards/art_<card_id>.png` x10 | 384x384 | one per card: second_chance (two dice mid-tumble), omen (hand nudging a die), drought (cracked dry field), charter (royal scroll with wax seal), cutpurse (masked figure snatching a pouch), bounty (overflowing crate of goods), banish (villager with broom chasing bandit), brigand (hooded figure sneaking at dusk), harvest (festival table piled with produce), tithe (tax collector with ledger) |
| `ui/panel_bg.png` | 256x256 | parchment panel with darkened wood border (9-slice) |

Already looking good and NOT needing art: dice (drawn), number tokens
(drawn), card frames (drawn), player colors (drawn).
