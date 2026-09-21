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
