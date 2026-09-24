import 'package:flutter_test/flutter_test.dart';
import 'package:hexstead/observability/analytics.dart';

void main() {
  // The whole suite leans on this: no test ever calls init(), so every
  // capture the game makes along the way has to be a silent no-op rather
  // than a throw - and above all, never a network call.
  test('capture and reportError are silent no-ops before init', () {
    final analytics = Analytics.instance;

    // What main.dart's uncaught-error hook reads to decide whether the
    // engine still has to print the error itself.
    expect(analytics.active, isFalse);
    expect(() => analytics.capture('game_started'), returnsNormally);
    expect(
      () => analytics.capture('game_finished', {'round': 7, 'human_won': true}),
      returnsNormally,
    );
    expect(
      () => analytics.reportError(StateError('boom'), StackTrace.current),
      returnsNormally,
    );
    expect(() => analytics.reportError('plain string', null), returnsNormally);
  });
}
