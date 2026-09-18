import 'dart:convert';

import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// Deterministic pseudo-random walk: picks the (step*31+seed)-th legal action.
/// Uses no wall-clock or dart:math randomness so failures reproduce exactly.
GameState _randomWalk(int seed, {int maxSteps = 5000}) {
  var s = GameState.newGame(seed: seed, players: [
    const PlayerSetup(name: 'P0', isBot: true),
    const PlayerSetup(name: 'P1', isBot: true),
    const PlayerSetup(name: 'P2', isBot: true),
  ]);
  for (var step = 0; step < maxSteps; step++) {
    if (s.phase == Phase.gameOver) return s;
    final actions = legalActions(s);
    expect(actions, isNotEmpty,
        reason: 'seed $seed step $step: no legal actions in ${s.phase}');
    final action = actions[(step * 31 + seed * 7) % actions.length];
    s = apply(s, action).state;

    for (final p in s.players) {
      for (final e in p.resources.entries) {
        expect(e.value, greaterThanOrEqualTo(0),
            reason: 'seed $seed step $step: negative ${e.key}');
      }
    }
    expect(s.tiles.length, 19, reason: 'seed $seed step $step');
  }
  fail('seed $seed: game did not terminate in $maxSteps steps');
}

void main() {
  test('random legal walks: no crashes, no negatives, always terminate', () {
    for (var seed = 0; seed < 120; seed++) {
      final end = _randomWalk(seed);
      expect(end.phase, Phase.gameOver);
      expect(end.winnerId, isNotNull);
      expect(end.round, lessThanOrEqualTo(end.roundCap));
    }
  });

  test('determinism golden: fixed seed and policy reach a known final state',
      () {
    final end = _randomWalk(424242);
    final digest = _fnv1a(jsonEncode(gameStateToJson(end)));
    final summary =
        '${end.round}/${end.winnerId}/${end.diceHistory.length}/$digest';
    // If a rules change legitimately alters this, re-record the value.
    expect(summary, '15/2/46/2913707569');
  });
}

int _fnv1a(String s) {
  var hash = 0x811C9DC5;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
