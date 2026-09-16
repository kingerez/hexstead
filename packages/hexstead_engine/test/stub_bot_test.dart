import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

GameState _botsOnly(int seed) => GameState.newGame(seed: seed, players: [
      const PlayerSetup(name: 'A', isBot: true),
      const PlayerSetup(name: 'B', isBot: true),
    ]);

void main() {
  group('StubBot', () {
    test('always returns a legal action', () {
      var s = _botsOnly(1);
      for (var i = 0; i < 500 && s.phase != Phase.gameOver; i++) {
        final action = StubBot.chooseAction(s);
        expect(legalActions(s), contains(action),
            reason: 'step $i phase ${s.phase}');
        s = apply(s, action).state;
      }
    });

    test('drives full games to completion on many seeds', () {
      for (var seed = 0; seed < 30; seed++) {
        var s = _botsOnly(seed);
        var steps = 0;
        while (s.phase != Phase.gameOver) {
          s = apply(s, StubBot.chooseAction(s)).state;
          expect(++steps, lessThan(3000), reason: 'seed $seed stuck');
        }
        expect(s.winnerId, isNotNull);
      }
    });

    test('expands territory instead of hoarding', () {
      var s = _botsOnly(7);
      while (s.phase != Phase.gameOver) {
        s = apply(s, StubBot.chooseAction(s)).state;
      }
      final claimed =
          s.tiles.values.where((t) => t.ownerId != null).length;
      expect(claimed, greaterThan(2)); // more than the 2 starting camps
    });
  });
}
