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
