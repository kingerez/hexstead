import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// (coord, terrain, number, ownerId, level) - every tile owned and numbered,
/// so the frontier term is 0 and cannot tilt these fixtures.
typedef TileSpec = (Hex, TerrainType, int, int, int);

/// A board sitting at the activation choice, bot in seat 0.
GameState dicePhase(
  List<TileSpec> tilesSpec,
  (int, int) dice, {
  List<String> hand = const [],
  BotDifficulty difficulty = BotDifficulty.hard,
  int seed = 1,
  int round = 3,
  int? rngSeed,
}) =>
    GameState(
      seed: seed,
      rng: GameRng(rngSeed ?? seed),
      round: round,
      roundCap: 15,
      targetVp: 99,
      currentPlayerIndex: 0,
      phase: Phase.awaitingChoice,
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
          hand: hand,
        ),
        const PlayerState(id: 1, name: 'B', isBot: true),
      ],
      landmarkOffer: const [],
      lastDice: dice,
    );

void main() {
  group('SmartBot dice phase', () {
    test('declines an omen that buys nothing', () {
      // Sum 9 harvests the bot's village; no shift of either die reaches a
      // number anyone owns, so spending the card would be pure waste.
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.forest, 9, 0, 2),
        (Hex(2, 0), TerrainType.field, 11, 1, 1),
      ];
      final action =
          SmartBot.chooseAction(dicePhase(tiles, (4, 5), hand: ['omen']));
      expect(action, const ChooseActivation(ActivationMode.sum));
    });

    test('splits when the split feeds two hexes and the sum feeds none', () {
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.field, 3, 0, 1),
        (Hex(1, 0), TerrainType.forest, 5, 0, 1),
        (Hex(3, 0), TerrainType.hill, 11, 1, 1),
      ];
      expect(SmartBot.chooseAction(dicePhase(tiles, (3, 5))),
          const ChooseActivation(ActivationMode.split));
    });

    test('sums when the wealth sits on the sum', () {
      // Mirror of the split fixture: 3 and 5 are barren, 8 is a village.
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.mountain, 8, 0, 2),
        (Hex(3, 0), TerrainType.hill, 11, 1, 1),
      ];
      expect(SmartBot.chooseAction(dicePhase(tiles, (3, 5))),
          const ChooseActivation(ActivationMode.sum));
    });

    test('plays the omen that turns a blank roll into a harvest', () {
      // (5, 6) produces nothing either way; shifting the 5 up makes 12 and
      // wakes both villages for 4 wood.
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.forest, 12, 0, 2),
        (Hex(1, 0), TerrainType.forest, 12, 0, 2),
        (Hex(3, 0), TerrainType.hill, 2, 1, 1),
      ];
      final action =
          SmartBot.chooseAction(dicePhase(tiles, (5, 6), hand: ['omen']));
      expect(action, const PlayCard('omen', dieIndex: 0, delta: 1));
    });

    test('splits to deny a rival a fat sum payout', () {
      // The bot banks exactly one resource either way; the sum would also
      // hand the rival six.
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.field, 3, 0, 1),
        (Hex(1, 0), TerrainType.hill, 8, 0, 1),
        (Hex(3, 0), TerrainType.mountain, 8, 1, 2),
        (Hex(4, 0), TerrainType.mountain, 8, 1, 2),
        (Hex(5, 0), TerrainType.mountain, 8, 1, 2),
      ];
      expect(SmartBot.chooseAction(dicePhase(tiles, (3, 5))),
          const ChooseActivation(ActivationMode.split));
    });

    test('medium reads a big activation gap right nearly every time', () {
      // Split banks 8 resources, the sum banks none - far outside medium's
      // noise, so its mistakes stay occasional rather than constant.
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.field, 3, 0, 2),
        (Hex(1, 0), TerrainType.field, 3, 0, 2),
        (Hex(0, 1), TerrainType.forest, 5, 0, 2),
        (Hex(1, 1), TerrainType.forest, 5, 0, 2),
        (Hex(4, 0), TerrainType.hill, 11, 1, 1),
      ];
      var correct = 0;
      for (var seed = 0; seed < 10; seed++) {
        final action = SmartBot.chooseAction(dicePhase(tiles, (3, 5),
            difficulty: BotDifficulty.medium, seed: seed, round: 2 + seed));
        if (action == const ChooseActivation(ActivationMode.split)) correct++;
      }
      expect(correct, greaterThanOrEqualTo(9), reason: '$correct/10 correct');
    });

    test('never fumbles a one-resource activation gap, at any difficulty', () {
      // Sum 6 wakes the bot's hamlet for a single wood; the split (2 and 4)
      // feeds nobody. The gap is one eval point - the smallest real gap the
      // choice can have, and reading the dice is mechanical, so no
      // difficulty may misread it.
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.forest, 6, 0, 1),
        (Hex(3, 0), TerrainType.hill, 8, 1, 1),
      ];
      for (final difficulty in BotDifficulty.values) {
        for (var seed = 0; seed < 30; seed++) {
          for (var round = 1; round <= 10; round++) {
            expect(
                SmartBot.chooseAction(dicePhase(tiles, (2, 4),
                    difficulty: difficulty, seed: seed, round: round)),
                const ChooseActivation(ActivationMode.sum),
                reason: '$difficulty seed $seed round $round');
          }
        }
      }
    });

    test('second chance is judged on the average roll, not the real one', () {
      // Dice (2, 3): nothing answers 2, 3 or 5, while villages wait on 4, 6,
      // 8 and 9 - so the average reroll is worth more than the card.
      const tiles = <TileSpec>[
        (Hex(0, 0), TerrainType.forest, 6, 0, 2),
        (Hex(1, 0), TerrainType.forest, 6, 0, 2),
        (Hex(0, 1), TerrainType.field, 8, 0, 2),
        (Hex(1, 1), TerrainType.field, 8, 0, 2),
        (Hex(0, 2), TerrainType.hill, 9, 0, 2),
        (Hex(1, 2), TerrainType.mountain, 4, 0, 2),
        (Hex(4, 0), TerrainType.hill, 11, 1, 1),
      ];
      // Only the dice stream changes between these states, so a bot that
      // peeked at its own reroll would waver; this one must not.
      for (var rngSeed = 1; rngSeed < 8; rngSeed++) {
        expect(
            SmartBot.chooseAction(dicePhase(tiles, (2, 3),
                hand: ['second_chance'], rngSeed: rngSeed)),
            const PlayCard('second_chance'),
            reason: 'rng seed $rngSeed');
      }
    });
  });
}
