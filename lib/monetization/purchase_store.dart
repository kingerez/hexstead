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
      {this.restoreSettle = const Duration(seconds: 2)});

  /// Reassignable so tests (and Task 3's conditional factory) can swap the
  /// gateway; production code only ever reads it.
  static PurchaseStore instance = PurchaseStore(createPurchaseGateway());

  final PurchaseGateway _gateway;

  /// Restored events arrive on the stream, possibly after the platform
  /// restore call returns; this window keeps "no purchase found" honest
  /// without a spinner state machine. Zero in tests.
  final Duration restoreSettle;

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
    await Future<void>.delayed(restoreSettle);
    return _unlocked;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
