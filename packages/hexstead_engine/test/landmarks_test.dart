import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

GameState fixture({
  Phase phase = Phase.main,
  (int, int)? lastDice,
  Map<Resource, int>? p0Resources,
  List<String> p0Landmarks = const [],
  List<String> p1Landmarks = const [],
  List<String> p0Hand = const [],
  List<String> offer = const [],
}) {
  const tilesSpec = [
    (Hex(0, 0), TerrainType.forest, 8, 0, 1),
    (Hex(1, 0), TerrainType.field, 8, 1, 2),
    (Hex(0, 1), TerrainType.hill, 4, 0, 1),
    (Hex(1, -1), TerrainType.mountain, 10, 0, 1),
    (Hex(-1, 0), TerrainType.field, 6, null, 0),
  ];
  return GameState(
    seed: 1,
    rng: GameRng(1),
    round: 1,
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
        resources: p0Resources ?? {for (final r in Resource.values) r: 4},
        hand: p0Hand,
        landmarkIds: p0Landmarks,
      ),
      PlayerState(
        id: 1,
        name: 'Bot',
        isBot: true,
        resources: {Resource.grain: 2},
        landmarkIds: p1Landmarks,
      ),
    ],
    landmarkOffer: offer,
    lastDice: lastDice,
    diceHistory: [?lastDice],
  );
}

void main() {
  group('landmark catalog', () {
    test('has 12 landmarks with names, costs, and vp', () {
      expect(landmarkCatalog.length, 12);
      for (final lm in landmarkCatalog.values) {
        expect(lm.name, isNotEmpty);
        expect(lm.cost, isNotEmpty);
        expect(lm.vp, greaterThanOrEqualTo(1));
      }
    });
  });

  group('setup', () {
    test('newGame offers 4 landmarks from the pool', () {
      final s = GameState.newGame(seed: 4, players: [
        const PlayerSetup(name: 'a', isBot: true),
        const PlayerSetup(name: 'b', isBot: true),
      ]);
      expect(s.landmarkOffer.length, 4);
      expect(s.landmarkOffer.toSet().length, 4);
      for (final id in s.landmarkOffer) {
        expect(landmarkCatalog.containsKey(id), isTrue);
      }
    });
  });

  group('buying', () {
    test('pays the cost, removes from offer, adds vp to score', () {
      final s = fixture(offer: ['cathedral', 'granary']);
      final base = scoreFor(s, 0);
      final r = apply(s, const BuyLandmark('cathedral'));
      expect(r.state.players[0].landmarkIds, ['cathedral']);
      expect(r.state.landmarkOffer, ['granary']);
      expect(r.state.players[0].countOf(Resource.grain), 1);
      expect(r.state.players[0].countOf(Resource.stone), 1);
      expect(scoreFor(r.state, 0), base + 3);
      expect(r.events.whereType<LandmarkPurchased>().length, 1);
    });

    test('cannot buy what is not offered or not affordable', () {
      final s = fixture(offer: ['granary']);
      expect(() => apply(s, const BuyLandmark('cathedral')),
          throwsA(isA<IllegalActionException>()));
      final broke = fixture(offer: ['cathedral'], p0Resources: {});
      expect(() => apply(broke, const BuyLandmark('cathedral')),
          throwsA(isA<IllegalActionException>()));
    });

    test('first come first served: a bought landmark is gone', () {
      final s = fixture(offer: ['granary']);
      final r = apply(s, const BuyLandmark('granary'));
      expect(
        legalActions(r.state).whereType<BuyLandmark>(),
        isEmpty,
      );
    });
  });

  group('production effects', () {
    test('high_roller doubles production of tiles numbered 9-12', () {
      final s = fixture(
        phase: Phase.awaitingChoice,
        lastDice: (4, 6),
        p0Landmarks: ['high_roller'],
      );
      final r = apply(s, const ChooseActivation(ActivationMode.sum));
      // mountain#10 camp: 1 x 2 = 2 stone
      expect(r.state.players[0].countOf(Resource.stone), 6);
    });

    test('terrain landmarks add +1 when their terrain produces', () {
      final s = fixture(
        phase: Phase.awaitingChoice,
        lastDice: (4, 4),
        p0Landmarks: ['lumber_mill'],
      );
      final r = apply(s, const ChooseActivation(ActivationMode.sum));
      // forest#8 camp: level 1 + mill 1 = 2 wood (p0 had 4)
      expect(r.state.players[0].countOf(Resource.wood), 6);
      // p1's field#8 village unaffected by p0's mill: +2 grain
      expect(r.state.players[1].countOf(Resource.grain), 4);
    });

    test('market_hall grants 1 grain on your own roll', () {
      final s = fixture(phase: Phase.awaitingRoll, p0Landmarks: ['market_hall']);
      final r = apply(s, const RollDice());
      expect(r.state.players[0].countOf(Resource.grain), 5);
    });
  });

  group('economy effects', () {
    test('trade_post improves bank trade to 2:1', () {
      final s = fixture(
        p0Landmarks: ['trade_post'],
        p0Resources: {Resource.wood: 2},
      );
      final r =
          apply(s, const BankTrade(give: Resource.wood, get: Resource.stone));
      expect(r.state.players[0].countOf(Resource.wood), 0);
      expect(r.state.players[0].countOf(Resource.stone), 1);
    });

    test('cheap_claims drops the brick from claim cost', () {
      final s = fixture(
        p0Landmarks: ['cheap_claims'],
        p0Resources: {Resource.wood: 1},
      );
      final r = apply(s, const ClaimHex(Hex(-1, 0)));
      expect(r.state.tiles[const Hex(-1, 0)]!.ownerId, 0);
      expect(r.state.players[0].countOf(Resource.wood), 0);
    });
  });

  group('protection effects', () {
    test('bandit_ward tiles refuse the bandit', () {
      final s = fixture(phase: Phase.awaitingBandit, p0Landmarks: ['bandit_ward']);
      expect(() => apply(s, const PlaceBandit(Hex(0, 0))),
          throwsA(isA<IllegalActionException>()));
      // p1 tile still fine
      final ok = apply(s, const PlaceBandit(Hex(1, 0)));
      expect(ok.state.tiles[const Hex(1, 0)]!.hasBandit, isTrue);
      // brigand card also blocked
      final withCard = fixture(
          p0Hand: ['brigand'], p1Landmarks: ['bandit_ward']);
      expect(
          () => apply(withCard, const PlayCard('brigand', targetHex: Hex(1, 0))),
          throwsA(isA<IllegalActionException>()));
    });

    test('watchtower blocks cutpurse, tithe, and drought', () {
      final s = fixture(p0Hand: ['cutpurse'], p1Landmarks: ['watchtower']);
      expect(() => apply(s, const PlayCard('cutpurse', targetPlayer: 1)),
          throwsA(isA<IllegalActionException>()));

      final drought = fixture(p0Hand: ['drought'], p1Landmarks: ['watchtower']);
      expect(
          () => apply(drought, const PlayCard('drought', targetHex: Hex(1, 0))),
          throwsA(isA<IllegalActionException>()));

      final tithe = fixture(p0Hand: ['tithe'], p1Landmarks: ['watchtower']);
      final r = apply(tithe, const PlayCard('tithe'));
      expect(r.state.players[1].totalResources, 2); // untouched
    });
  });

  group('scoring effects', () {
    test('keep grants +1 per village at scoring time', () {
      final s = fixture(p0Landmarks: ['keep']);
      // p0 has no villages: keep vp only (1)
      final withVillage = s.copyWith(tiles: {
        ...s.tiles,
        const Hex(0, 0): s.tiles[const Hex(0, 0)]!.copyWith(level: 2),
      });
      expect(
        scoreFor(withVillage, 0) - scoreFor(s, 0),
        greaterThanOrEqualTo(2), // village region bonus + keep bonus
      );
      expect(landmarkScore(withVillage, 0), 2); // keep vp 1 + 1 village
    });
  });
}
