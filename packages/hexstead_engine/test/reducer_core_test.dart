import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// Hand-built 4-tile board for precise production tests:
///   (0,0) forest #8  owned p0 camp
///   (1,0) field  #8  owned p1 village
///   (0,1) hill   #4  owned p0 camp
///   (1,-1) mountain #6 unowned
GameState fixtureState({
  Phase phase = Phase.main,
  (int, int)? lastDice,
  int currentPlayerIndex = 0,
  Map<Resource, int>? p0Resources,
  int round = 1,
  int roundCap = 15,
  int targetVp = 25,
}) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (Hex(1, 0), TerrainType.field, 8, 1, 2),
    (Hex(0, 1), TerrainType.hill, 4, 0, 1),
    (Hex(1, -1), TerrainType.mountain, 6, null, 0),
  ];
  final tiles = {
    for (final (coord, terrain, number, owner, level) in tilesSpec)
      coord: Tile(
        coord: coord,
        terrain: terrain,
        number: number,
        ownerId: owner,
        level: level,
      ),
  };
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: round,
    roundCap: roundCap,
    targetVp: targetVp,
    currentPlayerIndex: currentPlayerIndex,
    phase: phase,
    tiles: tiles,
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: p0Resources ?? {Resource.wood: 3, Resource.brick: 3},
      ),
      PlayerState(id: 1, name: 'Bot', isBot: true, resources: const {}),
    ],
    landmarkOffer: const [],
    lastDice: lastDice,
  );
}

void main() {
  group('newGame setup', () {
    test('each player starts with one numbered camp and claim resources', () {
      final s = GameState.newGame(
        seed: 5,
        players: [
          const PlayerSetup(name: 'You', isBot: false),
          const PlayerSetup(name: 'A', isBot: true),
          const PlayerSetup(name: 'B', isBot: true),
        ],
      );
      expect(s.players.length, 3);
      expect(s.phase, Phase.awaitingRoll);
      expect(s.round, 1);
      expect(s.currentPlayerIndex, 0);
      for (final p in s.players) {
        final owned = s.tiles.values.where((t) => t.ownerId == p.id).toList();
        expect(owned.length, 1);
        expect(owned.single.level, 1);
        expect(owned.single.number, isNotNull);
        // Base stake plus seat compensation for going later.
        expect(p.resources, {
          Resource.wood: 2,
          Resource.brick: 2,
          if (p.id >= 1) Resource.grain: 1,
          if (p.id >= 3) Resource.wood: 3,
        });
      }
    });

    test('starting camps are spread at least 2 hexes apart', () {
      for (var seed = 0; seed < 20; seed++) {
        final s = GameState.newGame(
          seed: seed,
          players: [
            const PlayerSetup(name: 'You', isBot: false),
            const PlayerSetup(name: 'A', isBot: true),
            const PlayerSetup(name: 'B', isBot: true),
          ],
        );
        final camps = s.tiles.values
            .where((t) => t.ownerId != null)
            .map((t) => t.coord)
            .toList();
        for (var i = 0; i < camps.length; i++) {
          for (var j = i + 1; j < camps.length; j++) {
            expect(camps[i].distanceTo(camps[j]), greaterThanOrEqualTo(2),
                reason: 'seed $seed');
          }
        }
      }
    });

    test('same seed reproduces identical setup', () {
      GameState make() => GameState.newGame(seed: 9, players: [
            const PlayerSetup(name: 'You', isBot: false),
            const PlayerSetup(name: 'A', isBot: true),
          ]);
      final a = make();
      final b = make();
      expect(
        a.tiles.map((k, v) => MapEntry(k, '${v.terrain}/${v.number}/${v.ownerId}')),
        b.tiles.map((k, v) => MapEntry(k, '${v.terrain}/${v.number}/${v.ownerId}')),
      );
    });
  });

  group('rolling', () {
    test('RollDice moves to activation choice and records dice', () {
      final s0 = fixtureState(phase: Phase.awaitingRoll);
      final r = apply(s0, const RollDice());
      expect(r.state.phase, Phase.awaitingChoice);
      expect(r.state.lastDice, isNotNull);
      final (d1, d2) = r.state.lastDice!;
      expect(d1, inInclusiveRange(1, 6));
      expect(d2, inInclusiveRange(1, 6));
      expect(r.state.diceHistory.last, (d1, d2));
      expect(r.events.whereType<DiceRolled>().length, 1);
    });

    test('RollDice is illegal outside awaitingRoll', () {
      expect(() => apply(fixtureState(phase: Phase.main), const RollDice()),
          throwsA(isA<IllegalActionException>()));
    });
  });

  group('activation and production', () {
    test('sum activates matching tiles; villages produce double; all owners collect', () {
      final s0 = fixtureState(phase: Phase.awaitingChoice, lastDice: (4, 4));
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      // sum=8: p0 forest camp -> +1 wood; p1 field village -> +2 grain
      expect(r.state.players[0].resources[Resource.wood], 4);
      expect(r.state.players[1].resources[Resource.grain], 2);
      expect(r.state.phase, Phase.main);
      expect(r.events.whereType<ResourcesProduced>().length, 1);
    });

    test('split activates each die number separately', () {
      final s0 = fixtureState(phase: Phase.awaitingChoice, lastDice: (4, 6));
      final r = apply(s0, const ChooseActivation(ActivationMode.split));
      // 4 -> p0 hill camp +1 brick; 6 -> unowned mountain, nothing
      expect(r.state.players[0].resources[Resource.brick], 4);
      expect(r.state.players[0].resources[Resource.wood], 3);
      expect(r.state.players[1].resources[Resource.grain], isNull);
    });

    test('split doubles produce twice', () {
      final s0 = fixtureState(phase: Phase.awaitingChoice, lastDice: (4, 4));
      final r = apply(s0, const ChooseActivation(ActivationMode.split));
      expect(r.state.players[0].resources[Resource.brick], 5); // 3 + 2
    });

    test('sum of 7 leads to bandit placement instead of production', () {
      final s0 = fixtureState(phase: Phase.awaitingChoice, lastDice: (3, 4));
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      expect(r.state.phase, Phase.awaitingBandit);
      expect(r.events.whereType<NothingProduced>().length, 1);
      // but split remains available as the alternative choice
      final r2 = apply(s0, const ChooseActivation(ActivationMode.split));
      expect(r2.state.phase, Phase.main);
      expect(r2.state.players[0].resources[Resource.brick], 4); // die 4 -> hill
    });
  });

  group('bandit', () {
    test('placement targets an owned tile, moves any previous bandit', () {
      final s0 = fixtureState(phase: Phase.awaitingBandit);
      final r = apply(s0, const PlaceBandit(Hex(1, 0)));
      expect(r.state.tiles[const Hex(1, 0)]!.hasBandit, isTrue);
      expect(r.state.phase, Phase.main);

      // move it elsewhere on a later 7: old spot clears
      final s1 = r.state.copyWith(phase: Phase.awaitingBandit);
      final r2 = apply(s1, const PlaceBandit(Hex(0, 0)));
      expect(r2.state.tiles[const Hex(1, 0)]!.hasBandit, isFalse);
      expect(r2.state.tiles[const Hex(0, 0)]!.hasBandit, isTrue);
    });

    test('placement on unowned tile is illegal', () {
      final s0 = fixtureState(phase: Phase.awaitingBandit);
      expect(() => apply(s0, const PlaceBandit(Hex(1, -1))),
          throwsA(isA<IllegalActionException>()));
    });

    test('bandit-hosting tile does not produce', () {
      var s0 = fixtureState(phase: Phase.awaitingChoice, lastDice: (4, 4));
      s0 = s0.copyWith(tiles: {
        ...s0.tiles,
        const Hex(1, 0): s0.tiles[const Hex(1, 0)]!.copyWith(hasBandit: true),
      });
      final r = apply(s0, const ChooseActivation(ActivationMode.sum));
      expect(r.state.players[1].resources[Resource.grain], isNull);
      expect(r.state.players[0].resources[Resource.wood], 4); // unaffected
    });

    test('owner pays any 2 resources to remove the bandit on their turn', () {
      var s0 = fixtureState(phase: Phase.main);
      s0 = s0.copyWith(tiles: {
        ...s0.tiles,
        const Hex(0, 0): s0.tiles[const Hex(0, 0)]!.copyWith(hasBandit: true),
      });
      final r = apply(
          s0, const RemoveBandit(spend: [Resource.wood, Resource.brick]));
      expect(r.state.tiles[const Hex(0, 0)]!.hasBandit, isFalse);
      expect(r.state.players[0].resources[Resource.wood], 2);
      expect(r.state.players[0].resources[Resource.brick], 2);
    });

    test('cannot remove a bandit from an opponent tile', () {
      var s0 = fixtureState(phase: Phase.main);
      s0 = s0.copyWith(tiles: {
        ...s0.tiles,
        const Hex(1, 0): s0.tiles[const Hex(1, 0)]!.copyWith(hasBandit: true),
      });
      expect(
          () => apply(
              s0, const RemoveBandit(spend: [Resource.wood, Resource.brick])),
          throwsA(isA<IllegalActionException>()));
    });
  });

  group('claiming and upgrading', () {
    test('claim adjacent unowned tile costs 1 wood + 1 brick', () {
      final s0 = fixtureState();
      // (1,-1) is adjacent to p0's (0,0)
      final r = apply(s0, const ClaimHex(Hex(1, -1)));
      final tile = r.state.tiles[const Hex(1, -1)]!;
      expect(tile.ownerId, 0);
      expect(tile.level, 1);
      expect(r.state.players[0].resources[Resource.wood], 2);
      expect(r.state.players[0].resources[Resource.brick], 2);
    });

    test('claim requires adjacency, vacancy, and funds', () {
      final s0 = fixtureState();
      // owned by p1
      expect(() => apply(s0, const ClaimHex(Hex(1, 0))),
          throwsA(isA<IllegalActionException>()));
      // not adjacent to p0 territory (far ring)
      expect(() => apply(s0, const ClaimHex(Hex(-2, 0))),
          throwsA(isA<IllegalActionException>()));
      // broke
      final broke = fixtureState(p0Resources: {Resource.wood: 1});
      expect(() => apply(broke, const ClaimHex(Hex(1, -1))),
          throwsA(isA<IllegalActionException>()));
    });

    test('upgrade own camp to village costs 2 grain + 1 stone', () {
      final s0 = fixtureState(p0Resources: {
        Resource.grain: 2,
        Resource.stone: 1,
      });
      final r = apply(s0, const UpgradeHex(Hex(0, 0)));
      expect(r.state.tiles[const Hex(0, 0)]!.level, 2);
      expect(r.state.players[0].resources[Resource.grain], 0);
      expect(r.state.players[0].resources[Resource.stone], 0);
    });

    test('cannot upgrade opponent tiles or villages', () {
      final rich = fixtureState(p0Resources: {
        Resource.grain: 9,
        Resource.stone: 9,
      });
      expect(() => apply(rich, const UpgradeHex(Hex(1, 0))),
          throwsA(isA<IllegalActionException>()));
      final upgraded = apply(rich, const UpgradeHex(Hex(0, 0))).state;
      expect(() => apply(upgraded, const UpgradeHex(Hex(0, 0))),
          throwsA(isA<IllegalActionException>()));
    });
  });

  group('bank trade', () {
    test('3:1 exchange', () {
      final s0 = fixtureState(p0Resources: {Resource.wood: 3});
      final r = apply(
          s0, const BankTrade(give: Resource.wood, get: Resource.stone));
      expect(r.state.players[0].resources[Resource.wood], 0);
      expect(r.state.players[0].resources[Resource.stone], 1);
    });

    test('needs 3 of the given resource', () {
      final s0 = fixtureState(p0Resources: {Resource.wood: 2});
      expect(
          () => apply(
              s0, const BankTrade(give: Resource.wood, get: Resource.stone)),
          throwsA(isA<IllegalActionException>()));
    });
  });

  group('turns, rounds, and endings', () {
    test('EndTurn advances player; wraps and increments round', () {
      final s0 = fixtureState();
      final r = apply(s0, const EndTurn());
      expect(r.state.currentPlayerIndex, 1);
      expect(r.state.round, 1);
      expect(r.state.phase, Phase.awaitingRoll);
      final r2 = apply(r.state.copyWith(phase: Phase.main), const EndTurn());
      expect(r2.state.currentPlayerIndex, 0);
      expect(r2.state.round, 2);
      expect(r2.events.whereType<RoundAdvanced>().length, 1);
    });

    test('game ends after last player of the cap round', () {
      final s0 = fixtureState(round: 15, currentPlayerIndex: 1);
      final r = apply(s0, const EndTurn());
      expect(r.state.phase, Phase.gameOver);
      // p1 has a 2-hex... no: p1 owns 1 village (1x2=2), p0 owns 2 camps in
      // separate regions (forest 1x1 + hill 1x1 = 2). Tie -> lowest seat.
      expect(r.state.winnerId, 0);
      expect(r.events.whereType<GameEnded>().length, 1);
    });

    test('reaching target VP ends the game immediately', () {
      final s0 = fixtureState(targetVp: 3);
      final r = apply(s0, const ClaimHex(Hex(1, -1)));
      // p0 now: forest 1x1 + hill 1x1 + mountain 1x1 = 3 >= 3
      expect(r.state.phase, Phase.gameOver);
      expect(r.state.winnerId, 0);
    });
  });

  group('scoring', () {
    test('connected same-terrain region scores size x (1 + villages)', () {
      // build: p0 owns 3 connected forests, one is a village
      const coords = [Hex(0, 0), Hex(1, 0), Hex(2, 0)];
      final tiles = {
        for (final (i, c) in coords.indexed)
          c: Tile(
            coord: c,
            terrain: TerrainType.forest,
            number: 5,
            ownerId: 0,
            level: i == 0 ? 2 : 1,
          ),
        const Hex(0, 2): const Tile(
          coord: Hex(0, 2),
          terrain: TerrainType.forest,
          number: 9,
          ownerId: 0,
          level: 1,
        ),
      };
      final s = fixtureState().copyWith(tiles: tiles);
      // region of 3 with 1 village: 3 x 2 = 6; lone forest: 1 x 1 = 1
      expect(scoreFor(s, 0), 7);
    });

    test('different terrains never merge into one region', () {
      final s = fixtureState();
      // p0: forest camp (1) + hill camp (1), adjacent but distinct terrain
      expect(scoreFor(s, 0), 2);
      expect(scoreFor(s, 1), 2); // village alone: 1 x 2
    });
  });

  group('legal moves', () {
    test('awaitingRoll offers RollDice plus bank actions (trade, landmarks)',
        () {
      final s = fixtureState(phase: Phase.awaitingRoll)
          .copyWith(landmarkOffer: ['trade_post']);
      final actions = legalActions(s);
      expect(actions, contains(const RollDice()));
      // p0 holds 3 wood: bank trade is available pre-roll.
      expect(actions,
          contains(const BankTrade(give: Resource.wood, get: Resource.grain)));
      // trade_post costs 2 wood + 2 brick, affordable pre-roll too.
      expect(actions, contains(const BuyLandmark('trade_post')));
      // Board actions stay post-roll.
      expect(actions.whereType<ClaimHex>(), isEmpty);
      expect(actions.whereType<UpgradeHex>(), isEmpty);
    });

    test('bank trade and landmark purchase apply during awaitingRoll', () {
      final s = fixtureState(phase: Phase.awaitingRoll)
          .copyWith(landmarkOffer: ['trade_post']);
      final traded = apply(
          s, const BankTrade(give: Resource.wood, get: Resource.stone));
      expect(traded.state.phase, Phase.awaitingRoll);
      expect(traded.state.players[0].countOf(Resource.stone), 1);

      final bought = apply(s, const BuyLandmark('trade_post'));
      expect(bought.state.phase, Phase.awaitingRoll);
      expect(bought.state.players[0].landmarkIds, ['trade_post']);
    });

    test('main phase enumerates claims, upgrades, trades, end turn', () {
      final s = fixtureState(p0Resources: {
        Resource.wood: 3,
        Resource.brick: 1,
        Resource.grain: 2,
        Resource.stone: 1,
      });
      final actions = legalActions(s);
      expect(actions, contains(const EndTurn()));
      expect(actions, contains(const ClaimHex(Hex(1, -1))));
      expect(actions, contains(const UpgradeHex(Hex(0, 0))));
      expect(actions,
          contains(const BankTrade(give: Resource.wood, get: Resource.grain)));
      expect(actions, isNot(contains(const ClaimHex(Hex(1, 0)))));
      expect(actions, isNot(contains(const RollDice())));
    });
  });
}
