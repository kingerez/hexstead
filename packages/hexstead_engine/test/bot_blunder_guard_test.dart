import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// (coord, terrain, number, ownerId, level) - every tile owned and numbered,
/// so the frontier term is 0 and cannot tilt these fixtures.
typedef TileSpec = (Hex, TerrainType, int, int, int);

/// A board in the main phase, bot in seat 0 holding exactly one upgrade's
/// worth of resources - so the only real choices are which tile to raise.
GameState mainPhase(
  List<TileSpec> tilesSpec, {
  BotDifficulty difficulty = BotDifficulty.medium,
  int seed = 1,
  int round = 3,
  int roundCap = 20,
}) =>
    GameState(
      seed: seed,
      rng: GameRng(seed),
      round: round,
      roundCap: roundCap,
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
          name: 'A',
          isBot: true,
          difficulty: difficulty,
          resources: const {Resource.grain: 2, Resource.stone: 1},
        ),
        const PlayerState(id: 1, name: 'B', isBot: true),
      ],
      landmarkOffer: const [],
    );

void main() {
  group('SmartBot blunder guard', () {
    // Both tiles sit in one forest region, so upgrading either scores the
    // same points; only the pips differ. A 7 pays five times what a 2 does,
    // which over 18 remaining rounds is ~5 eval points - twice medium's
    // margin, so a Fair bot must never raise the barren tile.
    const lopsided = <TileSpec>[
      (Hex(0, 0), TerrainType.forest, 7, 0, 1),
      (Hex(1, 0), TerrainType.forest, 2, 0, 1),
      (Hex(4, 0), TerrainType.hill, 11, 1, 1),
    ];

    test('medium never takes a clearly losing main-phase action', () {
      for (var seed = 0; seed < 30; seed++) {
        for (var round = 1; round <= 10; round++) {
          expect(
              SmartBot.chooseAction(
                  mainPhase(lopsided, seed: seed, round: round)),
              isNot(const UpgradeHex(Hex(1, 0))),
              reason: 'seed $seed round $round');
        }
      }
    });

    test('near-ties are still settled by noise, not by list order', () {
      // 6 and 8 carry the same five pips, so the two upgrades are worth
      // exactly the same; inside the margin noise must still decide.
      const tied = <TileSpec>[
        (Hex(0, 0), TerrainType.forest, 6, 0, 1),
        (Hex(1, 0), TerrainType.forest, 8, 0, 1),
        (Hex(4, 0), TerrainType.hill, 11, 1, 1),
      ];
      final chosen = <GameAction>{};
      for (var seed = 0; seed < 30; seed++) {
        for (var round = 1; round <= 10; round++) {
          chosen.add(SmartBot.chooseAction(
              mainPhase(tied, seed: seed, round: round)));
        }
      }
      expect(chosen,
          containsAll(const [UpgradeHex(Hex(0, 0)), UpgradeHex(Hex(1, 0))]));
    });
  });
}
