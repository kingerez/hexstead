import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Product analytics: one seam over PostHog so game code never imports the
/// SDK, and so anything that skips [init] - every test - gets a silent
/// no-op instead of a client that would reach for the network.
///
/// Nothing here may ever throw or await on the caller's behalf: a dropped
/// event is a lost data point, a thrown one is a lost game.
class Analytics {
  Analytics._();

  static final Analytics instance = Analytics._();

  static const _projectToken =
      'phc_oUuFMTuVcdBtrNfNivsXk6PSs9QPLjET59eujzY7Jr7J';
  static const _host = 'https://eu.i.posthog.com';

  /// Debug runs stay off the wire unless the dart-define asks otherwise:
  /// `--dart-define=POSTHOG_DEV=true` to check the wiring before a release.
  static const _enabled =
      kReleaseMode || bool.fromEnvironment('POSTHOG_DEV');

  bool _ready = false;

  /// Whether a [capture] or [reportError] right now would actually go
  /// somewhere. The uncaught-error hook needs to know: it may only tell the
  /// engine an error is handled when the report was really sent, or a debug
  /// run would swallow the crash it should be printing.
  bool get active => _ready;

  Future<void> init() async {
    if (!_enabled || _ready) return;
    try {
      final config = PostHogConfig(_projectToken)
        ..host = _host
        ..captureApplicationLifecycleEvents = true
        // Every event in this app is hand-placed: nothing automatic, no
        // screen views (no PostHogObserver is installed), no replay, no
        // surveys.
        ..sessionReplay = false
        ..surveys = false;
      await Posthog().setup(config);
      // Web ignores setup() - the posthog-js snippet in web/index.html is
      // what configures the client there - but capture() still routes
      // through it, so the flag flips on either platform.
      _ready = true;
    } catch (_) {
      // A failed analytics boot leaves the app running, silently untracked.
    }
  }

  void capture(String event, [Map<String, Object?>? properties]) {
    if (!_ready) return;
    _fireAndForget(() => Posthog().capture(
          eventName: event,
          properties: _withoutNulls(properties),
        ));
  }

  /// Feeds PostHog's error tracking product; the SDK builds the
  /// `$exception` event and its `$exception_list` from [error] and [stack].
  void reportError(Object error, StackTrace? stack) {
    if (!_ready) return;
    _fireAndForget(() => Posthog().captureException(
          error: error,
          stackTrace: stack,
        ));
  }

  /// Runs an SDK call for its side effect only, swallowing both a
  /// synchronous platform-channel throw and a rejected future.
  void _fireAndForget(Future<void> Function() call) {
    try {
      call().catchError((Object _) {});
    } catch (_) {
      // Nothing to do: analytics never reports its own failures.
    }
  }

  /// The SDK takes non-null values; callers get to pass properties that may
  /// legitimately be absent, and those simply do not travel.
  Map<String, Object>? _withoutNulls(Map<String, Object?>? properties) {
    if (properties == null) return null;
    return {
      for (final entry in properties.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }
}
