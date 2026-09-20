# Hexstead Monetization - Design Spec

Date: 2026-09-20
Status: approved direction, pending implementation plan

## Goal

Meaningful revenue from a ship-and-polish game. No live-ops, no consumables,
no subscriptions. The business is a single one-time unlock, with a small ad
revenue floor from free players.

## Model

### Free tier

- Complete, unlimited game vs 1 bot on easy difficulty.
- Guided tutorial included.
- All art themes and music included (the free tier doubles as the demo, so it
  should look and sound its best).
- One interstitial ad before game start (see Ads section for exceptions).

### Full unlock

- One non-consumable IAP, price tier $5.99 USD, product id `hexstead.full`.
- Unlocks:
  - 2 and 3 bot games.
  - Medium and hard difficulty (and their high-score multipliers).
  - Removes ads.
- No other SKUs. Single purchase, restorable.

### Platforms

- iOS: full model (IAP + ads). Requires a public App Store release; TestFlight
  cannot sell IAP to the public. One-time admin: Paid Apps agreement and
  banking/tax setup in App Store Connect, IAP product created in ASC.
- Web (GitHub Pages): permanently free tier. No ad SDK, no IAP code in the
  bundle. Locked setup options render with a lock and a "Get the full game on
  iOS" link. The web build is the acquisition funnel.
- Android: out of scope for now. The entitlement layer stays platform-agnostic
  so Android can be added without redesign.

## Components

### PurchaseStore (`lib/monetization/purchase_store.dart`)

Singleton in the same style as `ArtStore` and `SoundStore`.

- Exposes `isUnlocked` (plus a listenable for UI updates).
- Backed by the `in_app_purchase` plugin: product query, purchase stream
  handling, restore.
- Caches the entitlement via the existing persistence layer so offline
  launches keep the unlock. The store's answer wins over the cache when
  available; the cache is a fallback, not the source of truth.
- On web (and any platform without IAP) it compiles to a stub that reports
  locked and exposes the funnel link instead of purchase actions.

### Setup screen gating

- For free users, the 2-bot and 3-bot chips and the medium/hard difficulty
  chips render in a locked style (lock icon).
- Tapping a locked chip opens the paywall overlay instead of selecting.
- Default selection for free users is 1 bot, easy.

### Paywall overlay (`lib/widgets/paywall_overlay.dart`)

- Parchment-styled dialog matching the existing overlay family.
- Contents: what the unlock includes, live price fetched from the store,
  Buy button, Restore button.
- Reachable from: tapping any locked chip, and an entry in settings.
- Settings also gets a "Restore purchases" entry (App Store requirement).
- On web, the same surface becomes the "Get the full game on iOS" card.

### Ads

- `google_mobile_ads`, interstitial only, preloaded, shown when a free user
  starts a game.
- Never shown before the tutorial or before the player's first real game;
  the first session stays clean.
- Never shown to unlocked users.
- Wrapped in a small ad service with a no-op implementation for web and for
  unlocked users, so the ad SDK is never loaded where it is not needed
  (conditional imports keep it out of the web bundle entirely).
- Non-personalized ads only at launch: skips the App Tracking Transparency
  prompt and keeps the privacy label short. Personalized ads are a possible
  later optimization, not part of this design.
- AdMob test ad unit ids until release.

## Error handling

- Purchase flow errors (cancelled, deferred, store unreachable) surface as a
  short parchment-styled message; the game never blocks on the store.
- Ad load failure or timeout: start the game without an ad. An ad must never
  delay or prevent play.
- Restore with no prior purchase: friendly "no purchase found" message.

## Testing

- Unit tests: gating logic (which options are selectable free vs unlocked),
  entitlement cache behavior (offline fallback, store-wins refresh), ad
  eligibility rules (tutorial and first game exempt, unlocked exempt).
- Manual/integration: StoreKit Testing configuration in Xcode for purchase,
  cancel, and restore flows in the simulator; AdMob test units for ad display.
- Web build check: no ad or IAP plugin code in the bundle, locked chips show
  the iOS link, game fully playable in the free tier.

## Out of scope

- Android release, personalized ads / ATT, additional SKUs (cosmetic packs,
  tip jar), promo codes, server-side receipt validation (StoreKit local
  verification is sufficient at this scale).
