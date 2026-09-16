import 'dart:convert';

import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

GameState _newGame(int seed) => GameState.newGame(seed: seed, players: [
      const PlayerSetup(name: 'You', isBot: false),
      const PlayerSetup(name: 'A', isBot: true, difficulty: BotDifficulty.hard),
      const PlayerSetup(name: 'B', isBot: true),
    ]);

/// Drives [state] with the first legal action [steps] times (deterministic).
GameState _walk(GameState state, int steps) {
  var s = state;
  for (var i = 0; i < steps && s.phase != Phase.gameOver; i++) {
    s = apply(s, legalActions(s).first).state;
  }
  return s;
}

void main() {
  group('serialization', () {
    test('fresh game round-trips through JSON', () {
      final s = _newGame(11);
      final restored = gameStateFromJson(gameStateToJson(s));
      expect(gameStateToJson(restored), gameStateToJson(s));
    });

    test('mid-game states round-trip across many seeds and depths', () {
      for (var seed = 0; seed < 10; seed++) {
        for (final depth in [1, 5, 20, 60]) {
          final s = _walk(_newGame(seed), depth);
          final restored = gameStateFromJson(gameStateToJson(s));
          expect(gameStateToJson(restored), gameStateToJson(s),
              reason: 'seed $seed depth $depth phase ${s.phase}');
        }
      }
    });

    test('JSON is actually a string-encodable document', () {
      final s = _walk(_newGame(3), 10);
      final text = jsonEncode(gameStateToJson(s));
      final restored = gameStateFromJson(
          jsonDecode(text) as Map<String, dynamic>);
      expect(gameStateToJson(restored), gameStateToJson(s));
    });

    test('a resumed game continues the exact same dice sequence', () {
      final s = _walk(_newGame(21), 7);
      final restored = gameStateFromJson(gameStateToJson(s));
      var a = s;
      var b = restored;
      for (var i = 0; i < 30 && a.phase != Phase.gameOver; i++) {
        a = apply(a, legalActions(a).first).state;
        b = apply(b, legalActions(b).first).state;
      }
      expect(gameStateToJson(b), gameStateToJson(a));
      expect(b.diceHistory, a.diceHistory);
    });

    test('restored tiles keep bandit and block markers', () {
      var s = _newGame(2);
      final owned =
          s.tiles.values.firstWhere((t) => t.ownerId != null).coord;
      s = s.copyWith(tiles: {
        ...s.tiles,
        owned: s.tiles[owned]!
            .copyWith(hasBandit: true, blockedUntilRound: () => 4),
      });
      final restored = gameStateFromJson(gameStateToJson(s));
      expect(restored.tiles[owned]!.hasBandit, isTrue);
      expect(restored.tiles[owned]!.blockedUntilRound, 4);
    });
  });
}
