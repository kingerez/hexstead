import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// Same fixture as reducer_core_test: p0 forest#8 camp (0,0), hill#4 camp
/// (0,1); p1 field#8 village (1,0); unowned mountain#6 (1,-1).
GameState fixture({
  Phase phase = Phase.main,
  (int, int)? lastDice,
  Map<Resource, int>? p0Resources,
  List<String> p0Hand = const [],
  List<String> p1Hand = const [],
  int round = 1,
}) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (Hex(1, 0), TerrainType.field, 8, 1, 2),
    (Hex(0, 1), TerrainType.hill, 4, 0, 1),
    (Hex(1, -1), TerrainType.mountain, 6, null, 0),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: round,
    roundCap: 15,
    targetVp: 99,
    currentPlayerIndex: 0,
    phase: phase,
    tiles: {
      for (final (coord, terrain, number, owner, level) in tilesSpec)
        coord: Tile(
          coord: coord,
          terrain: terrain,
          number: number,
          ownerId: owner,
          level: level,
        ),
    },
    players: [
      PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: p0Resources ?? {Resource.wood: 3, Resource.brick: 3},
        hand: p0Hand,
      ),
      PlayerState(
          id: 1,
          name: 'Bot',
          isBot: true,
          resources: {Resource.grain: 2},
          hand: p1Hand),
    ],
    landmarkOffer: const [],
    lastDice: lastDice,
    diceHistory: [?lastDice],
  );
}

void main() {
  group('card catalog', () {
    test('has 10 distinct cards with names and descriptions', () {
      expect(cardCatalog.length, 10);
      expect(cardCatalog.keys.toSet().length, 10);
      for (final card in cardCatalog.values) {
        expect(card.name, isNotEmpty);
        expect(card.description, isNotEmpty);
      }
    });
  });

  group('dealing', () {
    test('newGame deals 3 cards to every player from the shared deck', () {
      final s = GameState.newGame(seed: 3, players: [
        const PlayerSetup(name: 'a', isBot: true),
        const PlayerSetup(name: 'b', isBot: true),
        const PlayerSetup(name: 'c', isBot: true),
        const PlayerSetup(name: 'd', isBot: true),
      ]);
      for (final p in s.players) {
        expect(p.hand.length, 3);
        for (final id in p.hand) {
          expect(cardCatalog.containsKey(id), isTrue);
        }
      }
      // Deck has 2 copies of each card: no card appears 3+ times overall.
      final all = s.players.expand((p) => p.hand).toList();
      for (final id in cardCatalog.keys) {
        expect(all.where((c) => c == id).length, lessThanOrEqualTo(2));
      }
    });
  });

  group('dice cards (awaitingChoice)', () {
    test('second_chance rerolls and consumes the card', () {
      final s = fixture(
        phase: Phase.awaitingChoice,
        lastDice: (3, 4),
        p0Hand: ['second_chance'],
      );
      final r = apply(s, const PlayCard('second_chance'));
      expect(r.state.phase, Phase.awaitingChoice);
      expect(r.state.lastDice, isNotNull);
      expect(r.state.players[0].hand, isEmpty);
      expect(r.state.players[0].cardPlayedThisTurn, isTrue);
      expect(r.state.diceHistory.length, 2); // original + reroll
      expect(r.events.whereType<CardPlayed>().length, 1);
      expect(r.events.whereType<DiceRolled>().length, 1);
    });

    test('omen shifts one die by +/-1 within 1..6', () {
      final s = fixture(
        phase: Phase.awaitingChoice,
        lastDice: (3, 4),
        p0Hand: ['omen'],
      );
      final r = apply(s, const PlayCard('omen', dieIndex: 0, delta: 1));
      expect(r.state.lastDice, (4, 4));
      expect(r.state.phase, Phase.awaitingChoice);

      expect(
        () => apply(fixture(phase: Phase.awaitingChoice, lastDice: (6, 4), p0Hand: ['omen']),
            const PlayCard('omen', dieIndex: 0, delta: 1)),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('dice cards are illegal during main phase', () {
      final s = fixture(p0Hand: ['second_chance']);
      expect(() => apply(s, const PlayCard('second_chance')),
          throwsA(isA<IllegalActionException>()));
    });
  });

  group('main-phase cards', () {
    test('drought blocks a tile this round and next', () {
      final s = fixture(p0Hand: ['drought'], round: 2);
      final r = apply(s, const PlayCard('drought', targetHex: Hex(1, 0)));
      final tile = r.state.tiles[const Hex(1, 0)]!;
      expect(tile.blockedUntilRound, 4);

      // production honors the block: round 2 and 3 nothing, round 4 produces
      var blocked = r.state.copyWith(
          phase: Phase.awaitingChoice, lastDice: () => (4, 4));
      var produced =
          apply(blocked, const ChooseActivation(ActivationMode.sum));
      expect(produced.state.players[1].resources[Resource.grain], 2);

      var later = r.state.copyWith(
          round: 4, phase: Phase.awaitingChoice, lastDice: () => (4, 4));
      produced = apply(later, const ChooseActivation(ActivationMode.sum));
      expect(produced.state.players[1].resources[Resource.grain], 4);
    });

    test('charter claims any unowned tile at normal cost, no adjacency', () {
      // (-2,0) is far from p0 territory
      final s = GameState.newGame(seed: 6, players: [
        const PlayerSetup(name: 'a', isBot: false),
        const PlayerSetup(name: 'b', isBot: true),
      ]);
      final far = s.tiles.values.firstWhere((t) =>
          t.ownerId == null &&
          s.tiles.values
              .where((o) => o.ownerId == 0)
              .every((o) => o.coord.distanceTo(t.coord) >= 2));
      var ready = s.copyWith(phase: Phase.main);
      ready = ready.withPlayer(
          0,
          (p) => p.copyWith(
              hand: ['charter'],
              resources: {Resource.wood: 1, Resource.brick: 1}));
      final r = apply(ready, PlayCard('charter', targetHex: far.coord));
      expect(r.state.tiles[far.coord]!.ownerId, 0);
      expect(r.state.players[0].countOf(Resource.wood), 0);
    });

    test('cutpurse steals one random resource from the target', () {
      final s = fixture(p0Hand: ['cutpurse']);
      final r = apply(s, const PlayCard('cutpurse', targetPlayer: 1));
      expect(r.state.players[1].totalResources, 1);
      expect(r.state.players[0].totalResources, 7);
      expect(r.events.whereType<ResourceStolen>().length, 1);
    });

    test('bounty grants 2 of a chosen resource', () {
      final s = fixture(p0Hand: ['bounty'], p0Resources: {});
      final r = apply(s, const PlayCard('bounty', resource: Resource.stone));
      expect(r.state.players[0].countOf(Resource.stone), 2);
    });

    test('banish clears a bandit from your own tile for free', () {
      var s = fixture(p0Hand: ['banish']);
      s = s.copyWith(tiles: {
        ...s.tiles,
        const Hex(0, 0): s.tiles[const Hex(0, 0)]!.copyWith(hasBandit: true),
      });
      final r = apply(s, const PlayCard('banish', targetHex: Hex(0, 0)));
      expect(r.state.tiles[const Hex(0, 0)]!.hasBandit, isFalse);
      expect(r.state.players[0].totalResources, 6); // nothing spent
    });

    test('brigand places the bandit on any claimed tile', () {
      final s = fixture(p0Hand: ['brigand']);
      final r = apply(s, const PlayCard('brigand', targetHex: Hex(1, 0)));
      expect(r.state.tiles[const Hex(1, 0)]!.hasBandit, isTrue);
    });

    test('harvest makes your hot tiles (5,6,8,9) produce immediately', () {
      final s = fixture(p0Hand: ['harvest']);
      final r = apply(s, const PlayCard('harvest'));
      // forest#8 camp produces 1 wood; hill#4 does not (4 is not hot)
      expect(r.state.players[0].countOf(Resource.wood), 4);
      expect(r.state.players[0].countOf(Resource.brick), 3);
    });

    test('tithe takes one random resource from each opponent', () {
      final s = fixture(p0Hand: ['tithe']);
      final r = apply(s, const PlayCard('tithe'));
      expect(r.state.players[1].totalResources, 1);
      expect(r.state.players[0].totalResources, 7);
    });
  });

  group('card rules', () {
    test('only one card per turn', () {
      final s = fixture(p0Hand: ['bounty', 'harvest']);
      final r = apply(s, const PlayCard('bounty', resource: Resource.wood));
      expect(
        () => apply(r.state, const PlayCard('harvest')),
        throwsA(isA<IllegalActionException>()),
      );
    });

    test('cannot play a card you do not hold', () {
      final s = fixture(p0Hand: ['bounty']);
      expect(() => apply(s, const PlayCard('harvest')),
          throwsA(isA<IllegalActionException>()));
    });

    test('legalActions enumerates playable cards with targets', () {
      final s = fixture(p0Hand: ['brigand', 'bounty']);
      final actions = legalActions(s);
      expect(actions,
          contains(const PlayCard('brigand', targetHex: Hex(0, 0))));
      expect(actions,
          contains(const PlayCard('brigand', targetHex: Hex(1, 0))));
      expect(actions,
          contains(const PlayCard('bounty', resource: Resource.stone)));
      // dice cards not offered in main phase
      final s2 = fixture(
          phase: Phase.awaitingChoice,
          lastDice: (2, 5),
          p0Hand: ['second_chance', 'bounty']);
      final choiceActions = legalActions(s2);
      expect(choiceActions, contains(const PlayCard('second_chance')));
      expect(
          choiceActions.whereType<PlayCard>().where((a) => a.cardId == 'bounty'),
          isEmpty);
    });
  });
}
