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
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    try {
      await ad.show();
    } catch (_) {
      // show() can throw on the platform channel (ad disposed, activity
      // gone) independent of the callbacks above - absorb it, play goes on.
      ad.dispose();
      if (!dismissed.isCompleted) dismissed.complete();
    }
    await dismissed.future;
  }
}
