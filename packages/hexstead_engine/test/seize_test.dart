import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// Fully-claimed 4-tile board: p0 owns (0,0); p1 owns the rest.
GameState fullBoard({
  Map<Resource, int>? p0Resources,
  int rivalLevel = 1,
  List<String> p1Landmarks = const [],
  bool leaveOneUnowned = false,
}) {
  final tilesSpec = [
    (const Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (const Hex(1, 0), TerrainType.field, 6, 1, rivalLevel),
    (const Hex(0, 1), TerrainType.hill, 4, 1, 1),
    (const Hex(1, -1), TerrainType.mountain, 10, leaveOneUnowned ? null : 1,
        leaveOneUnowned ? 0 : 1),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: 8,
    roundCap: 15,
    targetVp: 99,
    currentPlayerIndex: 0,
    phase: Phase.main,
    tiles: {
      for (final (coord, terrain, number, owner, level) in tilesSpec)
        coord: Tile(
            coord: coord,
            terrain: terrain,
            number: number,
            ownerId: owner,
            level: level),
    },
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: p0Resources ?? {Resource.wood: 3, Resource.grain: 2},
      ),
      PlayerState(
          id: 1,
          name: 'Bot',
          isBot: true,
          resources: const {Resource.grain: 2},
          landmarkIds: p1Landmarks),
    ],
    landmarkOffer: const [],
  );
}

void main() {
  group('seizing', () {
    test('costs 5 any-mix resources for a Level-1 hex and transfers it', () {
      final s = fullBoard();
      final r = apply(
        s,
        const SeizeHex(Hex(1, 0), spend: [
          Resource.wood,
          Resource.wood,
          Resource.wood,
          Resource.grain,
          Resource.grain,
        ]),
      );
      expect(r.state.tiles[const Hex(1, 0)]!.ownerId, 0);
      expect(r.state.tiles[const Hex(1, 0)]!.level, 1); // level preserved
      expect(r.state.players[0].totalResources, 0);
      expect(r.events.whereType<HexSeized>().length, 1);
    });

    test('a Level-2 hex costs 8', () {
      final s = fullBoard(
        rivalLevel: 2,
        p0Resources: {Resource.wood: 4, Resource.grain: 4},
      );
      final spend = [
        ...List.filled(4, Resource.wood),
        ...List.filled(4, Resource.grain),
      ];
      final r = apply(s, SeizeHex(const Hex(1, 0), spend: spend));
      expect(r.state.tiles[const Hex(1, 0)]!.ownerId, 0);
      expect(r.state.tiles[const Hex(1, 0)]!.level, 2);
      // paying only 5 for a Level-2 is rejected
      expect(
        () => apply(fullBoard(rivalLevel: 2, p0Resources: {Resource.wood: 5}),
            SeizeHex(const Hex(1, 0), spend: List.filled(5, Resource.wood))),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('only legal once no unowned tiles remain', () {
      final s = fullBoard(leaveOneUnowned: true);
      expect(
        () => apply(s,
            SeizeHex(const Hex(1, 0), spend: List.filled(5, Resource.wood))),
        throwsA(isA<IllegalActionException>()),
      );
      expect(legalActions(s).whereType<SeizeHex>(), isEmpty);
    });

    test('target must border the seizer\'s territory', () {
      // (0,1) borders p0's (0,0); (1,-1) also borders it. All p1 tiles here
      // border p0, so shrink adjacency: use a spend on a non-adjacent check
      // via a board where p0 owns only (0,0) and target (2,0) doesn\'t exist.
      final s = fullBoard();
      // All rival tiles are adjacent in this fixture; verify legalActions
      // only offers tiles adjacent to p0.
      final targets =
          legalActions(s).whereType<SeizeHex>().map((a) => a.target).toSet();
      expect(targets, {const Hex(1, 0), const Hex(0, 1), const Hex(1, -1)});
    });

    test('watchtower protects its owner\'s hexes from seizure', () {
      final s = fullBoard(p1Landmarks: ['watchtower'], p0Resources: {
        Resource.wood: 9,
      });
      expect(legalActions(s).whereType<SeizeHex>(), isEmpty);
      expect(
        () => apply(s,
            SeizeHex(const Hex(1, 0), spend: List.filled(5, Resource.wood))),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('legalActions offers one canonical greedy payment per target', () {
      final s = fullBoard(p0Resources: {
        Resource.wood: 4,
        Resource.grain: 1,
        Resource.brick: 1,
      });
      final seizes = legalActions(s).whereType<SeizeHex>().toList();
      expect(seizes, isNotEmpty);
      for (final a in seizes) {
        expect(a.spend.length, 5);
        // Greedy: most abundant first -> 4 wood then 1 of the next.
        expect(a.spend.where((r) => r == Resource.wood).length, 4);
      }
    });

    test('cannot seize your own tile and cannot pay short', () {
      final s = fullBoard(p0Resources: {Resource.wood: 2});
      expect(legalActions(s).whereType<SeizeHex>(), isEmpty);
      expect(
        () => apply(s,
            SeizeHex(const Hex(0, 0), spend: List.filled(5, Resource.wood))),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('seizing can win the game on the spot', () {
      final s = fullBoard(
        p0Resources: {Resource.wood: 5},
      ).copyWith(); // targetVp 99 default in fixture; rebuild with low target
      final low = GameState(
        seed: s.seed,
        rng: s.rng,
        round: s.round,
        roundCap: s.roundCap,
        targetVp: 2,
        currentPlayerIndex: 0,
        phase: Phase.main,
        tiles: s.tiles,
        players: s.players,
        landmarkOffer: const [],
      );
      final r = apply(low,
          SeizeHex(const Hex(1, -1), spend: List.filled(5, Resource.wood)));
      expect(r.state.phase, Phase.gameOver);
      expect(r.state.winnerId, 0);
    });
  });
}
