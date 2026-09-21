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
