# Hexstead Monetization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Free tier (1 bot, easy, one pre-game interstitial) plus a $5.99 one-time unlock (`hexstead.full`) that opens 2-3 bots, medium/hard difficulty, and removes ads, on iOS and Android, with the web build as an ad-free funnel.

**Architecture:** A `lib/monetization/` module in the codebase's existing store-singleton style: pure gating rules, a `PurchaseStore` (ChangeNotifier) over an abstract `PurchaseGateway` (in_app_purchase on mobile, unsupported stub elsewhere via conditional imports), and an `AdService` (google_mobile_ads on mobile, no-op elsewhere). UI touches: locked chips + paywall dialog on the setup screen, unlock/restore entries in the settings overlay.

**Tech Stack:** Flutter, `in_app_purchase` ^3.2.0, `google_mobile_ads` ^5.2.0, `url_launcher` ^6.3.0, `shared_preferences` (already present), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-20-monetization-design.md`

## Global Constraints

- Product id is exactly `hexstead.full`; price tier $5.99 USD (set in the store consoles, never hardcoded in UI - always show the localized price from the store).
- An ad or store failure must never block or delay starting a game (skip the ad, surface a short message, continue).
- No ads and no IAP plugin code in the web bundle: platform code goes behind conditional imports (`if (dart.library.io)`), never plain imports from shared files.
- Non-personalized ads only (`AdRequest(nonPersonalizedAds: true)`); no ATT prompt.
- Google test app/ad-unit ids until release (real ids are a release-checklist swap, called out in Task 9).
- All user-facing copy and comments use plain "-", never an em-dash.
- Existing engine constraint: any new randomness must be 32-bit web-safe (this plan adds none).
- Commit messages follow the repo style: `App: <what changed>` for app code, `Docs: <what>` for docs.
- Run tests with `flutter test <file>` from the repo root; run `flutter analyze` before every commit.

---

### Task 1: Entitlement rules and keys (pure logic)

**Files:**
- Create: `lib/monetization/entitlements.dart`
- Test: `test/entitlements_test.dart`

**Interfaces:**
- Consumes: `BotDifficulty` from `package:hexstead_engine/hexstead_engine.dart`.
- Produces (later tasks import these exact names):
  - `const String fullUnlockProductId = 'hexstead.full';`
  - `const String unlockedCacheKey = 'unlocked_v1';`
  - `const String gamesStartedKey = 'games_started_v1';`
  - `bool setupChoiceAllowed({required bool unlocked, required int botCount, required BotDifficulty difficulty})`
  - `bool shouldShowInterstitial({required bool unlocked, required int gamesStartedBefore})`

- [ ] **Step 1: Write the failing test**

```dart
// test/entitlements_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead_engine/hexstead_engine.dart';

void main() {
  group('setupChoiceAllowed', () {
    test('free tier is exactly 1 bot on easy', () {
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 1, difficulty: BotDifficulty.easy),
          isTrue);
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 2, difficulty: BotDifficulty.easy),
          isFalse);
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 1, difficulty: BotDifficulty.medium),
          isFalse);
      expect(
          setupChoiceAllowed(
              unlocked: false, botCount: 3, difficulty: BotDifficulty.hard),
          isFalse);
    });

    test('unlocked allows everything', () {
      for (final count in [1, 2, 3]) {
        for (final diff in BotDifficulty.values) {
          expect(
              setupChoiceAllowed(
                  unlocked: true, botCount: count, difficulty: diff),
              isTrue);
        }
      }
    });
  });

  group('shouldShowInterstitial', () {
    test('never for unlocked players', () {
      expect(shouldShowInterstitial(unlocked: true, gamesStartedBefore: 5),
          isFalse);
    });

    test('never before the first real game', () {
      expect(shouldShowInterstitial(unlocked: false, gamesStartedBefore: 0),
          isFalse);
    });

    test('shown from the second game on for free players', () {
      expect(shouldShowInterstitial(unlocked: false, gamesStartedBefore: 1),
          isTrue);
      expect(shouldShowInterstitial(unlocked: false, gamesStartedBefore: 7),
          isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/entitlements_test.dart`
Expected: FAIL - `Error: Couldn't resolve the package 'hexstead/monetization/entitlements.dart'` (file does not exist).

- [ ] **Step 3: Write the implementation**

```dart
// lib/monetization/entitlements.dart
import 'package:hexstead_engine/hexstead_engine.dart';

/// The single non-consumable unlock. Must match the product created in
/// App Store Connect and Play Console exactly.
const String fullUnlockProductId = 'hexstead.full';

/// SharedPreferences key caching the entitlement so offline launches keep
/// the unlock. The store's answer wins over this cache when available.
const String unlockedCacheKey = 'unlocked_v1';

/// SharedPreferences key counting real games started via the setup screen.
/// The tutorial never passes through setup, so it never increments this.
const String gamesStartedKey = 'games_started_v1';

/// Free tier is exactly one easy bot; the unlock opens everything else.
bool setupChoiceAllowed({
  required bool unlocked,
  required int botCount,
  required BotDifficulty difficulty,
}) =>
    unlocked || (botCount == 1 && difficulty == BotDifficulty.easy);

/// The pre-game interstitial: free players only, and never before their
/// first real game - the first session stays clean.
bool shouldShowInterstitial({
  required bool unlocked,
  required int gamesStartedBefore,
}) =>
    !unlocked && gamesStartedBefore >= 1;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/entitlements_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze
git add lib/monetization/entitlements.dart test/entitlements_test.dart
git commit -m "App: entitlement rules - free tier is 1 easy bot, ad from the second game"
```

---

### Task 2: PurchaseGateway abstraction and PurchaseStore

**Files:**
- Create: `lib/monetization/purchase_gateway.dart`
- Create: `lib/monetization/purchase_gateway_factory_stub.dart`
- Create: `lib/monetization/purchase_store.dart`
- Test: `test/purchase_store_test.dart`

**Interfaces:**
- Consumes: `fullUnlockProductId`, `unlockedCacheKey` from Task 1.
- Produces:
  - `enum PurchaseEventType { purchased, restored, cancelled, pending, error }`
  - `class PurchaseEvent { final PurchaseEventType type; final String? message; const PurchaseEvent(this.type, [this.message]); }`
  - `abstract class PurchaseGateway { bool get supported; Stream<PurchaseEvent> get events; Future<String?> queryPrice(String productId); Future<bool> buy(String productId); Future<void> restore(); }`
  - `class UnsupportedPurchaseGateway implements PurchaseGateway` (supported == false, empty stream, null price)
  - `PurchaseGateway createPurchaseGateway()` (factory function; stub-only in this task, becomes a conditional import in Task 3)
  - `class PurchaseStore extends ChangeNotifier` with:
    - `static PurchaseStore instance` (non-final, reassignable in tests)
    - `PurchaseStore(PurchaseGateway gateway, {Duration restoreSettle = const Duration(seconds: 2)})`
    - `bool get isUnlocked`, `String? get price`, `String? get lastError`, `bool get purchasesSupported`
    - `Future<void> load()`, `Future<void> buy()`, `Future<bool> restore()`

- [ ] **Step 1: Write the failing test**

```dart
// test/purchase_store_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PurchaseGateway {
  final events_ = StreamController<PurchaseEvent>.broadcast();
  bool buyCalled = false;
  bool restoreCalled = false;
  String? priceToReturn = r'$5.99';

  @override
  bool get supported => true;

  @override
  Stream<PurchaseEvent> get events => events_.stream;

  @override
  Future<String?> queryPrice(String productId) async => priceToReturn;

  @override
  Future<bool> buy(String productId) async {
    buyCalled = true;
    return true;
  }

  @override
  Future<void> restore() async {
    restoreCalled = true;
  }
}

PurchaseStore storeWith(FakeGateway gateway) =>
    PurchaseStore(gateway, restoreSettle: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts locked with an empty cache', () async {
    SharedPreferences.setMockInitialValues({});
    final store = storeWith(FakeGateway());
    await store.load();
    expect(store.isUnlocked, isFalse);
  });

  test('loads the cached entitlement for offline launches', () async {
    SharedPreferences.setMockInitialValues({unlockedCacheKey: true});
    final store = storeWith(FakeGateway());
    await store.load();
    expect(store.isUnlocked, isTrue);
  });

  test('a purchased event unlocks and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeGateway();
    final store = storeWith(gateway);
    await store.load();
    gateway.events_.add(const PurchaseEvent(PurchaseEventType.purchased));
    await Future<void>.delayed(Duration.zero);
    expect(store.isUnlocked, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(unlockedCacheKey), isTrue);
  });

  test('restore reports true when a restored event arrives', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeGateway();
    final store = storeWith(gateway);
    await store.load();
    gateway.events_.add(const PurchaseEvent(PurchaseEventType.restored));
    await Future<void>.delayed(Duration.zero);
    expect(await store.restore(), isTrue);
    expect(gateway.restoreCalled, isTrue);
  });

  test('restore reports false when nothing comes back', () async {
    SharedPreferences.setMockInitialValues({});
    final store = storeWith(FakeGateway());
    await store.load();
    expect(await store.restore(), isFalse);
  });

  test('an error event surfaces a message and stays locked', () async {
    SharedPreferences.setMockInitialValues({});
    final gateway = FakeGateway();
    final store = storeWith(gateway);
    await store.load();
    gateway.events_
        .add(const PurchaseEvent(PurchaseEventType.error, 'declined'));
    await Future<void>.delayed(Duration.zero);
    expect(store.isUnlocked, isFalse);
    expect(store.lastError, 'declined');
  });

  test('price comes from the gateway', () async {
    SharedPreferences.setMockInitialValues({});
    final store = storeWith(FakeGateway());
    await store.load();
    await Future<void>.delayed(Duration.zero);
    expect(store.price, r'$5.99');
  });

  test('unsupported gateway: locked, no price, restore false', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PurchaseStore(UnsupportedPurchaseGateway(),
        restoreSettle: Duration.zero);
    await store.load();
    expect(store.purchasesSupported, isFalse);
    expect(store.isUnlocked, isFalse);
    expect(await store.restore(), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/purchase_store_test.dart`
Expected: FAIL - missing `purchase_gateway.dart` / `purchase_store.dart`.

- [ ] **Step 3: Write the gateway abstraction**

```dart
// lib/monetization/purchase_gateway.dart
/// What happened on the platform purchase stream, reduced to what the app
/// cares about. `message` is only set for errors.
enum PurchaseEventType { purchased, restored, cancelled, pending, error }

class PurchaseEvent {
  final PurchaseEventType type;
  final String? message;

  const PurchaseEvent(this.type, [this.message]);
}

/// The store platform seam: in_app_purchase on mobile, nothing elsewhere.
/// PurchaseStore is written against this so tests can drive it with a fake.
abstract class PurchaseGateway {
  bool get supported;
  Stream<PurchaseEvent> get events;

  /// Localized price string for the product, or null when the store is
  /// unreachable or the product is missing.
  Future<String?> queryPrice(String productId);

  /// Launches the platform purchase flow. Results arrive on [events].
  Future<bool> buy(String productId);

  /// Asks the platform to replay past purchases onto [events].
  Future<void> restore();
}

/// Platforms with no store (web, desktop): everything reports unavailable.
class UnsupportedPurchaseGateway implements PurchaseGateway {
  @override
  bool get supported => false;

  @override
  Stream<PurchaseEvent> get events => const Stream.empty();

  @override
  Future<String?> queryPrice(String productId) async => null;

  @override
  Future<bool> buy(String productId) async => false;

  @override
  Future<void> restore() async {}
}
```

```dart
// lib/monetization/purchase_gateway_factory_stub.dart
import 'purchase_gateway.dart';

PurchaseGateway createPurchaseGateway() => UnsupportedPurchaseGateway();
```

- [ ] **Step 4: Write PurchaseStore**

```dart
// lib/monetization/purchase_store.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entitlements.dart';
import 'purchase_gateway.dart';
import 'purchase_gateway_factory_stub.dart';

/// Owns the one entitlement: whether the full game is unlocked. Cached in
/// prefs so offline launches keep the unlock; purchase and restore events
/// from the gateway are the source of truth when they arrive.
class PurchaseStore extends ChangeNotifier {
  PurchaseStore(this._gateway,
      {Duration restoreSettle = const Duration(seconds: 2)})
      : _restoreSettle = restoreSettle;

  /// Reassignable so tests (and Task 3's conditional factory) can swap the
  /// gateway; production code only ever reads it.
  static PurchaseStore instance = PurchaseStore(createPurchaseGateway());

  final PurchaseGateway _gateway;

  /// Restored events arrive on the stream, possibly after the platform
  /// restore call returns; this window keeps "no purchase found" honest
  /// without a spinner state machine. Zero in tests.
  final Duration _restoreSettle;

  StreamSubscription<PurchaseEvent>? _sub;
  bool _unlocked = false;
  String? _price;
  String? _lastError;

  bool get isUnlocked => _unlocked;
  String? get price => _price;
  String? get lastError => _lastError;
  bool get purchasesSupported => _gateway.supported;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _unlocked = prefs.getBool(unlockedCacheKey) ?? false;
    _sub ??= _gateway.events.listen(_onEvent);
    notifyListeners();
    if (_gateway.supported) unawaited(_refreshPrice());
  }

  Future<void> _refreshPrice() async {
    _price = await _gateway.queryPrice(fullUnlockProductId);
    notifyListeners();
  }

  Future<void> _onEvent(PurchaseEvent event) async {
    switch (event.type) {
      case PurchaseEventType.purchased:
      case PurchaseEventType.restored:
        await _setUnlocked(true);
      case PurchaseEventType.error:
        _lastError = event.message ?? 'Purchase failed';
        notifyListeners();
      case PurchaseEventType.cancelled:
      case PurchaseEventType.pending:
        break;
    }
  }

  Future<void> _setUnlocked(bool value) async {
    _unlocked = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(unlockedCacheKey, value);
    notifyListeners();
  }

  Future<void> buy() async {
    _lastError = null;
    if (!_gateway.supported) return;
    await _gateway.buy(fullUnlockProductId);
  }

  /// Returns true when a past purchase came back. False after the settle
  /// window means "no purchase found".
  Future<bool> restore() async {
    _lastError = null;
    if (!_gateway.supported) return false;
    await _gateway.restore();
    await Future<void>.delayed(_restoreSettle);
    return _unlocked;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/purchase_store_test.dart`
Expected: PASS (all 8 tests).

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/monetization/ test/purchase_store_test.dart
git commit -m "App: PurchaseStore over an abstract gateway, entitlement cached in prefs"
```

---

### Task 3: Mobile purchase gateway (in_app_purchase) and startup wiring

**Files:**
- Modify: `pubspec.yaml` (add `in_app_purchase: ^3.2.0` under dependencies)
- Create: `lib/monetization/purchase_gateway_factory_io.dart`
- Modify: `lib/monetization/purchase_store.dart` (factory import becomes conditional)
- Modify: `lib/main.dart` (load the store at startup)

**Interfaces:**
- Consumes: `PurchaseGateway`, `PurchaseEvent`, `UnsupportedPurchaseGateway` from Task 2; `fullUnlockProductId` from Task 1.
- Produces: `createPurchaseGateway()` resolved by conditional import - `MobilePurchaseGateway` on iOS/Android, `UnsupportedPurchaseGateway` on web/desktop. No new names for later tasks.

There is no meaningful unit test for the plugin wrapper itself (it is a thin adapter over platform channels); its behavior is covered by the StoreKit/Play manual flows in Task 9. The gate for this task is: all existing tests still pass, and the web build still compiles without the plugin (checked in Task 10).

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` dependencies (alphabetical, after `hexstead_engine`):

```yaml
  in_app_purchase: ^3.2.0
```

Run: `flutter pub get`
Expected: resolves without errors.

- [ ] **Step 2: Write the mobile gateway**

```dart
// lib/monetization/purchase_gateway_factory_io.dart
import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'entitlements.dart';
import 'purchase_gateway.dart';

PurchaseGateway createPurchaseGateway() {
  if (Platform.isIOS || Platform.isAndroid) return MobilePurchaseGateway();
  return UnsupportedPurchaseGateway();
}

/// Adapter over the in_app_purchase plugin: translates its purchase stream
/// into PurchaseEvents and completes purchases so StoreKit/Play stop
/// redelivering them.
class MobilePurchaseGateway implements PurchaseGateway {
  MobilePurchaseGateway() {
    InAppPurchase.instance.purchaseStream.listen(_onPurchases);
  }

  final _events = StreamController<PurchaseEvent>.broadcast();

  @override
  bool get supported => true;

  @override
  Stream<PurchaseEvent> get events => _events.stream;

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      _events.add(switch (p.status) {
        PurchaseStatus.purchased =>
          const PurchaseEvent(PurchaseEventType.purchased),
        PurchaseStatus.restored =>
          const PurchaseEvent(PurchaseEventType.restored),
        PurchaseStatus.canceled =>
          const PurchaseEvent(PurchaseEventType.cancelled),
        PurchaseStatus.pending =>
          const PurchaseEvent(PurchaseEventType.pending),
        PurchaseStatus.error =>
          PurchaseEvent(PurchaseEventType.error, p.error?.message),
      });
      if (p.pendingCompletePurchase) {
        unawaited(InAppPurchase.instance.completePurchase(p));
      }
    }
  }

  Future<ProductDetails?> _product() async {
    if (!await InAppPurchase.instance.isAvailable()) return null;
    final resp = await InAppPurchase.instance
        .queryProductDetails({fullUnlockProductId});
    return resp.productDetails.isEmpty ? null : resp.productDetails.first;
  }

  @override
  Future<String?> queryPrice(String productId) async =>
      (await _product())?.price;

  @override
  Future<bool> buy(String productId) async {
    final product = await _product();
    if (product == null) {
      _events.add(const PurchaseEvent(
          PurchaseEventType.error, 'Store unavailable - try again later'));
      return false;
    }
    return InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product));
  }

  @override
  Future<void> restore() => InAppPurchase.instance.restorePurchases();
}
```

- [ ] **Step 3: Switch the factory import to conditional**

In `lib/monetization/purchase_store.dart`, replace:

```dart
import 'purchase_gateway_factory_stub.dart';
```

with:

```dart
import 'purchase_gateway_factory_stub.dart'
    if (dart.library.io) 'purchase_gateway_factory_io.dart';
```

- [ ] **Step 4: Load the store at startup**

In `lib/main.dart`, add the import and the load line after `SoundStore.instance.load()`:

```dart
import 'monetization/purchase_store.dart';
```

```dart
  await ArtStore.instance.load();
  await SoundStore.instance.load();
  await PurchaseStore.instance.load();
```

(`load()` reads the prefs cache synchronously-ish and kicks off the price query without awaiting it, so startup is not blocked on the network.)

- [ ] **Step 5: Verify nothing broke**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass (the VM test binary picks the io factory, but no test constructs `MobilePurchaseGateway` - `PurchaseStore.instance` is never touched by existing tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/monetization/ lib/main.dart
git commit -m "App: real purchases on mobile via in_app_purchase, stub elsewhere"
```

---

### Task 4: Paywall dialog

**Files:**
- Create: `lib/widgets/paywall_dialog.dart`
- Test: `test/paywall_dialog_test.dart`

**Interfaces:**
- Consumes: `PurchaseStore` (Task 2), `parchmentPanel()` from `lib/widgets/chrome.dart`, `SoundStore.instance.playSfx(Sfx.uiTap)`.
- Produces:
  - `Future<void> showPaywall(BuildContext context)` - later tasks call exactly this.
  - `const String appStoreUrl = 'https://apps.apple.com/app/id6812996489';`
  - `const String playStoreUrl = 'https://play.google.com/store/apps/details?id=com.hexstead.hexstead';`
- New dependency: `url_launcher: ^6.3.0`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` dependencies (alphabetical):

```yaml
  url_launcher: ^6.3.0
```

Run: `flutter pub get`

- [ ] **Step 2: Write the failing test**

```dart
// test/paywall_dialog_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/widgets/paywall_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PurchaseGateway {
  FakeGateway({this.isSupported = true});

  final bool isSupported;
  final events_ = StreamController<PurchaseEvent>.broadcast();
  bool buyCalled = false;

  @override
  bool get supported => isSupported;

  @override
  Stream<PurchaseEvent> get events => events_.stream;

  @override
  Future<String?> queryPrice(String productId) async => r'$5.99';

  @override
  Future<bool> buy(String productId) async {
    buyCalled = true;
    return true;
  }

  @override
  Future<void> restore() async {}
}

Future<void> openPaywall(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showPaywall(context),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the price and starts a purchase', (tester) async {
    final gateway = FakeGateway();
    PurchaseStore.instance =
        PurchaseStore(gateway, restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    expect(find.textContaining(r'$5.99'), findsOneWidget);

    await tester.tap(find.textContaining('Unlock').last);
    await tester.pump();
    expect(gateway.buyCalled, isTrue);
  });

  testWidgets('closes itself when the purchase lands', (tester) async {
    final gateway = FakeGateway();
    PurchaseStore.instance =
        PurchaseStore(gateway, restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    gateway.events_.add(const PurchaseEvent(PurchaseEventType.purchased));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsNothing);
  });

  testWidgets('unsupported platform shows the store links card',
      (tester) async {
    PurchaseStore.instance = PurchaseStore(FakeGateway(isSupported: false),
        restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    expect(find.text('App Store'), findsOneWidget);
    expect(find.text('Google Play'), findsOneWidget);
  });

  testWidgets('a purchase error is shown in the dialog', (tester) async {
    final gateway = FakeGateway();
    PurchaseStore.instance =
        PurchaseStore(gateway, restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();

    await openPaywall(tester);
    gateway.events_
        .add(const PurchaseEvent(PurchaseEventType.error, 'declined'));
    await tester.pumpAndSettle();
    expect(find.text('declined'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/paywall_dialog_test.dart`
Expected: FAIL - missing `paywall_dialog.dart`.

- [ ] **Step 4: Write the dialog**

```dart
// lib/widgets/paywall_dialog.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio/sound_store.dart';
import '../monetization/purchase_store.dart';
import 'chrome.dart';

const String appStoreUrl = 'https://apps.apple.com/app/id6812996489';
const String playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.hexstead.hexstead';

Future<void> showPaywall(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const PaywallDialog(),
    );

/// The one purchase surface. On platforms with a store it sells the unlock;
/// on the web (and desktop) it becomes the funnel card pointing at the
/// mobile stores, where the full game lives.
class PaywallDialog extends StatefulWidget {
  const PaywallDialog({super.key});

  @override
  State<PaywallDialog> createState() => _PaywallDialogState();
}

class _PaywallDialogState extends State<PaywallDialog> {
  final _store = PurchaseStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (_store.isUnlocked) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: parchmentPanel(radius: 16),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The Full Homestead',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A3826),
              ),
            ),
            const SizedBox(height: 16),
            _benefit(Icons.groups, 'Face 2 or 3 rivals at once'),
            _benefit(Icons.local_fire_department,
                'Fair and Cruel bots - far bigger score bonuses'),
            _benefit(Icons.block, 'No more ads, ever'),
            const SizedBox(height: 20),
            if (_store.purchasesSupported)
              ..._purchaseButtons()
            else
              ..._storeLinks(),
          ],
        ),
      ),
    );
  }

  List<Widget> _purchaseButtons() => [
        FilledButton(
          onPressed: () {
            SoundStore.instance.playSfx(Sfx.uiTap);
            _store.buy();
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
          child: Text(
            _store.price == null ? 'Unlock' : 'Unlock - ${_store.price}',
            style: const TextStyle(fontSize: 17),
          ),
        ),
        if (_store.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _store.lastError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8B3A2E), fontSize: 13),
            ),
          ),
        TextButton(
          onPressed: () async {
            SoundStore.instance.playSfx(Sfx.uiTap);
            final restored = await _store.restore();
            if (!mounted || restored) return;
            setState(() =>
                _restoreMessage = 'No purchase found for this account');
          },
          child: const Text('Restore purchase'),
        ),
        if (_restoreMessage != null)
          Text(
            _restoreMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF7A6647), fontSize: 13),
          ),
      ];

  String? _restoreMessage;

  List<Widget> _storeLinks() => [
        const Text(
          'The full game lives on your phone - grab it and your '
          'homestead grows.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF3A2E20), fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () => launchUrl(Uri.parse(appStoreUrl)),
          child: const Text('App Store'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => launchUrl(Uri.parse(playStoreUrl)),
          child: const Text('Google Play'),
        ),
      ];

  Widget _benefit(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF9A6B1F)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF3A2E20),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
```

Note: move the `String? _restoreMessage;` field declaration up with the other fields (next to `_store`) - shown inline above only to keep the diff readable. Fields never live between methods in this codebase.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/paywall_dialog_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add pubspec.yaml pubspec.lock lib/widgets/paywall_dialog.dart test/paywall_dialog_test.dart
git commit -m "App: paywall dialog - unlock and restore on mobile, store links on web"
```

---

### Task 5: Setup screen gating

**Files:**
- Modify: `lib/screens/setup_screen.dart`
- Test: `test/setup_gating_test.dart`

**Interfaces:**
- Consumes: `setupChoiceAllowed` (Task 1), `PurchaseStore.instance` (Task 2), `showPaywall` + `PaywallDialog` (Task 4).
- Produces: no new public names. Behavior contract for Task 7: `_start()` is still the single entry point for every real game.

- [ ] **Step 1: Write the failing test**

```dart
// test/setup_gating_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/screens/setup_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:hexstead/widgets/paywall_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PurchaseGateway {
  final events_ = StreamController<PurchaseEvent>.broadcast();

  @override
  bool get supported => true;

  @override
  Stream<PurchaseEvent> get events => events_.stream;

  @override
  Future<String?> queryPrice(String productId) async => r'$5.99';

  @override
  Future<bool> buy(String productId) async => true;

  @override
  Future<void> restore() async {}
}

Future<FakeGateway> pumpSetup(WidgetTester tester,
    {bool unlocked = false}) async {
  SharedPreferences.setMockInitialValues(
      {if (unlocked) 'unlocked_v1': true});
  final gateway = FakeGateway();
  PurchaseStore.instance =
      PurchaseStore(gateway, restoreSettle: Duration.zero);
  await PurchaseStore.instance.load();
  await tester.pumpWidget(MaterialApp(
    home: SetupScreen(controller: GameController(saveStore: NullSaveStore())),
  ));
  await tester.pump();
  return gateway;
}

void main() {
  testWidgets('free tier defaults to 1 bot on Easy', (tester) async {
    await pumpSetup(tester);
    final oneBot = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('1 bot'), matching: find.byType(ChoiceChip)));
    final easy = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('Easy'), matching: find.byType(ChoiceChip)));
    expect(oneBot.selected, isTrue);
    expect(easy.selected, isTrue);
  });

  testWidgets('locked chips open the paywall instead of selecting',
      (tester) async {
    await pumpSetup(tester);
    await tester.tap(find.text('2 bots'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // dismiss barrier
    await tester.pumpAndSettle();
    final twoBots = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('2 bots'), matching: find.byType(ChoiceChip)));
    expect(twoBots.selected, isFalse);
  });

  testWidgets('locked chips carry a lock icon', (tester) async {
    await pumpSetup(tester);
    // 2 bots, 3 bots, Fair, Cruel are locked in the free tier.
    expect(find.byIcon(Icons.lock), findsNWidgets(4));
  });

  testWidgets('unlocked players select anything, no locks, no paywall',
      (tester) async {
    await pumpSetup(tester, unlocked: true);
    expect(find.byIcon(Icons.lock), findsNothing);
    await tester.tap(find.text('Cruel'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsNothing);
    final cruel = tester.widget<ChoiceChip>(find.ancestor(
        of: find.text('Cruel'), matching: find.byType(ChoiceChip)));
    expect(cruel.selected, isTrue);
  });

  testWidgets('chips unlock live when the purchase lands', (tester) async {
    final gateway = await pumpSetup(tester);
    gateway.events_.add(const PurchaseEvent(PurchaseEventType.purchased));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/setup_gating_test.dart`
Expected: FAIL - defaults are 2 bots / Fair, no lock icons, no paywall.

- [ ] **Step 3: Modify the setup screen**

In `lib/screens/setup_screen.dart`:

Add imports:

```dart
import '../monetization/entitlements.dart';
import '../monetization/purchase_store.dart';
import '../widgets/paywall_dialog.dart';
```

Replace the two state fields and add lifecycle wiring:

```dart
class _SetupScreenState extends State<SetupScreen> {
  // Free tier starts on its own allowed combination; unlocked players keep
  // the classic default of a fair 3-player game.
  late int _botCount = PurchaseStore.instance.isUnlocked ? 2 : 1;
  late BotDifficulty _difficulty = PurchaseStore.instance.isUnlocked
      ? BotDifficulty.medium
      : BotDifficulty.easy;

  @override
  void initState() {
    super.initState();
    PurchaseStore.instance.addListener(_onPurchaseChanged);
  }

  @override
  void dispose() {
    PurchaseStore.instance.removeListener(_onPurchaseChanged);
    super.dispose();
  }

  /// A purchase can land while this screen is up (paywall opened from a
  /// locked chip) - the locks have to melt away without a rebuild from
  /// outside.
  void _onPurchaseChanged() {
    if (mounted) setState(() {});
  }
```

Update both `Wrap` chip loops to compute and pass `locked`:

```dart
                for (final count in [1, 2, 3])
                  _chip(
                    label: count == 1 ? '1 bot' : '$count bots',
                    selected: _botCount == count,
                    locked: !setupChoiceAllowed(
                      unlocked: PurchaseStore.instance.isUnlocked,
                      botCount: count,
                      difficulty: BotDifficulty.easy,
                    ),
                    onSelected: () => setState(() => _botCount = count),
                  ),
```

```dart
                for (final entry in const {
                  BotDifficulty.easy: 'Easy',
                  BotDifficulty.medium: 'Fair',
                  BotDifficulty.hard: 'Cruel',
                }.entries)
                  _chip(
                    label: entry.value,
                    selected: _difficulty == entry.key,
                    locked: !setupChoiceAllowed(
                      unlocked: PurchaseStore.instance.isUnlocked,
                      botCount: 1,
                      difficulty: entry.key,
                    ),
                    onSelected: () => setState(() => _difficulty = entry.key),
                  ),
```

(Each axis is checked with the other axis at its free-tier value, so the
lock reflects the option itself, not the current combination.)

Replace `_chip` with:

```dart
  Widget _chip({
    required String label,
    required bool selected,
    required bool locked,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) {
        SoundStore.instance.playSfx(Sfx.uiTap);
        if (locked) {
          showPaywall(context);
          return;
        }
        onSelected();
      },
      showCheckmark: false,
      selectedColor: const Color(0xFF9A6B1F),
      backgroundColor: const Color(0xFFE7D9B8),
      side: const BorderSide(color: Color(0xFF8A6F4D)),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[
            const Icon(Icons.lock, size: 14, color: Color(0xFF8A6F4D)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected
                  ? Colors.white
                  : locked
                      ? const Color(0xFF8A7B62)
                      : const Color(0xFF3A2E20),
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/setup_gating_test.dart && flutter test`
Expected: new tests PASS; the full suite still passes (game_screen/full_game tests build their own controllers and never touch setup).

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze
git add lib/screens/setup_screen.dart test/setup_gating_test.dart
git commit -m "App: setup screen locks 2-3 bots and Fair/Cruel behind the unlock"
```

---

### Task 6: AdService abstraction and the pre-game slot

**Files:**
- Create: `lib/monetization/ad_service.dart`
- Create: `lib/monetization/ad_service_factory_stub.dart`
- Modify: `lib/screens/setup_screen.dart` (counter + ad in `_start()`, preload in `initState`)
- Test: `test/pregame_ad_test.dart`

**Interfaces:**
- Consumes: `shouldShowInterstitial`, `gamesStartedKey` (Task 1), `PurchaseStore.instance` (Task 2).
- Produces:
  - `abstract class AdService { static AdService instance; void preload(); Future<void> showIfReady(); }` - `instance` non-final for tests and for the Task 7 conditional factory.
  - `class NoopAdService implements AdService` (does nothing; web/desktop and the default until Task 7).
  - `AdService createAdService()` (stub-only in this task).

- [ ] **Step 1: Write the failing test**

```dart
// test/pregame_ad_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/ad_service.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/screens/setup_screen.dart';
import 'package:hexstead/state/game_controller.dart';
import 'package:hexstead/state/persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingAdService implements AdService {
  int preloads = 0;
  int shows = 0;

  @override
  void preload() => preloads++;

  @override
  Future<void> showIfReady() async => shows++;
}

Future<RecordingAdService> pumpAndStart(WidgetTester tester,
    {required bool unlocked, required int gamesStarted}) async {
  SharedPreferences.setMockInitialValues({
    if (unlocked) unlockedCacheKey: true,
    gamesStartedKey: gamesStarted,
  });
  PurchaseStore.instance = PurchaseStore(UnsupportedPurchaseGateway(),
      restoreSettle: Duration.zero);
  await PurchaseStore.instance.load();
  final ads = RecordingAdService();
  AdService.instance = ads;
  await tester.pumpWidget(MaterialApp(
    home: SetupScreen(controller: GameController(saveStore: NullSaveStore())),
  ));
  await tester.pump();
  await tester.tap(find.text('Begin'));
  // startNewGame runs a real board setup; give it generous settle time.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return ads;
}

void main() {
  testWidgets('second game for a free player shows the interstitial',
      (tester) async {
    final ads =
        await pumpAndStart(tester, unlocked: false, gamesStarted: 1);
    expect(ads.shows, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(gamesStartedKey), 2);
  });

  testWidgets('first game stays clean', (tester) async {
    final ads =
        await pumpAndStart(tester, unlocked: false, gamesStarted: 0);
    expect(ads.shows, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(gamesStartedKey), 1);
  });

  testWidgets('unlocked players never see an ad and never preload',
      (tester) async {
    final ads =
        await pumpAndStart(tester, unlocked: true, gamesStarted: 9);
    expect(ads.shows, 0);
    expect(ads.preloads, 0);
  });

  testWidgets('eligible free players preload on the setup screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({gamesStartedKey: 1});
    PurchaseStore.instance = PurchaseStore(UnsupportedPurchaseGateway(),
        restoreSettle: Duration.zero);
    await PurchaseStore.instance.load();
    final ads = RecordingAdService();
    AdService.instance = ads;
    await tester.pumpWidget(MaterialApp(
      home:
          SetupScreen(controller: GameController(saveStore: NullSaveStore())),
    ));
    await tester.pumpAndSettle();
    expect(ads.preloads, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pregame_ad_test.dart`
Expected: FAIL - missing `ad_service.dart`.

- [ ] **Step 3: Write the ad service seam**

```dart
// lib/monetization/ad_service.dart
import 'ad_service_factory_stub.dart';

/// The interstitial seam. The mobile implementation (google_mobile_ads)
/// arrives via the conditional factory; everywhere else this is a no-op,
/// and an ad must never delay or prevent play.
abstract class AdService {
  /// Reassignable so tests can record calls; production only reads it.
  static AdService instance = createAdService();

  /// Fire-and-forget: start fetching an interstitial so it is ready by the
  /// time the player taps Begin. Safe to call repeatedly.
  void preload();

  /// Shows the loaded interstitial and completes when it is dismissed.
  /// Completes immediately when nothing is loaded - the game starts anyway.
  Future<void> showIfReady();
}

class NoopAdService implements AdService {
  @override
  void preload() {}

  @override
  Future<void> showIfReady() async {}
}
```

```dart
// lib/monetization/ad_service_factory_stub.dart
import 'ad_service.dart';

AdService createAdService() => NoopAdService();
```

- [ ] **Step 4: Wire the setup screen**

In `lib/screens/setup_screen.dart`:

Add imports:

```dart
import 'package:shared_preferences/shared_preferences.dart';

import '../monetization/ad_service.dart';
```

In `initState()`, after the purchase listener line, add:

```dart
    _maybePreloadAd();
```

Add the helper and rewrite `_start()`:

```dart
  /// Only fetch ad inventory when it can actually be shown: free player,
  /// past the first-game grace. Unlocked players never load the SDK's work.
  Future<void> _maybePreloadAd() async {
    if (PurchaseStore.instance.isUnlocked) return;
    final prefs = await SharedPreferences.getInstance();
    final started = prefs.getInt(gamesStartedKey) ?? 0;
    if (shouldShowInterstitial(unlocked: false, gamesStartedBefore: started)) {
      AdService.instance.preload();
    }
  }

  Future<void> _start() async {
    SoundStore.instance.playSfx(Sfx.uiTap);
    final players = [
      const PlayerSetup(name: 'You', isBot: false),
      for (var i = 0; i < _botCount; i++)
        PlayerSetup(name: _botNames[i], isBot: true, difficulty: _difficulty),
    ];
    final navigator = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    final startedBefore = prefs.getInt(gamesStartedKey) ?? 0;
    await prefs.setInt(gamesStartedKey, startedBefore + 1);
    if (shouldShowInterstitial(
      unlocked: PurchaseStore.instance.isUnlocked,
      gamesStartedBefore: startedBefore,
    )) {
      await AdService.instance.showIfReady();
    }
    await widget.controller.startNewGame(
      seed: DateTime.now().millisecondsSinceEpoch,
      players: players,
    );
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen(controller: widget.controller),
      ),
    );
  }
```

(The tutorial starts from the menu, never through here, so it is exempt by construction. "Play again" on the game over screen routes back to this screen, so replays pass the ad slot too.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/pregame_ad_test.dart && flutter test test/setup_gating_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze
git add lib/monetization/ lib/screens/setup_screen.dart test/pregame_ad_test.dart
git commit -m "App: pre-game interstitial slot - free players only, first game clean"
```

---

### Task 7: Mobile ads (google_mobile_ads) and platform config

**Files:**
- Modify: `pubspec.yaml` (add `google_mobile_ads: ^5.2.0`)
- Create: `lib/monetization/ad_service_factory_io.dart`
- Modify: `lib/monetization/ad_service.dart` (factory import becomes conditional)
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts` (minSdk floor 23)

**Interfaces:**
- Consumes: `AdService`, `NoopAdService` (Task 6).
- Produces: `createAdService()` resolved by conditional import - `MobileAdService` on iOS/Android, `NoopAdService` elsewhere. No new names for later tasks.

Like Task 3, the plugin adapter has no meaningful unit test; the gates are compilation, the full suite staying green, and the on-device checks in Task 9.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` dependencies (alphabetical):

```yaml
  google_mobile_ads: ^5.2.0
```

Run: `flutter pub get`

- [ ] **Step 2: Write the mobile ad service**

```dart
// lib/monetization/ad_service_factory_io.dart
import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

AdService createAdService() {
  if (Platform.isIOS || Platform.isAndroid) return MobileAdService();
  return NoopAdService();
}

/// One preloaded interstitial, non-personalized requests only (no ATT
/// prompt, minimal privacy labels). Load failures are silently absorbed:
/// the game starts without an ad, never behind a spinner.
class MobileAdService implements AdService {
  // Google's public test ids. The release checklist swaps these for the
  // real AdMob unit ids (docs/RELEASE_MONETIZATION.md).
  static final String _adUnitId = Platform.isIOS
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-3940256099942544/1033173712';

  bool _sdkStarted = false;
  bool _loading = false;
  InterstitialAd? _ready;

  @override
  void preload() {
    if (_ready != null || _loading) return;
    _loading = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      if (!_sdkStarted) {
        _sdkStarted = true;
        await MobileAds.instance.initialize();
      }
      await InterstitialAd.load(
        adUnitId: _adUnitId,
        request: const AdRequest(nonPersonalizedAds: true),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _ready = ad;
            _loading = false;
          },
          onAdFailedToLoad: (_) {
            _ready = null;
            _loading = false;
          },
        ),
      );
    } catch (_) {
      _loading = false; // no inventory, no crash - play goes on
    }
  }

  @override
  Future<void> showIfReady() async {
    final ad = _ready;
    if (ad == null) return;
    _ready = null;
    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        dismissed.complete();
      },
    );
    await ad.show();
    await dismissed.future;
  }
}
```

- [ ] **Step 3: Switch the factory import to conditional**

In `lib/monetization/ad_service.dart`, replace:

```dart
import 'ad_service_factory_stub.dart';
```

with:

```dart
import 'ad_service_factory_stub.dart'
    if (dart.library.io) 'ad_service_factory_io.dart';
```

- [ ] **Step 4: iOS config**

In `ios/Runner/Info.plist`, inside the top-level `<dict>`, add (Google's
test application id until release):

```xml
	<key>GADApplicationIdentifier</key>
	<string>ca-app-pub-3940256099942544~1458002511</string>
	<key>SKAdNetworkItems</key>
	<array>
		<dict>
			<key>SKAdNetworkIdentifier</key>
			<string>cstr6suwn9.skadnetwork</string>
		</dict>
	</array>
```

- [ ] **Step 5: Android config**

In `android/app/src/main/AndroidManifest.xml`, inside `<application>`, add
(test application id until release):

```xml
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-3940256099942544~3347511713" />
```

In `android/app/build.gradle.kts`, replace:

```kotlin
        minSdk = flutter.minSdkVersion
```

with:

```kotlin
        // google_mobile_ads needs 23; keep Flutter's floor if it ever rises.
        minSdk = maxOf(flutter.minSdkVersion, 23)
```

- [ ] **Step 6: Verify nothing broke**

Run: `flutter analyze && flutter test`
Expected: clean and green. The VM test binary compiles the io factory but
every ad test injects `RecordingAdService`, so `MobileAdService` is never
constructed (its guard also returns `NoopAdService` off-phone).

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/monetization/ ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml android/app/build.gradle.kts
git commit -m "App: real interstitials on mobile - non-personalized, test ids for now"
```

---

### Task 8: Settings overlay - unlock and restore entries

**Files:**
- Modify: `lib/widgets/settings_overlay.dart`
- Test: `test/settings_purchase_test.dart`

**Interfaces:**
- Consumes: `PurchaseStore.instance` (Task 2), `showPaywall` (Task 4).
- Produces: no new public names.

- [ ] **Step 1: Write the failing test**

```dart
// test/settings_purchase_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/monetization/entitlements.dart';
import 'package:hexstead/monetization/purchase_gateway.dart';
import 'package:hexstead/monetization/purchase_store.dart';
import 'package:hexstead/widgets/paywall_dialog.dart';
import 'package:hexstead/widgets/settings_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PurchaseGateway {
  FakeGateway({this.isSupported = true, this.restoreUnlocks = false});

  final bool isSupported;
  final bool restoreUnlocks;
  final events_ = StreamController<PurchaseEvent>.broadcast();

  @override
  bool get supported => isSupported;

  @override
  Stream<PurchaseEvent> get events => events_.stream;

  @override
  Future<String?> queryPrice(String productId) async => r'$5.99';

  @override
  Future<bool> buy(String productId) async => true;

  @override
  Future<void> restore() async {
    if (restoreUnlocks) {
      events_.add(const PurchaseEvent(PurchaseEventType.restored));
    }
  }
}

Future<void> pumpSettings(WidgetTester tester, FakeGateway gateway,
    {bool unlocked = false}) async {
  SharedPreferences.setMockInitialValues(
      {if (unlocked) unlockedCacheKey: true});
  PurchaseStore.instance =
      PurchaseStore(gateway, restoreSettle: Duration.zero);
  await PurchaseStore.instance.load();
  await tester.pumpWidget(MaterialApp(
    home: Stack(children: [
      SettingsOverlay(onClose: () {}, onQuitToMenu: () {}),
    ]),
  ));
  await tester.pump();
}

void main() {
  testWidgets('locked players see unlock and restore entries',
      (tester) async {
    await pumpSettings(tester, FakeGateway());
    expect(find.text('Unlock full game'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
  });

  testWidgets('unlock entry opens the paywall', (tester) async {
    await pumpSettings(tester, FakeGateway());
    await tester.tap(find.text('Unlock full game'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallDialog), findsOneWidget);
  });

  testWidgets('restore with a past purchase reports success',
      (tester) async {
    await pumpSettings(tester, FakeGateway(restoreUnlocks: true));
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase restored - enjoy!'), findsOneWidget);
  });

  testWidgets('restore with nothing to restore says so', (tester) async {
    await pumpSettings(tester, FakeGateway());
    await tester.tap(find.text('Restore purchases'));
    await tester.pumpAndSettle();
    expect(find.text('No purchase found for this account'), findsOneWidget);
  });

  testWidgets('unlocked players see neither entry', (tester) async {
    await pumpSettings(tester, FakeGateway(), unlocked: true);
    expect(find.text('Unlock full game'), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
  });

  testWidgets('web (unsupported store) shows neither entry', (tester) async {
    await pumpSettings(tester, FakeGateway(isSupported: false));
    expect(find.text('Unlock full game'), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/settings_purchase_test.dart`
Expected: FAIL - no such entries in the overlay.

- [ ] **Step 3: Modify the settings overlay**

In `lib/widgets/settings_overlay.dart`:

Add imports:

```dart
import '../monetization/purchase_store.dart';
import 'paywall_dialog.dart';
```

In `_SettingsOverlayState`, add the store listener (the entries must vanish
the moment a purchase made through this very overlay lands):

```dart
  @override
  void initState() {
    super.initState();
    PurchaseStore.instance.addListener(_onPurchaseChanged);
    // ... existing SoundStore.load() block stays ...
  }

  @override
  void dispose() {
    PurchaseStore.instance.removeListener(_onPurchaseChanged);
    super.dispose();
  }

  void _onPurchaseChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    SoundStore.instance.playSfx(Sfx.uiTap);
    final restored = await PurchaseStore.instance.restore();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(restored
            ? 'Purchase restored - enjoy!'
            : 'No purchase found for this account'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
```

In `build()`, between the Sounds toggle and the `SizedBox(height: 12)`
before the Home button, insert:

```dart
                    if (PurchaseStore.instance.purchasesSupported &&
                        !PurchaseStore.instance.isUnlocked) ...[
                      TextButton(
                        onPressed: () {
                          SoundStore.instance.playSfx(Sfx.uiTap);
                          showPaywall(context);
                        },
                        child: const Text('Unlock full game'),
                      ),
                      TextButton(
                        onPressed: _restore,
                        child: const Text('Restore purchases'),
                      ),
                    ],
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/settings_purchase_test.dart && flutter test`
Expected: new tests PASS; full suite green (existing settings-dependent
tests may construct the overlay - if any fail on the new PurchaseStore
touch, they need `SharedPreferences.setMockInitialValues({})` in their
setup, which is the standard fix in this repo, not a design change).

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze
git add lib/widgets/settings_overlay.dart test/settings_purchase_test.dart
git commit -m "App: unlock and restore entries in settings"
```

---

### Task 9: Release checklist document (store admin, id swaps, manual test flows)

**Files:**
- Create: `docs/RELEASE_MONETIZATION.md`

**Interfaces:** none - this is the operator's runbook for everything code cannot do.

- [ ] **Step 1: Write the document**

```markdown
# Monetization Release Checklist

Everything here is one-time store admin or a release-day swap. The code
ships with Google's public TEST ids; nothing earns money until this list
is done.

## App Store Connect (app 6812996489, team T388BN3387)

- [ ] Sign the Paid Applications agreement (Agreements, Tax, Banking) and
      complete banking + tax forms.
- [ ] Create the in-app purchase: Non-Consumable, product id exactly
      `hexstead.full`, price $5.99 (USD tier), localized display name
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
- [ ] Add a Non-Consumable: product id `hexstead.full`, price 5.99.
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
- [ ] Create the in-app product `hexstead.full`, $5.99, activate it.
- [ ] Add license testers (Play Console > Settings > License testing) and
      run the same buy/cancel/restore flows on a device.

## AdMob

- [ ] Create an AdMob account, register both apps (iOS and Android).
- [ ] Create one Interstitial ad unit per platform.
- [ ] Swap the ids in code - all four live in two files:
      - `lib/monetization/ad_service_factory_io.dart`: both `_adUnitId`
        values (iOS and Android unit ids).
      - `ios/Runner/Info.plist`: `GADApplicationIdentifier`.
      - `android/app/src/main/AndroidManifest.xml`:
        `com.google.android.gms.ads.APPLICATION_ID`.
- [ ] Keep non-personalized requests (`nonPersonalizedAds: true`) unless
      a deliberate ATT/UMP consent flow ships with it.

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
```

- [ ] **Step 2: Commit**

```bash
git add docs/RELEASE_MONETIZATION.md
git commit -m "Docs: monetization release checklist - store admin, id swaps, smoke tests"
```

---

### Task 10: Full verification - suite, analyzer, and the web bundle promise

**Files:** none created; this task gates the branch.

- [ ] **Step 1: Full test suite and analyzer**

Run: `flutter analyze && flutter test`
Expected: analyzer clean; every test passes, including the goldens
(`board_golden_test.dart` is untouched by this work - if it fails, the
failure predates this branch; check `test/failures/`).

- [ ] **Step 2: Web build compiles and excludes the mobile SDKs**

```bash
flutter build web --release --base-href /hexstead/
grep -c "google_mobile_ads\|GADInterstitial\|in_app_purchase" build/web/main.dart.js || echo "CLEAN"
```

Expected: build succeeds; the grep prints `0` or `CLEAN` (conditional
imports kept both plugins out of the js bundle). If it prints a nonzero
count, a shared file imports a mobile plugin directly - find it with
`grep -rn "google_mobile_ads\|in_app_purchase" lib/` and route it through
the factory files.

- [ ] **Step 3: iOS compiles**

Run: `flutter build ios --no-codesign`
Expected: succeeds (CocoaPods pulls GoogleMobileAds and StoreKit wrappers;
first run is slow).

- [ ] **Step 4: Android compiles (best effort)**

Run: `flutter build apk --debug`
Expected: succeeds if an Android SDK is installed on this machine. If the
toolchain is missing, record that explicitly in the task report - do not
claim Android verified - and note it as a follow-up for the operator.

- [ ] **Step 5: Commit anything the builds touched**

```bash
git status --short
# expect only pubspec.lock / ios/Podfile.lock style changes; commit them:
git add -A
git commit -m "App: lockfile updates from monetization builds" || echo "nothing to commit"
```

---

## Self-review notes

- Spec coverage: free tier rules (Task 1, 5), unlock SKU + restore (Tasks 2-4, 8), ad slot with tutorial/first-game exemptions (Tasks 6-7), web funnel + bundle exclusion (Tasks 4, 10), platform admin including the Play applicationId trap (Task 9), error handling "never block play" (PurchaseStore error events surface in the paywall, MobileAdService absorbs load failures, `showIfReady` no-ops when empty).
- The spec's "paywall reachable from settings" and "restore in settings" land in Task 8; "store's answer wins over cache" is the purchased/restored event path in Task 2 (note: the store never revokes locally - a refunded purchase stays cached until the platform replays state; acceptable at this scale and consistent with the spec's local-verification stance).
- Type check: `PurchaseEvent(PurchaseEventType, [String?])`, `setupChoiceAllowed(unlocked:, botCount:, difficulty:)`, `shouldShowInterstitial(unlocked:, gamesStartedBefore:)`, `AdService.preload()/showIfReady()` are used with identical signatures in every task that consumes them.
