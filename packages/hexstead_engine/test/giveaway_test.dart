import 'package:hexstead_engine/hexstead_engine.dart';
import 'package:test/test.dart';

/// Two seats on a tiny board, parked in the main phase on the last seat so
/// one EndTurn wraps the round.
GameState fixture({
  int round = 3,
  int currentPlayerIndex = 1,
  Phase phase = Phase.main,
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
    currentPlayerIndex: currentPlayerIndex,
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
      const PlayerState(
        id: 0,
        name: 'You',
        isBot: false,
        resources: {Resource.wood: 3, Resource.brick: 3},
      ),
      const PlayerState(
        id: 1,
        name: 'Bot',
        isBot: true,
        resources: {Resource.grain: 2},
      ),
    ],
    landmarkOffer: const [],
  );
}

/// Walks a full round of play (roll, activate, end turn) for every seat,
/// collecting every event so a wrap's giveaway is visible.
(GameState, List<GameEvent>) playRound(GameState state) {
  var next = state;
  final events = <GameEvent>[];
  for (var seat = 0; seat < state.players.length; seat++) {
    for (final action in [
      const RollDice(),
      const ChooseActivation(ActivationMode.sum),
    ]) {
      final r = apply(next, action);
      next = r.state;
      events.addAll(r.events);
    }
    // A 7 parks in awaitingBandit; drop the bandit on a claimed hex.
    if (next.phase == Phase.awaitingBandit) {
      final r = apply(next, const PlaceBandit(Hex(0, 0)));
      next = r.state;
      events.addAll(r.events);
    }
    final r = apply(next, const EndTurn());
    next = r.state;
    events.addAll(r.events);
  }
  return (next, events);
}

void main() {
  group('resource giveaway', () {
    test('fires every 3 rounds', () {
      expect(Rules.giveawayInterval, 3);
    });

    test('wrapping into round 4 pays every player one resource', () {
      final s = fixture(round: 3);
      final before = [for (final p in s.players) p.totalResources];
      final r = apply(s, const EndTurn());
      expect(r.state.round, 4);
      final giveaways = r.events.whereType<ResourceGiveaway>().toList();
      expect(giveaways.length, 1);
      expect(giveaways.single.round, 4);
      expect(giveaways.single.grants.map((g) => g.playerId), [0, 1]);
      for (final grant in giveaways.single.grants) {
        expect(
          r.state.players[grant.playerId].totalResources,
          before[grant.playerId] + 1,
        );
        expect(
          r.state.players[grant.playerId].countOf(grant.resource),
          s.players[grant.playerId].countOf(grant.resource) + 1,
        );
      }
    });

    test('wrapping into rounds 2 and 3 pays nothing', () {
      for (final round in [1, 2]) {
        final r = apply(fixture(round: round), const EndTurn());
        expect(r.state.round, round + 1);
        expect(r.events.whereType<ResourceGiveaway>(), isEmpty,
            reason: 'round ${round + 1} is not a giveaway round');
        for (final p in r.state.players) {
          expect(p.totalResources,
              fixture(round: round).players[p.id].totalResources);
        }
      }
    });

    test('fires again entering round 7', () {
      final r = apply(fixture(round: 6), const EndTurn());
      expect(r.state.round, 7);
      final giveaway = r.events.whereType<ResourceGiveaway>().single;
      expect(giveaway.round, 7);
      expect(giveaway.grants.length, 2);
    });

    test('a played-out round grants exactly once on the wrap', () {
      final state = fixture(
          round: 3, currentPlayerIndex: 0, phase: Phase.awaitingRoll);
      final before = [for (final p in state.players) p.totalResources];
      final (next, events) = playRound(state);
      expect(next.round, 4);
      final giveaways = events.whereType<ResourceGiveaway>().toList();
      expect(giveaways.length, 1);
      // Production can also pay out, so only check the giveaway's own share.
      final produced = <int, int>{0: 0, 1: 0};
      for (final e in events.whereType<ResourcesProduced>()) {
        for (final g in e.grants) {
          produced[g.playerId] = produced[g.playerId]! + g.count;
        }
      }
      for (final p in next.players) {
        expect(p.totalResources, before[p.id] + produced[p.id]! + 1);
      }
    });
  });
}
