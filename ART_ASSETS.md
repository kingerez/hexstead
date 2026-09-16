# Hexstead — AI Art Generation Guide

The game is fully playable with placeholder art (colored hexes + emoji). Drop
PNGs into `assets/images/` using the file names below and they will replace
placeholders per-asset (partial art is fine — missing files fall back).

## Style prompt prefix (use verbatim on EVERY asset for consistency)

> Cozy medieval storybook game asset, flat vector illustration style, soft
> rounded shapes, warm autumn palette (moss green, wheat gold, terracotta,
> slate blue, cream), gentle top-left lighting, subtle texture, no text,
> no watermark, centered subject, transparent background.

Tips: generate one asset you love first (e.g. the forest tile), then feed it
back as a style reference image for every other batch. Generate at 2x the
listed size and downscale.

## Assets

| File | Size | Subject (append to style prefix) |
|---|---|---|
| `tiles/tile_forest.png` (+`_2` variant) | 512×512 | pointy-top hexagon tile, dense pine and oak forest seen from above at a slight angle |
| `tiles/tile_field.png` (+`_2`) | 512×512 | hexagon tile, golden wheat field with haystacks |
| `tiles/tile_hill.png` (+`_2`) | 512×512 | hexagon tile, rolling clay hills with a small brick kiln |
| `tiles/tile_mountain.png` (+`_2`) | 512×512 | hexagon tile, grey stone peaks with snow caps |
| `tiles/tile_desert.png` | 512×512 | hexagon tile, sandy dunes, single cactus |
| `buildings/camp.png` | 256×256 | small medieval tent camp with campfire |
| `buildings/village.png` | 256×256 | cluster of three thatched-roof cottages, chimney smoke |
| `bandit.png` | 256×256 | cheeky hooded bandit with a loot sack, mischievous not scary |
| `resources/wood.png` | 128×128 | icon, small stack of cut logs |
| `resources/grain.png` | 128×128 | icon, tied wheat sheaf |
| `resources/brick.png` | 128×128 | icon, stack of clay bricks |
| `resources/stone.png` | 128×128 | icon, pile of grey stone blocks |
| `dice/die_1.png` … `die_6.png` | 192×192 | cream ivory die face with N terracotta pips, rounded corners |
| `cards/card_frame.png` | 512×716 | ornate parchment playing-card frame, empty center panel and title banner |
| `cards/card_back.png` | 512×716 | card back with heraldic hex-and-dice emblem |
| `cards/art_second_chance.png` | 384×384 | two dice mid-tumble with motion swirls |
| `cards/art_omen.png` | 384×384 | a hand nudging a die, tiny stars |
| `cards/art_drought.png` | 384×384 | cracked dry field under a pale sun |
| `cards/art_charter.png` | 384×384 | royal scroll with wax seal and ribbon |
| `cards/art_cutpurse.png` | 384×384 | masked figure snatching a coin pouch |
| `cards/art_bounty.png` | 384×384 | overflowing crate of mixed goods |
| `cards/art_banish.png` | 384×384 | villager with a broom chasing a fleeing bandit |
| `cards/art_brigand.png` | 384×384 | hooded bandit sneaking toward a village at dusk |
| `cards/art_harvest.png` | 384×384 | festival table piled with produce, bunting |
| `cards/art_tithe.png` | 384×384 | tax collector with ledger and small chest |
| `landmarks/lm_high_roller.png` | 256×256 | small medieval gambling hall with dice sign |
| `landmarks/lm_trade_post.png` | 256×256 | market stall with scales |
| `landmarks/lm_cheap_claims.png` | 256×256 | surveyor's tripod and rolled maps |
| `landmarks/lm_bandit_ward.png` | 256×256 | stone boundary marker with warding rune |
| `landmarks/lm_granary.png` | 256×256 | round grain silo |
| `landmarks/lm_lumber_mill.png` | 256×256 | water-wheel sawmill |
| `landmarks/lm_deep_mine.png` | 256×256 | timber mine entrance with cart |
| `landmarks/lm_kiln.png` | 256×256 | brick kiln with smoke |
| `landmarks/lm_cathedral.png` | 256×256 | small stone cathedral with rose window |
| `landmarks/lm_market_hall.png` | 256×256 | timber-framed market hall |
| `landmarks/lm_watchtower.png` | 256×256 | stone watchtower with banner |
| `landmarks/lm_keep.png` | 256×256 | squat castle keep |
| `objectives/obj_scroll.png` | 256×256 | sealed quest scroll (one generic icon is enough for v1) |
| `ui/panel_bg.png` | 256×256 | parchment panel with darkened wood border (9-slice) |
| `ui/button_bg.png` | 256×96 | carved wooden button (9-slice) |
| `ui/bg_menu.png` | 1536×2048 | distant cozy medieval valley with hex-patterned farmland at dawn (no transparency) |
| `icon/app_icon.png` | 1024×1024 | single forest hex tile with an ivory die leaning against it (no transparency, fills canvas) |

~45 images. Priority order if generating incrementally:
1. 5 terrain tiles + camp + village + bandit (the board)
2. 4 resource icons + 6 die faces (the HUD)
3. menu background + app icon
4. card frame/back + card arts
5. landmark icons, UI 9-slices
