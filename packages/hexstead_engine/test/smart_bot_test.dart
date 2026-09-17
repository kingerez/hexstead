import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

GameState game(int seed,
        {BotDifficulty a = BotDifficulty.hard,
        BotDifficulty b = BotDifficulty.hard}) =>
    GameState.newGame(seed: seed, players: [
      PlayerSetup(name: 'A', isBot: true, difficulty: a),
      PlayerSetup(name: 'B', isBot: true, difficulty: b),
    ]);

/// Plays a full game with SmartBot for every decision; returns final state.
GameState playOut(GameState s, {int maxSteps = 4000}) {
  var state = s;
  var steps = 0;
  while (state.phase != Phase.gameOver) {
    state = apply(state, SmartBot.chooseAction(state)).state;
    if (++steps > maxSteps) fail('game did not terminate');
  }
  return state;
}

void main() {
  group('SmartBot', () {
    test('always returns a legal action across many seeds', () {
      for (var seed = 0; seed < 15; seed++) {
        var s = game(seed);
        for (var i = 0; i < 300 && s.phase != Phase.gameOver; i++) {
          final action = SmartBot.chooseAction(s);
          expect(legalActions(s), contains(action),
              reason: 'seed $seed step $i phase ${s.phase}');
          s = apply(s, action).state;
        }
      }
    });

    test('is deterministic for a given state', () {
      final s = game(3);
      final first = SmartBot.chooseAction(s);
      for (var i = 0; i < 5; i++) {
        expect(SmartBot.chooseAction(game(3)), first);
      }
    });

    test('completes full games', () {
      for (var seed = 0; seed < 10; seed++) {
        final end = playOut(game(seed));
        expect(end.winnerId, isNotNull);
      }
    });

    test('claims a clearly better tile over a worse one', () {
      // Territory with two claimable neighbors: a 6-pip tile vs a 2-pip tile.
      // The bot should take the 6.
      const tilesSpec = [
        (Hex(0, 0), TerrainType.forest, 5, 0, 1),
        (Hex(1, 0), TerrainType.field, 6, null, 0),
        (Hex(0, 1), TerrainType.field, 2, null, 0),
        (Hex(-2, 0), TerrainType.hill, 9, 1, 1),
      ];
      final s = GameState(
        seed: 1,
        rng: GameRng(1),
        round: 3,
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
          const PlayerState(
            id: 0,
            name: 'A',
            isBot: true,
            difficulty: BotDifficulty.hard,
            resources: {Resource.wood: 1, Resource.brick: 1},
          ),
          const PlayerState(id: 1, name: 'B', isBot: true),
        ],
        landmarkOffer: const [],
      );
      expect(SmartBot.chooseAction(s), const ClaimHex(Hex(1, 0)));
    });


    test('places the bandit where it hurts a rival, never on the desert', () {
      const tilesSpec = [
        // Rival's strong tile: forest #8 village.
        (Hex(0, 0), TerrainType.forest, 8, 1, 2),
        // Rival-owned desert: blocking it achieves nothing.
        (Hex(1, 0), TerrainType.desert, null, 1, 1),
        // Rival's weak tile.
        (Hex(0, 1), TerrainType.field, 2, 1, 1),
        // Bot's own tile - blocking yourself would be absurd.
        (Hex(1, -1), TerrainType.mountain, 6, 0, 1),
      ];
      final s = GameState(
        seed: 1,
        rng: GameRng(1),
        round: 3,
        roundCap: 15,
        targetVp: 99,
        currentPlayerIndex: 0,
        phase: Phase.awaitingBandit,
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
          const PlayerState(
              id: 0,
              name: 'A',
              isBot: true,
              difficulty: BotDifficulty.hard),
          const PlayerState(id: 1, name: 'B', isBot: true),
        ],
        landmarkOffer: const [],
        lastDice: (3, 4),
      );
      expect(SmartBot.chooseAction(s), const PlaceBandit(Hex(0, 0)));
    });
    test('hard beats easy convincingly over many games', () {
      var hardWins = 0;
      const games = 40;
      for (var seed = 0; seed < games; seed++) {
        // Alternate seats so seat advantage cancels out.
        final hardSeat = seed % 2;
        final end = playOut(GameState.newGame(seed: seed, players: [
          PlayerSetup(
              name: 'S0',
              isBot: true,
              difficulty:
                  hardSeat == 0 ? BotDifficulty.hard : BotDifficulty.easy),
          PlayerSetup(
              name: 'S1',
              isBot: true,
              difficulty:
                  hardSeat == 1 ? BotDifficulty.hard : BotDifficulty.easy),
        ]));
        final scores = [
          finalScoreFor(end, 0),
          finalScoreFor(end, 1),
        ];
        final hardWon = scores[hardSeat] > scores[1 - hardSeat] ||
            (scores[hardSeat] == scores[1 - hardSeat] &&
                end.winnerId == hardSeat);
        if (hardWon) hardWins++;
      }
      expect(hardWins / games, greaterThan(0.6),
          reason: 'hard won $hardWins/$games');
    });
  });
}
