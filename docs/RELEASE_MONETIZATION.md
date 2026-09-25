# Monetization Release Checklist

Everything here is one-time store admin or a release-day swap. The code
ships with Google's public TEST ids; nothing earns money until this list
is done.

## App Store Connect (app 6812996489, team T388BN3387)

- [ ] Sign the Paid Applications agreement (Agreements, Tax, Banking) and
      complete banking + tax forms.
- [ ] Create the in-app purchase: Non-Consumable, product id exactly
      `hexstead.full`, price $3.99 (USD tier), localized display name
      "The Full Homestead", plus review screenshot (the paywall dialog).
- [ ] Add the In-App Purchase capability to the Runner target if the build
      rejects StoreKit calls (Xcode > Runner > Signing & Capabilities).
- [ ] Public App Store listing (the app is TestFlight-only today):
      screenshots, description, privacy labels. Ads (non-personalized)
      mean declaring "Identifiers > Device ID" only if Google's SDK
      collects IDFV - follow the current AdMob disclosure guide.

## StoreKit local testing (before ASC is even configured)

- [ ] Xcode > File > New > File > StoreKit Configuration File, name it
      `Hexstead.storekit`, save under `ios/`.
- [ ] Add a Non-Consumable: product id `hexstead.full`, price 3.99.
- [ ] Product > Scheme > Edit Scheme > Run > Options > StoreKit
      Configuration: select `Hexstead.storekit`.
- [ ] In the simulator: buy from a locked chip, buy from settings, cancel
      mid-flow, restore after reinstall (Debug > StoreKit > Manage
      Transactions to reset).

## Google Play Console

- [ ] DECIDE THE APPLICATION ID FIRST: it is `com.hexstead.hexstead` today
      and permanent after the first upload. For consistency with iOS
      (`com.kingerez.hexstead`) consider renaming BEFORE creating the app
      (android/app/build.gradle.kts `applicationId` + `namespace`,
      MainActivity package path). If renamed, update `playStoreUrl` in
      `lib/widgets/paywall_dialog.dart`.
- [ ] Developer account + merchant profile (payments).
- [ ] Create the app, upload a signed bundle to the Internal testing
      track (signing config is not set up yet - `flutter build appbundle`
      + Play App Signing).
- [ ] Create the in-app product `hexstead.full`, $3.99, activate it.
- [ ] Add license testers (Play Console > Settings > License testing) and
      run the same buy/cancel/restore flows on a device.

## AdMob

- [x] AdMob account exists; both apps registered (2026-09-25).
- [x] Real Interstitial units on both platforms, swapped into code
      (`ad_service_factory_io.dart` + `Info.plist`
      `GADApplicationIdentifier` + `AndroidManifest.xml`
      `com.google.android.gms.ads.APPLICATION_ID`). Link each store
      listing in AdMob once the apps are live.
- [ ] Keep non-personalized requests (`nonPersonalizedAds: true`) unless
      a deliberate ATT/UMP consent flow ships with it.
- [ ] google_mobile_ads is pinned at ^7.0.0 deliberately - 6.0.0 shares the
      5.x Gradle bug and 9.x breaks the iOS build (non-modular header);
      re-test both platforms before any major bump.

## Web funnel

- [ ] After both store listings are live, verify `appStoreUrl` and
      `playStoreUrl` in `lib/widgets/paywall_dialog.dart` resolve, then
      redeploy Pages (`flutter build web --release --base-href /hexstead/`).

## Device smoke test (per platform, before release)

- [ ] Fresh install: tutorial offer, first game - no ad anywhere.
- [ ] Second game: one interstitial before the board, game starts after
      dismissing it.
- [ ] Airplane mode: game starts instantly, no ad, no error.
- [ ] Buy from a locked chip: chips unlock live, no ad on the next game,
      settings entries gone.
- [ ] Reinstall + restore purchases: unlocked without paying again.

## Build environment note (iOS)

google_mobile_ads is CocoaPods-only while some transitive deps ship
SPM-only manifests. This repo builds iOS with Swift Package Manager
disabled (`flutter config --no-enable-swift-package-manager`), a
per-machine setting that CI or a new machine must apply before
`flutter build ios`.
