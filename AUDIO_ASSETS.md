# Hexstead - Audio Generation Guide

The game is fully playable in silence. **Any m4a you drop into
`assets/audio/` at the names below is picked up automatically on the next
build; anything missing simply makes no sound.** Generate in any order -
partial audio always works, exactly like the art.

Easiest route: drop raws into `audio_inbox/` named EXACTLY after their
target (e.g. `sfx_dice_roll.wav`, not `dice.wav` - wrong names are
skipped) and run `python3 scripts/process_audio.py` - it transcodes to
AAC/m4a, normalizes loudness, and places the files for you. Needs ffmpeg
(`brew install ffmpeg`); without it, inputs that are already `.m4a` are
copied through unnormalized.

Wiring is live (`lib/audio/sound_store.dart`), so nothing needs code when a
file lands. The two toggles in the in-game settings card control it: music
stops and starts live, sounds go quiet immediately, and both persist.

## Style

> Cozy medieval storybook board game. Warm acoustic instruments - lute,
> recorder, hand percussion, light strings - never orchestral or heroic.
> Clean, dry, no reverb tails on the one-shots. Mono is fine for SFX.

Music is mixed quieter than the one-shots on purpose (-16 LUFS against
-14), so a ceremony sound always cuts through the loop under it. Keep the
loops sparse: they run for a whole five-minute match under constant
dice-rattling and banner sounds.

## The 11 targets

`assets/audio/<name>.m4a`. Loops want 60-90s and must be seamless (start
and end on the same beat, no fade); one-shots want 0.5-2s with an
immediate attack and no lead-in silence.

| File | Type | Length | Prompt subject |
|---|---|---|---|
| `music_menu.m4a` | loop | 60-90s | calm lute and recorder theme over a slow hand drum, an inn at dusk, unhurried |
| `music_game.m4a` | loop | 60-90s | light plucked-string bed with soft percussion, gently forward-moving, stays out of the way |
| `sfx_dice_roll.m4a` | one-shot | 0.8-1.5s | two wooden dice tumbling across a plank table and settling |
| `sfx_card_play.m4a` | one-shot | 0.5-1s | a single card snapping down onto a table |
| `sfx_claim.m4a` | one-shot | 0.5-1s | a wooden stake driven into soil, one satisfying thud |
| `sfx_upgrade.m4a` | one-shot | 1-1.5s | a small bright upward chime with a hammer tap under it |
| `sfx_production.m4a` | one-shot | 0.8-1.5s | grain and coins pouring into a basket, warm and generous |
| `sfx_bandit.m4a` | one-shot | 1-2s | a sly low woodwind slide with a quick cloth rustle, mischievous not scary |
| `sfx_match_point.m4a` | one-shot | 1-2s | a single distant warning horn, tense but not alarming |
| `sfx_victory.m4a` | one-shot | 1.5-2s | a short triumphant lute and recorder flourish with a light cymbal |
| `sfx_defeat.m4a` | one-shot | 1.5-2s | a soft descending recorder phrase, wistful rather than grim |

The full generation prompts live alongside this table (kept separately);
the subjects above are the one-line briefs each of them expands.

## Where each one fires

| Sound | Moment |
|---|---|
| `music_menu` | menu, from the first New Game / Continue tap (browsers block audio before a gesture) and again on every trip back to the menu |
| `music_game` | the game screen mounting; it keeps running across Play again |
| `sfx_dice_roll` | the dice ceremony starting, human and bot alike |
| `sfx_card_play` | a card you played being dispatched |
| `sfx_claim` | claiming a hex |
| `sfx_upgrade` | upgrading a hex |
| `sfx_production` | the payout chips floating over the board |
| `sfx_bandit` | the bandit's flight starting |
| `sfx_match_point` | a match-point banner appearing |
| `sfx_victory` / `sfx_defeat` | the game-end beat, by whether you won |

## Checks before accepting a take

- **Loop seam**: play the loop twice back to back. A click, a gap, or a
  fade-out at the join means reroll.
- **One-shot attack**: any silence before the sound arrives reads as lag,
  because these fire on a tap. Trim it to zero.
- **Twentieth hearing**: dice roll and production play dozens of times a
  match. Anything with a distinctive tail or a musical note in it grates
  fast - keep them dry and short.
- **Under the music**: check each one-shot against `music_game`, not in
  silence. That is the only mix that ships.
