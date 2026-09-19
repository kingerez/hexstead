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

  group('progress', () {
    test('every objective reports a positive target and a short label', () {
      final s = board([(const Hex(0, 0), TerrainType.forest, 5, 0, 1)]);
      for (final o in objectiveCatalog.values) {
        final (current, target) = o.progress(s, 0);
        expect(target, greaterThan(0), reason: o.id);
        expect(current, greaterThanOrEqualTo(0), reason: o.id);
        expect(o.shortLabel, isNotEmpty, reason: o.id);
      }
    });

    test('sprawl progress tracks tiles changing hands', () {
      final spec = objectiveCatalog['sprawl']!;
      final spread = [
        for (var q = 0; q < 8; q++) (Hex(q, 0), TerrainType.forest, 5, 0, 1),
      ];
      expect(spec.progress(board(spread.sublist(0, 4)), 0), (4, 8));
      expect(spec.progress(board(spread.sublist(0, 4)), 1), (0, 8));
      // Hand two of them to p1: both sides move.
      final split = [
        for (final (i, t) in spread.indexed)
          (t.$1, t.$2, t.$3, i < 6 ? 0 : 1, t.$5),
      ];
      expect(spec.progress(board(split), 0), (6, 8));
      expect(spec.progress(board(split), 1), (2, 8));
      expect(spec.isComplete(board(spread), 0), isTrue);
      expect(spec.progress(board(spread), 0), (8, 8));
    });

    test('centrist progress flips with the center tile owner', () {
      final spec = objectiveCatalog['centrist']!;
      final mine = board([(const Hex(0, 0), TerrainType.desert, null, 0, 1)]);
      expect(spec.progress(mine, 0), (1, 1));
      expect(spec.progress(mine, 1), (0, 1));
      final unowned =
          board([(const Hex(0, 0), TerrainType.desert, null, null, 0)]);
      expect(spec.progress(unowned, 0), (0, 1));
    });

    test('straight_line progress counts the longest run, capped at 3', () {
      final spec = objectiveCatalog['straight_line']!;
      expect(
          spec.progress(
              board([(const Hex(0, 0), TerrainType.field, 5, 0, 1)]), 0),
          (1, 3));
      expect(
          spec.progress(
              board([
                (const Hex(0, 0), TerrainType.field, 5, 0, 1),
                (const Hex(0, 1), TerrainType.forest, 5, 0, 1),
              ]),
              0),
          (2, 3));
      expect(
          spec.progress(
              board([
                (const Hex(0, -1), TerrainType.field, 5, 0, 1),
                (const Hex(0, 0), TerrainType.forest, 5, 0, 1),
                (const Hex(0, 1), TerrainType.hill, 5, 0, 1),
                (const Hex(0, 2), TerrainType.hill, 5, 0, 1),
              ]),
              0),
          (3, 3));
    });

    test('isComplete agrees with progress across the catalog', () {
      final s = board([
        for (var q = 0; q < 4; q++) (Hex(q, 0), TerrainType.forest, 5, 0, 1),
      ]);
      for (final o in objectiveCatalog.values) {
        final (current, target) = o.progress(s, 0);
        expect(o.isComplete(s, 0), current >= target, reason: o.id);
      }
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
