import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

GameState board(List<(Hex, TerrainType, int?, int?, int)> spec,
    {int round = 15, int currentPlayerIndex = 1}) {
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: round,
    roundCap: 15,
    targetVp: 99,
    currentPlayerIndex: currentPlayerIndex,
    phase: Phase.main,
    tiles: {
      for (final (coord, terrain, number, owner, level) in spec)
        coord: Tile(
          coord: coord,
          terrain: terrain,
          number: number,
          ownerId: owner,
          level: level,
        ),
    },
    players: [
      const PlayerState(
          id: 0, name: 'You', isBot: false, objectiveId: 'forester'),
      const PlayerState(
          id: 1, name: 'Bot', isBot: true, objectiveId: 'mayor'),
    ],
    landmarkOffer: const [],
  );
}

void main() {
  group('objective catalog', () {
    test('has 8 objectives with progress functions and bonuses', () {
      expect(objectiveCatalog.length, 8);
      for (final o in objectiveCatalog.values) {
        expect(o.name, isNotEmpty);
        expect(o.bonusVp, greaterThan(0));
      }
    });
  });

  group('assignment', () {
    test('newGame gives each player a distinct objective', () {
      final s = GameState.newGame(seed: 5, players: [
        const PlayerSetup(name: 'a', isBot: true),
        const PlayerSetup(name: 'b', isBot: true),
        const PlayerSetup(name: 'c', isBot: true),
      ]);
      final ids = s.players.map((p) => p.objectiveId).toList();
      expect(ids.every((id) => objectiveCatalog.containsKey(id)), isTrue);
      expect(ids.toSet().length, 3);
    });
  });

  group('completion checks', () {
    test('forester: own 4+ forest tiles', () {
      final s = board([
        for (var q = 0; q < 4; q++)
          (Hex(q, 0), TerrainType.forest, 5, 0, 1),
      ]);
      expect(objectiveCatalog['forester']!.isComplete(s, 0), isTrue);
      expect(
          objectiveCatalog['forester']!
              .isComplete(board([(const Hex(0, 0), TerrainType.forest, 5, 0, 1)]), 0),
          isFalse);
    });

    test('mayor: own 3+ villages', () {
      final s = board([
        for (var q = 0; q < 3; q++)
          (Hex(q, 0), TerrainType.field, 5, 1, 2),
      ]);
      expect(objectiveCatalog['mayor']!.isComplete(s, 1), isTrue);
    });

    test('straight_line: 3 collinear owned tiles', () {
      final line = board([
        (const Hex(0, -1), TerrainType.field, 5, 0, 1),
        (const Hex(0, 0), TerrainType.forest, 5, 0, 1),
        (const Hex(0, 1), TerrainType.hill, 5, 0, 1),
      ]);
      expect(objectiveCatalog['straight_line']!.isComplete(line, 0), isTrue);
      final bent = board([
        (const Hex(0, 0), TerrainType.field, 5, 0, 1),
        (const Hex(1, 0), TerrainType.forest, 5, 0, 1),
        (const Hex(1, 1), TerrainType.hill, 5, 0, 1),
      ]);
      expect(objectiveCatalog['straight_line']!.isComplete(bent, 0), isFalse);
    });

    test('centrist: own the center tile', () {
      final s = board([(const Hex(0, 0), TerrainType.desert, null, 0, 1)]);
      expect(objectiveCatalog['centrist']!.isComplete(s, 0), isTrue);
      expect(objectiveCatalog['centrist']!.isComplete(s, 1), isFalse);
    });
  });

  group('endgame integration', () {
    test('completed objectives add their bonus to final scores', () {
      // p0 has 4 forests (forester complete, +4); p1 has 2 camps (mayor not)
      final s = board(
        [
          for (var q = 0; q < 4; q++) (Hex(q, 0), TerrainType.forest, 5, 0, 1),
          (const Hex(0, 1), TerrainType.field, 5, 1, 1),
          (const Hex(0, 2), TerrainType.hill, 5, 1, 1),
        ],
        round: 15,
        currentPlayerIndex: 1,
      );
      final r = apply(s, const EndTurn());
      final ended = r.events.whereType<GameEnded>().single;
      // p0 territory: one 4-forest region = 4, + forester bonus 4 = 8
      expect(ended.finalScores[0], 8);
      // p1: two lone camps = 2, no bonus
      expect(ended.finalScores[1], 2);
      expect(r.state.winnerId, 0);
    });

    test('objective bonus does not count toward instant VP win', () {
      final s = board(
        [
          for (var q = 0; q < 4; q++) (Hex(q, 0), TerrainType.forest, 5, 0, 1),
        ],
        round: 1,
        currentPlayerIndex: 0,
      );
      // live score is 4 (region), objective would add 4 more, target is 99
      expect(scoreFor(s, 0), 4);
    });

    test('finalScoreFor = live score + objective bonus', () {
      final s = board([
        for (var q = 0; q < 4; q++) (Hex(q, 0), TerrainType.forest, 5, 0, 1),
      ]);
      expect(finalScoreFor(s, 0), 8);
      expect(finalScoreFor(s, 1), 0);
    });
  });
}
