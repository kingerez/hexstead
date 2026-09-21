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
  String? priceToReturn = r'$3.99';

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

class ThrowingGateway implements PurchaseGateway {
  @override
  bool get supported => true;

  @override
  Stream<PurchaseEvent> get events => const Stream.empty();

  @override
  Future<String?> queryPrice(String productId) async => null;

  @override
  Future<bool> buy(String productId) async => throw Exception('boom');

  @override
  Future<void> restore() async => throw Exception('boom');
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
    expect(store.price, r'$3.99');
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

  test('a throwing gateway never lets play block - buy and restore absorb it',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = PurchaseStore(ThrowingGateway(), restoreSettle: Duration.zero);
    await store.load();
    await store.buy();
    expect(store.lastError, isNotNull);
    expect(await store.restore(), isFalse);
  });
}
